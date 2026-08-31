#!/usr/bin/env python3
"""Deterministic local storage adapter for the hello skill."""

from __future__ import annotations

import argparse
import difflib
import hashlib
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
LAYOUT_TRANSACTION_FILE = ".hello-layout-transaction"
LOCK_DIR = ".hello-lock"
TARGET_LAYOUTS = {"target-draft", "target"}
TARGET_FORMAL_SCHEMA = "3"
TARGET_CORE_FILES = (
    "README.md",
    "个人全景档案.md",
    "主题覆盖矩阵.md",
    "manifest.json",
)
TARGET_COMPAT_FILES = ("待确认信息.md", "访谈进度.md", "资料索引.md", "迭代日志.md")
TARGET_REQUIRED_DIRS = ("原始访谈", "来源", "权威", "派生", "历史版本", ".backups", ".trash")
TARGET_METADATA_KEYS = ("layout", "layout_version", "schema_version", "migration_id", "package_id", "subject_id")
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
    "migrate-apply",
    "rebuild-index",
    "switch-layout",
    "rollback-layout",
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
    # Treat an all-whitespace value like an omitted value.  A wrapper that
    # loses the path but leaves spaces must fail closed rather than resolve
    # the current directory (or a whitespace-named POSIX directory).
    if raw is None or raw.strip() == "":
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
    "destination",
    "target",
    "migration-id",
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


# ---------------------------------------------------------------------------
# Target-layout protocol (P1/P3)
# ---------------------------------------------------------------------------
#
# The original adapter stores a schema-2 compatibility projection at the
# profile root.  The target protocol deliberately lives beside it: a target
# package has an explicit marker and a metadata-only manifest, and all
# migration/switch operations are guarded by source hashes and version CAS.
# These helpers never print document bodies.  They are intentionally small
# and deterministic so the PowerShell and POSIX adapters can implement the
# same contract without depending on Python.


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except (OSError, UnicodeError) as exc:
        raise StoreError(f"Cannot hash {path}: {exc}") from exc
    return digest.hexdigest()


def read_json_object(path: Path) -> dict:
    try:
        value = json.loads(read_text(path))
    except (json.JSONDecodeError, StoreError) as exc:
        raise StoreError(f"Invalid JSON in {path.name}: {exc}") from exc
    if not isinstance(value, dict):
        raise StoreError(f"JSON root in {path.name} must be an object.")
    return value


def _target_marker(root: Path) -> Dict[str, str]:
    marker = root / STATE_FILE
    if not marker.is_file():
        raise StoreError(f"Missing target marker: {STATE_FILE}")
    values = parse_key_values(marker)
    layout = values.get("layout", "")
    if layout not in TARGET_LAYOUTS:
        raise StoreError("Target marker layout must be target-draft or target.")
    for key in TARGET_METADATA_KEYS:
        if not values.get(key):
            raise StoreError(f"Missing target marker field: {key}")
    if values.get("layout_version") != "1":
        raise StoreError("Target marker layout_version must be 1.")
    if not SAFE_ID.fullmatch(values["migration_id"]):
        raise StoreError("Target marker migration_id is invalid.")
    if not SAFE_ID.fullmatch(values["package_id"]):
        raise StoreError("Target marker package_id is invalid.")
    if not SAFE_ID.fullmatch(values["subject_id"]):
        raise StoreError("Target marker subject_id is invalid.")
    return values


def _target_manifest(root: Path, marker: Dict[str, str]) -> dict:
    manifest = read_json_object(root / "manifest.json")
    for key in ("layout", "migration_id", "package_id", "subject_id", "owner", "audience"):
        if not str(manifest.get(key, "")):
            raise StoreError(f"Missing target manifest field: {key}")
    if manifest.get("layout") != marker.get("layout"):
        raise StoreError("Target marker and manifest layout do not match.")
    if str(manifest.get("layout_version")) != str(marker.get("layout_version")):
        raise StoreError("Target marker and manifest layout_version do not match.")
    manifest_schema = str(manifest.get("schema_version", ""))
    marker_schema = str(marker.get("schema_version", ""))
    if manifest_schema != marker_schema:
        # A draft created by an earlier hello release may use equivalent
        # target-draft-x.y spellings; formal schema-3 markers must match
        # exactly so a partial promotion cannot pass validation.
        if not (manifest_schema.startswith("target-draft-") and marker_schema.startswith("target-draft-")):
            raise StoreError("Target marker and manifest schema_version do not match.")
    for key in ("migration_id", "package_id", "subject_id"):
        if str(manifest.get(key)) != marker.get(key):
            raise StoreError(f"Target marker and manifest {key} do not match.")
    layout_version = str(manifest.get("layout_version", ""))
    if layout_version != "1":
        raise StoreError("Target manifest layout_version must be 1.")
    return manifest


