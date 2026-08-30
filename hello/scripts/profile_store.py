#!/usr/bin/env python3
"""Deterministic local storage adapter for the hello skill."""

from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from contextlib import contextmanager
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
TRANSACTION_FILE = ".hello-transaction"
LOCK_DIR = ".hello-lock"
CAPTURE_MODES = {"auto-stage", "prompt", "explicit"}
CAPTURE_STRATEGIES = {"auto-stage": "自动暂存", "prompt": "提示确认", "explicit": "仅显式"}
MUTATING_COMMANDS = {
    "init",
    "configure",
    "record-disclosure",
    "stage",
    "apply",
    "record-turn",
    "withdraw",
    "recover",
}
REVIEW_STAGES = {"baseline", "first-review", "stable"}
UPDATE_TYPES = {"新增", "状态变化", "事实纠正", "解释变化", "假设验证", "撤回隐藏"}
CANDIDATE_ID = re.compile(r"^C-[0-9TZ-]+$")
SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
SESSION_ID = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}[A-Za-z0-9._-]{0,117}$")
POSITIVE_DECIMAL = re.compile(r"^[1-9][0-9]*$")
PROFILE_SECTIONS = (
    "## 一、当前起点",
    "## 二、人生时间线与关键经历",
    "## 三、能力、经验与证据",
    "## 四、知识、认知与学习方式",
    "## 五、健康、精力与可持续边界",
    "## 六、经济、资源与风险承受能力",
    "## 七、关系、支持网络与现实责任",
    "## 八、习惯、行动与决策方式",
    "## 九、价值观、世界观与人生愿景",
    "## 十、当前目标与未来设想",
    "## 十一、AI 协作偏好",
    "## 十二、未知、冲突与 AI 假设",
    "## 十三、主要来源",
)
PROGRESS_SECTIONS = ("## 已覆盖主题", "## 待补充主题", "## 暂不收集", "## 下次问题")
SUMMARY_FIELDS = (
    "触发原因",
    "信息来源",
    "更新类型",
    "更新位置",
    "更新摘要",
    "用户确认状态",
    "执行工具",
)


class StoreError(RuntimeError):
    pass


class CliParseError(RuntimeError):
    """An argparse failure that can be rendered through the adapter contract."""


class JsonArgumentParser(argparse.ArgumentParser):
    """Keep parser failures on the same JSON/exit-code channel as other errors."""

    def __init__(self, *args, **kwargs):
        # PowerShell and POSIX adapters require exact long option names.  Do
        # not let argparse silently accept prefixes such as ``--r``.
        kwargs.setdefault("allow_abbrev", False)
        super().__init__(*args, **kwargs)

    def error(self, message: str) -> None:  # pragma: no cover - exercised via CLI probes
        raise CliParseError(message)


def now_utc() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def serialize_json(payload: dict) -> str:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n"


def emit(payload: dict) -> None:
    # Keep the adapter contract UTF-8 even when Windows uses a legacy console code page.
    text = serialize_json(payload)
    sys.stdout.buffer.write(text.encode("utf-8"))
    sys.stdout.buffer.flush()


def resolve_root(value: str | None) -> Path:
    # An explicitly supplied empty --root must fail closed.  Falling back to
    # HELLO_HOME in that case can silently redirect a probe or mutation to a
    # different person's space when a wrapper drops an argument value.
    raw = value if value is not None else os.environ.get("HELLO_HOME")
    if raw is None or raw == "":
        raise StoreError("Personal profile root is not configured. Pass --root or set HELLO_HOME.")
    return Path(raw).expanduser().resolve(strict=False)


def require_confirmed(confirmed: bool) -> None:
    if not confirmed:
        raise StoreError("Mutating commands require --confirmed after user authorization.")


VALUE_OPTIONS = {
    "root",
    "input",
    "summary-input",
    "expected-version",
    "kind",
    "source",
    "id",
    "capture-mode",
    "next-review-at",
    "review-stage",
    "progress-input",
    "session-id",
    "turn-id",
    "expected-progress-version",
}
FLAG_OPTIONS = {"confirmed", "simulate-failure"}


def validate_cli_syntax(raw_argv: list[str]) -> None:
    """Enforce the exact option grammar shared by all adapters.

    ``argparse`` otherwise accepts ``--name=value`` and repeated options;
    the PowerShell/POSIX readers intentionally do not.  Keeping this check
    before parser construction makes failures use the normal JSON contract.
    """
    seen_values: set[str] = set()
    seen_flags: set[str] = set()
    for token in raw_argv:
        if token == "--":
            raise CliParseError("Option terminator -- is not supported.")
        if not token.startswith("--"):
            continue
        if token[2:] in FLAG_OPTIONS:
            if token in seen_flags:
                raise CliParseError(f"Duplicate option: {token}")
            seen_flags.add(token)
            continue
        if "=" in token:
            raise CliParseError("Options must pass values as a separate argument.")
        name = token[2:]
        if name in VALUE_OPTIONS:
            if name in seen_values:
                raise CliParseError(f"Duplicate option: --{name}")
            seen_values.add(name)


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8-sig")
    except (OSError, UnicodeError) as exc:
        raise StoreError(f"Cannot read {path}: {exc}") from exc


def secure_file(path: Path) -> None:
    if os.name != "nt":
        path.chmod(0o600)


def secure_directory(path: Path) -> None:
    if os.name != "nt":
        path.chmod(0o700)


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        secure_file(path)
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def parse_key_values(path: Path) -> Dict[str, str]:
    values: Dict[str, str] = {}
    seen_keys: set[str] = set()
    for number, raw in enumerate(read_text(path).splitlines(), 1):
        if not raw or raw.startswith("#"):
            continue
        if "=" not in raw:
            raise StoreError(f"Invalid key=value line {number} in {path.name}.")
        key, value = raw.split("=", 1)
        # State/transaction keys are ASCII identifiers.  Treat case variants
        # as duplicates so the three adapters cannot disagree about whether
        # e.g. ``profile_version`` and ``PROFILE_VERSION`` are two fields.
        normalized_key = key.casefold()
        if not key or normalized_key in seen_keys:
            raise StoreError(f"Invalid or duplicate key on line {number} in {path.name}.")
        seen_keys.add(normalized_key)
        values[key] = value
    return values


def parse_state(path: Path) -> Dict[str, str]:
    return parse_key_values(path)


def write_state(path: Path, state: Dict[str, str]) -> None:
    order = (
        "schema_version",
        "profile_version",
        "progress_version",
        "capture_mode",
        "created_at",
        "updated_at",
        "last_confirmed_at",
        "next_review_at",
        "review_stage",
        "last_interview_at",
        "last_session_id",
        "last_turn_id",
        "last_capture_disclosed_at",
        "last_capture_disclosed_mode",
    )
    keys = [key for key in order if key in state] + sorted(key for key in state if key not in order)
    atomic_write(path, "".join(f"{key}={state.get(key, '')}\n" for key in keys))


def valid_iso8601(value: str, allow_empty: bool = True) -> bool:
    if not value:
        return allow_empty
    # State timestamps are stored in one canonical UTC form so all adapters
    # accept/reject the same values (and never mistake a local offset for UTC).
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", value):
        return False
    try:
        datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return False
    return True


def is_positive_decimal(value: str) -> bool:
    """Return whether a version uses the canonical positive decimal form."""
    return bool(POSITIVE_DECIMAL.fullmatch(value))


def compare_decimal(left: str, right: str) -> int:
    """Compare canonical positive decimal strings without host-size limits."""
    if not is_positive_decimal(left) or not is_positive_decimal(right):
        raise StoreError("Version must be a positive decimal integer.")
    if len(left) != len(right):
        return -1 if len(left) < len(right) else 1
    return (left > right) - (left < right)


