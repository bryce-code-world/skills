"""Edit and re-render an existing human-readable Remotion project, without overwriting history."""
from __future__ import annotations

import json
import os
import shutil
from pathlib import Path
import tempfile

from project_layout import (modern,project_root,MEDIA_DIR,parse_storyboard,
                            apply_storyboard,archive_video)
from quick_video import audio_duration,ensure_tools,run_cmd,local_probe


def rebuild(args,studio):
    root,_=studio.workspace(args.root)
    d=studio.paths(root,args.id)
    if not modern(d) or not (d/"src"/"index.tsx").is_file() or not (d/"shotlist.json").is_file():
        raise ValueError("仅支持新版可编辑 Remotion 项目，旧项目不迁移或改写")
    scenes=parse_storyboard(d)
    timeline=studio.load(d/"shotlist.json")
    if len(scenes)!=len(timeline["shots"]):
        raise ValueError("更改镜头数量须同步 React 动画工程")
    for i,(old,scene) in enumerate(zip(timeline["shots"],scenes),1):
        if (old.get("voiceover","")!=scene["voiceover"] and old.get("audio")==scene["audio"] and scene["audio"]):
            raise ValueError(f"镜头 {i} 的口播已改，但仍引用旧配音；请重新生成该段音频并修改中文分镜的配音路径")
    for i,shot in enumerate(scenes,1):
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
            if any(s["audio"] for s in scenes) and audio is None:
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
        studio.save(d/"video"/"render.json",{
            "engine":"remotion","render_status":"technical_only",
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
