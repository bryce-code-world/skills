#!/usr/bin/env python3
"""Cross-platform storage operations for the writing-style skill."""

import argparse
import difflib
import json
import os
import platform
import re
import shutil
import sys
import tempfile
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple


SCHEMA_VERSION = "1"
ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
META_PATTERN = re.compile(r"^- ([a-z_]+):\s*(.+?)\s*$", re.MULTILINE)
KINDS = {
    "personal": ("personal-profiles", "personal"),
    "reference": ("reference-profiles", "reference"),
}
REQUIRED_PROFILE_FIELDS = ("id", "type", "version", "status", "updated_at")
ALLOWED_STATUSES = {"candidate", "confirmed"}


class StoreError(Exception):
    pass


def emit(payload: dict, *, stream=sys.stdout) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2), file=stream)


def resolve_root(explicit: Optional[str] = None) -> Tuple[Path, str]:
    if explicit:
        raw, source = explicit, "explicit"
    elif os.environ.get("WRITING_STYLE_HOME"):
        raw, source = os.environ["WRITING_STYLE_HOME"], "environment"
    else:
        raw, source = str(Path.home() / ".writing-style"), "home"
    return Path(raw).expanduser().resolve(), source


def root_payload(root: Path, source: str) -> Dict:
    return {
        "ok": True,
        "command": "resolve-root",
        "root": str(root),
        "source": source,
        "platform": platform.system().lower(),
        "adapter": "python",
        "python": platform.python_version(),
    }


def require_confirmed(confirmed: bool) -> None:
    if not confirmed:
        raise StoreError("Mutating commands require --confirmed after explicit user confirmation.")


