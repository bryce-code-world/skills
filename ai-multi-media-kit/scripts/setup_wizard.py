#!/usr/bin/env python3
"""Interactive first-run wizard. Never implicitly downloads or executes third parties."""
from __future__ import annotations
import os
import sys
from pathlib import Path
import init_workspace
import installer


def prompt(name, default):
    try:
        answer=input(f'{name} [{default}]：').strip()
    except EOFError:
        raise ValueError('交互式初始化需要终端输入')
    return answer or default


def main():
    if sys.version_info < (3,11):
        print('需要 Python 3.11 或更新版本（建议 3.11/3.12）');return 2
    source=Path(__file__).resolve().parent.parent
    print('AI Media Studio V3 — 旧版 Python 初始化向导')
    print('更推荐直接执行 SETUP-WINDOWS.ps1 / SETUP-UNIX.sh，不需要预装 Python。')
    if os.name=='nt':
        disk='D:\\AI-Media-Studio' if Path('D:/').exists() else str(Path.home()/'AI-Media-Studio')
        kb='D:\\Company-Knowledge' if Path('D:/').exists() else str(Path.home()/'Company-Knowledge')
    else:
        disk=str(Path.home()/'AI-Media-Studio');kb=str(Path.home()/'Company-Knowledge')
    dest=prompt('工具/Skill 工作区位置',disk)
    knowledge=prompt('企业知识库位置（独立）',kb)
    sys.argv=['init_workspace.py','--install-root',dest,'--knowledge-root',knowledge]
    rc=init_workspace.main()
    if rc:return rc
    print('\n完成。后续操作：')
    print('① 在知识库内完善 brand.md/audience.md/review-rules.md。')
    print(f'② 从 {dest} 打开 Codex 或运行 start-codex.cmd。')
    print(f'③ 若要安装外部工具：RUN-STUDIO-WINDOWS.ps1 -Task installer --profile core --install # 或 ./run-studio.sh installer "{dest}" --profile core --install')
    print('④ 如要用 FFmpeg 合成视频，需具备可运行的 FFmpeg 或手动导入本地二进制。')
    return 0


if __name__=='__main__':
    try:raise SystemExit(main())
    except (ValueError, KeyboardInterrupt) as e:
        print('ERROR:',str(e),file=sys.stderr);raise SystemExit(2)
