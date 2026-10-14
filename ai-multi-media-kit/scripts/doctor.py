#!/usr/bin/env python3
"""Read-only layered health checks. Presence != operational readiness != published."""
from __future__ import annotations
import argparse
import json
import os
import shutil
import sys
from pathlib import Path

LOCAL = ['ai-media-studio','ai-media-topics','ai-media-scripts','ai-media-review','ai-media-video','ai-media-publish']
PLATFORMS=['xiaohongshu','douyin','tencent','bilibili','kuaishou','wechat_oa','zhihu']


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--install-root',required=True)
    ap.add_argument('--strict',action='store_true')
    ap.add_argument('--scope',choices=['bootstrap','core','video','publish','all'],default='core')
    ap.add_argument('--json-output')
    a=ap.parse_args()
    root=Path(a.install_root).expanduser().resolve()
    checks=[]
    def check(name,ok,detail='',scope='core',essential=True):
        checks.append({'name':name,'ok':bool(ok),'detail':str(detail),'scope':scope,'essential':essential})
        print(('[OK]' if ok else '[MISSING]')+' '+name+((' : '+str(detail)) if detail else ''))
    check('Python>=3.11',sys.version_info>=(3,11),sys.version.split()[0])
    check('工作区配置', (root/'config/workspace.json').is_file())
    cfg=root/'config/workspace.json'
    if cfg.is_file():
        try:
            val=json.loads(cfg.read_text(encoding='utf-8'))
            kb=Path(val['knowledge_root'])
            check('企业知识库',kb.is_dir(),kb)
            for f in ('brand.md','audience.md','review-rules.md'):
                check(f'知识库文件 {f}',(kb/f).is_file())
            check('默认禁止自动发布',val.get('auto_publish') is False)
        except (KeyError,ValueError,OSError) as exc:
            check('配置可读取',False,str(exc))
    for sk in LOCAL:
        check('自带 Skill '+sk, (root/'.agents/skills'/sk/'SKILL.md').is_file())
    check('内容工作流 CLI',(root/'scripts/studio.py').is_file())
    check('依赖安装器',(root/'scripts/installer.py').is_file())
    # Codex launch may be inside an IDE, so report environment status, not core workflow scripts broken.
    check('Codex CLI / IDE',bool(shutil.which('codex')),shutil.which('codex') or '可以从已登录 Codex IDE 打开此文件夹',scope='all',essential=False)
    uvbin=root/'runtime/bootstrap/uv'/('uv.exe' if os.name=='nt' else 'uv')
    check('本地 uv (无需系统安装)', uvbin.is_file(),uvbin,scope='core')
    check('本地 Python 3.12 (uv-managed)', (root/'runtime/uv-python').is_dir() and any((root/'runtime/uv-python').iterdir()) if (root/'runtime/uv-python').is_dir() else False,root/'runtime/uv-python',scope='core')
    localgit=root/'tools/git/cmd/git.exe'
    check('git（Windows便携版或系统Git；缺失时可用 GitHub ZIP）',bool(shutil.which('git') or localgit.is_file()),scope='all',essential=False)
    check('uv 可调用', bool(shutil.which('uv') or uvbin.is_file()),scope='core')
    ffbase=root/'tools/ffmpeg/bin'
    for bin in ('ffmpeg','ffprobe'):
        local=ffbase/(bin+'.exe' if os.name=='nt' else bin)
        check(bin,bool(shutil.which(bin) or local.is_file()),shutil.which(bin) or str(local),scope='video')
    mpt=root/'tools/MoneyPrinterTurbo'
    check('MPT 已安装环境',(mpt/'cli.py').is_file() and (mpt/'.venv').is_dir(),scope='video',essential=False)
    sau=root/'tools/social-auto-upload'
    check('social-auto-upload 源码/环境',(sau/'sau_cli.py').is_file() and (sau/'.venv').is_dir(),scope='publish')
    for sk in ('baoyu-post-to-wechat','zhihu-publisher'):
        check('发布 Skill '+sk,(root/'.agents/skills'/sk/'SKILL.md').is_file(),scope='publish',essential=(sk=='baoyu-post-to-wechat'))
    check('小红书 MCP（可选）',(root/'mcp/xiaohongshu-mcp').exists(),scope='publish',essential=False)
    selected={'bootstrap':{'core'},'core':{'core'},'video':{'core','video'},'publish':{'core','publish'},'all':{'core','video','publish','all'}}[a.scope]
    missing=[c['name'] for c in checks if not c['ok'] and c['essential'] and c['scope'] in selected]
    result={'readiness':not missing,'missing':missing,'checks':checks,'scope':'presence_only_not_platform_acceptance',
         'profile':a.scope,'warning':'只验证本地结构及工具存在，不代表账号已经登录/真实发帖成功'}
    if a.json_output:
        p=Path(a.json_output).resolve();p.parent.mkdir(parents=True,exist_ok=True)
        p.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f'PROFILE={a.scope} checks={len(checks)} essential_missing={len(missing)}; real publishing NOT tested.')
    return 1 if a.strict and missing else 0


if __name__=='__main__':raise SystemExit(main())
