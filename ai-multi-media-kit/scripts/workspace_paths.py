"""Workspace-owned project output path; one authority shared by CLI commands."""
from __future__ import annotations

from pathlib import Path


def output_directory(install: Path, config: dict, *, initializing: bool = False) -> Path:
    """Resolve the persisted output_root, keeping old workspaces at install/outputs."""
    install = Path(install).expanduser().resolve()
    raw = config.get("output_root", str(install / "outputs"))
    if not isinstance(raw, str) or not raw.strip():
        raise ValueError("output_root 必须是绝对目录路径")
    path = Path(raw).expanduser()
    if not path.is_absolute():
        raise ValueError("output_root 必须是绝对目录路径")
    output = path.resolve()
    kb_value = config.get("knowledge_root")
    if not isinstance(kb_value, str) or not kb_value.strip():
        raise ValueError("knowledge_root 未配置")
    knowledge = Path(kb_value).expanduser().resolve()
    if (output == knowledge or output in knowledge.parents or knowledge in output.parents):
        raise ValueError("项目输出目录不能与企业知识库重叠")
    # Legacy install/outputs is kept for compatibility; new paths remain independent.
    if output != (install / "outputs").resolve() and (
            output == install or output in install.parents or install in output.parents):
        raise ValueError("独立项目输出目录不能与工具安装目录重叠")
    if not initializing and output != (install / "outputs").resolve() and not output.is_dir():
        raise ValueError(f"项目成果目录不可访问：{output}；不会自动重建或迁移已有数据")
    return output
