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
$captionPrefix = ([string][char]0x56FE) + ([char]0x6CE8) + ([char]0xFF1A)
$legacyCaptionPrefix = ([string][char]0x56FE) + ([char]0xFF1A)
$captionText = 'The deterministic system verifies AI candidates.'

try {
    [System.IO.Directory]::CreateDirectory($root) | Out-Null
    [System.IO.File]::WriteAllBytes($cover, $png)
    [System.IO.File]::WriteAllBytes($bodyImage, $png)
    foreach ($platform in @('wechat', 'zhihu', 'csdn', 'juejin')) {
        $platformOutput = Join-Path $output $platform
        $sourceCaptionPrefix = if ($platform -eq 'zhihu') { $legacyCaptionPrefix } else { $captionPrefix }
        $fixture = @"
---
platform: $platform
title: "Native payload test"
summary: "Stable conversion"
cover: "cover.png"
---

Opening paragraph with a **real emphasis**.

## Section title

1. First item.
2. Second item.

![Testing loop diagram](body.png)

$sourceCaptionPrefix$captionText
"@
        [System.IO.File]::WriteAllText($article, $fixture.Replace("`r`n", "`n"), $utf8)

        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Platform $platform -InputPath $article -OutputDirectory $platformOutput | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Normal sample failed for $platform." }

        $html = [System.IO.File]::ReadAllText((Join-Path $platformOutput 'body.html'), [System.Text.Encoding]::UTF8)
        $markdown = [System.IO.File]::ReadAllText((Join-Path $platformOutput 'body.md'), [System.Text.Encoding]::UTF8)
        $manifest = Get-Content -LiteralPath (Join-Path $platformOutput 'manifest.json') -Raw | ConvertFrom-Json

        if ($manifest.schema_version -ne 2 -or
            $manifest.images.Count -ne 1 -or
            $manifest.images[0].alt -ne 'Testing loop diagram' -or
            $manifest.images[0].caption -ne $captionText -or
            $manifest.images[0].role -ne 'informative' -or
            ([regex]::Matches($html, [regex]::Escape($captionText))).Count -ne 1 -or
            $html -notmatch 'alt="Testing loop diagram"' -or
            $markdown -match '^---') {
            throw "Generated image contract is incomplete for $platform."
        }

        if ($platform -eq 'wechat') {
            if ($html -notmatch 'data-image-caption="true"' -or
                $html -notmatch 'font-size:13px' -or
                $html -notmatch '<strong style=' -or
                ([regex]::Matches($html, 'data-list-item="ordered"')).Count -ne 2 -or
                $html -notmatch 'font-size:16px;line-height:1.85') {
                throw 'Wechat caption style is missing.'
            }
        } else {
            if ($html -notmatch '<figcaption>') { throw "$platform semantic caption is missing." }
        }

        if ($platform -in @('csdn', 'juejin') -and $markdown -notmatch ('\*' + [regex]::Escape($captionPrefix + $captionText) + '\*')) {
            throw "$platform Markdown caption style is missing."
        }
    }

    $missingCaption = @"
---
platform: wechat
title: "Missing caption"
cover: "cover.png"
---

![Informative image](body.png)
"@
    [System.IO.File]::WriteAllText($article, $missingCaption.Replace("`r`n", "`n"), $utf8)
    $ErrorActionPreference = 'Continue'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Platform wechat -InputPath $article -OutputDirectory (Join-Path $root 'missing-caption') *> $null
    $failureExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($failureExitCode -eq 0) { throw 'Informative image without caption unexpectedly passed.' }

    $orphanCaption = @"
---
platform: wechat
title: "Orphan caption"
cover: "cover.png"
---

$captionPrefix$captionText
"@
    [System.IO.File]::WriteAllText($article, $orphanCaption.Replace("`r`n", "`n"), $utf8)
    $ErrorActionPreference = 'Continue'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Platform wechat -InputPath $article -OutputDirectory (Join-Path $root 'orphan-caption') *> $null
    $failureExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($failureExitCode -eq 0) { throw 'Orphan caption unexpectedly passed.' }

    $decorative = @'
---
platform: wechat
title: "Decorative image"
cover: "cover.png"
---

![](body.png)
'@
    [System.IO.File]::WriteAllText($article, $decorative.Replace("`r`n", "`n"), $utf8)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Platform wechat -InputPath $article -OutputDirectory (Join-Path $root 'decorative') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Decorative image without caption failed.' }
    $decorativeManifest = Get-Content -LiteralPath (Join-Path $root 'decorative\manifest.json') -Raw | ConvertFrom-Json
    if ($decorativeManifest.images[0].role -ne 'decorative' -or $decorativeManifest.images[0].caption -ne '') {
        throw 'Decorative image metadata is incorrect.'
    }

    $decorativeWithCaption = @"
---
platform: wechat
title: "Decorative image with caption"
cover: "cover.png"
---

![](body.png)

$captionPrefix$captionText
"@
    [System.IO.File]::WriteAllText($article, $decorativeWithCaption.Replace("`r`n", "`n"), $utf8)
    $ErrorActionPreference = 'Continue'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Platform wechat -InputPath $article -OutputDirectory (Join-Path $root 'decorative-caption') *> $null
    $failureExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($failureExitCode -eq 0) { throw 'Decorative image with caption unexpectedly passed.' }

    [System.IO.File]::WriteAllText($article, $fixture.Replace("`r`n", "`n"), $utf8)
    $ErrorActionPreference = 'Continue'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Platform wechat -InputPath $article -OutputDirectory (Join-Path $root 'platform-mismatch') *> $null
    $failureExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($failureExitCode -eq 0) { throw 'Platform mismatch unexpectedly passed.' }

    $captionInsideCode = @"
---
platform: csdn
title: "Caption text inside code"
cover: "cover.png"
---

``````text
$captionPrefix$captionText
``````
"@
    [System.IO.File]::WriteAllText($article, $captionInsideCode.Replace("`r`n", "`n"), $utf8)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Platform csdn -InputPath $article -OutputDirectory (Join-Path $root 'caption-inside-code') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Caption-like text inside a code block was parsed as a caption.' }

    Write-Output '{"ok":true,"checks":21}'
} finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
