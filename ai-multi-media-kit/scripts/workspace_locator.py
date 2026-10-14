#!/usr/bin/env python3
"""Per-installation workspace pointer, saved beside SKILL.md and excluded from Git.

This is only a locator. The authoritative configuration lives in the workspace's
config/workspace.json. Every read validates that file and does not create folders.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

SKILL_ROOT = Path(__file__).resolve().parent.parent
REGISTRY_RELATIVE = Path("config/local-install.json")


def validate_workspace(install_root: Path, knowledge_root: Path | None = None) -> tuple[Path, Path]:
    root = Path(install_root).expanduser().resolve()
    config = root / "config" / "workspace.json"
    if not config.is_file():
        raise ValueError(f"工作区配置不存在：{config}。请先初始化或重新指定有效目录")
    try:
        data = json.loads(config.read_text(encoding="utf-8"))
        configured_root = Path(data["install_root"]).expanduser().resolve()
        configured_k = Path(data["knowledge_root"]).expanduser().resolve()
    except (OSError, KeyError, TypeError, ValueError) as exc:
        raise ValueError(f"工作区配置无法读取：{config} ({exc})") from exc
    if root != configured_root:
        raise ValueError("工作区配置路径与实际目录不一致；不会自动修改原有安装")
    if not configured_k.is_dir():
        raise ValueError(f"企业知识库目录不可访问：{configured_k}")
    if knowledge_root is not None and Path(knowledge_root).expanduser().resolve() != configured_k:
        raise ValueError("企业知识库路径与工作区配置不一致；拒绝覆盖安装记录")
    return root, configured_k


def remember_workspace(install_root: Path, knowledge_root: Path,
                       skill_root: Path = SKILL_ROOT) -> bool:
    """Remember the explicitly initialized workspace. True only if pointer changed."""
    install, knowledge = validate_workspace(install_root, knowledge_root)
    path = Path(skill_root) / REGISTRY_RELATIVE
    if path.is_symlink():
        raise ValueError(f"安装记录是符号链接，拒绝覆盖：{path}")
    record = {
        "schema": 1,
        "install_root": str(install),
        "knowledge_root": str(knowledge),
    }
    if path.exists():
        try:
            old = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            raise ValueError("已有本机安装记录无法读取；请人工检查后修复") from exc
        if old.get("schema") != 1:
            raise ValueError("已有本机安装记录版本未知；不会覆盖")
        if all(old.get(key) == value for key, value in record.items()):
            return False

    record["registered_at_utc"] = datetime.now(timezone.utc).isoformat()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="\n",
                                         dir=path.parent, prefix=".local-install-",
                                         suffix=".tmp", delete=False) as file:
            temporary = Path(file.name)
            json.dump(record, file, indent=2, ensure_ascii=False)
            file.write("\n")
        if os.name != "nt":
            temporary.chmod(0o600)
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()
    return True


def current_workspace(skill_root: Path = SKILL_ROOT) -> dict:
    path = Path(skill_root) / REGISTRY_RELATIVE
    if not path.is_file() or path.is_symlink():
        raise ValueError(f"本机未登记工作区：{path}；请通过 Skill 首次初始化")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("schema") != 1:
            raise ValueError("不支持的安装索引版本")
        install = Path(data["install_root"])
        knowledge = Path(data["knowledge_root"])
    except (KeyError, TypeError, OSError, ValueError) as exc:
        raise ValueError(f"本机安装记录无效：{path} ({exc})") from exc
    root, kb = validate_workspace(install, knowledge)
    return {
        "schema": 1,
        "install_root": str(root),
        "knowledge_root": str(kb),
        "launchers": {
            "windows": str(root / "RUN-STUDIO-WINDOWS.ps1"),
            "unix": str(root / "run-studio.sh"),
        },
        "checked": "workspace_paths_only_not_runtime_readiness",
    }


def main():
    parser = argparse.ArgumentParser(description="读取或重登记已初始化的本机 AI Media Studio 工作区")
    sub = parser.add_subparsers(dest="task", required=True)
    sub.add_parser("show", help="只读：核验保存的默认工作区并打印绝对路径")
    bind = sub.add_parser("register", help="用户明确指定已有工作区，重新登记为默认")
    bind.add_argument("--install-root", required=True)
    args = parser.parse_args()
    try:
        if args.task == "register":
            root, knowledge = validate_workspace(Path(args.install_root))
            changed = remember_workspace(root, knowledge)
            print("REGISTERED" if changed else "ALREADY_REGISTERED")
        print(json.dumps(current_workspace(), indent=2, ensure_ascii=False))
        return 0
    except (ValueError, OSError) as exc:
        print("ERROR:", exc, file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
