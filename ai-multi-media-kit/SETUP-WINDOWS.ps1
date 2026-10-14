#requires -version 5.1
<#
Self-contained bootstrap: Windows PowerShell only; no system Python, Git or uv required.
No system PATH changes, elevation, or remote script execution.
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = '',
    [string]$KnowledgeRoot = '',
    [switch]$NonInteractive,
    [switch]$SkipGit,
    [switch]$SkipFfmpeg
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$source = Split-Path -Parent $MyInvocation.MyCommand.Path
function Fail([string]$Message) { throw $Message }
function Canonical([string]$PathText) {
    if ($PathText.StartsWith('~')) { $PathText = $env:USERPROFILE + $PathText.Substring(1) }
    return [IO.Path]::GetFullPath($PathText).TrimEnd([char[]]@('\','/'))
}
function RunChecked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { Fail "Command exited $LASTEXITCODE : $Program" }
}
function VerifiedDownload([string]$Url,[string]$Output,[string]$Sha256) {
    if (Test-Path -LiteralPath $Output -PathType Leaf) {
        $hash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -eq $Sha256.ToLowerInvariant()) { Write-Host "Using verified cache: $Output"; return }
    }
    $partial = "$Output.part"
    try {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
        Write-Host "Downloading (verified): $Url"
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $partial -MaximumRedirection 5
        $hash = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne $Sha256.ToLowerInvariant()) { Fail "SHA256 mismatch: $Url" }
        Move-Item -LiteralPath $partial -Destination $Output -Force
    } finally {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
    }
}
try {
    $homeDefault = if (Test-Path 'D:\') { 'D:\AI-Media-Studio' } else { Join-Path $env:USERPROFILE 'AI-Media-Studio' }
    $knowledgeDefault = if (Test-Path 'D:\') { 'D:\Company-Knowledge' } else { Join-Path $env:USERPROFILE 'Company-Knowledge' }
    if (-not $InstallRoot) {
        if ($NonInteractive) { Fail 'NonInteractive requires -InstallRoot and -KnowledgeRoot' }
        $answer = Read-Host "Tool installation root [$homeDefault]"
        $InstallRoot = if ($answer) { $answer } else { $homeDefault }
    }
    if (-not $KnowledgeRoot) {
        if ($NonInteractive) { Fail 'NonInteractive requires -InstallRoot and -KnowledgeRoot' }
        $answer = Read-Host "Company knowledge root [$knowledgeDefault]"
        $KnowledgeRoot = if ($answer) { $answer } else { $knowledgeDefault }
    }
    $root = Canonical $InstallRoot
    $knowledge = Canonical $KnowledgeRoot
    if ([string]::Equals($root,$knowledge,[StringComparison]::OrdinalIgnoreCase) -or
        $root.StartsWith($knowledge+'\',[StringComparison]::OrdinalIgnoreCase) -or
        $knowledge.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) {
        Fail 'Tool root and knowledge root must be separate and non-nested.'
    }
    $existing = Join-Path $root 'config\workspace.json'
    if (Test-Path -LiteralPath $existing) {
        $cfg = Get-Content -LiteralPath $existing -Raw -Encoding UTF8 | ConvertFrom-Json
        if ((Canonical $cfg.install_root) -ine $root -or (Canonical $cfg.knowledge_root) -ine $knowledge) {
            Fail 'Existing workspace has other paths. No changes were made.'
        }
    }
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    $key = switch ($arch) {
        'X64' { 'windows-x64' }
        'Arm64' { 'windows-arm64' }
        default { Fail "Unsupported Windows architecture: $arch" }
    }
    $manifest = Get-Content -LiteralPath (Join-Path $source 'config\bootstrap-assets.json') -Encoding UTF8 -Raw | ConvertFrom-Json
    $asset = $manifest.uv.assets.PSObject.Properties[$key].Value
    if (-not $asset) { Fail "No UV asset for $key" }
    $uvdir = Join-Path $root 'runtime\bootstrap\uv'
    $uv = Join-Path $uvdir 'uv.exe'
    $down = Join-Path $root 'runtime\downloads'
    New-Item -ItemType Directory -Force -Path $uvdir,$down | Out-Null
    $archive = Join-Path $down $asset.file
    if (-not (Test-Path -LiteralPath $uv -PathType Leaf)) {
        VerifiedDownload ($manifest.uv.source+'/'+$asset.file) $archive $asset.sha256
        $temp = Join-Path $root 'runtime\bootstrap\uv-extract-temp'
        if (Test-Path -LiteralPath $temp) { Fail "Interrupted extraction directory needs review: $temp" }
        New-Item -ItemType Directory -Force -Path $temp | Out-Null
        try {
            Expand-Archive -LiteralPath $archive -DestinationPath $temp
            $found = Get-ChildItem -LiteralPath $temp -File -Filter uv.exe -Recurse | Select-Object -First 1
            if (-not $found) { Fail 'uv.exe not found in release zip.' }
            Copy-Item -LiteralPath $found.FullName -Destination $uv
        } finally { Remove-Item -LiteralPath $temp -Force -Recurse -ErrorAction SilentlyContinue }
    }
    RunChecked $uv @('--version')
    $env:UV_CACHE_DIR = Join-Path $root 'runtime\uv-cache'
    $env:UV_PYTHON_INSTALL_DIR = Join-Path $root 'runtime\uv-python'
    $env:UV_PYTHON_BIN_DIR = Join-Path $root 'runtime\uv-python-bin'
    $env:UV_TOOL_DIR = Join-Path $root 'runtime\uv-tools'
    $env:UV_PYTHON_INSTALL_BIN = '0'
    $env:UV_MANAGED_PYTHON = '1'
    $env:UV_LINK_MODE = 'copy'
    $env:PIP_CACHE_DIR = Join-Path $root 'runtime\pip-cache'
    $env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $root 'runtime\browsers'
    $env:HF_HOME = Join-Path $root 'runtime\huggingface'
    $env:XDG_CACHE_HOME = Join-Path $root 'runtime\cache'
    $env:TEMP = Join-Path $root 'runtime\tmp'
    $env:TMP = $env:TEMP
    New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
    $env:PATH = "$uvdir;$(Join-Path $root 'tools\git\cmd');$(Join-Path $root 'tools\ffmpeg\bin');$env:PATH"
    Write-Host 'Provisioning Python 3.12 in your chosen folder...'
    RunChecked $uv @('python','install','3.12','--no-bin')
    $python = (& $uv python find --managed-python 3.12 | Select-Object -Last 1).Trim()
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $python -PathType Leaf)) { Fail 'uv-managed Python not found' }
    RunChecked $python @('-c','import sys; assert sys.version_info[:2] == (3,12)')
    RunChecked $python @((Join-Path $source 'scripts\init_workspace.py'),'--install-root',$root,'--knowledge-root',$knowledge)
    $more = @('--root',$root)
    if (-not $SkipGit) { $more += '--git' }
    if (-not $SkipFfmpeg) { $more += '--ffmpeg' }
    if ($more.Count -gt 2) {
        Write-Host 'Provisioning portable Git and media tools (downloaded files are checked)...'
        RunChecked $python (@((Join-Path $source 'scripts\bootstrap_assets.py')) + $more)
    }
    # Persist the locator only after the selected tool bootstrap has succeeded.
    RunChecked $python @((Join-Path $source 'scripts\workspace_locator.py'),'register','--install-root',$root)
    Write-Host ''
    Write-Host "SUCCESS: workspace $root"
    Write-Host "SUCCESS: knowledge $knowledge"
    Write-Host "Python: $python"
    Write-Host "Use: powershell -ExecutionPolicy Bypass -File `"$(Join-Path $root 'RUN-STUDIO-WINDOWS.ps1')`" -Task doctor"
    Write-Host 'No machine-wide Python / PATH modification performed.'
} catch {
    Write-Error "Bootstrap failed: $($_.Exception.Message)"
    exit 2
}