def _target_path_is_safe(root: Path, path: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
    except ValueError:
        return False
    return not path.is_symlink()


def _target_source_metadata(manifest: dict, marker: Dict[str, str] | None = None) -> dict:
    source = manifest.get("source")
    if not isinstance(source, dict):
        source = {}
    # Older drafts put versions/hashes directly in the marker or migration
    # manifest.  Normalize those shapes so switch/migrate-apply can fail
    # closed rather than silently skipping a source CAS check.
    profile = source.get("profile") if isinstance(source.get("profile"), dict) else {}
    progress = source.get("progress") if isinstance(source.get("progress"), dict) else {}
    pending = source.get("pending") if isinstance(source.get("pending"), dict) else {}
    # The PowerShell/POSIX adapters also accept the first migration-manifest
    # shape, which stores these five values as flat aliases.  Read that shape
    # before consulting the marker so a formal package produced by another
    # adapter remains switchable here even when its marker omits hashes.
    profile.setdefault("version", source.get("profile_version", ""))
    progress.setdefault("version", source.get("progress_version", ""))
    profile.setdefault("sha256", source.get("profile_sha256", ""))
    progress.setdefault("sha256", source.get("progress_sha256", ""))
    pending.setdefault("sha256", source.get("pending_sha256", ""))
    if marker:
        profile.setdefault("version", marker.get("source_profile_version", ""))
        progress.setdefault("version", marker.get("source_progress_version", ""))
        profile.setdefault("sha256", marker.get("source_profile_sha256", ""))
        progress.setdefault("sha256", marker.get("source_progress_sha256", ""))
        pending.setdefault("sha256", marker.get("source_pending_sha256", ""))
    return {"profile": profile, "progress": progress, "pending": pending}


def _compat_source_snapshot(root: Path) -> dict:
    state_path = root / STATE_FILE
    if not root.is_dir() or not state_path.is_file():
        raise StoreError("Source profile root is missing.")
    state = parse_state(state_path)
    if state.get("schema_version") not in {"1", "2"} or "layout" in state:
        raise StoreError("Migration source must be a compatibility schema-1/2 root.")
    required = ("个人全景档案.md", "访谈进度.md", "待确认信息.md")
    missing = [name for name in required if not (root / name).is_file()]
    if missing:
        raise StoreError("Migration source is missing: " + ", ".join(missing))
    return {
        "profile": {
            "path": "个人全景档案.md",
            "version": str(state.get("profile_version", "")),
            "sha256": sha256_file(root / "个人全景档案.md"),
        },
        "progress": {
            "path": "访谈进度.md",
            "version": str(effective_progress_version_for_root(root, state)),
            "sha256": sha256_file(root / "访谈进度.md"),
        },
        "pending": {
            "path": "待确认信息.md",
            "sha256": sha256_file(root / "待确认信息.md"),
        },
    }


def _source_matches_manifest(source_root: Path, manifest: dict, marker: Dict[str, str] | None = None,
                             expected_version: str | None = None,
                             expected_progress_version: str | None = None) -> dict:
    snapshot = _compat_source_snapshot(source_root)
    expected = _target_source_metadata(manifest, marker)
    for name in ("profile", "progress", "pending"):
        expected_hash = str(expected[name].get("sha256", ""))
        if not re.fullmatch(r"[0-9a-fA-F]{64}", expected_hash):
            raise StoreError(f"Target manifest is missing source {name} sha256.")
        if expected_hash.lower() != snapshot[name]["sha256"].lower():
            raise StoreError(f"Source {name} hash does not match target manifest.")
    profile_version = str(snapshot["profile"]["version"])
    progress_version = str(snapshot["progress"]["version"])
    expected_profile = str(expected["profile"].get("version", ""))
    expected_progress = str(expected["progress"].get("version", ""))
    if expected_profile and expected_profile != profile_version:
        raise StoreError("Source profile version does not match target manifest.")
    if expected_progress and expected_progress != progress_version:
        raise StoreError("Source progress version does not match target manifest.")
    if expected_version is not None and expected_version != profile_version:
        raise StoreError(f"Version conflict: expected {expected_version}, current {profile_version}.")
    if expected_progress_version is not None and expected_progress_version != progress_version:
        raise StoreError(
            f"Progress version conflict: expected {expected_progress_version}, current {progress_version}."
        )
    return snapshot


def _target_entry_count(root: Path) -> int:
    count = 0
    authority = root / "权威"
    if authority.is_dir():
        count = sum(1 for path in authority.rglob("*.md") if path.name != "README.md")
    return count


def _target_validate_unlocked(root: Path, expected_layout: str | None = None) -> Tuple[dict, int]:
    issues: list[str] = []
    marker: Dict[str, str] = {}
    manifest: dict = {}
    if not root.is_dir():
        issues.append("Root directory does not exist")
    else:
        try:
            marker = _target_marker(root)
        except StoreError as exc:
            issues.append(str(exc))
        if marker:
            if expected_layout and marker.get("layout") != expected_layout:
                issues.append(f"Target layout must be {expected_layout}")
            try:
                manifest = _target_manifest(root, marker)
            except StoreError as exc:
                issues.append(str(exc))
            if manifest:
                for key in ("layout", "layout_version", "schema_version", "migration_id", "package_id", "subject_id"):
                    marker_value = str(marker.get(key, ""))
                    manifest_value = str(manifest.get(key, ""))
                    if marker_value != manifest_value:
                        issues.append(f"Target marker and manifest {key} do not match.")
        for name in TARGET_CORE_FILES:
            if not (root / name).is_file():
                issues.append(f"Missing target file: {name}")
        for name in TARGET_COMPAT_FILES:
            if not (root / name).is_file():
                issues.append(f"Missing target file: {name}")
        for name in TARGET_REQUIRED_DIRS:
            if not (root / name).is_dir():
                issues.append(f"Missing target directory: {name}")
        if marker.get("layout") == "target":
            # A formal package must retain the compatibility cursor/state so
            # existing record-turn/stage callers can continue safely.
            for key in ("profile_version", "progress_version", "capture_mode", "created_at", "updated_at"):
                if not marker.get(key):
                    issues.append(f"Formal target marker is missing compatibility field: {key}")
            for key in (
                "last_confirmed_at",
                "next_review_at",
                "review_stage",
                "last_interview_at",
                "last_session_id",
                "last_turn_id",
                "last_capture_disclosed_at",
                "last_capture_disclosed_mode",
            ):
                if key not in marker:
                    issues.append(f"Formal target marker is missing compatibility field: {key}")
            if marker.get("schema_version") != TARGET_FORMAL_SCHEMA:
                issues.append("Formal target marker schema_version must be 3")
        elif marker.get("layout") == "target-draft":
            if not str(marker.get("schema_version", "")).startswith("target-draft"):
                issues.append("Target draft marker schema_version must start with target-draft")
        # Reject symlinks and path escapes before any migration operation.
        try:
            for child in root.rglob("*"):
                if not _target_path_is_safe(root, child):
                    issues.append(f"Unsafe target path: {child.name}")
                    break
                if child.is_file() and child.suffix.lower() in {".md", ".json", ".state", ".txt", ""}:
                    try:
                        raw = child.read_bytes()
                        if b"\r" in raw:
                            issues.append(f"CRLF is not allowed: {child.relative_to(root).as_posix()}")
                        raw.decode("utf-8-sig")
                    except (OSError, UnicodeError) as exc:
                        issues.append(f"Invalid UTF-8 file: {child.relative_to(root).as_posix()}")
        except OSError as exc:
            issues.append(f"Cannot scan target tree: {exc}")
        index_path = root / "权威" / "声明索引.json"
        if index_path.is_file():
            try:
                index_value = json.loads(read_text(index_path))
                if not isinstance(index_value, dict):
                    issues.append("Authority index JSON must be an object.")
            except (StoreError, json.JSONDecodeError):
                issues.append("Invalid authority index JSON: 权威/声明索引.json")
    pending = 0
    if (root / "待确认信息.md").is_file():
        try:
            pending = len(re.findall(r"(?m)^## C-[0-9TZ-]+\s*$", read_text(root / "待确认信息.md")))
        except StoreError:
            pass
    files = 0
    if root.is_dir():
        try:
            files = sum(1 for path in root.rglob("*") if path.is_file())
        except OSError:
            pass
    payload = {
        "ok": not issues,
        "command": "target-validate",
        "root": str(root),
        "layout": marker.get("layout", ""),
        "layout_version": str(marker.get("layout_version", "")),
        "schema_version": marker.get("schema_version", ""),
        "migration_id": marker.get("migration_id", ""),
        "package_id": marker.get("package_id", ""),
        "subject_id": marker.get("subject_id", ""),
        "authority_entry_count": str(_target_entry_count(root)) if root.is_dir() else "0",
        "file_count": str(files),
        "pending_candidates": str(pending),
        "issues": issues,
    }
    return payload, 0 if not issues else 1


@locked
def target_validate(root: Path, expected_layout: str | None = None) -> Tuple[dict, int]:
    """Validate a target package without returning any document body."""
    return _target_validate_unlocked(root, expected_layout)


def target_status(root: Path) -> Tuple[dict, int]:
    payload, code = _target_validate_unlocked(root)
    if code:
        payload["command"] = "status"
        return payload, code
    marker = _target_marker(root)
    manifest = _target_manifest(root, marker)
    # A migration draft may not yet have the compatibility state projection.
    # Keep the policy snapshot in the metadata-only status response so the
    # host can disclose the effective capture mode before asking to persist a
    # candidate.  Formal packages prefer the marker, which is the live cursor.
    policy = manifest.get("capture_policy_snapshot")
    if not isinstance(policy, dict):
        policy = {}
    capture_mode = marker.get("capture_mode") or str(policy.get("capture_mode", ""))
    capture_strategy = marker.get("capture_strategy") or str(
        policy.get("capture_strategy", CAPTURE_STRATEGIES.get(capture_mode, ""))
    )
    disclosed_at = marker.get("last_capture_disclosed_at") or str(
        policy.get("last_capture_disclosed_at", "")
    )
    disclosed_mode = marker.get("last_capture_disclosed_mode") or str(
        policy.get("last_capture_disclosed_mode", "")
    )
    # Status is metadata-only for target packages.  In particular, do not
    # expose aggregate/profile text or the next question in JSON output.
    baseline_remaining, long_term_backlog, split_unknown = target_progress_buckets(root)
    # A draft/formal-but-not-activated package still has an owner-confirmation
    # gate. Once canonical activation is confirmed, entity review is reported
    # by each entry's status and must not masquerade as a second switch gate.
    authority_status = str(marker.get("authority_status", manifest.get("authority_status", "")))
    if authority_status in {"non-authoritative-needs-user-confirmation", "active-layout-needs-review"}:
        baseline_remaining = list(baseline_remaining)
        baseline_remaining.append("migration-review（需用户确认目录化切换）")
    return {
        "ok": True,
        "command": "status",
        "root": str(root),
        "layout": marker["layout"],
        "layout_version": marker["layout_version"],
        "schema_version": marker["schema_version"],
        "migration_id": marker["migration_id"],
        "package_id": marker["package_id"],
        "subject_id": marker["subject_id"],
        "profile_version": str(marker.get("profile_version", marker.get("source_profile_version", ""))),
        "progress_version": str(marker.get("progress_version", marker.get("source_progress_version", ""))),
        "capture_mode": capture_mode,
        "capture_strategy": capture_strategy,
        "last_capture_disclosed_at": disclosed_at,
        "last_capture_disclosed_mode": disclosed_mode,
        "review_stage": marker.get("review_stage", "baseline"),
        "last_confirmed_at": marker.get("last_confirmed_at", ""),
        "next_review_at": marker.get("next_review_at", ""),
        "last_session_id": marker.get("last_session_id", ""),
        "last_turn_id": marker.get("last_turn_id", ""),
        "pending_candidates": payload["pending_candidates"],
        "authority_entry_count": payload["authority_entry_count"],
        "file_count": payload["file_count"],
        "baseline_required_remaining": baseline_remaining,
        "baseline_closure_blocked": bool(baseline_remaining) or split_unknown,
        "baseline_split_unknown": split_unknown,
        "long_term_backlog": long_term_backlog,
        "progress": {
            "current_stage": "目标资料包",
            "last_interview_at": marker.get("last_interview_at", ""),
            "next_question": "",
        },
    }, 0


def target_progress_buckets(root: Path) -> tuple[list[str], list[str], bool]:
    """Read only topic labels/statuses from the target coverage matrix."""
    matrix = root / "主题覆盖矩阵.md"
    if not matrix.is_file():
        return ["legacy-unclassified（缺少主题覆盖矩阵）"], [], True
    try:
        lines = read_text(matrix).splitlines()
    except StoreError:
        return ["legacy-unclassified（主题覆盖矩阵不可读）"], [], True
    baseline: list[str] = []
    long_term: list[str] = []
    found_bucket = False
    for raw in lines:
        if not raw.lstrip().startswith("|"):
            continue
        cells = [cell.strip() for cell in raw.strip().strip("|").split("|")]
        if len(cells) < 4:
            continue
        # Migration drafts use Markdown code spans in table cells.  Remove
        # presentation delimiters before comparing semantic values so status
        # is stable across adapters and does not expose labels such as
        # `` `situation`（`partial`） ``.
        clean = lambda value: value.strip().strip("`").strip()
        topic_id = clean(cells[0])
        if topic_id.casefold() in {"topic_id", "主题", "---", "-", ""}:
            continue
        priority = " ".join(clean(cells[2]).split())
        state = clean(cells[3].split()[0]) if cells[3] else ""
        if priority in {"基线必答", "baseline", "基线"}:
            found_bucket = True
            if state not in {"confirmed_minimum", "deepened", "declined", "not_applicable"}:
                baseline.append(f"{topic_id}（{state or 'unknown'}）")
        elif priority in {"可长期补充", "long-term", "long"}:
            found_bucket = True
            if state not in {"confirmed_minimum", "deepened", "declined", "not_applicable"}:
                long_term.append(f"{topic_id}（{state or 'unknown'}）")
    if not found_bucket:
        return ["legacy-unclassified（需先完成基线/长期分组）"], [], True
    return baseline, long_term, False


def _assert_independent_roots(left: Path, right: Path) -> None:
    """Reject equal/ancestor roots so a migration cannot recurse into itself."""
    left_resolved = left.resolve()
    right_resolved = right.resolve()
    if left_resolved == right_resolved:
        raise StoreError("Source and target roots must be different.")
    for ancestor, child in ((left_resolved, right_resolved), (right_resolved, left_resolved)):
        try:
            child.relative_to(ancestor)
        except ValueError:
            continue
        raise StoreError("Source and target roots must be independent directories.")


def _has_user_entries(path: Path) -> bool:
    if not path.is_dir():
        return False
    return any(
        child.name not in {LOCK_DIR, TRANSACTION_FILE, LAYOUT_TRANSACTION_FILE}
        for child in path.iterdir()
    )


def _safe_migration_id(value: str | None) -> str:
    candidate = (value or "").strip()
    if not candidate:
        candidate = "migration-" + stamp()
    if not SAFE_ID.fullmatch(candidate):
        raise StoreError("migration-id may contain only ASCII letters, digits, dot, underscore, or hyphen.")
    return candidate


def _write_target_marker(root: Path, values: Dict[str, str]) -> None:
    # Use the same key=value representation as the compatibility state so all
    # adapters can inspect the layout without loading document bodies.
    write_state(root / STATE_FILE, {str(k): str(v) for k, v in values.items()})


def _minimal_target_text(name: str) -> str:
    texts = {
        "README.md": "# 个人资料包\n\n此目录由 hello 目标布局协议创建。\n",
        "个人全景档案.md": "# 个人全景档案\n\n> 本文件是目录化资料包的聚合入口；详细内容以权威实体为准。\n",
        "主题覆盖矩阵.md": "# 主题覆盖矩阵\n\n> 覆盖状态由权威条目和用户确认维护。\n",
        "待确认信息.md": "# 待确认信息\n\n当前没有待确认信息。\n",
        "访谈进度.md": "# 访谈进度\n\n- 进度版本：1\n\n## 已覆盖主题\n\n- 尚未开始。\n\n## 待补充主题\n\n### 基线必答（阻塞基线收口）\n\n- 尚未分组。\n\n### 可长期补充（不阻塞基线收口）\n\n- 尚未分组。\n\n## 暂不收集\n\n- 暂无。\n\n## 下次问题\n\n- 待定。\n",
        "资料索引.md": "# 资料索引\n\n- 由目标协议维护。\n",
        "迭代日志.md": "# 迭代日志\n\n当前没有正式迭代。\n",
    }
    return texts.get(name, "")


def _write_bytes_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
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


def _copy_file_atomic(source: Path, target: Path) -> None:
    try:
        _write_bytes_atomic(target, source.read_bytes())
    except OSError as exc:
        raise StoreError(f"Cannot copy {source}: {exc}") from exc


def _copy_tree_contents(source: Path, target: Path, skip: set[str] | None = None) -> int:
    """Copy a target package without following symlinks; return file count."""
    skip = set(skip or ()) | {LOCK_DIR, TRANSACTION_FILE, LAYOUT_TRANSACTION_FILE}
    if not source.is_dir():
        raise StoreError(f"Target source directory does not exist: {source}")
    target.mkdir(parents=True, exist_ok=True)
    secure_directory(target)
    copied = 0
    for child in sorted(source.iterdir(), key=lambda item: item.name.casefold()):
        if child.name in skip:
            continue
        if child.is_symlink():
            raise StoreError(f"Target source contains an unsafe symlink: {child.name}")
        destination = target / child.name
        if child.is_dir():
            copied += _copy_tree_contents(child, destination)
        elif child.is_file():
            _copy_file_atomic(child, destination)
            copied += 1
        else:
            raise StoreError(f"Target source contains unsupported path: {child.name}")
    return copied


def _snapshot_root(root: Path, migration_id: str, version: str | None = None) -> Path:
    history = root / "历史版本"
    history.mkdir(parents=True, exist_ok=True)
    secure_directory(history)
    prefix = f"compat-v{version}-{migration_id}" if version else f".hello-layout-{migration_id}"
    snapshot = history / f"{prefix}-{stamp()}" if not version else history / prefix
    counter = 1
    while snapshot.exists():
        snapshot = (
            history / f"{prefix}-{stamp()}-{counter}"
            if not version
            else history / f"{prefix}-{counter}"
        )
        counter += 1
    snapshot.mkdir()
    secure_directory(snapshot)
    for child in sorted(root.iterdir(), key=lambda item: item.name.casefold()):
        if child.name in {"历史版本", LOCK_DIR, LAYOUT_TRANSACTION_FILE}:
            continue
        if child.is_symlink():
            raise StoreError(f"Cannot snapshot unsafe symlink: {child.name}")
        destination = snapshot / child.name
        if child.is_dir():
            _copy_tree_contents(child, destination)
        elif child.is_file():
            _copy_file_atomic(child, destination)
    atomic_write(
        snapshot / "snapshot.json",
        serialize_json({"migration_id": migration_id, "created_at": now_utc(), "layout_snapshot": True}),
    )
    return snapshot


def _remove_exact(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def _restore_snapshot(root: Path, snapshot: Path) -> None:
    if not snapshot.is_dir() or not _target_path_is_safe(root, snapshot):
        raise StoreError("Layout snapshot is missing or escapes the profile root.")
    try:
        snapshot_meta = read_json_object(snapshot / "snapshot.json")
    except StoreError as exc:
        raise StoreError("Layout snapshot metadata is invalid.") from exc
    if not snapshot_meta.get("layout_snapshot"):
        raise StoreError("Layout snapshot metadata is invalid.")
    for child in list(root.iterdir()):
        if child.name in {"历史版本", LOCK_DIR, LAYOUT_TRANSACTION_FILE}:
            continue
        _remove_exact(child)
    for child in sorted(snapshot.iterdir(), key=lambda item: item.name.casefold()):
        if child.name == "snapshot.json":
            continue
        destination = root / child.name
        if child.is_dir():
            _copy_tree_contents(child, destination)
        elif child.is_file():
            _copy_file_atomic(child, destination)


def _write_layout_transaction(root: Path, values: dict) -> None:
    marker = root / LAYOUT_TRANSACTION_FILE
    if marker.exists():
        raise StoreError("Interrupted layout transaction exists; run rollback-layout first.")
    try:
        with marker.open("x", encoding="utf-8", newline="\n") as handle:
            handle.write(serialize_json(values))
            handle.flush()
            os.fsync(handle.fileno())
        secure_file(marker)
    except FileExistsError as exc:
        raise StoreError("Interrupted layout transaction exists; run rollback-layout first.") from exc


def _read_layout_transaction(root: Path) -> dict:
    marker = root / LAYOUT_TRANSACTION_FILE
    if not marker.is_file():
        raise StoreError("No interrupted layout transaction exists.")
    values = read_json_object(marker)
    for key in ("migration_id", "snapshot"):
        if not str(values.get(key, "")):
            raise StoreError(f"Layout transaction is missing field: {key}")
    snapshot = transaction_target(root, str(values["snapshot"]))
    if not snapshot.is_dir():
        raise StoreError("Layout transaction snapshot is missing.")
    try:
        snapshot_meta = read_json_object(snapshot / "snapshot.json")
    except StoreError as exc:
        raise StoreError("Layout transaction snapshot metadata is invalid.") from exc
    if str(snapshot_meta.get("migration_id", "")) != str(values["migration_id"]):
        raise StoreError("Layout transaction snapshot migration_id does not match.")
    return values


def _source_manifest_payload(source: dict) -> dict:
    return {
        "profile": dict(source["profile"]),
        "progress": dict(source["progress"]),
        "pending": dict(source["pending"]),
    }


def _merge_source_manifest(previous: object, source: dict) -> dict:
    """Refresh source fingerprints without discarding migration metadata.

    ``migration-manifest.json`` files produced by the migration tooling carry
    mapping/copy-policy fields alongside the source snapshot.  Replacing the
    whole ``source`` object during formalization used to silently discard
    those fields.  Keep every existing key, refresh the canonical nested
    snapshots, and update legacy flat aliases when they are present.
    """
    normalized = _source_manifest_payload(source)
    if not isinstance(previous, dict):
        return normalized
    merged = dict(previous)
    for section in ("profile", "progress", "pending"):
        prior = previous.get(section)
        if isinstance(prior, dict):
            section_value = dict(prior)
            section_value.update(normalized[section])
            merged[section] = section_value
        else:
            merged[section] = dict(normalized[section])
    # Some early migration manifests used flat aliases.  Preserve their
    # shape and refresh values so source/hash validation remains truthful.
    aliases = {
        "profile_version": source["profile"]["version"],
        "progress_version": source["progress"]["version"],
        "profile_sha256": source["profile"]["sha256"],
        "progress_sha256": source["progress"]["sha256"],
        "pending_sha256": source["pending"]["sha256"],
    }
    for key, value in aliases.items():
        if key in merged:
            merged[key] = value
    return merged


def _update_migration_manifest(root: Path, source: dict, migration_id: str, layout: str) -> dict:
    """Set the formalization fields while retaining all existing manifest data."""
    path = root / "migration-manifest.json"
    document = read_json_object(path) if path.is_file() else {}
    document["migration_id"] = migration_id
    document["layout"] = layout
    document["source"] = _merge_source_manifest(document.get("source"), source)
    atomic_write(path, serialize_json(document))
    return document


def _snapshot_belongs_to(snapshot: Path, migration_id: str) -> bool:
    """Return true only for a snapshot whose metadata names this migration."""
    try:
        metadata = read_json_object(snapshot / "snapshot.json")
    except StoreError:
        return False
    return bool(metadata.get("layout_snapshot")) and str(metadata.get("migration_id", "")) == migration_id


def _create_target_draft(source_root: Path, destination: Path, migration_id: str, source: dict) -> dict:
    if destination.exists() and _has_user_entries(destination):
        raise StoreError(f"Destination already exists and is not empty: {destination}")
    destination.mkdir(parents=True, exist_ok=True)
    secure_directory(destination)
    for directory in TARGET_REQUIRED_DIRS:
        (destination / directory).mkdir(parents=True, exist_ok=True)
        secure_directory(destination / directory)
    marker = {
        "layout": "target-draft",
        "layout_version": "1",
        "schema_version": "target-draft-0.1",
        "migration_id": migration_id,
        "package_id": f"pkg-{migration_id}",
        "subject_id": "subject-local",
        "source_profile_version": source["profile"]["version"],
        "source_progress_version": source["progress"]["version"],
        "source_profile_sha256": source["profile"]["sha256"],
        "source_progress_sha256": source["progress"]["sha256"],
        "source_pending_sha256": source["pending"]["sha256"],
        "generated_at": now_utc(),
        "authority_status": "non-authoritative-needs-user-confirmation",
    }
    manifest = {
        "layout": "target-draft",
        "layout_version": 1,
        "schema_version": "target-draft-0.1",
        "migration_id": migration_id,
        "package_id": marker["package_id"],
        "subject_id": marker["subject_id"],
        "owner": "local-owner",
        "audience": "owner-and-authorized-ai",
        "generated_at": marker["generated_at"],
        "authority_status": marker["authority_status"],
        "source": _source_manifest_payload(source),
    }
    _write_target_marker(destination, marker)
    atomic_write(destination / "manifest.json", serialize_json(manifest))
    for name in TARGET_CORE_FILES:
        if name == "manifest.json":
            continue
        atomic_write(destination / name, _minimal_target_text(name))
    # Carry the compatibility projection into the isolated draft so a later
    # promotion can resume the interview without silently replacing the
    # source cursor with an empty template.  The projection remains
    # non-authoritative; source fingerprints and the owner review gate still
    # control activation.
    for name in TARGET_COMPAT_FILES:
        source_path = source_root / name
        if source_path.is_file():
            _copy_file_atomic(source_path, destination / name)
        else:
            atomic_write(destination / name, _minimal_target_text(name))
    atomic_write(
        destination / "迁移映射.md",
        "# 迁移映射\n\n- 状态：待用户确认。\n- 详细来源映射由迁移工具维护。\n",
    )
    atomic_write(
        destination / "migration-manifest.json",
        serialize_json({"migration_id": migration_id, "layout": "target-draft", "source": _source_manifest_payload(source)}),
    )
    return marker


def _formalize_target(
    root: Path,
    source: dict,
    source_state: Dict[str, str],
    migration_id: str,
    source_root: Path,
) -> dict:
    marker = _target_marker(root)
    if marker["migration_id"] != migration_id:
        raise StoreError("Target migration_id does not match the requested migration.")
    manifest = _target_manifest(root, marker)
    # A formal package keeps a compatibility projection at the root.  Drafts
    # generated by older versions may not have it; fill only missing files
    # from the validated source, never overwrite a reviewed draft projection.
    for name in TARGET_COMPAT_FILES:
        target = root / name
        if not target.is_file():
            _copy_file_atomic(source_root / name, target)
    formal_marker = dict(source_state)
    formal_marker.pop("_root", None)
    formal_marker.update(marker)
    formal_marker.update(
        {
            "layout": "target",
            "layout_version": marker.get("layout_version", "1"),
            "schema_version": TARGET_FORMAL_SCHEMA,
            "migration_id": migration_id,
            "profile_version": source["profile"]["version"],
            "progress_version": source["progress"]["version"],
            "source_profile_version": source["profile"]["version"],
            "source_progress_version": source["progress"]["version"],
            "source_profile_sha256": source["profile"]["sha256"],
            "source_progress_sha256": source["progress"]["sha256"],
            "source_pending_sha256": source["pending"]["sha256"],
            # The formal package can still contain draft entities; keep that
            # review state separate from the physical activation gate.
            "authority_status": "active-layout-needs-review",
            "updated_at": now_utc(),
        }
    )
    _write_target_marker(root, formal_marker)
    manifest["layout"] = "target"
    manifest["schema_version"] = TARGET_FORMAL_SCHEMA
    manifest["layout_version"] = int(marker.get("layout_version", "1"))
    manifest["authority_status"] = "active-layout-needs-review"
    manifest["activated_at"] = now_utc()
    manifest["source"] = _merge_source_manifest(manifest.get("source"), source)
    atomic_write(root / "manifest.json", serialize_json(manifest))
    _update_migration_manifest(root, source, migration_id, "target")
    return formal_marker


@contextmanager
def _lock_roots(*roots: Path):
    """Acquire multiple profile locks in a deterministic order."""
    unique = sorted({str(path.resolve()): path.resolve() for path in roots}.values(), key=str)
    if not unique:
        yield
        return
    with store_lock(unique[0]):
        with _lock_roots(*unique[1:]):
            yield


def _target_plan_result(source_root: Path, root: Path, source: dict, migration_id: str, created: bool) -> dict:
    target_exists = root.exists()
    payload, code = _target_validate_unlocked(root) if target_exists else ({"layout": "", "authority_entry_count": "0", "issues": []}, 0)
    if code and target_exists:
        raise StoreError("Target plan is invalid: " + "; ".join(payload["issues"]))
    return {
        "ok": True,
        "command": "migrate-plan",
        "root": str(source_root),
        "destination": str(root),
        "source_root": str(source_root),
        "target_root": str(root),
        "migration_id": migration_id,
        "created": created,
        "target_exists": target_exists,
        "layout": payload["layout"],
        "target_layout": payload["layout"],
        "mapping_ready": bool(target_exists and not code),
        "target_issues": payload.get("issues", []),
        "source_profile_version": str(source["profile"]["version"]),
        "source_progress_version": str(source["progress"]["version"]),
        "source_profile_sha256": source["profile"]["sha256"],
        "source_progress_sha256": source["progress"]["sha256"],
        "source_pending_sha256": source["pending"]["sha256"],
        "authority_entry_count": payload["authority_entry_count"],
    }


def migrate_plan(
    source_root: Path,
    destination: Path,
    migration_id: str | None,
    confirmed: bool,
) -> dict:
    """Create or verify a read-only migration plan in an independent root."""
    migration_id = _safe_migration_id(migration_id)
    _assert_independent_roots(source_root, destination)
    # A lock cannot be materialized for a path that does not yet exist.  Claim
    # the caller's confirmation before creating an empty destination, then
    # acquire the normal inter-process lock for the actual plan write.
    destination_precreated = False
    if not destination.exists() and confirmed:
        require_confirmed(confirmed)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.mkdir()
        secure_directory(destination)
        destination_precreated = True
    with _lock_roots(source_root, destination):
        source_payload, source_code = validate_space(source_root)
        if source_code:
            raise StoreError("Migration source is invalid: " + "; ".join(source_payload["issues"]))
        source = _compat_source_snapshot(source_root)
        source_state = parse_state(source_root / STATE_FILE)
        if destination.exists() and not destination.is_dir():
            raise StoreError("Migration destination must be a directory.")
        created = False
        if destination.exists() and _has_user_entries(destination):
            target_payload, target_code = _target_validate_unlocked(destination, "target-draft")
            if target_code:
                raise StoreError("Existing migration destination is invalid: " + "; ".join(target_payload["issues"]))
            marker = _target_marker(destination)
            if marker["migration_id"] != migration_id:
                raise StoreError("Existing migration destination has a different migration_id.")
            manifest = _target_manifest(destination, marker)
            _source_matches_manifest(source_root, manifest, marker)
        else:
            if not destination_precreated:
                # Planning is intentionally read-only when the target does
                # not exist.  A confirmed direct function call may opt into
                # the convenience skeleton creation used by self-test and
                # local migration tooling; the CLI does not expose that
                # mutating flag.
                if not confirmed:
                    return _target_plan_result(source_root, destination, source, migration_id, False)
                require_confirmed(confirmed)
            _create_target_draft(source_root, destination, migration_id, source)
            created = True
        return _target_plan_result(source_root, destination, source, migration_id, created)


def _promote_existing_target(
    source_root: Path,
    draft_root: Path,
    target_root: Path,
    source: dict,
    source_state: Dict[str, str],
    migration_id: str,
    simulate_failure: bool = False,
) -> tuple[dict, Path | None]:
    """Promote a draft in place or copy it to a new formal target root."""
    source_state = dict(source_state)
    if target_root.resolve() != draft_root.resolve():
        if target_root.exists():
            if not target_root.is_dir() or _has_user_entries(target_root):
                # Idempotent retry is allowed only for the same formal package.
                try:
                    existing_marker = _target_marker(target_root)
                except StoreError:
                    existing_marker = {}
                if existing_marker.get("layout") == "target" and existing_marker.get("migration_id") == migration_id:
                    return _target_marker(target_root), None
                raise StoreError("Formal target already exists and is not empty.")
        target_root.parent.mkdir(parents=True, exist_ok=True)
        temporary = Path(tempfile.mkdtemp(prefix=f".{target_root.name}.", dir=str(target_root.parent)))
        try:
            _copy_tree_contents(draft_root, temporary)
            _formalize_target(temporary, source, source_state, migration_id, source_root)
            if simulate_failure:
                raise StoreError("simulated failure before target promotion")
            os.replace(str(temporary), str(target_root))
            temporary = Path("__already_moved__")
        except Exception:
            if temporary.exists() and temporary.name != "__already_moved__":
                shutil.rmtree(temporary)
            raise
        return _target_marker(target_root), None

    # In-place promotion is protected by a snapshot and a durable marker so a
    # process interruption can be recovered with rollback-layout.
    if (target_root / LAYOUT_TRANSACTION_FILE).exists():
        raise StoreError("Interrupted layout transaction exists; run rollback-layout first.")
    snapshot = _snapshot_root(target_root, migration_id)
    _write_layout_transaction(
        target_root,
        {
            "migration_id": migration_id,
            "snapshot": relative_to_root(target_root, snapshot),
            "operation": "migrate-apply",
            "created_at": now_utc(),
        },
    )
    try:
        _formalize_target(target_root, source, source_state, migration_id, source_root)
        if simulate_failure:
            raise StoreError("simulated failure after target promotion")
        payload, code = _target_validate_unlocked(target_root, "target")
        if code:
            raise StoreError("Post-promotion target validation failed: " + "; ".join(payload["issues"]))
        (target_root / LAYOUT_TRANSACTION_FILE).unlink()
        return _target_marker(target_root), snapshot
    except Exception as exc:
        try:
            _restore_snapshot(target_root, snapshot)
            (target_root / LAYOUT_TRANSACTION_FILE).unlink(missing_ok=True)
        except Exception as rollback_error:
            raise StoreError(
                f"Target promotion failed: {exc}. Rollback failed: {rollback_error}; run rollback-layout."
            ) from exc
        raise StoreError(f"Target promotion failed and was rolled back: {exc}") from exc


def migrate_apply(
    source_root: Path,
    draft_root: Path,
    target_root: Path | None,
    migration_id: str | None,
    expected_version: str | None,
    expected_progress_version: str | None,
    confirmed: bool,
    simulate_failure: bool = False,
) -> dict:
    """Promote a validated target draft without changing the source root."""
    require_confirmed(confirmed)
    migration_id = _safe_migration_id(migration_id)
    target_root = target_root or draft_root
    _assert_independent_roots(source_root, draft_root)
    if target_root.resolve() != draft_root.resolve():
        _assert_independent_roots(source_root, target_root)
    with _lock_roots(source_root, draft_root, target_root):
        source_payload, source_code = validate_space(source_root)
        if source_code:
            raise StoreError("Migration source is invalid: " + "; ".join(source_payload["issues"]))
        source = _compat_source_snapshot(source_root)
        source_state = parse_state(source_root / STATE_FILE)
        draft_payload, draft_code = _target_validate_unlocked(draft_root, "target-draft")
        if draft_code:
            raise StoreError("Target draft is invalid: " + "; ".join(draft_payload["issues"]))
        marker = _target_marker(draft_root)
        if marker["migration_id"] != migration_id:
            raise StoreError("Target draft migration_id does not match the requested migration.")
        manifest = _target_manifest(draft_root, marker)
        _source_matches_manifest(
            source_root,
            manifest,
            marker,
            expected_version=expected_version,
            expected_progress_version=expected_progress_version,
        )
        formal_marker, snapshot = _promote_existing_target(
            source_root,
            draft_root,
            target_root,
            source,
            source_state,
            migration_id,
            simulate_failure,
        )
        return {
            "ok": True,
            "command": "migrate-apply",
            "root": str(source_root),
            "draft": str(draft_root),
            "target": str(target_root),
            "migration_id": migration_id,
            "layout": formal_marker.get("layout", "target"),
            "profile_version": str(formal_marker.get("profile_version", source["profile"]["version"])),
            "progress_version": str(formal_marker.get("progress_version", source["progress"]["version"])),
            # The source compatibility root is never modified by
            # migrate-apply, including the in-place promotion of the draft.
            "source_unchanged": True,
            "snapshot": str(snapshot) if snapshot else "",
        }


def _frontmatter_fields(content: str) -> dict[str, str]:
    """Read the small YAML-like header used by target entity files.

    Migration entries use plain ``key: value`` lines, while early fixtures
    used Markdown-list ``- key: value`` lines.  Accept both forms, but only
    between the first pair of ``---`` delimiters so body text cannot become
    index metadata.
    """
    lines = content.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    try:
        end = next(index for index, line in enumerate(lines[1:], 1) if line.strip() == "---")
    except StopIteration:
        return {}
    fields: dict[str, str] = {}
    for line in lines[1:end]:
        match = re.match(r"^\s*-?\s*([A-Za-z][A-Za-z0-9_-]*)\s*:\s*(.*?)\s*$", line)
        if match:
            fields[match.group(1)] = match.group(2).strip()
    return fields


def _frontmatter_value(content: str, key: str) -> str:
    value = _frontmatter_fields(content).get(key, "")
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        return value[1:-1]
    return value.strip("`")


def _frontmatter_list(content: str, key: str) -> list[str]:
    """Return a scalar or bracket-list frontmatter value as strings."""
    value = _frontmatter_value(content, key).strip()
    if not value:
        return []
    if value.startswith("[") and value.endswith("]"):
        value = value[1:-1].strip()
    if not value:
        return []
    values = []
    for item in re.split(r"\s*,\s*", value):
        item = item.strip().strip("`")
        if len(item) >= 2 and item[0] == item[-1] and item[0] in {'\"', "'"}:
            item = item[1:-1]
        if item:
            values.append(item)
    return values


def rebuild_index(target_root: Path, confirmed: bool) -> dict:
    """Rebuild the deterministic target entity index from authoritative files."""
    require_confirmed(confirmed)
    with store_lock(target_root):
        payload, code = _target_validate_unlocked(target_root)
        if code:
            raise StoreError("Target package is invalid: " + "; ".join(payload["issues"]))
        marker = _target_marker(target_root)
        entries: list[dict] = []
        authority = target_root / "权威"
        source_hash_parts: list[str] = []
        if authority.is_dir():
            for path in sorted(authority.rglob("*.md"), key=lambda item: item.relative_to(target_root).as_posix()):
                if path.name == "README.md":
                    continue
                rel = path.relative_to(target_root).as_posix()
                content = read_text(path)
                digest = sha256_file(path)
                source_hash_parts.append(f"{rel}:{digest}")
                parent_name = path.parent.name
                kind = {"声明": "Claim", "事件": "Event", "决策": "Decision"}.get(path.parent.parent.name, "")
                if not kind:
                    kind = {"声明": "Claim", "事件": "Event", "决策": "Decision"}.get(parent_name, "Claim")
                item_id = (
                    _frontmatter_value(content, "claim_id")
                    or _frontmatter_value(content, "event_id")
                    or _frontmatter_value(content, "decision_id")
                    or _frontmatter_value(content, "draft_id")
                    or _frontmatter_value(content, "id")
                    or path.stem
                )
                topic_ids = []
                for field in ("topic_id", "topic_ids", "cross_topic_ids"):
                    for value in _frontmatter_list(content, field):
                        if value not in topic_ids:
                            topic_ids.append(value)
                status = _frontmatter_value(content, "status") or "unknown"
                source_refs = []
                for field in ("source_ref", "source_refs"):
                    for value in _frontmatter_list(content, field):
                        if value not in source_refs:
                            source_refs.append(value)
                allowed_uses = []
                for field in ("allowed_use", "allowed_uses"):
                    for value in _frontmatter_list(content, field):
                        if value not in allowed_uses:
                            allowed_uses.append(value)
                entries.append(
                    {
                        "id": item_id,
                        "topic_ids": topic_ids,
                        "kind": kind,
                        "status": status,
                        "source_refs": source_refs,
                        "sensitivity": _frontmatter_value(content, "sensitivity") or "unknown",
                        "allowed_uses": allowed_uses,
                        "path": rel,
                        "sha256": digest,
                    }
                )
        index_source_hash = hashlib.sha256("\n".join(source_hash_parts).encode("utf-8")).hexdigest()
        matrix_path = target_root / "主题覆盖矩阵.md"
        index_source_matrix_version = sha256_file(matrix_path) if matrix_path.is_file() else ""
        index = {
            "layout": marker["layout"],
            "layout_version": int(marker["layout_version"]),
            "generated_at": now_utc(),
            "index_source_hash": index_source_hash,
            "index_source_version": str(marker.get("profile_version", marker.get("source_profile_version", ""))),
            "index_source_progress_version": str(marker.get("progress_version", marker.get("source_progress_version", ""))),
            "index_source_matrix_version": index_source_matrix_version,
            "entries": entries,
        }
        atomic_write(target_root / "权威" / "声明索引.json", serialize_json(index))
        marker["index_source_hash"] = index_source_hash
        marker["index_generated_at"] = index["generated_at"]
        marker["index_source_matrix_version"] = index_source_matrix_version
        _write_target_marker(target_root, marker)
        manifest = _target_manifest(target_root, marker)
        manifest["index_source_hash"] = index_source_hash
        manifest["index_generated_at"] = index["generated_at"]
        manifest["index_source_matrix_version"] = index_source_matrix_version
        atomic_write(target_root / "manifest.json", serialize_json(manifest))
        atomic_write(
            target_root / "资料索引.md",
            "# 资料索引\n\n"
            f"- 布局：{marker['layout']}\n"
            f"- 权威条目数：{len(entries)}\n"
            f"- 索引源哈希：{index_source_hash}\n"
            f"- 索引源矩阵版本：{index_source_matrix_version}\n"
            f"- 生成时间：{index['generated_at']}\n",
        )
        return {
            "ok": True,
            "command": "rebuild-index",
            "root": str(target_root),
            "layout": marker["layout"],
            "entry_count": str(len(entries)),
            "index_source_hash": index_source_hash,
            "index_source_matrix_version": index_source_matrix_version,
            "generated_at": index["generated_at"],
        }


def switch_layout(
    canonical_root: Path,
    target_root: Path,
    migration_id: str | None,
    expected_version: str | None,
    expected_progress_version: str | None,
    confirmed: bool,
    simulate_failure: bool = False,
) -> dict:
    """Activate a validated target package at the canonical root.

    The old canonical tree is snapshotted under ``历史版本`` before any
    target files are copied.  A durable layout transaction marker plus source
    hash/version fences make interruption and rollback explicit.
    """
    require_confirmed(confirmed)
    migration_id = _safe_migration_id(migration_id)
    _assert_independent_roots(canonical_root, target_root)
    with _lock_roots(canonical_root, target_root):
        source_payload, source_code = validate_space(canonical_root)
        if source_code and not (
            canonical_root.is_dir()
            and (canonical_root / STATE_FILE).is_file()
            and parse_key_values(canonical_root / STATE_FILE).get("layout") == "target"
        ):
            raise StoreError("Canonical source is invalid: " + "; ".join(source_payload["issues"]))
        source_state = parse_state(canonical_root / STATE_FILE)
        # Idempotent retry after a completed switch.
        if source_state.get("layout") == "target" and source_state.get("migration_id") == migration_id:
            target_payload, target_code = _target_validate_unlocked(canonical_root, "target")
            if target_code:
                raise StoreError("Canonical target is invalid: " + "; ".join(target_payload["issues"]))
            return {
                "ok": True,
                "command": "switch-layout",
                "root": str(canonical_root),
                "target": str(target_root),
                "migration_id": migration_id,
                "layout": "target",
                "idempotent": True,
                "source_unchanged": True,
            }
        source = _compat_source_snapshot(canonical_root)
        if expected_version is not None and expected_version != source["profile"]["version"]:
            raise StoreError(f"Version conflict: expected {expected_version}, current {source['profile']['version']}.")
        if expected_progress_version is not None and expected_progress_version != source["progress"]["version"]:
            raise StoreError(
                f"Progress version conflict: expected {expected_progress_version}, current {source['progress']['version']}."
            )
        target_payload, target_code = _target_validate_unlocked(target_root)
        if target_code:
            raise StoreError("Target package is invalid: " + "; ".join(target_payload["issues"]))
        target_marker = _target_marker(target_root)
        if target_marker["migration_id"] != migration_id:
            raise StoreError("Target migration_id does not match the requested migration.")
        if target_marker.get("layout") != "target":
            raise StoreError("switch-layout requires a formal target with layout=target; run migrate-apply first.")
        target_manifest = _target_manifest(target_root, target_marker)
        _source_matches_manifest(
            canonical_root,
            target_manifest,
            target_marker,
            expected_version=expected_version,
            expected_progress_version=expected_progress_version,
        )
        # Keep the documented compatibility snapshot name stable so an
        # operator can locate/rollback a switch without reading transaction
        # internals.  Version is part of the name and comes from the fenced
        # pre-switch source cursor.
        snapshot = _snapshot_root(canonical_root, migration_id, source["profile"]["version"])
        _write_layout_transaction(
            canonical_root,
            {
                "migration_id": migration_id,
                "snapshot": relative_to_root(canonical_root, snapshot),
                "operation": "switch-layout",
                "target": str(target_root),
                "created_at": now_utc(),
            },
        )
        try:
            # Do not import a target's history/backup/trash into the
            # canonical history; the pre-switch snapshot remains the sole
            # rollback source and avoids duplicate sensitive copies.
            _copy_tree_contents(
                target_root,
                canonical_root,
                skip={"历史版本", ".backups", ".trash", LOCK_DIR, LAYOUT_TRANSACTION_FILE, STATE_FILE, "manifest.json"},
            )
            # Fill compatibility files absent from a draft from the source;
            # this keeps record-turn/stage available immediately after switch.
            for name in TARGET_COMPAT_FILES:
                if not (canonical_root / name).is_file():
                    source_copy = snapshot / name
                    if source_copy.is_file():
                        _copy_file_atomic(source_copy, canonical_root / name)
            formal_state = dict(source_state)
            formal_state.update(target_marker)
            formal_state.update(
                {
                    "layout": "target",
                    "layout_version": target_marker.get("layout_version", "1"),
                    "schema_version": TARGET_FORMAL_SCHEMA,
                    "migration_id": migration_id,
                    "profile_version": source["profile"]["version"],
                    "progress_version": source["progress"]["version"],
                    "source_profile_version": source["profile"]["version"],
                    "source_progress_version": source["progress"]["version"],
                    "source_profile_sha256": source["profile"]["sha256"],
                    "source_progress_sha256": source["progress"]["sha256"],
                    "source_pending_sha256": source["pending"]["sha256"],
                    # The owner has confirmed the physical switch. Remaining
                    # review belongs to migrated entities, not activation.
                    "authority_status": "active-pending-review",
                    "updated_at": now_utc(),
                }
            )
            _write_target_marker(canonical_root, formal_state)
            target_manifest["layout"] = "target"
            target_manifest["schema_version"] = TARGET_FORMAL_SCHEMA
            target_manifest["layout_version"] = int(target_marker.get("layout_version", "1"))
            target_manifest["authority_status"] = "active-pending-review"
            target_manifest["activated_at"] = now_utc()
            target_manifest["source"] = _merge_source_manifest(target_manifest.get("source"), source)
            atomic_write(canonical_root / "manifest.json", serialize_json(target_manifest))
            _update_migration_manifest(canonical_root, source, migration_id, "target")
            if simulate_failure:
                raise StoreError("simulated failure during layout switch")
            checked, checked_code = _target_validate_unlocked(canonical_root, "target")
            if checked_code:
                raise StoreError("Post-switch validation failed: " + "; ".join(checked["issues"]))
            (canonical_root / LAYOUT_TRANSACTION_FILE).unlink()
        except Exception as exc:
            try:
                _restore_snapshot(canonical_root, snapshot)
                (canonical_root / LAYOUT_TRANSACTION_FILE).unlink(missing_ok=True)
            except Exception as rollback_error:
                raise StoreError(
                    f"Layout switch failed: {exc}. Rollback failed: {rollback_error}; run rollback-layout."
                ) from exc
            raise StoreError(f"Layout switch failed and was rolled back: {exc}") from exc
        return {
            "ok": True,
            "command": "switch-layout",
            "root": str(canonical_root),
            "target": str(target_root),
            "migration_id": migration_id,
            "layout": "target",
            "profile_version": source["profile"]["version"],
            "progress_version": source["progress"]["version"],
            "snapshot": str(snapshot),
            # Activation intentionally changes the canonical root; the old
            # bytes remain available through the returned snapshot.
            "source_unchanged": False,
            "source_snapshot_preserved": True,
            "idempotent": False,
        }


def rollback_layout(root: Path, migration_id: str, confirmed: bool) -> dict:
    """Restore the exact pre-switch compatibility tree from a layout snapshot."""
    require_confirmed(confirmed)
    migration_id = _safe_migration_id(migration_id)
    with store_lock(root):
        snapshot: Path | None = None
        if (root / LAYOUT_TRANSACTION_FILE).is_file():
            tx = _read_layout_transaction(root)
            if str(tx.get("migration_id")) != migration_id:
                raise StoreError("Layout transaction migration_id does not match.")
            snapshot = transaction_target(root, str(tx["snapshot"]))
        else:
            history = root / "历史版本"
            candidates = [
                path
                for pattern in (f"compat-v*-{migration_id}*", f".hello-layout-{migration_id}-*")
                for path in history.glob(pattern)
                if path.is_dir()
                and (path / "snapshot.json").is_file()
                and _snapshot_belongs_to(path, migration_id)
            ]
            if candidates:
                snapshot = sorted(candidates, key=lambda path: path.name)[-1]
        if snapshot is None or not snapshot.is_dir():
            raise StoreError("No layout snapshot found for migration_id.")
        _restore_snapshot(root, snapshot)
        (root / LAYOUT_TRANSACTION_FILE).unlink(missing_ok=True)
        payload, code = validate_space(root)
        if code:
            raise StoreError("Rollback completed but restored root is invalid: " + "; ".join(payload["issues"]))
        state = parse_state(root / STATE_FILE)
        return {
            "ok": True,
            "command": "rollback-layout",
            "root": str(root),
            "migration_id": migration_id,
            "snapshot": str(snapshot),
            "layout": state.get("layout", "compatibility"),
            "profile_version": str(state.get("profile_version", "")),
            "progress_version": str(state.get("progress_version", "")),
        }


def require_active_layout(root: Path, state: Dict[str, str], operation: str) -> None:
    layout = state.get("layout", "compatibility")
    if layout == "target-draft":
        raise StoreError(
            f"{operation} cannot write a target-draft package; run migrate-apply/switch-layout after confirmation."
        )
    if layout not in {"compatibility", "target", ""}:
        raise StoreError(f"Unsupported profile layout for {operation}: {layout}")


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
    # A root-level target marker is authoritative for layout detection.  Do
    # not feed target packages through the schema-2 section validator; doing
    # so would either reject the aggregate projection or, worse, invite a
    # legacy writer to overwrite entity files.
    if root.is_dir() and (root / STATE_FILE).is_file():
        try:
            marker_probe = parse_key_values(root / STATE_FILE)
        except StoreError:
            marker_probe = {}
        if marker_probe.get("layout") in TARGET_LAYOUTS:
            payload, code = _target_validate_unlocked(root)
            payload["command"] = "validate"
            if (root / LAYOUT_TRANSACTION_FILE).exists() and not ignore_transaction:
                payload["issues"].append(
                    "Interrupted layout transaction exists; run rollback-layout --confirmed --root <authorized-root> --migration-id <id>"
                )
                payload["ok"] = False
                code = 1
            return payload, code
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
    if root.is_dir() and (root / STATE_FILE).is_file():
        try:
            marker_probe = parse_key_values(root / STATE_FILE)
        except StoreError:
            marker_probe = {}
        if marker_probe.get("layout") in TARGET_LAYOUTS:
            return target_status(root)
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
    require_active_layout(root, state, "configure")
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
    require_active_layout(root, state, "record-disclosure")
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
    state = require_valid(root)
    if state.get("layout") == "target":
        raise StoreError("diff is only available for a compatibility schema-2 root; use target-validate/rebuild-index.")
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
    require_active_layout(root, state, "stage")
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
    if state.get("layout") == "target":
        raise StoreError("apply is only available for a compatibility schema-2 root; update target entities explicitly.")
    require_active_layout(root, state, "apply")
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
        # Formal target roots retain the compatibility cursor but keep their
        # target schema marker; downgrading it to schema 2 would make the
        # package fail closed on the next status/validate call.
        state["schema_version"] = TARGET_FORMAL_SCHEMA if state.get("layout") == "target" else "2"
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
    require_active_layout(root, state, "record-turn")
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
        # Preserve the formal target marker while advancing its compatibility
        # progress cursor; a target root must not silently downgrade to
        # schema-2 after a recorded interview turn.
        state["schema_version"] = TARGET_FORMAL_SCHEMA if state.get("layout") == "target" else "2"
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
    require_active_layout(root, state, "withdraw")
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
    # Target entries use ordinary YAML frontmatter (without a Markdown list
    # dash).  Keep this fixture synthetic so index parsing cannot regress to
    # the old `- key:`-only pattern unnoticed.
    frontmatter_fixture = (
        "---\n"
        "draft_id: D-fixture\n"
        "kind: Claim\n"
        "topic_id: capability\n"
        "cross_topic_ids: [work, values]\n"
        "status: draft\n"
        "source_ref: source://fixture\n"
        "sensitivity: medium\n"
        "allowed_uses: local-review-only\n"
        "---\n"
    )
    assert _frontmatter_value(frontmatter_fixture, "draft_id") == "D-fixture"
    assert _frontmatter_value(frontmatter_fixture, "status") == "draft"
    saved_hello_home = os.environ.get("HELLO_HOME")
    os.environ["HELLO_HOME"] = str(Path(tempfile.gettempdir()) / "must-not-be-used")
    try:
        for blank_root in ("", "   ", "\t\r\n", "\u00a0"):
            try:
                resolve_root(blank_root)
                raise AssertionError("an explicit blank --root fell back to HELLO_HOME")
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
        (["status", "--root", "   "], "status"),
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
    # Target-layout protocol probes use a separate fixture so the legacy
    # schema-2 assertions above remain independent.  No user path or body is
    # read by this self-test.
    with tempfile.TemporaryDirectory(prefix="hello-target-self-test-") as target_temp:
        base = Path(target_temp)
        source_root = base / "source"
        draft_root = base / "draft"
        formal_root = base / "formal"
        canonical_root = base / "canonical"
        init_space(source_root, True)
        init_space(canonical_root, True)
        source_bytes = {
            name: (source_root / name).read_bytes()
            for name in ("个人全景档案.md", "访谈进度.md", "待确认信息.md", STATE_FILE)
        }
        plan = migrate_plan(source_root, draft_root, "self-test-migration", True)
        assert plan["created"] is True
        target_payload, target_code = target_validate(draft_root)
        assert target_code == 0, target_payload
        entity = draft_root / "权威" / "声明" / "capability" / "CL-self-test.md"
        entity.parent.mkdir(parents=True)
        atomic_write(
            entity,
            "---\n- claim_id: CL-self-test\n- topic_id: capability\n- status: draft\n---\n\n虚构测试声明。\n",
        )
        rebuilt = rebuild_index(draft_root, True)
        assert rebuilt["entry_count"] == "1"
        promoted = migrate_apply(
            source_root,
            draft_root,
            formal_root,
            "self-test-migration",
            plan["source_profile_version"],
            plan["source_progress_version"],
            True,
        )
        assert promoted["layout"] == "target"
        formal_payload, formal_code = target_validate(formal_root, "target")
        assert formal_code == 0, formal_payload
        assert all((source_root / name).read_bytes() == value for name, value in source_bytes.items())
        switched = switch_layout(
            canonical_root,
            formal_root,
            "self-test-migration",
            "1",
            "1",
            True,
        )
        assert switched["layout"] == "target"
        canonical_status, canonical_code = status(canonical_root)
        assert canonical_code == 0 and canonical_status["layout"] == "target"
        rollback = rollback_layout(canonical_root, "self-test-migration", True)
        assert rollback["layout"] in {"compatibility", ""}
        assert (canonical_root / "个人全景档案.md").read_bytes() == source_bytes["个人全景档案.md"]
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
    item = sub.add_parser("target-validate")
    root_argument(item)
    item.add_argument("--target")
    item = sub.add_parser("migrate-plan")
    root_argument(item)
    item.add_argument("--target")
    item.add_argument("--destination")
    item.add_argument("--migration-id")
    item.add_argument("--confirmed", action="store_true")
    item = sub.add_parser("migrate-apply")
    root_argument(item)
    item.add_argument("--destination", required=True)
    item.add_argument("--target", required=True)
    item.add_argument("--migration-id")
    item.add_argument("--expected-version", required=True, type=positive_integer)
    item.add_argument("--expected-progress-version", required=True, type=positive_integer)
    item.add_argument("--confirmed", action="store_true")
    item.add_argument("--simulate-failure", action="store_true")
    item = sub.add_parser("rebuild-index")
    root_argument(item)
    item.add_argument("--target")
    item.add_argument("--confirmed", action="store_true")
    item = sub.add_parser("switch-layout")
    root_argument(item)
    item.add_argument("--target", required=True)
    item.add_argument("--migration-id", required=True)
    item.add_argument("--expected-version", required=True, type=positive_integer)
    item.add_argument("--expected-progress-version", required=True, type=positive_integer)
    item.add_argument("--confirmed", action="store_true")
    item.add_argument("--simulate-failure", action="store_true")
    item = sub.add_parser("rollback-layout")
    root_argument(item)
    item.add_argument("--migration-id", required=True)
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
        if args.command in MUTATING_COMMANDS and args.command != "rebuild-index" and args.root is None:
            # HELLO_HOME remains a convenient read-only discovery fallback,
            # but a write must name its exact profile root.  This fail-closed
            # guard prevents a dropped --root value from mutating whichever
            # personal space happens to be in the process environment.
            raise StoreError("Mutating commands require an explicit --root.")
        if args.command == "rebuild-index" and args.root is None and args.target is None:
            raise StoreError("rebuild-index requires an explicit --root or --target.")
        # Target-only commands may name their root with --target.  They must
        # never silently fall back to HELLO_HOME when an explicit target path
        # was supplied.
        if args.command in {"target-validate", "rebuild-index"} and args.target is not None:
            root = resolve_root(args.target)
        else:
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
        if args.command == "target-validate":
            payload, code = target_validate(root)
            emit(payload)
            return code
        if args.command == "migrate-plan":
            target_value = args.target or args.destination
            if not target_value:
                raise StoreError("migrate-plan requires --target (or --destination).")
            if args.confirmed and args.root is None:
                raise StoreError("Confirmed migrate-plan requires an explicit --root.")
            emit(migrate_plan(root, Path(target_value), args.migration_id, args.confirmed))
            return 0
        if args.command == "migrate-apply":
            if not args.destination and not args.target:
                raise StoreError("migrate-apply requires --destination or --target.")
            draft = None
            formal = None
            if args.destination and args.target:
                first = Path(args.destination).expanduser().resolve(strict=False)
                second = Path(args.target).expanduser().resolve(strict=False)
                # Accept both spellings used by host wrappers: either
                # --destination=draft --target=formal or
                # --target=draft --destination=formal.  An existing marker
                # is the unambiguous discriminator; equal paths promote
                # in-place without copying.
                if first == second:
                    draft, formal = first, None
                else:
                    first_layout = ""
                    second_layout = ""
                    try:
                        first_layout = _target_marker(first).get("layout", "")
                    except StoreError:
                        pass
                    try:
                        second_layout = _target_marker(second).get("layout", "")
                    except StoreError:
                        pass
                    if second_layout == "target-draft" and first_layout != "target-draft":
                        draft, formal = second, first
                    else:
                        draft, formal = first, second
            else:
                draft = Path(args.destination or args.target).expanduser().resolve(strict=False)
            emit(
                migrate_apply(
                    root,
                    draft,
                    formal,
                    args.migration_id,
                    args.expected_version,
                    args.expected_progress_version,
                    args.confirmed,
                    args.simulate_failure,
                )
            )
            return 0
        if args.command == "rebuild-index":
            emit(rebuild_index(root, args.confirmed))
            return 0
        if args.command == "switch-layout":
            emit(
                switch_layout(
                    root,
                    Path(args.target).expanduser().resolve(strict=False),
                    args.migration_id,
                    args.expected_version,
                    args.expected_progress_version,
                    args.confirmed,
                    args.simulate_failure,
                )
            )
            return 0
        if args.command == "rollback-layout":
            emit(rollback_layout(root, args.migration_id, args.confirmed))
            return 0
        raise StoreError(f"Unknown command: {args.command}")
    except (StoreError, OSError, UnicodeError, AssertionError) as exc:
        emit({"ok": False, "command": args.command, "error": str(exc)})
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
