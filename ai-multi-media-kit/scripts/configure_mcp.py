#!/usr/bin/env python3
"""Task-scoped, explicit project-local MCP registration; no token or service start."""
from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path

STANZA='''# AI Media Studio — local xiaohongshu MCP (task-scoped opt-in)
# The server must be independently installed, authenticated, and running on loopback.
# Set XHS_MCP_TOKEN in the Codex process environment; never place token value in this file.
[mcp_servers.xiaohongshu]
url = "http://127.0.0.1:18060/mcp"
bearer_token_env_var = "XHS_MCP_TOKEN"
'''


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--root',required=True)
    p.add_argument('--enable-xhs',action='store_true')
    a=p.parse_args()
    root=Path(a.root).expanduser().resolve()
    if not (root/'config/workspace.json').is_file():raise ValueError('工作区未初始化')
    if not a.enable_xhs:
        print('PLAN ONLY: 在项目 .codex/config.toml 配置本地 xiaohongshu MCP。')
        print('需要本地 MCP 进程监听 127.0.0.1:18060，并启用 AUTH_TOKEN。')
        print('不会运行 Docker、登录账号或复制任何 Cookie。')
        return 0
    target=root/'.codex'/'config.toml'
    if target.exists():
        s=target.read_text(encoding='utf-8')
        if '[mcp_servers.xiaohongshu]' in s:
            print('PRESERVED existing registration:',target)
            return 0
        # no modification to any other arbitrary Codex user/project config
        raise ValueError('项目 .codex/config.toml 已存在其他内容，先人工合并；安装器不会覆盖配置')
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(STANZA,encoding='utf-8')
    print('REGISTERED (config only, server NOT started):',target)
    print('将 MCP 的 AUTH_TOKEN 与 Codex 的 XHS_MCP_TOKEN 配成相同随机字符串，再启动服务并重启 Codex。')
    return 0

if __name__=='__main__':
    try:raise SystemExit(main())
    except (ValueError,KeyboardInterrupt) as e:
        print('ERROR:',str(e),file=sys.stderr);raise SystemExit(2)