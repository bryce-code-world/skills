"""Small, project-local Remotion route with a self-contained starter.

Agent authors the short shot list; this module only validates local materials,
copies the supplied media, and renders an editable technical preview. It never
creates script/video PASS records or grants any publishing permission.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import shutil
import subprocess
import wave


IMAGE_FORMATS = {".png", ".jpg", ".jpeg", ".webp", ".svg"}
AUDIO_FORMATS = {".wav", ".mp3", ".m4a"}
VIDEO_FORMATS = {".mp4", ".webm"}
SUBTITLE_SOURCES = {"tts_word_boundary", "verified_sentence_timing", "manually_reviewed"}
SHOTS_LIMIT = 12
MEDIA_LIMIT = 80 * 1024 * 1024


def media_path(value, spec_path: Path, formats: set[str], name: str) -> Path:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{name} 素材路径必须是非空字符串")
    source = Path(value).expanduser()
    if not source.is_absolute():
        source = spec_path.parent / source
    source = source.resolve()
    if source.suffix.lower() not in formats or not source.is_file():
        raise ValueError(f"{name} 素材不存在或格式不支持：{value}")
    if source.stat().st_size > MEDIA_LIMIT:
        raise ValueError(f"{name} 素材超过 80MB：{value}")
    return source


def valid_text(value, label: str, limit: int, *, required=True) -> str:
    if not isinstance(value, str) or (required and not value.strip()) or len(value) > limit:
        raise ValueError(f"{label} 需要有效文本（最多 {limit} 字符）")
    return value.strip()


def audio_duration(source: Path, ffprobe: str | None, kind: str = 'audio') -> float:
    if source.suffix.lower() == ".wav":
        try:
            with wave.open(str(source), "rb") as audio:
                duration = audio.getnframes() / audio.getframerate()
        except (wave.Error, EOFError, ZeroDivisionError) as exc:
            raise ValueError(f"配音 WAV 格式损坏：{source.name}") from exc
    else:
        if not ffprobe:
            raise ValueError("检查 MP3/M4A 配音时长需要已有 ffprobe；可使用有效 PCM WAV，或补齐 FFmpeg 后重试")
        try:
            info = json.loads(run_cmd([ffprobe, "-v", "error", "-show_streams", "-show_format",
                                       "-of", "json", str(source)], source.parent, 30))
            if not any(s.get("codec_type") == kind for s in info.get("streams", [])):
                raise ValueError(f"文件没有{kind}流")
            duration = float(info["format"]["duration"])
        except (KeyError, TypeError, ValueError, RuntimeError) as exc:
            raise ValueError(f"无法验证配音时长：{source.name}（{exc}）") from exc
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError(f"配音时长无效：{source.name}")
    return duration


def parse_srt(source: Path) -> list[dict]:
    """Read human-edited subtitles for Remotion: SRT is the only user edit source."""
    import re
    data=source.read_text(encoding="utf-8-sig").replace("\r\n","\n").strip()
    if not data:
        return []
    items=[]
    for i,paragraph in enumerate(re.split(r"\n\s*\n",data),1):
        lines=paragraph.splitlines()
        if len(lines)<3 or lines[0].strip()!=str(i):
            raise ValueError(f"字幕文件第 {i} 条结构或编号有误")
        pattern=r"^(\d{2}):([0-5]\d):([0-5]\d),(\d{3}) --> (\d{2}):([0-5]\d):([0-5]\d),(\d{3})$"
        m=re.fullmatch(pattern,lines[1].strip())
        if not m:
            raise ValueError(f"字幕文件第 {i} 条时间格式错误")
        h1,m1,s1,ms1,h2,m2,s2,ms2=map(int,m.groups())
        start=h1*3600+m1*60+s1+ms1/1000
        end=h2*3600+m2*60+s2+ms2/1000
        if start < (items[-1]["end"]-.001 if items else 0) or end<=start:
            raise ValueError(f"字幕第 {i} 条发生重叠或时长无效")
        text="".join(line.strip() for line in lines[2:])
        if not text:
            raise ValueError(f"字幕第 {i} 条缺少文字")
        items.append({"start":round(start,4),"end":round(end,4),"text":text})
    return items


def checked_spec(raw: dict, file: Path, ffprobe: str | None = None) -> dict:
    if not isinstance(raw, dict):
        raise ValueError("快速分镜需要 JSON 对象")
    title = valid_text(raw.get("title"), "title", 120)
    audience = valid_text(raw.get("audience", ""), "audience", 200, required=False)
    value = valid_text(raw.get("primary_value"), "primary_value", 300)
    aspect = raw.get("aspect", "9:16")
    if aspect not in ("9:16", "16:9"):
        raise ValueError("aspect 只支持 9:16 或 16:9")
    shots = raw.get("shots")
    if not isinstance(shots, list) or not 1 <= len(shots) <= SHOTS_LIMIT:
        raise ValueError("shots 必须有 1～12 段")
    prepared = []
    master = media_path(raw["narration_audio"],file,AUDIO_FORMATS,"完整连续配音") if raw.get("narration_audio") else None
    if master and any(s.get("audio") for s in shots if isinstance(s,dict)):
        raise ValueError("连续主音轨与逐镜头配音不可同时启用")
    for i, shot in enumerate(shots, 1):
        if not isinstance(shot, dict):
            raise ValueError(f"第 {i} 段不是对象")
        seconds = shot.get("seconds")
        if isinstance(seconds, bool) or not isinstance(seconds, (float, int)) or not 2 <= seconds <= 20:
            raise ValueError(f"第 {i} 段 seconds 必须在 2～20 秒之间")
        caption = valid_text(shot.get("caption", ""), f"第 {i} 段 caption", 60, required=False)
        line = {
            "title": valid_text(shot.get("title"), f"第 {i} 段 title", 60),
            "caption": caption,
            "voiceover": valid_text(shot.get("voiceover", ""), f"第 {i} 段 voiceover", 300, required=False),
            "seconds": float(seconds),
            "frames": round(seconds * 30),
            "image": None,
            "audio": None,
        }
        if shot.get("image") and shot.get("video"):
            raise ValueError(f"第 {i} 段不能同时指定图片和视频素材")
        if shot.get("image"):
            line["image"] = media_path(shot["image"], file, IMAGE_FORMATS, f"第 {i} 段图片")
        line["video"] = None
        if shot.get("video"):
            line["video"] = media_path(shot["video"],file,VIDEO_FORMATS,f"第 {i} 段视频")
            if audio_duration(line["video"],ffprobe,kind="video") < line["frames"]/30 - .05:
                raise ValueError(f"第 {i} 段视频素材短于镜头；请延长素材或缩短镜头")
        if shot.get("audio"):
            line["audio"] = media_path(shot["audio"], file, AUDIO_FORMATS, f"第 {i} 段配音")
            duration = audio_duration(line["audio"], ffprobe)
            if duration > line["frames"] / 30 - 0.15:
                raise ValueError(f"第 {i} 段配音过长，需保留 0.15 秒余量：{duration:.2f}s / {seconds}s")
        line["voice_missing"] = bool(line["voiceover"] and not line["audio"])
        prepared.append(line)
    total=sum(s["frames"] for s in prepared)/30
    if total > 180:
        raise ValueError("总时长不能超过 180 秒；请使用完整制作模式")
    master_length=audio_duration(master,ffprobe) if master else None
    if master and master_length > total + .02:
        raise ValueError(f"连续配音 {master_length:.2f}s 超过画面总时长 {total:.2f}s，禁止硬裁切")
    cues=raw.get("subtitles",[])
    required=raw.get("subtitles_required",False)
    if not isinstance(required,bool):
        raise ValueError("subtitles_required 必须是布尔值")
    if not isinstance(cues,list):
        raise ValueError("字幕必须是带时间戳的句级或词组列表")
    if required and not cues:
        raise ValueError("用户要求同步字幕，但缺少真实字幕时间轴；固定画面 caption 不能冒充字幕")
    source=raw.get("subtitle_timing_source")
    if cues and source not in SUBTITLE_SOURCES:
        raise ValueError("字幕需要可追溯的时间来源（tts_word_boundary / verified_sentence_timing / manually_reviewed）")
    if cues and not (master or any(s["audio"] for s in prepared)):
        raise ValueError("没有实际配音文件，不能声称字幕与口播同步")
    normalized=[]
    preceding=0.
    import math
    for idx,cue in enumerate(cues,1):
        if not isinstance(cue,dict):
            raise ValueError(f"字幕 {idx} 须为时间与文本对象")
        start,end=cue.get("start"),cue.get("end")
        if (not isinstance(start,(int,float)) or isinstance(start,bool) or not math.isfinite(start)
                or not isinstance(end,(int,float)) or isinstance(end,bool) or not math.isfinite(end)
                or start < preceding-.001 or end <= start or end > total+.04 or
                (master_length is not None and end > master_length+.04)):
            raise ValueError(f"字幕 {idx} 时间越界或重叠")
        text=valid_text(cue.get("text"),f"字幕 {idx}",85)
        normalized.append({"start":round(float(start),4),"end":round(float(end),4),"text":text})
        preceding=float(end)
    if normalized:
        from speech_plan import text_key
        spoken="".join(x["voiceover"] for x in prepared if x["voiceover"])
        if text_key("".join(c["text"] for c in normalized)) != text_key(spoken):
            raise ValueError("字幕与正式口播不一致，禁止以静态提示文字冒充同步字幕")
    return {"title":title,"audience":audience,"primary_value":value,
            "aspect":aspect,"shots":prepared,"narration_audio":master,
            "subtitles":normalized,"subtitles_required":required,
            "subtitle_timing_source":source if normalized else "none"}


def provider_root(raw: str | None) -> Path | None:
    if not raw:
        return None
    root = Path(raw).expanduser().resolve()
    required = ["SKILL.md", "LICENSE", "template/package.json", "template/package-lock.json",
                "template/tsconfig.json", "template/remotion.config.ts"]
    if not all((root / f).is_file() for f in required):
        raise ValueError(f"未找到可用的 video-shotcraft（不会自动安装或覆盖）：{root}")
    return root


def run_cmd(args: list[str], directory: Path, timeout: int):
    try:
        call = subprocess.run(args, cwd=directory, capture_output=True, text=True,
                              encoding="utf8", errors="replace", timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"命令超时：{Path(args[0]).name}") from exc
    if call.returncode:
        raise RuntimeError(f"{Path(args[0]).name} 失败（exit={call.returncode}）：{(call.stderr or call.stdout)[-1400:]}")
    return call.stdout


def ensure_tools():
    node = shutil.which("node")
    npm = shutil.which("npm")
    npx = shutil.which("npx")
    if not node or not npm or not npx:
        raise ValueError("Remotion 快速创作需要已安装 Node.js/npm；不会自动修改 PATH 或安装未知组件")
    try:
        major = int(run_cmd([node, "--version"], Path.cwd(), 15).strip().lstrip("v").split(".")[0])
    except (ValueError, RuntimeError) as exc:
        raise ValueError("无法确认 Node.js 版本") from exc
    if major < 18:
        raise ValueError("Remotion 快速创作需要 Node.js 18 或更新版本")
    run_cmd([npm, "--version"], Path.cwd(), 15)
    return npm, npx


def local_probe(project: Path):
    system = shutil.which("ffprobe")
    if system:
        return system
    # Remotion bundles FFprobe in its platform-specific native compositor.
    modules = project / "node_modules" / "@remotion"
    for native in modules.glob("compositor-*"):
        for filename in ("ffprobe.exe", "ffprobe"):
            probe = native / filename
            if probe.is_file():
                return str(probe)
    raise RuntimeError("无法校验 MP4：Remotion 原生 FFprobe 未安装")


def run_quick(args, studio):
    root, knowledge = studio.workspace(args.root)
    # Protect the persisted output directory, including its separation from tools/knowledge.
    from workspace_paths import output_directory
    output = output_directory(root, studio.load(root / "config" / "workspace.json"))
    if not (knowledge / "review-rules.md").is_file():
        raise ValueError("工作区缺少 review-rules.md，请修复已有知识库配置后重试")
    spec_file = Path(args.spec).expanduser().resolve()
    if not spec_file.is_file():
        raise ValueError(f"缺少快速分镜 JSON：{spec_file}")
    spec = checked_spec(studio.load(spec_file), spec_file, studio.load_ffmpeg_bin(root, "ffprobe"))
    upstream = provider_root(args.shotcraft_dir)
    source = Path(__file__).resolve().parents[1] / "assets" / "quick-remotion"
    template = upstream / "template" if upstream else source
    for path in [source / "index.tsx", source / "Quick.tsx"] + [
        template / name for name in ("package.json", "package-lock.json", "tsconfig.json", "remotion.config.ts")
    ]:
        if not path.is_file():
            raise ValueError(f"快速视频模板不完整，请更新核心文件：{path}")
    creator = argparse.Namespace(
        id=None, topic=args.topic, agent=args.agent, model=args.model, run_id=args.run_id,
        parent_id=None, publish_target=None, title=spec["title"], task_ref=None, root=str(root)
    )
    from content_identity import new_identity
    identity = new_identity(creator)
    creator.run_id = identity["run_id"]
    project = studio.content_dir(root, identity["content_id"])
    if project.exists():
        raise ValueError(f"快速视频项目已存在，禁止覆盖：{project}")
    npm, npx = ensure_tools()
    summary = {
        "engine": "remotion / video-shotcraft" if upstream else "remotion / built-in",
        "aspect": spec["aspect"],
        "shot_count": len(spec["shots"]),
        "duration_seconds": sum(s["frames"] for s in spec["shots"]) / 30,
        "voice_missing": [] if spec["narration_audio"] else [i + 1 for i, s in enumerate(spec["shots"]) if s.get("voice_missing")],
        "silent_shots": [] if spec["narration_audio"] else [i + 1 for i, s in enumerate(spec["shots"]) if not s["audio"] and not s["voiceover"]],
        "subtitles": "timed" if spec["subtitles"] else ("missing" if spec["subtitles_required"] else "not_provided"),
        "output_root": str(output),
        "status": "plan_only" if args.dry_run else "technical_preview",
    }
    if args.dry_run:
        print("QUICK_PLAN " + json.dumps(summary, ensure_ascii=False))
        return
    studio.cmd_new(creator, quiet=True)
    project = studio.paths(root, creator.id)
    data = [{"title": s["title"], "caption": s["caption"], "seconds": s["seconds"],
             "frames": s["frames"], "voiceover": s["voiceover"], "image": None,
             "video":None,"audio": None} for s in spec["shots"]]
    for folder in ("src", "docs", "video"):
        (project / folder).mkdir(parents=True, exist_ok=True)
    for name in ("index.tsx", "Quick.tsx"):
        shutil.copy2(source / name, project / "src" / name)
    for name in ("package.json", "package-lock.json", "tsconfig.json"):
        shutil.copy2(template / name, project / name)
    # Always use the user-centered media directory as Remotion's publicDir,
    # regardless of which optional package lockfile supplies dependencies.
    shutil.copy2(source / "remotion.config.ts", project / "remotion.config.ts")
    package = studio.load(project / "package.json")
    package["scripts"] = {
        "dev": "remotion studio src/index.tsx",
        "render": "remotion render src/index.tsx QuickVideo ../成品视频.mp4",
        "still": "remotion still src/index.tsx QuickVideo",
    }
    studio.save(project / "package.json", package)
    if upstream:
        shutil.copy2(upstream / "LICENSE", project / "docs" / "video-shotcraft-LICENSE.txt")
    from project_layout import store_asset, relative_media, project_root
    master_path = relative_media(project,store_asset(project,spec["narration_audio"],"audio")) if spec["narration_audio"] else None
    for i, (shot, item) in enumerate(zip(spec["shots"], data), 1):
        if shot["image"]:
            dest=store_asset(project,shot["image"],"image",i)
            item["image"]=relative_media(project,dest)
        if shot["video"]:
            dest=store_asset(project,shot["video"],"video",i)
            item["video"]=relative_media(project,dest)
        if shot["audio"]:
            dest=store_asset(project,shot["audio"],"audio",i)
            item["audio"]=relative_media(project,dest)
    width, height = (1080, 1920) if spec["aspect"] == "9:16" else (1920, 1080)
    studio.save(project / "shotlist.json", {"width":width, "height":height, "fps":30,
        "narration_audio":master_path,"shots":data})
    studio.save(project / "subtitles.json",{
        "cues":spec["subtitles"],"required":spec["subtitles_required"],
        "timing_source":spec["subtitle_timing_source"]})
    if spec["subtitles"]:
        srt=project_root(project)/"01-文案与分镜"/"字幕文件.srt"
        def srt_time(t):
            milli=round(t*1000)
            hours,milli=divmod(milli,3600000)
            minutes,milli=divmod(milli,60000)
            seconds,milli=divmod(milli,1000)
            return f"{hours:02d}:{minutes:02d}:{seconds:02d},{milli:03d}"
        srt.write_text("".join(f"{i}\n{srt_time(c['start'])} --> {srt_time(c['end'])}\n{c['text']}\n\n"
                               for i,c in enumerate(spec["subtitles"],1)),encoding="utf8")
    script = {
        "content_id": creator.id, "title": spec["title"],
        "narration": " ".join(s["voiceover"] for s in data if s["voiceover"]) or spec["title"],
        "duration_seconds": sum(s["seconds"] for s in data),
        "editorial_intent": {
            "audience": spec["audience"] or spec["title"],
            "primary_value": spec["primary_value"],
            "secondary_values": [],
            "evidence_plan": ["使用了本地图片/视频素材；是否属于可证实的实际成果由 Agent 按来源核对" if any(s["image"] or s["video"] for s in data)
                              else "目前只有文字动效示意，不得冒充真实产品效果"],
        },
        "shots":[{"seconds":s["seconds"], "visual":s["caption"] or s["title"],
                  "voiceover":s["voiceover"]} for s in data],
        "platforms":{p:{"title":spec["title"],"description":"","tags":[]} for p in studio.PLATFORMS},
    }
    studio.save(project / "script.json", script)
    studio.export_storyboard(project)
    (project / "brief.md").write_text(
        f"# {spec['title']}\n\n目标用户：{spec['audience']}\n\n核心用户价值："
        f"{spec['primary_value']}\n\n输出性质：未经过 AI 内容审核的技术预览；不能直接发布。\n",
        encoding="utf8"
    )
    # Lockfile keeps dependencies reproducible; all packages remain project-local.
    run_cmd([npm, "ci", "--ignore-scripts", "--no-audit", "--no-fund"], project, timeout=240)
    run_cmd([npx, "--no-install", "remotion", "render", "src/index.tsx",
             "QuickVideo", "../成品视频.mp4", "--codec=h264", "--crf=23",
             "--concurrency=4", "--log=error"], project, timeout=540)
    mp4 = studio.video_path(project)
    if not mp4.is_file() or mp4.stat().st_size < 1024:
        raise RuntimeError("Remotion 没有生成有效 MP4")
    checked = json.loads(run_cmd([local_probe(project), "-v", "error", "-show_streams",
                                "-show_format", "-of", "json", str(mp4)], project, timeout=30))
    tracks = checked.get("streams", [])
    video = next((s for s in tracks if s.get("codec_type")=="video"), None)
    audio = next((s for s in tracks if s.get("codec_type")=="audio"), None)
    if not video or video.get("width")!=width or video.get("height")!=height:
        raise RuntimeError("实际 MP4 视频画幅不正确")
    if (master_path or any(s["audio"] for s in data)) and not audio:
        raise RuntimeError("实际 MP4 缺少预期配音音轨")
    if abs(float(checked["format"]["duration"]) - summary["duration_seconds"]) > 0.15:
        raise RuntimeError("实际 MP4 时长与分镜不一致")
    cover=project_root(project)/"视频封面.png"
    cover_frame=min(max(0,sum(s["frames"] for s in data)-1),35)
    run_cmd([npx,"--no-install","remotion","still","src/index.tsx","QuickVideo",
             str(cover),f"--frame={cover_frame}","--log=error"],project,120)
    ffmpeg=studio.load_ffmpeg_bin(root,"ffmpeg")
    ffprobe=studio.load_ffmpeg_bin(root,"ffprobe")
    audio_check={"result":"NOT_RUN","note":"仅依赖渲染器完成，不代表真实听音"}
    if ffmpeg and ffprobe and (master_path or any(s["audio"] for s in data)):
        try:
            audio_check=studio.inspect_video(ffmpeg,ffprobe,mp4,script["shots"])
        except (RuntimeError,ValueError) as error:
            audio_check={"result":"BLOCK","issues":[str(error)]}
    studio.save(project / "video" / "render.json", {
        "engine": "remotion", "video_sha256": studio.filehash(mp4),
        "technical_audio_check":audio_check,
        "script_sha256": studio.filehash(project / "script.json"),
        "duration_seconds": float(checked["format"]["duration"]),
        "render_status": "technical_only",
        "subtitles_sha256":studio.filehash(project/"subtitles.json"),
        "subtitle_file_sha256":studio.filehash(project_root(project)/"01-文案与分镜"/"字幕文件.srt") if spec["subtitles"] else None,
        "subtitle_timing_source":spec["subtitle_timing_source"],
        "subtitles_status":summary["subtitles"],
        "narration_audio_sha256":studio.filehash(project_root(project)/"02-媒体素材"/master_path) if master_path else None,
        "voice_missing": summary["voice_missing"],
        "silent_shots": summary["silent_shots"],
        "created_at_utc": studio.now(),
        "provenance": studio.provenance(studio.load(project / "content.json")),
    })
    print("QUICK_VIDEO_READY " + json.dumps({
        **summary, "content_id":creator.id,"project_dir":str(project_root(project)),"video_path":str(mp4),
        "studio_command":"npx remotion studio src/index.tsx",
        "review_status":"NOT_REVIEWED",
        "publish_status":"NOT_AUTHORIZED",
    }, ensure_ascii=False))
