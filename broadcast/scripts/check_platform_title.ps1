#requires -version 5.1
<#
.SYNOPSIS
Checks that platform Markdown keeps its title in front matter and not in the body.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8

function Get-PlatformFiles([string]$TargetPath) {
    $resolved = Resolve-Path -LiteralPath $TargetPath -ErrorAction Stop
    if ((Get-Item -LiteralPath $resolved).PSIsContainer) {
        return @(Get-ChildItem -LiteralPath $resolved -Recurse -File -Filter '*.md')
    }
    return @(Get-Item -LiteralPath $resolved)
}

function Remove-YamlQuotes([string]$Value) {
    $trimmed = $Value.Trim()
    if ($trimmed.Length -ge 2) {
        $first = $trimmed[0]
        $last = $trimmed[$trimmed.Length - 1]
        if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
            return $trimmed.Substring(1, $trimmed.Length - 2)
        }
    }
    return $trimmed
}

$supported = @('wechat', 'zhihu', 'csdn', 'juejin')
$failures = @()
$checked = 0

foreach ($file in Get-PlatformFiles $Path) {
    $lines = [System.IO.File]::ReadAllLines($file.FullName, $utf8)
    if ($lines.Count -eq 0 -or $lines[0].TrimStart([char]0xFEFF) -ne '---') { continue }

    $closing = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq '---') { $closing = $i; break }
    }
    if ($closing -lt 0) { continue }

    $platform = ''
    $title = ''
    for ($i = 1; $i -lt $closing; $i++) {
        if ($lines[$i] -match '^platform:\s*(.+?)\s*$') { $platform = Remove-YamlQuotes $Matches[1] }
        if ($lines[$i] -match '^title:\s*(.+?)\s*$') { $title = Remove-YamlQuotes $Matches[1] }
    }
    if ($supported -notcontains $platform) { continue }

    $checked++
    if ([string]::IsNullOrWhiteSpace($title)) {
        $failures += "$($file.FullName): front matter requires a non-empty title"
    }

    $inFence = $false
    $fenceMarker = ''
    $firstBodyLine = $null
    for ($i = $closing + 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*(```|~~~)') {
            $marker = $Matches[1]
            if (-not $inFence) { $inFence = $true; $fenceMarker = $marker }
            elseif ($marker -eq $fenceMarker) { $inFence = $false; $fenceMarker = '' }
            continue
        }
        if ($inFence -or [string]::IsNullOrWhiteSpace($line)) { continue }

        if ($null -eq $firstBodyLine) { $firstBodyLine = $line.Trim() }
        if ($line -match '^#\s+') {
            $failures += "$($file.FullName):$($i + 1): platform body must not contain an H1"
        }
    }

    if ($null -eq $firstBodyLine) {
        $failures += "$($file.FullName): platform body is empty"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($title) -and $firstBodyLine -eq $title) {
        $failures += "$($file.FullName):$($closing + 2): first body line repeats front matter title"
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine($_) }
    exit 1
}

Write-Output "platform title check passed: $checked file(s)"
