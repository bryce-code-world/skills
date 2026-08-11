#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('wechat', 'zhihu', 'csdn', 'juejin')]
    [string]$Platform,

    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$CaptionLinePattern = '^(?:\u56FE\u6CE8|\u56FE)\uFF1A\s*(.*)$'
$CanonicalCaptionPrefix = ([string][char]0x56FE) + ([char]0x6CE8) + ([char]0xFF1A)

function Write-Utf8Lf {
    param([string]$Path, [string]$Text)
    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.File]::WriteAllText($Path, $normalized, $Utf8NoBom)
}

function Unquote-Value {
    param([string]$Value)
    $trimmed = $Value.Trim()
    if ($trimmed.Length -ge 2) {
        $first = $trimmed.Substring(0, 1)
        $last = $trimmed.Substring($trimmed.Length - 1, 1)
        if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
            return $trimmed.Substring(1, $trimmed.Length - 2)
        }
    }
    return $trimmed
}

function Convert-Inline {
    param([string]$Text, [string]$TargetPlatform)

    $encoded = [System.Net.WebUtility]::HtmlEncode($Text)
    $strongStyle = if ($TargetPlatform -eq 'wechat') {
        'font-weight:700;color:#242424;'
    } else {
        'font-weight:700;'
    }
    $codeStyle = if ($TargetPlatform -eq 'wechat') {
        'font-family:Consolas,Menlo,monospace;font-size:0.94em;background:#f5f5f5;padding:1px 4px;border-radius:3px;'
    } else {
        'font-family:monospace;'
    }

    $strongEvaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        return '<strong style="' + $strongStyle + '">' + $match.Groups[1].Value + '</strong>'
    }
    $codeEvaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        return '<code style="' + $codeStyle + '">' + $match.Groups[1].Value + '</code>'
    }

    $encoded = [regex]::Replace($encoded, '\*\*(.+?)\*\*', $strongEvaluator)
    $encoded = [regex]::Replace($encoded, '`([^`]+)`', $codeEvaluator)
    return $encoded
}

function Test-SpecialLine {
    param([string]$Line)
    $trimmed = $Line.Trim()
    return (
        $trimmed -match '^#{2,3}\s+' -or
        $trimmed -match '^```' -or
        $trimmed -match '^-\s+' -or
        $trimmed -match '^\d+\.\s+' -or
        $trimmed -match $CaptionLinePattern -or
        $trimmed -match '^!\[[^\]]*\]\([^)]+\)$'
    )
}

$resolvedInput = [System.IO.Path]::GetFullPath($InputPath)
if (-not [System.IO.File]::Exists($resolvedInput)) {
    throw "Input file does not exist: $resolvedInput"
}

$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
[System.IO.Directory]::CreateDirectory($resolvedOutput) | Out-Null

$text = [System.IO.File]::ReadAllText($resolvedInput, [System.Text.Encoding]::UTF8)
$text = $text.TrimStart([char]0xFEFF)
$text = $text.Replace("`r`n", "`n").Replace("`r", "`n")
$lines = $text.Split([char]10)

if ($lines.Count -lt 3 -or $lines[0].Trim() -ne '---') {
    throw 'Article must start with YAML front matter.'
}

$frontMatterEnd = -1
for ($i = 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -eq '---') {
        $frontMatterEnd = $i
        break
    }
}
if ($frontMatterEnd -lt 0) {
    throw 'Front matter is not closed.'
}

$meta = [ordered]@{}
for ($i = 1; $i -lt $frontMatterEnd; $i++) {
    if ($lines[$i] -match '^\s*([^:#]+):\s*(.*?)\s*$') {
        $meta[$matches[1].Trim()] = Unquote-Value $matches[2]
    }
}

foreach ($required in @('platform', 'title')) {
    if (-not $meta.Contains($required) -or [string]::IsNullOrWhiteSpace([string]$meta[$required])) {
        throw "Missing front matter field: $required"
    }
}
if ([string]$meta['platform'] -ne $Platform) {
    throw "Platform mismatch: article=$($meta['platform']), requested=$Platform"
}

$bodyLines = if ($frontMatterEnd + 1 -lt $lines.Count) {
    @($lines[($frontMatterEnd + 1)..($lines.Count - 1)])
} else {
    @()
}
$bodyText = ($bodyLines -join "`n").Trim()
if ([string]::IsNullOrWhiteSpace($bodyText)) {
    throw 'Article body is empty.'
}

