#!/usr/bin/env python3
"""Deterministic local storage adapter for the hello skill."""

from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import shutil
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, Tuple


FILES = (
    "README.md",
    "个人全景档案.md",
    "待确认信息.md",
    "访谈进度.md",
    "资料索引.md",
    "迭代日志.md",
)
DIRS = ("原始访谈", "历史版本", ".backups", ".trash")
STATE_FILE = ".hello-state"
CAPTURE_MODES = {"auto-stage", "prompt", "explicit"}
REVIEW_STAGES = {"baseline", "first-review", "stable"}
CANDIDATE_ID = re.compile(r"^C-[0-9TZ-]+$")


class StoreError(RuntimeError):
    pass


def now_utc() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def emit(payload: dict) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


def resolve_root(value: str | None) -> Path:
    raw = value or os.environ.get("HELLO_HOME")
    if not raw:
        raise StoreError("Personal profile root is not configured. Pass --root or set HELLO_HOME.")
    return Path(raw).expanduser().resolve(strict=False)


def require_confirmed(confirmed: bool) -> None:
    if not confirmed:
        raise StoreError("Mutating commands require --confirmed after user authorization.")


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8-sig")
    except OSError as exc:
        raise StoreError(f"Cannot read {path}: {exc}") from exc


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def parse_state(path: Path) -> Dict[str, str]:
    values: Dict[str, str] = {}
    for number, raw in enumerate(read_text(path).splitlines(), 1):
        if not raw or raw.startswith("#"):
            continue
        if "=" not in raw:
            raise StoreError(f"Invalid state line {number}: expected key=value.")
        key, value = raw.split("=", 1)
        if not key or key in values:
            raise StoreError(f"Invalid or duplicate state key on line {number}.")
        values[key] = value
    return values


def write_state(path: Path, state: Dict[str, str]) -> None:
    order = (
        "schema_version",
        "profile_version",
        "capture_mode",
        "created_at",
        "updated_at",
        "last_confirmed_at",
        "next_review_at",
        "review_stage",
    )
    keys = list(order) + sorted(key for key in state if key not in order)
    atomic_write(path, "".join(f"{key}={state.get(key, '')}\n" for key in keys))


def validate_state(state: Dict[str, str]) -> list[str]:
    issues: list[str] = []
    required = {
        "schema_version",
        "profile_version",
        "capture_mode",
        "created_at",
        "updated_at",
        "last_confirmed_at",
        "next_review_at",
        "review_stage",
    }
    missing = sorted(required - state.keys())
    issues.extend(f"Missing state key: {key}" for key in missing)
    if state.get("schema_version") != "1":
        issues.append("schema_version must be 1")
    try:
        if int(state.get("profile_version", "0")) < 1:
            raise ValueError
    except ValueError:
        issues.append("profile_version must be a positive integer")
    if state.get("capture_mode") not in CAPTURE_MODES:
        issues.append("capture_mode must be auto-stage, prompt, or explicit")
    if state.get("review_stage") not in REVIEW_STAGES:
        issues.append("review_stage must be baseline, first-review, or stable")
    return issues


def init_space(root: Path, confirmed: bool) -> dict:
    require_confirmed(confirmed)
    root.mkdir(parents=True, exist_ok=True)
    template_root = Path(__file__).resolve().parents[1] / "assets" / "profile-templates"
    created: list[str] = []
    for directory in DIRS:
        target = root / directory
        if not target.exists():
            target.mkdir(parents=True)
            created.append(directory + "/")
    for name in FILES:
        target = root / name
        if not target.exists():
            shutil.copy2(template_root / name, target)
            created.append(name)
    state_path = root / STATE_FILE
    if not state_path.exists():
        current = now_utc()
        write_state(
            state_path,
            {
                "schema_version": "1",
                "profile_version": "1",
                "capture_mode": "auto-stage",
                "created_at": current,
                "updated_at": current,
                "last_confirmed_at": "",
                "next_review_at": "",
                "review_stage": "baseline",
            },
        )
        created.append(STATE_FILE)
    return {"ok": True, "command": "init", "root": str(root), "created": created}


