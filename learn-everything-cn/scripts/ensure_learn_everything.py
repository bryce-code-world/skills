#!/usr/bin/env python3
"""Install the pinned learn-everything dependency without overwriting conflicts."""

import argparse
import hashlib
import json
import os
import shutil
import sys
import tempfile
import urllib.request
from pathlib import Path, PurePosixPath
from urllib.parse import urljoin


INSTALL_METADATA = ".learn-everything-install.json"


class VerificationError(ValueError):
    pass


def read_lock(path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def safe_relative_path(value):
    relative = PurePosixPath(value)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError(f"unsafe dependency path: {value}")
    return Path(*relative.parts)


def fetch_bytes(source_base, relative_path):
    with urllib.request.urlopen(urljoin(source_base, relative_path), timeout=30) as response:
        return response.read()


def validate_bytes(content, expected_hash, relative_path):
    actual_hash = hashlib.sha256(content).hexdigest()
    if actual_hash != expected_hash:
        raise VerificationError(
            f"hash mismatch for {relative_path}: expected {expected_hash}, got {actual_hash}"
        )


def emit(payload, as_json):
    if as_json:
        print(json.dumps(payload, ensure_ascii=False))
    else:
        print(f"{payload['status']}: {payload.get('path', payload.get('message', ''))}")


def metadata_for(lock, lock_path):
    return {
        "schema_version": lock["schema_version"],
        "dependency": lock["dependency"],
        "repository": lock["repository"],
        "ref": lock["ref"],
        "source_path": lock["source_path"],
        "lock_sha256": hashlib.sha256(lock_path.read_bytes()).hexdigest(),
        "files": [
            {"path": entry["path"], "sha256": entry["sha256"]}
            for entry in lock["files"]
        ],
    }


def write_metadata(target, lock, lock_path):
    metadata_path = target / INSTALL_METADATA
    content = json.dumps(metadata_for(lock, lock_path), ensure_ascii=False, indent=2) + "\n"
    if metadata_path.is_file() and metadata_path.read_text(encoding="utf-8") == content:
        return
    metadata_path.write_text(
        content,
        encoding="utf-8",
        newline="\n",
    )


def validate_directory(target, lock):
    issues = []
    for file_entry in lock["files"]:
        relative = safe_relative_path(file_entry["path"])
        dependency_file = target / relative
        if not dependency_file.is_file():
            if file_entry.get("required_for_existing", True):
                issues.append(f"missing {file_entry['path']}")
            continue
        actual_hash = hashlib.sha256(dependency_file.read_bytes()).hexdigest()
        if actual_hash != file_entry["sha256"]:
            issues.append(f"hash mismatch for {file_entry['path']}")
    identity_issue = skill_identity_issue(target / "SKILL.md", lock["dependency"])
    if identity_issue:
        issues.append(identity_issue)
    return issues


def skill_identity_issue(skill_file, expected_name):
    if not skill_file.is_file():
        return None
    lines = skill_file.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        return "SKILL.md has no YAML frontmatter"
    for line in lines[1:]:
        stripped = line.strip()
        if stripped == "---":
            break
        if stripped.startswith("name:"):
            actual_name = stripped.split(":", 1)[1].strip().strip('"\'')
            if actual_name == expected_name:
                return None
            return f"SKILL.md name is {actual_name!r}, expected {expected_name!r}"
    return "SKILL.md frontmatter has no name"


def repair_optional_files(target, lock, lock_path):
    for file_entry in lock["files"]:
        destination = target / safe_relative_path(file_entry["path"])
        bundled_path = file_entry.get("bundled_path")
        if destination.exists() or not bundled_path:
            continue
        content = (lock_path.parent / safe_relative_path(bundled_path)).read_bytes()
        validate_bytes(content, file_entry["sha256"], file_entry["path"])
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(content)


def install(lock, lock_path, dest_root, source_base):
    dependency = lock["dependency"]
    target = dest_root / dependency
    if target.exists():
        raise FileExistsError(f"dependency target already exists: {target}")

    dest_root.mkdir(parents=True, exist_ok=True)
    temp_path = Path(tempfile.mkdtemp(prefix=f".{dependency}-", dir=dest_root))
    try:
        for file_entry in lock["files"]:
            relative = safe_relative_path(file_entry["path"])
            source_path = file_entry.get("source", file_entry["path"])
            safe_relative_path(source_path)
            content = fetch_bytes(source_base, source_path)
            validate_bytes(content, file_entry["sha256"], file_entry["path"])
            destination = temp_path / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(content)

        identity_issue = skill_identity_issue(temp_path / "SKILL.md", dependency)
        if identity_issue:
            raise VerificationError(identity_issue)
        write_metadata(temp_path, lock, lock_path)
        os.replace(temp_path, target)
        return target.resolve()
    finally:
        if temp_path.exists():
            shutil.rmtree(temp_path)


def default_skill_roots():
    roots = []
    for directory in (Path.cwd(), *Path.cwd().parents):
        roots.append(directory / ".agents" / "skills")
    codex_home = os.environ.get("CODEX_HOME")
    if codex_home:
        roots.append(Path(codex_home) / "skills")
    roots.extend(
        [
            Path.home() / ".agents" / "skills",
            Path.home() / ".codex" / "skills",
        ]
    )
    unique = []
    seen = set()
    for root in roots:
        resolved = root.resolve()
        normalized = os.path.normcase(str(resolved))
        if normalized not in seen:
            unique.append(resolved)
            seen.add(normalized)
    return unique


def parse_args():
    skill_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--lock",
        type=Path,
        default=skill_root / "references" / "dependency-lock.json",
    )
    parser.add_argument(
        "--dest-root",
        type=Path,
    )
    parser.add_argument("--source-base")
    parser.add_argument("--json", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    try:
        lock = read_lock(args.lock)
        source_base = args.source_base or (
            "https://raw.githubusercontent.com/"
            f"{lock['repository']}/{lock['ref']}/"
        )
        roots = [args.dest_root.resolve()] if args.dest_root else default_skill_roots()
        existing_targets = [
            root / lock["dependency"]
            for root in roots
            if (root / lock["dependency"]).exists()
        ]
        if len(existing_targets) > 1:
            emit(
                {
                    "status": "conflict",
                    "path": str(existing_targets[0]),
                    "message": "multiple dependency installations found: "
                    + "; ".join(str(path) for path in existing_targets),
                },
                args.json,
            )
            return 3
        target = (
            existing_targets[0]
            if existing_targets
            else roots[0] / lock["dependency"]
        )
        if target.exists():
            issues = validate_directory(target, lock)
            if issues:
                emit(
                    {
                        "status": "conflict",
                        "path": str(target),
                        "message": "; ".join(issues),
                    },
                    args.json,
                )
                return 3
            repair_optional_files(target, lock, args.lock)
            write_metadata(target, lock, args.lock)
            emit({"status": "ready", "path": str(target)}, args.json)
            return 0
        install_root = (
            args.dest_root.resolve()
            if args.dest_root
            else (Path.home() / ".agents" / "skills").resolve()
        )
        target = install(lock, args.lock, install_root, source_base)
        emit({"status": "installed", "path": str(target)}, args.json)
        return 0
    except VerificationError as exc:
        emit({"status": "verification_failed", "message": str(exc)}, args.json)
        return 4
    except Exception as exc:
        emit({"status": "error", "message": str(exc)}, args.json)
        return 2


if __name__ == "__main__":
    sys.exit(main())