if ($Platform -in @('wechat', 'zhihu')) {
    foreach ($line in $bodyLines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^```' -or $trimmed -match '^>' -or $trimmed -match '^\|.*\|$') {
            throw "$Platform article contains a structure that is not allowed: $trimmed"
        }
    }
}

$paragraphStyle = if ($Platform -eq 'wechat') {
    'font-size:16px;line-height:1.85;color:#303030;margin:0 0 20px;text-align:left;letter-spacing:0.02em;'
} else {
    ''
}
$heading2Style = if ($Platform -eq 'wechat') {
    'font-size:19px;line-height:1.5;font-weight:700;color:#242424;margin:42px 0 20px;padding-left:10px;border-left:3px solid #c58a45;text-align:left;'
} else {
    ''
}
$heading3Style = if ($Platform -eq 'wechat') {
    'font-size:17px;line-height:1.55;font-weight:700;color:#242424;margin:32px 0 16px;text-align:left;'
} else {
    ''
}
$listStyle = if ($Platform -eq 'wechat') {
    'font-size:16px;line-height:1.85;color:#303030;margin:0 0 14px;text-align:left;padding-left:0;'
} else {
    ''
}
$imageStyle = if ($Platform -eq 'wechat') {
    'display:block;width:100%;height:auto;margin:28px auto 8px;'
} else {
    'max-width:100%;height:auto;'
}
$imageContainerStyle = if ($Platform -eq 'wechat') { 'margin:0;' } else { '' }
$captionStyle = if ($Platform -eq 'wechat') {
    'font-size:13px;line-height:1.6;color:#888888;margin:0 0 24px;text-align:center;'
} else {
    ''
}

$captionByImageLine = @{}
$boundCaptionLines = @{}
$captionByCaptionLine = @{}
$codeLines = @{}
$insideCode = $false
for ($lineIndex = 0; $lineIndex -lt $bodyLines.Count; $lineIndex++) {
    if ($bodyLines[$lineIndex].Trim() -match '^```') {
        $codeLines[$lineIndex] = $true
        $insideCode = -not $insideCode
    } elseif ($insideCode) {
        $codeLines[$lineIndex] = $true
    }
}

for ($lineIndex = 0; $lineIndex -lt $bodyLines.Count; $lineIndex++) {
    if ($codeLines.ContainsKey($lineIndex)) {
        continue
    }
    $trimmed = $bodyLines[$lineIndex].Trim()
    if ($trimmed -notmatch '^!\[([^\]]*)\]\([^)]+\)$') {
        continue
    }

    $alt = $matches[1]
    $captionLineIndex = $lineIndex + 1
    while ($captionLineIndex -lt $bodyLines.Count -and [string]::IsNullOrWhiteSpace($bodyLines[$captionLineIndex])) {
        $captionLineIndex++
    }
    $captionMatch = if ($captionLineIndex -lt $bodyLines.Count) {
        [regex]::Match($bodyLines[$captionLineIndex].Trim(), $CaptionLinePattern)
    } else {
        $null
    }

    if ([string]::IsNullOrWhiteSpace($alt)) {
        if ($null -ne $captionMatch -and $captionMatch.Success) {
            throw "Decorative image must not have a caption at body line $($captionLineIndex + 1)."
        }
        continue
    }

    if ($null -eq $captionMatch -or -not $captionMatch.Success -or [string]::IsNullOrWhiteSpace($captionMatch.Groups[1].Value)) {
        throw "Informative image is missing an adjacent caption at body line $($lineIndex + 1)."
    }

    $captionByImageLine[$lineIndex] = $captionMatch.Groups[1].Value.Trim()
    $boundCaptionLines[$captionLineIndex] = $true
    $captionByCaptionLine[$captionLineIndex] = $captionMatch.Groups[1].Value.Trim()
}

for ($lineIndex = 0; $lineIndex -lt $bodyLines.Count; $lineIndex++) {
    if (-not $codeLines.ContainsKey($lineIndex) -and $bodyLines[$lineIndex].Trim() -match $CaptionLinePattern -and -not $boundCaptionLines.ContainsKey($lineIndex)) {
        throw "Orphan image caption at body line $($lineIndex + 1)."
    }
}

