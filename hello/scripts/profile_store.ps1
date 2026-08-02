[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Remaining
)

$ErrorActionPreference = 'Stop'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:Files = @('README.md', '个人全景档案.md', '待确认信息.md', '访谈进度.md', '资料索引.md', '迭代日志.md')
$script:Directories = @('原始访谈', '历史版本', '.backups', '.trash')
$script:StateFile = '.hello-state'

function Write-Json([hashtable]$Value) {
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    [Console]::WriteLine(($Value | ConvertTo-Json -Compress -Depth 8))
}

function Fail([string]$Message) {
    throw [InvalidOperationException]::new($Message)
}

function Utc-Now {
    return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function File-Stamp {
    return (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
}

function Parse-Arguments([string[]]$Items) {
    $values = @{}
    $flags = @{'confirmed' = $false}
    $valueNames = @('root', 'input', 'summary-input', 'expected-version', 'kind', 'source', 'id', 'capture-mode', 'next-review-at', 'review-stage')
    for ($index = 0; $index -lt $Items.Count; $index++) {
        $token = $Items[$index]
        if ($token -eq '--confirmed') {
            $flags['confirmed'] = $true
            continue
        }
        if (-not $token.StartsWith('--')) {
            Fail "Unexpected argument: $token"
        }
        $name = $token.Substring(2)
        if ($valueNames -notcontains $name) {
            Fail "Unknown option: $token"
        }
        if ($index + 1 -ge $Items.Count) {
            Fail "Missing value for $token"
        }
        $index++
        $values[$name] = $Items[$index]
    }
    return @{'values' = $values; 'flags' = $flags}
}

function Resolve-ProfileRoot([string]$Value) {
    $raw = $Value
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $raw = [Environment]::GetEnvironmentVariable('HELLO_HOME')
    }
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Fail 'Personal profile root is not configured. Pass --root or set HELLO_HOME.'
    }
    if ($raw -eq '~') {
        $raw = [Environment]::GetFolderPath('UserProfile')
    } elseif ($raw.StartsWith('~\') -or $raw.StartsWith('~/')) {
        $raw = Join-Path ([Environment]::GetFolderPath('UserProfile')) $raw.Substring(2)
    }
    return [IO.Path]::GetFullPath($raw)
}

function Require-Confirmed([bool]$Confirmed) {
    if (-not $Confirmed) {
        Fail 'Mutating commands require --confirmed after user authorization.'
    }
}

function Read-Text([string]$Path) {
    try {
        return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    } catch {
        Fail "Cannot read ${Path}: $($_.Exception.Message)"
    }
}

function Write-Atomic([string]$Path, [string]$Content) {
    $directory = [IO.Path]::GetDirectoryName($Path)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporary = Join-Path $directory ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($temporary, $Content, $script:Utf8)
    try {
        if ([IO.File]::Exists($Path)) {
            $replaceBackup = $temporary + '.replace-backup'
            try {
                [IO.File]::Replace($temporary, $Path, $replaceBackup, $true)
                if ([IO.File]::Exists($replaceBackup)) { [IO.File]::Delete($replaceBackup) }
            } catch {
                if ([IO.File]::Exists($replaceBackup)) { [IO.File]::Delete($replaceBackup) }
                Move-Item -LiteralPath $temporary -Destination $Path -Force
            }
        } else {
            [IO.File]::Move($temporary, $Path)
        }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Read-State([string]$Path) {
    $state = [ordered]@{}
    $number = 0
    foreach ($line in (Read-Text $Path) -split "`r?`n") {
        $number++
        if ([string]::IsNullOrEmpty($line) -or $line.StartsWith('#')) { continue }
        $position = $line.IndexOf('=')
        if ($position -lt 1) { Fail "Invalid state line ${number}: expected key=value." }
        $key = $line.Substring(0, $position)
        if ($state.Contains($key)) { Fail "Duplicate state key on line $number." }
        $state[$key] = $line.Substring($position + 1)
    }
    return $state
}

function Write-State([string]$Path, [System.Collections.IDictionary]$State) {
    $order = @('schema_version', 'profile_version', 'capture_mode', 'created_at', 'updated_at', 'last_confirmed_at', 'next_review_at', 'review_stage')
    $builder = New-Object Text.StringBuilder
    foreach ($key in $order) {
        $value = if ($State.Contains($key)) { [string]$State[$key] } else { '' }
        [void]$builder.Append($key).Append('=').Append($value).Append("`n")
    }
    foreach ($key in ($State.Keys | Where-Object { $order -notcontains $_ } | Sort-Object)) {
        [void]$builder.Append($key).Append('=').Append([string]$State[$key]).Append("`n")
    }
    Write-Atomic $Path $builder.ToString()
}

function Test-State([System.Collections.IDictionary]$State) {
    $issues = New-Object Collections.Generic.List[string]
    $required = @('schema_version', 'profile_version', 'capture_mode', 'created_at', 'updated_at', 'last_confirmed_at', 'next_review_at', 'review_stage')
    foreach ($key in $required) {
        if (-not $State.Contains($key)) { $issues.Add("Missing state key: $key") }
    }
    if ($State['schema_version'] -ne '1') { $issues.Add('schema_version must be 1') }
    $version = 0
    if (-not [int]::TryParse([string]$State['profile_version'], [ref]$version) -or $version -lt 1) {
        $issues.Add('profile_version must be a positive integer')
    }
    if (@('auto-stage', 'prompt', 'explicit') -notcontains $State['capture_mode']) {
        $issues.Add('capture_mode must be auto-stage, prompt, or explicit')
    }
    if (@('baseline', 'first-review', 'stable') -notcontains $State['review_stage']) {
        $issues.Add('review_stage must be baseline, first-review, or stable')
    }
    return $issues.ToArray()
}

function Initialize-Space([string]$Root, [bool]$Confirmed) {
    Require-Confirmed $Confirmed
    [IO.Directory]::CreateDirectory($Root) | Out-Null
    $templateRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\assets\profile-templates'))
    $created = New-Object Collections.Generic.List[string]
    foreach ($name in $script:Directories) {
        $target = Join-Path $Root $name
        if (-not [IO.Directory]::Exists($target)) {
            [IO.Directory]::CreateDirectory($target) | Out-Null
            $created.Add($name + '/')
        }
    }
    foreach ($name in $script:Files) {
        $target = Join-Path $Root $name
        if (-not [IO.File]::Exists($target)) {
            [IO.File]::Copy((Join-Path $templateRoot $name), $target, $false)
            $created.Add($name)
        }
    }
    $statePath = Join-Path $Root $script:StateFile
    if (-not [IO.File]::Exists($statePath)) {
        $current = Utc-Now
        $state = [ordered]@{
            schema_version = '1'; profile_version = '1'; capture_mode = 'auto-stage';
            created_at = $current; updated_at = $current; last_confirmed_at = '';
            next_review_at = ''; review_stage = 'baseline'
        }
        Write-State $statePath $state
        $created.Add($script:StateFile)
    }
    return @{'ok' = $true; 'command' = 'init'; 'root' = $Root; 'created' = $created.ToArray()}
}

function Validate-Space([string]$Root) {
    $issues = New-Object Collections.Generic.List[string]
    if (-not [IO.Directory]::Exists($Root)) {
        $issues.Add('Root directory does not exist')
    } else {
        foreach ($name in $script:Files) {
            if (-not [IO.File]::Exists((Join-Path $Root $name))) { $issues.Add("Missing file: $name") }
        }
        foreach ($name in $script:Directories) {
            if (-not [IO.Directory]::Exists((Join-Path $Root $name))) { $issues.Add("Missing directory: $name") }
        }
        $statePath = Join-Path $Root $script:StateFile
        if (-not [IO.File]::Exists($statePath)) {
            $issues.Add("Missing file: $($script:StateFile)")
        } else {
            try { foreach ($issue in (Test-State (Read-State $statePath))) { $issues.Add($issue) } }
            catch { $issues.Add($_.Exception.Message) }
        }
    }
    return @{'ok' = ($issues.Count -eq 0); 'command' = 'validate'; 'root' = $Root; 'issues' = $issues.ToArray()}
}

function Require-Valid([string]$Root) {
    $result = Validate-Space $Root
    if (-not $result.ok) { Fail ('Invalid profile space: ' + ($result.issues -join '; ')) }
    return Read-State (Join-Path $Root $script:StateFile)
}

function Get-Status([string]$Root) {
    $valid = Validate-Space $Root
    if (-not $valid.ok) {
        return @{'payload' = @{'ok' = $false; 'command' = 'status'; 'root' = $Root; 'issues' = $valid.issues}; 'code' = 1}
    }
    $state = Read-State (Join-Path $Root $script:StateFile)
    $pending = ([regex]::Matches((Read-Text (Join-Path $Root '待确认信息.md')), '(?m)^## C-[0-9TZ-]+\s*$')).Count
    $payload = @{
        'ok' = $true; 'command' = 'status'; 'root' = $Root;
        'profile_version' = [int]$state['profile_version']; 'capture_mode' = $state['capture_mode'];
        'review_stage' = $state['review_stage']; 'last_confirmed_at' = $state['last_confirmed_at'];
        'next_review_at' = $state['next_review_at']; 'pending_candidates' = $pending
    }
    return @{'payload' = $payload; 'code' = 0}
}

function Configure-Space([string]$Root, [string]$CaptureMode, [string]$NextReviewAt, [string]$ReviewStage, [bool]$Confirmed) {
    Require-Confirmed $Confirmed
    $state = Require-Valid $Root
    if ([string]::IsNullOrWhiteSpace($CaptureMode) -and $null -eq $NextReviewAt -and [string]::IsNullOrWhiteSpace($ReviewStage)) {
        Fail 'configure requires at least one setting.'
    }
    if (-not [string]::IsNullOrWhiteSpace($CaptureMode)) {
        if (@('auto-stage', 'prompt', 'explicit') -notcontains $CaptureMode) {
            Fail '--capture-mode must be auto-stage, prompt, or explicit.'
        }
        $state['capture_mode'] = $CaptureMode
    }
    if (-not [string]::IsNullOrWhiteSpace($ReviewStage)) {
        if (@('baseline', 'first-review', 'stable') -notcontains $ReviewStage) {
            Fail '--review-stage must be baseline, first-review, or stable.'
        }
        $state['review_stage'] = $ReviewStage
    }
    if ($null -ne $NextReviewAt) {
        if ($NextReviewAt -eq 'none' -or $NextReviewAt -eq '') {
            $state['next_review_at'] = ''
        } else {
            $parsedDate = [DateTimeOffset]::MinValue
            if (-not [DateTimeOffset]::TryParse($NextReviewAt, [ref]$parsedDate)) {
                Fail '--next-review-at must be ISO 8601 or none.'
            }
            $state['next_review_at'] = $NextReviewAt
        }
    }
    $state['updated_at'] = Utc-Now
    Write-State (Join-Path $Root $script:StateFile) $state
    return @{
        'ok' = $true; 'command' = 'configure'; 'root' = $Root;
        'capture_mode' = $state['capture_mode']; 'review_stage' = $state['review_stage'];
        'next_review_at' = $state['next_review_at']
    }
}

function Show-Diff([string]$Root, [string]$InputPath) {
    [void](Require-Valid $Root)
    $current = (Read-Text (Join-Path $Root '个人全景档案.md')) -split "`r?`n"
    $candidate = (Read-Text $InputPath) -split "`r?`n"
    if ((($current -join "`n") -ceq ($candidate -join "`n"))) {
        [Console]::WriteLine('No changes.')
        return
    }
    [Console]::WriteLine('--- 个人全景档案.md')
    [Console]::WriteLine("+++ $InputPath")
    foreach ($item in (Compare-Object -ReferenceObject $current -DifferenceObject $candidate -SyncWindow 3)) {
        $prefix = if ($item.SideIndicator -eq '=>') { '+' } else { '-' }
        [Console]::WriteLine($prefix + $item.InputObject)
    }
}

function Clean-Label([string]$Value, [string]$Fallback) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Fallback }
    $clean = ([regex]::Replace($Value, '\s+', ' ')).Trim()
    if ($clean.Length -gt 200) { return $clean.Substring(0, 200) }
    return $clean
}

function Stage-Candidate([string]$Root, [string]$InputPath, [string]$Kind, [string]$Source, [bool]$Confirmed) {
    Require-Confirmed $Confirmed
    $state = Require-Valid $Root
    $body = (Read-Text $InputPath).Trim()
    if ([string]::IsNullOrWhiteSpace($body)) { Fail 'Candidate input is empty.' }
    $current = Utc-Now
    $candidateId = 'C-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '-' + $PID
    $pendingPath = Join-Path $Root '待确认信息.md'
    $pending = (Read-Text $pendingPath).Replace("`n当前没有待确认信息。`n", "`n")
    $block = "`n## $candidateId`n`n- 暂存时间：$current`n- 类型：$(Clean-Label $Kind '未分类')`n- 来源：$(Clean-Label $Source '当前会话')`n- 状态：待确认`n`n$body`n"
    Write-Atomic $pendingPath ($pending.TrimEnd() + "`n" + $block)
    $state['updated_at'] = $current
    Write-State (Join-Path $Root $script:StateFile) $state
    return @{'ok' = $true; 'command' = 'stage'; 'root' = $Root; 'candidate_id' = $candidateId}
}

function Copy-Unique([string]$Source, [string]$Directory, [string]$Name) {
    [IO.Directory]::CreateDirectory($Directory) | Out-Null
    $target = Join-Path $Directory $Name
    $counter = 1
    while ([IO.File]::Exists($target)) {
        $target = Join-Path $Directory (([IO.Path]::GetFileNameWithoutExtension($Name)) + '-' + $counter + [IO.Path]::GetExtension($Name))
        $counter++
    }
    [IO.File]::Copy($Source, $target, $false)
    return $target
}

function Update-ProfileHeader([string]$Content, [int]$Version, [string]$ConfirmedAt) {
    $versionRegex = New-Object Text.RegularExpressions.Regex('(?m)^- 资料版本：.*$')
    $timeRegex = New-Object Text.RegularExpressions.Regex('(?m)^- 最近确认时间：.*$')
    if ($versionRegex.Matches($Content).Count -ne 1 -or $timeRegex.Matches($Content).Count -ne 1) {
        Fail 'Candidate profile must contain 资料版本 and 最近确认时间 metadata lines.'
    }
    $content = $versionRegex.Replace($Content, "- 资料版本：$Version", 1)
    return $timeRegex.Replace($content, "- 最近确认时间：$ConfirmedAt", 1)
}

function Apply-Profile([string]$Root, [string]$InputPath, [string]$SummaryPath, [int]$ExpectedVersion, [bool]$Confirmed) {
    Require-Confirmed $Confirmed
    $state = Require-Valid $Root
    $currentVersion = [int]$state['profile_version']
    if ($ExpectedVersion -ne $currentVersion) { Fail "Version conflict: expected $ExpectedVersion, current $currentVersion." }
    $candidate = (Read-Text $InputPath).Trim()
    $summary = (Read-Text $SummaryPath).Trim()
    if ([string]::IsNullOrWhiteSpace($candidate)) { Fail 'Candidate profile is empty.' }
    if ([string]::IsNullOrWhiteSpace($summary)) { Fail 'Update summary is empty.' }
    $profilePath = Join-Path $Root '个人全景档案.md'
    $current = Utc-Now
    $newVersion = $currentVersion + 1
    $candidate = (Update-ProfileHeader ($candidate + "`n") $newVersion $current)
    $name = (File-Stamp) + "-v$currentVersion-个人全景档案.md"
    $history = Copy-Unique $profilePath (Join-Path $Root '历史版本') $name
    $backup = Copy-Unique $profilePath (Join-Path $Root '.backups\profile') $name
    Write-Atomic $profilePath $candidate
    $logPath = Join-Path $Root '迭代日志.md'
    $log = (Read-Text $logPath).Replace("`n当前没有正式迭代。`n", "`n").TrimEnd()
    $entry = "`n`n## R$newVersion · $current`n`n- 资料版本：$newVersion`n- 确认状态：用户已确认`n- 历史快照：``历史版本/$([IO.Path]::GetFileName($history))```n`n$summary`n"
    Write-Atomic $logPath ($log + $entry)
    $state['profile_version'] = [string]$newVersion
    $state['updated_at'] = $current
    $state['last_confirmed_at'] = $current
    if ($state['review_stage'] -eq 'baseline') { $state['review_stage'] = 'first-review' }
    Write-State (Join-Path $Root $script:StateFile) $state
    return @{
        'ok' = $true; 'command' = 'apply'; 'root' = $Root; 'old_version' = $currentVersion;
        'profile_version' = $newVersion; 'history' = $history; 'backup' = $backup
    }
}

function Withdraw-Candidate([string]$Root, [string]$CandidateId, [bool]$Confirmed) {
    Require-Confirmed $Confirmed
    $state = Require-Valid $Root
    if ($CandidateId -notmatch '^C-[0-9TZ-]+$') { Fail 'Invalid candidate id.' }
    $pendingPath = Join-Path $Root '待确认信息.md'
    $content = Read-Text $pendingPath
    $pattern = '(?ms)^## ' + [regex]::Escape($CandidateId) + '\s*\r?\n.*?(?=^## C-[0-9TZ-]+\s*$|\z)'
    $match = [regex]::Match($content, $pattern)
    if (-not $match.Success) { Fail "Candidate not found: $CandidateId" }
    $trashDirectory = Join-Path $Root '.trash\candidates'
    [IO.Directory]::CreateDirectory($trashDirectory) | Out-Null
    $trash = Join-Path $trashDirectory ($CandidateId + '.md')
    if ([IO.File]::Exists($trash)) { $trash = Join-Path $trashDirectory ($CandidateId + '-' + (File-Stamp) + '.md') }
    Write-Atomic $trash ($match.Value.TrimEnd() + "`n")
    $remaining = ($content.Remove($match.Index, $match.Length)).TrimEnd() + "`n"
    if ($remaining -notmatch '(?m)^## C-[0-9TZ-]+\s*$') {
        $remaining = $remaining.TrimEnd() + "`n`n当前没有待确认信息。`n"
    }
    Write-Atomic $pendingPath $remaining
    $state['updated_at'] = Utc-Now
    Write-State (Join-Path $Root $script:StateFile) $state
    return @{'ok' = $true; 'command' = 'withdraw'; 'root' = $Root; 'candidate_id' = $CandidateId; 'trash' = $trash}
}

function Invoke-SelfTest {
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('hello-self-test-' + [Guid]::NewGuid().ToString('N'))
    try {
        $root = Join-Path $temporary '中文 空格'
        try {
            [void](Initialize-Space $root $false)
            Fail 'Confirmation guard did not fail.'
        } catch {
            if ($_.Exception.Message -notlike 'Mutating commands require*') { throw }
        }
        [void](Initialize-Space $root $true)
        $secondInit = Initialize-Space $root $true
        if ($secondInit.created.Count -ne 0) { Fail 'Self-test init overwrote existing space.' }
        $validation = Validate-Space $root
        if (-not $validation.ok) { Fail ('Self-test init failed: ' + ($validation.issues -join '; ')) }
        $candidatePath = Join-Path $temporary 'candidate.md'
        Write-Atomic $candidatePath "用户完成了一个重要项目。`n"
        $staged = Stage-Candidate $root $candidatePath '经历' '自测' $true
        $configured = Configure-Space $root 'prompt' '2030-01-01T00:00:00Z' $null $true
        if ($configured.capture_mode -ne 'prompt') { Fail 'Self-test configure failed.' }
        $profileCandidate = Join-Path $temporary 'profile.md'
        Write-Atomic $profileCandidate (Read-Text (Join-Path $root '个人全景档案.md'))
        $summary = Join-Path $temporary 'summary.md'
        Write-Atomic $summary "- 自测更新。`n"
        $state = Read-State (Join-Path $root $script:StateFile)
        $applied = Apply-Profile $root $profileCandidate $summary ([int]$state['profile_version']) $true
        try {
            [void](Apply-Profile $root $profileCandidate $summary 1 $true)
            Fail 'Version conflict did not fail.'
        } catch {
            if ($_.Exception.Message -notlike 'Version conflict:*') { throw }
        }
        [void](Withdraw-Candidate $root $staged.candidate_id $true)
        $final = Validate-Space $root
        if (-not $final.ok -or $applied.profile_version -ne 2) { Fail 'Self-test final validation failed.' }
        return @{'ok' = $true; 'command' = 'self-test'}
    } finally {
        if ([IO.Directory]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force }
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($Command)) { Fail 'Command is required.' }
    $allowed = @('resolve-root', 'init', 'validate', 'status', 'configure', 'diff', 'stage', 'apply', 'withdraw', 'self-test')
    if ($allowed -notcontains $Command) { Fail ('Unknown command: ' + $Command) }
    if ($Command -eq 'self-test') {
        Write-Json (Invoke-SelfTest)
        exit 0
    }
    $parsed = Parse-Arguments $Remaining
    $values = $parsed.values
    $confirmed = [bool]$parsed.flags.confirmed
    $root = Resolve-ProfileRoot $values['root']
    switch ($Command) {
        'resolve-root' { Write-Json @{'ok' = $true; 'command' = $Command; 'root' = $root}; exit 0 }
        'init' { Write-Json (Initialize-Space $root $confirmed); exit 0 }
        'validate' {
            $result = Validate-Space $root
            Write-Json $result
            if ($result.ok) { exit 0 } else { exit 1 }
        }
        'status' {
            $result = Get-Status $root
            Write-Json $result.payload
            exit $result.code
        }
        'configure' {
            Write-Json (Configure-Space $root $values['capture-mode'] $values['next-review-at'] $values['review-stage'] $confirmed)
            exit 0
        }
        'diff' {
            if (-not $values.ContainsKey('input')) { Fail 'diff requires --input.' }
            Show-Diff $root ([IO.Path]::GetFullPath($values['input']))
            exit 0
        }
        'stage' {
            if (-not $values.ContainsKey('input')) { Fail 'stage requires --input.' }
            Write-Json (Stage-Candidate $root ([IO.Path]::GetFullPath($values['input'])) $values['kind'] $values['source'] $confirmed)
            exit 0
        }
        'apply' {
            foreach ($name in @('input', 'summary-input', 'expected-version')) {
                if (-not $values.ContainsKey($name)) { Fail "apply requires --$name." }
            }
            $expected = 0
            if (-not [int]::TryParse($values['expected-version'], [ref]$expected)) { Fail '--expected-version must be an integer.' }
            Write-Json (Apply-Profile $root ([IO.Path]::GetFullPath($values['input'])) ([IO.Path]::GetFullPath($values['summary-input'])) $expected $confirmed)
            exit 0
        }
        'withdraw' {
            if (-not $values.ContainsKey('id')) { Fail 'withdraw requires --id.' }
            Write-Json (Withdraw-Candidate $root $values['id'] $confirmed)
            exit 0
        }
    }
} catch {
    Write-Json @{'ok' = $false; 'command' = $Command; 'error' = $_.Exception.Message}
    exit 2
}
