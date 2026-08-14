#requires -version 5.1
<#
.SYNOPSIS
Native Windows mechanical guard for Markdown documents.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = 'Stop'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Commands = @('check', 'readability', 'compare', 'self-test')

function Fail([string]$Message) {
    throw [System.InvalidOperationException]::new($Message)
}

function Write-Json($Value, [bool]$ToError = $false) {
    $json = $Value | ConvertTo-Json -Depth 10 -Compress
    if ($ToError) {
        [Console]::Error.WriteLine($json)
    }
    else {
        [Console]::Out.WriteLine($json)
    }
}

function Parse-Options([string[]]$Items) {
    $values = @{}
    for ($index = 0; $index -lt $Items.Count; $index++) {
        $item = $Items[$index]
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }
        if ($item -notin @('--path', '--source', '--output')) {
            Fail "Unknown argument: $item"
        }
        if ($index + 1 -ge $Items.Count) {
            Fail "Missing value for $item."
        }
        $index++
        $values[$item] = $Items[$index]
    }
    return $values
}

function Get-Option($Options, [string]$Name, [bool]$Required = $false) {
    if ($Options.ContainsKey($Name)) {
        return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$Options[$Name]))
    }
    if ($Required) {
        Fail "Missing required argument: $Name"
    }
    return $null
}

function Get-MarkdownFiles([string]$Path) {
    if ([IO.File]::Exists($Path)) {
        if ([IO.Path]::GetExtension($Path) -ne '.md') {
            Fail "Expected a Markdown file: $Path"
        }
        return @([IO.Path]::GetFullPath($Path))
    }
    if ([IO.Directory]::Exists($Path)) {
        $files = @(Get-ChildItem -LiteralPath $Path -Filter '*.md' -File -Recurse | Sort-Object FullName | ForEach-Object { $_.FullName })
        if ($files.Count -eq 0) {
            Fail "No Markdown files found: $Path"
        }
        return $files
    }
    Fail "Path does not exist: $Path"
}

function New-Issue(
    [string]$File,
    [string]$Type,
    [int]$Line,
    [string]$Message,
    [string]$Target = $null
) {
    return @{
        file = $File
        type = $Type
        line = $Line
        message = $Message
        target = $Target
    }
}

function Resolve-LinkTarget([string]$File, [string]$RawTarget) {
    $target = $RawTarget.Trim()
    if ($target.StartsWith('<') -and $target.EndsWith('>')) {
        $target = $target.Substring(1, $target.Length - 2)
    }
    if (-not $target -or $target.StartsWith('#') -or $target.StartsWith('//')) {
        return $null
    }
    if ($target -notmatch '^[A-Za-z]:[\\/]' -and $target -match '^[A-Za-z][A-Za-z0-9+.-]*:') {
        return $null
    }
    $target = $target.Split('#')[0].Split('?')[0]
    if (-not $target) {
        return $null
    }
    $target = [Uri]::UnescapeDataString($target)
    if ([IO.Path]::IsPathRooted($target)) {
        return [IO.Path]::GetFullPath($target)
    }
    return [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($File)) $target))
}

