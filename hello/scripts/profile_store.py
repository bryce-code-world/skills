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
TRANSACTION_FILE = ".hello-transaction"
CAPTURE_MODES = {"auto-stage", "prompt", "explicit"}
REVIEW_STAGES = {"baseline", "first-review", "stable"}
UPDATE_TYPES = {"新增", "状态变化", "事实纠正", "解释变化", "假设验证", "撤回隐藏"}
CANDIDATE_ID = re.compile(r"^C-[0-9TZ-]+$")
SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
SESSION_ID = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}[A-Za-z0-9._-]{0,117}$")
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
    for number, raw in enumerate(read_text(path).splitlines(), 1):
        if not raw or raw.startswith("#"):
            continue
        if "=" not in raw:
            raise StoreError(f"Invalid key=value line {number} in {path.name}.")
        key, value = raw.split("=", 1)
        if not key or key in values:
            raise StoreError(f"Invalid or duplicate key on line {number} in {path.name}.")
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
        "last_session_id",
        "last_turn_id",
    )
    keys = [key for key in order if key in state] + sorted(key for key in state if key not in order)
    atomic_write(path, "".join(f"{key}={state.get(key, '')}\n" for key in keys))


def valid_iso8601(value: str, allow_empty: bool = True) -> bool:
    if not value:
        return allow_empty
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return "T" in value


def effective_progress_version(state: Dict[str, str]) -> int:
    return int(state.get("progress_version", "1"))


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
        try:
            if int(state.get(key, "0")) < 1:
                raise ValueError
        except ValueError:
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
    for key in ("last_confirmed_at", "next_review_at"):
        if key in state and not valid_iso8601(state[key]):
            issues.append(f"{key} must be empty or ISO 8601")
    return issues


def one_match(pattern: str, content: str, label: str) -> tuple[str | None, list[str]]:
    matches = re.findall(pattern, content, flags=re.MULTILINE)
    if len(matches) != 1:
        return None, [f"{label} must appear exactly once"]
    return matches[0], []


def validate_profile_content(content: str, expected_version: int | None = None) -> list[str]:
    issues: list[str] = []
    if not content.startswith("# 个人全景档案\n"):
        issues.append("Profile must start with # 个人全景档案")
    raw_version, found = one_match(r"^- 资料版本：([0-9]+)$", content, "资料版本 metadata")
    issues.extend(found)
    _, found = one_match(r"^- 最近确认时间：(.+)$", content, "最近确认时间 metadata")
    issues.extend(found)
    if raw_version is not None:
        version = int(raw_version)
        if version < 1:
            issues.append("Profile version must be positive")
        if expected_version is not None and version != expected_version:
            issues.append(f"Profile version {version} does not match state version {expected_version}")
    for heading in PROFILE_SECTIONS:
        if len(re.findall(rf"(?m)^{re.escape(heading)}$", content)) != 1:
            issues.append(f"Missing or duplicate profile section: {heading[3:]}")
    return issues


def progress_version_from_content(content: str) -> tuple[int | None, list[str]]:
    matches = re.findall(r"(?m)^- 进度版本：([0-9]+)$", content)
    if not matches:
        return None, []
    if len(matches) != 1:
        return None, ["进度版本 metadata must appear at most once"]
    return int(matches[0]), []


def validate_progress_content(content: str, expected_version: int | None, require_version: bool) -> list[str]:
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


def validate_log_content(content: str, profile_version: int) -> list[str]:
    issues: list[str] = []
    headings = [int(value) for value in re.findall(r"(?m)^## R([0-9]+) · ", content)]
    if len(headings) != len(set(headings)):
        issues.append("Iteration log contains duplicate version headings")
    if headings != sorted(headings):
        issues.append("Iteration log versions must be ascending")
    if profile_version > 1 and profile_version not in headings:
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


def init_space(root: Path, confirmed: bool) -> dict:
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
            shutil.copyfile(template_root / name, target)
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
                "last_session_id": "",
                "last_turn_id": "",
            },
        )
        created.append(STATE_FILE)
    return {"ok": True, "command": "init", "root": str(root), "created": created}


def validate_space(root: Path, ignore_transaction: bool = False) -> Tuple[dict, int]:
    issues: list[str] = []
    state: Dict[str, str] | None = None
    if not root.is_dir():
        issues.append("Root directory does not exist")
    else:
        if (root / TRANSACTION_FILE).exists() and not ignore_transaction:
            issues.append("Interrupted transaction exists; run recover --confirmed")
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
            profile_version = int(state["profile_version"])
            progress_version = effective_progress_version(state)
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
        "progress_version": effective_progress_version(state),
        "capture_mode": state["capture_mode"],
        "review_stage": state["review_stage"],
        "last_confirmed_at": state["last_confirmed_at"],
        "next_review_at": state["next_review_at"],
        "last_session_id": state.get("last_session_id", ""),
        "last_turn_id": state.get("last_turn_id", ""),
        "pending_candidates": pending,
        "progress": progress_summary(read_text(root / "访谈进度.md")),
    }, 0


