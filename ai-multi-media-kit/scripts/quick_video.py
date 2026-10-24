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


def audio_duration(source: Path, ffprobe: str | None) -> float:
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
            if not any(s.get("codec_type") == "audio" for s in info.get("streams", [])):
                raise ValueError("文件没有音频流")
            duration = float(info["format"]["duration"])
        except (KeyError, TypeError, ValueError, RuntimeError) as exc:
            raise ValueError(f"无法验证配音时长：{source.name}（{exc}）") from exc
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError(f"配音时长无效：{source.name}")
    return duration


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
        if shot.get("image"):
            line["image"] = media_path(shot["image"], file, IMAGE_FORMATS, f"第 {i} 段图片")
        if shot.get("audio"):
            line["audio"] = media_path(shot["audio"], file, AUDIO_FORMATS, f"第 {i} 段配音")
            duration = audio_duration(line["audio"], ffprobe)
            if duration > line["frames"] / 30 - 0.15:
                raise ValueError(f"第 {i} 段配音过长，需保留 0.15 秒余量：{duration:.2f}s / {seconds}s")
        line["voice_missing"] = bool(line["voiceover"] and not line["audio"])
        prepared.append(line)
    if sum(shot["seconds"] for shot in prepared) > 180:
        raise ValueError("总时长不能超过 180 秒；请使用完整制作模式")
    return {"title": title, "audience": audience, "primary_value": value,
            "aspect": aspect, "shots": prepared}


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
        "voice_missing": [i + 1 for i, s in enumerate(spec["shots"]) if s.get("voice_missing")],
        "silent_shots": [i + 1 for i, s in enumerate(spec["shots"]) if not s["audio"] and not s["voiceover"]],
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
             "audio": None} for s in spec["shots"]]
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
    for i, (shot, item) in enumerate(zip(spec["shots"], data), 1):
        if shot["image"]:
            dest=store_asset(project,shot["image"],"image",i)
            item["image"]=relative_media(project,dest)
        if shot["audio"]:
            dest=store_asset(project,shot["audio"],"audio",i)
            item["audio"]=relative_media(project,dest)
    width, height = (1080, 1920) if spec["aspect"] == "9:16" else (1920, 1080)
    studio.save(project / "shotlist.json", {"width":width, "height":height, "fps":30, "shots":data})
    script = {
        "content_id": creator.id, "title": spec["title"],
        "narration": " ".join(s["voiceover"] for s in data if s["voiceover"]) or spec["title"],
        "duration_seconds": sum(s["seconds"] for s in data),
        "editorial_intent": {
            "audience": spec["audience"] or spec["title"],
            "primary_value": spec["primary_value"],
            "secondary_values": [],
            "evidence_plan": ["展示用户提供的实际截图" if any(s["image"] for s in data)
                              else "仅文字动效示意，不冒充真实产品界面"],
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
    if any(s["audio"] for s in data) and not audio:
        raise RuntimeError("实际 MP4 缺少预期配音音轨")
    if abs(float(checked["format"]["duration"]) - summary["duration_seconds"]) > 0.15:
        raise RuntimeError("实际 MP4 时长与分镜不一致")
    cover=project_root(project)/"视频封面.png"
    cover_frame=min(max(0,sum(s["frames"] for s in data)-1),35)
    run_cmd([npx,"--no-install","remotion","still","src/index.tsx","QuickVideo",
             str(cover),f"--frame={cover_frame}","--log=error"],project,120)
    studio.save(project / "video" / "render.json", {
        "engine": "remotion", "video_sha256": studio.filehash(mp4),
        "script_sha256": studio.filehash(project / "script.json"),
        "duration_seconds": float(checked["format"]["duration"]),
        "render_status": "technical_only",
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