$blocks = New-Object System.Collections.Generic.List[string]
$imageRecords = New-Object System.Collections.Generic.List[object]
$sourceDirectory = [System.IO.Path]::GetDirectoryName($resolvedInput)
$index = 0
while ($index -lt $bodyLines.Count) {
    $line = $bodyLines[$index].Trim()
    if ([string]::IsNullOrWhiteSpace($line)) {
        $index++
        continue
    }

    if ($line -match '^##\s+(.+)$') {
        $content = Convert-Inline $matches[1].Trim() $Platform
        $blocks.Add('<h2 style="' + $heading2Style + '">' + $content + '</h2>')
    } elseif ($line -match '^###\s+(.+)$') {
        $content = Convert-Inline $matches[1].Trim() $Platform
        $blocks.Add('<h3 style="' + $heading3Style + '">' + $content + '</h3>')
    } elseif ($line -match '^!\[([^\]]*)\]\(([^)]+)\)$') {
        $alt = $matches[1]
        $relativePath = $matches[2]
        $absolutePath = [System.IO.Path]::GetFullPath((Join-Path $sourceDirectory $relativePath))
        if (-not [System.IO.File]::Exists($absolutePath)) {
            throw "Article image does not exist: $absolutePath"
        }
        $placeholder = '__DISTRIBUTION_IMAGE_{0:D3}__' -f ($imageRecords.Count + 1)
        $imageRecords.Add([ordered]@{
            placeholder = $placeholder
            relative_path = $relativePath
            absolute_path = $absolutePath
            alt = $alt
            caption = if ($captionByImageLine.ContainsKey($index)) { [string]$captionByImageLine[$index] } else { '' }
            role = if ([string]::IsNullOrWhiteSpace($alt)) { 'decorative' } else { 'informative' }
        })
        $encodedAlt = [System.Net.WebUtility]::HtmlEncode($alt)
        if ($captionByImageLine.ContainsKey($index)) {
            $caption = Convert-Inline ([string]$captionByImageLine[$index]) $Platform
            if ($Platform -eq 'wechat') {
                $blocks.Add('<p data-image="true" style="' + $imageContainerStyle + '"><img src="' + $placeholder + '" alt="' + $encodedAlt + '" style="' + $imageStyle + '" /></p>')
                $blocks.Add('<p data-image-caption="true" style="' + $captionStyle + '">' + $caption + '</p>')
            } else {
                $blocks.Add('<figure data-image="true"><img src="' + $placeholder + '" alt="' + $encodedAlt + '" style="' + $imageStyle + '" /><figcaption>' + $caption + '</figcaption></figure>')
            }
        } else {
            $blocks.Add('<p data-image="true" style="' + $imageContainerStyle + '"><img src="' + $placeholder + '" alt="' + $encodedAlt + '" style="' + $imageStyle + '" /></p>')
        }
    } elseif ($boundCaptionLines.ContainsKey($index)) {
        # The caption is emitted with its image so it cannot fall through as body text.
    } elseif ($line -match '^-\s+(.+)$') {
        $items = New-Object System.Collections.Generic.List[object]
        while ($index -lt $bodyLines.Count -and $bodyLines[$index].Trim() -match '^-\s+(.+)$') {
            $items.Add((Convert-Inline $matches[1].Trim() $Platform))
            $index++
        }
        $index--
        if ($Platform -eq 'wechat') {
            foreach ($item in $items) {
                $blocks.Add('<p data-list-item="bullet" style="' + $listStyle + '"><strong style="font-weight:700;color:#242424;">&#8226;</strong>&nbsp;&nbsp;' + $item + '</p>')
            }
        } else {
            $htmlItems = ($items | ForEach-Object { '<li>' + $_ + '</li>' }) -join ''
            $blocks.Add('<ul>' + $htmlItems + '</ul>')
        }
    } elseif ($line -match '^\d+\.\s+(.+)$') {
        $items = New-Object System.Collections.Generic.List[object]
        while ($index -lt $bodyLines.Count -and $bodyLines[$index].Trim() -match '^(\d+)\.\s+(.+)$') {
            $items.Add([ordered]@{ number = $matches[1]; content = Convert-Inline $matches[2].Trim() $Platform })
            $index++
        }
        $index--
        if ($Platform -eq 'wechat') {
            foreach ($item in $items) {
                $blocks.Add('<p data-list-item="ordered" style="' + $listStyle + '"><strong style="font-weight:700;color:#242424;">' + $item.number + '.</strong>&nbsp;&nbsp;' + $item.content + '</p>')
            }
        } else {
            $htmlItems = ($items | ForEach-Object { '<li>' + $_.content + '</li>' }) -join ''
            $blocks.Add('<ol>' + $htmlItems + '</ol>')
        }
    } elseif ($line -match '^```') {
        $language = $line.Substring(3).Trim()
        $code = New-Object System.Collections.Generic.List[string]
        $index++
        while ($index -lt $bodyLines.Count -and $bodyLines[$index].Trim() -notmatch '^```') {
            $code.Add($bodyLines[$index])
            $index++
        }
        if ($index -ge $bodyLines.Count) {
            throw 'Code fence is not closed.'
        }
        $encodedCode = [System.Net.WebUtility]::HtmlEncode(($code -join "`n"))
        $encodedLanguage = [System.Net.WebUtility]::HtmlEncode($language)
        $blocks.Add('<pre><code class="language-' + $encodedLanguage + '">' + $encodedCode + '</code></pre>')
    } else {
        $paragraph = New-Object System.Collections.Generic.List[string]
        $paragraph.Add($line)
        while ($index + 1 -lt $bodyLines.Count) {
            $next = $bodyLines[$index + 1]
            if ([string]::IsNullOrWhiteSpace($next) -or (Test-SpecialLine $next)) {
                break
            }
            $index++
            $paragraph.Add($bodyLines[$index].Trim())
        }
        $content = Convert-Inline (($paragraph -join ' ').Trim()) $Platform
        $blocks.Add('<p style="' + $paragraphStyle + '">' + $content + '</p>')
    }
    $index++
}