def increment_decimal(value: str) -> str:
    """Increment a canonical positive decimal string one digit at a time."""
    if not is_positive_decimal(value):
        raise StoreError("Version must be a positive decimal integer.")
    digits = list(value)
    carry = 1
    for index in range(len(digits) - 1, -1, -1):
        if not carry:
            break
        if digits[index] == "9":
            digits[index] = "0"
        else:
            digits[index] = str(ord(digits[index]) - ord("0") + 1)
            carry = 0
    if carry:
        digits.insert(0, "1")
    return "".join(digits)


_held_locks: dict[str, int] = {}


@contextmanager
def store_lock(root: Path):
    """Take an atomic per-space lock for every read/modify/write operation."""
    key = str(root)
    # Read-only validation/status of a not-yet-created space must retain its
    # structured "root does not exist" response; do not create a lock
    # directory as a side effect of that probe.
    if not root.exists():
        yield
        return
    if key in _held_locks:
        _held_locks[key] += 1
        try:
            yield
        finally:
            _held_locks[key] -= 1
        return
    lock = root / LOCK_DIR
    try:
        lock.mkdir()
    except FileExistsError as exc:
        raise StoreError("Profile space is busy; retry after the active operation finishes.") from exc
    except OSError as exc:
        raise StoreError(f"Cannot acquire profile lock: {exc}") from exc
    _held_locks[key] = 1
    try:
        atomic_write(lock / "owner", f"pid={os.getpid()}\nstarted_at={now_utc()}\n")
        yield
    finally:
        _held_locks.pop(key, None)
        try:
            (lock / "owner").unlink()
        except FileNotFoundError:
            pass
        try:
            lock.rmdir()
        except FileNotFoundError:
            pass
        except OSError:
            # Leave a visible lock rather than recursively deleting anything
            # that another process may have placed there.
            pass


def locked(function):
    """Decorate a public operation with the re-entrant profile lock."""
    def wrapped(root: Path, *args, **kwargs):
        with store_lock(root):
            return function(root, *args, **kwargs)

    wrapped.__name__ = function.__name__
    wrapped.__doc__ = function.__doc__
    return wrapped


def effective_progress_version(state: Dict[str, str]) -> str:
    return state.get("progress_version", "1")


def effective_progress_version_for_root(root: Path, state: Dict[str, str]) -> str:
    """Return the progress version for both schema shapes.

    Schema 1 did not require a state cursor, so a legacy progress document
    may be the only authoritative version.  Use it when present; otherwise
    retain the schema-1 default of 1.  Schema 2 always uses the state field.
    """
    version = effective_progress_version(state)
    if state.get("schema_version") == "1" and "progress_version" not in state:
        progress_path = root / "访谈进度.md"
        if not progress_path.is_file():
            return version
        parsed, issues = progress_version_from_content(read_text(progress_path))
        if not issues and parsed is not None:
            return parsed
    return version


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
    issues.extend(f"Missing state key: {key}" for key in sorted(required - state.keys()))
    if state.get("schema_version") not in {"1", "2"}:
        issues.append("schema_version must be 1 or 2")
    if state.get("schema_version") == "2":
        for key in ("progress_version", "last_session_id", "last_turn_id"):
            if key not in state:
                issues.append(f"Missing state key: {key}")
    for key in ("profile_version", "progress_version"):
        if key not in state and key == "progress_version" and state.get("schema_version") == "1":
            continue
        if not is_positive_decimal(str(state.get(key, ""))):
            issues.append(f"{key} must be a positive integer")
    if state.get("capture_mode") not in CAPTURE_MODES:
        issues.append("capture_mode must be auto-stage, prompt, or explicit")
    if state.get("review_stage") not in REVIEW_STAGES:
        issues.append("review_stage must be baseline, first-review, or stable")
    if state.get("review_stage") == "first-review" and not state.get("next_review_at"):
        issues.append("first-review requires next_review_at")
    for key in ("created_at", "updated_at"):
        if key in state and not valid_iso8601(state[key], allow_empty=False):
            issues.append(f"{key} must be ISO 8601")
    for key in ("last_confirmed_at", "next_review_at", "last_interview_at", "last_capture_disclosed_at"):
        if key in state and not valid_iso8601(state[key]):
            issues.append(f"{key} must be empty or ISO 8601")
    if "last_capture_disclosed_mode" in state and state["last_capture_disclosed_mode"] not in {"", *CAPTURE_MODES}:
        issues.append("last_capture_disclosed_mode must be empty or a capture mode")
    # The mode field was added after schema-2 was already in use.  A legacy
    # timestamp without it remains readable, but it cannot satisfy the stage
    # gate until the host records a fresh disclosure for the current mode.
    return issues


def one_match(pattern: str, content: str, label: str) -> tuple[str | None, list[str]]:
    matches = re.findall(pattern, content, flags=re.MULTILINE)
    if len(matches) != 1:
        return None, [f"{label} must appear exactly once"]
    return matches[0], []


def validate_profile_content(content: str, expected_version: str | None = None) -> list[str]:
    issues: list[str] = []
    if not content.startswith("# 个人全景档案\n"):
        issues.append("Profile must start with # 个人全景档案")
    raw_version, found = one_match(r"^- 资料版本：([1-9][0-9]*)$", content, "资料版本 metadata")
    issues.extend(found)
    _, found = one_match(r"^- 最近确认时间：(.+)$", content, "最近确认时间 metadata")
    issues.extend(found)
    if raw_version is not None and expected_version is not None and raw_version != expected_version:
        issues.append(f"Profile version {raw_version} does not match state version {expected_version}")
    for heading in PROFILE_SECTIONS:
        if len(re.findall(rf"(?m)^{re.escape(heading)}$", content)) != 1:
            issues.append(f"Missing or duplicate profile section: {heading[3:]}")
    return issues


def progress_version_from_content(content: str) -> tuple[str | None, list[str]]:
    headers = re.findall(r"(?m)^- 进度版本：.*$", content)
    matches = re.findall(r"(?m)^- 进度版本：([1-9][0-9]*)$", content)
    if len(headers) > 1:
        return None, ["进度版本 metadata must appear at most once"]
    if headers and not matches:
        return None, ["进度版本 metadata must be a positive integer"]
    if not matches:
        return None, []
    if len(matches) != 1:
        return None, ["进度版本 metadata must appear at most once"]
    return matches[0], []


def validate_progress_content(content: str, expected_version: str | None, require_version: bool) -> list[str]:
    issues: list[str] = []
    if not content.startswith("# 访谈进度\n"):
        issues.append("Interview progress must start with # 访谈进度")
    version, found = progress_version_from_content(content)
    issues.extend(found)
    if require_version and version is None:
        issues.append("Missing progress metadata: 进度版本")
    if version is not None and expected_version is not None and version != expected_version:
        issues.append(f"Progress version {version} does not match state version {expected_version}")
    for heading in PROGRESS_SECTIONS:
        if len(re.findall(rf"(?m)^{re.escape(heading)}$", content)) != 1:
            issues.append(f"Missing or duplicate progress section: {heading[3:]}")
    return issues


def validate_log_content(content: str, profile_version: str) -> list[str]:
    issues: list[str] = []
    raw_headings = re.findall(r"(?m)^## R([0-9]+) · ", content)
    headings = [value for value in raw_headings if is_positive_decimal(value)]
    if len(headings) != len(raw_headings):
        issues.append("Iteration log versions must be canonical positive decimals")
    if len(headings) != len(set(headings)):
        issues.append("Iteration log contains duplicate version headings")
    if any(compare_decimal(left, right) > 0 for left, right in zip(headings, headings[1:])):
        issues.append("Iteration log versions must be ascending")
    if compare_decimal(profile_version, "1") > 0 and profile_version not in headings:
        issues.append(f"Iteration log is missing version R{profile_version}")
    return issues