function Test-MarkdownFile([string]$File) {
    try {
        $content = [IO.File]::ReadAllText($File)
    }
    catch {
        Fail "Cannot read ${File}: $($_.Exception.Message)"
    }
    $issues = @()
    if ($content.Length -eq 0) {
        $issues += New-Issue $File 'empty-file' 1 'Markdown file is empty.'
        return $issues
    }

    $lines = $content -split "`r?`n"
    $fenceCharacter = $null
    $fenceLength = 0
    $fenceLine = 0
    $todoDefinitions = @{}
    $linkPattern = [regex]'!?\[[^\]]*\]\((?<target><[^>]+>|[^)\s]+)'

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $lineNumber = $index + 1
        $line = $lines[$index]
        $fenceMatch = [regex]::Match($line, '^\s*(?<marker>`{3,}|~{3,})')
        if ($fenceMatch.Success) {
            $marker = $fenceMatch.Groups['marker'].Value
            $character = $marker.Substring(0, 1)
            if ($null -eq $fenceCharacter) {
                $fenceCharacter = $character
                $fenceLength = $marker.Length
                $fenceLine = $lineNumber
            }
            elseif ($character -eq $fenceCharacter -and $marker.Length -ge $fenceLength) {
                $fenceCharacter = $null
                $fenceLength = 0
                $fenceLine = 0
            }
            continue
        }
        if ($null -ne $fenceCharacter) {
            continue
        }

        $todoMatch = [regex]::Match(
            $line,
            '^\s*(?:#{1,6}\s+|[-*+]\s+)?TODO-(?<id>\d{2,})(?:\s*[:：]|\s|$)'
        )
        if ($todoMatch.Success) {
            $todoId = 'TODO-' + $todoMatch.Groups['id'].Value
            if ($todoDefinitions.ContainsKey($todoId)) {
                $issues += New-Issue $File 'duplicate-todo' $lineNumber "$todoId is already defined at line $($todoDefinitions[$todoId])." $todoId
            }
            else {
                $todoDefinitions[$todoId] = $lineNumber
            }
        }

        $linkTargets = @($linkPattern.Matches($line) | ForEach-Object { $_.Groups['target'].Value })
        $definition = [regex]::Match($line, '^\s{0,3}\[[^\]]+\]:\s*(?<target><[^>]+>|\S+)')
        if ($definition.Success) {
            $linkTargets += $definition.Groups['target'].Value
        }
        foreach ($rawTarget in $linkTargets) {
            try {
                $resolvedTarget = Resolve-LinkTarget $File $rawTarget
            }
            catch {
                $issues += New-Issue $File 'invalid-link' $lineNumber $_.Exception.Message $rawTarget
                continue
            }
            if ($resolvedTarget -and -not ([IO.File]::Exists($resolvedTarget) -or [IO.Directory]::Exists($resolvedTarget))) {
                $issues += New-Issue $File 'missing-link' $lineNumber "Local link target does not exist: $rawTarget" $rawTarget
            }
        }
    }

    if ($null -ne $fenceCharacter) {
        $issues += New-Issue $File 'unclosed-fence' $fenceLine "Code fence opened at line $fenceLine is not closed."
    }
    return $issues
}

function Test-MarkdownPath([string]$Path) {
    $files = @(Get-MarkdownFiles $Path)
    $issues = @()
    foreach ($file in $files) {
        $issues += @(Test-MarkdownFile $file)
    }
    return @{
        ok = ($issues.Count -eq 0)
        command = 'check'
        path = $Path
        files_checked = $files.Count
        issues = $issues
    }
}

function New-ReadabilityWarning(
    [string]$File,
    [int]$Line,
    [int]$Characters,
    [int]$Separators,
    [string]$Text
) {
    return @{
        file = $File
        line = $Line
        characters = $Characters
        separators = $Separators
        text = $Text
    }
}

function Get-ReadabilityVisibleText([string]$Text) {
    $visible = [regex]::Replace($Text, '!?\[([^\]]*)\]\((?:<[^>]+>|[^)\s]+)\)', '$1')
    $visible = [regex]::Replace($visible, '\[([^\]]+)\]\[[^\]]*\]', '$1')
    $visible = [regex]::Replace($visible, '`([^`]+)`', '$1')
    return ($visible -replace '[*_~]', '')
}

function New-ParagraphReview(
    [string]$File,
    [int]$Line,
    [string[]]$Lines
) {
    if ($Lines.Count -eq 0) {
        return $null
    }
    $text = (($Lines | ForEach-Object { $_.Trim() }) -join ' ').Trim()
    $sentenceCount = [regex]::Matches((Get-ReadabilityVisibleText $text), '[。！？!?]+').Count
    if ($sentenceCount -lt 2) {
        return $null
    }
    return @{
        file = $File
        line = $Line
        sentence_count = $sentenceCount
        text = $text
    }
}

