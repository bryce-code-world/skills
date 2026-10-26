"""Edit and re-render an existing human-readable Remotion project, without overwriting history."""
from __future__ import annotations

import json
import os
import re
import shutil
from pathlib import Path
import tempfile

from project_layout import (modern,project_root,MEDIA_DIR,parse_storyboard,
                            apply_storyboard,archive_video,story_file,_resolve_asset)
from quick_video import audio_duration,ensure_tools,run_cmd,local_probe,parse_srt,check_subtitle_readability,audience_risk_notes,check_named_product


def review_subtitle_edits(d:Path, scenes:list[dict], duration:float, audio_duration_seconds:float|None=None)->dict:
    """Read actual user SRT, not a stale copy of the engine's cue list."""
    timeline_file=d/"subtitles.json"
    if not timeline_file.is_file():
        return {"modified":False,"plan":None}
    plan=json.loads(timeline_file.read_text(encoding="utf8"))
    source=project_root(d)/"01-文案与分镜"/"字幕文件.srt"
    if not source.is_file() and plan.get("cues"):
        raise ValueError("中文 SRT 字幕已丢失，禁止悄悄沿用旧时间轴")
    cues=parse_srt(source) if source.is_file() else []
    check_subtitle_readability(cues)
    if plan.get("required") and not cues:
        raise ValueError("本视频要求同步字幕，缺少实际 SRT 时间轴")
    if cues:
        from speech_plan import text_key
        narration="".join(s.get("voiceover","") for s in scenes)
        if text_key("".join(c["text"] for c in cues))!=text_key(narration):
            raise ValueError("字幕文字与正式口播不一致，需同步改稿与配音")
        if cues[-1]["end"]>duration+.04 or (audio_duration_seconds is not None and cues[-1]["end"]>audio_duration_seconds+.04):
            raise ValueError("字幕越过视频或连续配音时长，请调整镜头和字幕时间")
    original=plan.get("cues",[])
    # SRT stores integer milliseconds; sub-millisecond rounding is not a human edit.
    same=(len(cues)==len(original) and all(
        new["text"]==old.get("text") and
        all(round(new[key]*1000)==round(old[key]*1000) for key in ("start","end"))
        for new,old in zip(cues,original)))
    changed=not same
    return {"modified":changed,"plan":{**plan,"cues":cues if changed else original,
        "timing_source":"manually_adjusted_needs_listening" if changed else plan.get("timing_source","none")}}


def validate_rebuild_subject(script:dict,scenes:list[dict])->dict:
    editorial=script.get("editorial_intent") or {}
    return check_named_product({
        "video_purpose":editorial.get("video_purpose","general"),
        "subject_name":editorial.get("subject_name"),
        "subject_spoken":editorial.get("spoken_name"),
    },scenes)


