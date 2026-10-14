#!/usr/bin/env python3
"""Reproducible opt-in third-party dependency installer.

Downloads source to the chosen workspace root, locks commit SHA, installs only
selected skills, then optionally runs upstream `uv sync --frozen` when explicitly
approved. It does NOT bypass browser logins or enable platform publishing.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import tempfile
import urllib.request
import zipfile
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

SOURCES={
 'marketing': {'url':'https://github.com/coreyhaines31/marketingskills.git','dest':'marketingskills',
    'skills':['product-marketing','content-strategy','social','copywriting','copy-editing','video'], 'tier':'text'},
 'baoyu':{'url':'https://github.com/JimLiu/baoyu-skills.git','dest':'baoyu-skills',
    'skills':['baoyu-post-to-wechat','baoyu-cover-image','baoyu-xhs-images'], 'tier':'wechat'},
 'social':{'url':'https://github.com/dreammis/social-auto-upload.git','dest':'social-auto-upload',
    'skills':['douyin-upload','kuaishou-upload','xiaohongshu-upload','bilibili-upload'],'uv':True, 'tier':'publish'},
 'mpt':{'url':'https://github.com/harry0703/MoneyPrinterTurbo.git','dest':'MoneyPrinterTurbo',
    'skills':[], 'uv':True, 'tier':'video'},
 'xhs-mcp':{'url':'https://github.com/xpzouying/xiaohongshu-mcp.git','dest':'xiaohongshu-mcp',
    'skills':[],'tier':'ops'},
 'zhihu':{'url':'https://github.com/zhihu/ZhihuPublisher.git','dest':'ZhihuPublisher',
    'skills':['ZhihuPublisher'], 'tier':'zhihu'},
}
PROFILES={'core':['marketing','baoyu'],'video':['mpt'],
          'publish':['social','baoyu','zhihu'],'ops':['xhs-mcp'],
          'all':list(SOURCES)}


def die(msg): raise RuntimeError(msg)


def env_for(root):
    env=os.environ.copy()
    for var,rel in {'UV_CACHE_DIR':'runtime/uv-cache','UV_PYTHON_INSTALL_DIR':'runtime/uv-python',
        'PIP_CACHE_DIR':'runtime/pip-cache','PLAYWRIGHT_BROWSERS_PATH':'runtime/browsers',
        'XDG_CACHE_HOME':'runtime/cache','HF_HOME':'runtime/huggingface','TMPDIR':'runtime/tmp'}.items():
        path=root/rel
        path.mkdir(parents=True,exist_ok=True)
        env[var]=str(path)
    path_entries=[root/'runtime/bootstrap/uv',root/'tools/git/cmd',root/'tools/ffmpeg/bin']
    env['PATH']=os.pathsep.join([str(p) for p in path_entries])+os.pathsep+env.get('PATH','')
    env['UV_PYTHON_INSTALL_BIN']='0'
    env['UV_MANAGED_PYTHON']='1'
    env['UV_LINK_MODE']='copy'
    env['UV_TOOL_DIR']=str(root/'runtime/uv-tools')
    env['UV_PYTHON_BIN_DIR']=str(root/'runtime/uv-python-bin')
    return env


def tool(root, name):
    lookup={'git':root/'tools/git/cmd/git.exe','uv':root/'runtime/bootstrap/uv'/('uv.exe' if os.name=='nt' else 'uv')}
    found=lookup.get(name)
    return str(found) if found and found.is_file() else shutil.which(name)


def http_json(url):
    req=urllib.request.Request(url,headers={'User-Agent':'AI-Media-Studio-Installer/3.0','Accept':'application/vnd.github+json'})
    with urllib.request.urlopen(req,timeout=45) as rsp:
        if not rsp.geturl().startswith('https://'):die('GitHub API insecure redirect')
        return json.load(rsp)


def github_archive_checkout(root,source_url,target):
    # Git is not mandatory: GitHub archives still lock a full commit SHA.
    match=re.fullmatch(r'https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)\.git',source_url)
    if not match:die('Only allowlisted public GitHub repositories are supported')
    owner,repo=match.groups()
    info=http_json(f'https://api.github.com/repos/{owner}/{repo}')
    branch=info['default_branch']
    commit=http_json(f'https://api.github.com/repos/{owner}/{repo}/commits/{branch}')['sha']
    if not re.fullmatch(r'[0-9a-f]{40}',commit):die('GitHub commit SHA validation failed')
    url=f'https://codeload.github.com/{owner}/{repo}/zip/{commit}'
    target.parent.mkdir(parents=True,exist_ok=True)
    tempzip=root/'runtime/downloads'/(repo+'-'+commit+'.zip')
    tempzip.parent.mkdir(parents=True,exist_ok=True)
    if not tempzip.is_file():
        req=urllib.request.Request(url,headers={'User-Agent':'AI-Media-Studio-Installer/3.0'})
        tmp=tempzip.with_suffix('.zip.part')
        try:
            with urllib.request.urlopen(req,timeout=90) as rsp, tmp.open('wb') as fp:
                if not rsp.geturl().startswith('https://'):die('Unsafe zip redirect')
                shutil.copyfileobj(rsp,fp)
            os.replace(tmp,tempzip)
        finally:tmp.unlink(missing_ok=True)
    with tempfile.TemporaryDirectory(prefix='.media-archive-',dir=target.parent) as tempdir:
        extraction=Path(tempdir)
        with zipfile.ZipFile(tempzip) as z:
            infos=z.infolist()
            if len(infos)>50000 or sum(x.file_size for x in infos)>1500*1024**2:
                die('Archive too large')
            for info in infos:
                parts=Path(info.filename.replace('\\','/')).parts
                if not parts or '..' in parts or info.filename.startswith('/') or ':' in parts[0]:
                    die('Unsafe archive path: '+info.filename)
                if ((info.external_attr >> 16) & 0o170000)==0o120000:
                    die('Archive contains symlink')
            z.extractall(extraction)
        bases=[p for p in extraction.iterdir() if p.is_dir()]
        if len(bases)!=1:die('Unexpected GitHub archive structure')
        if target.exists():die('Target already created by another process')
        shutil.move(str(bases[0]),str(target))
    (target/'.ai-media-checkout.json').write_text(json.dumps({'repo':source_url,'commit':commit,'method':'github_zip'},indent=2),encoding='utf-8')
    print('CLONED WITHOUT GIT (locked GitHub ZIP):',target,commit)
    return commit


def cmd_run(cmd, cwd=None, env=None, timeout=600):
    print('EXEC:',subprocess.list2cmdline(list(map(str,cmd))))
    p=subprocess.run(list(map(str,cmd)),cwd=cwd,env=env,timeout=timeout)
    if p.returncode:die(f'命令失败(退出码 {p.returncode})：{cmd[0]}')


def rev(path, git='git'):
    q=subprocess.run([git,'-C',str(path),'rev-parse','HEAD'],capture_output=True,text=True)
    if q.returncode: die('git 仓库校验失败：'+str(path))
    return q.stdout.strip()


def retrieve(root,id,options):
    src=SOURCES[id]
    target=root/'tools'/src['dest'] if id not in ('xhs-mcp',) else root/'mcp'/src['dest']
    git=tool(root,'git')
    if target.exists():
        if (target/'.git').exists():
            if not git:die('当前目录是 Git clone，但找不到本地/系统 Git，无法验证来源与版本')
            actual=subprocess.run([git,'-C',str(target),'remote','get-url','origin'],capture_output=True,text=True)
            if actual.returncode or actual.stdout.strip().removesuffix('.git').lower()!=src['url'].removesuffix('.git').lower():
                die('已有目录来源不一致，拒绝继续：'+str(target))
            sha=rev(target,git)
        elif (target/'.ai-media-checkout.json').exists():
            meta=json.loads((target/'.ai-media-checkout.json').read_text(encoding='utf-8'))
            if meta.get('repo')!=src['url']:die('已有源码归档来源不一致，拒绝覆盖')
            sha=meta['commit']
            if not re.fullmatch(r'[a-f0-9]{40}',sha):die('已下载源码归档 commit 无效')
        else:die('已有目录，但来源不受本安装器管理：'+str(target))
        print('PRESERVE existing repo:',target)
    else:
        target.parent.mkdir(parents=True,exist_ok=True)
        if git:
            cmd_run([git,'clone','--depth','1','--',src['url'],target],env=env_for(root),timeout=1200)
            sha=rev(target,git)
        else:sha=github_archive_checkout(root,src['url'],target)
    lock_path=root/'config'/'dependencies.lock.json'
    lock=json.loads(lock_path.read_text(encoding='utf-8')) if lock_path.exists() else {'schema':2,'verified_dependencies':{}}
    existing=lock.get('verified_dependencies',{}).get(id)
    if existing and existing.get('commit')!=sha:die('检测到已安装依赖发生版本漂移，请手动审查更新，安装器不会自动升级')
    names=[]
    if id!='zhihu':
        for skill in src.get('skills',[]):
            # We only accept expected, specifically named first-party skill directories.
            candidates=[target/'skills'/skill, target/'.agents'/'skills'/skill,
                        target/'.claude'/'skills'/skill]
            found=next((v for v in candidates if (v/'SKILL.md').is_file()),None)
            if found is None:
                # External project changed structure, report rather than silently skipping.
                die(f'{id} 缺少预期的 Skill: {skill}；保持上游源码供排查：{target}')
            dest=root/'.agents'/'skills'/skill
            if dest.exists():
                if (dest/'.ai-media-source.json').exists():
                    meta=json.loads((dest/'.ai-media-source.json').read_text(encoding='utf-8'))
                    if meta.get('source')!=id or meta.get('commit')!=sha:
                        die(f'Skill 版本冲突，不覆盖本地已有内容：{dest}')
                else:
                    die(f'Skill 目录已被占用，拒绝覆盖：{dest}')
                print('SKIP existing skill:',skill)
            else:
                shutil.copytree(found,dest,ignore=shutil.ignore_patterns('.git','__pycache__','.env','.env.*'))
                (dest/'.ai-media-source.json').write_text(json.dumps({'source':id,'commit':sha},indent=2),encoding='utf-8')
            names.append(skill)
    else:
        dest=root/'.agents'/'skills'/'zhihu-publisher'
        if dest.exists():
            if not (dest/'.ai-media-source.json').is_file(): die('知乎 Skill 目录已存在，拒绝覆盖')
            meta=json.loads((dest/'.ai-media-source.json').read_text(encoding='utf-8'))
            if meta.get('commit')!=sha: die('知乎 Skill 已安装不同版本，拒绝覆盖')
        else:
            shutil.copytree(target,dest,ignore=shutil.ignore_patterns('.git','__pycache__','.env','.env.*'))
            (dest/'.ai-media-source.json').write_text(json.dumps({'source':id,'commit':sha},indent=2),encoding='utf-8')
        names=['zhihu-publisher']
    if src.get('uv'):
        uv=tool(root,'uv')
        if not uv:die('未发现 uv，请安装 uv 后继续；源码已经保存在 '+str(target))
        # Upstream pyproject/uv.lock is untrusted code/dependencies; explicit --install
        # authorizes running its dependency setup. No network commands hidden in Skill.
        cmd_run([uv,'sync','--frozen','--python','3.12'],cwd=target,env=env_for(root),timeout=1800)
        if id=='social' and not options.skip_browser:
            # Social-auto-upload uses Patchright Chromium, which is a separate
            # downloadable browser asset and is NOT included in uv dependencies.
            venv_python=target/'.venv'/('Scripts/python.exe' if os.name=='nt' else 'bin/python')
            if not venv_python.is_file():die('social 的虚拟环境中找不到 python，无法安装 Patchright Chromium')
            print('Installing Chromium into user-selected workspace runtime/browsers. May download >100MB.')
            cmd_run([venv_python,'-m','patchright','install','chromium'],
                    cwd=target,env=env_for(root),timeout=1800)
    lock.setdefault('verified_dependencies',{})[id]={'repo':src['url'],'commit':sha,
        'installed_at_utc':datetime.now(timezone.utc).isoformat(),'source_dir':str(target),
        'selected_skills':names,'installation':'uv_sync' if src.get('uv') else 'repo_copy',
        'readiness':'installed_not_functionally_verified', 'browser':('installed' if id=='social' and not options.skip_browser else 'not_managed')}
    lock['schema']=2
    lock_path.parent.mkdir(parents=True,exist_ok=True)
    tmp=lock_path.with_suffix('.tmp')
    tmp.write_text(json.dumps(lock,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    os.replace(tmp,lock_path)
    print('INSTALLED source checkout / installed skills (NOT account or end-to-end verified):',id,sha)


def install_ffmpeg(root, bin_dir):
    ff=Path(bin_dir).expanduser().resolve()
    if (ff/'bin').is_dir():ff=ff/'bin'
    names=['ffmpeg.exe','ffprobe.exe'] if os.name=='nt' else ['ffmpeg','ffprobe']
    if not all((ff/name).is_file() for name in names):die('指定路径下缺少 ffmpeg 和 ffprobe')
    dst=root/'tools'/'ffmpeg'/'bin';dst.mkdir(exist_ok=True,parents=True)
    for name in names:
        if (dst/name).exists():
            # Never silently replace local binaries.
            if (dst/name).read_bytes()!= (ff/name).read_bytes():die('FFmpeg 文件已存在且版本不同，拒绝覆盖')
        else:
            shutil.copy2(ff/name,dst/name)
    print('LOCAL FFmpeg binary staged:',dst)


def main():
    ap=argparse.ArgumentParser(description='显式授权的 AI Media Studio 第三方工具安装器')
    ap.add_argument('--root',required=True)
    ap.add_argument('--profile',choices=list(PROFILES),default='core')
    ap.add_argument('--component',choices=list(SOURCES),action='append',help='可重复，覆盖 --profile')
    ap.add_argument('--install',action='store_true',help='显式进行联网 Git 下载/第三方依赖安装')
    ap.add_argument('--yes',action='store_true',help='跳过安装器级别的键盘确认；需要用户已经明确授权')
    ap.add_argument('--skip-browser',action='store_true',help='仅安装 social CLI，不下载 Patchright Chromium（稍后必须补装才可用平台登录）')
    ap.add_argument('--ffmpeg-from',help='从自己信任的本地 ffmpeg / ffprobe 二进制目录复制')
    args=ap.parse_args()
    root=Path(args.root).expanduser().resolve()
    conf=root/'config'/'workspace.json'
    if not conf.exists():die('先初始化工作区：'+str(conf))
    ids=list(dict.fromkeys(args.component or PROFILES[args.profile]))
    print('选择的依赖（按需安装，不需要 API Key 即可下载源码）：')
    for id in ids:
        item=SOURCES[id]
        print(' -',id,item['url'],'; child skills:',', '.join(item.get('skills',[])) or 'none',
              '; uv sync:',bool(item.get('uv')))
    print('注意：第三方源代码和依赖未经本环境安全审计；不会自动登录/发表文章/启用 MCP。')
    if not args.install and not args.ffmpeg_from:
        print('PLAN_ONLY：仅展示计划。安装请运行同命令 + --install。')
        return 0
    if not args.yes:
        confirm=input('输入 INSTALL 以确认从上述仓库下载安装并运行需要的 uv 依赖：').strip()
        if confirm!='INSTALL':die('已取消，未开始安装')
    if args.ffmpeg_from:install_ffmpeg(root,args.ffmpeg_from)
    if args.install:
        if not tool(root,'git'): print('Git unavailable: downloading verified commit source ZIP through GitHub API (Git not required).')
        errors=[]
        for id in ids:
            try:retrieve(root,id,args)
            except (RuntimeError,subprocess.TimeoutExpired,FileNotFoundError) as e:
                errors.append((id,str(e)))
                print('FAILED:',id,e,file=sys.stderr)
        if errors:
            print('有依赖未完成安装：',errors,file=sys.stderr)
            return 2
    print('安装步骤结束。运行 scripts/doctor.py，登录平台并逐项功能验收。')
    return 0


if __name__=='__main__':
    try:raise SystemExit(main())
    except (RuntimeError,ValueError,KeyboardInterrupt) as e:
        print('ERROR:',str(e),file=sys.stderr);raise SystemExit(2)