def validate_review_time(value: str) -> str:
    if value in {"", "none"}:
        return ""
    if not valid_iso8601(value, allow_empty=False):
        raise StoreError("--next-review-at must be ISO 8601 or none.")
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
        if review_stage == "first-review" and next_review_at in {None, "", "none"} and not state.get("next_review_at"):
            raise StoreError("Entering first-review requires --next-review-at.")
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
    content, version_count = re.subn(r"(?m)^- 资料版本：.*$", f"- 资料版本：{version}", content, count=1)
    content, time_count = re.subn(r"(?m)^- 最近确认时间：.*$", f"- 最近确认时间：{confirmed_at}", content, count=1)
    if version_count != 1 or time_count != 1:
        raise StoreError("Candidate profile must contain 资料版本 and 最近确认时间 metadata lines.")
    return content


def update_progress_header(content: str, version: int) -> str:
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
    if marker.exists():
        raise StoreError("Interrupted transaction exists; run recover --confirmed.")
    values = {"schema_version": "1", **values}
    atomic_write(marker, "".join(f"{key}={value}\n" for key, value in values.items()))


def transaction_target(root: Path, relative: str) -> Path:
    target = (root / relative).resolve()
    try:
        target.relative_to(root.resolve())
    except ValueError as exc:
        raise StoreError("Transaction backup path escapes profile root.") from exc
    return target


def recover_transaction(root: Path, confirmed: bool) -> dict:
    require_confirmed(confirmed)
    marker = root / TRANSACTION_FILE
    if not marker.is_file():
        raise StoreError("No interrupted transaction exists.")
    values = parse_key_values(marker)
    mappings = {
        "profile_backup": root / "个人全景档案.md",
        "log_backup": root / "迭代日志.md",
        "state_backup": root / STATE_FILE,
        "progress_backup": root / "访谈进度.md",
    }
    restored: list[str] = []
    for key, target in mappings.items():
        relative = values.get(key)
        if relative:
            backup = transaction_target(root, relative)
            if not backup.is_file():
                raise StoreError(f"Missing transaction backup: {relative}")
            atomic_write(target, read_text(backup))
            restored.append(target.name)
    record_path = values.get("record_path")
    if record_path and values.get("record_created") == "true":
        target = transaction_target(root, record_path)
        if target.is_file():
            target.unlink()
    marker.unlink()
    payload, code = validate_space(root)
    if code:
        raise StoreError("Recovery completed but profile space is invalid: " + "; ".join(payload["issues"]))
    return {"ok": True, "command": "recover", "root": str(root), "restored": restored}


