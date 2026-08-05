#!/usr/bin/env python3
"""筛查中文成稿中的模板化文字形状，只报告候选，不自动改稿。"""

from __future__ import annotations

import argparse
import collections
import re
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Finding:
    line: int
    code: str
    label: str
    reason: str
    excerpt: str


@dataclass(frozen=True)
class Paragraph:
    position: int
    text: str
    han: int
    sentences: int


PATTERNS = (
    (
        "S1",
        "宏大通用开头",
        "开头没有直接进入当前问题、材料或判断",
        re.compile(r"(?:在当今|随着)[^。！？\n]{0,36}(?:时代|社会|技术|发展|背景|浪潮)"),
        240,
    ),
    (
        "S2",
        "预告代替内容",
        "检查是否可以直接进入正文",
        re.compile(r"(?:接下来|下面)(?:我们)?(?:将|会|来)?[^。！？\n]{0,28}(?:分析|探讨|介绍|展开|说明|看看)"),
        None,
    ),
    (
        "L1",
        "空泛转场",
        "检查该表达是否承担了真实逻辑关系",
        re.compile(r"(?:^|[。！？!?]\s*)(?:值得注意的是|需要强调的是|需要指出的是|从某种意义上说)"),
        None,
    ),
    (
        "L2",
        "假装深入",
        "检查后文是否增加了新的事实或推理",
        re.compile(r"(?:^|[。！？!?]\s*)(?:本质上|真正的问题(?:是|在于)|更深层次(?:看|来看))"),
        None,
    ),
    (
        "L9",
        "否定揭晓句",
        "该句式不是禁用项，只检查是否反复制造假冲突",
        re.compile(
            r"(?:不是[^。！？\n]{0,90}而是|并非[^。！？\n]{0,90}而是|"
            r"不在于[^。！？\n]{0,90}而在于|不只是?[^。！？\n]{0,90}(?:更是|还是))"
        ),
        None,
    ),
    (
        "L10",
        "营销或抽象词",
        "单个词不能证明问题，检查是否缺少主体、动作和后果",
        re.compile(r"(?:颠覆性|革命性|前所未有|赋能|抓手|闭环|底层逻辑|顶层设计|全链路|组合拳)"),
        None,
    ),
)

REPEATED_OPENERS = (
    "其实",
    "不过",
    "当然",
    "所以",
    "但是",
    "与此同时",
    "值得注意的是",
    "更重要的是",
    "问题是",
)


def han_count(value: str) -> int:
    return len(re.findall(r"[\u4e00-\u9fff]", value))


def line_number(text: str, position: int) -> int:
    return text.count("\n", 0, position) + 1


def excerpt(value: str, width: int = 68) -> str:
    clean = re.sub(r"\s+", " ", value).strip(" 。！？!?，,")
    return clean if len(clean) <= width else f"{clean[: width - 1]}…"


def mask_match(match: re.Match[str]) -> str:
    return "".join("\n" if char == "\n" else " " for char in match.group())


def mask_non_prose(text: str) -> str:
    """屏蔽不应参与语言审查的区域，同时保留字符位置和换行。"""
    patterns = (
        re.compile(r"\A---\s*\n.*?\n---\s*(?:\n|\Z)", re.DOTALL),
        re.compile(r"```.*?```", re.DOTALL),
        re.compile(r"~~~.*?~~~", re.DOTALL),
        re.compile(r"`[^`\n]*`"),
        re.compile(r"!\[[^\n]*?\]\([^\n)]*\)"),
        re.compile(r"\]\([^\n)]*\)"),
        re.compile(r"https?://[^\s)>]+"),
        re.compile(r"<[^>\n]+>"),
        re.compile(r"^\s*>.*$", re.MULTILINE),
        re.compile(r"^\s*\|.*\|\s*$", re.MULTILINE),
    )
    masked = text
    for pattern in patterns:
        masked = pattern.sub(mask_match, masked)
    return masked


def prose_paragraphs(text: str) -> list[Paragraph]:
    paragraphs: list[Paragraph] = []
    cursor = 0
    for block in re.split(r"\n\s*\n", text):
        position = text.find(block, cursor)
        if position < 0:
            continue
        cursor = position + len(block)
        clean = re.sub(r"[>*_#]", "", block).strip()
        if not clean or re.match(r"^(?:[-+*]|\d+[.、])\s", clean):
            continue
        count = han_count(clean)
        if count < 2:
            continue
        sentences = max(1, len(re.findall(r"[。！？!?]", clean)))
        paragraphs.append(Paragraph(position, clean, count, sentences))
    return paragraphs


def pattern_findings(source: str, prose: str) -> list[Finding]:
    findings: list[Finding] = []
    for code, label, reason, pattern, position_limit in PATTERNS:
        for match in pattern.finditer(prose):
            if position_limit is not None and match.start() > position_limit:
                continue
            findings.append(
                Finding(
                    line_number(source, match.start()),
                    code,
                    label,
                    reason,
                    excerpt(match.group()),
                )
            )
    return findings


def repeated_sentence_findings(source: str, prose: str) -> list[Finding]:
    seen: dict[str, tuple[int, str]] = {}
    reported: set[str] = set()
    findings: list[Finding] = []
    for match in re.finditer(r"[^。！？!?\n]+[。！？!?]", prose):
        value = re.sub(r"[\s，,；;：:]", "", match.group()).strip("。！？!?")
        if not 14 <= han_count(value) <= 100:
            continue
        if value not in seen:
            seen[value] = (match.start(), match.group())
            continue
        if value in reported:
            continue
        first_position, first_text = seen[value]
        reported.add(value)
        findings.append(
            Finding(
                line_number(source, match.start()),
                "L6",
                "重复句",
                f"与第 {line_number(source, first_position)} 行内容相同，检查是否需要保留两次",
                excerpt(first_text),
            )
        )
    return findings


