#!/usr/bin/env bash
# Launcher that never needs global Python / uv / PATH.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export UV_CACHE_DIR="$ROOT/runtime/uv-cache"
export UV_PYTHON_INSTALL_DIR="$ROOT/runtime/uv-python"
export UV_PYTHON_BIN_DIR="$ROOT/runtime/uv-python-bin"
export UV_TOOL_DIR="$ROOT/runtime/uv-tools"
export UV_PYTHON_INSTALL_BIN=0 UV_MANAGED_PYTHON=1 UV_LINK_MODE=copy
export PIP_CACHE_DIR="$ROOT/runtime/pip-cache"
export PLAYWRIGHT_BROWSERS_PATH="$ROOT/runtime/browsers"
export HF_HOME="$ROOT/runtime/huggingface"
export XDG_CACHE_HOME="$ROOT/runtime/cache"
export TMPDIR="$ROOT/runtime/tmp"
mkdir -p "$TMPDIR"
export PATH="$ROOT/runtime/bootstrap/uv:$ROOT/tools/ffmpeg/bin:$PATH"
UV="$ROOT/runtime/bootstrap/uv/uv"
[ -x "$UV" ] || { echo 'Run SETUP-UNIX.sh first.' >&2;exit 2; }
PYTHON="$("$UV" python find --managed-python 3.12)"
TASK="${1:-doctor}"; [ "$#" -eq 0 ] || shift
case "$TASK" in
  doctor) exec "$PYTHON" "$ROOT/scripts/doctor.py" --install-root "$ROOT" "$@";;
  studio|materials|installer|bootstrap_assets|configure_mcp|offline_smoke|upgrade_core)
    exec "$PYTHON" "$ROOT/scripts/$TASK.py" --root "$ROOT" "$@";;
  export_assets) exec "$PYTHON" "$ROOT/scripts/export_assets.py" --install-root "$ROOT" "$@";;
  test) cd "$ROOT";exec "$PYTHON" -m unittest discover -s tests -p 'test_*.py' -v;;
  *) echo "Unknown command: $TASK" >&2; exit 2;;
esac
