#requires -version 5.1
<#
.SYNOPSIS
Native Windows prose-shape checker for the writing-style skill.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8

$patterns = @(
    @{ Code = 'S1'; Label = '宏大通用开头'; Reason = '开头没有直接进入当前问题、材料或判断'; Regex = '(?:在当今|随着)[^。！？\r\n]{0,36}(?:时代|社会|技术|发展|背景|浪潮)'; Limit = 240 },
    @{ Code = 'S2'; Label = '预告代替内容'; Reason = '检查是否可以直接进入正文'; Regex = '(?:接下来|下面)(?:我们)?(?:将|会|来)?[^。！？\r\n]{0,28}(?:分析|探讨|介绍|展开|说明|看看)'; Limit = $null },
    @{ Code = 'L1'; Label = '空泛转场'; Reason = '检查该表达是否承担了真实逻辑关系'; Regex = '(?:^|[。！？!?]\s*)(?:值得注意的是|需要强调的是|需要指出的是|从某种意义上说)'; Limit = $null },
    @{ Code = 'L2'; Label = '假装深入'; Reason = '检查后文是否增加了新的事实或推理'; Regex = '(?:^|[。！？!?]\s*)(?:本质上|真正的问题(?:是|在于)|更深层次(?:看|来看))'; Limit = $null },
    @{ Code = 'L9'; Label = '否定揭晓句'; Reason = '该句式不是禁用项，只检查是否反复制造假冲突'; Regex = '(?:不是[^。！？\r\n]{0,90}而是|并非[^。！？\r\n]{0,90}而是|不在于[^。！？\r\n]{0,90}而在于|不只是?[^。！？\r\n]{0,90}(?:更是|还是))'; Limit = $null },
    @{ Code = 'L10'; Label = '营销或抽象词'; Reason = '单个词不能证明问题，检查是否缺少主体、动作和后果'; Regex = '(?:颠覆性|革命性|前所未有|赋能|抓手|闭环|底层逻辑|顶层设计|全链路|组合拳)'; Limit = $null }
)

$repeatedOpeners = @(
    '其实', '不过', '当然', '所以', '但是', '与此同时',
    '值得注意的是', '更重要的是', '问题是'
)

function Get-HanCount([string]$Value) {
    return [regex]::Matches($Value, '[\u4e00-\u9fff]').Count
}

function Get-LineNumber([string]$Text, [int]$Position) {
    if ($Position -le 0) { return 1 }
    return ([regex]::Matches($Text.Substring(0, $Position), "`n").Count + 1)
}

function Get-Excerpt([string]$Value, [int]$Width = 68) {
    $clean = ([regex]::Replace($Value, '\s+', ' ')).Trim(' ', '。', '！', '？', '!', '?', '，', ',')
    if ($clean.Length -le $Width) { return $clean }
    return $clean.Substring(0, $Width - 1) + '…'
}

function Mask-NonProse([string]$Text) {
    $masked = $Text
    $masker = [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $builder = New-Object System.Text.StringBuilder
        foreach ($char in $match.Value.ToCharArray()) {
            if ($char -eq "`n") { [void]$builder.Append("`n") }
            else { [void]$builder.Append(' ') }
        }
        return $builder.ToString()
    }
    $maskPatterns = @(
        '(?s)\A---\s*\r?\n.*?\r?\n---\s*(?:\r?\n|\z)',
        '(?s)```.*?```',
        '(?s)~~~.*?~~~',
        '`[^`\r\n]*`',
        '!\[[^\r\n]*?\]\([^\r\n)]*\)',
        '\]\([^\r\n)]*\)',
        'https?://[^\s)>]+',
        '<[^>\r\n]+>',
        '(?m)^\s*>.*$',
        '(?m)^\s*\|.*\|\s*$'
    )
    foreach ($maskPattern in $maskPatterns) {
        $masked = [regex]::Replace($masked, $maskPattern, $masker)
    }
    return $masked
}