def validate_pending_content(content: str) -> list[str]:
    ids = re.findall(r"(?m)^## (C-[0-9TZ-]+)\s*$", content)
    return ["Pending candidates contain duplicate ids"] if len(ids) != len(set(ids)) else []


def permission_issues(root: Path) -> list[str]:
    if os.name == "nt" or not root.exists():
        return []
    issues: list[str] = []
    if root.stat().st_mode & 0o077:
        issues.append("Profile root permissions must not grant group or other access")
    for name in FILES + (STATE_FILE,):
        path = root / name
        if path.is_file() and path.stat().st_mode & 0o077:
            issues.append(f"Unsafe file permissions: {name}")
    return issues


def _init_space_unlocked(root: Path, confirmed: bool) -> dict:
    require_confirmed(confirmed)
    root_created = not root.exists()
    root.mkdir(parents=True, exist_ok=True)
    if root_created:
        secure_directory(root)
    template_root = Path(__file__).resolve().parents[1] / "assets" / "profile-templates"
    created: list[str] = []
    for directory in DIRS:
        target = root / directory
        if not target.exists():
            target.mkdir(parents=True)
            secure_directory(target)
            created.append(directory + "/")
    for name in FILES:
        target = root / name
        if not target.exists():
            # Read through the UTF-8 helper and write atomically so every
            # adapter materializes templates with canonical LF newlines.
            atomic_write(target, read_text(template_root / name))
            secure_file(target)
            created.append(name)
    state_path = root / STATE_FILE
    if not state_path.exists():
        current = now_utc()
        write_state(
            state_path,
            {
                "schema_version": "2",
                "profile_version": "1",
                "progress_version": "1",
                "capture_mode": "prompt",
                "created_at": current,
                "updated_at": current,
                "last_confirmed_at": "",
                "next_review_at": "",
                "review_stage": "baseline",
                "last_interview_at": "",
                "last_session_id": "",
                "last_turn_id": "",
                "last_capture_disclosed_at": "",
                "last_capture_disclosed_mode": "",
            },
        )
        created.append(STATE_FILE)
    return {"ok": True, "command": "init", "root": str(root), "created": created}


def init_space(root: Path, confirmed: bool) -> dict:
    """Initialize a space while serializing creation with other writers."""
    require_confirmed(confirmed)
    root_created = not root.exists()
    root.mkdir(parents=True, exist_ok=True)
    if root_created:
        secure_directory(root)
    with store_lock(root):
        return _init_space_unlocked(root, True)


@locked
def validate_space(root: Path, ignore_transaction: bool = False) -> Tuple[dict, int]:
    issues: list[str] = []
    state: Dict[str, str] | None = None
    if not root.is_dir():
        issues.append("Root directory does not exist")
    else:
        if (root / TRANSACTION_FILE).exists() and not ignore_transaction:
            issues.append("Interrupted transaction exists; run recover --confirmed --root <authorized-root>")
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
                state = parse_state(state_path)
                issues.extend(validate_state(state))
            except StoreError as exc:
                issues.append(str(exc))
        if state is not None and not validate_state(state):
            profile_version = state["profile_version"]
            progress_version = effective_progress_version_for_root(root, state)
            try:
                issues.extend(validate_profile_content(read_text(root / "个人全景档案.md"), profile_version))
                issues.extend(
                    validate_progress_content(
                        read_text(root / "访谈进度.md"),
                        progress_version,
                        state.get("schema_version") == "2",
                    )
                )
                issues.extend(validate_log_content(read_text(root / "迭代日志.md"), profile_version))
                issues.extend(validate_pending_content(read_text(root / "待确认信息.md")))
            except StoreError as exc:
                issues.append(str(exc))
        issues.extend(permission_issues(root))
    payload = {"ok": not issues, "command": "validate", "root": str(root), "issues": issues}
    return payload, 0 if not issues else 1


def require_valid(root: Path) -> Dict[str, str]:
    payload, code = validate_space(root)
    if code:
        raise StoreError("Invalid profile space: " + "; ".join(payload["issues"]))
    return parse_state(root / STATE_FILE)


def progress_summary(content: str) -> dict:
    def field(pattern: str) -> str:
        match = re.search(pattern, content, flags=re.MULTILINE)
        return match.group(1).strip() if match else ""

    next_match = re.search(r"(?ms)^## 下次问题\s*\n+(.+?)(?=^## |\Z)", content)
    next_question = ""
    if next_match:
        next_question = next((line.strip() for line in next_match.group(1).splitlines() if line.strip()), "")
    return {
        "current_stage": field(r"^- 当前阶段：(.+)$"),
        "last_interview_at": field(r"^- 最近正式访谈时间：(.+)$"),
        "next_question": next_question,
    }


def cleanup_transaction_backups(root: Path, values: Dict[str, str]) -> None:
    for key in ("profile_backup", "log_backup", "state_backup", "progress_backup"):
        relative = values.get(key)
        if not relative:
            continue
        backup = transaction_target(root, relative)
        if backup.is_file():
            backup.unlink()


def finish_transaction(root: Path) -> None:
    marker = root / TRANSACTION_FILE
    values = parse_key_values(marker)
    cleanup_transaction_backups(root, values)
    marker.unlink()


@locked
def status(root: Path) -> Tuple[dict, int]:
    payload, code = validate_space(root)
    if code:
        payload["command"] = "status"
        return payload, code
    state = parse_state(root / STATE_FILE)
    pending = len(re.findall(r"(?m)^## C-[0-9TZ-]+\s*$", read_text(root / "待确认信息.md")))
    progress = progress_summary(read_text(root / "访谈进度.md"))
    progress["current_stage"] = progress["current_stage"] or {
        "baseline": "基线访谈",
        "first-review": "首次回访",
        "stable": "稳定维护",
    }[state["review_stage"]]
    progress["last_interview_at"] = (
        progress["last_interview_at"]
        or state.get("last_interview_at", "")
        or (state.get("updated_at", "") if state.get("last_turn_id") else "")
    )
    progress_content = read_text(root / "访谈进度.md")
    baseline_remaining, long_term_backlog = progress_backlog(progress_content)
    baseline_split_unknown = state.get("schema_version") != "2" or not progress_buckets_present(progress_content)
    if baseline_split_unknown:
        baseline_remaining = ["legacy-unclassified（需先完成基线/长期分组）"]
    return {
        "ok": True,
        "command": "status",
        "root": str(root),
        "profile_version": state["profile_version"],
        "progress_version": effective_progress_version_for_root(root, state),
        "capture_mode": state["capture_mode"],
        "capture_strategy": CAPTURE_STRATEGIES[state["capture_mode"]],
        "last_capture_disclosed_at": state.get("last_capture_disclosed_at", ""),
        "last_capture_disclosed_mode": state.get("last_capture_disclosed_mode", ""),
        "review_stage": state["review_stage"],
        "last_confirmed_at": state["last_confirmed_at"],
        "next_review_at": state["next_review_at"],
        "last_session_id": state.get("last_session_id", ""),
        "last_turn_id": state.get("last_turn_id", ""),
        "pending_candidates": pending,
        "baseline_required_remaining": baseline_remaining,
        "baseline_closure_blocked": bool(baseline_remaining),
        "baseline_split_unknown": baseline_split_unknown,
        "long_term_backlog": long_term_backlog,
        "progress": progress,
    }, 0


def progress_backlog(content: str) -> tuple[list[str], list[str]]:
    buckets: dict[str, list[str]] = {"baseline": [], "long": []}
    bucket: str | None = None
    for line in content.splitlines():
        if line.strip() == "### 基线必答（阻塞基线收口）":
            bucket = "baseline"
        elif line.strip() == "### 可长期补充（不阻塞基线收口）":
            bucket = "long"
        elif line.startswith("### ") or line.startswith("## "):
            bucket = None
        elif bucket and line.startswith("- "):
            item = line[2:].strip()
            if item:
                buckets[bucket].append(item)
    return buckets["baseline"], buckets["long"]


