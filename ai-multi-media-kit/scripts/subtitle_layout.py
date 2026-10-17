"""Pre-render safe-area checks for captioned, programmatic video layouts.

Inputs are bounding boxes supplied by the renderer. This cannot infer real
objects from flattened MP4 frames: inspect the final video visually as well.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def _box(box, width: int, height: int) -> tuple[float, float, float, float]:
    if (not isinstance(box, (list, tuple)) or len(box) != 4 or
            any(not isinstance(v, (int, float)) or isinstance(v, bool) for v in box)):
        raise ValueError("布局矩形必须为 [left,top,right,bottom] 四个数")
    left, top, right, bottom = box
    if not (0 <= left < right <= width and 0 <= top < bottom <= height):
        raise ValueError(f"布局矩形坐标越界或尺寸非法：{box}")
    return left, top, right, bottom


def inspect_layout(width: int, height: int, *, content_boxes, subtitle_boxes) -> dict:
    """Keep readable scene content and captions in nonoverlapping zones."""
    if width <= 0 or height <= 0:
        raise ValueError("视频尺寸必须是正整数")
    if not isinstance(content_boxes, list) or not isinstance(subtitle_boxes, list):
        raise ValueError("content_boxes/subtitle_boxes 必须是矩形数组")
    content = [_box(b, width, height) for b in content_boxes]
    captions = [_box(b, width, height) for b in subtitle_boxes]
    content_bottom = height * 0.72
    subtitle_top, subtitle_bottom = height * 0.76, height * 0.92
    side = width * 0.07
    problems = []
    if not captions:
        problems.append("字幕布局未登记，不能视为已通过字幕遮挡检查")
    for i, b in enumerate(content, 1):
        if b[3] > content_bottom:
            problems.append(f"正文/重要元素 {i} 侵入预留字幕缓冲区：底边 {b[3]:.0f} > {content_bottom:.0f}")
    for i, b in enumerate(captions, 1):
        if b[0] < side or b[2] > width - side or b[1] < subtitle_top or b[3] > subtitle_bottom:
            problems.append(f"字幕 {i} 超出侧边/底部安全区：{tuple(b)}")
        if b[3] - b[1] > height * 0.15:
            problems.append(f"字幕 {i} 高度过大，可能多行遮挡")
        for j, scene in enumerate(content, 1):
            if (b[0] < scene[2] and scene[0] < b[2] and
                    b[1] < scene[3] and scene[1] < b[3]):
                problems.append(f"字幕 {i} 与正文/重要元素 {j} 重叠")
    return {
        "result": "BLOCK" if problems else "PASS",
        "method": "renderer_declared_boxes_not_video_vision",
        "safe_areas": {"content_bottom": round(content_bottom),
                       "subtitle_top": round(subtitle_top),
                       "subtitle_bottom": round(subtitle_bottom),
                       "side_margin": round(side)},
        "issues": problems,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="字幕排版几何预检（不能代替最终 MP4 实际画面审查）")
    parser.add_argument("--layout", type=Path, required=True, help="包含 width/height/shots 的 JSON")
    args = parser.parse_args()
    try:
        config = json.loads(args.layout.read_text("utf8"))
        shots = config["shots"]
        if not isinstance(shots, list) or not shots:
            raise ValueError("必须为每个含字幕的镜头登记布局")
        issues = []
        for i, shot in enumerate(shots, 1):
            result = inspect_layout(config["width"], config["height"],
                                    content_boxes=shot["content_boxes"],
                                    subtitle_boxes=shot["subtitle_boxes"])
            for issue in result["issues"]:
                issues.append(f"镜头 {i}：{issue}")
        print(json.dumps({"result": "BLOCK" if issues else "PASS",
                          "method": "renderer_declared_boxes_not_video_vision",
                          "issues": issues}, ensure_ascii=False, indent=2))
        return 2 if issues else 0
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        print("ERROR:", exc, file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