def validate_space(root: Path) -> Tuple[dict, int]:
    issues: list[str] = []
    if not root.is_dir():
        issues.append("Root directory does not exist")
    else:
        for name in FILES:
            if not (root / name).is_file():
                issues.append(f"Missing file: {name}")
        for name in DIRS:
            if not (root / name).is_dir():
                issues.append(f"Missing directory: {name}")
        state_path = root / STATE_FILE
        if not state_path.is_file():
            issues.append(f"Missing file: {STATE_FILE}")
        else:
            try:
                issues.extend(validate_state(parse_state(state_path)))
            except StoreError as exc:
                issues.append(str(exc))
    payload = {"ok": not issues, "command": "validate", "root": str(root), "issues": issues}
    return payload, 0 if not issues else 1


def require_valid(root: Path) -> Dict[str, str]:
    payload, code = validate_space(root)
    if code:
        raise StoreError("Invalid profile space: " + "; ".join(payload["issues"]))
    return parse_state(root / STATE_FILE)


def status(root: Path) -> Tuple[dict, int]:
    payload, code = validate_space(root)
    if code:
        payload["command"] = "status"
        return payload, code
    state = parse_state(root / STATE_FILE)
    pending = len(re.findall(r"(?m)^## C-[0-9TZ-]+\s*$", read_text(root / "待确认信息.md")))
    return {
        "ok": True,
        "command": "status",
        "root": str(root),
        "profile_version": int(state["profile_version"]),
        "capture_mode": state["capture_mode"],
        "review_stage": state["review_stage"],
        "last_confirmed_at": state["last_confirmed_at"],
        "next_review_at": state["next_review_at"],
        "pending_candidates": pending,
    }, 0


def validate_review_time(value: str) -> str:
    if value in {"", "none"}:
        return ""
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise StoreError("--next-review-at must be ISO 8601 or none.") from exc
    return value


def configure_space(
    root: Path,
    capture_mode: str | None,
    next_review_at: str | None,
    review_stage: str | None,
    confirmed: bool,
) -> dict:
    require_confirmed(confirmed)
    state = require_valid(root)
    if capture_mode is None and next_review_at is None and review_stage is None:
        raise StoreError("configure requires at least one setting.")
    if capture_mode is not None:
        if capture_mode not in CAPTURE_MODES:
            raise StoreError("--capture-mode must be auto-stage, prompt, or explicit.")
        state["capture_mode"] = capture_mode
    if review_stage is not None:
        if review_stage not in REVIEW_STAGES:
            raise StoreError("--review-stage must be baseline, first-review, or stable.")
        state["review_stage"] = review_stage
    if next_review_at is not None:
        state["next_review_at"] = validate_review_time(next_review_at)
    state["updated_at"] = now_utc()
    write_state(root / STATE_FILE, state)
    return {
        "ok": True,
        "command": "configure",
        "root": str(root),
        "capture_mode": state["capture_mode"],
        "review_stage": state["review_stage"],
        "next_review_at": state["next_review_at"],
    }


def diff_profile(root: Path, input_path: Path) -> str:
    require_valid(root)
    current = read_text(root / "个人全景档案.md").splitlines(keepends=True)
    candidate = read_text(input_path).splitlines(keepends=True)
    return "".join(
        difflib.unified_diff(current, candidate, fromfile="个人全景档案.md", tofile=str(input_path))
    ) or "No changes.\n"


def clean_label(value: str | None, fallback: str) -> str:
    compact = " ".join((value or fallback).split())
    return compact[:200] or fallback


def stage_candidate(root: Path, input_path: Path, kind: str | None, source: str | None, confirmed: bool) -> dict:
    require_confirmed(confirmed)
    state = require_valid(root)
    body = read_text(input_path).strip()
    if not body:
        raise StoreError("Candidate input is empty.")
    current = now_utc()
    candidate_id = f"C-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}-{os.getpid()}"
    pending_path = root / "待确认信息.md"
    pending = read_text(pending_path).replace("\n当前没有待确认信息。\n", "\n")
    block = (
        f"\n## {candidate_id}\n\n"
        f"- 暂存时间：{current}\n"
        f"- 类型：{clean_label(kind, '未分类')}\n"
        f"- 来源：{clean_label(source, '当前会话')}\n"
        "- 状态：待确认\n\n"
        f"{body}\n"
    )
    atomic_write(pending_path, pending.rstrip() + "\n" + block)
    state["updated_at"] = current
    write_state(root / STATE_FILE, state)
    return {"ok": True, "command": "stage", "root": str(root), "candidate_id": candidate_id}


