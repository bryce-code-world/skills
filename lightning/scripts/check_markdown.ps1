#requires -version 5.1

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    throw [System.InvalidOperationException]::new($Message)
}

function Write-Json($Value, [bool]$ToError = $false) {
    $json = $Value | ConvertTo-Json -Depth 8 -Compress
    if ($ToError) {
        [Console]::Error.WriteLine($json)
    }
    else {
        [Console]::Out.WriteLine($json)
    }
}

function Parse-PathOption([string[]]$Items) {
    $path = $null
    for ($index = 0; $index -lt $Items.Count; $index++) {
        $item = $Items[$index]
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }
        if ($item -ne '--path') {
            Fail "Unknown argument: $item"
        }
        if ($index + 1 -ge $Items.Count) {
            Fail 'Missing value for --path.'
        }
        $index++
        $path = $Items[$index]
    }
    if (-not $path) {
        Fail 'Missing required argument: --path'
    }
    return [IO.Path]::GetFullPath($path)
}

function Get-MarkdownFiles([string]$Path) {
    if ([IO.File]::Exists($Path)) {
        if ([IO.Path]::GetExtension($Path) -ne '.md') {
            Fail "Expected a Markdown file: $Path"
        }
        return @([IO.Path]::GetFullPath($Path))
    }
    if ([IO.Directory]::Exists($Path)) {
        $files = @(Get-ChildItem -LiteralPath $Path -Filter '*.md' -File -Recurse |
            Sort-Object FullName |
            ForEach-Object { $_.FullName })
        if ($files.Count -eq 0) {
            Fail "No Markdown files found: $Path"
        }
        return $files
    }
    Fail "Path does not exist: $Path"
}

function Is-RelativeLocalTarget([string]$Target) {
    if (-not $Target -or $Target.StartsWith('#') -or $Target.StartsWith('/') -or $Target.StartsWith('\')) {
        return $false
    }
    if ($Target.StartsWith('//') -or $Target -match '^[A-Za-z][A-Za-z0-9+.-]*:') {
        return $false
    }
    return $true
}

function Normalize-LinkTarget([string]$Target) {
    $value = $Target.Trim()
    if ($value.StartsWith('<') -and $value.EndsWith('>')) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    $value = ($value -split '[?#]', 2)[0]
    return [Uri]::UnescapeDataString($value)
}

function New-Finding([string]$File, [int]$Line, [string]$Rule, [string]$Message, [string]$Target = $null) {
    return @{
        file = $File
        line = $Line
        rule = $Rule
        target = $Target
        message = $Message
    }
}

function Test-MarkdownFile([string]$File) {
    try {
        $content = [IO.File]::ReadAllText($File, [Text.Encoding]::UTF8)
    }
    catch {
        return @(New-Finding $File 0 'read-error' $_.Exception.Message)
    }

    $findings = @()
    $fenceCharacter = $null
    $fenceLength = 0
    $fenceLine = 0
    $lines = $content -split "`r?`n"

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $lineNumber = $index + 1
        $line = $lines[$index]
        $fenceMatch = [regex]::Match($line, '^[ ]{0,3}(`{3,}|~{3,})')
        if ($fenceMatch.Success) {
            $marker = $fenceMatch.Groups[1].Value
            $character = $marker.Substring(0, 1)
            if (-not $fenceCharacter) {
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
        if ($fenceCharacter) {
            continue
        }

        $targets = @()
        foreach ($match in [regex]::Matches($line, '!?\[[^\]]*\]\((?<target><[^>]+>|[^)\s]+)(?:\s+["''][^"'']*["''])?\)')) {
            $targets += $match.Groups['target'].Value
        }
        $definition = [regex]::Match($line, '^[ ]{0,3}\[[^\]]+\]:\s*(?<target><[^>]+>|\S+)')
        if ($definition.Success) {
            $targets += $definition.Groups['target'].Value
        }

        foreach ($rawTarget in $targets) {
            $target = Normalize-LinkTarget $rawTarget
            if (-not (Is-RelativeLocalTarget $target)) {
                continue
            }
            $resolved = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($File)) $target))
            if (-not [IO.File]::Exists($resolved) -and -not [IO.Directory]::Exists($resolved)) {
                $findings += New-Finding $File $lineNumber 'missing-local-target' "Local target does not exist: $target" $target
            }
        }
    }

    if ($fenceCharacter) {
        $findings += New-Finding $File $fenceLine 'unclosed-fence' 'Code fence is not closed.'
    }
    return $findings
}

