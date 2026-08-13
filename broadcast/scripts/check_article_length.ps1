#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('inspect', 'check', 'self-test')]
    [string]$Command,
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8

function ConvertFrom-CodePoints([int[]]$Points) {
    $builder = New-Object System.Text.StringBuilder
    foreach ($point in $Points) { [void]$builder.Append([char]$point) }
    return $builder.ToString()
}

$noticePrefix = (ConvertFrom-CodePoints @(0x5168, 0x6587, 0x7EA6)) + ' '
$noticeMiddle = ' ' + (ConvertFrom-CodePoints @(0x5B57, 0xFF0C, 0x9884, 0x8BA1, 0x9605, 0x8BFB)) + ' '
$noticeSuffix = ' ' + (ConvertFrom-CodePoints @(0x5206, 0x949F))

function Get-CodePointCount([string]$Value) {
    $count = 0
    for ($i = 0; $i -lt $Value.Length; $i++) {
        if ([char]::IsHighSurrogate($Value[$i]) -and $i + 1 -lt $Value.Length -and [char]::IsLowSurrogate($Value[$i + 1])) { $i++ }
        $count++
    }
    return $count
}

function ConvertTo-VisibleText([string]$Line) {
    $value = $Line
    $value = [regex]::Replace($value, '!\[[^\]]*\]\([^)]*\)', '')
    $value = [regex]::Replace($value, '(?<!!)\[([^\]]+)\]\([^)]*\)', '$1')
    $value = [regex]::Replace($value, '<[^>]+>', '')
    $value = [regex]::Replace($value, '`[^`]*`', '')
    $value = [regex]::Replace($value, '^\s{0,3}#{1,6}\s+', '')
    $value = [regex]::Replace($value, '^\s*(?:[-+*]|[0-9]+[.)])\s+', '')
    $value = [regex]::Replace($value, '^\s*>\s?', '')
    $value = [regex]::Replace($value, '[*_~]', '')
    return [regex]::Replace($value, '\s', '')
}

function Get-ArticleStats([string]$Path) {
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if ((Get-Item -LiteralPath $resolved).PSIsContainer) { throw 'path must be a Markdown file' }
    $lines = [System.IO.File]::ReadAllLines($resolved, $utf8)
    $frontMatter = $lines.Count -gt 0 -and $lines[0].TrimStart([char]0xFEFF) -eq '---'
    $frontMatterClosed = -not $frontMatter
    $inFence = $false
    $fenceMarker = ''
    $codeLines = 0
    $visibleChars = 0
    $noticeLines = New-Object System.Collections.ArrayList
    $sections = New-Object System.Collections.ArrayList
    $currentSection = $null

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if (-not $frontMatterClosed) {
            if ($i -gt 0 -and $line -eq '---') { $frontMatterClosed = $true }
            continue
        }
        if ($line -match '^\s*(```|~~~)') {
            $marker = $Matches[1]
            if (-not $inFence) { $inFence = $true; $fenceMarker = $marker }
            elseif ($marker -eq $fenceMarker) { $inFence = $false; $fenceMarker = '' }
            continue
        }
        if ($inFence) {
            if (-not [string]::IsNullOrWhiteSpace($line)) { $codeLines++ }
            continue
        }
        if ($line.TrimStart().StartsWith($noticePrefix)) {
            [void]$noticeLines.Add($line.Trim())
            continue
        }
        if ($line -match '^\s*##(?!#)\s+(.+?)\s*$') {
            $currentSection = [ordered]@{ title = $Matches[1]; visible_chars = 0 }
            [void]$sections.Add($currentSection)
        }
        $visible = ConvertTo-VisibleText $line
        $lineCount = Get-CodePointCount $visible
        $visibleChars += $lineCount
        if ($null -ne $currentSection) { $currentSection.visible_chars += $lineCount }
    }

    $displayChars = [int]([math]::Floor(($visibleChars + 50) / 100) * 100)
    $minutes = [int][math]::Ceiling($visibleChars / 500.0)
    $requiresNotice = $visibleChars -gt 3000
    $expectedNotice = $noticePrefix + $displayChars + $noticeMiddle + $minutes + $noticeSuffix
    $noticeFound = $noticeLines.Count -gt 0
    $noticeMatches = if ($requiresNotice) { $noticeLines.Count -eq 1 -and $noticeLines[0] -eq $expectedNotice } else { $noticeLines.Count -eq 0 }

    return [ordered]@{
        path = $resolved
        visible_chars = $visibleChars
        display_chars = $displayChars
        estimated_minutes = $minutes
        code_lines = $codeLines
        section_count = $sections.Count
        sections = @($sections)
        requires_notice = $requiresNotice
        notice_found = $noticeFound
        notice_matches = $noticeMatches
        expected_notice = if ($requiresNotice) { $expectedNotice } else { $null }
    }
}