function New-Finding(
    [string]$Source,
    [int]$Position,
    [string]$Code,
    [string]$Label,
    [string]$Reason,
    [string]$Value
) {
    return [pscustomobject]@{
        Line = Get-LineNumber $Source $Position
        Code = $Code
        Label = $Label
        Reason = $Reason
        Excerpt = Get-Excerpt $Value
    }
}

function Get-Paragraphs([string]$Prose) {
    $paragraphs = @()
    $cursor = 0
    foreach ($block in [regex]::Split($Prose, '\r?\n\s*\r?\n')) {
        $position = $Prose.IndexOf($block, $cursor, [System.StringComparison]::Ordinal)
        if ($position -lt 0) { continue }
        $cursor = $position + $block.Length
        $clean = ([regex]::Replace($block, '[>*_#]', '')).Trim()
        if ([string]::IsNullOrWhiteSpace($clean) -or $clean -match '^(?:[-+*]|\d+[.、])\s') { continue }
        $han = Get-HanCount $clean
        if ($han -lt 2) { continue }
        $sentences = [Math]::Max(1, [regex]::Matches($clean, '[。！？!?]').Count)
        $paragraphs += [pscustomobject]@{
            Position = $position
            Text = $clean
            Han = $han
            Sentences = $sentences
        }
    }
    return @($paragraphs)
}

function Invoke-Analysis([string]$Source) {
    $prose = Mask-NonProse $Source
    $totalHan = Get-HanCount $prose
    $paragraphs = @(Get-Paragraphs $prose)
    $findings = @()

    foreach ($pattern in $patterns) {
        foreach ($match in [regex]::Matches($prose, $pattern.Regex, [System.Text.RegularExpressions.RegexOptions]::Multiline)) {
            if ($null -ne $pattern.Limit -and $match.Index -gt $pattern.Limit) { continue }
            $findings += New-Finding $Source $match.Index $pattern.Code $pattern.Label $pattern.Reason $match.Value
        }
    }

    $seenSentences = @{}
    $reportedSentences = @{}
    foreach ($match in [regex]::Matches($prose, '[^。！？!?\r\n]+[。！？!?]')) {
        $value = ([regex]::Replace($match.Value, '[\s，,；;：:]', '')).Trim('。', '！', '？', '!', '?')
        $han = Get-HanCount $value
        if ($han -lt 14 -or $han -gt 100) { continue }
        if (-not $seenSentences.ContainsKey($value)) {
            $seenSentences[$value] = $match
            continue
        }
        if ($reportedSentences.ContainsKey($value)) { continue }
        $first = $seenSentences[$value]
        $reportedSentences[$value] = $true
        $reason = "与第 $(Get-LineNumber $Source $first.Index) 行内容相同，检查是否需要保留两次"
        $findings += New-Finding $Source $match.Index 'L6' '重复句' $reason $first.Value
    }

    $shortStreak = @()
    foreach ($paragraph in $paragraphs) {
        if ($paragraph.Han -le 24 -and $paragraph.Sentences -le 1) {
            $shortStreak += $paragraph
            if ($shortStreak.Count -eq 4) {
                $value = ($shortStreak | ForEach-Object { $_.Text }) -join ' / '
                $findings += New-Finding $Source $shortStreak[0].Position 'R5' '连续短段' '连续四个短促单句段，检查是否在排队输出结论' $value
            }
        }
        else { $shortStreak = @() }
    }

    if ($paragraphs.Count -ge 10) {
        $oneSentence = @($paragraphs | Where-Object { $_.Sentences -le 1 }).Count
        $ratio = $oneSentence / $paragraphs.Count
        if ($ratio -ge 0.75) {
            $reason = "可识别段落中有 $($ratio.ToString('P0')) 只有一句；移动端排版合理时保留"
            $findings += New-Finding $Source $paragraphs[0].Position 'R2' '段落形状单一' $reason $paragraphs[0].Text
        }
    }

    if ($paragraphs.Count -ge 8) {
        $lengths = @($paragraphs | ForEach-Object { $_.Han })
        $average = ($lengths | Measure-Object -Average).Average
        $minimum = ($lengths | Measure-Object -Minimum).Minimum
        $maximum = ($lengths | Measure-Object -Maximum).Maximum
        if ($average -ge 20 -and (($maximum - $minimum) / $average) -le 0.45) {
            $reason = '多个段落长度接近，检查是否按同一模具展开'
            $value = "$($paragraphs.Count) 段，汉字数范围 $minimum-$maximum"
            $findings += New-Finding $Source $paragraphs[0].Position 'R2' '段长过度一致' $reason $value
        }
    }

    $openerCounts = @{}
    $openerPositions = @{}
    foreach ($paragraph in $paragraphs) {
        foreach ($opener in $repeatedOpeners) {
            if (-not $paragraph.Text.StartsWith($opener, [System.StringComparison]::Ordinal)) { continue }
            if (-not $openerCounts.ContainsKey($opener)) {
                $openerCounts[$opener] = 0
                $openerPositions[$opener] = $paragraph.Position
            }
            $openerCounts[$opener]++
            break
        }
    }
    foreach ($opener in $openerCounts.Keys) {
        if ($openerCounts[$opener] -lt 3) { continue }
        $reason = "「${opener}」作为段首出现 $($openerCounts[$opener]) 次，检查是否形成固定路标"
        $findings += New-Finding $Source $openerPositions[$opener] 'R6' '重复段首' $reason $opener
    }

    return [pscustomobject]@{
        TotalHan = $totalHan
        Paragraphs = $paragraphs.Count
        Findings = @($findings | Sort-Object Line, Code, Excerpt)
    }
}

