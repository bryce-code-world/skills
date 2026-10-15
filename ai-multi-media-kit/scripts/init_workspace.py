#!/usr/bin/env python3
"""Safely initialize a local AI Media Studio workspace. No network or package installs."""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PLATFORMS = ["xiaohongshu", "douyin", "tencent", "bilibili", "kuaishou", "wechat_oa", "zhihu"]


def safe_copy(src: Path, dst: Path) -> bool:
    if dst.exists():
        return False
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.is_dir():
        shutil.copytree(src, dst)
    else:
        shutil.copy2(src, dst)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Initialize AI Media Studio (no downloads or installs).")
    parser.add_argument("--install-root", required=True, help="Workspace/tool root, e.g. D:\\AI-Media-Studio")
    parser.add_argument("--knowledge-root", required=True, help="Independent company knowledge root")
    parser.add_argument("--output-root", help="Separate project output root; default keeps legacy <install-root>/outputs")
    parser.add_argument("--remember", action="store_true", help="Remember this initialized workspace in this Skill's private local-install.json")
    args = parser.parse_args()
    install = Path(args.install_root).expanduser().resolve()
    knowledge = Path(args.knowledge_root).expanduser().resolve()
    if install == knowledge or install in knowledge.parents or knowledge in install.parents:
        print("ERROR: install-root and knowledge-root must be separate, non-nested directories.", file=sys.stderr)
        return 2

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from workspace_paths import output_directory
    # Preflight BEFORE any filesystem changes: avoid creating an unwanted knowledge
    # directory and copying files when reconfiguration conflicts with existing data.
    preexisting_config = install / "config" / "workspace.json"
    if preexisting_config.exists():
        try:
            previous = json.loads(preexisting_config.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            print(f"ERROR: invalid existing workspace.json: {exc}", file=sys.stderr)
            return 2
        if str(install) != previous.get("install_root") or str(knowledge) != previous.get("knowledge_root"):
            print("ERROR: existing workspace.json paths differ; no paths were created or modified.", file=sys.stderr)
            return 2
    # An existing output directory cannot be moved safely by merely changing its config.
    # When --output-root is omitted, preserve the previous choice or the legacy default.
    raw_output = args.output_root if args.output_root is not None else (
        previous.get("output_root", str(install / "outputs")) if preexisting_config.exists()
        else str(install / "outputs"))
    try:
        output = output_directory(install, {"knowledge_root": str(knowledge), "output_root": raw_output}, initializing=True)
        if preexisting_config.exists():
            stored = output_directory(install, previous)
            if output != stored:
                print("ERROR: Existing output_root differs; do not relocate or split existing projects.", file=sys.stderr)
                return 2
            if output != (install / "outputs").resolve() and not output.is_dir():
                print("ERROR: existing custom output_root is missing or not a directory; refusing to recreate it.", file=sys.stderr)
                return 2
    except (ValueError, OSError) as exc:
        print(f"ERROR: invalid output_root: {exc}", file=sys.stderr)
        return 2

    install.mkdir(parents=True, exist_ok=True)
    knowledge.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)

    for rel in [".agents/skills", "config", "docs", "scripts"]:
        source = PROJECT_ROOT / rel
        if rel == "config":
            # Never copy a host-specific locator into another user's runtime workspace.
            for file in ("bootstrap-assets.json", "dependencies.yaml", "platforms.yaml"):
                if (source / file).is_file():
                    safe_copy(source / file, install / rel / file)
            continue
        if source.exists() and source.resolve() != (install / rel).resolve():
            if not (install / rel).exists():
                safe_copy(source, install / rel)
            else:
                # Copy missing files only; leave existing skill and user edits alone.
                for path in source.rglob("*"):
                    if path.is_file():
                        safe_copy(path, install / rel / path.relative_to(source))

    for base_file in ["AGENTS.md", "README.md", ".gitignore", "SETUP-WINDOWS.cmd", "SETUP-WINDOWS.ps1", "SETUP-UNIX.sh", "RUN-STUDIO-WINDOWS.ps1", "run-studio.sh", "start-codex.cmd", "start-codex.sh"]:
        safe_copy(PROJECT_ROOT / base_file, install / base_file)
    for folder in ["tools", "mcp", "runtime/browsers", "runtime/uv-cache", "runtime/uv-python", "runtime/bootstrap/uv", "runtime/downloads", "runtime/cache", "runtime/tmp", "auth", "cache", "logs"]:
        (install / folder).mkdir(parents=True, exist_ok=True)
    for folder in ["examples", "materials", "review-history", "platform-rules", "methodologies", "successful-examples"]:
        (knowledge / folder).mkdir(parents=True, exist_ok=True)
    for path in (PROJECT_ROOT / "knowledge-templates").iterdir():
        if path.is_file():
            safe_copy(path, knowledge / path.name)

    config_path = install / "config" / "workspace.json"
    if not config_path.exists():
        obj = {
            "schema": 2,
            "install_root": str(install),
            "knowledge_root": str(knowledge),
            "output_root": str(output),
            "platforms": PLATFORMS,
            "publish_mode": "dry-run",
            "auto_publish": False,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        config_path.write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print("CREATED:", config_path)
    else:
        current = json.loads(config_path.read_text(encoding="utf-8"))
        if str(install) != current.get("install_root") or str(knowledge) != current.get("knowledge_root"):
            print("ERROR: existing workspace.json paths differ. No changes made; review configuration before moving.", file=sys.stderr)
            return 2
        print("PRESERVED:", config_path)

    # The source registry belongs to the user workspace, not the distributable Skill.
    # Re-running setup never overwrites user-managed source paths or rights metadata.
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from materials import ensure_registry
    ensure_registry(install, knowledge)

    lock = install / "config" / "dependencies.lock.json"
    if not lock.exists():
        lock.write_text(json.dumps({"schema": 1, "status": "not_installed", "verified_dependencies": {}}, indent=2) + "\n", encoding="utf-8")
        print("CREATED:", lock)
    if args.remember:
        from workspace_locator import remember_workspace
        try:
            changed = remember_workspace(install, knowledge, PROJECT_ROOT)
        except (ValueError, OSError) as exc:
            print(f"ERROR: cannot persist workspace locator: {exc}", file=sys.stderr)
            return 2
        print("DEFAULT_WORKSPACE_REGISTERED" if changed else "DEFAULT_WORKSPACE_UNCHANGED")
    print("READY (workspace scaffolding only). Run SETUP-WINDOWS.ps1 or SETUP-UNIX.sh to bootstrap Python and media tooling; external accounts have NOT been linked.")
    print("PROJECT_OUTPUT_ROOT:", output)
    print("NEXT: run-studio.sh doctor / RUN-STUDIO-WINDOWS.ps1 -Task doctor; workspace:", str(install))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