def progress_buckets_present(content: str) -> bool:
    return all(
        len(re.findall(rf"(?m)^{re.escape(heading)}$", content)) == 1
        for heading in ("### 基线必答（阻塞基线收口）", "### 可长期补充（不阻塞基线收口）")
    )


def validate_review_time(value: str) -> str:
    if value in {"", "none"}:
        return ""
    if not valid_iso8601(value, allow_empty=False):
        raise StoreError("--next-review-at must be ISO 8601 or none.")
    return value


@locked
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
    new_capture_mode = state["capture_mode"]
    new_review_stage = state["review_stage"]
    new_next_review_at = state["next_review_at"]
    if capture_mode is not None:
        if capture_mode not in CAPTURE_MODES:
            raise StoreError("--capture-mode must be auto-stage, prompt, or explicit.")
        new_capture_mode = capture_mode
    if review_stage is not None:
        if review_stage not in REVIEW_STAGES:
            raise StoreError("--review-stage must be baseline, first-review, or stable.")
        new_review_stage = review_stage
    if next_review_at is not None:
        new_next_review_at = validate_review_time(next_review_at)
    # Validate the proposed final tuple, not just the individual argument.
    # This also rejects clearing an existing date while remaining in
    # first-review, without touching the on-disk state on failure.
    if new_review_stage == "first-review" and not new_next_review_at:
        if state["review_stage"] != "first-review":
            raise StoreError("Entering first-review requires --next-review-at.")
        raise StoreError("first-review requires --next-review-at.")
    state["capture_mode"] = new_capture_mode
    state["review_stage"] = new_review_stage
    state["next_review_at"] = new_next_review_at
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


@locked
def record_disclosure(root: Path, confirmed: bool, capture_mode: str | None = None) -> dict:
    """Record that the host has just disclosed the effective capture policy.

    The host is responsible for actually reading ``status`` and showing the
    policy to the user; this command only attests that event in the local
    state file.  It deliberately leaves ``capture_mode`` unchanged.
    """
    require_confirmed(confirmed)
    state = require_valid(root)
    if capture_mode is not None:
        if capture_mode not in CAPTURE_MODES:
            raise StoreError("--capture-mode must be auto-stage, prompt, or explicit.")
        if capture_mode != state["capture_mode"]:
            raise StoreError("--capture-mode does not match the current capture policy.")
    current = now_utc()
    state["last_capture_disclosed_at"] = current
    state["last_capture_disclosed_mode"] = state["capture_mode"]
    state["updated_at"] = current
    write_state(root / STATE_FILE, state)
    return {
        "ok": True,
        "command": "record-disclosure",
        "root": str(root),
        "capture_mode": state["capture_mode"],
        "capture_strategy": CAPTURE_STRATEGIES[state["capture_mode"]],
        "last_capture_disclosed_at": current,
        "last_capture_disclosed_mode": state["capture_mode"],
    }


@locked
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


@locked
def stage_candidate(root: Path, input_path: Path, kind: str | None, source: str | None, confirmed: bool) -> dict:
    require_confirmed(confirmed)
    state = require_valid(root)
    if state["capture_mode"] != "explicit":
        if (
            not state.get("last_capture_disclosed_at")
            or state.get("last_capture_disclosed_mode") != state["capture_mode"]
        ):
            raise StoreError(
                "Capture policy must be disclosed (with matching mode) before staging candidates."
            )
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


def update_profile_header(content: str, version: str, confirmed_at: str) -> str:
    content, version_count = re.subn(r"(?m)^- 资料版本：.*$", f"- 资料版本：{version}", content, count=1)
    content, time_count = re.subn(r"(?m)^- 最近确认时间：.*$", f"- 最近确认时间：{confirmed_at}", content, count=1)
    if version_count != 1 or time_count != 1:
        raise StoreError("Candidate profile must contain 资料版本 and 最近确认时间 metadata lines.")
    return content


def update_progress_header(content: str, version: str) -> str:
    if re.search(r"(?m)^- 进度版本：", content):
        content, count = re.subn(r"(?m)^- 进度版本：.*$", f"- 进度版本：{version}", content, count=1)
        if count != 1:
            raise StoreError("Progress metadata is invalid.")
        return content
    return content.replace("# 访谈进度\n", f"# 访谈进度\n\n- 进度版本：{version}", 1)


def copy_unique(source: Path, directory: Path, name: str) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    secure_directory(directory)
    target = directory / name
    counter = 1
    while target.exists():
        target = directory / f"{Path(name).stem}-{counter}{Path(name).suffix}"
        counter += 1
    shutil.copyfile(source, target)
    secure_file(target)
    return target


