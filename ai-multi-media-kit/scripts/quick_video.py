"""Small, project-local Remotion rendering route backed by video-shotcraft.

Agent authors the short shot list; this module only validates local materials,
copies the supplied media, and renders an editable technical preview. It never
creates script/video PASS records or grants any publishing permission.
"""
from __future__ import annotations

import argparse
import json
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


def checked_spec(raw: dict, file: Path) -> dict:
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
        caption = valid_text(shot.get("caption", ""), f"第 {i} 段 caption", 150, required=False)
        line = {
            "title": valid_text(shot.get("title"), f"第 {i} 段 title", 100),
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
            if line["audio"].suffix.lower() == ".wav":
                try:
                    with wave.open(str(line["audio"]), "rb") as audio:
                        duration = audio.getnframes() / audio.getframerate()
                except (wave.Error, EOFError, ZeroDivisionError) as exc:
                    raise ValueError(f"第 {i} 段配音 WAV 格式损坏") from exc
                if duration > float(seconds) - 0.15:
                    raise ValueError(f"第 {i} 段配音超过镜头时长：{duration:.2f}s > {seconds}s")
        if not line["audio"]:
            line["voice_missing"] = True
        prepared.append(line)
    if sum(shot["seconds"] for shot in prepared) > 180:
        raise ValueError("总时长不能超过 180 秒；请使用完整制作模式")
    return {"title": title, "audience": audience, "primary_value": value,
            "aspect": aspect, "shots": prepared}


def provider_root(raw: str | None) -> Path:
    root = Path(raw).expanduser().resolve() if raw else Path.home() / ".codex" / "skills" / "video-shotcraft"
    required = ["SKILL.md", "LICENSE", "template/package.json", "template/package-lock.json",
                "template/tsconfig.json", "template/remotion.config.ts",
                "assets/lib/FlashCut.tsx", "assets/audio/bgm/house-vibez.mp3",
                "assets/audio/ATTRIBUTION.md"]
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
    npm = shutil.which("npm")
    npx = shutil.which("npx")
    if not npm or not npx:
        raise ValueError("Remotion 快速创作需要已安装 Node.js/npm；不会自动修改 PATH 或安装未知组件")
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
    root, _ = studio.workspace(args.root)
    # Protect the persisted output directory, including its separation from tools/knowledge.
    from workspace_paths import output_directory
    output = output_directory(root, studio.load(root / "config" / "workspace.json"))
    spec_file = Path(args.spec).expanduser().resolve()
    if not spec_file.is_file():
        raise ValueError(f"缺少快速分镜 JSON：{spec_file}")
    spec = checked_spec(studio.load(spec_file), spec_file)
    upstream = provider_root(args.shotcraft_dir)
    summary = {
        "engine": "remotion / video-shotcraft",
        "aspect": spec["aspect"],
        "shot_count": len(spec["shots"]),
        "duration_seconds": sum(s["frames"] for s in spec["shots"]) / 30,
        "voice_missing": [i + 1 for i, s in enumerate(spec["shots"]) if s.get("voice_missing")],
        "output_root": str(output),
        "status": "plan_only" if args.dry_run else "technical_preview",
    }
    if args.dry_run:
        print("QUICK_PLAN " + json.dumps(summary, ensure_ascii=False))
        return
    npm, npx = ensure_tools()
    # Reserve this original content ID through the existing CLI, retaining creator provenance.
    creator = argparse.Namespace(
        id=None, topic=args.topic, agent=args.agent, model=args.model, run_id=args.run_id,
        parent_id=None, publish_target=None, title=spec["title"], task_ref=None,
        root=str(root)
    )
    # Fail any identity problem *before* creating an output folder.
    from content_identity import new_identity
    identity = new_identity(creator)
    creator.run_id = identity["run_id"]  # Preserve the collision-tested ID at creation.
    project = studio.content_dir(root, identity["content_id"])
    if project.exists():
        raise ValueError(f"快速视频项目已存在，禁止覆盖：{project}")

    studio.cmd_new(creator)
    project = studio.paths(root, creator.id)
    data = [{"title": s["title"], "caption": s["caption"], "seconds": s["seconds"],
             "frames": s["frames"], "voiceover": s["voiceover"], "image": None,
             "audio": None} for s in spec["shots"]]
    for folder in ("src", "public/screens", "public/audio", "docs", "video"):
        (project / folder).mkdir(parents=True, exist_ok=True)
    source = Path(__file__).resolve().parents[1] / "assets" / "quick-remotion"
    for name in ("index.tsx", "Quick.tsx"):
        shutil.copy2(source / name, project / "src" / name)
    for name in ("package.json", "package-lock.json", "tsconfig.json", "remotion.config.ts"):
        shutil.copy2(upstream / "template" / name, project / name)
    package = studio.load(project / "package.json")
    package["scripts"] = {
        "dev": "remotion studio src/index.tsx",
        "render": "remotion render src/index.tsx QuickVideo video/master.mp4",
        "still": "remotion still src/index.tsx QuickVideo",
    }
    studio.save(project / "package.json", package)
    shutil.copy2(upstream / "assets" / "lib" / "FlashCut.tsx", project / "src" / "FlashCut.tsx")
    shutil.copy2(upstream / "assets" / "audio" / "bgm" / "house-vibez.mp3", project / "public" / "audio" / "bgm.mp3")
    shutil.copy2(upstream / "assets" / "audio" / "ATTRIBUTION.md", project / "docs" / "audio-attribution.md")
    shutil.copy2(upstream / "LICENSE", project / "docs" / "video-shotcraft-LICENSE.txt")
    for i, (shot, item) in enumerate(zip(spec["shots"], data), 1):
        if shot["image"]:
            name = f"shot-{i:02d}{shot['image'].suffix.lower()}"
            shutil.copy2(shot["image"], project / "public" / "screens" / name)
            item["image"] = "screens/" + name
        if shot["audio"]:
            name = f"shot-{i:02d}{shot['audio'].suffix.lower()}"
            shutil.copy2(shot["audio"], project / "public" / "audio" / name)
            item["audio"] = "audio/" + name
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
    (project / "brief.md").write_text(
        f"# {spec['title']}\n\n目标用户：{spec['audience']}\n\n核心用户价值："
        f"{spec['primary_value']}\n\n输出性质：未经过 AI 内容审核的技术预览；不能直接发布。\n",
        encoding="utf8"
    )
    # Provider lockfile is reused; no extra package or global install is necessary.
    run_cmd([npm, "ci", "--ignore-scripts", "--no-audit", "--no-fund"], project, timeout=240)
    run_cmd([npx, "--no-install", "remotion", "render", "src/index.tsx",
             "QuickVideo", "video/master.mp4", "--codec=h264", "--crf=23",
             "--concurrency=4", "--log=error"], project, timeout=540)
    mp4 = project / "video" / "master.mp4"
    if not mp4.is_file() or mp4.stat().st_size < 1024:
        raise RuntimeError("Remotion 没有生成有效 MP4")
    checked = json.loads(run_cmd([local_probe(project), "-v", "error", "-show_streams",
                                "-show_format", "-of", "json", str(mp4)], project, timeout=30))
    tracks = checked.get("streams", [])
    video = next((s for s in tracks if s.get("codec_type")=="video"), None)
    audio = next((s for s in tracks if s.get("codec_type")=="audio"), None)
    if not video or not audio or video.get("width")!=width or video.get("height")!=height:
        raise RuntimeError("实际 MP4 缺少音轨或视频画幅不正确")
    studio.save(project / "video" / "render.json", {
        "engine": "remotion", "video_sha256": studio.filehash(mp4),
        "script_sha256": studio.filehash(project / "script.json"),
        "duration_seconds": float(checked["format"]["duration"]),
        "render_status": "technical_only",
        "voice_missing": summary["voice_missing"],
        "created_at_utc": studio.now(),
        "provenance": studio.provenance(studio.load(project / "content.json")),
    })
    print("QUICK_VIDEO_READY " + json.dumps({
        **summary, "content_id":creator.id,"video_path":str(mp4),
        "studio_command":"npx remotion studio src/index.tsx",
        "review_status":"NOT_REVIEWED",
        "publish_status":"NOT_AUTHORIZED",
    }, ensure_ascii=False))