def paragraph_findings(source: str, paragraphs: list[Paragraph]) -> list[Finding]:
    findings: list[Finding] = []
    if not paragraphs:
        return findings

    short_streak: list[Paragraph] = []
    for paragraph in paragraphs:
        if paragraph.han <= 24 and paragraph.sentences <= 1:
            short_streak.append(paragraph)
            if len(short_streak) == 4:
                first = short_streak[0]
                findings.append(
                    Finding(
                        line_number(source, first.position),
                        "R5",
                        "连续短段",
                        "连续四个短促单句段，检查是否在排队输出结论",
                        excerpt(" / ".join(item.text for item in short_streak)),
                    )
                )
        else:
            short_streak = []

    if len(paragraphs) >= 10:
        one_sentence = sum(item.sentences <= 1 for item in paragraphs)
        ratio = one_sentence / len(paragraphs)
        if ratio >= 0.75:
            findings.append(
                Finding(
                    line_number(source, paragraphs[0].position),
                    "R2",
                    "段落形状单一",
                    f"可识别段落中有 {ratio:.0%} 只有一句；移动端排版合理时保留",
                    excerpt(paragraphs[0].text),
                )
            )

    if len(paragraphs) >= 8:
        lengths = [item.han for item in paragraphs]
        average = sum(lengths) / len(lengths)
        spread = max(lengths) - min(lengths)
        if average >= 20 and spread / average <= 0.45:
            findings.append(
                Finding(
                    line_number(source, paragraphs[0].position),
                    "R2",
                    "段长过度一致",
                    "多个段落长度接近，检查是否按同一模具展开",
                    f"{len(paragraphs)} 段，汉字数范围 {min(lengths)}-{max(lengths)}",
                )
            )

    opener_counts: collections.Counter[str] = collections.Counter()
    opener_positions: dict[str, int] = {}
    for paragraph in paragraphs:
        value = paragraph.text.lstrip("“‘\"（(")
        for opener in REPEATED_OPENERS:
            if value.startswith(opener):
                opener_counts[opener] += 1
                opener_positions.setdefault(opener, paragraph.position)
                break
    for opener, count in opener_counts.items():
        if count < 3:
            continue
        findings.append(
            Finding(
                line_number(source, opener_positions[opener]),
                "R6",
                "重复段首",
                f"“{opener}”作为段首出现 {count} 次，检查是否形成固定路标",
                opener,
            )
        )
    return findings


def read_text(path: str) -> str:
    if path == "-":
        return sys.stdin.read()
    return Path(path).read_text(encoding="utf-8")


def analyze(source: str):
    prose = mask_non_prose(source)
    paragraphs = prose_paragraphs(prose)
    findings = pattern_findings(source, prose)
    findings.extend(repeated_sentence_findings(source, prose))
    findings.extend(paragraph_findings(source, paragraphs))
    findings.sort(key=lambda item: (item.line, item.code, item.excerpt))
    return han_count(prose), paragraphs, findings


def self_test() -> None:
    sample = (
        "在当今时代，内容创作正在发生变化。\n\n"
        "接下来我们将深入分析这个问题。\n\n"
        "值得注意的是，这不是工具变化，而是认知革命。\n\n"
        "一句话。\n\n很重要。\n\n必须重视。\n\n值得思考。"
    )
    _, _, findings = analyze(sample)
    codes = {item.code for item in findings}
    expected = {"S1", "S2", "L1", "L9", "R5"}
    missing = expected - codes
    if missing:
        raise AssertionError(f"Self-test missing {', '.join(sorted(missing))}.")

    masked = (
        "正文直接说明已经确认的事实。\n\n"
        "> 在当今时代，值得注意的是。\n\n"
        "```text\n接下来我们将深入分析。\n```"
    )
    if analyze(masked)[2]:
        raise AssertionError("Self-test masking failed.")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="筛查中文成稿中的模板化文字形状，只报告人工复核候选"
    )
    parser.add_argument(
        "path", help="Markdown 或文本路径；使用 - 从标准输入读取；使用 self-test 自测"
    )
    args = parser.parse_args()

    if args.path == "self-test":
        try:
            self_test()
        except AssertionError as error:
            print(str(error), file=sys.stderr)
            return 2
        print("self-test passed")
        return 0

    try:
        source = read_text(args.path)
    except (OSError, UnicodeError) as error:
        print(f"无法读取稿件：{error}", file=sys.stderr)
        return 2

    total_han, paragraphs, findings = analyze(source)
    if total_han == 0:
        print("没有检测到可审查的中文正文。", file=sys.stderr)
        return 2

    print(f"可见汉字 {total_han}，可识别段落 {len(paragraphs)}")
    if findings:
        print(f"发现 {len(findings)} 个候选问题，全部需要结合声纹和语境人工判断：")
        for item in findings:
            print(
                f"- 第 {item.line} 行 [{item.code} {item.label}] "
                f"{item.reason}；“{item.excerpt}”"
            )
    else:
        print("未发现本检查器覆盖的文字形状。")

    print("检查器不判断材料充足度、语义推进、作者身份或风格一致性，也不自动修改正文。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