def update_profile_header(content: str, version: int, confirmed_at: str) -> str:
    content, version_count = re.subn(
        r"(?m)^- 资料版本：.*$", f"- 资料版本：{version}", content, count=1
    )
    content, time_count = re.subn(
        r"(?m)^- 最近确认时间：.*$", f"- 最近确认时间：{confirmed_at}", content, count=1
    )
    if version_count != 1 or time_count != 1:
        raise StoreError("Candidate profile must contain 资料版本 and 最近确认时间 metadata lines.")
    return content


def copy_unique(source: Path, directory: Path, name: str) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / name
    counter = 1
    while target.exists():
        target = directory / f"{Path(name).stem}-{counter}{Path(name).suffix}"
        counter += 1
    shutil.copy2(source, target)
    return target


def apply_profile(
    root: Path,
    input_path: Path,
    summary_path: Path,
    expected_version: int,
    confirmed: bool,
) -> dict:
    require_confirmed(confirmed)
    state = require_valid(root)
    current_version = int(state["profile_version"])
    if expected_version != current_version:
        raise StoreError(f"Version conflict: expected {expected_version}, current {current_version}.")
    candidate = read_text(input_path).strip()
    summary = read_text(summary_path).strip()
    if not candidate:
        raise StoreError("Candidate profile is empty.")
    if not summary:
        raise StoreError("Update summary is empty.")
    profile_path = root / "个人全景档案.md"
    current = now_utc()
    new_version = current_version + 1
    candidate = update_profile_header(candidate + "\n", new_version, current)
    file_stamp = stamp()
    history = copy_unique(
        profile_path,
        root / "历史版本",
        f"{file_stamp}-v{current_version}-个人全景档案.md",
    )
    backup = copy_unique(
        profile_path,
        root / ".backups" / "profile",
        f"{file_stamp}-v{current_version}-个人全景档案.md",
    )
    atomic_write(profile_path, candidate)
    log_path = root / "迭代日志.md"
    log = read_text(log_path).replace("\n当前没有正式迭代。\n", "\n").rstrip()
    entry = (
        f"\n\n## R{new_version} · {current}\n\n"
        f"- 资料版本：{new_version}\n"
        "- 确认状态：用户已确认\n"
        f"- 历史快照：`历史版本/{history.name}`\n\n"
        f"{summary}\n"
    )
    atomic_write(log_path, log + entry)
    state["profile_version"] = str(new_version)
    state["updated_at"] = current
    state["last_confirmed_at"] = current
    if state["review_stage"] == "baseline":
        state["review_stage"] = "first-review"
    write_state(root / STATE_FILE, state)
    return {
        "ok": True,
        "command": "apply",
        "root": str(root),
        "old_version": current_version,
        "profile_version": new_version,
        "history": str(history),
        "backup": str(backup),
    }


def withdraw_candidate(root: Path, candidate_id: str, confirmed: bool) -> dict:
    require_confirmed(confirmed)
    state = require_valid(root)
    if not CANDIDATE_ID.fullmatch(candidate_id):
        raise StoreError("Invalid candidate id.")
    pending_path = root / "待确认信息.md"
    content = read_text(pending_path)
    pattern = re.compile(
        rf"(?ms)^## {re.escape(candidate_id)}\s*\n.*?(?=^## C-[0-9TZ-]+\s*$|\Z)"
    )
    match = pattern.search(content)
    if not match:
        raise StoreError(f"Candidate not found: {candidate_id}")
    trash = root / ".trash" / "candidates" / f"{candidate_id}.md"
    trash.parent.mkdir(parents=True, exist_ok=True)
    if trash.exists():
        trash = trash.with_name(f"{candidate_id}-{stamp()}.md")
    atomic_write(trash, match.group(0).rstrip() + "\n")
    remaining = (content[: match.start()] + content[match.end() :]).rstrip() + "\n"
    if not re.search(r"(?m)^## C-[0-9TZ-]+\s*$", remaining):
        remaining = remaining.rstrip() + "\n\n当前没有待确认信息。\n"
    atomic_write(pending_path, remaining)
    state["updated_at"] = now_utc()
    write_state(root / STATE_FILE, state)
    return {
        "ok": True,
        "command": "withdraw",
        "root": str(root),
        "candidate_id": candidate_id,
        "trash": str(trash),
    }


