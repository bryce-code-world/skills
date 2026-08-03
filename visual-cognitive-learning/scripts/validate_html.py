#!/usr/bin/env python3
"""Validate the deterministic offline single-HTML contract using stdlib only."""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
import tempfile
from pathlib import Path


if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="strict")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="strict")


VIOLATION_ORDER = [
    "missing-doctype",
    "missing-html",
    "missing-head",
    "missing-body",
    "missing-lang",
    "missing-title",
    "missing-viewport",
    "external-resource",
    "css-external-url",
    "network-api",
    "dynamic-code",
    "module-import",
    "duplicate-id",
    "unlabeled-control",
    "missing-reduced-motion",
    "missing-inline-style",
    "missing-static-content",
]


def has(pattern: str, text: str) -> bool:
    return re.search(pattern, text, re.IGNORECASE | re.DOTALL) is not None


def attributes(tag: str) -> dict[str, str]:
    return {
        name.lower(): value
        for name, _, value in re.findall(
            r"\b([\w:-]+)\s*=\s*([\"'])(.*?)\2", tag, re.DOTALL
        )
    }


def validate_text(content: str) -> list[str]:
    found: set[str] = set()

    if not has(r"<!doctype\s+html\s*>", content):
        found.add("missing-doctype")
    if not has(r"<html\b[^>]*>.*?</html\s*>", content):
        found.add("missing-html")
    if not has(r"<head\b[^>]*>.*?</head\s*>", content):
        found.add("missing-head")
    if not has(r"<body\b[^>]*>.*?</body\s*>", content):
        found.add("missing-body")
    html_tag = re.search(r"<html\b[^>]*>", content, re.IGNORECASE | re.DOTALL)
    if not html_tag or not attributes(html_tag.group(0)).get("lang", "").strip():
        found.add("missing-lang")
    title = re.search(r"<title\b[^>]*>(.*?)</title\s*>", content, re.I | re.S)
    if not title or not re.sub(r"\s+", "", title.group(1)):
        found.add("missing-title")
    if not has(r"<meta\b[^>]*\bname\s*=\s*([\"'])viewport\1", content):
        found.add("missing-viewport")

    resource_tags = re.findall(
        r"<(?:script|img|iframe|source|video|audio|link)\b[^>]*>",
        content,
        re.I | re.S,
    )
    for tag in resource_tags:
        attrs = attributes(tag)
        for key in ("src", "href"):
            value = attrs.get(key, "").strip()
            if value and not value.lower().startswith("data:") and not value.startswith("#"):
                found.add("external-resource")

    css_sources = re.findall(r"<style\b[^>]*>(.*?)</style\s*>", content, re.I | re.S)
    css_sources += re.findall(r"\bstyle\s*=\s*([\"'])(.*?)\1", content, re.I | re.S)
    css_text = "\n".join(item[-1] if isinstance(item, tuple) else item for item in css_sources)
    for match in re.finditer(r"url\(\s*([\"']?)(.*?)\1\s*\)", css_text, re.I | re.S):
        value = match.group(2).strip()
        if value and not value.lower().startswith("data:") and not value.startswith("#"):
            found.add("css-external-url")

    script_text = "\n".join(
        re.findall(r"<script\b[^>]*>(.*?)</script\s*>", content, re.I | re.S)
    )
    if has(
        r"\b(?:fetch|XMLHttpRequest|WebSocket|EventSource)\s*\(|"
        r"\bnavigator\s*\.\s*sendBeacon\s*\(",
        script_text,
    ):
        found.add("network-api")
    if has(r"\beval\s*\(|\bnew\s+Function\s*\(", script_text):
        found.add("dynamic-code")
    if has(r"<script\b[^>]*\btype\s*=\s*([\"'])module\1", content) or has(
        r"\bimport\s*(?:\(|[^;\n]*\bfrom\s*[\"'])", script_text
    ):
        found.add("module-import")

    ids = [
        value.strip()
        for _, value in re.findall(r"\bid\s*=\s*([\"'])(.*?)\1", content, re.I | re.S)
        if value.strip()
    ]
    if len(ids) != len(set(ids)):
        found.add("duplicate-id")

    label_targets = {
        value.strip()
        for _, value in re.findall(r"<label\b[^>]*\bfor\s*=\s*([\"'])(.*?)\1", content, re.I | re.S)
        if value.strip()
    }
    for control in re.findall(r"<(?:input|select|textarea)\b[^>]*>", content, re.I | re.S):
        attrs = attributes(control)
        if attrs.get("type", "").lower() == "hidden":
            continue
        if attrs.get("aria-label", "").strip() or attrs.get("aria-labelledby", "").strip():
            continue
        if attrs.get("id", "").strip() in label_targets:
            continue
        found.add("unlabeled-control")
        break

    if "prefers-reduced-motion" not in content.lower():
        found.add("missing-reduced-motion")
    if not has(r"<style\b[^>]*>.*?</style\s*>", content):
        found.add("missing-inline-style")

    body = re.search(r"<body\b[^>]*>(.*?)</body\s*>", content, re.I | re.S)
    visible = body.group(1) if body else ""
    visible = re.sub(r"<(?:script|style)\b[^>]*>.*?</(?:script|style)\s*>", " ", visible, flags=re.I | re.S)
    visible = re.sub(r"<[^>]+>", " ", visible)
    visible = html.unescape(visible)
    if len(re.sub(r"\s+", "", visible)) < 40:
        found.add("missing-static-content")

    return [code for code in VIOLATION_ORDER if code in found]