def validate_id(profile_id: str) -> None:
    if not ID_PATTERN.fullmatch(profile_id):
        raise StoreError("Profile id must match [a-z0-9][a-z0-9-]{0,63}.")


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8-sig")
    except OSError as exc:
        raise StoreError(f"Cannot read {path}: {exc}") from exc


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    normalized = content.replace("\r\n", "\n").replace("\r", "\n")
    if not normalized.endswith("\n"):
        normalized += "\n"
    temp_path: Optional[Path] = None
    try:
        with tempfile.NamedTemporaryFile(
            "w",
            encoding="utf-8",
            newline="\n",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as handle:
            handle.write(normalized)
            handle.flush()
            os.fsync(handle.fileno())
            temp_path = Path(handle.name)
        os.replace(temp_path, path)
    except OSError as exc:
        if temp_path:
            temp_path.unlink(missing_ok=True)
        raise StoreError(f"Cannot write {path}: {exc}") from exc


def render_config(default_profile: str) -> str:
    return (
        "# 声纹用户空间\n\n"
        f"- schema_version: {SCHEMA_VERSION}\n"
        f"- default_personal_profile: {default_profile}\n"
    )


def parse_config(content: str) -> Dict[str, str]:
    values = dict(META_PATTERN.findall(content))
    if values.get("schema_version") != SCHEMA_VERSION:
        raise StoreError(f"Unsupported or missing schema_version; expected {SCHEMA_VERSION}.")
    default_profile = values.get("default_personal_profile")
    if not default_profile:
        raise StoreError("Missing default_personal_profile in config.md.")
    if default_profile != "none":
        validate_id(default_profile)
    return values


def load_config(root: Path) -> Dict[str, str]:
    config_path = root / "config.md"
    if not config_path.is_file():
        raise StoreError(f"Missing config: {config_path}")
    return parse_config(read_text(config_path))


def profile_path(root: Path, kind: str, profile_id: str) -> Path:
    validate_id(profile_id)
    directory, _ = KINDS[kind]
    return root / directory / f"{profile_id}.md"


def parse_profile(content: str, *, kind: str, profile_id: str) -> Dict[str, str]:
    header = content.split("\n## ", 1)[0]
    metadata = dict(META_PATTERN.findall(header))
    missing = [field for field in REQUIRED_PROFILE_FIELDS if not metadata.get(field)]
    if missing:
        raise StoreError(f"Missing profile fields: {', '.join(missing)}")
    if metadata["id"] != profile_id:
        raise StoreError(f"Profile id {metadata['id']!r} does not match target {profile_id!r}.")
    expected_type = KINDS[kind][1]
    if metadata["type"] != expected_type:
        raise StoreError(f"Profile type must be {expected_type!r}.")
    try:
        version = int(metadata["version"])
    except ValueError as exc:
        raise StoreError("Profile version must be an integer.") from exc
    if version < 1:
        raise StoreError("Profile version must be at least 1.")
    metadata["version"] = str(version)
    if metadata["status"] not in ALLOWED_STATUSES:
        raise StoreError(f"Profile status must be one of: {', '.join(sorted(ALLOWED_STATUSES))}.")
    try:
        date.fromisoformat(metadata["updated_at"])
    except ValueError as exc:
        raise StoreError("updated_at must use YYYY-MM-DD.") from exc
    return metadata


def validate_profile_file(path: Path, *, kind: str, profile_id: str) -> Dict[str, str]:
    if not path.is_file():
        raise StoreError(f"Missing profile: {path}")
    return parse_profile(read_text(path), kind=kind, profile_id=profile_id)


def timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")


def backup_file(root: Path, source: Path, category: str) -> Path:
    backup = root / ".backups" / category / f"{source.stem}-{timestamp()}{source.suffix}"
    backup.parent.mkdir(parents=True, exist_ok=True)
    try:
        shutil.copy2(source, backup)
    except OSError as exc:
        raise StoreError(f"Cannot back up {source}: {exc}") from exc
    return backup


def init_space(root: Path, *, confirmed: bool) -> dict:
    require_confirmed(confirmed)
    created: List[str] = []
    try:
        for name in ("personal-profiles", "reference-profiles"):
            directory = root / name
            if not directory.exists():
                directory.mkdir(parents=True)
                created.append(str(directory))
            elif not directory.is_dir():
                raise StoreError(f"Expected directory but found file: {directory}")
        config_path = root / "config.md"
        if not config_path.exists():
            atomic_write(config_path, render_config("none"))
            created.append(str(config_path))
        elif not config_path.is_file():
            raise StoreError(f"Expected file but found directory: {config_path}")
        load_config(root)
    except OSError as exc:
        raise StoreError(f"Cannot initialize {root}: {exc}") from exc
    return {"ok": True, "root": str(root), "created": created, "idempotent": not created}


def validate_space(root: Path) -> Tuple[Dict, int]:
    errors: List[str] = []
    profiles: List[Dict] = []
    config: Optional[Dict[str, str]] = None
    try:
        config = load_config(root)
    except StoreError as exc:
        errors.append(str(exc))
    for kind, (directory_name, _) in KINDS.items():
        directory = root / directory_name
        if not directory.is_dir():
            errors.append(f"Missing directory: {directory}")
            continue
        for path in sorted(directory.glob("*.md")):
            try:
                metadata = validate_profile_file(path, kind=kind, profile_id=path.stem)
                profiles.append({"kind": kind, "path": str(path), **metadata})
            except StoreError as exc:
                errors.append(f"{path}: {exc}")
    if config and config["default_personal_profile"] != "none":
        default_path = profile_path(root, "personal", config["default_personal_profile"])
        if not default_path.is_file():
            errors.append(f"Default personal profile does not exist: {default_path}")
    payload = {
        "ok": not errors,
        "root": str(root),
        "platform": platform.system().lower(),
        "profiles": profiles,
        "errors": errors,
    }
    return payload, 0 if not errors else 1


def list_profiles(root: Path, kind: Optional[str]) -> Dict:
    selected = [kind] if kind else list(KINDS)
    profiles: List[Dict] = []
    errors: List[str] = []
    try:
        load_config(root)
    except StoreError as exc:
        errors.append(str(exc))
    for selected_kind in selected:
        directory = root / KINDS[selected_kind][0]
        if not directory.is_dir():
            errors.append(f"Missing directory: {directory}")
            continue
        for path in sorted(directory.glob("*.md")):
            try:
                metadata = validate_profile_file(path, kind=selected_kind, profile_id=path.stem)
                profiles.append({"kind": selected_kind, "path": str(path), **metadata})
            except StoreError as exc:
                errors.append(f"{path}: {exc}")
    return {"ok": not errors, "root": str(root), "profiles": profiles, "errors": errors}


def diff_profile(root: Path, *, kind: str, profile_id: str, input_path: Path) -> str:
    candidate = read_text(input_path)
    parse_profile(candidate, kind=kind, profile_id=profile_id)
    target = profile_path(root, kind, profile_id)
    current = read_text(target) if target.is_file() else ""
    diff = difflib.unified_diff(
        current.splitlines(keepends=True),
        candidate.splitlines(keepends=True),
        fromfile=str(target) if current else "/dev/null",
        tofile=str(target),
    )
    return "".join(diff) or "No changes.\n"


def save_profile(
    root: Path,
    *,
    kind: str,
    profile_id: str,
    input_path: Path,
    confirmed: bool,
    replace: bool,
    expected_version: Optional[int],
) -> dict:
    require_confirmed(confirmed)
    load_config(root)
    candidate = read_text(input_path)
    new_metadata = parse_profile(candidate, kind=kind, profile_id=profile_id)
    target = profile_path(root, kind, profile_id)
    backup: Optional[Path] = None
    if target.exists():
        if not replace:
            raise StoreError(f"Profile already exists; use --replace with --expected-version: {target}")
        old_metadata = validate_profile_file(target, kind=kind, profile_id=profile_id)
        old_version = int(old_metadata["version"])
        if expected_version is None or expected_version != old_version:
            raise StoreError(f"Expected version must match current version {old_version}.")
        if int(new_metadata["version"]) != old_version + 1:
            raise StoreError(f"Replacement version must be {old_version + 1}.")
        backup = backup_file(root, target, kind)
    elif replace:
        raise StoreError("Cannot use --replace for a profile that does not exist.")
    elif int(new_metadata["version"]) != 1:
        raise StoreError("A new profile must start at version 1.")
    atomic_write(target, candidate)
    return {
        "ok": True,
        "operation": "replace" if backup else "create",
        "path": str(target),
        "version": int(new_metadata["version"]),
        "backup": str(backup) if backup else None,
    }


def set_default(root: Path, *, profile_id: str, confirmed: bool) -> dict:
    require_confirmed(confirmed)
    config = load_config(root)
    if profile_id != "none":
        validate_profile_file(
            profile_path(root, "personal", profile_id),
            kind="personal",
            profile_id=profile_id,
        )
    config_path = root / "config.md"
    old_default = config["default_personal_profile"]
    if old_default == profile_id:
        return {"ok": True, "changed": False, "default_personal_profile": profile_id}
    backup = backup_file(root, config_path, "config")
    atomic_write(config_path, render_config(profile_id))
    return {
        "ok": True,
        "changed": True,
        "old_default": old_default,
        "default_personal_profile": profile_id,
        "backup": str(backup),
    }


def delete_profile(
    root: Path,
    *,
    kind: str,
    profile_id: str,
    confirmed: bool,
    clear_default: bool,
) -> dict:
    require_confirmed(confirmed)
    config = load_config(root)
    target = profile_path(root, kind, profile_id)
    validate_profile_file(target, kind=kind, profile_id=profile_id)
    is_default = kind == "personal" and config["default_personal_profile"] == profile_id
    if is_default:
        if not clear_default:
            raise StoreError("Profile is the default; use --clear-default after user confirmation.")
    trash = root / ".trash" / kind / f"{profile_id}-{timestamp()}.md"
    trash.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.replace(target, trash)
    except OSError as exc:
        raise StoreError(f"Cannot move profile to trash: {exc}") from exc
    try:
        if is_default:
            set_default(root, profile_id="none", confirmed=True)
    except StoreError as exc:
        try:
            os.replace(trash, target)
        except OSError as rollback_exc:
            raise StoreError(
                f"Cannot clear default after moving profile, and rollback failed: {rollback_exc}"
            ) from exc
        raise
    return {
        "ok": True,
        "deleted": str(target),
        "recoverable_at": str(trash),
        "default_cleared": is_default,
    }


def sample_profile(profile_id: str, version: int) -> str:
    return f"""# 测试档案

- id: {profile_id}
- type: personal
- version: {version}
- status: candidate
- updated_at: 2026-07-31

## 来源

- 作者：测试

## 核心风格

- 核心气质：清楚
"""


def expect_store_error(action) -> None:
    try:
        action()
    except StoreError:
        return
    raise AssertionError("Expected StoreError.")


def self_test() -> dict:
    with tempfile.TemporaryDirectory(prefix="writing-style-声纹-") as temp:
        root = Path(temp) / "user space"
        old_environment_root = os.environ.get("WRITING_STYLE_HOME")
        os.environ["WRITING_STYLE_HOME"] = str(root)
        try:
            assert resolve_root()[0] == root.resolve()
            assert resolve_root()[1] == "environment"
            assert resolve_root(str(root / "explicit"))[1] == "explicit"
        finally:
            if old_environment_root is None:
                os.environ.pop("WRITING_STYLE_HOME", None)
            else:
                os.environ["WRITING_STYLE_HOME"] = old_environment_root
        expect_store_error(lambda: init_space(root, confirmed=False))
        init_space(root, confirmed=True)
        blocked_root = Path(temp) / "root-is-a-file"
        atomic_write(blocked_root, "blocked")
        expect_store_error(lambda: init_space(blocked_root, confirmed=True))
        candidate_v1 = root / "candidate-v1.md"
        candidate_v2 = root / "candidate-v2.md"
        atomic_write(candidate_v1, sample_profile("test-profile", 1))
        atomic_write(candidate_v2, sample_profile("test-profile", 2))
        save_profile(
            root,
            kind="personal",
            profile_id="test-profile",
            input_path=candidate_v1,
            confirmed=True,
            replace=False,
            expected_version=None,
        )
        set_default(root, profile_id="test-profile", confirmed=True)
        expect_store_error(
            lambda: save_profile(
                root,
                kind="personal",
                profile_id="test-profile",
                input_path=candidate_v2,
                confirmed=True,
                replace=True,
                expected_version=99,
            )
        )
        assert "version: 2" in diff_profile(
            root,
            kind="personal",
            profile_id="test-profile",
            input_path=candidate_v2,
        )
        save_profile(
            root,
            kind="personal",
            profile_id="test-profile",
            input_path=candidate_v2,
            confirmed=True,
            replace=True,
            expected_version=1,
        )
        payload, code = validate_space(root)
        assert code == 0 and payload["ok"]
        expect_store_error(
            lambda: delete_profile(
                root,
                kind="personal",
                profile_id="test-profile",
                confirmed=True,
                clear_default=False,
            )
        )
        delete_result = delete_profile(
            root,
            kind="personal",
            profile_id="test-profile",
            confirmed=True,
            clear_default=True,
        )
        assert Path(delete_result["recoverable_at"]).is_file()
        payload, code = validate_space(root)
        assert code == 0 and payload["ok"] and not payload["profiles"]
    return {
        "ok": True,
        "checks": [
            "root-precedence",
            "mutation-confirmation-guard",
            "unicode-and-space-path",
            "init",
            "invalid-root-error",
            "create",
            "set-default",
            "diff",
            "expected-version-guard",
            "version-checked-replace",
            "validate",
            "default-delete-guard",
            "recoverable-delete",
        ],
        "platform": platform.system().lower(),
        "python": platform.python_version(),
    }


def add_root_argument(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--root", help="Explicit user-space root. Overrides WRITING_STYLE_HOME.")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    resolve = subparsers.add_parser("resolve-root", help="Resolve the active user-space root.")
    add_root_argument(resolve)

    init = subparsers.add_parser("init", help="Initialize a user space.")
    add_root_argument(init)
    init.add_argument("--confirmed", action="store_true")

    validate = subparsers.add_parser("validate", help="Validate config and profiles.")
    add_root_argument(validate)

    list_command = subparsers.add_parser("list", help="List valid profiles.")
    add_root_argument(list_command)
    list_command.add_argument("--kind", choices=KINDS)

    diff = subparsers.add_parser("diff", help="Validate and diff a candidate profile.")
    add_root_argument(diff)
    diff.add_argument("--kind", choices=KINDS, required=True)
    diff.add_argument("--id", required=True)
    diff.add_argument("--input", type=Path, required=True)

    save = subparsers.add_parser("save", help="Create or replace a profile.")
    add_root_argument(save)
    save.add_argument("--kind", choices=KINDS, required=True)
    save.add_argument("--id", required=True)
    save.add_argument("--input", type=Path, required=True)
    save.add_argument("--confirmed", action="store_true")
    save.add_argument("--replace", action="store_true")
    save.add_argument("--expected-version", type=int)

    default = subparsers.add_parser("set-default", help="Set or clear the default profile.")
    add_root_argument(default)
    default.add_argument("--id", required=True, help="Personal profile id or none.")
    default.add_argument("--confirmed", action="store_true")

    delete = subparsers.add_parser("delete", help="Move a profile to the user-space trash.")
    add_root_argument(delete)
    delete.add_argument("--kind", choices=KINDS, required=True)
    delete.add_argument("--id", required=True)
    delete.add_argument("--confirmed", action="store_true")
    delete.add_argument("--clear-default", action="store_true")

    subparsers.add_parser("self-test", help="Run an isolated standard-library smoke test.")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "self-test":
            payload = self_test()
            payload["command"] = args.command
            payload["adapter"] = "python"
            emit(payload)
            return 0
        root, source = resolve_root(args.root)
        if args.command == "resolve-root":
            emit(root_payload(root, source))
            return 0
        if args.command == "init":
            payload = init_space(root, confirmed=args.confirmed)
            payload["command"] = args.command
            emit(payload)
            return 0
        if args.command == "validate":
            payload, code = validate_space(root)
            payload["command"] = args.command
            payload["source"] = source
            emit(payload)
            return code
        if args.command == "list":
            payload = list_profiles(root, args.kind)
            payload["command"] = args.command
            emit(payload)
            return 0 if payload["ok"] else 1
        if args.command == "diff":
            print(
                diff_profile(
                    root,
                    kind=args.kind,
                    profile_id=args.id,
                    input_path=args.input,
                ),
                end="",
            )
            return 0
        if args.command == "save":
            payload = save_profile(
                root,
                kind=args.kind,
                profile_id=args.id,
                input_path=args.input,
                confirmed=args.confirmed,
                replace=args.replace,
                expected_version=args.expected_version,
            )
            payload["command"] = args.command
            emit(payload)
            return 0
        if args.command == "set-default":
            payload = set_default(root, profile_id=args.id, confirmed=args.confirmed)
            payload["command"] = args.command
            emit(payload)
            return 0
        if args.command == "delete":
            payload = delete_profile(
                root,
                kind=args.kind,
                profile_id=args.id,
                confirmed=args.confirmed,
                clear_default=args.clear_default,
            )
            payload["command"] = args.command
            emit(payload)
            return 0
    except (StoreError, AssertionError) as exc:
        emit({"ok": False, "command": args.command, "error": str(exc)}, stream=sys.stderr)
        return 2
    raise StoreError(f"Unsupported command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())
