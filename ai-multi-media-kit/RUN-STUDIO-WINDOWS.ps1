#requires -version 5.1
[CmdletBinding()]
param([string]$Task = 'doctor',[Parameter(ValueFromRemainingArguments=$true)][string[]]$TaskArgs)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$uv=Join-Path $root 'runtime\bootstrap\uv\uv.exe'
if (!(Test-Path -LiteralPath $uv -PathType Leaf)) { throw 'Run SETUP-WINDOWS.ps1 first.' }
$env:UV_CACHE_DIR=Join-Path $root 'runtime\uv-cache'
$env:UV_PYTHON_INSTALL_DIR=Join-Path $root 'runtime\uv-python'
$env:UV_PYTHON_BIN_DIR=Join-Path $root 'runtime\uv-python-bin'
$env:UV_TOOL_DIR=Join-Path $root 'runtime\uv-tools'
$env:UV_PYTHON_INSTALL_BIN='0'
$env:UV_MANAGED_PYTHON='1'
$env:UV_LINK_MODE='copy'
$env:PIP_CACHE_DIR=Join-Path $root 'runtime\pip-cache'
$env:PLAYWRIGHT_BROWSERS_PATH=Join-Path $root 'runtime\browsers'
$env:HF_HOME=Join-Path $root 'runtime\huggingface'
$env:XDG_CACHE_HOME=Join-Path $root 'runtime\cache'
$env:TEMP=Join-Path $root 'runtime\tmp'
$env:TMP=$env:TEMP
New-Item -ItemType Directory -Force $env:TEMP | Out-Null
$env:PATH="$(Join-Path $root 'runtime\bootstrap\uv');$(Join-Path $root 'tools\git\cmd');$(Join-Path $root 'tools\ffmpeg\bin');$env:PATH"
$python=(& $uv python find --managed-python 3.12 | Select-Object -Last 1).Trim()
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $python)) { throw 'Managed Python 3.12 missing, rerun setup.' }
switch ($Task) {
    doctor { & $python (Join-Path $root 'scripts\doctor.py') --install-root $root @TaskArgs }
    test { Push-Location $root;try { & $python -m unittest discover -s tests -p 'test_*.py' -v } finally { Pop-Location } }
    {$_ -in @('studio','materials','installer','bootstrap_assets','configure_mcp','offline_smoke')} { & $python (Join-Path $root "scripts\$Task.py") --root $root @TaskArgs }
    export_assets { & $python (Join-Path $root 'scripts\export_assets.py') --install-root $root @TaskArgs }
    upgrade_core { & $python (Join-Path $root 'scripts\upgrade_core.py') --root $root @TaskArgs }
    default { throw "Unknown command: $Task" }
}
exit $LASTEXITCODE
