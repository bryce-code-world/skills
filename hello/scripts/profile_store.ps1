param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ArgTail
)

$Remaining = if ($null -eq $ArgTail -or ($ArgTail.Count -eq 1 -and [string]::IsNullOrEmpty([string]$ArgTail[0]))) { @() } else { @($ArgTail) }

$ErrorActionPreference = 'Stop'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:StrictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
$script:Files = @('README.md', '个人全景档案.md', '待确认信息.md', '访谈进度.md', '资料索引.md', '迭代日志.md')
$script:Directories = @('原始访谈', '历史版本', '.backups', '.trash')
$script:StateFile = '.hello-state'
$script:TransactionFile = '.hello-transaction'
$script:LayoutTransactionFile = '.hello-layout-transaction'
$script:LockDirectoryName = '.hello-lock'
$script:HeldLocks = @{}
$script:SelfPath = $PSCommandPath
$script:HostCommand = if($PSVersionTable.PSEdition -ceq 'Core'){'pwsh'}else{'powershell.exe'}
$script:ProfileSections = @(
    '## 一、当前起点', '## 二、人生时间线与关键经历', '## 三、能力、经验与证据',
    '## 四、知识、认知与学习方式', '## 五、健康、精力与可持续边界', '## 六、经济、资源与风险承受能力',
    '## 七、关系、支持网络与现实责任', '## 八、习惯、行动与决策方式', '## 九、价值观、世界观与人生愿景',
    '## 十、当前目标与未来设想', '## 十一、AI 协作偏好', '## 十二、未知、冲突与 AI 假设', '## 十三、主要来源'
)
$script:ProgressSections = @('## 已覆盖主题', '## 待补充主题', '## 暂不收集', '## 下次问题')
$script:SummaryFields = @('触发原因', '信息来源', '更新类型', '更新位置', '更新摘要', '用户确认状态', '执行工具')
$script:TargetRequiredFiles = @('.hello-state', 'manifest.json', 'README.md', '个人全景档案.md', '主题覆盖矩阵.md', '待确认信息.md', '访谈进度.md', '资料索引.md', '迭代日志.md')
$script:TargetRequiredDirectories = @('原始访谈', '来源', '权威', '派生', '历史版本', '.backups', '.trash')

function Write-Json([hashtable]$Value) {
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    [Console]::WriteLine(($Value | ConvertTo-Json -Compress -Depth 10))
}