function Write-Result($Result) {
    Write-Output "可见汉字 $($Result.TotalHan)，可识别段落 $($Result.Paragraphs)"
    if ($Result.Findings.Count -gt 0) {
        Write-Output "发现 $($Result.Findings.Count) 个候选问题，全部需要结合声纹和语境人工判断："
        foreach ($finding in $Result.Findings) {
            Write-Output "- 第 $($finding.Line) 行 [$($finding.Code) $($finding.Label)] $($finding.Reason)；「$($finding.Excerpt)」"
        }
    }
    else { Write-Output '未发现本检查器覆盖的文字形状。' }
    Write-Output '检查器不判断材料充足度、语义推进、作者身份或风格一致性，也不自动修改正文。'
}

function Invoke-SelfTest {
    $sample = @'
在当今时代，内容创作正在发生变化。

接下来我们将深入分析这个问题。

值得注意的是，这不是工具变化，而是认知革命。

一句话。

很重要。

必须重视。

值得思考。
'@
    $codes = @(Invoke-Analysis $sample).Findings.Code
    foreach ($expected in @('S1', 'S2', 'L1', 'L9', 'R5')) {
        if ($codes -notcontains $expected) { throw "Self-test missing $expected." }
    }
    $masked = @'
正文直接说明已经确认的事实。

> 在当今时代，值得注意的是。

```text
接下来我们将深入分析。
```
'@
    if (@(Invoke-Analysis $masked).Findings.Count -ne 0) { throw 'Self-test masking failed.' }
    Write-Output 'self-test passed'
}

try {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Missing Markdown or text path.' }
    if ($Path -eq 'self-test') { Invoke-SelfTest; exit 0 }
    if ($Path -eq '-') { $source = [Console]::In.ReadToEnd() }
    else { $source = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path), [System.Text.Encoding]::UTF8) }
    $result = Invoke-Analysis $source
    if ($result.TotalHan -eq 0) { throw '没有检测到可审查的中文正文。' }
    Write-Result $result
    exit 0
}
catch {
    [Console]::Error.WriteLine("无法检查稿件：$($_.Exception.Message)")
    exit 2
}