$normalizedBodyLines = New-Object System.Collections.Generic.List[string]
for ($lineIndex = 0; $lineIndex -lt $bodyLines.Count; $lineIndex++) {
    if ($boundCaptionLines.ContainsKey($lineIndex)) {
        $captionLine = $CanonicalCaptionPrefix + [string]$captionByCaptionLine[$lineIndex]
        if ($Platform -in @('csdn', 'juejin')) {
            $captionLine = '*' + $captionLine + '*'
        }
        $normalizedBodyLines.Add($captionLine)
    } else {
        $normalizedBodyLines.Add($bodyLines[$lineIndex])
    }
}
$normalizedBodyText = ($normalizedBodyLines -join "`n").Trim()

$bodyMarkdownPath = Join-Path $resolvedOutput 'body.md'
$bodyHtmlPath = Join-Path $resolvedOutput 'body.html'
$manifestPath = Join-Path $resolvedOutput 'manifest.json'

Write-Utf8Lf $bodyMarkdownPath ($normalizedBodyText + "`n")
Write-Utf8Lf $bodyHtmlPath (("<section data-distribution-platform=`"$Platform`">`n" + ($blocks -join "`n") + "`n</section>`n"))

$coverPath = $null
if ($meta.Contains('cover') -and -not [string]::IsNullOrWhiteSpace([string]$meta['cover'])) {
    $coverPath = [System.IO.Path]::GetFullPath((Join-Path $sourceDirectory ([string]$meta['cover'])))
    if (-not [System.IO.File]::Exists($coverPath)) {
        throw "Cover image does not exist: $coverPath"
    }
}

$manifestSummary = if ($meta.Contains('summary')) { [string]$meta['summary'] } else { '' }
$manifestSource = if ($meta.Contains('source')) { [string]$meta['source'] } else { '' }
$manifestImages = @()
foreach ($imageRecord in $imageRecords) {
    $manifestImages += $imageRecord
}

$manifest = [ordered]@{
    schema_version = 2
    platform = $Platform
    title = [string]$meta['title']
    summary = $manifestSummary
    source_article = $resolvedInput
    source = $manifestSource
    cover = $coverPath
    body_markdown = $bodyMarkdownPath
    body_html = $bodyHtmlPath
    images = $manifestImages
}
Write-Utf8Lf $manifestPath (($manifest | ConvertTo-Json -Depth 6) + "`n")

[ordered]@{
    ok = $true
    platform = $Platform
    manifest = $manifestPath
    body_markdown = $bodyMarkdownPath
    body_html = $bodyHtmlPath
    image_count = $imageRecords.Count
} | ConvertTo-Json -Compress