function Test-MarkdownPath([string]$Path) {
    $files = @(Get-MarkdownFiles $Path)
    $findings = @()
    foreach ($file in $files) {
        $findings += @(Test-MarkdownFile $file)
    }
    return @{
        ok = ($findings.Count -eq 0)
        command = 'check'
        path = $Path
        files_checked = $files.Count
        findings = $findings
    }
}

function Invoke-SelfTest {
    $unicodeName = ([char]0x4E2D).ToString() + ([char]0x6587).ToString()
    $base = Join-Path ([IO.Path]::GetTempPath()) ('lightning-markdown-' + $unicodeName + ' test-' + [Guid]::NewGuid().ToString('N'))
    $checks = @()
    try {
        [IO.Directory]::CreateDirectory($base) | Out-Null
        $fence = ([char]96).ToString() + ([char]96).ToString() + ([char]96).ToString()
        $target = Join-Path $base ($unicodeName + ' file.md')
        [IO.File]::WriteAllText($target, "# Target`n", [Text.UTF8Encoding]::new($false))

        $valid = Join-Path $base 'valid.md'
        [IO.File]::WriteAllText($valid, "# Valid`n`n[local](<$unicodeName file.md>)`n`n${fence}text`nok`n$fence`n", [Text.UTF8Encoding]::new($false))
        $result = Test-MarkdownPath $valid
        $checks += @{ name = 'valid document'; passed = $result.ok }

        $result = Test-MarkdownPath $base
        $checks += @{ name = 'directory unicode and spaces'; passed = ($result.ok -and $result.files_checked -eq 2) }

        $broken = Join-Path $base 'broken.md'
        [IO.File]::WriteAllText($broken, "# Broken`n`n[missing](./missing.md)`n", [Text.UTF8Encoding]::new($false))
        $result = Test-MarkdownPath $broken
        $checks += @{ name = 'missing target'; passed = (-not $result.ok -and $result.findings[0].rule -eq 'missing-local-target') }

        $unclosed = Join-Path $base 'unclosed.md'
        [IO.File]::WriteAllText($unclosed, "# Unclosed`n`n${fence}text`ncontent`n", [Text.UTF8Encoding]::new($false))
        $result = Test-MarkdownPath $unclosed
        $checks += @{ name = 'unclosed fence'; passed = (-not $result.ok -and $result.findings[0].rule -eq 'unclosed-fence') }

        $remote = Join-Path $base 'remote.md'
        [IO.File]::WriteAllText($remote, "# Remote`n`n[web](https://example.com) [anchor](#part)`n", [Text.UTF8Encoding]::new($false))
        $result = Test-MarkdownPath $remote
        $checks += @{ name = 'remote and fragment ignored'; passed = $result.ok }

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
    switch ($Command) {
        'check' {
            $path = Parse-PathOption @($RemainingArgs)
            $result = Test-MarkdownPath $path
            Write-Json $result
            if ($result.ok) { exit 0 } else { exit 1 }
        }
        'self-test' {
            if (@($RemainingArgs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
                Fail 'self-test does not accept arguments.'
            }
            Write-Json (Invoke-SelfTest)
            exit 0
        }
        default {
            Fail 'Command must be check or self-test.'
        }
    }
}
catch {
    Write-Json @{ ok = $false; command = $Command; error = $_.Exception.Message } $true
    exit 2
}
