#!/usr/bin/env bash
# Bash 3.2+ bootstrap for macOS and glibc Linux, no system Python or Git required.
set -euo pipefail
SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT=""; KNOWLEDGE=""; OUTPUT=""; NONINTERACTIVE=0; SKIP_FFMPEG=0; SKIP_GIT=0; NEW_WORKSPACE=0
usage() { echo 'Usage: bash SETUP-UNIX.sh [--install-root DIR] [--knowledge-root DIR] [--output-root DIR] [--non-interactive] [--skip-ffmpeg] [--new-workspace]'; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-root|--knowledge-root|--output-root)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      case "$1" in --install-root) ROOT="$2";; --knowledge-root) KNOWLEDGE="$2";; --output-root) OUTPUT="$2";; esac
      shift 2;;
    --non-interactive) NONINTERACTIVE=1; shift;;
    --skip-ffmpeg) SKIP_FFMPEG=1; shift;;
    --skip-git) SKIP_GIT=1; shift;;  # Unix Git is optional, see tool install note.
    --new-workspace) NEW_WORKSPACE=1; shift;; # Explicit user-directed second workspace only.
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2;;
  esac
done
# A new Agent must not bootstrap a second toolchain when this OS user already
# has a registered workspace. No Python is required for first installation,
# but use an available host Python only for read-only verification here.
INDEX="${XDG_CONFIG_HOME:-$HOME/.config}/ai-multi-media-kit/local-install.json"
[ -e "$INDEX" ] || [ -L "$INDEX" ] || INDEX="$SOURCE/config/local-install.json"
if [ -e "$INDEX" ] || [ -L "$INDEX" ]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Existing workspace locator: $INDEX. No setup performed; Agent must validate workspace.json before reuse." >&2
    exit 2
  fi
  ARGS=(show)
  if [ "$NEW_WORKSPACE" -eq 0 ]; then
    [ -z "$ROOT" ] || ARGS+=(--install-root "$ROOT")
    [ -z "$KNOWLEDGE" ] || ARGS+=(--knowledge-root "$KNOWLEDGE")
    [ -z "$OUTPUT" ] || ARGS+=(--output-root "$OUTPUT")
  elif [ -z "$ROOT" ] || [ -z "$KNOWLEDGE" ]; then
    echo 'Explicit new workspace requires both --install-root and --knowledge-root' >&2; exit 2
  fi
  python3 "$SOURCE/scripts/workspace_locator.py" "${ARGS[@]}" || exit 2
  if [ "$NEW_WORKSPACE" -eq 0 ]; then
    echo 'REUSE_EXISTING_WORKSPACE: verified paths above; skipping initialization and all downloads.'
    exit 0
  fi
fi
if [ -z "$ROOT" ]; then
  [ "$NONINTERACTIVE" -eq 0 ] || { echo '--install-root is required' >&2; exit 2; }
  read -r -p "Tool installation root [$HOME/AI-Media-Studio]: " ROOT || exit 2
  ROOT="${ROOT:-$HOME/AI-Media-Studio}"