def validate_file(path: Path) -> tuple[Path, list[str]]:
    resolved = path.expanduser().resolve(strict=True)
    if not resolved.is_file():
        raise ValueError(f"Path is not a regular file: {resolved}")
    return resolved, validate_text(resolved.read_text(encoding="utf-8"))


def emit(payload: dict[str, object]) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


def self_test() -> None:
    valid = """<!doctype html><html lang="zh-CN"><head><meta name="viewport" content="width=device-width"><title>流程学习</title><style>body{color:#111}@media (prefers-reduced-motion: reduce){*{animation:none}}</style></head><body><main><h1>理解交付流程</h1><p>这个页面保留足够的静态说明，让脚本失效时仍能理解阶段、检查、异常处理和最终交付之间的关系。</p><label for="step">选择阶段</label><select id="step"><option>分析</option></select></main><script>document.documentElement.dataset.ready="true";</script></body></html>"""
    invalid = """<script type="module" src="https://example.com/a.js">fetch('https://example.com');eval('1');import('./x.js')</script><img src="https://example.com/x.png"><input id="same"><div id="same" style="background:url(https://example.com/x.png)"></div>"""

    with tempfile.TemporaryDirectory(prefix="visual-cognitive-learning-") as temp_dir:
        root = Path(temp_dir) / "中文 path"
        root.mkdir()
        good_path = root / "good.html"
        bad_path = root / "bad.html"
        good_path.write_text(valid, encoding="utf-8")
        bad_path.write_text(invalid, encoding="utf-8")
        _, good_result = validate_file(good_path)
        _, bad_result = validate_file(bad_path)
        if good_result:
            raise AssertionError(f"valid fixture failed: {good_result}")
        if bad_result != VIOLATION_ORDER:
            raise AssertionError(f"invalid fixture mismatch: {bad_result}")
        try:
            validate_file(root / "missing.html")
        except FileNotFoundError:
            pass
        else:
            raise AssertionError("missing path did not fail")


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("command", nargs="?")
    parser.add_argument("--path")
    args, extra = parser.parse_known_args()
    try:
        if extra:
            raise ValueError(f"Unexpected arguments: {' '.join(extra)}")
        if args.command == "self-test":
            if args.path:
                raise ValueError("self-test does not accept --path")
            self_test()
            emit({"ok": True, "command": "self-test", "tests": 3})
            return 0
        if args.command == "check":
            if not args.path:
                raise ValueError("check requires --path <html-file>")
            resolved, violations = validate_file(Path(args.path))
            emit(
                {
                    "ok": not violations,
                    "command": "check",
                    "path": str(resolved),
                    "violations": violations,
                }
            )
            return 1 if violations else 0
        raise ValueError("Expected: check --path <html-file> | self-test")
    except (OSError, UnicodeError, ValueError, AssertionError) as exc:
        emit({"ok": False, "command": args.command or "", "error": str(exc)})
        return 2


if __name__ == "__main__":
    sys.exit(main())