def self_test() -> dict:
    with tempfile.TemporaryDirectory(prefix="hello-self-test-") as temporary:
        root = Path(temporary) / "中文 空格"
        try:
            init_space(root, False)
            raise AssertionError("confirmation guard did not fail")
        except StoreError:
            pass
        init_space(root, True)
        assert init_space(root, True)["created"] == []
        payload, code = validate_space(root)
        assert code == 0, payload
        candidate_note = root.parent / "candidate.md"
        candidate_note.write_text("用户完成了一个重要项目。\n", encoding="utf-8")
        staged = stage_candidate(root, candidate_note, "经历", "自测", True)
        configured = configure_space(root, "prompt", "2030-01-01T00:00:00Z", None, True)
        assert configured["capture_mode"] == "prompt"
        state = parse_state(root / STATE_FILE)
        profile_candidate = root.parent / "profile.md"
        profile_candidate.write_text(read_text(root / "个人全景档案.md"), encoding="utf-8")
        summary = root.parent / "summary.md"
        summary.write_text("- 自测更新。\n", encoding="utf-8")
        applied = apply_profile(root, profile_candidate, summary, int(state["profile_version"]), True)
        try:
            apply_profile(root, profile_candidate, summary, 1, True)
            raise AssertionError("version conflict did not fail")
        except StoreError:
            pass
        withdraw_candidate(root, staged["candidate_id"], True)
        final, code = validate_space(root)
        assert code == 0, final
        assert applied["profile_version"] == 2
    return {"ok": True, "command": "self-test"}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    def root_argument(item: argparse.ArgumentParser) -> None:
        item.add_argument("--root")

    root_argument(sub.add_parser("resolve-root"))
    item = sub.add_parser("init")
    root_argument(item)
    item.add_argument("--confirmed", action="store_true")
    root_argument(sub.add_parser("validate"))
    root_argument(sub.add_parser("status"))
    item = sub.add_parser("configure")
    root_argument(item)
    item.add_argument("--capture-mode")
    item.add_argument("--next-review-at")
    item.add_argument("--review-stage")
    item.add_argument("--confirmed", action="store_true")
    item = sub.add_parser("diff")
    root_argument(item)
    item.add_argument("--input", required=True)
    item = sub.add_parser("stage")
    root_argument(item)
    item.add_argument("--input", required=True)
    item.add_argument("--kind")
    item.add_argument("--source")
    item.add_argument("--confirmed", action="store_true")
    item = sub.add_parser("apply")
    root_argument(item)
    item.add_argument("--input", required=True)
    item.add_argument("--summary-input", required=True)
    item.add_argument("--expected-version", required=True, type=int)
    item.add_argument("--confirmed", action="store_true")
    item = sub.add_parser("withdraw")
    root_argument(item)
    item.add_argument("--id", required=True)
    item.add_argument("--confirmed", action="store_true")
    sub.add_parser("self-test")
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "self-test":
            emit(self_test())
            return 0
        root = resolve_root(args.root)
        if args.command == "resolve-root":
            emit({"ok": True, "command": args.command, "root": str(root)})
            return 0
        if args.command == "init":
            emit(init_space(root, args.confirmed))
            return 0
        if args.command == "validate":
            payload, code = validate_space(root)
            emit(payload)
            return code
        if args.command == "status":
            payload, code = status(root)
            emit(payload)
            return code
        if args.command == "configure":
            emit(
                configure_space(
                    root,
                    args.capture_mode,
                    args.next_review_at,
                    args.review_stage,
                    args.confirmed,
                )
            )
            return 0
        if args.command == "diff":
            sys.stdout.write(diff_profile(root, Path(args.input)))
            return 0
        if args.command == "stage":
            emit(stage_candidate(root, Path(args.input), args.kind, args.source, args.confirmed))
            return 0
        if args.command == "apply":
            emit(
                apply_profile(
                    root,
                    Path(args.input),
                    Path(args.summary_input),
                    args.expected_version,
                    args.confirmed,
                )
            )
            return 0
        if args.command == "withdraw":
            emit(withdraw_candidate(root, args.id, args.confirmed))
            return 0
        raise StoreError(f"Unknown command: {args.command}")
    except (StoreError, OSError, AssertionError) as exc:
        emit({"ok": False, "command": args.command, "error": str(exc)})
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
