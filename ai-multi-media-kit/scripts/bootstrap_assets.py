#!/usr/bin/env python3
"""No-system-install tool provisioning, called *after* pinned uv provides Python.

Pin binary source/version and validate digest; keep artifacts beneath user's root.
Never silently replace an existing unrelated file or execute downloaded source code.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import urllib.error
import zipfile
from pathlib import Path

MANIFEST = Path(__file__).resolve().parents[1] / 'config' / 'bootstrap-assets.json'


def target_platform() -> str:
    os_name = {'Windows':'windows','Darwin':'macos','Linux':'linux'}.get(platform.system())
    raw = platform.machine().lower()
    arch = 'arm64' if raw in ('arm64','aarch64') else 'x64' if raw in ('x86_64','amd64') else None
    if not os_name or not arch:
        raise ValueError('不支持此系统/处理器架构: ' + platform.platform())
    return os_name + '-' + arch


def checksum(path: Path, name: str) -> str:
    h = hashlib.new(name)
    with path.open('rb') as file:
        for chunk in iter(lambda: file.read(2 * 1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def verify(path: Path, meta: dict) -> bool:
    alg = 'sha256' if 'sha256' in meta else 'md5' if 'md5' in meta else None
    if alg is None:
        raise ValueError('缺少固定校验值，不执行下载: ' + str(path))
    return path.is_file() and checksum(path, alg).lower() == meta[alg].lower()


def download(url: str, dest: Path, meta: dict, offline: bool) -> None:
    if verify(dest, meta):
        print('CACHED CHECKSUM OK:', dest.name)
        return
    if offline:
        raise ValueError('离线缓存缺失或校验失败: ' + str(dest))
    if not url.startswith('https://'):
        raise ValueError('只允许 HTTPS: '+url)
    dest.parent.mkdir(parents=True, exist_ok=True)
    temp = dest.with_name(dest.name + '.part')
    try:
        req = urllib.request.Request(url, headers={'User-Agent':'AI-Media-Studio-Bootstrap/3.0'})
        with urllib.request.urlopen(req, timeout=50) as r, temp.open('wb') as fp:
            if not r.geturl().startswith('https://'):
                raise ValueError('拒绝不安全的重定向')
            shutil.copyfileobj(r, fp)
        if not verify(temp, meta):
            raise ValueError('下载文件校验失败：' + url)
        os.replace(temp, dest)
    finally:
        temp.unlink(missing_ok=True)


def safe_extract_zip(file: Path, dst: Path):
    with zipfile.ZipFile(file) as z:
        infos = z.infolist()
        if len(infos) > 30000 or sum(x.file_size for x in infos) > 1500 * 1024 ** 2:
            raise ValueError('归档内容过大')
        for x in infos:
            name=x.filename.replace('\\','/')
            p=Path(name)
            if name.startswith('/') or '..' in p.parts or (p.parts and ':' in p.parts[0]):
                raise ValueError('压缩包存在非法路径: '+name)
            if ((x.external_attr >> 16) & 0o170000) == 0o120000:
                raise ValueError('压缩包含符号链接，拒绝解压')
        z.extractall(dst)


def stage_mingit(root: Path, conf: dict, oskey: str, offline: bool):
    if not oskey.startswith('windows-'):
        return 'Linux/macOS 使用已有 git；若无 git，第三方项目获取需额外安装或改用源码归档。'
    dest=root/'tools'/'git'
    binary=dest/'cmd'/'git.exe'
    asset=conf['assets'].get(oskey)
    if asset is None:
        raise ValueError('当前 Windows 架构缺少便携式 Git')
    if binary.is_file():
        p=subprocess.run([str(binary),'--version'],capture_output=True,text=True,timeout=20)
        if p.returncode==0 and conf['version'].rsplit('.',1)[0] in p.stdout:
            return 'PRESERVED local MinGit '+p.stdout.strip()
        raise ValueError('已存在非预期 Git；拒绝覆盖 '+str(dest))
    archive=root/'runtime'/'downloads'/asset['file']
    download(conf['source']+'/'+asset['file'],archive,asset,offline)
    dest.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.git-extract-',dir=dest.parent) as tmp:
        temp=Path(tmp)
        safe_extract_zip(archive,temp)
        if not (temp/'cmd'/'git.exe').is_file():
            raise ValueError('MinGit zip 缺少 cmd/git.exe')
        temp_final=dest.with_name('git-installing')
        if temp_final.exists(): raise ValueError('已有未完成 Git 安装目录: '+str(temp_final))
        shutil.move(str(temp),str(temp_final))
        os.rename(temp_final,dest)
    p=subprocess.run([str(binary),'--version'],capture_output=True,text=True,timeout=20)
    if p.returncode: raise ValueError('Git 安装后启动失败: '+p.stderr)
    return 'INSTALLED local MinGit: '+p.stdout.strip()


def stage_ffmpeg(root:Path,conf:dict,oskey:str,offline:bool):
    assets=conf['assets'].get(oskey)
    if not assets:
        raise ValueError('当前平台没有自动下载的 FFmpeg 二进制；可以使用 installer.py --ffmpeg-from 手动导入。')
    bin_dir=root/'tools'/'ffmpeg'/'bin'
    bin_dir.mkdir(parents=True,exist_ok=True)
    results=[]
    for entry in assets:
        archive=root/'runtime'/'downloads'/entry['file']
        dst=bin_dir/entry['output']
        if dst.is_file():
            if verify(dst,entry):
                results.append('PRESERVED '+str(dst));continue
            raise ValueError('存在 FFmpeg 二进制文件，但校验不匹配；拒绝覆盖: '+str(dst))
        download(conf['source']+'/'+entry['file'],archive,entry,offline)
        shutil.copy2(archive,dst)
        if os.name!='nt':dst.chmod(dst.stat().st_mode | 0o755)
        if not verify(dst,entry): raise ValueError('安装 FFmpeg 时校验失败')
        results.append('INSTALLED '+str(dst))
    for bin in ('ffmpeg','ffprobe'):
        target=bin_dir/(bin+'.exe' if os.name=='nt' else bin)
        proc=subprocess.run([str(target),'-version'],capture_output=True,text=True,timeout=30)
        if proc.returncode:raise ValueError('FFmpeg/FFprobe 启动失败: '+proc.stderr[:500])
    return results


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--root',required=True)
    ap.add_argument('--ffmpeg',action='store_true')
    ap.add_argument('--git',action='store_true')
    ap.add_argument('--offline',action='store_true')
    ap.add_argument('--platform-for-test',help=argparse.SUPPRESS)
    a=ap.parse_args()
    root=Path(a.root).expanduser().resolve()
    cfg=root/'config'/'workspace.json'
    if not cfg.exists():raise ValueError('请先执行初始化: '+str(cfg))
    conf=json.loads(MANIFEST.read_text(encoding='utf-8'))
    plat=a.platform_for_test or target_platform()
    if a.git:print(stage_mingit(root,conf['mingit'],plat,a.offline))
    if a.ffmpeg:
        for item in stage_ffmpeg(root,conf['ffmpeg'],plat,a.offline):print(item)
    return 0


if __name__ == '__main__':
    try:raise SystemExit(main())
    except (ValueError,OSError,urllib.error.URLError,subprocess.TimeoutExpired) as exc:
        print('BOOTSTRAP_ERROR:',exc,file=sys.stderr)
        raise SystemExit(2)