def rebuild(args,studio):
    root,_=studio.workspace(args.root)
    d=studio.paths(root,args.id)
    if not modern(d) or not (d/"src"/"index.tsx").is_file() or not (d/"shotlist.json").is_file():
        raise ValueError("仅支持新版可编辑 Remotion 项目，旧项目不迁移或改写")
    scenes=parse_storyboard(d)
    source_script=studio.load(d/"script.json")
    subject=validate_rebuild_subject(source_script,scenes)
    timeline=studio.load(d/"shotlist.json")
    old_master=timeline.get("narration_audio")
    master_tag=re.search(r"^- 连续旁白：(.*)$",story_file(d).read_text(encoding="utf8"),re.M)
    new_master=_resolve_asset(d,master_tag.group(1),"audio") if master_tag else old_master
    old_words="".join(x.get("voiceover","") for x in timeline["shots"])
    new_words="".join(x.get("voiceover","") for x in scenes)
    if old_master and old_words!=new_words and new_master==old_master:
        raise ValueError("完整口播文字已改变但仍引用旧连续配音；请只重新生成受影响的语音段并更新连续旁白文件")
    if old_master and new_master is None and new_words.strip():
        raise ValueError("完整口播仍有文字，但连续旁白文件被清空")
    if len(scenes)!=len(timeline["shots"]):
        raise ValueError("更改镜头数量须同步 React 动画工程")
    for i,(old,scene) in enumerate(zip(timeline["shots"],scenes),1):
        if (old.get("voiceover","")!=scene["voiceover"] and old.get("audio")==scene["audio"] and scene["audio"]):
            raise ValueError(f"镜头 {i} 的口播已改，但仍引用旧配音；请重新生成该段音频并修改中文分镜的配音路径")
    ffprobe=studio.load_ffmpeg_bin(root,"ffprobe")
    master_length=audio_duration(project_root(d)/MEDIA_DIR/new_master,ffprobe) if new_master else None
    total=sum(s["seconds"] for s in scenes)
    if master_length and master_length>total+.02:
        raise ValueError("连续旁白超过新镜头总时长，不能截掉语音尾部")
    if new_master and any(s["audio"] for s in scenes):
        raise ValueError("连续主音轨与逐镜头音频不能同时启用")
    cues=review_subtitle_edits(d,scenes,total,master_length)
    for i,shot in enumerate(scenes,1):
        if shot.get("video"):
            source=project_root(d)/MEDIA_DIR/shot["video"]
            if audio_duration(source,ffprobe,kind="video")<shot["seconds"]-.05:
                raise ValueError(f"镜头 {i} 视频素材太短，请调整镜头时长或替换素材")
        if shot["audio"]:
            source=project_root(d)/MEDIA_DIR/shot["audio"]
            seconds=audio_duration(source,studio.load_ffmpeg_bin(root,"ffprobe"))
            if seconds>shot["seconds"]-.15:
                raise ValueError(f"镜头 {i} 配音 {seconds:.2f}s 超过时槽 {shot['seconds']:.2f}s，拒绝截尾音")
    npm,npx=ensure_tools()
    if args.dry_run:
        print("REBUILD_PLAN "+json.dumps({"project":str(project_root(d)),"shots":len(scenes),
            "seconds":sum(s["seconds"] for s in scenes),"old_mp4":studio.video_path(d).exists()},ensure_ascii=False))
        return
    lock=d/".rebuild.lock"
    try:
        fd=os.open(lock,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
    except FileExistsError:
        raise ValueError("有另一个渲染进程正在处理本项目")
    os.close(fd)
    try:
        change=apply_storyboard(d)
        if cues["plan"] and cues["modified"]:
            history=d/"history"/"人工调整字幕"
            history.mkdir(parents=True,exist_ok=True)
            original=d/"subtitles.json"
            backup=history/(str(__import__("time").time_ns())+"-subtitles.json")
            shutil.copy2(original,backup)
            studio.save(original,cues["plan"])
        if not (d/"node_modules").is_dir():
            run_cmd([npm,"ci","--ignore-scripts","--no-audit","--no-fund"],d,240)
        with tempfile.TemporaryDirectory(prefix=".重新渲染-",dir=project_root(d)) as folder:
            candidate=Path(folder)/"新成片.mp4"
            run_cmd([npx,"--no-install","remotion","render","src/index.tsx","QuickVideo",
                     str(candidate),"--codec=h264","--crf=23","--concurrency=4","--log=error"],d,540)
            if not candidate.is_file() or candidate.stat().st_size<1024:
                raise RuntimeError("未生成有效 MP4")
            info=json.loads(run_cmd([local_probe(d),"-v","error","-show_streams",
                         "-show_format","-of","json",str(candidate)],d,30))
            video=next((s for s in info["streams"] if s.get("codec_type")=="video"),None)
            audio=next((s for s in info["streams"] if s.get("codec_type")=="audio"),None)
            if not video or (video["width"],video["height"])!=(timeline["width"],timeline["height"]):
                raise RuntimeError("重渲染后视频画幅错误")
            if (new_master or any(s["audio"] for s in scenes)) and audio is None:
                raise RuntimeError("重渲染缺少预期配音")
            expected=sum(round(s["seconds"]*timeline["fps"]) for s in scenes)/timeline["fps"]
            if abs(float(info["format"]["duration"])-expected)>.15:
                raise RuntimeError("实际视频与分镜时长不一致")
            cover=project_root(d)/"视频封面.png"
            candidate_cover=Path(folder)/"新封面.png"
            frame=min(max(0,sum(round(s["seconds"]*timeline["fps"]) for s in scenes)-1),35)
            run_cmd([npx,"--no-install","remotion","still","src/index.tsx","QuickVideo",
                     str(candidate_cover),f"--frame={frame}","--log=error"],d,120)
            old=archive_video(d)
            if cover.is_file():
                from datetime import datetime, timezone
                previous=project_root(d)/"03-修改与版本"/("旧封面-"+datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")+".png")
                shutil.copy2(cover,previous)
            os.replace(candidate,studio.video_path(d))
            os.replace(candidate_cover,cover)
        subtitlefile=d/"subtitles.json"
        srt=project_root(d)/"01-文案与分镜"/"字幕文件.srt"
        ffmpeg=studio.load_ffmpeg_bin(root,"ffmpeg")
        ffprobe=studio.load_ffmpeg_bin(root,"ffprobe")
        audio_check={"result":"NOT_RUN","note":"尚未进行真实音频检测，不代表试听通过"}
        if ffmpeg and ffprobe and (new_master or any(s["audio"] for s in scenes)):
            try:audio_check=studio.inspect_video(ffmpeg,ffprobe,studio.video_path(d),studio.load(d/"script.json")["shots"])
            except (RuntimeError,ValueError) as error:audio_check={"result":"BLOCK","issues":[str(error)]}
        old_record=studio.load(d/"video"/"render.json") if (d/"video"/"render.json").is_file() else {}
        current_audio_sha=studio.filehash(project_root(d)/MEDIA_DIR/new_master) if new_master else None
        same_voice=(current_audio_sha == old_record.get("narration_audio_sha256"))
        voice_source=old_record.get("voice_source") if same_voice else None
        if not isinstance(voice_source,dict):
            voice_source={"service":"unknown","voice":"unknown",
                          "usage_note":"配音来源未记录或音频已替换，需重新核对",
                          "verification":"not_verified"}
        studio.save(d/"video"/"render.json",{
            "technical_audio_check":audio_check,
            "voice_source":{**voice_source,"verification":"not_verified"},
            "claim_warnings":audience_risk_notes(scenes),
            "evidence_status":"agent_review_required",
            "engine":"remotion","render_status":"technical_only",
            "video_purpose":subject["video_purpose"],
            "subject_name":subject["subject_name"],
            "visual_style":studio.load(d/"shotlist.json").get("visual_style","product"),
            "visual_modes":[item.get("visual_mode","standard")
                            for item in studio.load(d/"shotlist.json")["shots"]],
            "subtitles_sha256":studio.filehash(subtitlefile) if subtitlefile.is_file() else None,
            "subtitle_file_sha256":studio.filehash(srt) if srt.is_file() else None,
            "subtitles_status":"timed" if cues["plan"] and cues["plan"].get("cues") else "not_provided",
            "subtitle_timing_source":cues["plan"].get("timing_source") if cues["plan"] else "none",
            "narration_audio_sha256":current_audio_sha,
            "video_sha256":studio.filehash(studio.video_path(d)),
            "script_sha256":studio.filehash(d/"script.json"),
            "created_at_utc":studio.now(),"duration_seconds":float(info["format"]["duration"]),
            "provenance":studio.provenance(studio.load(d/"content.json")),
            "archive_previous_video":str(old) if old else None})
        with (project_root(d)/"03-修改与版本"/"修改记录.md").open("a",encoding="utf8") as f:
            f.write(f"\n- {studio.now()}：同步分镜并重渲染，旧成片归档：{old.name if old else '无'}；旧审核不可沿用。\n")
        print("VIDEO_REBUILT "+json.dumps({"mp4":str(studio.video_path(d)),
             "archive":str(old) if old else None,"storyboard_changed":change["changed"],
             "review_status":"NOT_REVIEWED"},ensure_ascii=False))
    finally:
        lock.unlink(missing_ok=True)
