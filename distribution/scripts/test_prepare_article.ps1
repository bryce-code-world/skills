#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('distribution-prepare-' + [guid]::NewGuid().ToString('N'))
$article = Join-Path $root 'article.md'
$cover = Join-Path $root 'cover.png'
$bodyImage = Join-Path $root 'body.png'
$output = Join-Path $root 'output'
$script = Join-Path $PSScriptRoot 'prepare_article.ps1'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$png = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')

try {
    [System.IO.Directory]::CreateDirectory($root) | Out-Null
    [System.IO.File]::WriteAllBytes($cover, $png)
    [System.IO.File]::WriteAllBytes($bodyImage, $png)
    $fixture = @'
---
platform: wechat
title: "Native payload test"
summary: "Stable conversion"
cover: "cover.png"
---

Opening paragraph with a **real emphasis**.

## Section title

1. First item.
2. Second item.

![Body image](body.png)
'@
    [System.IO.File]::WriteAllText($article, $fixture.Replace("`r`n", "`n"), $utf8)

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Platform wechat -InputPath $article -OutputDirectory $output | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Normal sample failed.' }

    $html = [System.IO.File]::ReadAllText((Join-Path $output 'body.html'), [System.Text.Encoding]::UTF8)
    $markdown = [System.IO.File]::ReadAllText((Join-Path $output 'body.md'), [System.Text.Encoding]::UTF8)
    if ($html -notmatch '<strong style=' -or
        ([regex]::Matches($html, 'data-list-item="ordered"')).Count -ne 2 -or
        $html -notmatch 'font-size:16px;line-height:1.85' -or
        $markdown -match '^---') {
        throw 'Generated payload does not satisfy the contract.'
    }

    $ErrorActionPreference = 'Continue'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Platform zhihu -InputPath $article -OutputDirectory (Join-Path $root 'failure') *> $null
    $failureExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($failureExitCode -eq 0) { throw 'Platform mismatch unexpectedly passed.' }

    Write-Output '{"ok":true,"checks":5}'
} finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