function Test-ReadabilityFile([string]$File) {
    try {
        $content = [IO.File]::ReadAllText($File)
    }
    catch {
        Fail "Cannot read ${File}: $($_.Exception.Message)"
    }

    $warnings = @()
    $paragraphReviews = @()
    $paragraphLines = @()
    $paragraphStart = 0
    $lines = $content -split "`r?`n"
    $fenceCharacter = $null
    $fenceLength = 0
    $inFrontmatter = $false

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        $trimmed = $line.TrimStart()
        if ($index -eq 0 -and $trimmed -eq '---') {
            $inFrontmatter = $true
            continue
        }
        if ($inFrontmatter) {
            if ($trimmed -eq '---') {
                $inFrontmatter = $false
            }
            continue
        }
        $fenceMatch = [regex]::Match($line, '^\s*(?<marker>`{3,}|~{3,})')
        if ($fenceMatch.Success) {
            $review = New-ParagraphReview $File $paragraphStart @($paragraphLines)
            if ($null -ne $review) { $paragraphReviews += $review }
            $paragraphLines = @()
            $paragraphStart = 0
            $marker = $fenceMatch.Groups['marker'].Value
            $character = $marker.Substring(0, 1)
            if ($null -eq $fenceCharacter) {
                $fenceCharacter = $character
                $fenceLength = $marker.Length
            }
            elseif ($character -eq $fenceCharacter -and $marker.Length -ge $fenceLength) {
                $fenceCharacter = $null
                $fenceLength = 0
            }
            continue
        }
        if ($null -ne $fenceCharacter -or -not $trimmed -or $trimmed.StartsWith('#') -or $trimmed.StartsWith('|')) {
            $review = New-ParagraphReview $File $paragraphStart @($paragraphLines)
            if ($null -ne $review) { $paragraphReviews += $review }
            $paragraphLines = @()
            $paragraphStart = 0
            continue
        }

        $visible = Get-ReadabilityVisibleText $line
        $visible = [regex]::Replace($visible, '^\s*(?:[-*+]|\d+[.)])\s+', '')

        foreach ($match in [regex]::Matches($visible, '[^。！？!?]+[。！？!?]?')) {
            $sentence = $match.Value.Trim()
            if (-not $sentence) {
                continue
            }
            $characters = ($sentence -replace '\s+', '').Length
            $separators = [regex]::Matches($sentence, '[，；：]').Count
            if ($characters -ge 55 -or $separators -ge 3) {
                $warnings += New-ReadabilityWarning $File ($index + 1) $characters $separators $sentence
            }
        }

        if ($trimmed.StartsWith('>') -or $trimmed -match '^(?:[-*+]|\d+[.)])\s+') {
            $review = New-ParagraphReview $File $paragraphStart @($paragraphLines)
            if ($null -ne $review) { $paragraphReviews += $review }
            $paragraphLines = @()
            $paragraphStart = 0
            continue
        }
        if ($paragraphLines.Count -eq 0) {
            $paragraphStart = $index + 1
        }
        $paragraphLines += $line
    }
    $review = New-ParagraphReview $File $paragraphStart @($paragraphLines)
    if ($null -ne $review) { $paragraphReviews += $review }
    return @{ warnings = $warnings; paragraph_reviews = $paragraphReviews }
}

function Test-ReadabilityPath([string]$Path) {
    $files = @(Get-MarkdownFiles $Path)
    $warnings = @()
    $paragraphReviews = @()
    foreach ($file in $files) {
        $fileResult = Test-ReadabilityFile $file
        $warnings += @($fileResult.warnings)
        $paragraphReviews += @($fileResult.paragraph_reviews)
    }
    return @{
        ok = $true
        command = 'readability'
        path = $Path
        files_checked = $files.Count
        review_required = ($warnings.Count -gt 0 -or $paragraphReviews.Count -gt 0)
        warnings = $warnings
        paragraph_reviews = $paragraphReviews
    }
}

function Add-Literal($Map, [string]$Kind, [string]$Value) {
    $normalized = $Value.Trim()
    if (-not $normalized) {
        return
    }
    $key = $Kind + [char]31 + $normalized
    if (-not $Map.ContainsKey($key)) {
        $Map[$key] = @{ kind = $Kind; value = $normalized }
    }
}

