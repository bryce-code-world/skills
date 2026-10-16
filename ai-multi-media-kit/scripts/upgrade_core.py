#!/usr/bin/env python3
"""Upgrade bundled own code after explicit --apply, with backups; preserve user assets."""
from __future__ import annotations
import argparse
import hashlib
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

SOURCE=Path(__file__).resolve().parent.parent


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()


def owned_files():
    names=['AGENTS.md','README.md','SETUP-WINDOWS.cmd','SETUP-WINDOWS.ps1','SETUP-UNIX.sh','RUN-STUDIO-WINDOWS.ps1','run-studio.sh','start-codex.cmd','start-codex.sh','.gitignore']
    names += [p.relative_to(SOURCE).as_posix() for f in ('scripts','docs','knowledge-templates')
              for p in (SOURCE/f).rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix!='.pyc']
    # Include nested own skill resources too.
    names += [p.relative_to(SOURCE).as_posix() for p in (SOURCE/'.agents/skills').rglob('*')
              if p.is_file() and p.relative_to(SOURCE/'.agents/skills').parts[0].startswith('ai-media-')]
    names += ['config/dependencies.yaml','config/platforms.yaml','config/bootstrap-assets.json', 'references/release.json']
    return sorted(set(names))


def main():
    p=argparse.ArgumentParser(description='更新主 Skill 自有文件，保留用户数据并完整备份被替换的旧文件')
    p.add_argument('--root',required=True)
    p.add_argument('--apply',action='store_true',help='在当前任务范围内备份并应用升级，不要求额外的键盘口令')
    a=p.parse_args()
    root=Path(a.root).expanduser().resolve()
    if not (root/'config/workspace.json').is_file():raise ValueError('未初始化工作区')
    updates=[]
    for rel in owned_files():
        src=SOURCE/rel;dest=root/rel
        if not src.is_file():continue
        if not dest.exists() or sha(src)!=sha(dest):updates.append(rel)
    if root==SOURCE:updates=[]
    print('将更新的核心文件数：',len(updates))
    for r in updates:print(' -',r)
    print('不会改动企业知识库、项目产出目录、auth、runtime、第三方工具和 workspace.json。')
    if not a.apply:
        print('PREVIEW ONLY：如确认需要升级，运行相同命令 + --apply')
        return 0
    if not updates:
        print('ALREADY UP TO DATE');return 0
    backup=root/'backups'/('core-before-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
    for rel in updates:
        src=SOURCE/rel;dest=root/rel
        if dest.is_symlink():raise ValueError('拒绝覆盖链接：'+str(dest))
        if dest.is_file():
            saved=backup/rel;saved.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(dest,saved)
        dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dest)
    print('UPGRADED',len(updates),'files. Old files backed up in:',backup)
    return 0


if __name__=='__main__':
    try:raise SystemExit(main())
    except (ValueError,OSError,KeyboardInterrupt) as e:
        print('ERROR:',str(e),file=sys.stderr);raise SystemExit(2)