def relative_to_root(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError as exc:
        raise StoreError(f"Transaction path escapes profile root: {path}") from exc


def begin_transaction(root: Path, values: Dict[str, str]) -> None:
    marker = root / TRANSACTION_FILE
    values = {"schema_version": "1", **values}
    content = "".join(f"{key}={value}\n" for key, value in values.items())
    # Create the marker exclusively.  A separate exists() check followed by
    # replace() lets two writers both pass the check and strand one set of
    # transaction backups.  The profile lock normally serializes writers,
    # while CreateNew keeps the invariant true even for a direct probe.
    try:
        with marker.open("x", encoding="utf-8", newline="\n") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        secure_file(marker)
    except FileExistsError as exc:
        raise StoreError("Interrupted transaction exists; run recover --confirmed --root <authorized-root>.") from exc
    except Exception:
        try:
            marker.unlink()
        except OSError:
            pass
        raise


def transaction_target(root: Path, relative: str) -> Path:
    target = (root / relative).resolve()
    try:
        target.relative_to(root.resolve())
    except ValueError as exc:
        raise StoreError("Transaction backup path escapes profile root.") from exc
    return target


def validate_transaction_marker(values: Dict[str, str]) -> None:
    """Reject incomplete/unknown transaction markers before any restore.

    The marker is the recovery contract, so treating a missing field as an
    optional value can make recovery silently commit only part of a previous
    operation.  Required fields depend on the operation kind; ``apply`` may
    omit ``progress_backup`` only when no legacy-progress migration occurred.
    """
    if values.get("schema_version") != "1":
        raise StoreError("Transaction marker schema_version must be 1.")
    kind = values.get("kind")
    required = {
        "apply": ("profile_backup", "log_backup", "state_backup"),
        "record-turn": ("progress_backup", "state_backup", "record_path", "record_created"),
    }.get(kind)
    if required is None:
        if not kind:
            raise StoreError("Missing transaction marker field: kind")
        raise StoreError(f"Unknown transaction marker kind: {kind}")
    missing = [key for key in required if not values.get(key)]
    if missing:
        raise StoreError("Missing transaction marker field: " + ", ".join(missing))
    if kind == "record-turn" and values["record_created"] not in {"true", "false"}:
        raise StoreError("Transaction marker record_created must be true or false.")


@locked
def recover_transaction(root: Path, confirmed: bool) -> dict:
    require_confirmed(confirmed)
    marker = root / TRANSACTION_FILE
    if not marker.is_file():
        raise StoreError("No interrupted transaction exists.")
    values = parse_key_values(marker)
    validate_transaction_marker(values)
    mappings = {
        "profile_backup": root / "个人全景档案.md",
        "log_backup": root / "迭代日志.md",
        "state_backup": root / STATE_FILE,
        "progress_backup": root / "访谈进度.md",
    }
    # Preflight every referenced backup and path before restoring any target;
    # a malformed/incomplete marker must not leave a half-restored tree.
    restore_plan: list[tuple[Path, Path, str]] = []
    for key, target in mappings.items():
        relative = values.get(key)
        if relative:
            backup = transaction_target(root, relative)
            if not backup.is_file():
                raise StoreError(f"Missing transaction backup: {relative}")
            restore_plan.append((target, backup, relative))
    record_path = values.get("record_path")
    record_target = transaction_target(root, record_path) if record_path else None
    restored: list[str] = []
    for target, backup, _ in restore_plan:
        atomic_write(target, read_text(backup))
        restored.append(target.name)
    if record_target is not None and values["record_created"] == "true":
        if record_target.is_file():
            record_target.unlink()
    # Keep the marker and every backup until the restored tree has passed
    # validation.  A failed validation must leave enough material for a
    # second, explicit recovery attempt; deleting first would turn a
    # recoverable interruption into an unrecoverable partial restore.
    payload, code = validate_space(root, ignore_transaction=True)
    if code:
        raise StoreError("Recovery completed but profile space is invalid: " + "; ".join(payload["issues"]))
    cleanup_transaction_backups(root, values)
    marker.unlink()
    return {"ok": True, "command": "recover", "root": str(root), "restored": restored}


def rollback_after_failure(root: Path, original: Exception) -> None:
    try:
        recover_transaction(root, True)
    except Exception as rollback_error:
        raise StoreError(
            f"Operation failed: {original}. Automatic rollback failed: {rollback_error}. Run recover --confirmed --root <authorized-root>."
        ) from original
    raise StoreError(f"Operation failed and was rolled back: {original}") from original


def validate_summary(summary: str) -> None:
    invalid = [
        field
        for field in SUMMARY_FIELDS
        if len(re.findall(rf"(?m)^- {re.escape(field)}：.+$", summary)) != 1
    ]
    if invalid:
        raise StoreError("Update summary requires exactly one of each field: " + ", ".join(invalid))
    type_match = re.search(r"(?m)^- 更新类型：(.+)$", summary)
    update_type = type_match.group(1).strip().rstrip("。.;；") if type_match else ""
    if update_type not in UPDATE_TYPES:
        raise StoreError("Update summary contains an invalid update type.")


def canonical_profile(content: str) -> str:
    content = re.sub(r"(?m)^- 资料版本：.*$", "- 资料版本：<version>", content)
    return re.sub(r"(?m)^- 最近确认时间：.*$", "- 最近确认时间：<time>", content).strip()


@locked
def apply_profile(
    root: Path,
    input_path: Path,
    summary_path: Path,
    expected_version: str,
    confirmed: bool,
    simulate_failure: bool = False,
) -> dict:
    require_confirmed(confirmed)
    state = require_valid(root)
    current_version = state["profile_version"]
    if expected_version != current_version:
        raise StoreError(f"Version conflict: expected {expected_version}, current {current_version}.")
    candidate = read_text(input_path).strip() + "\n"
    summary = read_text(summary_path).strip()
    if not candidate.strip():
        raise StoreError("Candidate profile is empty.")
    if not summary:
        raise StoreError("Update summary is empty.")
    issues = validate_profile_content(candidate)
    if issues:
        raise StoreError("Invalid candidate profile: " + "; ".join(issues))
    validate_summary(summary)
    profile_path = root / "个人全景档案.md"
    current_profile = read_text(profile_path)
    if canonical_profile(current_profile) == canonical_profile(candidate):
        raise StoreError("Candidate profile has no content changes.")
    current = now_utc()
    new_version = increment_decimal(current_version)
    candidate = update_profile_header(candidate, new_version, current)
    file_stamp = stamp()
    history = copy_unique(profile_path, root / "历史版本", f"{file_stamp}-v{current_version}-个人全景档案.md")
    backup = copy_unique(profile_path, root / ".backups" / "profile", f"{file_stamp}-v{current_version}-个人全景档案.md")
    transaction_dir = root / ".backups" / "transactions"
    log_path = root / "迭代日志.md"
    progress_path = root / "访谈进度.md"
    state_path = root / STATE_FILE
    # A schema-1 progress file was allowed to omit its version header.  Make
    # the smallest compatible upgrade in the same transaction as the profile
    # write so the resulting schema-2 space passes strict validation.
    progress_original = read_text(progress_path)
    migration_progress_version = effective_progress_version(state)
    progress_candidate = progress_original
    if state.get("schema_version") != "2":
        parsed_progress_version, progress_issues = progress_version_from_content(progress_original)
        if progress_issues:
            raise StoreError("Invalid legacy progress metadata: " + "; ".join(progress_issues))
        if "progress_version" not in state and parsed_progress_version is not None:
            migration_progress_version = parsed_progress_version
        if parsed_progress_version is None:
            progress_candidate = update_progress_header(progress_original, migration_progress_version)
    log_backup = copy_unique(log_path, transaction_dir, f"{file_stamp}-v{current_version}-迭代日志.md")
    state_backup = copy_unique(state_path, transaction_dir, f"{file_stamp}-v{current_version}-hello-state")
    progress_backup = None
    if progress_candidate != progress_original:
        progress_backup = copy_unique(progress_path, transaction_dir, f"{file_stamp}-v{current_version}-访谈进度.md")
    transaction_values = {
        "kind": "apply",
        "profile_backup": relative_to_root(root, backup),
        "log_backup": relative_to_root(root, log_backup),
        "state_backup": relative_to_root(root, state_backup),
    }
    if progress_backup is not None:
        transaction_values["progress_backup"] = relative_to_root(root, progress_backup)
    try:
        begin_transaction(root, transaction_values)
    except Exception:
        # These transaction-only copies are not useful when the marker could
        # not be claimed (for example, a concurrent writer won the race).
        for transaction_backup in (log_backup, state_backup, progress_backup):
            if transaction_backup is not None:
                try:
                    transaction_backup.unlink()
                except FileNotFoundError:
                    pass
        raise
    try:
        atomic_write(profile_path, candidate)
        if simulate_failure:
            raise StoreError("simulated failure after profile write")
        log = read_text(log_path).replace("\n当前没有正式迭代。\n", "\n").rstrip()
        entry = (
            f"\n\n## R{new_version} · {current}\n\n"
            f"- 资料版本：{new_version}\n"
            "- 确认状态：用户已确认\n"
            f"- 历史快照：`历史版本/{history.name}`\n\n"
            f"{summary}\n"
        )
        atomic_write(log_path, log + entry)
        if progress_candidate != progress_original:
            atomic_write(progress_path, progress_candidate)
        # The first mutating operation on a schema-1 space upgrades the
        # state shape.  Missing schema-2 cursor fields are intentionally
        # initialized rather than inferred from unrelated files.
        state["schema_version"] = "2"
        state.setdefault("progress_version", str(migration_progress_version))
        state.setdefault("last_session_id", "")
        state.setdefault("last_turn_id", "")
        state.setdefault("last_capture_disclosed_at", "")
        state["profile_version"] = str(new_version)
        state["updated_at"] = current
        state["last_confirmed_at"] = current
        write_state(state_path, state)
        payload, code = validate_space(root, ignore_transaction=True)
        if code:
            raise StoreError("Post-write validation failed: " + "; ".join(payload["issues"]))
    except Exception as exc:
        rollback_after_failure(root, exc)
    finish_transaction(root)
    return {
        "ok": True,
        "command": "apply",
        "root": str(root),
        "old_version": current_version,
        "profile_version": new_version,
        "history": str(history),
        "backup": str(backup),
    }


@locked
def record_turn(
    root: Path,
    input_path: Path,
    progress_input: Path,
    session_id: str,
    turn_id: str,
    expected_progress_version: str,
    confirmed: bool,
    simulate_failure: bool = False,
) -> dict:
    require_confirmed(confirmed)
    state = require_valid(root)
    if not SESSION_ID.fullmatch(session_id) or not SAFE_ID.fullmatch(turn_id):
        raise StoreError("session-id must start with YYYY-MM-DD; ids may only use ASCII letters, digits, dot, underscore, or hyphen.")
    body = read_text(input_path).strip()
    if not body:
        raise StoreError("Turn input is empty.")
    year = session_id[:4]
    record_path = root / "原始访谈" / year / session_id / f"{turn_id}.md"
    # The durable idempotency key is the immutable turn file itself, not the
    # mutable ``last_*`` cursor.  A retry can arrive after later turns have
    # advanced the cursor (or after another process resumed the session), so
    # always consult the original record before applying the progress CAS.
    if record_path.exists():
        if read_text(record_path).strip() != body:
            raise StoreError("Idempotent turn retry has different content.")
        return {
            "ok": True,
            "command": "record-turn",
            "root": str(root),
            "session_id": session_id,
            "turn_id": turn_id,
            "record": str(record_path),
            "created": False,
            "idempotent": True,
            "progress_version": effective_progress_version_for_root(root, state),
            **session_termination(root, session_id),
        }
    current_progress_version = effective_progress_version_for_root(root, state)
    if expected_progress_version != current_progress_version:
        raise StoreError(
            f"Progress version conflict: expected {expected_progress_version}, current {current_progress_version}."
        )
    progress_candidate = read_text(progress_input).strip() + "\n"
    issues = validate_progress_content(progress_candidate, None, False)
    if issues:
        raise StoreError("Invalid progress input: " + "; ".join(issues))
    new_progress_version = increment_decimal(current_progress_version)
    progress_candidate = update_progress_header(progress_candidate, new_progress_version)
    record_created = not record_path.exists()
    file_stamp = stamp()
    transaction_dir = root / ".backups" / "transactions"
    progress_path = root / "访谈进度.md"
    state_path = root / STATE_FILE
    progress_backup = copy_unique(progress_path, transaction_dir, f"{file_stamp}-p{current_progress_version}-访谈进度.md")
    state_backup = copy_unique(state_path, transaction_dir, f"{file_stamp}-p{current_progress_version}-hello-state")
    try:
        begin_transaction(
            root,
            {
                "kind": "record-turn",
                "progress_backup": relative_to_root(root, progress_backup),
                "state_backup": relative_to_root(root, state_backup),
                "record_path": relative_to_root(root, record_path),
                "record_created": "true" if record_created else "false",
            },
        )
    except Exception:
        for transaction_backup in (progress_backup, state_backup):
            try:
                transaction_backup.unlink()
            except FileNotFoundError:
                pass
        raise
    try:
        if record_created:
            atomic_write(record_path, body + "\n")
            secure_directory(record_path.parent)
            secure_directory(record_path.parent.parent)
        atomic_write(progress_path, progress_candidate)
        state["schema_version"] = "2"
        state["progress_version"] = str(new_progress_version)
        state["last_session_id"] = session_id
        state["last_turn_id"] = turn_id
        current = now_utc()
        state["updated_at"] = current
        state["last_interview_at"] = current
        write_state(state_path, state)
        if simulate_failure:
            raise StoreError("simulated failure after state write")
        payload, code = validate_space(root, ignore_transaction=True)
        if code:
            raise StoreError("Post-write validation failed: " + "; ".join(payload["issues"]))
    except Exception as exc:
        rollback_after_failure(root, exc)
    finish_transaction(root)
    return {
        "ok": True,
        "command": "record-turn",
        "root": str(root),
        "session_id": session_id,
        "turn_id": turn_id,
        "record": str(record_path),
        "created": record_created,
        "idempotent": False,
        "progress_version": new_progress_version,
        **session_termination(root, session_id),
    }


def session_termination(root: Path, session_id: str) -> dict:
    reasons: list[str] = []
    today = now_utc()[:10]
    if session_id[:10] != today:
        reasons.append("cross-natural-day")
    session_dir = root / "原始访谈" / session_id[:4] / session_id
    if session_dir.is_dir() and len(list(session_dir.glob("*.md"))) > 50:
        reasons.append("over-50-turns")
    return {
        "new_session_required": bool(reasons),
        "session_termination_reasons": reasons,
        "session_termination_notice": "请开启新会话" if reasons else "",
    }


@locked
def withdraw_candidate(root: Path, candidate_id: str, confirmed: bool) -> dict:
    require_confirmed(confirmed)
    state = require_valid(root)
    if not CANDIDATE_ID.fullmatch(candidate_id):
        raise StoreError("Invalid candidate id.")
    pending_path = root / "待确认信息.md"
    content = read_text(pending_path)
    pattern = re.compile(rf"(?ms)^## {re.escape(candidate_id)}\s*\n.*?(?=^## C-[0-9TZ-]+\s*$|\Z)")
    match = pattern.search(content)
    if not match:
        raise StoreError(f"Candidate not found: {candidate_id}")
    trash = root / ".trash" / "candidates" / f"{candidate_id}.md"
    trash.parent.mkdir(parents=True, exist_ok=True)
    secure_directory(trash.parent)
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


def test_summary() -> str:
    return "\n".join(
        (
            "- 触发原因：自测。",
            "- 信息来源：隔离测试。",
            "- 更新类型：新增。",
            "- 更新位置：当前起点。",
            "- 更新摘要：验证存储事务。",
            "- 用户确认状态：自测确认。",
            "- 执行工具：hello self-test。",
        )
    ) + "\n"


def self_test() -> dict:
    assert serialize_json({"中文": "自测"}).encode("utf-8").decode("utf-8").startswith("{\"中文\"")
    saved_hello_home = os.environ.get("HELLO_HOME")
    os.environ["HELLO_HOME"] = str(Path(tempfile.gettempdir()) / "must-not-be-used")
    try:
        try:
            resolve_root("")
            raise AssertionError("an explicit empty --root fell back to HELLO_HOME")
        except StoreError:
            pass
    finally:
        if saved_hello_home is None:
            os.environ.pop("HELLO_HOME", None)
        else:
            os.environ["HELLO_HOME"] = saved_hello_home
    # Parser failures are part of the machine-facing contract: they must not
    # leak argparse usage text or a non-JSON stderr response.
    for probe_args, expected_command in (
        (["not-a-command"], "not-a-command"),
        (["status", "--unknown-option"], "status"),
        (["status", "--root", "--confirmed"], "status"),
        (["status", "--r", "C:/not-a-root"], "status"),
        (["status", "--root=C:/not-a-root"], "status"),
        (["status", "--root", "C:/one", "--root", "C:/two"], "status"),
        (["status", "--"], "status"),
        (["status", "--simulate-failure"], "status"),
    ):
        probe = subprocess.run(
            [sys.executable, str(Path(__file__).resolve()), *probe_args],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        assert probe.returncode == 2
        assert probe.stderr == b""
        probe_payload = json.loads(probe.stdout.decode("utf-8"))
        assert probe_payload["ok"] is False
        assert probe_payload["command"] == expected_command
        assert probe_payload["error"]
    with tempfile.TemporaryDirectory(prefix="hello-self-test-") as temporary:
        assert positive_integer("1") == "1"
        for invalid_version in ("0", "01", "+1", "-1"):
            try:
                positive_integer(invalid_version)
                raise AssertionError("non-canonical positive integer was accepted")
            except argparse.ArgumentTypeError:
                pass
        root = Path(temporary) / "中文 空格"
        try:
            init_space(root, False)
            raise AssertionError("confirmation guard did not fail")
        except StoreError:
            pass
        init_space(root, True)
        assert init_space(root, True)["created"] == []
        for name in FILES:
            assert b"\r" not in (root / name).read_bytes()
        malformed_marker = root / TRANSACTION_FILE
        atomic_write(
            malformed_marker,
            "schema_version=1\nkind=record-turn\nduplicate=x\nduplicate=y\n",
        )
        try:
            recover_transaction(root, True)
            raise AssertionError("malformed transaction marker was accepted")
        except StoreError:
            pass
        assert malformed_marker.exists()
        malformed_marker.unlink()
        atomic_write(
            malformed_marker,
            "schema_version=1\nPROFILE_VERSION=shadow\nprofile_version=1\n",
        )
        try:
            recover_transaction(root, True)
            raise AssertionError("case-variant transaction keys were accepted")
        except StoreError:
            pass
        assert malformed_marker.exists()
        malformed_marker.unlink()
        atomic_write(malformed_marker, "schema_version=1\nkind=apply\n")
        try:
            recover_transaction(root, True)
            raise AssertionError("incomplete apply transaction marker was accepted")
        except StoreError as exc:
            assert "Missing transaction marker field" in str(exc)
        assert malformed_marker.exists()
        malformed_marker.unlink()
        atomic_write(malformed_marker, "schema_version=1\nkind=record-turn\n")
        try:
            recover_transaction(root, True)
            raise AssertionError("incomplete record-turn transaction marker was accepted")
        except StoreError as exc:
            assert "Missing transaction marker field" in str(exc)
        assert malformed_marker.exists()
        malformed_marker.unlink()
        profile_before_missing_backup = (root / "个人全景档案.md").read_bytes()
        atomic_write(
            malformed_marker,
            "schema_version=1\nkind=apply\nprofile_backup=.backups/transactions/missing-profile.md\n",
        )
        try:
            recover_transaction(root, True)
            raise AssertionError("missing transaction backup was accepted")
        except StoreError:
            pass
        assert malformed_marker.exists()
        assert (root / "个人全景档案.md").read_bytes() == profile_before_missing_backup
        malformed_marker.unlink()
        payload, code = validate_space(root)
        assert code == 0, payload
        state = parse_state(root / STATE_FILE)
        assert state["capture_mode"] == "prompt"
        # A mutation must never silently follow HELLO_HOME when a caller
        # forgot to pass the intended isolated root.  This probe models the
        # review-agent failure mode and must leave the state byte-for-byte
        # unchanged.
        state_before_implicit_mutation = (root / STATE_FILE).read_bytes()
        implicit_env = os.environ.copy()
        implicit_env["HELLO_HOME"] = str(root)
        implicit_probe = subprocess.run(
            [sys.executable, str(Path(__file__).resolve()), "record-disclosure", "--confirmed"],
            env=implicit_env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        assert implicit_probe.returncode == 2
        assert implicit_probe.stderr == b""
        implicit_payload = json.loads(implicit_probe.stdout.decode("utf-8"))
        assert implicit_payload["ok"] is False
        assert "explicit --root" in implicit_payload["error"]
        assert (root / STATE_FILE).read_bytes() == state_before_implicit_mutation
        status_payload, status_code = status(root)
        assert status_code == 0
        assert status_payload["capture_strategy"] == "提示确认"
        assert status_payload["last_capture_disclosed_at"] == ""
        assert status_payload["last_capture_disclosed_mode"] == ""
        assert status_payload["baseline_closure_blocked"] is True
        assert status_payload["baseline_split_unknown"] is False
        assert status_payload["baseline_required_remaining"]
        assert status_payload["long_term_backlog"]
        # Version values stay exact across adapters, including values longer
        # than the host language's ordinary integer type.
        long_version = "9" * 40
        assert is_positive_decimal(long_version)
        assert increment_decimal(long_version) == "1" + "0" * 40
        assert compare_decimal(long_version, "1" + "0" * 40) < 0
        assert not valid_iso8601("2030-01-01T00:00:00+08:00", allow_empty=False)
        assert not valid_iso8601("2030-02-30T00:00:00Z", allow_empty=False)
        assert not valid_iso8601("2030-01-01T00:00:00z", allow_empty=False)
        state_with_leading_zero = dict(state)
        state_with_leading_zero["profile_version"] = "01"
        assert any("profile_version" in issue for issue in validate_state(state_with_leading_zero))
        profile_with_leading_zero = read_text(root / "个人全景档案.md").replace(
            "- 资料版本：1", "- 资料版本：01", 1
        )
        assert validate_profile_content(profile_with_leading_zero, None)
        progress_with_leading_zero = read_text(root / "访谈进度.md").replace(
            "- 进度版本：1", "- 进度版本：01", 1
        )
        assert validate_progress_content(progress_with_leading_zero, None, True)
        malformed_progress = read_text(root / "访谈进度.md").replace(
            "- 进度版本：1", "- 进度版本：abc", 1
        )
        assert validate_progress_content(malformed_progress, None, False)
        disclosed = record_disclosure(root, True, "prompt")
        assert disclosed["capture_mode"] == "prompt"
        assert valid_iso8601(disclosed["last_capture_disclosed_at"], allow_empty=False)
        assert disclosed["last_capture_disclosed_mode"] == "prompt"
        disclosed_state = parse_state(root / STATE_FILE)
        assert disclosed_state["capture_mode"] == "prompt"
        assert disclosed_state["last_capture_disclosed_at"] == disclosed["last_capture_disclosed_at"]
        assert disclosed_state["last_capture_disclosed_mode"] == "prompt"
        try:
            record_disclosure(root, True, "explicit")
            raise AssertionError("record-disclosure accepted a stale capture mode")
        except StoreError as exc:
            assert "does not match" in str(exc)
        assert parse_state(root / STATE_FILE) == disclosed_state
        disclosed_state["last_capture_disclosed_at"] = ""
        write_state(root / STATE_FILE, disclosed_state)
        state_path = root / STATE_FILE
        state_v2 = parse_state(state_path)
        state_v1 = dict(state_v2)
        state_v1["schema_version"] = "1"
        for key in ("progress_version", "last_session_id", "last_turn_id"):
            state_v1.pop(key, None)
        write_state(state_path, state_v1)
        legacy_status, legacy_code = status(root)
        assert legacy_code == 0
        assert legacy_status["baseline_split_unknown"] is True
        assert legacy_status["baseline_closure_blocked"] is True
        assert "legacy-unclassified" in legacy_status["baseline_required_remaining"][0]
        write_state(state_path, state_v2)
        progress_path = root / "访谈进度.md"
        progress_saved = read_text(progress_path)
        atomic_write(progress_path, progress_saved.replace("### 可长期补充（不阻塞基线收口）", "### 未分组主题"))
        missing_bucket_status, missing_bucket_code = status(root)
        assert missing_bucket_code == 0
        assert missing_bucket_status["baseline_split_unknown"] is True
        assert missing_bucket_status["baseline_closure_blocked"] is True
        assert "legacy-unclassified" in missing_bucket_status["baseline_required_remaining"][0]
        atomic_write(progress_path, progress_saved)
        candidate_note = root.parent / "candidate.md"
        candidate_note.write_text("用户完成了一个重要项目。\n", encoding="utf-8")
        lock_dir = root / LOCK_DIR
        lock_dir.mkdir()
        try:
            stage_candidate(root, candidate_note, "经历", "自测", True)
            raise AssertionError("stage ignored an active profile lock")
        except StoreError as exc:
            assert "busy" in str(exc).lower()
        finally:
            lock_dir.rmdir()
        record_disclosure(root, True, "prompt")
        staged = stage_candidate(root, candidate_note, "经历", "自测", True)
        disclosure_before_configure = parse_state(state_path).get("last_capture_disclosed_at", "")
        configured = configure_space(root, "auto-stage", None, None, True)
        assert configured["capture_mode"] == "auto-stage"
        assert parse_state(state_path).get("last_capture_disclosed_at", "") == disclosure_before_configure
        try:
            stage_candidate(root, candidate_note, "经历", "自测", True)
            raise AssertionError("stage accepted a policy without a matching disclosure")
        except StoreError as exc:
            assert "disclos" in str(exc).lower()
        record_disclosure(root, True, "auto-stage")
        profile_candidate = root.parent / "profile.md"
        profile_text = read_text(root / "个人全景档案.md").replace("尚未访谈。", "已完成一项自测。", 1)
        profile_candidate.write_text(profile_text, encoding="utf-8")
        summary = root.parent / "summary.md"
        summary.write_text(test_summary(), encoding="utf-8")
        legacy_apply_state = parse_state(state_path)
        legacy_apply_state["schema_version"] = "1"
        legacy_apply_state.pop("progress_version", None)
        legacy_apply_state.pop("last_session_id", None)
        legacy_apply_state.pop("last_turn_id", None)
        legacy_apply_state["legacy_marker"] = "keep"
        write_state(state_path, legacy_apply_state)
        legacy_progress = read_text(progress_path)
        atomic_write(progress_path, re.sub(r"(?m)^- 进度版本：.*\n", "", legacy_progress))
        try:
            apply_profile(root, profile_candidate, summary, "1", True, simulate_failure=True)
            raise AssertionError("simulated failure did not fail")
        except StoreError as exc:
            assert "rolled back" in str(exc)
        assert parse_state(root / STATE_FILE)["profile_version"] == "1"
        assert "- 进度版本：" not in read_text(progress_path)
        assert not (root / TRANSACTION_FILE).exists()
        applied = apply_profile(root, profile_candidate, summary, "1", True)
        assert applied["profile_version"] == "2"
        migrated_state = parse_state(state_path)
        assert migrated_state["schema_version"] == "2"
        assert migrated_state["progress_version"] == "1"
        assert migrated_state["last_session_id"] == ""
        assert migrated_state["last_turn_id"] == ""
        assert migrated_state["legacy_marker"] == "keep"
        assert "- 进度版本：1" in read_text(progress_path)
        assert not list((root / ".backups" / "transactions").iterdir())
        assert parse_state(root / STATE_FILE)["review_stage"] == "baseline"
        turn_input = root.parent / "turn.md"
        turn_input.write_text("# 单轮记录\n\n- 已确认：自测。\n", encoding="utf-8")
        progress_input = root.parent / "progress.md"
        progress_input.write_text(read_text(root / "访谈进度.md").replace("尚未开始。", "下一项自测。"), encoding="utf-8")
        recorded = record_turn(root, turn_input, progress_input, "2030-01-01-session-1", "turn-1", "1", True)
        assert recorded["progress_version"] == "2"
        assert recorded["new_session_required"] is True
        assert "cross-natural-day" in recorded["session_termination_reasons"]
        assert not list((root / ".backups" / "transactions").iterdir())
        retried = record_turn(root, turn_input, progress_input, "2030-01-01-session-1", "turn-1", "1", True)
        assert retried["idempotent"] is True
        second_turn = root.parent / "turn-2.md"
        second_turn.write_text("# 第二轮记录\n\n- 仅使用隔离自测数据。\n", encoding="utf-8")
        second_progress = root.parent / "progress-2.md"
        second_progress.write_text(read_text(root / "访谈进度.md").replace("下一项自测。", "第二项自测。"), encoding="utf-8")
        recorded_second = record_turn(root, second_turn, second_progress, "2030-01-01-session-1", "turn-2", "2", True)
        assert recorded_second["idempotent"] is False
        retried_old = record_turn(root, turn_input, progress_input, "2030-01-01-session-1", "turn-1", "1", True)
        assert retried_old["idempotent"] is True
        try:
            configure_space(root, None, None, "first-review", True)
            raise AssertionError("first-review without date did not fail")
        except StoreError:
            pass
        configure_space(root, None, "2030-01-01T00:00:00Z", "first-review", True)
        state_before_clear = parse_state(state_path)
        try:
            configure_space(root, None, "none", None, True)
            raise AssertionError("first-review clear did not fail")
        except StoreError as exc:
            assert "first-review requires" in str(exc)
        assert parse_state(state_path) == state_before_clear
        try:
            apply_profile(root, profile_candidate, summary, "1", True)
            raise AssertionError("version conflict did not fail")
        except StoreError:
            pass
        withdraw_candidate(root, staged["candidate_id"], True)
        final, code = validate_space(root)
        assert code == 0, final
    return {"ok": True, "command": "self-test"}


def positive_integer(value: str) -> str:
    """Parse version arguments without adapter-specific coercions."""
    if not is_positive_decimal(value):
        raise argparse.ArgumentTypeError("must be a positive decimal integer")
    return value


def build_parser() -> argparse.ArgumentParser:
    parser = JsonArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True, parser_class=JsonArgumentParser)

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
    item = sub.add_parser("record-disclosure")
    root_argument(item)
    item.add_argument("--capture-mode")
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
    item.add_argument("--expected-version", required=True, type=positive_integer)
    item.add_argument("--confirmed", action="store_true")
    item.add_argument("--simulate-failure", action="store_true")
    item = sub.add_parser("record-turn")
    root_argument(item)
    item.add_argument("--input", required=True)
    item.add_argument("--progress-input", required=True)
    item.add_argument("--session-id", required=True)
    item.add_argument("--turn-id", required=True)
    item.add_argument("--expected-progress-version", required=True, type=positive_integer)
    item.add_argument("--confirmed", action="store_true")
    item.add_argument("--simulate-failure", action="store_true")
    item = sub.add_parser("withdraw")
    root_argument(item)
    item.add_argument("--id", required=True)
    item.add_argument("--confirmed", action="store_true")
    item = sub.add_parser("recover")
    root_argument(item)
    item.add_argument("--confirmed", action="store_true")
    sub.add_parser("self-test")
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    raw_argv = list(sys.argv[1:] if argv is None else argv)
    try:
        validate_cli_syntax(raw_argv)
        args = build_parser().parse_args(raw_argv)
    except CliParseError as exc:
        # The first positional token is the command in this CLI grammar.  If
        # parsing failed before one was supplied, keep the required field but
        # leave it empty rather than guessing from an option value.
        command_hint = raw_argv[0] if raw_argv and not raw_argv[0].startswith("-") else ""
        emit({"ok": False, "command": command_hint, "error": str(exc)})
        return 2
    try:
        if args.command == "self-test":
            emit(self_test())
            return 0
        if args.command in MUTATING_COMMANDS and args.root is None:
            # HELLO_HOME remains a convenient read-only discovery fallback,
            # but a write must name its exact profile root.  This fail-closed
            # guard prevents a dropped --root value from mutating whichever
            # personal space happens to be in the process environment.
            raise StoreError("Mutating commands require an explicit --root.")
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
            emit(configure_space(root, args.capture_mode, args.next_review_at, args.review_stage, args.confirmed))
            return 0
        if args.command == "record-disclosure":
            emit(record_disclosure(root, args.confirmed, args.capture_mode))
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
                    args.simulate_failure,
                )
            )
            return 0
        if args.command == "record-turn":
            emit(
                record_turn(
                    root,
                    Path(args.input),
                    Path(args.progress_input),
                    args.session_id,
                    args.turn_id,
                    args.expected_progress_version,
                    args.confirmed,
                    args.simulate_failure,
                )
            )
            return 0
        if args.command == "withdraw":
            emit(withdraw_candidate(root, args.id, args.confirmed))
            return 0
        if args.command == "recover":
            emit(recover_transaction(root, args.confirmed))
            return 0
        raise StoreError(f"Unknown command: {args.command}")
    except (StoreError, OSError, UnicodeError, AssertionError) as exc:
        emit({"ok": False, "command": args.command, "error": str(exc)})
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
