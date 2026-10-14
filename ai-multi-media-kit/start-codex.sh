#!/usr/bin/env sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if ! command -v codex >/dev/null 2>&1; then
  echo 'Codex CLI not found. Install/login before running this launcher.' >&2
  exit 1
fi
exec codex