function Get-Literals([string]$Path) {
    if (-not [IO.File]::Exists($Path)) {
        Fail "File does not exist: $Path"
    }
    try {
        $content = [IO.File]::ReadAllText($Path)
    }
    catch {
        Fail "Cannot read ${Path}: $($_.Exception.Message)"
    }
    $literals = @{}

    foreach ($match in [regex]::Matches($content, '\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}\b')) {
        Add-Literal $literals 'uuid' $match.Value.ToLowerInvariant()
    }
    foreach ($match in [regex]::Matches($content, '(?<!`)`([^`\r\n]+)`(?!`)')) {
        Add-Literal $literals 'code' $match.Groups[1].Value
    }
    $numberPattern = '\d+(?:\.\d+)?(?:\s*[~～—-]\s*\d+(?:\.\d+)?)?(?:\s*(?:%|％|ms|s|min|h|KB|MB|GB|次|个|天|周|月|年))?'
    foreach ($match in [regex]::Matches($content, $numberPattern)) {
        Add-Literal $literals 'number' (($match.Value -replace '\s+', ' ').Trim())
    }
    $linkPattern = [regex]'!?\[[^\]]*\]\((?<target><[^>]+>|[^)\s]+)'
    foreach ($match in $linkPattern.Matches($content)) {
        $target = $match.Groups['target'].Value.Trim('<', '>')
        if ($target -and -not $target.StartsWith('#') -and $target -notmatch '^[A-Za-z][A-Za-z0-9+.-]*:') {
            Add-Literal $literals 'link' $target
        }
    }
    $definitionPattern = [regex]'(?m)^\s{0,3}\[[^\]]+\]:\s*(?<target><[^>]+>|\S+)'
    foreach ($match in $definitionPattern.Matches($content)) {
        $target = $match.Groups['target'].Value.Trim('<', '>')
        if ($target -and -not $target.StartsWith('#') -and $target -notmatch '^[A-Za-z][A-Za-z0-9+.-]*:') {
            Add-Literal $literals 'link' $target
        }
    }
    return $literals
}

function Compare-Literals([string]$Source, [string]$Output) {
    $mechanical = Test-MarkdownPath $Output
    $sourceLiterals = Get-Literals $Source
    $outputLiterals = Get-Literals $Output
    $sourceOnly = @(
        $sourceLiterals.Keys |
            Where-Object { -not $outputLiterals.ContainsKey($_) } |
            ForEach-Object { $sourceLiterals[$_] } |
            Sort-Object kind, value
    )
    $outputOnly = @(
        $outputLiterals.Keys |
            Where-Object { -not $sourceLiterals.ContainsKey($_) } |
            ForEach-Object { $outputLiterals[$_] } |
            Sort-Object kind, value
    )
    return @{
        ok = $mechanical.ok
        command = 'compare'
        source = $Source
        output = $Output
        review_required = ($sourceOnly.Count -gt 0 -or $outputOnly.Count -gt 0)
        source_only = $sourceOnly
        output_only = $outputOnly
        mechanical_issues = $mechanical.issues
    }
}

function Write-TestFile([string]$Path, [string]$Content) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Content.Replace("`r`n", "`n"), $script:Utf8NoBom)
}