function Fail([string]$Message) { throw [InvalidOperationException]::new($Message) }
function Utc-Now { return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
function File-Stamp { return (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') }

function Parse-Arguments([string[]]$Items) {
    $values = @{}
    $flags = @{'confirmed' = $false; 'simulate-failure' = $false}
    $seenValueNames = @()
    $confirmedSeen = $false
    $simulateFailureSeen = $false
    $valueNames = @(
        'root', 'input', 'summary-input', 'expected-version', 'kind', 'source', 'id',
        'capture-mode', 'next-review-at', 'review-stage', 'progress-input', 'session-id',
        'turn-id', 'expected-progress-version', 'target', 'destination', 'migration-id'
    )
    for ($index = 0; $index -lt $Items.Count; $index++) {
        $token = $Items[$index]
        if ($token -ceq '--confirmed') {
            if ($confirmedSeen) { Fail 'Duplicate option: --confirmed' }
            $confirmedSeen = $true; $flags['confirmed'] = $true; continue
        }
        if ($token -ceq '--simulate-failure') {
            if ($simulateFailureSeen) { Fail 'Duplicate option: --simulate-failure' }
            $simulateFailureSeen = $true; $flags['simulate-failure'] = $true; continue
        }
        if ($token -ceq '--') { Fail 'Option terminator -- is not supported.' }
        if (-not $token.StartsWith('--')) { Fail "Unexpected argument: $token" }
        if ($token.Contains('=')) { Fail 'Options must pass values as a separate argument.' }
        $name = $token.Substring(2)
        if ($valueNames -cnotcontains $name) { Fail "Unknown option: $token" }
        if ($seenValueNames -ccontains $name) { Fail "Duplicate option: --$name" }
        $seenValueNames += $name
        if ($index + 1 -ge $Items.Count) { Fail "Missing value for $token" }
        # Never consume another option as a value. A dropped value such as
        # ``--root --confirmed`` must fail at the parser boundary.
        if ([string]$Items[$index + 1] -like '--*') { Fail "Missing value for $token" }
        $index++; $values[$name] = $Items[$index]
    }
    return @{'values' = $values; 'flags' = $flags}
}

function Validate-CommandArguments([string]$Name,[System.Collections.IDictionary]$Values,[System.Collections.IDictionary]$Flags) {
    $allowed = @{
        'resolve-root' = @('root')
        'init' = @('root')
        'validate' = @('root')
        'status' = @('root')
        'configure' = @('root','capture-mode','next-review-at','review-stage')
        'record-disclosure' = @('root','capture-mode')
        'diff' = @('root','input')
        'stage' = @('root','input','kind','source')
        'apply' = @('root','input','summary-input','expected-version')
        'record-turn' = @('root','input','progress-input','session-id','turn-id','expected-progress-version')
        'withdraw' = @('root','id')
        'recover' = @('root')
        'target-validate' = @('root','target')
        'migrate-plan' = @('root','target','migration-id')
        'migrate-apply' = @('root','target','destination','expected-version','expected-progress-version')
        'rebuild-index' = @('root','target')
        'switch-layout' = @('root','target','migration-id','expected-version','expected-progress-version')
        'rollback-layout' = @('root','migration-id')
    }
    foreach($key in $Values.Keys) {
        if(-not ($allowed.Keys -ccontains $Name) -or $allowed[$Name] -cnotcontains [string]$key) {
            Fail "Option --$key is not valid for $Name."
        }
    }
    if($Flags['confirmed'] -and @('resolve-root','validate','status','diff','target-validate') -ccontains $Name) {
        Fail "Option --confirmed is not valid for $Name."
    }
    if($Flags['simulate-failure'] -and @('apply','record-turn','migrate-apply','switch-layout') -cnotcontains $Name) {
        Fail "Option --simulate-failure is not valid for $Name."
    }
}

function Resolve-ProfileRoot([string]$Value,[bool]$Provided=$false) {
    $raw = $Value
    if ($Provided -and [string]::IsNullOrWhiteSpace($raw)) { Fail 'Explicit --root cannot be empty.' }
    if (-not $Provided -and [string]::IsNullOrWhiteSpace($raw)) { $raw = [Environment]::GetEnvironmentVariable('HELLO_HOME') }
    if ([string]::IsNullOrWhiteSpace($raw)) { Fail 'Personal profile root is not configured. Pass --root or set HELLO_HOME.' }
    if ($raw -ceq '~') { $raw = [Environment]::GetFolderPath('UserProfile') }
    elseif ($raw.StartsWith('~\') -or $raw.StartsWith('~/')) { $raw = Join-Path ([Environment]::GetFolderPath('UserProfile')) $raw.Substring(2) }
    return [IO.Path]::GetFullPath($raw)
}

function Require-Confirmed([bool]$Confirmed) {
    if (-not $Confirmed) { Fail 'Mutating commands require --confirmed after user authorization.' }
}

function Read-Text([string]$Path) {
    try {
        $content = [IO.File]::ReadAllText($Path, $script:StrictUtf8)
        return $content.Replace("`r`n", "`n").Replace("`r", "`n")
    }
    catch { Fail "Cannot read ${Path}: $($_.Exception.Message)" }
}

function Write-Atomic([string]$Path, [string]$Content) {
    $directory = [IO.Path]::GetDirectoryName($Path)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    # PowerShell's JSON serializer may emit CRLF even when the caller passes
    # LF.  Normalize at the single write boundary so target packages satisfy
    # the cross-adapter UTF-8/LF contract.
    $Content = [regex]::Replace([string]$Content, "`r`n|`r", "`n")
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
        } else { [IO.File]::Move($temporary, $Path) }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Write-Atomic-New([string]$Path, [string]$Content) {
    $directory = [IO.Path]::GetDirectoryName($Path)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $Content = [regex]::Replace([string]$Content, "`r`n|`r", "`n")
    $temporary = Join-Path $directory ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($temporary, $Content, $script:Utf8)
    try {
        # A same-directory rename is atomic and, unlike Write-Atomic, refuses
        # to replace an existing marker (the File.Move destination check is
        # the Windows equivalent of O_EXCL/CreateNew).
        [IO.File]::Move($temporary, $Path)
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Get-LockKey([string]$Root) {
    return ([IO.Path]::GetFullPath($Root)).TrimEnd('\').ToUpperInvariant()
}

function Enter-ProfileLock([string]$Root) {
    $key = Get-LockKey $Root
    if ($script:HeldLocks.ContainsKey($key)) {
        $script:HeldLocks[$key] = [int]$script:HeldLocks[$key] + 1
        return
    }
    if (-not [IO.Directory]::Exists($Root)) { return }
    $lockPath = Join-Path $Root $script:LockDirectoryName
    if ([IO.Directory]::Exists($lockPath)) { Fail 'Profile space is busy; retry later.' }
    try {
        # CreateNew on the owner file closes the check/create race between
        # processes; an existing lock is never removed by a losing process.
        [IO.Directory]::CreateDirectory($lockPath) | Out-Null
        $ownerPath = Join-Path $lockPath 'owner'
        $stream = [IO.File]::Open($ownerPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $bytes = $script:Utf8.GetBytes("pid=$PID`nstarted_at=$(Utc-Now)`n")
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()
        } finally { $stream.Dispose() }
        $script:HeldLocks[$key] = 1
    } catch {
        Fail 'Profile space is busy; retry later.'
    }
}

function Exit-ProfileLock([string]$Root) {
    $key = Get-LockKey $Root
    if (-not $script:HeldLocks.ContainsKey($key)) { return }
    $depth = [int]$script:HeldLocks[$key] - 1
    if ($depth -gt 0) { $script:HeldLocks[$key] = $depth; return }
    [void]$script:HeldLocks.Remove($key)
    $lockPath = Join-Path $Root $script:LockDirectoryName
    $ownerPath = Join-Path $lockPath 'owner'
    try { if ([IO.File]::Exists($ownerPath)) { [IO.File]::Delete($ownerPath) }; if ([IO.Directory]::Exists($lockPath)) { [IO.Directory]::Delete($lockPath, $false) } } catch { }
}

function Invoke-WithProfileLock([string]$Root, [scriptblock]$Action) {
    Enter-ProfileLock $Root
    try { return (& $Action) } finally { Exit-ProfileLock $Root }
}

function Read-KeyValues([string]$Path) {
    # Keep storage keys case-sensitive for exact lookup, while rejecting
    # case-variant duplicates just like Python/POSIX.  This prevents a
    # reserved key from being interpreted differently by another adapter.
    $state = New-Object System.Collections.Specialized.OrderedDictionary ([StringComparer]::Ordinal)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $number = 0
    foreach ($line in (Read-Text $Path) -split "`r?`n") {
        $number++
        if ([string]::IsNullOrEmpty($line) -or $line.StartsWith('#')) { continue }
        $position = $line.IndexOf('=')
        if ($position -lt 1) { Fail "Invalid key=value line $number in $([IO.Path]::GetFileName($Path))." }
        $key = $line.Substring(0, $position)
        if (-not $seen.Add($key)) { Fail "Duplicate key on line $number in $([IO.Path]::GetFileName($Path))." }
        $state.Add($key, $line.Substring($position + 1))
    }
    return $state
}

function Read-State([string]$Path) { return Read-KeyValues $Path }

function Write-State([string]$Path, [System.Collections.IDictionary]$State) {
    $order = @(
        'schema_version', 'profile_version', 'progress_version', 'capture_mode', 'created_at', 'updated_at',
        'last_confirmed_at', 'next_review_at', 'review_stage', 'last_interview_at', 'last_session_id', 'last_turn_id', 'last_capture_disclosed_at', 'last_capture_disclosed_mode'
    )
    $builder = New-Object Text.StringBuilder
    foreach ($key in $order) { if ($State.Contains($key)) { [void]$builder.Append($key).Append('=').Append([string]$State[$key]).Append("`n") } }
    foreach ($key in ($State.Keys | Where-Object { $order -cnotcontains $_ } | Sort-Object)) {
        [void]$builder.Append($key).Append('=').Append([string]$State[$key]).Append("`n")
    }
    Write-Atomic $Path $builder.ToString()
}

function Test-Iso([string]$Value, [bool]$AllowEmpty = $true) {
    if ([string]::IsNullOrEmpty($Value)) { return $AllowEmpty }
    # State timestamps use one canonical UTC representation across adapters.
    if ($Value -cnotmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$') { return $false }
    $parsed = [DateTimeOffset]::MinValue
    return [DateTimeOffset]::TryParseExact(
        $Value,
        'yyyy-MM-ddTHH:mm:ss\Z',
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal,
        [ref]$parsed
    )
}

function Test-PositiveDecimal([string]$Value) {
    return (-not [string]::IsNullOrEmpty($Value)) -and $Value -cmatch '^[1-9][0-9]*$'
}

function Compare-Decimal([string]$Left,[string]$Right) {
    if (-not (Test-PositiveDecimal $Left) -or -not (Test-PositiveDecimal $Right)) { Fail 'Decimal version must be a canonical positive integer.' }
    if ($Left.Length -lt $Right.Length) { return -1 }
    if ($Left.Length -gt $Right.Length) { return 1 }
    $comparison = [String]::CompareOrdinal($Left,$Right)
    if ($comparison -lt 0) { return -1 }
    if ($comparison -gt 0) { return 1 }
    return 0
}

function Increment-Decimal([string]$Value) {
    if (-not (Test-PositiveDecimal $Value)) { Fail 'Decimal version must be a canonical positive integer.' }
    $chars = $Value.ToCharArray()
    for ($index = $chars.Length - 1; $index -ge 0; $index--) {
        if ($chars[$index] -ceq [char]'9') { $chars[$index] = [char]'0'; continue }
        $chars[$index] = [char](([int][char]$chars[$index]) + 1)
        return (-join $chars)
    }
    return ('1' + (-join $chars))
}

function Get-ProgressVersion([System.Collections.IDictionary]$State) {
    if ($State.Contains('progress_version')) { return [string]$State['progress_version'] }
    return '1'
}

function Get-EffectiveProgressVersion([string]$Root,[System.Collections.IDictionary]$State) {
    if ($State.Contains('progress_version') -or [string]$State['schema_version'] -cne '1') { return Get-ProgressVersion $State }
    $progressPath=Join-Path $Root '访谈进度.md'
    if ([IO.File]::Exists($progressPath)) {
        $matches=[regex]::Matches((Read-Text $progressPath),'(?m)^- 进度版本：([1-9][0-9]*)$')
        if($matches.Count -eq 1) {
            return [string]$matches[0].Groups[1].Value
        }
    }
    return '1'
}

function Test-State([System.Collections.IDictionary]$State) {
    $issues = New-Object Collections.Generic.List[string]
    $required = @('schema_version','profile_version','capture_mode','created_at','updated_at','last_confirmed_at','next_review_at','review_stage')
    foreach ($key in $required) { if (-not $State.Contains($key)) { $issues.Add("Missing state key: $key") } }
    if (@('1','2','3') -cnotcontains [string]$State['schema_version']) { $issues.Add('schema_version must be 1, 2, or 3') }
    if ([string]$State['schema_version'] -ceq '3' -and [string]$State['layout'] -cne 'target') { $issues.Add('schema_version 3 requires layout=target') }
    if ($State['schema_version'] -ceq '2') { foreach($key in @('progress_version','last_session_id','last_turn_id')) { if(-not $State.Contains($key)){$issues.Add("Missing state key: $key")} } }
    foreach ($key in @('profile_version','progress_version')) {
        if ($key -ceq 'progress_version' -and $State['schema_version'] -ceq '1' -and -not $State.Contains($key)) { continue }
        if (-not (Test-PositiveDecimal ([string]$State[$key]))) { $issues.Add("$key must be a positive integer") }
    }
    if (@('auto-stage','prompt','explicit') -cnotcontains $State['capture_mode']) { $issues.Add('capture_mode must be auto-stage, prompt, or explicit') }
    if ($State.Contains('last_capture_disclosed_mode') -and -not [string]::IsNullOrEmpty([string]$State['last_capture_disclosed_mode']) -and @('auto-stage','prompt','explicit') -cnotcontains [string]$State['last_capture_disclosed_mode']) { $issues.Add('last_capture_disclosed_mode must be empty, auto-stage, prompt, or explicit') }
    if (@('baseline','first-review','stable') -cnotcontains $State['review_stage']) { $issues.Add('review_stage must be baseline, first-review, or stable') }
    if ($State['review_stage'] -ceq 'first-review' -and [string]::IsNullOrWhiteSpace([string]$State['next_review_at'])) { $issues.Add('first-review requires next_review_at') }
    foreach ($key in @('created_at','updated_at')) { if ($State.Contains($key) -and -not (Test-Iso ([string]$State[$key]) $false)) { $issues.Add("$key must be ISO 8601") } }
    foreach ($key in @('last_confirmed_at','next_review_at','last_interview_at','last_capture_disclosed_at')) { if ($State.Contains($key) -and -not (Test-Iso ([string]$State[$key]) $true)) { $issues.Add("$key must be empty or ISO 8601") } }
    return $issues.ToArray()
}

function Count-Matches([string]$Content, [string]$Pattern) { return ([regex]::Matches($Content, $Pattern)).Count }

function Test-ProfileContent([string]$Content, [string]$ExpectedVersion) {
    $issues = New-Object Collections.Generic.List[string]
    if (-not $Content.StartsWith("# 个人全景档案`n")) { $issues.Add('Profile must start with # 个人全景档案') }
    $versions = [regex]::Matches($Content, '(?m)^- 资料版本：([1-9][0-9]*)$')
    if ($versions.Count -ne 1) { $issues.Add('资料版本 metadata must appear exactly once') }
    else {
        $profileNumber = [string]$versions[0].Groups[1].Value
        if (-not [string]::IsNullOrEmpty([string]$ExpectedVersion) -and (Compare-Decimal $profileNumber ([string]$ExpectedVersion)) -ne 0) { $issues.Add("Profile version $profileNumber does not match state version $ExpectedVersion") }
    }
    if ((Count-Matches $Content '(?m)^- 最近确认时间：.+$') -ne 1) { $issues.Add('最近确认时间 metadata must appear exactly once') }
    foreach ($heading in $script:ProfileSections) { if ((Count-Matches $Content ('(?m)^' + [regex]::Escape($heading) + '$')) -ne 1) { $issues.Add("Missing or duplicate profile section: $($heading.Substring(3))") } }
    return $issues.ToArray()
}

function Test-ProgressContent([string]$Content, [string]$ExpectedVersion, [bool]$RequireVersion) {
    $issues = New-Object Collections.Generic.List[string]
    if (-not $Content.StartsWith("# 访谈进度`n")) { $issues.Add('Interview progress must start with # 访谈进度') }
    $headers = [regex]::Matches($Content, '(?m)^- 进度版本：.*$')
    $versions = [regex]::Matches($Content, '(?m)^- 进度版本：([1-9][0-9]*)$')
    if ($headers.Count -gt 1) { $issues.Add('进度版本 metadata must appear at most once') }
    elseif ($headers.Count -eq 1 -and $versions.Count -eq 0) { $issues.Add('进度版本 metadata must be a positive integer') }
    elseif ($RequireVersion -and $headers.Count -eq 0) { $issues.Add('Missing progress metadata: 进度版本') }
    elseif ($versions.Count -eq 1) {
        $progressNumber=[string]$versions[0].Groups[1].Value
        if(-not [string]::IsNullOrEmpty([string]$ExpectedVersion) -and (Compare-Decimal $progressNumber ([string]$ExpectedVersion)) -ne 0) { $issues.Add("Progress version $progressNumber does not match state version $ExpectedVersion") }
    }
    foreach ($heading in $script:ProgressSections) { if ((Count-Matches $Content ('(?m)^' + [regex]::Escape($heading) + '$')) -ne 1) { $issues.Add("Missing or duplicate progress section: $($heading.Substring(3))") } }
    return $issues.ToArray()
}

function Test-LogContent([string]$Content, [string]$ProfileVersion) {
    $issues = New-Object Collections.Generic.List[string]
    $headings = @()
    foreach ($match in [regex]::Matches($Content, '(?m)^## R([0-9]+) · ')) {
        $value = [string]$match.Groups[1].Value
        if (-not (Test-PositiveDecimal $value)) { $issues.Add("Invalid iteration log version R$value") } else { $headings += $value }
    }
    if (($headings | Select-Object -Unique).Count -ne $headings.Count) { $issues.Add('Iteration log contains duplicate version headings') }
    for ($index = 1; $index -lt $headings.Count; $index++) { if ((Compare-Decimal $headings[$index] $headings[$index - 1]) -lt 0) { $issues.Add('Iteration log versions must be ascending'); break } }
    if (-not [string]::IsNullOrEmpty([string]$ProfileVersion) -and (Compare-Decimal ([string]$ProfileVersion) '1') -gt 0 -and $headings -notcontains [string]$ProfileVersion) { $issues.Add("Iteration log is missing version R$ProfileVersion") }
    return $issues.ToArray()
}

function Initialize-Space-Core([string]$Root, [bool]$Confirmed) {
    Require-Confirmed $Confirmed
    [IO.Directory]::CreateDirectory($Root) | Out-Null
    $templateRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\assets\profile-templates'))
    $created = New-Object Collections.Generic.List[string]
    foreach ($name in $script:Directories) { $target = Join-Path $Root $name; if (-not [IO.Directory]::Exists($target)) { [IO.Directory]::CreateDirectory($target) | Out-Null; $created.Add($name + '/') } }
    foreach ($name in $script:Files) { $target = Join-Path $Root $name; if (-not [IO.File]::Exists($target)) { Write-Atomic $target (Read-Text (Join-Path $templateRoot $name)); $created.Add($name) } }
    $statePath = Join-Path $Root $script:StateFile
    if (-not [IO.File]::Exists($statePath)) {
        $current = Utc-Now
        $state = [ordered]@{
            schema_version='2'; profile_version='1'; progress_version='1'; capture_mode='prompt';
            created_at=$current; updated_at=$current; last_confirmed_at=''; next_review_at=''; review_stage='baseline';
            last_interview_at=''; last_session_id=''; last_turn_id=''; last_capture_disclosed_at=''; last_capture_disclosed_mode=''
        }
        Write-State $statePath $state; $created.Add($script:StateFile)
    }
    return @{'ok'=$true;'command'='init';'root'=$Root;'created'=$created.ToArray()}
}

function Initialize-Space([string]$Root, [bool]$Confirmed) {
    Require-Confirmed $Confirmed
    [IO.Directory]::CreateDirectory($Root) | Out-Null
    return Invoke-WithProfileLock $Root { Initialize-Space-Core $Root $Confirmed }
}

# ---------------------------------------------------------------------------
# Target layout (schema 3) helpers
# ---------------------------------------------------------------------------
# Target commands deliberately live beside the compatibility implementation.
# They never infer a root from directory names: a root is target only when the
# explicit marker and manifest agree.  Keeping these helpers in the adapter
# makes the PowerShell, Python and POSIX implementations share the same
# fail-closed boundary without changing schema-2 files or command semantics.

function Resolve-ExplicitPath([string]$Value,[string]$OptionName) {
    if ([string]::IsNullOrWhiteSpace($Value)) { Fail "Explicit --$OptionName cannot be empty." }
    return [IO.Path]::GetFullPath($Value)
}

function Get-Sha256Hex([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { Fail "File does not exist: $Path" }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [IO.File]::ReadAllBytes($Path)
        $digest = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($digest).Replace('-', '')).ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Get-RelativePath([string]$Root,[string]$Path) {
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($rootFull,[StringComparison]::OrdinalIgnoreCase)) {
        Fail "Path escapes root: $Path"
    }
    return $full.Substring($rootFull.Length).Replace('\','/')
}

function Assert-IndependentRoots([string]$Left,[string]$Right) {
    $leftFull = [IO.Path]::GetFullPath($Left).TrimEnd('\')
    $rightFull = [IO.Path]::GetFullPath($Right).TrimEnd('\')
    if ($leftFull.Equals($rightFull,[StringComparison]::OrdinalIgnoreCase)) {
        Fail 'Source and target roots must be independent (the same root is not allowed).'
    }
    $leftPrefix = $leftFull + '\'; $rightPrefix = $rightFull + '\'
    if ($leftFull.StartsWith($rightPrefix,[StringComparison]::OrdinalIgnoreCase) -or
        $rightFull.StartsWith($leftPrefix,[StringComparison]::OrdinalIgnoreCase)) {
        Fail 'Source and target roots must not be parent/child directories.'
    }
}

function Test-SafeMigrationId([string]$Value) {
    return (-not [string]::IsNullOrWhiteSpace($Value)) -and $Value -cmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'
}

function Has-JsonProperty($Object,[string]$Name) {
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return ($null -ne $Object.PSObject.Properties[$Name])
}

function Read-TargetMarker([string]$Root) {
    $path = Join-Path $Root $script:StateFile
    if (-not [IO.File]::Exists($path)) { Fail "Missing target marker: $script:StateFile" }
    $values = Read-KeyValues $path
    foreach ($key in @('layout','layout_version','schema_version','migration_id','package_id','subject_id')) {
        if (-not $values.Contains($key) -or [string]::IsNullOrWhiteSpace([string]$values[$key])) {
            Fail "Missing target marker field: $key"
        }
    }
    if (@('target-draft','target') -cnotcontains [string]$values['layout']) { Fail 'Target marker layout must be target-draft or target.' }
    if ([string]$values['layout_version'] -cne '1') { Fail 'Target marker layout_version must be 1.' }
    $schema = [string]$values['schema_version']
    if ($schema -cne '3' -and $schema -notmatch '^target-draft-[0-9]+\.[0-9]+$') { Fail 'Target marker schema_version must be 3 or target-draft-x.y.' }
    if (-not (Test-SafeMigrationId ([string]$values['migration_id']))) { Fail 'Target marker migration_id is invalid.' }
    return $values
}

function Read-TargetManifest([string]$Root) {
    $path = Join-Path $Root 'manifest.json'
    if (-not [IO.File]::Exists($path)) { Fail 'Missing target manifest: manifest.json' }
    try { $manifest = (Read-Text $path) | ConvertFrom-Json -ErrorAction Stop }
    catch { Fail "Invalid target manifest JSON: $($_.Exception.Message)" }
    foreach ($key in @('layout','layout_version','schema_version','migration_id','package_id','subject_id','owner','audience')) {
        if (-not (Has-JsonProperty $manifest $key)) { Fail "Missing target manifest field: $key" }
    }
    if (@('target-draft','target') -cnotcontains [string]$manifest.layout) { Fail 'Target manifest layout must be target-draft or target.' }
    if ([int]$manifest.layout_version -ne 1) { Fail 'Target manifest layout_version must be 1.' }
    if ([string]$manifest.schema_version -cne '3' -and [string]$manifest.schema_version -notmatch '^target-draft-[0-9]+\.[0-9]+$') { Fail 'Target manifest schema_version is invalid.' }
    if (-not (Test-SafeMigrationId ([string]$manifest.migration_id))) { Fail 'Target manifest migration_id is invalid.' }
    return $manifest
}

function Get-TargetMarkerIfPresent([string]$Root) {
    $path = Join-Path $Root $script:StateFile
    if (-not [IO.File]::Exists($path)) { return $null }
    try {
        $values = Read-KeyValues $path
        if ($values.Contains('layout')) { return $values }
    } catch { return $null }
    return $null
}

function Test-TargetTextFiles([string]$Root,[System.Collections.Generic.List[string]]$Issues) {
    # Check all markdown/JSON/key-value files for UTF-8 and LF.  Binary files
    # are ignored; no file is ever echoed into validation output.
    try {
        foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction Stop)) {
            if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $Issues.Add("Reparse point is not allowed: $(Get-RelativePath $Root $file.FullName)"); continue }
            $ext = [IO.Path]::GetExtension($file.Name).ToLowerInvariant()
            if (@('.md','.json','.state','.txt','') -notcontains $ext -and $file.Name -ne 'manifest.json') { continue }
            try {
                $bytes = [IO.File]::ReadAllBytes($file.FullName)
                if ($bytes -contains [byte]13) { $Issues.Add("CRLF is not allowed: $(Get-RelativePath $Root $file.FullName)") }
                [void]$script:StrictUtf8.GetString($bytes)
            } catch { $Issues.Add("Invalid UTF-8 file: $(Get-RelativePath $Root $file.FullName)") }
        }
    } catch { $Issues.Add("Cannot enumerate target files: $($_.Exception.Message)") }
}

function Target-Validate-Core([string]$Root) {
    $issues = New-Object Collections.Generic.List[string]
    $marker = $null; $manifest = $null
    if (-not [IO.Directory]::Exists($Root)) { $issues.Add('Root directory does not exist') }
    else {
        foreach ($name in $script:TargetRequiredFiles) { if (-not [IO.File]::Exists((Join-Path $Root $name))) { $issues.Add("Missing target file: $name") } }
        foreach ($name in $script:TargetRequiredDirectories) { if (-not [IO.Directory]::Exists((Join-Path $Root $name))) { $issues.Add("Missing target directory: $name") } }
        try { $marker = Read-TargetMarker $Root } catch { $issues.Add($_.Exception.Message) }
        try { $manifest = Read-TargetManifest $Root } catch { $issues.Add($_.Exception.Message) }
        if ($null -ne $marker -and $null -ne $manifest) {
            foreach ($key in @('layout','layout_version','schema_version','migration_id','package_id','subject_id')) {
                $mv = [string]$marker[$key]; $fv = [string]$manifest.$key
                if ($mv -cne $fv) { $issues.Add("Marker/manifest mismatch: $key") }
            }
            if ([string]$marker['layout'] -ceq 'target') {
                foreach ($key in @('profile_version','progress_version','capture_mode','created_at','updated_at')) {
                    if (-not $marker.Contains($key) -or [string]::IsNullOrWhiteSpace([string]$marker[$key])) { $issues.Add("Formal target marker is missing compatibility field: $key") }
                }
                foreach ($key in @('last_confirmed_at','next_review_at','review_stage','last_interview_at','last_session_id','last_turn_id','last_capture_disclosed_at','last_capture_disclosed_mode')) {
                    if (-not $marker.Contains($key)) { $issues.Add("Formal target marker is missing compatibility field: $key") }
                }
                if ([string]$marker['schema_version'] -cne '3') { $issues.Add('Formal target marker schema_version must be 3') }
            }
        }
        Test-TargetTextFiles $Root $issues
    }
    $layout = if ($null -ne $marker) { [string]$marker['layout'] } else { '' }
    $migration = if ($null -ne $marker) { [string]$marker['migration_id'] } else { '' }
    $entryCount = 0
    # The machine index may be an older `items` projection.  Report the
    # authoritative markdown count consistently across adapters; index shape
    # is validated separately and can be rebuilt by rebuild-index.
    $indexPath = Join-Path $Root '权威\声明索引.json'
    if ([IO.File]::Exists($indexPath)) {
        try {
            $index = (Read-Text $indexPath) | ConvertFrom-Json -ErrorAction Stop
            if (-not (Has-JsonProperty $index 'entries') -and -not (Has-JsonProperty $index 'items') -and -not ($index -is [Array])) {
                $issues.Add('Authority index JSON must contain entries or items.')
            }
        } catch { $issues.Add('Invalid authority index JSON: 权威/声明索引.json') }
    }
    if ([IO.Directory]::Exists((Join-Path $Root '权威'))) {
        try { $entryCount = @(Get-ChildItem -LiteralPath (Join-Path $Root '权威') -Recurse -Force -File -Filter '*.md' | Where-Object { $_.Name -ne 'README.md' }).Count } catch {}
    }
    $fileCount = 0
    if ([IO.Directory]::Exists($Root)) { try { $fileCount = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File).Count } catch {} }
    return [ordered]@{
        'ok'=($issues.Count -eq 0); 'command'='target-validate'; 'root'=$Root; 'layout'=$layout;
        'migration_id'=$migration; 'layout_version'=$(if($null -ne $marker){[string]$marker['layout_version']}else{''});
        'schema_version'=$(if($null -ne $marker){[string]$marker['schema_version']}else{''});
        'package_id'=$(if($null -ne $marker){[string]$marker['package_id']}else{''});
        'subject_id'=$(if($null -ne $marker){[string]$marker['subject_id']}else{''});
        'pending_candidates'=$(if([IO.File]::Exists((Join-Path $Root '待确认信息.md'))){([regex]::Matches((Read-Text (Join-Path $Root '待确认信息.md')),'(?m)^## C-[0-9TZ-]+\s*$')).Count}else{0});
        'file_count'=$fileCount; 'authority_entry_count'=$entryCount;
        'issues'=$issues.ToArray()
    }
}

function Target-Validate([string]$Root) { return Invoke-WithProfileLock $Root { Target-Validate-Core $Root } }

function Get-TargetSourceSnapshot([string]$Root) {
    $state = Read-State (Join-Path $Root $script:StateFile)
    foreach ($key in @('profile_version','progress_version')) { if (-not $state.Contains($key)) { Fail "Source state missing $key." } }
    $profilePath = Join-Path $Root '个人全景档案.md'; $progressPath = Join-Path $Root '访谈进度.md'; $pendingPath = Join-Path $Root '待确认信息.md'
    foreach ($path in @($profilePath,$progressPath,$pendingPath)) { if (-not [IO.File]::Exists($path)) { Fail "Source file does not exist: $path" } }
    return [ordered]@{
        'profile_version'=[string]$state['profile_version']; 'progress_version'=[string](Get-EffectiveProgressVersion $Root $state);
        'profile_sha256'=(Get-Sha256Hex $profilePath); 'progress_sha256'=(Get-Sha256Hex $progressPath); 'pending_sha256'=(Get-Sha256Hex $pendingPath);
        'capture_mode'=[string]$state['capture_mode']; 'capture_strategy'=$(switch([string]$state['capture_mode']){'auto-stage'{'自动暂存'}'prompt'{'提示确认'}'explicit'{'仅显式'}default{''}});
        'last_capture_disclosed_at'=$(if($state.Contains('last_capture_disclosed_at')){[string]$state['last_capture_disclosed_at']}else{''});
        'last_capture_disclosed_mode'=$(if($state.Contains('last_capture_disclosed_mode')){[string]$state['last_capture_disclosed_mode']}else{''});
        'created_at'=[string]$state['created_at']; 'updated_at'=[string]$state['updated_at'];
        'review_stage'=[string]$state['review_stage']; 'next_review_at'=[string]$state['next_review_at'];
        'last_confirmed_at'=[string]$state['last_confirmed_at']; 'last_interview_at'=[string]$state['last_interview_at'];
        'last_session_id'=[string]$state['last_session_id']; 'last_turn_id'=[string]$state['last_turn_id']
    }
}

function Get-ManifestSource($Manifest) {
    if (-not (Has-JsonProperty $Manifest 'source') -or $null -eq $Manifest.source) { return $null }
    # Accept both the original migration draft's flat source fields and the
    # frozen protocol's grouped `{profile,progress,pending}` form.  Normalize
    # to one metadata-only object so fingerprints are compared identically.
    $source = $Manifest.source
    if ((Has-JsonProperty $source 'profile') -and $null -ne $source.profile) {
        # Avoid PowerShell's automatic `$PROFILE` variable (case-insensitive)
        # when naming the nested source objects.
        $profileSource = $source.profile; $progressSource = $source.progress; $pendingSource = $source.pending
        return [ordered]@{
            'profile_version'=$(if((Has-JsonProperty $profileSource 'version')){[string]$profileSource.version}else{''});
            'progress_version'=$(if((Has-JsonProperty $progressSource 'version')){[string]$progressSource.version}else{''});
            'profile_sha256'=$(if((Has-JsonProperty $profileSource 'sha256')){[string]$profileSource.sha256}else{''});
            'progress_sha256'=$(if((Has-JsonProperty $progressSource 'sha256')){[string]$progressSource.sha256}else{''});
            'pending_sha256'=$(if(($null -ne $pendingSource) -and (Has-JsonProperty $pendingSource 'sha256')){[string]$pendingSource.sha256}else{''})
        }
    }
    return $source
}

function Assert-TargetMatchesSource([string]$SourceRoot,[string]$TargetRoot,[bool]$RequireDraft=$false) {
    $valid = Target-Validate-Core $TargetRoot
    if (-not $valid.ok) { Fail ('Invalid target package: ' + ($valid.issues -join '; ')) }
    $marker = Read-TargetMarker $TargetRoot; $manifest = Read-TargetManifest $TargetRoot
    if ($RequireDraft -and [string]$marker['layout'] -cne 'target-draft') { Fail 'migrate-apply requires a target-draft root.' }
    $source = Get-TargetSourceSnapshot $SourceRoot; $manifestSource = Get-ManifestSource $manifest
    if ($null -eq $manifestSource) { Fail 'Target manifest does not contain source fingerprints.' }
    foreach ($key in @('profile_version','progress_version','profile_sha256','progress_sha256','pending_sha256')) {
        if (-not (Has-JsonProperty $manifestSource $key)) { Fail "Target manifest source missing $key." }
        if ([string]$manifestSource.$key -cne [string]$source[$key]) { Fail "Source/target conflict: $key differs; regenerate the migration plan." }
    }
    return [ordered]@{'marker'=$marker;'manifest'=$manifest;'source'=$source}
}

function Require-ActiveLayout([string]$Root,[System.Collections.IDictionary]$State,[string]$Operation) {
    $layout = if ($State.Contains('layout')) { [string]$State['layout'] } else { 'compatibility' }
    if ($layout -ceq 'target-draft') { Fail "$Operation cannot write a target-draft package; run migrate-apply/switch-layout after confirmation." }
    if (@('compatibility','target','') -cnotcontains $layout) { Fail "Unsupported profile layout for ${Operation}: $layout" }
}

function Validate-Space-Core([string]$Root, [bool]$IgnoreTransaction = $false) {
    # A target-draft is intentionally not accepted by the compatibility
    # validator; callers must use target-validate until the package is
    # explicitly promoted.  A formal target is validated by the schema-3
    # contract and never interpreted as a schema-2 profile by accident.
    $targetMarker = Get-TargetMarkerIfPresent $Root
    if ($null -ne $targetMarker) {
        if ([string]$targetMarker['layout'] -ceq 'target-draft') {
            return [ordered]@{'ok'=$false;'command'='validate';'root'=$Root;'issues'=@('Target draft requires target-validate; it is not a schema-2 profile space.')}
        }
        if ([string]$targetMarker['layout'] -ceq 'target') {
            $targetResult = Target-Validate-Core $Root
            $targetResult['command'] = 'validate'
            return $targetResult
        }
    }
    $issues = New-Object Collections.Generic.List[string]; $state = $null
    if (-not [IO.Directory]::Exists($Root)) { $issues.Add('Root directory does not exist') }
    else {
        if (-not $IgnoreTransaction -and [IO.File]::Exists((Join-Path $Root $script:TransactionFile))) { $issues.Add('Interrupted transaction exists; run recover --confirmed --root <authorized-root>') }
        foreach ($name in $script:Files) { if (-not [IO.File]::Exists((Join-Path $Root $name))) { $issues.Add("Missing file: $name") } }
        foreach ($name in $script:Directories) { if (-not [IO.Directory]::Exists((Join-Path $Root $name))) { $issues.Add("Missing directory: $name") } }
        $statePath = Join-Path $Root $script:StateFile
        if (-not [IO.File]::Exists($statePath)) { $issues.Add("Missing file: $($script:StateFile)") }
        else { try { $state = Read-State $statePath; foreach ($issue in (Test-State $state)) { $issues.Add($issue) } } catch { $issues.Add($_.Exception.Message) } }
        if ($null -ne $state -and (Test-State $state).Count -eq 0) {
            try {
                foreach ($issue in (Test-ProfileContent (Read-Text (Join-Path $Root '个人全景档案.md')) ([string]$state['profile_version']))) { $issues.Add($issue) }
                foreach ($issue in (Test-ProgressContent (Read-Text (Join-Path $Root '访谈进度.md')) (Get-EffectiveProgressVersion $Root $state) ($state['schema_version'] -ceq '2'))) { $issues.Add($issue) }
                foreach ($issue in (Test-LogContent (Read-Text (Join-Path $Root '迭代日志.md')) ([string]$state['profile_version']))) { $issues.Add($issue) }
                $candidateIds = @([regex]::Matches((Read-Text (Join-Path $Root '待确认信息.md')), '(?m)^## (C-[0-9TZ-]+)\s*$') | ForEach-Object { $_.Groups[1].Value })
                if (($candidateIds | Select-Object -Unique).Count -ne $candidateIds.Count) { $issues.Add('Pending candidates contain duplicate ids') }
            } catch { $issues.Add($_.Exception.Message) }
        }
    }
    return @{'ok'=($issues.Count -eq 0);'command'='validate';'root'=$Root;'issues'=$issues.ToArray()}
}

function Validate-Space([string]$Root, [bool]$IgnoreTransaction = $false) {
    return Invoke-WithProfileLock $Root { Validate-Space-Core $Root $IgnoreTransaction }
}

function Require-Valid([string]$Root) {
    $result = Validate-Space $Root
    if (-not $result.ok) { Fail ('Invalid profile space: ' + ($result.issues -join '; ')) }
    return Read-State (Join-Path $Root $script:StateFile)
}

function Get-ProgressSummary([string]$Content) {
    $stage = [regex]::Match($Content, '(?m)^- 当前阶段：(.+)$').Groups[1].Value.Trim()
    $last = [regex]::Match($Content, '(?m)^- 最近正式访谈时间：(.+)$').Groups[1].Value.Trim()
    $next = ''; $match = [regex]::Match($Content, '(?ms)^## 下次问题\s*\n+(.+?)(?=^## |\z)')
    if ($match.Success) { $next = @($match.Groups[1].Value -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[0].Trim() }
    return @{'current_stage'=$stage;'last_interview_at'=$last;'next_question'=$next}
}

function Get-ProgressBacklog([string]$Content) {
    $baseline = New-Object Collections.Generic.List[string]; $long = New-Object Collections.Generic.List[string]; $bucket = ''
    foreach ($line in ($Content -split "`r?`n")) {
        if ($line.Trim() -ceq '### 基线必答（阻塞基线收口）') { $bucket = 'baseline' }
        elseif ($line.Trim() -ceq '### 可长期补充（不阻塞基线收口）') { $bucket = 'long' }
        elseif ($line.StartsWith('### ') -or $line.StartsWith('## ')) { $bucket = '' }
        elseif ($line.StartsWith('- ') -and $bucket) { if ($bucket -ceq 'baseline') { $baseline.Add($line.Substring(2).Trim()) } else { $long.Add($line.Substring(2).Trim()) } }
    }
    return @{'baseline_required_remaining'=$baseline.ToArray();'long_term_backlog'=$long.ToArray()}
}

function Test-ProgressBuckets([string]$Content) {
    foreach ($heading in @('### 基线必答（阻塞基线收口）', '### 可长期补充（不阻塞基线收口）')) {
        if ((Count-Matches $Content ('(?m)^' + [regex]::Escape($heading) + '$')) -cne 1) { return $false }
    }
    return $true
}

function Get-TargetStatus-Core([string]$Root) {
    $valid = Target-Validate-Core $Root
    if (-not $valid.ok) { return @{'payload'=@{'ok'=$false;'command'='status';'root'=$Root;'layout'='target';'issues'=$valid.issues};'code'=1} }
    $marker = Read-TargetMarker $Root
    $manifest = Read-TargetManifest $Root
    $pending = 0; $pendingPath = Join-Path $Root '待确认信息.md'
    if ([IO.File]::Exists($pendingPath)) { $pending = ([regex]::Matches((Read-Text $pendingPath), '(?m)^## C-[0-9TZ-]+\s*$')).Count }
    $progressSummary = @{'current_stage'='';'last_interview_at'='';'next_question'=''}
    $progressPath = Join-Path $Root '访谈进度.md'
    # Target status is metadata-only. Do not expose the interview's next
    # question (or any other body text) merely to report capture policy.
    # Formal target status is metadata-only: never infer cursor timestamps
    # from the compatibility progress projection.  The marker is the single
    # source of the schema-3 resume cursor across adapters.
    $progressSummary.current_stage = '目标资料包'
    if ($marker.Contains('last_interview_at')) { $progressSummary.last_interview_at = [string]$marker['last_interview_at'] }
    $captureMode = if ($marker.Contains('capture_mode')) { [string]$marker['capture_mode'] } elseif (Has-JsonProperty $manifest 'capture_policy_snapshot') { [string]$manifest.capture_policy_snapshot.capture_mode } else { '' }
    $strategy = @{ 'auto-stage'='自动暂存'; 'prompt'='提示确认'; 'explicit'='仅显式' }[$captureMode]
    if ($null -eq $strategy) { $strategy = '' }
    $disclosed = if ($marker.Contains('last_capture_disclosed_at')) { [string]$marker['last_capture_disclosed_at'] } elseif (Has-JsonProperty $manifest 'capture_policy_snapshot') { [string]$manifest.capture_policy_snapshot.last_capture_disclosed_at } else { '' }
    $disclosedMode = if ($marker.Contains('last_capture_disclosed_mode')) { [string]$marker['last_capture_disclosed_mode'] } elseif (Has-JsonProperty $manifest 'capture_policy_snapshot') { [string]$manifest.capture_policy_snapshot.last_capture_disclosed_mode } else { '' }
    $source = Get-ManifestSource $manifest
    $profileVersion = if ($null -ne $source) { [string]$source.profile_version } else { '' }
    $progressVersion = if ($null -ne $source) { [string]$source.progress_version } else { '' }
    $baseline = New-Object Collections.Generic.List[string]; $long = New-Object Collections.Generic.List[string]; $splitUnknown = $false
    $matrixPath = Join-Path $Root '主题覆盖矩阵.md'
    if ([IO.File]::Exists($matrixPath)) {
        foreach ($line in (Read-Text $matrixPath) -split "`r?`n") {
            if (-not $line.Trim().StartsWith('|')) { continue }
            $cells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
            if ($cells.Count -lt 4) { continue }
            $topicId = ([string]$cells[0]).Trim('`').Trim()
            $priority = ([string]$cells[2]).Trim('`').Trim()
            $stateText = ([string]$cells[3]).Trim('`').Trim()
            if ([string]::IsNullOrWhiteSpace($topicId) -or $topicId -in @('主题 ID','topic_id','---','-') -or $topicId -match '^[-:]+$') { continue }
            if ($priority -in @('基线必答','baseline','基线')) { $splitUnknown = $false; if ($stateText -notmatch '^(confirmed_minimum|deepened|declined|not_applicable)$') { $baseline.Add("$topicId（$stateText）") } }
            elseif ($priority -in @('可长期补充','long-term','long')) { $splitUnknown = $false; if ($stateText -notmatch '^(confirmed_minimum|deepened|declined|not_applicable)$') { $long.Add("$topicId（$stateText）") } }
        }
        if ($baseline.Count -eq 0 -and $long.Count -eq 0 -and ((Read-Text $matrixPath) -notmatch '(?m)^\|.*\|.*\|.*\|')) { $splitUnknown = $true }
    } else { $splitUnknown = $true }
    if ($splitUnknown) { $baseline.Add('legacy-unclassified（需先完成基线/长期分组）') }
    $authorityStatus = if ($marker.Contains('authority_status')) { [string]$marker['authority_status'] } elseif (Has-JsonProperty $manifest 'authority_status') { [string]$manifest.authority_status } else { '' }
    if ($authorityStatus -in @('non-authoritative-needs-user-confirmation','active-layout-needs-review')) {
        $baseline.Add('migration-review（需用户确认目录化切换）')
    }
    $payload = [ordered]@{
        'ok'=$true;'command'='status';'root'=$Root;'layout'='target';'layout_version'=[string]$marker['layout_version'];'schema_version'=[string]$marker['schema_version'];
        'migration_id'=[string]$marker['migration_id'];'package_id'=[string]$marker['package_id'];'subject_id'=[string]$marker['subject_id'];
        'profile_version'=$profileVersion;'progress_version'=$progressVersion;'capture_mode'=$captureMode;'capture_strategy'=$strategy;
        'last_capture_disclosed_at'=$disclosed;'last_capture_disclosed_mode'=$disclosedMode;'review_stage'=$(if($marker.Contains('review_stage')){[string]$marker['review_stage']}else{'baseline'});
        'last_confirmed_at'=$(if($marker.Contains('last_confirmed_at')){[string]$marker['last_confirmed_at']}else{''});'next_review_at'=$(if($marker.Contains('next_review_at')){[string]$marker['next_review_at']}else{''});
        'last_session_id'=$(if($marker.Contains('last_session_id')){[string]$marker['last_session_id']}else{''});'last_turn_id'=$(if($marker.Contains('last_turn_id')){[string]$marker['last_turn_id']}else{''});
        'pending_candidates'=$pending;'baseline_required_remaining'=$baseline.ToArray();'baseline_closure_blocked'=($baseline.Count -gt 0 -or $splitUnknown);'baseline_split_unknown'=$splitUnknown;
        'long_term_backlog'=$long.ToArray();'authority_entry_count'=$valid.authority_entry_count;'file_count'=$valid.file_count;
        'progress'=$progressSummary
    }
    return @{'payload'=$payload;'code'=0}
}

function Get-Status-Core([string]$Root) {
    $targetMarker = Get-TargetMarkerIfPresent $Root
    if ($null -ne $targetMarker -and [string]$targetMarker['layout'] -ceq 'target') { return Get-TargetStatus-Core $Root }
    $valid = Validate-Space $Root
    if (-not $valid.ok) { return @{'payload'=@{'ok'=$false;'command'='status';'root'=$Root;'issues'=$valid.issues};'code'=1} }
    $state = Read-State (Join-Path $Root $script:StateFile)
    $pending = ([regex]::Matches((Read-Text (Join-Path $Root '待确认信息.md')), '(?m)^## C-[0-9TZ-]+\s*$')).Count
    $progressSummary = Get-ProgressSummary (Read-Text (Join-Path $Root '访谈进度.md'))
    if ([string]::IsNullOrWhiteSpace($progressSummary.current_stage)) { $progressSummary.current_stage = @{ baseline='基线访谈'; 'first-review'='首次回访'; stable='稳定维护' }[[string]$state['review_stage']] }
    if ([string]::IsNullOrWhiteSpace($progressSummary.last_interview_at)) { $progressSummary.last_interview_at = [string]$state['last_interview_at']; if ([string]::IsNullOrWhiteSpace($progressSummary.last_interview_at) -and -not [string]::IsNullOrWhiteSpace($state['last_turn_id'])) { $progressSummary.last_interview_at = [string]$state['updated_at'] } }
    $progressContent = Read-Text (Join-Path $Root '访谈进度.md')
    $backlog = Get-ProgressBacklog $progressContent
    $baselineSplitUnknown = ([string]$state['schema_version'] -cne '2') -or (-not (Test-ProgressBuckets $progressContent))
    if ($baselineSplitUnknown) { $backlog.baseline_required_remaining = @('legacy-unclassified（需先完成基线/长期分组）') }
    $strategy = @{ 'auto-stage'='自动暂存'; 'prompt'='提示确认'; 'explicit'='仅显式' }[[string]$state['capture_mode']]
    $disclosed = if ($state.Contains('last_capture_disclosed_at')) { [string]$state['last_capture_disclosed_at'] } else { '' }
    $lastSession = if ($state.Contains('last_session_id')) { [string]$state['last_session_id'] } else { '' }
    $lastTurn = if ($state.Contains('last_turn_id')) { [string]$state['last_turn_id'] } else { '' }
    $payload = @{
        'ok'=$true;'command'='status';'root'=$Root;'profile_version'=[string]$state['profile_version'];
        'progress_version'=[string](Get-EffectiveProgressVersion $Root $state);'capture_mode'=$state['capture_mode'];'capture_strategy'=$strategy;'last_capture_disclosed_at'=$disclosed;
        'last_capture_disclosed_mode'=$(if($state.Contains('last_capture_disclosed_mode')){[string]$state['last_capture_disclosed_mode']}else{''});'review_stage'=$state['review_stage'];
        'last_confirmed_at'=$state['last_confirmed_at'];'next_review_at'=$state['next_review_at'];'last_session_id'=$lastSession;'last_turn_id'=$lastTurn;'pending_candidates'=$pending;
        'baseline_required_remaining'=$backlog.baseline_required_remaining;'baseline_closure_blocked'=($backlog.baseline_required_remaining.Count -gt 0);'baseline_split_unknown'=$baselineSplitUnknown;'long_term_backlog'=$backlog.long_term_backlog;
        'progress'=$progressSummary
    }
    return @{'payload'=$payload;'code'=0}
}

function Get-Status([string]$Root) {
    return Invoke-WithProfileLock $Root { Get-Status-Core $Root }
}

function Write-KeyValues([string]$Path,[System.Collections.IDictionary]$Values) {
    $builder = New-Object Text.StringBuilder
    foreach ($key in $Values.Keys) {
        $keyText = [string]$key; $valueText = [string]$Values[$key]
        if ($keyText -notmatch '^[A-Za-z0-9_.-]+$' -or $valueText -match '[\r\n]') { Fail "Invalid key-value marker field: $keyText" }
        [void]$builder.Append($keyText).Append('=').Append($valueText).Append("`n")
    }
    Write-Atomic $Path $builder.ToString()
}

function Copy-TargetTree([string]$Source,[string]$Destination,[string[]]$ExcludePrefixes=@()) {
    if (-not [IO.Directory]::Exists($Source)) { Fail "Target source directory does not exist: $Source" }
    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    $sourceFull = [IO.Path]::GetFullPath($Source).TrimEnd('\')
    foreach ($directory in @(Get-ChildItem -LiteralPath $Source -Recurse -Force -Directory -ErrorAction Stop)) {
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Fail "Reparse point is not allowed: $($directory.FullName)" }
        $relativeDir = Get-RelativePath $Source $directory.FullName
        $skipDir = $false
        foreach ($prefix in $ExcludePrefixes) {
            $p = [string]$prefix
            if ($relativeDir.Equals($p,[StringComparison]::OrdinalIgnoreCase) -or $relativeDir.StartsWith($p.TrimEnd('/') + '/',[StringComparison]::OrdinalIgnoreCase)) { $skipDir = $true; break }
        }
        if (-not $skipDir) { [IO.Directory]::CreateDirectory((Join-Path $Destination ($relativeDir -replace '/','\'))) | Out-Null }
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $Source -Recurse -Force -File -ErrorAction Stop)) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Fail "Reparse point is not allowed: $($file.FullName)" }
        $relative = Get-RelativePath $Source $file.FullName
        $skip = $false
        foreach ($prefix in $ExcludePrefixes) {
            $p = [string]$prefix
            if ($relative.Equals($p,[StringComparison]::OrdinalIgnoreCase) -or $relative.StartsWith($p.TrimEnd('/') + '/',[StringComparison]::OrdinalIgnoreCase)) { $skip = $true; break }
        }
        if ($skip) { continue }
        $destinationPath = Join-Path $Destination ($relative -replace '/','\')
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destinationPath)) | Out-Null
        [IO.File]::Copy($file.FullName,$destinationPath,$true)
    }
}

function Set-TargetMarkerValues([string]$Root,[hashtable]$Changes) {
    $path = Join-Path $Root $script:StateFile; $values = Read-KeyValues $path
    foreach ($key in $Changes.Keys) { if ($values.Contains($key)) { $values[$key] = [string]$Changes[$key] } else { $values.Add($key,[string]$Changes[$key]) } }
    Write-KeyValues $path $values
    return $values
}

function Promote-TargetPackage([string]$Root,[string]$AuthorityStatus='active-pending-review',[System.Collections.IDictionary]$CompatibilityState=$null) {
    $marker = Read-TargetMarker $Root
    $manifest = Read-TargetManifest $Root
    $now = Utc-Now
    $sourceMeta = Get-ManifestSource $manifest
    $policy = if (Has-JsonProperty $manifest 'capture_policy_snapshot') { $manifest.capture_policy_snapshot } else { $null }
    $captureMode = if ($null -ne $policy -and (Has-JsonProperty $policy 'capture_mode')) { [string]$policy.capture_mode } elseif ($marker.Contains('capture_mode')) { [string]$marker['capture_mode'] } else { '' }
    if ([string]::IsNullOrWhiteSpace($captureMode)) { $captureMode = 'prompt' }
    $captureStrategy = switch($captureMode) { 'auto-stage' {'自动暂存'} 'prompt' {'提示确认'} 'explicit' {'仅显式'} default { '' } }
    $createdAt = if ($marker.Contains('created_at')) { [string]$marker['created_at'] } elseif ($marker.Contains('generated_at')) { [string]$marker['generated_at'] } elseif (Has-JsonProperty $manifest 'generated_at') { [string]$manifest.generated_at } else { $now }
    if ([string]::IsNullOrWhiteSpace($createdAt)) { $createdAt = $now }
    $disclosedAt = if ($null -ne $policy -and (Has-JsonProperty $policy 'last_capture_disclosed_at')) { [string]$policy.last_capture_disclosed_at } elseif ($marker.Contains('last_capture_disclosed_at')) { [string]$marker['last_capture_disclosed_at'] } else { '' }
    $disclosedMode = if ($null -ne $policy -and (Has-JsonProperty $policy 'last_capture_disclosed_mode')) { [string]$policy.last_capture_disclosed_mode } elseif ($marker.Contains('last_capture_disclosed_mode')) { [string]$marker['last_capture_disclosed_mode'] } else { '' }
    $compat = if ($null -ne $CompatibilityState) { $CompatibilityState } else { @{} }
    $compatValue = {
        param([string]$Key,[string]$Fallback='')
        if ($compat.Contains($Key)) { return [string]$compat[$Key] }
        return $Fallback
    }
    [void](Set-TargetMarkerValues $Root @{
        'layout'='target'; 'layout_version'='1'; 'schema_version'='3';
        'authority_status'=$AuthorityStatus; 'activated_at'=$now;
        'profile_version'=$(if($null -ne $sourceMeta){[string]$sourceMeta.profile_version}else{[string]$marker['source_profile_version']});
        'progress_version'=$(if($null -ne $sourceMeta){[string]$sourceMeta.progress_version}else{[string]$marker['source_progress_version']});
        'capture_mode'=$captureMode; 'capture_strategy'=$captureStrategy; 'created_at'=$createdAt; 'updated_at'=$now;
        'last_confirmed_at'=&$compatValue 'last_confirmed_at';
        'next_review_at'=&$compatValue 'next_review_at';
        'review_stage'=&$compatValue 'review_stage' 'baseline';
        'last_interview_at'=&$compatValue 'last_interview_at';
        'last_session_id'=&$compatValue 'last_session_id';
        'last_turn_id'=&$compatValue 'last_turn_id';
        'last_capture_disclosed_at'=$disclosedAt; 'last_capture_disclosed_mode'=$disclosedMode
    })
    $manifest.layout = 'target'; $manifest.layout_version = 1; $manifest.schema_version = '3'
    if (Has-JsonProperty $manifest 'authority_status') { $manifest.authority_status = $AuthorityStatus } else { $manifest | Add-Member -NotePropertyName authority_status -NotePropertyValue $AuthorityStatus }
    if (-not (Has-JsonProperty $manifest 'activated_at')) { $manifest | Add-Member -NotePropertyName activated_at -NotePropertyValue $now } else { $manifest.activated_at = $now }
    if (-not (Has-JsonProperty $manifest 'capture_policy_snapshot')) {
        $manifest | Add-Member -NotePropertyName capture_policy_snapshot -NotePropertyValue ([pscustomobject]@{capture_mode=$captureMode;capture_strategy=$captureStrategy;last_capture_disclosed_at=$disclosedAt;last_capture_disclosed_mode=$disclosedMode})
    } else {
        if (Has-JsonProperty $manifest.capture_policy_snapshot 'capture_mode') { $manifest.capture_policy_snapshot.capture_mode = $captureMode } else { $manifest.capture_policy_snapshot | Add-Member -NotePropertyName capture_mode -NotePropertyValue $captureMode }
        if (Has-JsonProperty $manifest.capture_policy_snapshot 'capture_strategy') { $manifest.capture_policy_snapshot.capture_strategy = $captureStrategy } else { $manifest.capture_policy_snapshot | Add-Member -NotePropertyName capture_strategy -NotePropertyValue $captureStrategy }
        if (Has-JsonProperty $manifest.capture_policy_snapshot 'last_capture_disclosed_at') { $manifest.capture_policy_snapshot.last_capture_disclosed_at = $disclosedAt } else { $manifest.capture_policy_snapshot | Add-Member -NotePropertyName last_capture_disclosed_at -NotePropertyValue $disclosedAt }
        if (Has-JsonProperty $manifest.capture_policy_snapshot 'last_capture_disclosed_mode') { $manifest.capture_policy_snapshot.last_capture_disclosed_mode = $disclosedMode } else { $manifest.capture_policy_snapshot | Add-Member -NotePropertyName last_capture_disclosed_mode -NotePropertyValue $disclosedMode }
    }
    $manifestText = (($manifest | ConvertTo-Json -Depth 40) -replace "`r`n", "`n") + "`n"
    Write-Atomic (Join-Path $Root 'manifest.json') $manifestText
    return Read-TargetMarker $Root
}

function New-TargetDraft([string]$SourceRoot,[string]$TargetRoot,[string]$MigrationId,$Source) {
    if ([IO.Directory]::Exists($TargetRoot)) {
        $existing = @(Get-ChildItem -LiteralPath $TargetRoot -Force -ErrorAction Stop | Where-Object { $_.Name -notin @('.hello-lock','.hello-transaction','.hello-layout-transaction') })
        if ($existing.Count -gt 0) { Fail 'Target destination already exists and is not empty.' }
    } else {
        [IO.Directory]::CreateDirectory($TargetRoot) | Out-Null
    }
    foreach ($directory in @('原始访谈','来源','权威','派生','历史版本','.backups','.trash')) {
        [IO.Directory]::CreateDirectory((Join-Path $TargetRoot $directory)) | Out-Null
    }
    $now = Utc-Now
    $package = 'pkg-' + $MigrationId
    $subject = 'subject-local'
    $marker = [ordered]@{
        layout='target-draft'; layout_version='1'; schema_version='target-draft-0.1';
        migration_id=$MigrationId; package_id=$package; subject_id=$subject;
        source_profile_version=[string]$Source.profile_version; source_progress_version=[string]$Source.progress_version;
        source_profile_sha256=[string]$Source.profile_sha256; source_progress_sha256=[string]$Source.progress_sha256;
        source_pending_sha256=[string]$Source.pending_sha256; generated_at=$now;
        authority_status='non-authoritative-needs-user-confirmation'
    }
    $markerText = (($marker.Keys | ForEach-Object { "$_=$($marker[$_])" }) -join "`n") + "`n"
    Write-Atomic (Join-Path $TargetRoot $script:StateFile) $markerText
    $sourceManifest = [ordered]@{
        profile=[ordered]@{path='个人全景档案.md';version=[string]$Source.profile_version;sha256=[string]$Source.profile_sha256};
        progress=[ordered]@{path='访谈进度.md';version=[string]$Source.progress_version;sha256=[string]$Source.progress_sha256};
        pending=[ordered]@{path='待确认信息.md';sha256=[string]$Source.pending_sha256}
    }
    $manifest = [ordered]@{
        layout='target-draft'; layout_version=1; schema_version='target-draft-0.1'; migration_id=$MigrationId;
        package_id=$package; subject_id=$subject; owner='local-owner'; audience='owner-and-authorized-ai';
        language='zh-CN'; generated_at=$now; authority_status='non-authoritative-needs-user-confirmation'; source=$sourceManifest;
        capture_policy_snapshot=[ordered]@{
            capture_mode=[string]$Source.capture_mode; capture_strategy=[string]$Source.capture_strategy;
            last_capture_disclosed_at=[string]$Source.last_capture_disclosed_at;
            last_capture_disclosed_mode=[string]$Source.last_capture_disclosed_mode
        }
    }
    Write-Atomic (Join-Path $TargetRoot 'manifest.json') (($manifest | ConvertTo-Json -Depth 20) + "`n")
    $minimal = @{
        'README.md'="# 个人资料包`n`n此目录由 hello 目标布局协议创建。`n";
        '个人全景档案.md'="# 个人全景档案`n`n> 本文件是目录化资料包的聚合入口；详细内容以权威实体为准。`n";
        '主题覆盖矩阵.md'="# 主题覆盖矩阵`n`n> 覆盖状态由权威条目和用户确认维护。`n`n## 基线必答（阻塞基线收口）`n`n- situation（待确认）`n- chapters（待确认）`n- work（待确认）`n- capability（待确认）`n`n## 可长期补充（不阻塞基线收口）`n`n- 其余主题按需补充。`n";
        '迁移映射.md'="# 迁移映射`n`n- 状态：待用户确认。`n- 详细来源映射由迁移工具维护。`n";
        '资料索引.md'="# 资料索引`n`n- 布局：target-draft`n- 由目标协议维护。`n";
        '迭代日志.md'="# 迭代日志`n`n- 迁移草稿尚未产生正式迭代。`n"
    }
    foreach ($name in $minimal.Keys) { Write-Atomic (Join-Path $TargetRoot $name) $minimal[$name] }
    foreach ($name in @('待确认信息.md','访谈进度.md')) {
        $sourcePath = Join-Path $SourceRoot $name
        if ([IO.File]::Exists($sourcePath)) { Write-Atomic (Join-Path $TargetRoot $name) (Read-Text $sourcePath) }
        else { Write-Atomic (Join-Path $TargetRoot $name) "# $name`n" }
    }
    $migration = [ordered]@{migration_id=$MigrationId;layout='target-draft';source=$sourceManifest;generated_at=$now}
    Write-Atomic (Join-Path $TargetRoot 'migration-manifest.json') (($migration | ConvertTo-Json -Depth 20) + "`n")
}

function Get-TargetPlan([string]$SourceRoot,[string]$TargetRoot,[string]$MigrationId,[bool]$Confirmed=$false) {
    if (-not (Test-SafeMigrationId $MigrationId)) { Fail 'migration-id is invalid.' }
    Assert-IndependentRoots $SourceRoot $TargetRoot
    $sourceValid = Validate-Space $SourceRoot
    if (-not $sourceValid.ok) { Fail ('Invalid source profile space: ' + ($sourceValid.issues -join '; ')) }
    $source = Get-TargetSourceSnapshot $SourceRoot
    $targetExists = [IO.Directory]::Exists($TargetRoot)
    $created = $false
    if (-not $targetExists -and $Confirmed) {
        Require-Confirmed $Confirmed
        New-TargetDraft $SourceRoot $TargetRoot $MigrationId $source
        $targetExists = $true
        $created = $true
    }
    $targetValid = $null; $targetLayout = ''
    if ($targetExists) {
        $targetValid = Target-Validate-Core $TargetRoot
        $targetMarker = Get-TargetMarkerIfPresent $TargetRoot
        if ($null -ne $targetMarker) { $targetLayout = [string]$targetMarker['layout'] }
    }
    return [ordered]@{
        'ok'=($null -eq $targetValid -or [bool]$targetValid.ok); 'command'='migrate-plan';
        'source_root'=$SourceRoot;'target_root'=$TargetRoot;'migration_id'=$MigrationId;
        'source_profile_version'=$source.profile_version;'source_progress_version'=$source.progress_version;
        'source_profile_sha256'=$source.profile_sha256;'source_progress_sha256'=$source.progress_sha256;'source_pending_sha256'=$source.pending_sha256;
        'target_exists'=$targetExists;'target_layout'=$targetLayout;
        'target_issues'=($(if($null -ne $targetValid){$targetValid.issues}else{@()}));
        'created'=$created;
        'mapping_ready'=($targetExists -and ($null -eq $targetValid -or [bool]$targetValid.ok))
    }
}

function Migrate-Plan([string]$SourceRoot,[string]$TargetRoot,[string]$MigrationId,[bool]$Confirmed=$false) {
    return Get-TargetPlan $SourceRoot $TargetRoot $MigrationId $Confirmed
}

function Migrate-Apply-Core([string]$SourceRoot,[string]$TargetRoot,[string]$Destination,[string]$ExpectedVersion,[string]$ExpectedProgressVersion,[bool]$Confirmed,[bool]$SimulateFailure=$false) {
    Require-Confirmed $Confirmed
    if (-not (Test-PositiveDecimal $ExpectedVersion) -or -not (Test-PositiveDecimal $ExpectedProgressVersion)) { Fail 'Expected versions must be positive decimal integers.' }
    Assert-IndependentRoots $SourceRoot $TargetRoot
    Assert-IndependentRoots $SourceRoot $Destination
    $sourceValid = Validate-Space $SourceRoot
    if (-not $sourceValid.ok) { Fail ('Invalid source profile space: ' + ($sourceValid.issues -join '; ')) }
    $source = Get-TargetSourceSnapshot $SourceRoot
    $sourceState = Read-State (Join-Path $SourceRoot $script:StateFile)
    if ($source.profile_version -cne $ExpectedVersion) { Fail "Version conflict: expected $ExpectedVersion, current $($source.profile_version)." }
    if ($source.progress_version -cne $ExpectedProgressVersion) { Fail "Progress version conflict: expected $ExpectedProgressVersion, current $($source.progress_version)." }
    $targetInfo = Assert-TargetMatchesSource $SourceRoot $TargetRoot $true
    $marker = $targetInfo.marker; $manifest = $targetInfo.manifest
    if ([string]$marker['migration_id'] -cne [string]$manifest.migration_id) { Fail 'Target marker/manifest migration_id mismatch.' }
    $destinationFull = [IO.Path]::GetFullPath($Destination)
    $targetFull = [IO.Path]::GetFullPath($TargetRoot)
    # Promoting the already-reviewed draft in place is safe and avoids an
    # unnecessary second copy of sensitive material.  It still uses atomic
    # marker/manifest writes and revalidates the result.
    if ($destinationFull.Equals($targetFull,[StringComparison]::OrdinalIgnoreCase)) {
        $promoted = Promote-TargetPackage $TargetRoot 'active-pending-review' $sourceState
        if ($SimulateFailure) { Fail 'simulated failure during target promotion' }
        $after = Target-Validate-Core $TargetRoot
        if (-not $after.ok) { Fail ('Target promotion validation failed: ' + ($after.issues -join '; ')) }
        return [ordered]@{'ok'=$true;'command'='migrate-apply';'source_root'=$SourceRoot;'target_root'=$TargetRoot;'destination'=$TargetRoot;'migration_id'=$marker['migration_id'];'layout'='target';'promoted_in_place'=$true;'source_unchanged'=$true}
    }
    if ([IO.Directory]::Exists($destinationFull) -or [IO.File]::Exists($destinationFull)) { Fail 'Destination must not already exist; choose a new formal target path.' }
    $parent = [IO.Path]::GetDirectoryName($destinationFull)
    if ([string]::IsNullOrWhiteSpace($parent)) { Fail 'Destination must have a parent directory.' }
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $temporary = Join-Path $parent ('.hello-target-promote-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        Copy-TargetTree $TargetRoot $temporary @('.hello-lock','.hello-transaction','.hello-layout-transaction')
        [void](Promote-TargetPackage $temporary 'active-pending-review' $sourceState)
        if ($SimulateFailure) { Fail 'simulated failure during target copy' }
        $check = Target-Validate-Core $temporary
        if (-not $check.ok) { Fail ('Promoted target validation failed: ' + ($check.issues -join '; ')) }
        [IO.Directory]::Move($temporary,$destinationFull)
    } catch { if ([IO.Directory]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue }; throw }
    return [ordered]@{'ok'=$true;'command'='migrate-apply';'source_root'=$SourceRoot;'target_root'=$TargetRoot;'destination'=$destinationFull;'migration_id'=$marker['migration_id'];'layout'='target';'promoted_in_place'=$false;'source_unchanged'=$true}
}

function Migrate-Apply([string]$SourceRoot,[string]$TargetRoot,[string]$Destination,[string]$ExpectedVersion,[string]$ExpectedProgressVersion,[bool]$Confirmed,[bool]$SimulateFailure=$false) {
    # Source is read-only; only the destination (or explicitly named draft in
    # the in-place promotion case) is mutated.  Locking the source prevents a
    # concurrent schema-2 write from invalidating the fingerprint mid-copy.
    return Invoke-WithProfileLock $SourceRoot { Migrate-Apply-Core $SourceRoot $TargetRoot $Destination $ExpectedVersion $ExpectedProgressVersion $Confirmed $SimulateFailure }
}

function Get-StringSha256Hex([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash($script:Utf8.GetBytes($Text))
        return ([BitConverter]::ToString($digest).Replace('-', '')).ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Split-TargetYamlValues([string]$Raw) {
    $value = if ($null -eq $Raw) { '' } else { [string]$Raw.Trim() }
    $parts = New-Object Collections.Generic.List[string]
    $builder = New-Object Text.StringBuilder
    $quote = [char]0; $depth = 0
    foreach ($character in $value.ToCharArray()) {
        if ($quote -ne [char]0) {
            [void]$builder.Append($character)
            if ($character -eq $quote) { $quote = [char]0 }
            continue
        }
        if ($character -eq [char]39 -or $character -eq [char]34) { $quote = $character; [void]$builder.Append($character); continue }
        if ($character -eq '[' -or $character -eq '{' -or $character -eq '(') { $depth++; [void]$builder.Append($character); continue }
        if ($character -eq ']' -or $character -eq '}' -or $character -eq ')') { if ($depth -gt 0) { $depth-- }; [void]$builder.Append($character); continue }
        if ($character -eq ',' -and $depth -eq 0) { [void]$parts.Add($builder.ToString()); [void]$builder.Clear(); continue }
        [void]$builder.Append($character)
    }
    [void]$parts.Add($builder.ToString())
    return @($parts.ToArray())
}

function Normalize-TargetYamlScalar([string]$Raw) {
    $value = if ($null -eq $Raw) { '' } else { [string]$Raw.Trim() }
    if ([string]::IsNullOrWhiteSpace($value) -or $value -match '^#') { return '' }
    # Strip an unquoted YAML comment suffix; URLs and quoted values are kept.
    if ($value -notmatch '^["''].*["'']$') { $value = [regex]::Replace($value, '\s+#.*$', '').Trim() }
    if (($value.StartsWith('[') -and $value.EndsWith(']')) -or ($value.StartsWith('{') -and $value.EndsWith('}'))) { $value = $value.Substring(1,$value.Length-2).Trim() }
    if ($value.Length -ge 2 -and (($value[0] -eq [char]39 -and $value[$value.Length-1] -eq [char]39) -or ($value[0] -eq [char]34 -and $value[$value.Length-1] -eq [char]34))) {
        $value = $value.Substring(1,$value.Length-2)
        $value = $value.Replace("''", "'").Replace('\"','"')
    }
    if ($value -in @('null','Null','NULL','~')) { return '' }
    return $value.Trim()
}

function Convert-TargetYamlValues([string]$Raw) {
    $value = if ($null -eq $Raw) { '' } else { [string]$Raw.Trim() }
    if ([string]::IsNullOrWhiteSpace($value)) { return @() }
    $flow = (($value.StartsWith('[') -and $value.EndsWith(']')) -or ($value.StartsWith('{') -and $value.EndsWith('}')))
    if ($flow) { $value = $value.Substring(1,$value.Length-2) }
    $pieces = if ($flow) { Split-TargetYamlValues $value } else { @($value) }
    $result = New-Object Collections.Generic.List[string]
    foreach ($piece in $pieces) {
        $normalized = Normalize-TargetYamlScalar ([string]$piece)
        if (-not [string]::IsNullOrWhiteSpace($normalized)) { [void]$result.Add($normalized) }
    }
    return @($result.ToArray())
}

function Add-TargetFrontmatterValues([System.Collections.IDictionary]$Map,[string]$Key,[string]$Raw) {
    $normalizedKey = [string]$Key.ToLowerInvariant()
    if (-not $Map.Contains($normalizedKey)) { $Map[$normalizedKey] = New-Object Collections.Generic.List[string] }
    foreach ($value in @(Convert-TargetYamlValues $Raw)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) { [void]$Map[$normalizedKey].Add([string]$value) }
    }
}

function Read-TargetFrontmatter([string]$Content) {
    $normalized = ([string]$Content).Replace("`r`n", "`n").Replace("`r", "`n").TrimStart([char]0xFEFF)
    $allLines = @($normalized -split "`n")
    $start = -1; $end = $allLines.Count
    for ($i = 0; $i -lt $allLines.Count; $i++) {
        if ($allLines[$i].Trim() -ceq '---') { $start = $i; break }
        if (-not [string]::IsNullOrWhiteSpace($allLines[$i])) { break }
    }
    if ($start -ge 0) {
        for ($i = $start + 1; $i -lt $allLines.Count; $i++) { if ($allLines[$i].Trim() -in @('---','...')) { $end = $i; break } }
    } else { $start = -1 }
    $map = [ordered]@{}; $current = ''
    $first = $start + 1; $last = $end - 1
    if ($last -lt $first) { return ,$map }
    for ($i = $first; $i -le $last; $i++) {
        $line = [string]$allLines[$i]
        $match = [regex]::Match($line, '^\s*(?:-\s*)?([A-Za-z][A-Za-z0-9_.-]*)\s*:\s*(.*?)\s*$')
        if ($match.Success) {
            $current = $match.Groups[1].Value.ToLowerInvariant()
            Add-TargetFrontmatterValues $map $current $match.Groups[2].Value
            continue
        }
        $item = [regex]::Match($line, '^\s*-\s+(.+?)\s*$')
        if ($item.Success -and -not [string]::IsNullOrWhiteSpace($current)) {
            foreach ($value in @(Convert-TargetYamlValues $item.Groups[1].Value)) { if (-not $map.Contains($current)) { $map[$current] = New-Object Collections.Generic.List[string] }; [void]$map[$current].Add([string]$value) }
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($line)) { $current = '' }
    }
    return ,$map
}

function Get-TargetFrontmatterValues([System.Collections.IDictionary]$Map,[string]$Key) {
    $normalizedKey = $Key.ToLowerInvariant()
    if (-not $Map.Contains($normalizedKey)) { return @() }
    $value = $Map[$normalizedKey]
    if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) { return @($value | ForEach-Object { [string]$_ }) }
    return @([string]$value)
}

function Merge-TargetFrontmatterValues([System.Collections.IDictionary]$Map,[string[]]$Keys) {
    $result = New-Object Collections.Generic.List[string]
    foreach ($key in $Keys) {
        foreach ($value in @(Get-TargetFrontmatterValues $Map $key)) {
            $text = [string]$value
            if (-not [string]::IsNullOrWhiteSpace($text) -and -not $result.Contains($text)) { [void]$result.Add($text) }
        }
    }
    return @($result.ToArray())
}

function Get-TargetAuthorityEntries([string]$Root) {
    $entries = New-Object Collections.Generic.List[object]
    $authority = Join-Path $Root '权威'
    if (-not [IO.Directory]::Exists($authority)) { return @() }
    foreach ($file in @(Get-ChildItem -LiteralPath $authority -Recurse -Force -File | Sort-Object FullName)) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Fail "Reparse point is not allowed: $($file.FullName)" }
        if ($file.Name -ceq 'README.md' -or $file.Name -ceq '索引.json' -or $file.Name -ceq '声明索引.json') { continue }
        $relative = Get-RelativePath $Root $file.FullName
        $kind = 'Claim'
        if ($relative -match '^权威/事件/') { $kind = 'Event' } elseif ($relative -match '^权威/决策/') { $kind = 'Decision' }
        $body = Read-Text $file.FullName
        $frontmatter = Read-TargetFrontmatter $body
        $id = ''
        foreach ($field in @('claim_id','event_id','decision_id','draft_id','id')) {
            $values = @(Get-TargetFrontmatterValues $frontmatter $field)
            if ($values.Count -gt 0) { $id = [string]$values[0]; break }
        }
        if ([string]::IsNullOrWhiteSpace($id)) { $id = [IO.Path]::GetFileNameWithoutExtension($file.Name) }
        $topicIds = Merge-TargetFrontmatterValues $frontmatter @('topic_id','topic_ids','cross_topic_ids')
        $sourceRefs = Merge-TargetFrontmatterValues $frontmatter @('source_ref','source_refs')
        $allowedUses = Merge-TargetFrontmatterValues $frontmatter @('allowed_use','allowed_uses')
        $statusValues = @(Get-TargetFrontmatterValues $frontmatter 'status')
        $sensitivityValues = @(Get-TargetFrontmatterValues $frontmatter 'sensitivity')
        $entry = [ordered]@{
            'id'=[string]$id; 'kind'=[string]$kind;
            'status'=$(if($statusValues.Count -gt 0){[string]$statusValues[0]}else{'unknown'});
            'topic_ids'=@($topicIds); 'source_refs'=@($sourceRefs);
            'sensitivity'=$(if($sensitivityValues.Count -gt 0){[string]$sensitivityValues[0]}else{'unknown'});
            'allowed_uses'=@($allowedUses); 'path'=[string]$relative; 'sha256'=[string](Get-Sha256Hex $file.FullName)
        }
        $entries.Add($entry)
    }
    return @($entries.ToArray())
}

function Rebuild-Index-Core([string]$Root,[bool]$Confirmed) {
    Require-Confirmed $Confirmed
    $marker = Read-TargetMarker $Root; $manifest = Read-TargetManifest $Root
    $entries = Get-TargetAuthorityEntries $Root
    # Keep the freshness hash independent of adapter-specific JSON formatting:
    # it is the SHA-256 of sorted `path:sha256` lines with no trailing LF.
    $hashLines = @($entries | ForEach-Object { "$($_.path):$($_.sha256)" })
    $sourceHash = Get-StringSha256Hex ($hashLines -join "`n")
    $matrixPath = Join-Path $Root '主题覆盖矩阵.md'
    $matrixHash = if ([IO.File]::Exists($matrixPath)) { Get-Sha256Hex $matrixPath } else { '' }
    $source = Get-ManifestSource $manifest
    $profileVersion = if ($null -ne $source) { [string]$source.profile_version } else { '' }
    $progressVersion = if ($null -ne $source) { [string]$source.progress_version } else { '' }
    $index = [ordered]@{
        'schema_version'=1;'layout'='target';'migration_id'=[string]$marker['migration_id'];
        'index_source_version'=$profileVersion;'index_source_progress_version'=$progressVersion;
        'index_source_matrix_version'=$matrixHash;'generated_at'=(Utc-Now);'index_source_hash'=$sourceHash;
        'entries'=@($entries)
    }
    $indexText = ((($index | ConvertTo-Json -Depth 40) -replace "`r`n", "`n") + "`n")
    $indexPath = Join-Path $Root '权威\声明索引.json'
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($indexPath)) | Out-Null
    Write-Atomic $indexPath $indexText
    $lines = New-Object Collections.Generic.List[string]
    $lines.Add('# 资料索引（目标布局）'); $lines.Add(''); $lines.Add("- 索引源档案版本：$profileVersion"); $lines.Add("- 索引源进度版本：$progressVersion"); $lines.Add("- 索引源矩阵版本：$matrixHash"); $lines.Add("- 生成时间：$($index.generated_at)"); $lines.Add("- 索引源 hash：$sourceHash"); $lines.Add('')
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File | Sort-Object FullName)) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        $relative = Get-RelativePath $Root $file.FullName
        if ($relative -ceq '资料索引.md') { continue }
        $lines.Add("- $relative · $((Get-Sha256Hex $file.FullName))")
    }
    Write-Atomic (Join-Path $Root '资料索引.md') (($lines -join "`n") + "`n")
    [void](Set-TargetMarkerValues $Root @{
        'index_source_version'=$profileVersion;'index_source_progress_version'=$progressVersion;
        'index_source_matrix_version'=$matrixHash;'index_source_hash'=$sourceHash;'generated_at'=$index.generated_at
    })
    $manifestFreshness = [ordered]@{
        'index_source_version'=$profileVersion; 'index_source_progress_version'=$progressVersion;
        'index_source_matrix_version'=$matrixHash; 'index_source_hash'=$sourceHash;
        'index_generated_at'=$index.generated_at
    }
    foreach ($key in $manifestFreshness.Keys) {
        $value = [string]$manifestFreshness[$key]
        if (Has-JsonProperty $manifest $key) { $manifest.PSObject.Properties[$key].Value = $value }
        else { $manifest | Add-Member -NotePropertyName $key -NotePropertyValue $value }
    }
    Write-Atomic (Join-Path $Root 'manifest.json') ((($manifest | ConvertTo-Json -Depth 40) -replace "`r`n", "`n") + "`n")
    return [ordered]@{'ok'=$true;'command'='rebuild-index';'root'=$Root;'layout'=[string]$marker['layout'];'migration_id'=$marker['migration_id'];'entry_count'=$entries.Count;'index_source_hash'=$sourceHash;'index_source_matrix_version'=$matrixHash;'generated_at'=$index.generated_at}
}

function Rebuild-Index([string]$Root,[bool]$Confirmed) {
    return Invoke-WithProfileLock $Root { Rebuild-Index-Core $Root $Confirmed }
}

function Write-LayoutTransaction([string]$Root,[System.Collections.IDictionary]$Values) {
    $path = Join-Path $Root $script:LayoutTransactionFile
    if ([IO.File]::Exists($path)) { Fail 'Interrupted layout transaction exists; run rollback-layout --confirmed --root <authorized-root>.' }
    Write-KeyValues $path $Values
}

function Read-LayoutTransaction([string]$Root) {
    $path = Join-Path $Root $script:LayoutTransactionFile
    if (-not [IO.File]::Exists($path)) { return $null }
    $values = Read-KeyValues $path
    foreach ($key in @('kind','migration_id','snapshot_rel','target_root','old_profile_version','old_progress_version')) {
        if (-not $values.Contains($key) -or [string]::IsNullOrWhiteSpace([string]$values[$key])) { Fail "Missing layout transaction field: $key" }
    }
    if ([string]$values['kind'] -cne 'switch-layout') { Fail 'Unknown layout transaction kind.' }
    if (-not (Test-SafeMigrationId ([string]$values['migration_id']))) { Fail 'Invalid layout transaction migration_id.' }
    $snapshot = Resolve-TransactionPath $Root ([string]$values['snapshot_rel'])
    if (-not [IO.Directory]::Exists($snapshot)) { Fail 'Missing layout transaction snapshot.' }
    return $values
}

function Snapshot-Canonical([string]$Root,[string]$SnapshotDir,[string]$MigrationId) {
    if ([IO.Directory]::Exists($SnapshotDir)) { Fail "Snapshot already exists: $SnapshotDir" }
    [IO.Directory]::CreateDirectory($SnapshotDir) | Out-Null
    $snapshotRel = Get-RelativePath $Root $SnapshotDir
    # Preserve directory shape as well as files.  Empty recovery/history
    # directories are part of the schema-2 contract, so a file-only snapshot
    # would be impossible to validate during rollback.
    foreach ($directory in @(Get-ChildItem -LiteralPath $Root -Recurse -Force -Directory -ErrorAction Stop)) {
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Fail "Reparse point is not allowed: $($directory.FullName)" }
        $relativeDir = Get-RelativePath $Root $directory.FullName
        if ($relativeDir.Equals($snapshotRel,[StringComparison]::OrdinalIgnoreCase) -or $relativeDir.StartsWith($snapshotRel.TrimEnd('/') + '/',[StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($relativeDir.Equals($script:LayoutTransactionFile,[StringComparison]::OrdinalIgnoreCase) -or
            $relativeDir.StartsWith($script:LayoutTransactionFile + '/',[StringComparison]::OrdinalIgnoreCase) -or
            $relativeDir.Equals($script:TransactionFile,[StringComparison]::OrdinalIgnoreCase) -or
            $relativeDir.StartsWith($script:TransactionFile + '/',[StringComparison]::OrdinalIgnoreCase) -or
            $relativeDir.Equals($script:LockDirectoryName,[StringComparison]::OrdinalIgnoreCase) -or
            $relativeDir.StartsWith($script:LockDirectoryName + '/',[StringComparison]::OrdinalIgnoreCase)) { continue }
        [IO.Directory]::CreateDirectory((Join-Path $SnapshotDir ($relativeDir -replace '/','\'))) | Out-Null
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction Stop)) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Fail "Reparse point is not allowed: $($file.FullName)" }
        $relative = Get-RelativePath $Root $file.FullName
        if ($relative.Equals($snapshotRel,[StringComparison]::OrdinalIgnoreCase) -or $relative.StartsWith($snapshotRel.TrimEnd('/') + '/',[StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($relative.Equals($script:LayoutTransactionFile,[StringComparison]::OrdinalIgnoreCase) -or
            $relative.StartsWith($script:LayoutTransactionFile + '/',[StringComparison]::OrdinalIgnoreCase) -or
            $relative.Equals($script:TransactionFile,[StringComparison]::OrdinalIgnoreCase) -or
            $relative.StartsWith($script:TransactionFile + '/',[StringComparison]::OrdinalIgnoreCase) -or
            $relative.Equals($script:LockDirectoryName,[StringComparison]::OrdinalIgnoreCase) -or
            $relative.StartsWith($script:LockDirectoryName + '/',[StringComparison]::OrdinalIgnoreCase)) { continue }
        $destination = Join-Path $SnapshotDir ($relative -replace '/','\')
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
        [IO.File]::Copy($file.FullName,$destination,$true)
    }
    $snapshotState = $null
    try { $snapshotState = Read-State (Join-Path $Root $script:StateFile) } catch { $snapshotState = $null }
    $snapshotMetadata = [ordered]@{
        'layout_snapshot' = $true; 'migration_id' = [string]$MigrationId;
        'profile_version' = $(if($null -ne $snapshotState -and $snapshotState.Contains('profile_version')){[string]$snapshotState['profile_version']}else{''});
        'created_at' = (Utc-Now)
    }
    Write-Atomic (Join-Path $SnapshotDir 'snapshot.json') ((($snapshotMetadata | ConvertTo-Json -Depth 10) -replace "`r`n", "`n") + "`n")
}

function Invoke-WithTwoProfileLocks([string]$Left,[string]$Right,[scriptblock]$Action) {
    $leftFull = [IO.Path]::GetFullPath($Left); $rightFull = [IO.Path]::GetFullPath($Right)
    # PowerShell uses dynamic scoping for scriptblocks. Capture the caller's
    # action under distinct names before nesting lock wrappers; otherwise the
    # nested block resolves `$Action` to Invoke-WithProfileLock's own
    # parameter and recursively invokes itself until call-depth overflow.
    $leftRoot = $Left; $rightRoot = $Right; $callerAction = $Action
    if ([String]::Compare($leftFull,$rightFull,[StringComparison]::OrdinalIgnoreCase) -le 0) {
        $nested = { Invoke-WithProfileLock $rightRoot $callerAction }.GetNewClosure()
        return Invoke-WithProfileLock $leftRoot $nested
    }
    $nested = { Invoke-WithProfileLock $leftRoot $callerAction }.GetNewClosure()
    return Invoke-WithProfileLock $rightRoot $nested
}

function Restore-LayoutSnapshot-Core([string]$Root,[string]$MigrationId,[System.Collections.IDictionary]$Transaction=$null) {
    $snapshot = $null
    if ($null -ne $Transaction) { $snapshot = Resolve-TransactionPath $Root ([string]$Transaction['snapshot_rel']) }
    if ($null -eq $snapshot) {
        $historyRoot = Join-Path $Root '历史版本'
        $matches = @()
        if ([IO.Directory]::Exists($historyRoot)) {
            $pattern = '^compat-v[1-9][0-9]*-' + [regex]::Escape($MigrationId) + '$'
            $matches = @(Get-ChildItem -LiteralPath $historyRoot -Directory -Force | Where-Object { $_.Name -cmatch $pattern })
        }
        if ($matches.Count -ne 1) { Fail "No unique migration snapshot found for $MigrationId." }
        $snapshot = $matches[0].FullName
    }
    if (-not [IO.Directory]::Exists($snapshot)) { Fail 'Migration snapshot does not exist.' }
    $snapshotValid = Validate-Space-Core $snapshot $true
    if (-not $snapshotValid.ok) { Fail ('Migration snapshot is invalid: ' + ($snapshotValid.issues -join '; ')) }
    $quarantine = Join-Path $Root ('.trash\layout-rollback-' + $MigrationId + '-' + (File-Stamp))
    [IO.Directory]::CreateDirectory($quarantine) | Out-Null
    $snapshotRel = Get-RelativePath $Root $snapshot
    $snapshotFiles = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $snapshot -Recurse -Force -File)) {
        $relativeSnapshotFile = Get-RelativePath $snapshot $file.FullName
        if ($relativeSnapshotFile -ceq 'snapshot.json') { continue }
        $snapshotFiles[$relativeSnapshotFile] = $true
    }
    $quarantineRel = Get-RelativePath $Root $quarantine
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File)) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        $relative = Get-RelativePath $Root $file.FullName
        if ($relative.StartsWith($snapshotRel.TrimEnd('/') + '/',[StringComparison]::OrdinalIgnoreCase) -or $relative.Equals($snapshotRel,[StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($relative.StartsWith($quarantineRel.TrimEnd('/') + '/',[StringComparison]::OrdinalIgnoreCase) -or $relative.Equals($quarantineRel,[StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($relative.Equals($script:LayoutTransactionFile,[StringComparison]::OrdinalIgnoreCase) -or
            $relative.StartsWith($script:LayoutTransactionFile + '/',[StringComparison]::OrdinalIgnoreCase) -or
            $relative.Equals($script:LockDirectoryName,[StringComparison]::OrdinalIgnoreCase) -or
            $relative.StartsWith($script:LockDirectoryName + '/',[StringComparison]::OrdinalIgnoreCase)) { continue }
        if (-not $snapshotFiles.ContainsKey($relative)) {
            $destination = Join-Path $quarantine ($relative -replace '/','\')
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
            Move-Item -LiteralPath $file.FullName -Destination $destination -Force
        }
    }
    $restored = New-Object Collections.Generic.List[string]
    foreach ($file in @(Get-ChildItem -LiteralPath $snapshot -Recurse -Force -File)) {
        $relative = Get-RelativePath $snapshot $file.FullName
        if ($relative -ceq 'snapshot.json') { continue }
        $destination = Join-Path $Root ($relative -replace '/','\')
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
        [IO.File]::Copy($file.FullName,$destination,$true); $restored.Add($relative)
    }
    $layoutMarker = Join-Path $Root $script:LayoutTransactionFile
    if ([IO.File]::Exists($layoutMarker)) { [IO.File]::Delete($layoutMarker) }
    $valid = Validate-Space-Core $Root $true
    if (-not $valid.ok) { Fail ('Rollback completed but canonical profile is invalid: ' + ($valid.issues -join '; ')) }
    return [ordered]@{'ok'=$true;'command'='rollback-layout';'root'=$Root;'migration_id'=$MigrationId;'snapshot'=$snapshot;'quarantine'=$quarantine;'restored_count'=$restored.Count}
}

function Switch-Layout-Core([string]$Root,[string]$TargetRoot,[string]$RequestedMigrationId,[string]$ExpectedVersion,[string]$ExpectedProgressVersion,[bool]$Confirmed,[bool]$SimulateFailure=$false) {
    Require-Confirmed $Confirmed
    if (-not (Test-PositiveDecimal $ExpectedVersion) -or -not (Test-PositiveDecimal $ExpectedProgressVersion)) { Fail 'Expected versions must be positive decimal integers.' }
    Assert-IndependentRoots $Root $TargetRoot
    $sourceMarker = Get-TargetMarkerIfPresent $Root
    if ($null -ne $sourceMarker -and [string]$sourceMarker['layout'] -ceq 'target') {
        $existingId = [string]$sourceMarker['migration_id']
        $targetMarker = Read-TargetMarker $TargetRoot
        if ($existingId -ceq [string]$targetMarker['migration_id']) { return [ordered]@{'ok'=$true;'command'='switch-layout';'root'=$Root;'target'=$TargetRoot;'migration_id'=$existingId;'already_switched'=$true;'layout'='target'} }
        Fail 'Canonical root is already a different target migration.'
    }
    $sourceValid = Validate-Space $Root
    if (-not $sourceValid.ok) { Fail ('Invalid canonical source: ' + ($sourceValid.issues -join '; ')) }
    $source = Get-TargetSourceSnapshot $Root
    $sourceState = Read-State (Join-Path $Root $script:StateFile)
    if ($source.profile_version -cne $ExpectedVersion) { Fail "Version conflict: expected $ExpectedVersion, current $($source.profile_version)." }
    if ($source.progress_version -cne $ExpectedProgressVersion) { Fail "Progress version conflict: expected $ExpectedProgressVersion, current $($source.progress_version)." }
    $targetInfo = Assert-TargetMatchesSource $Root $TargetRoot $false
    $targetMarker = $targetInfo.marker
    if ([string]$targetMarker['layout'] -cne 'target') { Fail 'switch-layout requires a formal target with layout=target.' }
    $migrationId = [string]$targetMarker['migration_id']
    if (-not [string]::IsNullOrWhiteSpace($RequestedMigrationId) -and $RequestedMigrationId -cne $migrationId) { Fail 'Migration id does not match formal target.' }
    $historyRoot = Join-Path $Root '历史版本'
    $snapshotDir = Join-Path $historyRoot ("compat-v$ExpectedVersion-$migrationId")
    $transactionPath = Join-Path $Root $script:LayoutTransactionFile
    Invoke-WithTwoProfileLocks $Root $TargetRoot {
        if ([IO.File]::Exists($transactionPath)) { Fail 'Interrupted layout transaction exists; run rollback-layout --confirmed --root <authorized-root>.' }
        Write-LayoutTransaction $Root ([ordered]@{'kind'='switch-layout';'migration_id'=$migrationId;'snapshot_rel'=(Get-RelativePath $Root $snapshotDir);'target_root'=$TargetRoot;'old_profile_version'=$ExpectedVersion;'old_progress_version'=$ExpectedProgressVersion})
        try {
            Snapshot-Canonical $Root $snapshotDir $migrationId
            # Preserve old recovery/history/withdrawal stores.  Target
            # authority, source indexes and derived views are copied over; the
            # old root-level files are in the exact snapshot above.
            Copy-TargetTree $TargetRoot $Root @('.hello-lock','.hello-transaction','.hello-layout-transaction','历史版本','.backups','.trash')
            [void](Promote-TargetPackage $Root 'active-pending-review' $sourceState)
            if ($SimulateFailure) { Fail 'simulated failure after target copy' }
            $valid = Target-Validate-Core $Root
            if (-not $valid.ok) { Fail ('Post-switch target validation failed: ' + ($valid.issues -join '; ')) }
            [IO.File]::Delete($transactionPath)
        } catch {
            $original = $_.Exception
            try { [void](Restore-LayoutSnapshot-Core $Root $migrationId (Read-LayoutTransaction $Root)) } catch { Fail "Layout switch failed: $($original.Message). Automatic rollback failed: $($_.Exception.Message)." }
            Fail "Layout switch failed and was rolled back: $($original.Message)"
        }
    }
    return [ordered]@{'ok'=$true;'command'='switch-layout';'root'=$Root;'target'=$TargetRoot;'migration_id'=$migrationId;'layout'='target';'snapshot'=$snapshotDir;'source_unchanged'=$false}
}

function Switch-Layout([string]$Root,[string]$TargetRoot,[string]$MigrationId,[string]$ExpectedVersion,[string]$ExpectedProgressVersion,[bool]$Confirmed,[bool]$SimulateFailure=$false) {
    return Switch-Layout-Core $Root $TargetRoot $MigrationId $ExpectedVersion $ExpectedProgressVersion $Confirmed $SimulateFailure
}

function Rollback-Layout([string]$Root,[string]$MigrationId,[bool]$Confirmed) {
    Require-Confirmed $Confirmed
    if (-not (Test-SafeMigrationId $MigrationId)) { Fail 'migration-id is invalid.' }
    return Invoke-WithProfileLock $Root {
        $transaction = $null; $markerPath = Join-Path $Root $script:LayoutTransactionFile
        if ([IO.File]::Exists($markerPath)) { $transaction = Read-LayoutTransaction $Root; if ([string]$transaction['migration_id'] -cne $MigrationId) { Fail 'Interrupted transaction migration_id does not match.' } }
        Restore-LayoutSnapshot-Core $Root $MigrationId $transaction
    }
}

function Configure-Space-Core([string]$Root,[string]$CaptureMode,[string]$NextReviewAt,[string]$ReviewStage,[bool]$Confirmed,[bool]$CaptureModeProvided=$false,[bool]$NextReviewAtProvided=$false,[bool]$ReviewStageProvided=$false) {
    Require-Confirmed $Confirmed; $state = Require-Valid $Root; Require-ActiveLayout $Root $state 'configure'
    # The CLI passes explicit presence flags because Windows PowerShell 5.1
    # coerces a missing value-index into an empty string for typed parameters.
    # Direct callers retain the historical inference for non-empty values.
    if(-not$CaptureModeProvided -and -not[string]::IsNullOrWhiteSpace($CaptureMode)){$CaptureModeProvided=$true}
    if(-not$NextReviewAtProvided -and -not[string]::IsNullOrEmpty($NextReviewAt)){$NextReviewAtProvided=$true}
    if(-not$ReviewStageProvided -and -not[string]::IsNullOrWhiteSpace($ReviewStage)){$ReviewStageProvided=$true}
    if (-not $CaptureModeProvided -and -not $NextReviewAtProvided -and -not $ReviewStageProvided) { Fail 'configure requires at least one setting.' }
    $newCaptureMode = [string]$state['capture_mode']
    $newReviewStage = [string]$state['review_stage']
    $newNextReviewAt = [string]$state['next_review_at']
    if ($CaptureModeProvided) { if (@('auto-stage','prompt','explicit') -cnotcontains $CaptureMode) { Fail '--capture-mode must be auto-stage, prompt, or explicit.' }; $newCaptureMode=$CaptureMode }
    if ($ReviewStageProvided) {
        if (@('baseline','first-review','stable') -cnotcontains $ReviewStage) { Fail '--review-stage must be baseline, first-review, or stable.' }
        $newReviewStage=$ReviewStage
    }
    if ($NextReviewAtProvided) { if ($NextReviewAt -ceq 'none' -or $NextReviewAt -ceq '') { $newNextReviewAt='' } elseif (-not (Test-Iso $NextReviewAt $false)) { Fail '--next-review-at must be ISO 8601 or none.' } else { $newNextReviewAt=$NextReviewAt } }
    if ($newReviewStage -ceq 'first-review' -and [string]::IsNullOrWhiteSpace($newNextReviewAt)) { if ([string]$state['review_stage'] -cne 'first-review') { Fail 'Entering first-review requires --next-review-at.' }; Fail 'first-review requires --next-review-at.' }
    $state['capture_mode']=$newCaptureMode
    $state['review_stage']=$newReviewStage
    $state['next_review_at']=$newNextReviewAt
    $state['updated_at']=Utc-Now; Write-State (Join-Path $Root $script:StateFile) $state
    return @{'ok'=$true;'command'='configure';'root'=$Root;'capture_mode'=$state['capture_mode'];'review_stage'=$state['review_stage'];'next_review_at'=$state['next_review_at']}
}

function Configure-Space([string]$Root,[string]$CaptureMode,[string]$NextReviewAt,[string]$ReviewStage,[bool]$Confirmed,[bool]$CaptureModeProvided=$false,[bool]$NextReviewAtProvided=$false,[bool]$ReviewStageProvided=$false) {
    return Invoke-WithProfileLock $Root { Configure-Space-Core $Root $CaptureMode $NextReviewAt $ReviewStage $Confirmed $CaptureModeProvided $NextReviewAtProvided $ReviewStageProvided }
}

function Record-Disclosure-Core([string]$Root,[string]$CaptureMode,[bool]$Confirmed,[bool]$CaptureModeProvided=$false) {
    Require-Confirmed $Confirmed
    $state=Require-Valid $Root
    Require-ActiveLayout $Root $state 'record-disclosure'
    if(-not$CaptureModeProvided -and -not[string]::IsNullOrWhiteSpace($CaptureMode)){$CaptureModeProvided=$true}
    if($CaptureModeProvided) {
        if(@('auto-stage','prompt','explicit') -cnotcontains $CaptureMode) { Fail '--capture-mode must be auto-stage, prompt, or explicit.' }
        if($CaptureMode -cne [string]$state['capture_mode']) { Fail '--capture-mode does not match the current capture policy.' }
    }
    $current=Utc-Now
    $state['last_capture_disclosed_at']=$current
    $state['last_capture_disclosed_mode']=[string]$state['capture_mode']
    $state['updated_at']=$current
    Write-State (Join-Path $Root $script:StateFile) $state
    $strategy=@{'auto-stage'='自动暂存';'prompt'='提示确认';'explicit'='仅显式'}[[string]$state['capture_mode']]
    return @{'ok'=$true;'command'='record-disclosure';'root'=$Root;'capture_mode'=$state['capture_mode'];'capture_strategy'=$strategy;'last_capture_disclosed_at'=$current;'last_capture_disclosed_mode'=$state['last_capture_disclosed_mode']}
}

function Record-Disclosure([string]$Root,[string]$CaptureMode,[bool]$Confirmed,[bool]$CaptureModeProvided=$false) {
    return Invoke-WithProfileLock $Root { Record-Disclosure-Core $Root $CaptureMode $Confirmed $CaptureModeProvided }
}

function Show-Diff-Core([string]$Root,[string]$InputPath) {
    $diffState = Require-Valid $Root
    if ($diffState.Contains('layout') -and [string]$diffState['layout'] -ceq 'target') { Fail 'diff is only available for a compatibility schema-2 root; use target-validate/rebuild-index.' }
    $current = @((Read-Text (Join-Path $Root '个人全景档案.md')) -split "`n")
    $candidate = @((Read-Text $InputPath) -split "`n")
    if ((($current -join "`n") -ceq ($candidate -join "`n"))) { [Console]::WriteLine('No changes.'); return }
    $prefix=0; while($prefix -lt $current.Count -and $prefix -lt $candidate.Count -and $current[$prefix] -ceq $candidate[$prefix]){$prefix++}
    $suffix=0; while($suffix -lt ($current.Count-$prefix) -and $suffix -lt ($candidate.Count-$prefix) -and $current[$current.Count-1-$suffix] -ceq $candidate[$candidate.Count-1-$suffix]){$suffix++}
    $oldCount=$current.Count-$prefix-$suffix; $newCount=$candidate.Count-$prefix-$suffix
    [Console]::WriteLine('--- 个人全景档案.md'); [Console]::WriteLine("+++ $InputPath"); [Console]::WriteLine("@@ -$($prefix+1),$oldCount +$($prefix+1),$newCount @@")
    for($i=$prefix;$i -lt $current.Count-$suffix;$i++){[Console]::WriteLine('-'+$current[$i])}
    for($i=$prefix;$i -lt $candidate.Count-$suffix;$i++){[Console]::WriteLine('+'+$candidate[$i])}
}

function Show-Diff([string]$Root,[string]$InputPath) {
    Invoke-WithProfileLock $Root { Show-Diff-Core $Root $InputPath } | Out-Null
}

function Clean-Label([string]$Value,[string]$Fallback) { if([string]::IsNullOrWhiteSpace($Value)){return $Fallback}; $clean=([regex]::Replace($Value,'\s+',' ')).Trim(); if($clean.Length -gt 200){return $clean.Substring(0,200)}; return $clean }

function Stage-Candidate-Core([string]$Root,[string]$InputPath,[string]$Kind,[string]$Source,[bool]$Confirmed) {
    Require-Confirmed $Confirmed; $state=Require-Valid $Root; Require-ActiveLayout $Root $state 'stage'
    $mode=[string]$state['capture_mode']; $disclosedMode=if($state.Contains('last_capture_disclosed_mode')){[string]$state['last_capture_disclosed_mode']}else{''}; $disclosedAt=if($state.Contains('last_capture_disclosed_at')){[string]$state['last_capture_disclosed_at']}else{''}
    if($mode -cne 'explicit' -and ([string]::IsNullOrWhiteSpace($disclosedAt) -or $disclosedMode -cne $mode)){Fail 'Capture policy has not been disclosed for the current mode; record-disclosure is required before staging.'}
    $body=(Read-Text $InputPath).Trim(); if([string]::IsNullOrWhiteSpace($body)){Fail 'Candidate input is empty.'}
    $current=Utc-Now; $candidateId='C-'+(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')+'-'+$PID; $pendingPath=Join-Path $Root '待确认信息.md'
    $pending=(Read-Text $pendingPath).Replace("`n当前没有待确认信息。`n","`n")
    $block="`n## $candidateId`n`n- 暂存时间：$current`n- 类型：$(Clean-Label $Kind '未分类')`n- 来源：$(Clean-Label $Source '当前会话')`n- 状态：待确认`n`n$body`n"
    Write-Atomic $pendingPath ($pending.TrimEnd()+"`n"+$block); $state['updated_at']=$current; Write-State (Join-Path $Root $script:StateFile) $state
    return @{'ok'=$true;'command'='stage';'root'=$Root;'candidate_id'=$candidateId}
}

function Stage-Candidate([string]$Root,[string]$InputPath,[string]$Kind,[string]$Source,[bool]$Confirmed) {
    return Invoke-WithProfileLock $Root { Stage-Candidate-Core $Root $InputPath $Kind $Source $Confirmed }
}

function Copy-Unique([string]$Source,[string]$Directory,[string]$Name) {
    [IO.Directory]::CreateDirectory($Directory)|Out-Null; $target=Join-Path $Directory $Name; $counter=1
    while([IO.File]::Exists($target)){ $target=Join-Path $Directory (([IO.Path]::GetFileNameWithoutExtension($Name))+'-'+$counter+[IO.Path]::GetExtension($Name));$counter++ }
    [IO.File]::Copy($Source,$target,$false); return $target
}

function Relative-ToRoot([string]$Root,[string]$Path) { $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'; $full=[IO.Path]::GetFullPath($Path); if(-not $full.StartsWith($rootFull,[StringComparison]::OrdinalIgnoreCase)){Fail "Transaction path escapes profile root: $Path"}; return $full.Substring($rootFull.Length).Replace('\','/') }
function Resolve-TransactionPath([string]$Root,[string]$Relative) { $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'; $full=[IO.Path]::GetFullPath((Join-Path $Root $Relative)); if(-not $full.StartsWith($rootFull,[StringComparison]::OrdinalIgnoreCase)){Fail 'Transaction backup path escapes profile root.'}; return $full }
function Remove-TransactionBackups([string]$Root,[System.Collections.IDictionary]$Values) { foreach($key in @('profile_backup','log_backup','state_backup','progress_backup')) { if($Values.Contains($key)-and -not [string]::IsNullOrWhiteSpace([string]$Values[$key])) { $backup=Resolve-TransactionPath $Root ([string]$Values[$key]); if([IO.File]::Exists($backup)){[IO.File]::Delete($backup)} } } }
function Validate-TransactionMarker([System.Collections.IDictionary]$Values) {
    if(-not $Values.Contains('schema_version') -or [string]$Values['schema_version'] -cne '1'){Fail 'Transaction marker schema_version must be 1.'}
    if(-not $Values.Contains('kind')){Fail 'Missing transaction marker field: kind'}
    switch -CaseSensitive ([string]$Values['kind']) {
        'apply' { $required=@('profile_backup','log_backup','state_backup') }
        'record-turn' { $required=@('progress_backup','state_backup','record_path','record_created') }
        default { Fail "Unknown transaction marker kind: $($Values['kind'])" }
    }
    $missing=New-Object Collections.Generic.List[string]
    foreach($key in $required){if(-not $Values.Contains($key)-or [string]::IsNullOrWhiteSpace([string]$Values[$key])){[void]$missing.Add($key)}}
    if($missing.Count -gt 0){Fail ('Missing transaction marker field: '+($missing -join ', '))}
    if([string]$Values['kind'] -ceq 'record-turn' -and @('true','false') -cnotcontains [string]$Values['record_created']){Fail 'Transaction marker record_created must be true or false.'}
}
function Finish-Transaction([string]$Root) { $marker=Join-Path $Root $script:TransactionFile; $values=Read-KeyValues $marker; Remove-TransactionBackups $Root $values; [IO.File]::Delete($marker) }

function Begin-Transaction([string]$Root,[System.Collections.IDictionary]$Values) {
    $marker=Join-Path $Root $script:TransactionFile; if([IO.File]::Exists($marker)){Fail 'Interrupted transaction exists; run recover --confirmed --root <authorized-root>.'}
    $builder=New-Object Text.StringBuilder; [void]$builder.Append("schema_version=1`n"); foreach($key in $Values.Keys){[void]$builder.Append($key).Append('=').Append([string]$Values[$key]).Append("`n")}
    try { Write-Atomic-New $marker $builder.ToString() } catch { if([IO.File]::Exists($marker)){Fail 'Interrupted transaction exists; run recover --confirmed --root <authorized-root>.'}; throw }
}

function Recover-Transaction-Core([string]$Root,[bool]$Confirmed) {
    Require-Confirmed $Confirmed; $marker=Join-Path $Root $script:TransactionFile; if(-not [IO.File]::Exists($marker)){Fail 'No interrupted transaction exists.'}; $values=Read-KeyValues $marker; Validate-TransactionMarker $values
    $map=[ordered]@{'profile_backup'='个人全景档案.md';'log_backup'='迭代日志.md';'state_backup'=$script:StateFile;'progress_backup'='访谈进度.md'}; $restorePlan=New-Object Collections.Generic.List[object]; $restored=New-Object Collections.Generic.List[string]
    # Preflight every referenced backup and path before copying any target. A
    # malformed/incomplete marker must not leave a half-restored tree.
    foreach($key in $map.Keys){if($values.Contains($key)-and -not [string]::IsNullOrWhiteSpace([string]$values[$key])){$backup=Resolve-TransactionPath $Root $values[$key];if(-not [IO.File]::Exists($backup)){Fail "Missing transaction backup: $($values[$key])"};$restorePlan.Add(@($key,$backup))}}
    $recordPathValue=if($values.Contains('record_path')){[string]$values['record_path']}else{''}; $recordTarget=$null
    if(-not [string]::IsNullOrWhiteSpace($recordPathValue)){$recordTarget=Resolve-TransactionPath $Root $recordPathValue}
    foreach($plan in $restorePlan){$key=$plan[0];$backup=$plan[1];Write-Atomic (Join-Path $Root $map[$key]) (Read-Text $backup);$restored.Add($map[$key])}
    if($null -ne $recordTarget -and $values['record_created'] -ceq 'true'){if([IO.File]::Exists($recordTarget)){[IO.File]::Delete($recordTarget)}}
    # Validate while the marker and backups are still present.  If the
    # restored tree is invalid, retain both so an explicit retry remains
    # possible instead of deleting the only recovery material first.
    $valid=Validate-Space $Root $true;if(-not $valid.ok){Fail ('Recovery completed but profile space is invalid: '+($valid.issues -join '; '))}
    Remove-TransactionBackups $Root $values;[IO.File]::Delete($marker)
    return @{'ok'=$true;'command'='recover';'root'=$Root;'restored'=$restored.ToArray()}
}

function Recover-Transaction([string]$Root,[bool]$Confirmed) {
    return Invoke-WithProfileLock $Root { Recover-Transaction-Core $Root $Confirmed }
}

function Rollback-Failure([string]$Root,[Exception]$Original) { try{[void](Recover-Transaction $Root $true)}catch{Fail "Operation failed: $($Original.Message). Automatic rollback failed: $($_.Exception.Message). Run recover --confirmed --root <authorized-root>."};Fail "Operation failed and was rolled back: $($Original.Message)" }

function Update-ProfileHeader([string]$Content,[string]$Version,[string]$ConfirmedAt) { $v=New-Object Text.RegularExpressions.Regex('(?m)^- 资料版本：.*$');$t=New-Object Text.RegularExpressions.Regex('(?m)^- 最近确认时间：.*$');if($v.Matches($Content).Count-ne1-or$t.Matches($Content).Count-ne1){Fail 'Candidate profile must contain 资料版本 and 最近确认时间 metadata lines.'};return $t.Replace($v.Replace($Content,"- 资料版本：$Version",1),"- 最近确认时间：$ConfirmedAt",1) }
function Update-ProgressHeader([string]$Content,[string]$Version){$r=New-Object Text.RegularExpressions.Regex('(?m)^- 进度版本：.*$');if($r.Matches($Content).Count-gt0){return $r.Replace($Content,"- 进度版本：$Version",1)};$marker="# 访谈进度`n";$position=$Content.IndexOf($marker,[StringComparison]::Ordinal);if($position-lt0){Fail 'Progress input must contain the # 访谈进度 heading.'};return $Content.Substring(0,$position)+$marker+"`n- 进度版本：$Version"+$Content.Substring($position+$marker.Length)}
function Canonical-Profile([string]$Content){return ([regex]::Replace([regex]::Replace($Content,'(?m)^- 资料版本：.*$','- 资料版本：<version>'),'(?m)^- 最近确认时间：.*$','- 最近确认时间：<time>')).Trim()}

function Test-Summary([string]$Summary){$invalid=New-Object Collections.Generic.List[string];foreach($field in $script:SummaryFields){if(([regex]::Matches($Summary,'(?m)^- '+[regex]::Escape($field)+'：.+$')).Count-ne1){$invalid.Add($field)}};if($invalid.Count){Fail ('Update summary requires exactly one of each field: '+($invalid -join ', '))};$type=[regex]::Match($Summary,'(?m)^- 更新类型：(.+)$').Groups[1].Value.Trim().TrimEnd([char[]]'。.;；');if(@('新增','状态变化','事实纠正','解释变化','假设验证','撤回隐藏')-ccontains$type){return};Fail 'Update summary contains an invalid update type.'}

function Apply-Profile-Core([string]$Root,[string]$InputPath,[string]$SummaryPath,[string]$ExpectedVersion,[bool]$Confirmed,[bool]$SimulateFailure=$false) {
    Require-Confirmed $Confirmed
    $state=Require-Valid $Root
    if ($state.Contains('layout') -and [string]$state['layout'] -ceq 'target') { Fail 'apply is only available for a compatibility schema-2 root; update target entities explicitly.' }
    Require-ActiveLayout $Root $state 'apply'
    $currentVersion=[string]$state['profile_version']
    if($ExpectedVersion -cne $currentVersion){Fail "Version conflict: expected $ExpectedVersion, current $currentVersion."}
    $candidate=(Read-Text $InputPath).Trim()+"`n"
    $summary=(Read-Text $SummaryPath).Trim()
    $issues=Test-ProfileContent $candidate $null
    if($issues.Count){Fail ('Invalid candidate profile: '+($issues -join '; '))}
    Test-Summary $summary
    $profilePath=Join-Path $Root '个人全景档案.md'
    $currentProfile=Read-Text $profilePath
    if((Canonical-Profile $currentProfile)-ceq(Canonical-Profile $candidate)){Fail 'Candidate profile has no content changes.'}
    $current=Utc-Now
    $newVersion=Increment-Decimal $currentVersion
    $candidate=Update-ProfileHeader $candidate $newVersion $current
    $name=(File-Stamp)+"-v$currentVersion-个人全景档案.md"
    $history=Copy-Unique $profilePath (Join-Path $Root '历史版本') $name
    $backup=Copy-Unique $profilePath (Join-Path $Root '.backups\profile') $name
    $transactionDir=Join-Path $Root '.backups\transactions'
    $logPath=Join-Path $Root '迭代日志.md'
    $progressPath=Join-Path $Root '访谈进度.md'
    $statePath=Join-Path $Root $script:StateFile
    $progressOriginal=Read-Text $progressPath
    $progressCandidate=$progressOriginal
    $migrationProgressVersion=Get-EffectiveProgressVersion $Root $state
    if([string]$state['schema_version'] -cne '2') {
        $progressHeaders=[regex]::Matches($progressOriginal,'(?m)^- 进度版本：.*$')
        $progressMatches=[regex]::Matches($progressOriginal,'(?m)^- 进度版本：([1-9][0-9]*)$')
        if($progressHeaders.Count -gt 1) { Fail 'Invalid legacy progress metadata: duplicate 进度版本 metadata.' }
        if($progressHeaders.Count -eq 1 -and $progressMatches.Count -eq 0) { Fail 'Invalid legacy progress metadata: 进度版本 must be a positive integer.' }
        if($progressMatches.Count -eq 1 -and -not $state.Contains('progress_version')) {
            $migrationProgressVersion=[string]$progressMatches[0].Groups[1].Value
        } elseif($progressHeaders.Count -eq 0) {
            $progressCandidate=Update-ProgressHeader $progressOriginal $migrationProgressVersion
        }
    }
    $logBackup=Copy-Unique $logPath $transactionDir ((File-Stamp)+"-v$currentVersion-迭代日志.md")
    $stateBackup=Copy-Unique $statePath $transactionDir ((File-Stamp)+"-v$currentVersion-hello-state")
    $progressBackup=$null
    if($progressCandidate -cne $progressOriginal) { $progressBackup=Copy-Unique $progressPath $transactionDir ((File-Stamp)+"-v$currentVersion-访谈进度.md") }
    $transactionValues=[ordered]@{'kind'='apply';'profile_backup'=(Relative-ToRoot $Root $backup);'log_backup'=(Relative-ToRoot $Root $logBackup);'state_backup'=(Relative-ToRoot $Root $stateBackup)}
    if($null -ne $progressBackup) { $transactionValues['progress_backup']=(Relative-ToRoot $Root $progressBackup) }
    Begin-Transaction $Root $transactionValues
    try {
        Write-Atomic $profilePath $candidate
        if($SimulateFailure){Fail 'simulated failure after profile write'}
        $log=(Read-Text $logPath).Replace("`n当前没有正式迭代。`n","`n").TrimEnd()
        $entry="`n`n## R$newVersion · $current`n`n- 资料版本：$newVersion`n- 确认状态：用户已确认`n- 历史快照：``历史版本/$([IO.Path]::GetFileName($history))```n`n$summary`n"
        Write-Atomic $logPath ($log+$entry)
        if($progressCandidate -cne $progressOriginal) { Write-Atomic $progressPath $progressCandidate }
        $state['schema_version']='2'
        if(-not$state.Contains('progress_version')){$state['progress_version']=[string]$migrationProgressVersion}
        if(-not$state.Contains('last_session_id')){$state['last_session_id']=''}
        if(-not$state.Contains('last_turn_id')){$state['last_turn_id']=''}
        if(-not$state.Contains('last_capture_disclosed_at')){$state['last_capture_disclosed_at']=''}
        if(-not$state.Contains('last_capture_disclosed_mode')){$state['last_capture_disclosed_mode']=''}
        $state['profile_version']=[string]$newVersion
        $state['updated_at']=$current
        $state['last_confirmed_at']=$current
        Write-State $statePath $state
        $valid=Validate-Space $Root $true
        if(-not$valid.ok){Fail ('Post-write validation failed: '+($valid.issues -join '; '))}
    } catch { Rollback-Failure $Root $_.Exception }
    Finish-Transaction $Root
    return @{'ok'=$true;'command'='apply';'root'=$Root;'old_version'=$currentVersion;'profile_version'=$newVersion;'history'=$history;'backup'=$backup}
}

function Apply-Profile([string]$Root,[string]$InputPath,[string]$SummaryPath,[string]$ExpectedVersion,[bool]$Confirmed,[bool]$SimulateFailure=$false) {
    return Invoke-WithProfileLock $Root { Apply-Profile-Core $Root $InputPath $SummaryPath $ExpectedVersion $Confirmed $SimulateFailure }
}

function Get-SessionTermination([string]$Root,[string]$SessionId) {
    $reasons = New-Object Collections.Generic.List[string]
    if ($SessionId.Substring(0,10) -ne (Utc-Now).Substring(0,10)) { $reasons.Add('cross-natural-day') }
    $dir = Join-Path $Root ("原始访谈\" + $SessionId.Substring(0,4) + "\" + $SessionId)
    if ([IO.Directory]::Exists($dir) -and @([IO.Directory]::GetFiles($dir,'*.md')).Count -gt 50) { $reasons.Add('over-50-turns') }
    return @{'new_session_required'=($reasons.Count -gt 0);'session_termination_reasons'=$reasons.ToArray();'session_termination_notice'=($(if($reasons.Count){'请开启新会话'}else{''}))}
}

function Record-Turn-Core([string]$Root,[string]$InputPath,[string]$ProgressInput,[string]$SessionId,[string]$TurnId,[string]$ExpectedProgressVersion,[bool]$Confirmed,[bool]$SimulateFailure=$false) {
    Require-Confirmed $Confirmed;$state=Require-Valid $Root; Require-ActiveLayout $Root $state 'record-turn'
    if($SessionId-cnotmatch'^[0-9]{4}-[0-9]{2}-[0-9]{2}[A-Za-z0-9._-]{0,117}$'-or$TurnId-cnotmatch'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'){Fail 'session-id must start with YYYY-MM-DD; ids may only use ASCII letters, digits, dot, underscore, or hyphen.'}
    $body=(Read-Text $InputPath).Trim();if([string]::IsNullOrWhiteSpace($body)){Fail 'Turn input is empty.'};$year=$SessionId.Substring(0,4);$recordPath=Join-Path $Root "原始访谈\$year\$SessionId\$TurnId.md"
    # The immutable turn file is the durable idempotency key, not the mutable
    # last-session/last-turn cursor. A retry may arrive after later turns have
    # advanced that cursor, so consult the original file first.
    if([IO.File]::Exists($recordPath)){if((Read-Text $recordPath).Trim()-cne$body){Fail 'Idempotent turn retry has different content.'};return (@{'ok'=$true;'command'='record-turn';'root'=$Root;'session_id'=$SessionId;'turn_id'=$TurnId;'record'=$recordPath;'created'=$false;'idempotent'=$true;'progress_version'=(Get-EffectiveProgressVersion $Root $state)} + (Get-SessionTermination $Root $SessionId))}
    $currentVersion=[string](Get-EffectiveProgressVersion $Root $state);if($ExpectedProgressVersion -cne $currentVersion){Fail "Progress version conflict: expected $ExpectedProgressVersion, current $currentVersion."};if([IO.File]::Exists($recordPath)){Fail 'Turn record already exists with different content.'}
    $progress=(Read-Text $ProgressInput).Trim()+"`n";$issues=Test-ProgressContent $progress $null $false;if($issues.Count){Fail ('Invalid progress input: '+($issues -join '; '))};$newVersion=Increment-Decimal $currentVersion;$progress=Update-ProgressHeader $progress $newVersion
    $transactionDir=Join-Path $Root '.backups\transactions';$progressPath=Join-Path $Root '访谈进度.md';$statePath=Join-Path $Root $script:StateFile;$tag=File-Stamp;$progressBackup=Copy-Unique $progressPath $transactionDir "$tag-p$currentVersion-访谈进度.md";$stateBackup=Copy-Unique $statePath $transactionDir "$tag-p$currentVersion-hello-state"
    Begin-Transaction $Root ([ordered]@{'kind'='record-turn';'progress_backup'=(Relative-ToRoot $Root $progressBackup);'state_backup'=(Relative-ToRoot $Root $stateBackup);'record_path'=(Relative-ToRoot $Root $recordPath);'record_created'='true'})
    try{$current=Utc-Now;Write-Atomic $recordPath ($body+"`n");Write-Atomic $progressPath $progress;$state['schema_version']=if($state.Contains('layout') -and [string]$state['layout'] -ceq 'target'){'3'}else{'2'};$state['progress_version']=[string]$newVersion;$state['last_session_id']=$SessionId;$state['last_turn_id']=$TurnId;$state['last_interview_at']=$current;$state['updated_at']=$current;Write-State $statePath $state;if($SimulateFailure){Fail 'simulated failure after state write'};$valid=Validate-Space $Root $true;if(-not$valid.ok){Fail ('Post-write validation failed: '+($valid.issues -join '; '))}}catch{Rollback-Failure $Root $_.Exception}
    Finish-Transaction $Root;return (@{'ok'=$true;'command'='record-turn';'root'=$Root;'session_id'=$SessionId;'turn_id'=$TurnId;'record'=$recordPath;'created'=$true;'idempotent'=$false;'progress_version'=$newVersion} + (Get-SessionTermination $Root $SessionId))
}

function Record-Turn([string]$Root,[string]$InputPath,[string]$ProgressInput,[string]$SessionId,[string]$TurnId,[string]$ExpectedProgressVersion,[bool]$Confirmed,[bool]$SimulateFailure=$false) {
    return Invoke-WithProfileLock $Root { Record-Turn-Core $Root $InputPath $ProgressInput $SessionId $TurnId $ExpectedProgressVersion $Confirmed $SimulateFailure }
}

function Withdraw-Candidate-Core([string]$Root,[string]$CandidateId,[bool]$Confirmed){Require-Confirmed $Confirmed;$state=Require-Valid $Root;Require-ActiveLayout $Root $state 'withdraw';if($CandidateId-cnotmatch'^C-[0-9TZ-]+$'){Fail 'Invalid candidate id.'};$pendingPath=Join-Path $Root '待确认信息.md';$content=Read-Text $pendingPath;$pattern='(?ms)^## '+[regex]::Escape($CandidateId)+'\s*\r?\n.*?(?=^## C-[0-9TZ-]+\s*$|\z)';$match=[regex]::Match($content,$pattern);if(-not$match.Success){Fail "Candidate not found: $CandidateId"};$trashDir=Join-Path $Root '.trash\candidates';[IO.Directory]::CreateDirectory($trashDir)|Out-Null;$trash=Join-Path $trashDir ($CandidateId+'.md');if([IO.File]::Exists($trash)){$trash=Join-Path $trashDir ($CandidateId+'-'+(File-Stamp)+'.md')};Write-Atomic $trash ($match.Value.TrimEnd()+"`n");$remaining=($content.Remove($match.Index,$match.Length)).TrimEnd()+"`n";if($remaining-cnotmatch'(?m)^## C-[0-9TZ-]+\s*$'){$remaining=$remaining.TrimEnd()+"`n`n当前没有待确认信息。`n"};Write-Atomic $pendingPath $remaining;$state['updated_at']=Utc-Now;Write-State (Join-Path $Root $script:StateFile) $state;return @{'ok'=$true;'command'='withdraw';'root'=$Root;'candidate_id'=$CandidateId;'trash'=$trash}}

function Withdraw-Candidate([string]$Root,[string]$CandidateId,[bool]$Confirmed){ return Invoke-WithProfileLock $Root { Withdraw-Candidate-Core $Root $CandidateId $Confirmed } }

function SelfTest-Summary{return "- 触发原因：自测。`n- 信息来源：隔离测试。`n- 更新类型：新增。`n- 更新位置：当前起点。`n- 更新摘要：验证存储事务。`n- 用户确认状态：自测确认。`n- 执行工具：hello self-test。`n"}

function Assert-ConfigurePreservesDisclosure([string]$Root,[string]$CaptureMode) {
    $statePath=Join-Path $Root $script:StateFile
    $before=Read-State $statePath
    $beforeValue=if($before.Contains('last_capture_disclosed_at')){[string]$before['last_capture_disclosed_at']}else{''}
    [void](Configure-Space $Root $CaptureMode $null $null $true)
    $after=Read-State $statePath
    $afterValue=if($after.Contains('last_capture_disclosed_at')){[string]$after['last_capture_disclosed_at']}else{''}
    if($afterValue -cne $beforeValue){Fail 'Self-test configure faked a disclosure timestamp.'}
}

function Assert-CanonicalVersions([string]$Root) {
    $statePath = Join-Path $Root $script:StateFile
    $profilePath = Join-Path $Root '个人全景档案.md'
    $progressPath = Join-Path $Root '访谈进度.md'
    $state = Read-State $statePath
    $state['profile_version'] = '01'
    Write-State $statePath $state
    try {
        if ((Validate-Space $Root).ok) { Fail 'Self-test accepted a leading-zero state version.' }
    } finally {
        $state['profile_version'] = '1'
        Write-State $statePath $state
    }
    $profile = Read-Text $profilePath
    Write-Atomic $profilePath ($profile -replace '- 资料版本：1', '- 资料版本：01')
    try {
        if ((Validate-Space $Root).ok) { Fail 'Self-test accepted a leading-zero profile version.' }
    } finally { Write-Atomic $profilePath $profile }
    $progress = Read-Text $progressPath
    Write-Atomic $progressPath ($progress -replace '- 进度版本：1', '- 进度版本：01')
    try {
        if ((Validate-Space $Root).ok) { Fail 'Self-test accepted a leading-zero progress version.' }
    } finally { Write-Atomic $progressPath $progress }
}

function Assert-MalformedMarkerRejected([string]$Root) {
    $marker=Join-Path $Root $script:TransactionFile
    foreach($content in @(
        "schema_version=1`nkind=record-turn`nduplicate=x`nduplicate=y`n",
        "schema_version=1`nPROFILE_VERSION=shadow`nprofile_version=1`n"
    )) {
        Write-Atomic $marker $content
        try { [void](Recover-Transaction $Root $true); Fail 'Self-test accepted a malformed transaction marker.' }
        catch { if($_.Exception.Message -notlike '*Duplicate key*'){ throw } }
        if(-not [IO.File]::Exists($marker)){Fail 'Self-test removed a malformed transaction marker.'}
        [IO.File]::Delete($marker)
    }
}

function Assert-MissingBackupRejected([string]$Root) {
    $marker=Join-Path $Root $script:TransactionFile
    $profile=Join-Path $Root '个人全景档案.md'
    $before=[IO.File]::ReadAllBytes($profile)
    Write-Atomic $marker "schema_version=1`nkind=apply`nprofile_backup=.backups/transactions/missing-profile.md`n"
    try { [void](Recover-Transaction $Root $true); Fail 'Self-test accepted a missing transaction backup.' }
    catch { if($_.Exception.Message -notlike '*Missing transaction backup*' -and $_.Exception.Message -notlike '*Missing transaction marker field*'){ throw } }
    if(-not [IO.File]::Exists($marker)){Fail 'Self-test removed a missing-backup marker.'}
    $after=[IO.File]::ReadAllBytes($profile)
    if(-not [Linq.Enumerable]::SequenceEqual($before,$after)){Fail 'Self-test changed a target before missing-backup failure.'}
    [IO.File]::Delete($marker)
    foreach($content in @(
        "schema_version=1`nkind=apply`n",
        "schema_version=1`nkind=record-turn`n"
    )) {
        Write-Atomic $marker $content
        try { [void](Recover-Transaction $Root $true); Fail 'Self-test accepted an incomplete transaction marker.' }
        catch { if($_.Exception.Message -notlike '*Missing transaction marker field*'){ throw } }
        if(-not [IO.File]::Exists($marker)){Fail 'Self-test removed an incomplete transaction marker.'}
        [IO.File]::Delete($marker)
    }
}

function Assert-LfFiles([string]$Root) {
    foreach($name in $script:Files) {
        $bytes=[IO.File]::ReadAllBytes((Join-Path $Root $name))
        if($bytes -contains [byte]13){Fail "Self-test init left CR in $name."}
    }
}

function Assert-CliParserError([string[]]$Arguments,[string]$ExpectedCommand,[string]$ExpectedErrorPattern='') {
    $output=@(& $script:HostCommand -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:SelfPath @Arguments 2>&1)
    if($LASTEXITCODE -ne 2){Fail "Self-test parser probe returned exit $LASTEXITCODE."}
    $text=($output -join "`n")
    try{$payload=$text | ConvertFrom-Json}catch{Fail 'Self-test parser probe did not return JSON.'}
    if($payload.ok -ne $false -or [string]$payload.command -cne $ExpectedCommand -or [string]::IsNullOrWhiteSpace([string]$payload.error)){Fail 'Self-test parser error contract failed.'}
    if($ExpectedErrorPattern -and [string]$payload.error -notlike $ExpectedErrorPattern){Fail "Self-test parser error did not match $ExpectedErrorPattern."}
}

function Assert-ExplicitRootGuard([string]$Root) {
    $statePath = Join-Path $Root $script:StateFile
    $before = [IO.File]::ReadAllBytes($statePath)
    $oldHelloHome = [Environment]::GetEnvironmentVariable('HELLO_HOME', 'Process')
    [Environment]::SetEnvironmentVariable('HELLO_HOME', $Root, 'Process')
    try {
        $output = @(& $script:HostCommand -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:SelfPath record-disclosure --confirmed 2>&1)
        if($LASTEXITCODE -ne 2){Fail 'Self-test mutation without explicit root did not fail.'}
        try { $payload = (($output -join "`n") | ConvertFrom-Json) } catch { Fail 'Self-test root-guard probe did not return JSON.' }
        if($payload.ok -ne $false -or [string]$payload.error -notlike '*--root*'){Fail 'Self-test root-guard error contract failed.'}
    } finally {
        [Environment]::SetEnvironmentVariable('HELLO_HOME', $oldHelloHome, 'Process')
    }
    $after = [IO.File]::ReadAllBytes($statePath)
    if(-not [Linq.Enumerable]::SequenceEqual($before,$after)){Fail 'Self-test root-guard probe changed state.'}
}

function Assert-CaseSensitiveInputs([string]$Root) {
    Assert-CliParserError @('STATUS','--root',$Root) 'STATUS' 'Unknown command*'
    Assert-CliParserError @('resolve-root','--ROOT',$Root) 'resolve-root' 'Unknown option*'
    Assert-CliParserError @('status','--r',$Root) 'status' '*Unknown option*'
    Assert-CliParserError @('status','--root='+$Root) 'status' '*separate*'
    Assert-CliParserError @('status','--root','   ') 'status' '*cannot be empty*'
    Assert-CliParserError @('status','--root',$Root,'--root',$Root) 'status' '*Duplicate option*'
    $statePath=Join-Path $Root $script:StateFile
    $before=Read-State $statePath
    $accepted=$false
    try { [void](Configure-Space $Root 'PROMPT' $null $null $true); $accepted=$true } catch { }
    if($accepted){Fail 'Self-test accepted a case-variant capture mode.'}
    $after=Read-State $statePath
    if([string]$after['capture_mode'] -cne [string]$before['capture_mode']){Fail 'Case-variant capture mode changed state.'}
}

function Assert-DisclosureGate([string]$Root,[string]$InputPath) {
    $statePath=Join-Path $Root $script:StateFile
    $state=Read-State $statePath
    $state['last_capture_disclosed_at']='2030-01-01T00:00:00Z'
    if($state.Contains('last_capture_disclosed_mode')){[void]$state.Remove('last_capture_disclosed_mode')}
    Write-State $statePath $state
    $valid=Validate-Space $Root
    if(-not $valid.ok){Fail 'Self-test rejected a legacy disclosure timestamp without a mode.'}
    try{[void](Stage-Candidate $Root $InputPath '经历' '自测' $true);Fail 'Self-test stage accepted a disclosure timestamp without a mode.'}
    catch{if($_.Exception.Message-notlike'*disclos*'){throw}}
}

function Invoke-SelfTest {
    $temporary=Join-Path ([IO.Path]::GetTempPath()) ('hello-self-test-'+[Guid]::NewGuid().ToString('N'))
    Assert-CliParserError @('not-a-command') 'not-a-command';Assert-CliParserError @('status','--unknown-option') 'status';Assert-CliParserError @('status','--simulate-failure') 'status';Assert-CliParserError @('status','--root','--confirmed') 'status' '*Missing value*';Assert-CliParserError @('status','--confirmed') 'status';Assert-CliParserError @('configure','--capture-mode','prompt','--confirmed') 'configure' '*requires --root*'
    try{$root=Join-Path $temporary '中文 空格';try{[void](Initialize-Space $root $false);Fail 'Confirmation guard did not fail.'}catch{if($_.Exception.Message-notlike'Mutating commands require*'){throw}};[void](Initialize-Space $root $true);if((Initialize-Space $root $true).created.Count-ne0){Fail 'Self-test init overwrote existing space.'};$valid=Validate-Space $root;if(-not$valid.ok){Fail ('Self-test init failed: '+($valid.issues -join '; '))};Assert-CliParserError @('configure','--capture-mode','prompt','--confirmed') 'configure' '*requires --root*';Assert-ExplicitRootGuard $root;Assert-CaseSensitiveInputs $root;Assert-LfFiles $root;Assert-MalformedMarkerRejected $root;Assert-MissingBackupRejected $root;$state=Read-State (Join-Path $root $script:StateFile);if($state['capture_mode']-ne'prompt'){Fail 'Self-test capture default failed.'};$nines=('9' * 40 -join '');$zeros=('0' * 40 -join '');if((Increment-Decimal $nines)-ne('1'+$zeros) -or (Compare-Decimal $nines ('1'+$zeros)) -ge 0){Fail 'Self-test long decimal version handling failed.'};if((Test-Iso '2030-01-01T00:00:00+08:00' $false)){Fail 'Self-test accepted a non-UTC timestamp.'};if((Test-Iso '2030-02-30T00:00:00Z' $false)){Fail 'Self-test accepted an invalid calendar timestamp.'};if((Test-Iso '2030-01-01T00:00:00z' $false)){Fail 'Self-test accepted a lowercase UTC marker.'};$initialStatus=(Get-Status $root).payload;if($initialStatus.capture_strategy-ne'提示确认'-or$initialStatus.last_capture_disclosed_at-ne''-or$initialStatus.last_capture_disclosed_mode-ne''-or-not$initialStatus.baseline_closure_blocked-or$initialStatus.baseline_required_remaining.Count-eq0-or$initialStatus.long_term_backlog.Count-eq0-or$initialStatus.baseline_split_unknown){Fail 'Self-test status fields failed.'};$disclosed=Record-Disclosure $root 'prompt' $true;if($disclosed.capture_mode-ne'prompt'-or$disclosed.last_capture_disclosed_mode-ne'prompt'-or-not(Test-Iso ([string]$disclosed.last_capture_disclosed_at) $false)){Fail 'Self-test record-disclosure failed.'};$disclosedState=Read-State (Join-Path $root $script:StateFile);if($disclosedState['capture_mode']-ne'prompt'-or$disclosedState['last_capture_disclosed_mode']-ne'prompt'-or$disclosedState['last_capture_disclosed_at']-ne$disclosed.last_capture_disclosed_at){Fail 'Self-test record-disclosure state failed.'};try{[void](Record-Disclosure $root 'explicit' $true);Fail 'Self-test accepted a stale capture mode.'}catch{if($_.Exception.Message-notlike'*does not match*'){throw}};if((Read-State (Join-Path $root $script:StateFile))['last_capture_disclosed_at']-ne$disclosedState['last_capture_disclosed_at']){Fail 'Self-test stale disclosure changed state.'};$disclosedState['last_capture_disclosed_at']='';$disclosedState['last_capture_disclosed_mode']='';Write-State (Join-Path $root $script:StateFile) $disclosedState
        $stateSnapshot=[ordered]@{};foreach($key in $state.Keys){$stateSnapshot[$key]=$state[$key]};$legacyStatusState=[ordered]@{};foreach($key in $state.Keys){$legacyStatusState[$key]=$state[$key]};$legacyStatusState['schema_version']='1';[void]$legacyStatusState.Remove('progress_version');[void]$legacyStatusState.Remove('last_session_id');[void]$legacyStatusState.Remove('last_turn_id');Write-State (Join-Path $root $script:StateFile) $legacyStatusState;$legacyStatus=(Get-Status $root).payload;if(-not$legacyStatus.baseline_split_unknown){Fail 'Self-test legacy schema status failed.'};Write-State (Join-Path $root $script:StateFile) $stateSnapshot
        $note=Join-Path $temporary 'candidate.md';Write-Atomic $note "用户完成了一个重要项目。`n";Assert-DisclosureGate $root $note;$lockDir=Join-Path $root $script:LockDirectoryName;[IO.Directory]::CreateDirectory($lockDir)|Out-Null;try{[void](Stage-Candidate $root $note '经历' '自测' $true);Fail 'Self-test stage ignored an active profile lock.'}catch{if($_.Exception.Message-notlike'*busy*'){throw}};try{[void](Initialize-Space $root $true);Fail 'Self-test init ignored an active profile lock.'}catch{if($_.Exception.Message-notlike'*busy*'){throw}}finally{if([IO.Directory]::Exists($lockDir)){[IO.Directory]::Delete($lockDir,$true)}};$nested=Invoke-WithProfileLock $root { Invoke-WithProfileLock $root { 'nested-ok' } };if([string]$nested -cne 'nested-ok'){Fail 'Self-test profile lock was not reentrant.'};[void](Record-Disclosure $root 'prompt' $true);$staged=Stage-Candidate $root $note '经历' '自测' $true;Assert-CanonicalVersions $root;Assert-ConfigurePreservesDisclosure $root 'auto-stage';try{[void](Stage-Candidate $root $note '经历' '自测' $true);Fail 'Self-test stage accepted a policy without a matching disclosure.'}catch{if($_.Exception.Message-notlike'*disclos*'){throw}};[void](Record-Disclosure $root 'auto-stage' $true)
        $candidate=Join-Path $temporary 'profile.md';Write-Atomic $candidate ((Read-Text (Join-Path $root '个人全景档案.md')).Replace('尚未访谈。','已完成一项自测。')) ;$summary=Join-Path $temporary 'summary.md';Write-Atomic $summary (SelfTest-Summary);$legacyApplyState=[ordered]@{};$currentApplyState=Read-State (Join-Path $root $script:StateFile);foreach($key in $currentApplyState.Keys){$legacyApplyState[$key]=$currentApplyState[$key]};$legacyApplyState['schema_version']='1';[void]$legacyApplyState.Remove('progress_version');[void]$legacyApplyState.Remove('last_session_id');[void]$legacyApplyState.Remove('last_turn_id');$legacyApplyState['legacy_marker']='keep';Write-State (Join-Path $root $script:StateFile) $legacyApplyState;$progressPath=Join-Path $root '访谈进度.md';$legacyProgress=Read-Text $progressPath;Write-Atomic $progressPath ([regex]::Replace($legacyProgress,'(?m)^- 进度版本：.*\r?\n',''))
        try{[void](Apply-Profile $root $candidate $summary '1' $true $true);Fail 'Simulated failure did not fail.'}catch{if($_.Exception.Message-notlike'* rolled back*'){throw}};if((Read-State (Join-Path $root $script:StateFile))['profile_version']-cne'1'){Fail 'Rollback did not restore version.'};if((Read-Text $progressPath)-match '(?m)^- 进度版本：'){Fail 'Rollback unexpectedly added progress metadata.'};$applied=Apply-Profile $root $candidate $summary '1' $true;if([string]$applied.profile_version -cne '2'){Fail 'Apply failed.'};$migratedState=Read-State (Join-Path $root $script:StateFile);if($migratedState['schema_version']-ne'2'-or$migratedState['progress_version']-cne'1'-or$migratedState['last_session_id']-ne''-or$migratedState['last_turn_id']-ne'') {Fail 'Schema 1 apply migration defaults failed.'};if($migratedState['legacy_marker']-ne'keep'){Fail 'Schema 1 unknown state key was not preserved.'};if(-not((Read-Text $progressPath)-match '(?m)^- 进度版本：1$')){Fail 'Schema 1 apply did not add progress metadata.'};if((Get-ChildItem -LiteralPath (Join-Path $root '.backups\transactions') -File).Count-ne0){Fail 'Transaction backups were not cleaned after apply.'};if((Read-State (Join-Path $root $script:StateFile))['review_stage']-ne'baseline'){Fail 'Apply changed review stage.'}
        $turn=Join-Path $temporary 'turn.md';Write-Atomic $turn "# 单轮记录`n`n- 已确认：自测。`n";$progress=Join-Path $temporary 'progress.md';Write-Atomic $progress ((Read-Text (Join-Path $root '访谈进度.md')).Replace('尚未开始。','下一项自测。'));$recorded=Record-Turn $root $turn $progress '2030-01-01-session-1' 'turn-1' '1' $true;if([string]$recorded.progress_version -cne '2'-or-not$recorded.new_session_required-or-not($recorded.session_termination_reasons-contains'cross-natural-day')){Fail 'Session termination warning failed.'};if((Get-ChildItem -LiteralPath (Join-Path $root '.backups\transactions') -File).Count-ne0){Fail 'Transaction backups were not cleaned after record-turn.'};$retry=Record-Turn $root $turn $progress '2030-01-01-session-1' 'turn-1' '1' $true;if(-not$retry.idempotent){Fail 'Record turn retry was not idempotent.'};$turn2=Join-Path $temporary 'turn-2.md';Write-Atomic $turn2 "# 第二轮记录`n`n- 仅使用隔离自测数据。`n";$progress2=Join-Path $temporary 'progress-2.md';Write-Atomic $progress2 ((Read-Text (Join-Path $root '访谈进度.md')).Replace('下一项自测。','第二项自测。'));$recorded2=Record-Turn $root $turn2 $progress2 '2030-01-01-session-1' 'turn-2' '2' $true;if($recorded2.idempotent){Fail 'Second record-turn unexpectedly idempotent.'};$oldRetry=Record-Turn $root $turn $progress '2030-01-01-session-1' 'turn-1' '1' $true;if(-not$oldRetry.idempotent){Fail 'Old record-turn retry was not idempotent.'}
        try{[void](Configure-Space $root $null $null 'first-review' $true);Fail 'First review guard did not fail.'}catch{if($_.Exception.Message-notlike'Entering first-review*'){throw}};[void](Configure-Space $root $null '2030-01-01T00:00:00Z' 'first-review' $true);$beforeClear=Read-State (Join-Path $root $script:StateFile);try{[void](Configure-Space $root $null 'none' $null $true);Fail 'First review clear guard did not fail.'}catch{if($_.Exception.Message-notlike'first-review requires*'){throw}};$afterClear=Read-State (Join-Path $root $script:StateFile);if($afterClear['next_review_at']-ne$beforeClear['next_review_at']){Fail 'First review clear changed state.'};[void](Withdraw-Candidate $root $staged.candidate_id $true);$final=Validate-Space $root;if(-not$final.ok){Fail ('Self-test final validation failed: '+($final.issues -join '; '))};return @{'ok'=$true;'command'='self-test'}
    }finally{if([IO.Directory]::Exists($temporary)){Remove-Item -LiteralPath $temporary -Recurse -Force}}
}

try {
    if([string]::IsNullOrWhiteSpace($Command)){Fail 'Command is required.'};$allowed=@('resolve-root','init','validate','status','configure','record-disclosure','diff','stage','apply','record-turn','withdraw','recover','target-validate','migrate-plan','migrate-apply','rebuild-index','switch-layout','rollback-layout','self-test');if($allowed-cnotcontains$Command){Fail ('Unknown command: '+$Command)}
    if($Command-ceq'self-test'){
        if($null -ne $Remaining -and $Remaining.Count -gt 0){Fail "Unexpected argument: $($Remaining[0])"}
        Write-Json (Invoke-SelfTest);exit 0
    };$parsed=Parse-Arguments $Remaining;$values=$parsed.values;$confirmed=[bool]$parsed.flags.confirmed;$simulateFailure=[bool]$parsed.flags['simulate-failure'];Validate-CommandArguments $Command $values $parsed.flags
    if(@('init','configure','record-disclosure','stage','apply','record-turn','withdraw','recover','migrate-apply','rebuild-index','switch-layout','rollback-layout') -ccontains $Command -and -not $values.ContainsKey('root')){Fail "$Command requires --root for mutating operations."}
    if($Command -ceq 'migrate-plan' -and $confirmed -and -not $values.ContainsKey('root')){Fail 'Confirmed migrate-plan requires --root.'}
    if (@('target-validate','rebuild-index') -ccontains $Command -and $values.ContainsKey('target')) {
        if ($values.ContainsKey('root')) { Fail "$Command accepts either --root or --target, not both." }
        $root=Resolve-ExplicitPath $values['target'] 'target'
    } else {
        $root=Resolve-ProfileRoot $values['root'] $values.ContainsKey('root')
    }
    switch($Command){
        'resolve-root'{Write-Json @{'ok'=$true;'command'=$Command;'root'=$root};exit 0}
        'init'{Write-Json (Initialize-Space $root $confirmed);exit 0}
        'validate'{$result=Validate-Space $root;Write-Json $result;if($result.ok){exit 0}else{exit 1}}
        'status'{$result=Get-Status $root;Write-Json $result.payload;exit $result.code}
        'configure'{Write-Json (Configure-Space $root $values['capture-mode'] $values['next-review-at'] $values['review-stage'] $confirmed $values.ContainsKey('capture-mode') $values.ContainsKey('next-review-at') $values.ContainsKey('review-stage'));exit 0}
        'record-disclosure'{Write-Json (Record-Disclosure $root $values['capture-mode'] $confirmed $values.ContainsKey('capture-mode'));exit 0}
        'diff'{if(-not$values.ContainsKey('input')){Fail 'diff requires --input.'};Show-Diff $root ([IO.Path]::GetFullPath($values['input']));exit 0}
        'stage'{if(-not$values.ContainsKey('input')){Fail 'stage requires --input.'};Write-Json (Stage-Candidate $root ([IO.Path]::GetFullPath($values['input'])) $values['kind'] $values['source'] $confirmed);exit 0}
        'apply'{foreach($name in @('input','summary-input','expected-version')){if(-not$values.ContainsKey($name)){Fail "apply requires --$name."}};if(-not(Test-PositiveDecimal ([string]$values['expected-version']))){Fail '--expected-version must be a positive decimal integer.'};Write-Json (Apply-Profile $root ([IO.Path]::GetFullPath($values['input'])) ([IO.Path]::GetFullPath($values['summary-input'])) ([string]$values['expected-version']) $confirmed $simulateFailure);exit 0}
        'record-turn'{foreach($name in @('input','progress-input','session-id','turn-id','expected-progress-version')){if(-not$values.ContainsKey($name)){Fail "record-turn requires --$name."}};if(-not(Test-PositiveDecimal ([string]$values['expected-progress-version']))){Fail '--expected-progress-version must be a positive decimal integer.'};Write-Json (Record-Turn $root ([IO.Path]::GetFullPath($values['input'])) ([IO.Path]::GetFullPath($values['progress-input'])) $values['session-id'] $values['turn-id'] ([string]$values['expected-progress-version']) $confirmed $simulateFailure);exit 0}
        'withdraw'{if(-not$values.ContainsKey('id')){Fail 'withdraw requires --id.'};Write-Json (Withdraw-Candidate $root $values['id'] $confirmed);exit 0}
        'recover'{Write-Json (Recover-Transaction $root $confirmed);exit 0}
        'target-validate'{$result=Target-Validate $root;Write-Json $result;if($result.ok){exit 0}else{exit 1}}
        'migrate-plan'{foreach($name in @('target')){if(-not$values.ContainsKey($name)){Fail "migrate-plan requires --$name."}};$target=Resolve-ExplicitPath $values['target'] 'target';$migrationId=if($values.ContainsKey('migration-id')){[string]$values['migration-id']}else{'hello-migration-'+(Get-Date).ToUniversalTime().ToString('yyyyMMdd')};Write-Json (Migrate-Plan $root $target $migrationId $confirmed);exit 0}
        'migrate-apply'{foreach($name in @('target','destination','expected-version','expected-progress-version')){if(-not$values.ContainsKey($name)){Fail "migrate-apply requires --$name."}};$target=Resolve-ExplicitPath $values['target'] 'target';$destination=Resolve-ExplicitPath $values['destination'] 'destination';Write-Json (Migrate-Apply $root $target $destination ([string]$values['expected-version']) ([string]$values['expected-progress-version']) $confirmed $simulateFailure);exit 0}
        'rebuild-index'{Write-Json (Rebuild-Index $root $confirmed);exit 0}
        'switch-layout'{foreach($name in @('target','migration-id','expected-version','expected-progress-version')){if(-not$values.ContainsKey($name)){Fail "switch-layout requires --$name."}};$target=Resolve-ExplicitPath $values['target'] 'target';$migrationId=[string]$values['migration-id'];Write-Json (Switch-Layout $root $target $migrationId ([string]$values['expected-version']) ([string]$values['expected-progress-version']) $confirmed $simulateFailure);exit 0}
        'rollback-layout'{if(-not$values.ContainsKey('migration-id')){Fail 'rollback-layout requires --migration-id.'};Write-Json (Rollback-Layout $root ([string]$values['migration-id']) $confirmed);exit 0}
    }
} catch { Write-Json @{'ok'=$false;'command'=$Command;'error'=$_.Exception.Message};exit 2 }