function Get-ContractErrors($Stats) {
    $errors = New-Object System.Collections.ArrayList
    if ($Stats.requires_notice -and -not $Stats.notice_found) { [void]$errors.Add('long article notice is missing') }
    elseif (-not $Stats.requires_notice -and $Stats.notice_found) { [void]$errors.Add('short article must not contain a long article notice') }
    elseif (-not $Stats.notice_matches) { [void]$errors.Add('long article notice does not match computed values') }
    return @($errors)
}

function Invoke-SelfTest {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('broadcast-length-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $root)
    try {
        $cases = New-Object System.Collections.ArrayList
        $front = "---`nplatform: zhihu`ntitle: test`n---`n`n"
        $tick = [char]0x60
        $emoji = ConvertFrom-CodePoints @(0xD83D, 0xDE00)
        $mixed = $front + "## Part`n" + (ConvertFrom-CodePoints @(0x4E2D, 0x6587)) + ' [link](https://example.com) ![alt](x.png) <b>x</b> ' + $tick + 'code' + $tick + ' ' + $emoji + "`n" + ($tick.ToString() * 3) + "text`nignored`n" + ($tick.ToString() * 3)
        $samples = [ordered]@{
            short = $front + ('a' * 2999)
            exact = $front + ('a' * 3000)
            missing = $front + ('a' * 3060)
            wrong_chars = $front + $noticePrefix + '3000' + $noticeMiddle + '7' + $noticeSuffix + "`n" + ('a' * 3060)
            wrong_time = $front + $noticePrefix + '3100' + $noticeMiddle + '1' + $noticeSuffix + "`n" + ('a' * 3060)
            correct = $front + $noticePrefix + '3100' + $noticeMiddle + '7' + $noticeSuffix + "`n" + ('a' * 3060)
            mixed = $mixed
        }
        foreach ($name in $samples.Keys) {
            $file = Join-Path $root ($name + '.md')
            [System.IO.File]::WriteAllText($file, $samples[$name], $utf8)
            $stats = Get-ArticleStats $file
            $errors = Get-ContractErrors $stats
            $expectedPass = @('short', 'exact', 'correct', 'mixed') -contains $name
            $passed = (($errors.Count -eq 0) -eq $expectedPass)
            if ($name -eq 'mixed') { $passed = $passed -and $stats.visible_chars -eq 12 -and $stats.code_lines -eq 1 -and $stats.section_count -eq 1 }
            [void]$cases.Add([ordered]@{ name = $name; passed = $passed })
        }
        $ok = (@($cases | Where-Object { -not $_.passed }).Count -eq 0)
        [ordered]@{ ok = $ok; cases = @($cases) } | ConvertTo-Json -Depth 6 -Compress
        if (-not $ok) { exit 1 }
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

try {
    if ($Command -eq 'self-test') { Invoke-SelfTest; exit 0 }
    if ($Arguments.Count -ne 2 -or $Arguments[0] -ne '--path') { throw 'usage: inspect|check --path <platform-markdown>' }
    $stats = Get-ArticleStats $Arguments[1]
    $errors = Get-ContractErrors $stats
    $result = [ordered]@{ ok = ($errors.Count -eq 0); errors = @($errors) }
    foreach ($key in $stats.Keys) { $result[$key] = $stats[$key] }
    $result | ConvertTo-Json -Depth 8 -Compress
    if ($Command -eq 'check' -and $errors.Count -gt 0) { exit 1 }
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 2
}