def rollback_after_failure(root: Path, original: Exception) -> None:
    try:
        recover_transaction(root, True)
    except Exception as rollback_error:
        raise StoreError(
            f"Operation failed: {original}. Automatic rollback failed: {rollback_error}. Run recover --confirmed."
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


def apply_profile(
    root: Path,
    input_path: Path,
    summary_path: Path,
    expected_version: int,
    confirmed: bool,
    simulate_failure: bool = False,
) -> dict:
    require_confirmed(confirmed)
    state = require_valid(root)
    current_version = int(state["profile_version"])
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
    new_version = current_version + 1
    candidate = update_profile_header(candidate, new_version, current)
    file_stamp = stamp()
    history = copy_unique(profile_path, root / "历史版本", f"{file_stamp}-v{current_version}-个人全景档案.md")
    backup = copy_unique(profile_path, root / ".backups" / "profile", f"{file_stamp}-v{current_version}-个人全景档案.md")
    transaction_dir = root / ".backups" / "transactions"
    log_path = root / "迭代日志.md"
    state_path = root / STATE_FILE
    log_backup = copy_unique(log_path, transaction_dir, f"{file_stamp}-v{current_version}-迭代日志.md")
    state_backup = copy_unique(state_path, transaction_dir, f"{file_stamp}-v{current_version}-hello-state")
    begin_transaction(
        root,
        {
            "kind": "apply",
            "profile_backup": relative_to_root(root, backup),
            "log_backup": relative_to_root(root, log_backup),
            "state_backup": relative_to_root(root, state_backup),
        },
    )
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
        state["profile_version"] = str(new_version)
        state["updated_at"] = current
        state["last_confirmed_at"] = current
        write_state(state_path, state)
        payload, code = validate_space(root, ignore_transaction=True)
        if code:
            raise StoreError("Post-write validation failed: " + "; ".join(payload["issues"]))
    except Exception as exc:
        rollback_after_failure(root, exc)
    (root / TRANSACTION_FILE).unlink()
    return {
        "ok": True,
        "command": "apply",
        "root": str(root),
        "old_version": current_version,
        "profile_version": new_version,
        "history": str(history),
        "backup": str(backup),
    }


def record_turn(
    root: Path,
    input_path: Path,
    progress_input: Path,
    session_id: str,
    turn_id: str,
    expected_progress_version: int,
    confirmed: bool,
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
    if state.get("last_session_id") == session_id and state.get("last_turn_id") == turn_id and record_path.exists():
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
            "progress_version": effective_progress_version(state),
        }
    current_progress_version = effective_progress_version(state)
    if expected_progress_version != current_progress_version:
        raise StoreError(
            f"Progress version conflict: expected {expected_progress_version}, current {current_progress_version}."
        )
    progress_candidate = read_text(progress_input).strip() + "\n"
    issues = validate_progress_content(progress_candidate, None, False)
    if issues:
        raise StoreError("Invalid progress input: " + "; ".join(issues))
    new_progress_version = current_progress_version + 1
    progress_candidate = update_progress_header(progress_candidate, new_progress_version)
    record_created = not record_path.exists()
    if not record_created:
        raise StoreError("Turn id already exists but is not the current idempotency key.")
    file_stamp = stamp()
    transaction_dir = root / ".backups" / "transactions"
    progress_path = root / "访谈进度.md"
    state_path = root / STATE_FILE
    progress_backup = copy_unique(progress_path, transaction_dir, f"{file_stamp}-p{current_progress_version}-访谈进度.md")
    state_backup = copy_unique(state_path, transaction_dir, f"{file_stamp}-p{current_progress_version}-hello-state")
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
        state["updated_at"] = now_utc()
        write_state(state_path, state)
        payload, code = validate_space(root, ignore_transaction=True)
        if code:
            raise StoreError("Post-write validation failed: " + "; ".join(payload["issues"]))
    except Exception as exc:
        rollback_after_failure(root, exc)
    (root / TRANSACTION_FILE).unlink()
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
    }


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
        state = parse_state(root / STATE_FILE)
        assert state["capture_mode"] == "prompt"
        candidate_note = root.parent / "candidate.md"
        candidate_note.write_text("用户完成了一个重要项目。\n", encoding="utf-8")
        staged = stage_candidate(root, candidate_note, "经历", "自测", True)
        configured = configure_space(root, "auto-stage", None, None, True)
        assert configured["capture_mode"] == "auto-stage"
        profile_candidate = root.parent / "profile.md"
        profile_text = read_text(root / "个人全景档案.md").replace("尚未访谈。", "已完成一项自测。", 1)
        profile_candidate.write_text(profile_text, encoding="utf-8")
        summary = root.parent / "summary.md"
        summary.write_text(test_summary(), encoding="utf-8")
        try:
            apply_profile(root, profile_candidate, summary, 1, True, simulate_failure=True)
            raise AssertionError("simulated failure did not fail")
        except StoreError as exc:
            assert "rolled back" in str(exc)
        assert parse_state(root / STATE_FILE)["profile_version"] == "1"
        assert not (root / TRANSACTION_FILE).exists()
        applied = apply_profile(root, profile_candidate, summary, 1, True)
        assert applied["profile_version"] == 2
        assert parse_state(root / STATE_FILE)["review_stage"] == "baseline"
        turn_input = root.parent / "turn.md"
        turn_input.write_text("# 单轮记录\n\n- 已确认：自测。\n", encoding="utf-8")
        progress_input = root.parent / "progress.md"
        progress_input.write_text(read_text(root / "访谈进度.md").replace("尚未开始。", "下一项自测。"), encoding="utf-8")
        recorded = record_turn(root, turn_input, progress_input, "2030-01-01-session-1", "turn-1", 1, True)
        assert recorded["progress_version"] == 2
        retried = record_turn(root, turn_input, progress_input, "2030-01-01-session-1", "turn-1", 1, True)
        assert retried["idempotent"] is True
        try:
            record_turn(root, turn_input, progress_input, "2030-01-01-session-1", "turn-2", 1, True)
            raise AssertionError("progress version conflict did not fail")
        except StoreError:
            pass
        try:
            configure_space(root, None, None, "first-review", True)
            raise AssertionError("first-review without date did not fail")
        except StoreError:
            pass
        configure_space(root, None, "2030-01-01T00:00:00Z", "first-review", True)
        try:
            apply_profile(root, profile_candidate, summary, 1, True)
            raise AssertionError("version conflict did not fail")
        except StoreError:
            pass
        withdraw_candidate(root, staged["candidate_id"], True)
        final, code = validate_space(root)
        assert code == 0, final
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
    item = sub.add_parser("record-turn")
    root_argument(item)
    item.add_argument("--input", required=True)
    item.add_argument("--progress-input", required=True)
    item.add_argument("--session-id", required=True)
    item.add_argument("--turn-id", required=True)
    item.add_argument("--expected-progress-version", required=True, type=int)
    item.add_argument("--confirmed", action="store_true")
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
            emit(configure_space(root, args.capture_mode, args.next_review_at, args.review_stage, args.confirmed))
            return 0
        if args.command == "diff":
            sys.stdout.write(diff_profile(root, Path(args.input)))
            return 0
        if args.command == "stage":
            emit(stage_candidate(root, Path(args.input), args.kind, args.source, args.confirmed))
            return 0
        if args.command == "apply":
            emit(apply_profile(root, Path(args.input), Path(args.summary_input), args.expected_version, args.confirmed))
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