function Invoke-SelfTest {
    $base = Join-Path ([IO.Path]::GetTempPath()) ('lightning-护栏 测试-' + [Guid]::NewGuid().ToString('N'))
    $checks = @()
    try {
        [IO.Directory]::CreateDirectory($base) | Out-Null
        Write-TestFile (Join-Path $base 'target file.md') "# Target`n"
        $valid = Join-Path $base 'valid.md'
        Write-TestFile $valid (@(
            '# Valid',
            '',
            '[目标](<target file.md>) [网页](https://example.com) [锚点](#part)',
            '[引用][doc]',
            '[doc]: <target file.md>',
            '',
            'TODO-01：确认范围。',
            '',
            '```text',
            'ok',
            '```'
        ) -join "`n")
        $validResult = Test-MarkdownPath $valid
        $checks += @{ name = 'valid file'; passed = $validResult.ok }

        $broken = Join-Path $base 'broken.md'
        Write-TestFile $broken "[missing](missing.md)`n"
        $brokenResult = Test-MarkdownPath $broken
        $checks += @{ name = 'missing local link'; passed = (-not $brokenResult.ok -and $brokenResult.issues[0].type -eq 'missing-link') }

        $fence = Join-Path $base 'fence.md'
        Write-TestFile $fence (@('```text', 'unclosed') -join "`n")
        $fenceResult = Test-MarkdownPath $fence
        $checks += @{ name = 'unclosed fence'; passed = (-not $fenceResult.ok -and $fenceResult.issues[0].type -eq 'unclosed-fence') }

        $todo = Join-Path $base 'todo.md'
        Write-TestFile $todo "TODO-02：first`n`n## TODO-02：second`n"
        $todoResult = Test-MarkdownPath $todo
        $checks += @{ name = 'duplicate todo'; passed = (-not $todoResult.ok -and $todoResult.issues[0].type -eq 'duplicate-todo') }

        $source = Join-Path $base 'source.md'
        $output = Join-Path $base 'output.md'
        Write-TestFile $source '版本 `v1`，范围 10～20 个，ID 123e4567-e89b-12d3-a456-426614174000。'
        Write-TestFile $output '版本 `v2`，范围 10 个。'
        $compare = Compare-Literals $source $output
        $checks += @{ name = 'literal comparison'; passed = ($compare.ok -and $compare.review_required -and $compare.source_only.Count -gt 0 -and $compare.output_only.Count -gt 0) }

        $readability = Join-Path $base 'readability.md'
        Write-TestFile $readability (@(
            '---',
            'description: "This intentionally long frontmatter value must not become a readability warning candidate."',
            '---',
            '',
            '# 标题第一句。标题第二句。',
            '',
            '普通单行第一句。普通单行第二句。',
            '',
            '跨行第一句。',
            '跨行第二句。',
            '',
            '单句段落。',
            '',
            '- 列表第一句。列表第二句。',
            '',
            '| 表格第一句。表格第二句。 |',
            '',
            '> 引用第一句。引用第二句。',
            '',
            '```text',
            '代码第一句。代码第二句。',
            '```',
            '',
            '对象满足条件时，执行动作一，执行动作二；出现异常时，执行联动结果。',
            ''
        ) -join "`n")
        $readabilityResult = Test-ReadabilityPath $readability
        $checks += @{ name = 'readability warnings'; passed = ($readabilityResult.ok -and $readabilityResult.review_required -and $readabilityResult.warnings.Count -eq 1 -and $readabilityResult.warnings[0].separators -eq 4) }

        $paragraphReviews = @($readabilityResult.paragraph_reviews)
        $paragraphOnly = Join-Path $base 'paragraph-only.md'
        Write-TestFile $paragraphOnly '第一项规则已经确认。第二项规则等待单独维护。'
        $paragraphOnlyResult = Test-ReadabilityPath $paragraphOnly
        $paragraphReviewPassed = (
            $paragraphReviews.Count -eq 2 -and
            $paragraphReviews[0].line -eq 7 -and
            $paragraphReviews[0].sentence_count -eq 2 -and
            $paragraphReviews[0].text -eq '普通单行第一句。普通单行第二句。' -and
            $paragraphReviews[1].line -eq 9 -and
            $paragraphReviews[1].sentence_count -eq 2 -and
            $paragraphReviews[1].text -eq '跨行第一句。 跨行第二句。' -and
            $paragraphOnlyResult.review_required -and
            $paragraphOnlyResult.warnings.Count -eq 0 -and
            $paragraphOnlyResult.paragraph_reviews.Count -eq 1
        )
        $checks += @{ name = 'paragraph review candidates'; passed = $paragraphReviewPassed }

        $directoryResult = Test-MarkdownPath $base
        $checks += @{ name = 'unicode directory recursion'; passed = ($directoryResult.files_checked -eq 9) }

        $failed = @($checks | Where-Object { -not $_.passed })
        if ($failed.Count -gt 0) {
            Fail ('Self-test failed: ' + (($failed | ForEach-Object { $_.name }) -join ', '))
        }
        return @{
            ok = $true
            command = 'self-test'
            adapter = 'powershell'
            runtime = $PSVersionTable.PSVersion.ToString()
            checks_passed = $checks.Count
            checks = $checks
        }
    }
    finally {
        if ([IO.Directory]::Exists($base)) {
            [IO.Directory]::Delete($base, $true)
        }
    }
}

try {
    if (-not $Command -or $Command -notin $script:Commands) {
        Fail ('Command must be one of: ' + ($script:Commands -join ', ') + '.')
    }
    $options = Parse-Options @($RemainingArgs)
    switch ($Command) {
        'check' {
            $result = Test-MarkdownPath (Get-Option $options '--path' $true)
            Write-Json $result
            if ($result.ok) { exit 0 } else { exit 1 }
        }
        'readability' {
            $result = Test-ReadabilityPath (Get-Option $options '--path' $true)
            Write-Json $result
            exit 0
        }
        'compare' {
            $result = Compare-Literals (Get-Option $options '--source' $true) (Get-Option $options '--output' $true)
            Write-Json $result
            if ($result.ok) { exit 0 } else { exit 1 }
        }
        'self-test' {
            if ($options.Count -gt 0) {
                Fail 'self-test does not accept arguments.'
            }
            Write-Json (Invoke-SelfTest)
            exit 0
        }
    }
}
catch {
    Write-Json @{ ok = $false; command = $Command; error = $_.Exception.Message } $true
    exit 2
}