fi
# Recover a known existing runtime without asking for paths already in its config.
KNOWN_ROOT="$ROOT"
case "$KNOWN_ROOT" in '~'*) KNOWN_ROOT="$HOME${KNOWN_ROOT#\~}";; esac
case "$KNOWN_ROOT" in /*) ;; *) KNOWN_ROOT="$PWD/$KNOWN_ROOT";; esac
KNOWN_ROOT="${KNOWN_ROOT%/}"
if [ -f "$KNOWN_ROOT/config/workspace.json" ]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo 'Existing workspace found; Agent must inspect config/workspace.json before reuse.' >&2; exit 2
  fi
  ARGS=(inspect --install-root "$KNOWN_ROOT")
  [ -z "$KNOWLEDGE" ] || ARGS+=(--knowledge-root "$KNOWLEDGE")
  [ -z "$OUTPUT" ] || ARGS+=(--output-root "$OUTPUT")
  python3 "$SOURCE/scripts/workspace_locator.py" "${ARGS[@]}" || exit 2
  echo 'REUSE_EXISTING_WORKSPACE: skipping dependencies and configuration.'
  exit 0
fi
if [ -z "$KNOWLEDGE" ]; then
  [ "$NONINTERACTIVE" -eq 0 ] || { echo '--knowledge-root is required' >&2; exit 2; }
  read -r -p "Company knowledge root [$HOME/Company-Knowledge]: " KNOWLEDGE || exit 2
  KNOWLEDGE="${KNOWLEDGE:-$HOME/Company-Knowledge}"
fi
case "$ROOT" in '~'*) ROOT="$HOME${ROOT#\~}";; esac
case "$KNOWLEDGE" in '~'*) KNOWLEDGE="$HOME${KNOWLEDGE#\~}";; esac
case "$ROOT" in /*) ;; *) ROOT="$PWD/$ROOT";; esac
case "$KNOWLEDGE" in /*) ;; *) KNOWLEDGE="$PWD/$KNOWLEDGE";; esac
ROOT="${ROOT%/}"; KNOWLEDGE="${KNOWLEDGE%/}"
case "$KNOWLEDGE/" in "$ROOT/"* ) echo 'Install root may not contain knowledge root' >&2; exit 2;; esac
# Preserve custom output_root in an already-initialized workspace when the
# operator omits --output-root. Prompt on first install only.
if [ -z "$OUTPUT" ] && [ ! -f "$ROOT/config/workspace.json" ]; then
  if [ "$NONINTERACTIVE" -eq 1 ]; then
    OUTPUT="$ROOT/outputs"
  else
    read -r -p "Project output root [$ROOT/outputs]: " OUTPUT || exit 2
    OUTPUT="${OUTPUT:-$ROOT/outputs}"
  fi
fi
if [ -n "$OUTPUT" ]; then
  case "$OUTPUT" in '~'*) OUTPUT="$HOME${OUTPUT#\~}";; esac
  case "$OUTPUT" in /*) ;; *) OUTPUT="$PWD/$OUTPUT";; esac
  OUTPUT="${OUTPUT%/}"
  case "$KNOWLEDGE/" in "$OUTPUT/"* ) echo 'Project output may not contain the knowledge root' >&2; exit 2;; esac
  case "$OUTPUT/" in "$KNOWLEDGE/"* ) echo 'Project output may not be inside the knowledge root' >&2; exit 2;; esac
  if [ "$OUTPUT" != "$ROOT/outputs" ]; then
    case "$ROOT/" in "$OUTPUT/"* ) echo 'Project output may not contain the install root' >&2; exit 2;; esac
    case "$OUTPUT/" in "$ROOT/"* ) echo 'Project output may not be inside the install root' >&2; exit 2;; esac
  fi
fi
case "$ROOT/" in "$KNOWLEDGE/"* ) echo 'Knowledge root may not contain install root' >&2; exit 2;; esac
if [ -f "$ROOT/config/workspace.json" ]; then
  # Python bootstrap follows, but refuse silently changing existing workspace roots:
  if ! grep -Fq "\"install_root\": \"$ROOT\"" "$ROOT/config/workspace.json" || \
     ! grep -Fq "\"knowledge_root\": \"$KNOWLEDGE\"" "$ROOT/config/workspace.json"; then
     echo 'Existing workspace paths differ. Review config/workspace.json before proceeding.' >&2; exit 2
  fi
fi
OS="$(uname -s)"; ARCH="$(uname -m)"
case "$ARCH" in x86_64|amd64) ARCH=x64;; arm64|aarch64) ARCH=arm64;; *) echo "Unsupported architecture: $ARCH" >&2;exit 2;; esac
case "$OS-$ARCH" in
  Linux-x64) TARGET=uv-x86_64-unknown-linux-gnu.tar.gz; SHA=23bf5552d220e0842b65c862097b2ebaeba0064b74eda5e565e77fd25969d8c8;;
  Linux-arm64) TARGET=uv-aarch64-unknown-linux-gnu.tar.gz; SHA=0804e9b164c64b6914182d5920c08551958a095986f10a3731056df701126436;;
  Darwin-x64) TARGET=uv-x86_64-apple-darwin.tar.gz; SHA=cb5fa57bafe68fc0fb94b17f06bee0b0b9a7feb94ccbd110445afa0696e39273;;
  Darwin-arm64) TARGET=uv-aarch64-apple-darwin.tar.gz; SHA=a9a8df1eedeb192f2e47e40e2faabfb387db4b850209118786d42f89dde3e0ba;;
  *) echo "Unsupported host: $OS-$ARCH (Linux musl is not supported by this installer)" >&2; exit 2;;
esac
sha_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 "$1" | awk '{print $NF}'
  else echo 'Need a system SHA256 utility (sha256sum, shasum or openssl)' >&2;return 2; fi
}
verified_fetch() {
  local url="$1" dest="$2" sha="$3" part="${2}.part"
  if [ -f "$dest" ] && [ "$(sha_file "$dest")" = "$sha" ]; then echo "Verified cached: $dest";return 0;fi
  rm -f "$part"
  echo "Downloading and verifying: $url"
  if command -v curl >/dev/null 2>&1; then curl --proto '=https' --tlsv1.2 -fL --retry 2 --connect-timeout 25 -o "$part" "$url"
  elif command -v wget >/dev/null 2>&1; then wget --https-only -O "$part" "$url"
  else echo 'Missing curl/wget, required for HTTPS bootstrap' >&2;return 2;fi
  if [ "$(sha_file "$part")" != "$sha" ]; then rm -f "$part";echo 'SHA256 mismatch' >&2;return 2;fi
  mv -f "$part" "$dest"
}
UV_DIR="$ROOT/runtime/bootstrap/uv"; UV="$UV_DIR/uv"
DOWNLOADS="$ROOT/runtime/downloads"
mkdir -p "$UV_DIR" "$DOWNLOADS"
if [ ! -x "$UV" ]; then
  ARCHIVE="$DOWNLOADS/$TARGET"
  verified_fetch "https://releases.astral.sh/github/uv/releases/download/0.12.19/$TARGET" "$ARCHIVE" "$SHA"
  TEMP_EXTRACT="$ROOT/runtime/bootstrap/uv-extract-temp"
  [ ! -e "$TEMP_EXTRACT" ] || { echo 'Incomplete bootstrap extraction detected; review before retry.' >&2;exit 2; }
  mkdir -p "$TEMP_EXTRACT"
  tar -xzf "$ARCHIVE" -C "$TEMP_EXTRACT"
  UV_IN_ARCHIVE="$(find "$TEMP_EXTRACT" -type f -name uv | head -n 1)"
  [ -n "$UV_IN_ARCHIVE" ] || { echo 'uv archive is missing binary' >&2;exit 2; }
  cp "$UV_IN_ARCHIVE" "$UV"
  chmod 755 "$UV"
  rm -rf "$TEMP_EXTRACT"
fi
"$UV" --version
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
export PATH="$UV_DIR:$ROOT/tools/ffmpeg/bin:$PATH"
echo 'Provisioning Python 3.12 inside the chosen installation root...'
"$UV" python install 3.12 --no-bin
PYTHON="$("$UV" python find --managed-python 3.12)"
[ -x "$PYTHON" ] || { echo 'Managed Python not available' >&2; exit 2; }
"$PYTHON" -c 'import sys;assert sys.version_info[:2] == (3,12)'
INIT_ARGS=(--install-root "$ROOT" --knowledge-root "$KNOWLEDGE")
[ -z "$OUTPUT" ] || INIT_ARGS+=(--output-root "$OUTPUT")
[ "$NEW_WORKSPACE" -eq 0 ] || INIT_ARGS+=(--new-workspace)
"$PYTHON" "$SOURCE/scripts/init_workspace.py" "${INIT_ARGS[@]}"
if [ "$SKIP_FFMPEG" -eq 0 ]; then
  "$PYTHON" "$SOURCE/scripts/bootstrap_assets.py" --root "$ROOT" --ffmpeg
fi
# Save the default locator only when initial provisioning has completed.
"$PYTHON" "$SOURCE/scripts/workspace_locator.py" register --install-root "$ROOT"
echo "READY: workspace $ROOT"
echo "READY: knowledge $KNOWLEDGE"
echo "Project outputs: see $ROOT/config/workspace.json (output_root)"
echo "Python: $PYTHON"
echo "Use: bash \"$ROOT/run-studio.sh\" doctor"
echo 'No sudo, homebrew, global PATH changes or machine-wide Python installation.'
