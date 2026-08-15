[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Remaining
)

$ErrorActionPreference = 'Stop'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:StrictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
$script:Files = @('README.md', '个人全景档案.md', '待确认信息.md', '访谈进度.md', '资料索引.md', '迭代日志.md')
$script:Directories = @('原始访谈', '历史版本', '.backups', '.trash')
$script:StateFile = '.hello-state'
$script:TransactionFile = '.hello-transaction'
$script:ProfileSections = @(
    '## 一、当前起点', '## 二、人生时间线与关键经历', '## 三、能力、经验与证据',
    '## 四、知识、认知与学习方式', '## 五、健康、精力与可持续边界', '## 六、经济、资源与风险承受能力',
    '## 七、关系、支持网络与现实责任', '## 八、习惯、行动与决策方式', '## 九、价值观、世界观与人生愿景',
    '## 十、当前目标与未来设想', '## 十一、AI 协作偏好', '## 十二、未知、冲突与 AI 假设', '## 十三、主要来源'
)
$script:ProgressSections = @('## 已覆盖主题', '## 待补充主题', '## 暂不收集', '## 下次问题')
$script:SummaryFields = @('触发原因', '信息来源', '更新类型', '更新位置', '更新摘要', '用户确认状态', '执行工具')

function Write-Json([hashtable]$Value) {
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    [Console]::WriteLine(($Value | ConvertTo-Json -Compress -Depth 10))
}

function Fail([string]$Message) { throw [InvalidOperationException]::new($Message) }
function Utc-Now { return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
function File-Stamp { return (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') }

function Parse-Arguments([string[]]$Items) {
    $values = @{}
    $flags = @{'confirmed' = $false}
    $valueNames = @(
        'root', 'input', 'summary-input', 'expected-version', 'kind', 'source', 'id',
        'capture-mode', 'next-review-at', 'review-stage', 'progress-input', 'session-id',
        'turn-id', 'expected-progress-version'
    )
    for ($index = 0; $index -lt $Items.Count; $index++) {
        $token = $Items[$index]
        if ($token -eq '--confirmed') { $flags['confirmed'] = $true; continue }
        if (-not $token.StartsWith('--')) { Fail "Unexpected argument: $token" }
        $name = $token.Substring(2)
        if ($valueNames -notcontains $name) { Fail "Unknown option: $token" }
        if ($index + 1 -ge $Items.Count) { Fail "Missing value for $token" }
        $index++; $values[$name] = $Items[$index]
    }
    return @{'values' = $values; 'flags' = $flags}
}

function Resolve-ProfileRoot([string]$Value) {
    $raw = $Value
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = [Environment]::GetEnvironmentVariable('HELLO_HOME') }
    if ([string]::IsNullOrWhiteSpace($raw)) { Fail 'Personal profile root is not configured. Pass --root or set HELLO_HOME.' }
    if ($raw -eq '~') { $raw = [Environment]::GetFolderPath('UserProfile') }
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

function Read-KeyValues([string]$Path) {
    $state = [ordered]@{}; $number = 0
    foreach ($line in (Read-Text $Path) -split "`r?`n") {
        $number++
        if ([string]::IsNullOrEmpty($line) -or $line.StartsWith('#')) { continue }
        $position = $line.IndexOf('=')
        if ($position -lt 1) { Fail "Invalid key=value line $number in $([IO.Path]::GetFileName($Path))." }
        $key = $line.Substring(0, $position)
        if ($state.Contains($key)) { Fail "Duplicate key on line $number in $([IO.Path]::GetFileName($Path))." }
        $state[$key] = $line.Substring($position + 1)
    }
    return $state
}

function Read-State([string]$Path) { return Read-KeyValues $Path }

function Write-State([string]$Path, [System.Collections.IDictionary]$State) {
    $order = @(
        'schema_version', 'profile_version', 'progress_version', 'capture_mode', 'created_at', 'updated_at',
        'last_confirmed_at', 'next_review_at', 'review_stage', 'last_session_id', 'last_turn_id'
    )
    $builder = New-Object Text.StringBuilder
    foreach ($key in $order) { if ($State.Contains($key)) { [void]$builder.Append($key).Append('=').Append([string]$State[$key]).Append("`n") } }
    foreach ($key in ($State.Keys | Where-Object { $order -notcontains $_ } | Sort-Object)) {
        [void]$builder.Append($key).Append('=').Append([string]$State[$key]).Append("`n")
    }
    Write-Atomic $Path $builder.ToString()
}

function Test-Iso([string]$Value, [bool]$AllowEmpty = $true) {
    if ([string]::IsNullOrEmpty($Value)) { return $AllowEmpty }
    if (-not $Value.Contains('T')) { return $false }
    $parsed = [DateTimeOffset]::MinValue
    return [DateTimeOffset]::TryParse($Value, [ref]$parsed)
}

function Get-ProgressVersion([System.Collections.IDictionary]$State) {
    if ($State.Contains('progress_version')) { return [int]$State['progress_version'] }
    return 1
}

function Test-State([System.Collections.IDictionary]$State) {
    $issues = New-Object Collections.Generic.List[string]
    $required = @('schema_version','profile_version','capture_mode','created_at','updated_at','last_confirmed_at','next_review_at','review_stage')
    foreach ($key in $required) { if (-not $State.Contains($key)) { $issues.Add("Missing state key: $key") } }
    if (@('1','2') -notcontains [string]$State['schema_version']) { $issues.Add('schema_version must be 1 or 2') }
    if ($State['schema_version'] -eq '2') { foreach($key in @('progress_version','last_session_id','last_turn_id')) { if(-not $State.Contains($key)){$issues.Add("Missing state key: $key")} } }
    foreach ($key in @('profile_version','progress_version')) {
        if ($key -eq 'progress_version' -and $State['schema_version'] -eq '1' -and -not $State.Contains($key)) { continue }
        $number = 0
        if (-not [int]::TryParse([string]$State[$key], [ref]$number) -or $number -lt 1) { $issues.Add("$key must be a positive integer") }
    }
    if (@('auto-stage','prompt','explicit') -notcontains $State['capture_mode']) { $issues.Add('capture_mode must be auto-stage, prompt, or explicit') }
    if (@('baseline','first-review','stable') -notcontains $State['review_stage']) { $issues.Add('review_stage must be baseline, first-review, or stable') }
    if ($State['review_stage'] -eq 'first-review' -and [string]::IsNullOrWhiteSpace([string]$State['next_review_at'])) { $issues.Add('first-review requires next_review_at') }
    foreach ($key in @('created_at','updated_at')) { if ($State.Contains($key) -and -not (Test-Iso ([string]$State[$key]) $false)) { $issues.Add("$key must be ISO 8601") } }
    foreach ($key in @('last_confirmed_at','next_review_at')) { if ($State.Contains($key) -and -not (Test-Iso ([string]$State[$key]) $true)) { $issues.Add("$key must be empty or ISO 8601") } }
    return $issues.ToArray()
}

function Count-Matches([string]$Content, [string]$Pattern) { return ([regex]::Matches($Content, $Pattern)).Count }

function Test-ProfileContent([string]$Content, $ExpectedVersion) {
    $issues = New-Object Collections.Generic.List[string]
    if (-not $Content.StartsWith("# 个人全景档案`n")) { $issues.Add('Profile must start with # 个人全景档案') }
    $versions = [regex]::Matches($Content, '(?m)^- 资料版本：([0-9]+)$')
    if ($versions.Count -ne 1) { $issues.Add('资料版本 metadata must appear exactly once') }
    elseif ($null -ne $ExpectedVersion -and [int]$versions[0].Groups[1].Value -ne [int]$ExpectedVersion) { $issues.Add("Profile version $($versions[0].Groups[1].Value) does not match state version $ExpectedVersion") }
    if ((Count-Matches $Content '(?m)^- 最近确认时间：.+$') -ne 1) { $issues.Add('最近确认时间 metadata must appear exactly once') }
    foreach ($heading in $script:ProfileSections) { if ((Count-Matches $Content ('(?m)^' + [regex]::Escape($heading) + '$')) -ne 1) { $issues.Add("Missing or duplicate profile section: $($heading.Substring(3))") } }
    return $issues.ToArray()
}

function Test-ProgressContent([string]$Content, $ExpectedVersion, [bool]$RequireVersion) {
    $issues = New-Object Collections.Generic.List[string]
    if (-not $Content.StartsWith("# 访谈进度`n")) { $issues.Add('Interview progress must start with # 访谈进度') }
    $versions = [regex]::Matches($Content, '(?m)^- 进度版本：([0-9]+)$')
    if ($versions.Count -gt 1) { $issues.Add('进度版本 metadata must appear at most once') }
    elseif ($RequireVersion -and $versions.Count -eq 0) { $issues.Add('Missing progress metadata: 进度版本') }
    elseif ($versions.Count -eq 1 -and $null -ne $ExpectedVersion -and [int]$versions[0].Groups[1].Value -ne [int]$ExpectedVersion) { $issues.Add("Progress version $($versions[0].Groups[1].Value) does not match state version $ExpectedVersion") }
    foreach ($heading in $script:ProgressSections) { if ((Count-Matches $Content ('(?m)^' + [regex]::Escape($heading) + '$')) -ne 1) { $issues.Add("Missing or duplicate progress section: $($heading.Substring(3))") } }
    return $issues.ToArray()
}

function Test-LogContent([string]$Content, [int]$ProfileVersion) {
    $issues = New-Object Collections.Generic.List[string]
    $headings = @([regex]::Matches($Content, '(?m)^## R([0-9]+) · ') | ForEach-Object { [int]$_.Groups[1].Value })
    if (($headings | Select-Object -Unique).Count -ne $headings.Count) { $issues.Add('Iteration log contains duplicate version headings') }
    if ($ProfileVersion -gt 1 -and $headings -notcontains $ProfileVersion) { $issues.Add("Iteration log is missing version R$ProfileVersion") }
    return $issues.ToArray()
}

function Initialize-Space([string]$Root, [bool]$Confirmed) {
    Require-Confirmed $Confirmed
    [IO.Directory]::CreateDirectory($Root) | Out-Null
    $templateRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\assets\profile-templates'))
    $created = New-Object Collections.Generic.List[string]
    foreach ($name in $script:Directories) { $target = Join-Path $Root $name; if (-not [IO.Directory]::Exists($target)) { [IO.Directory]::CreateDirectory($target) | Out-Null; $created.Add($name + '/') } }
    foreach ($name in $script:Files) { $target = Join-Path $Root $name; if (-not [IO.File]::Exists($target)) { [IO.File]::Copy((Join-Path $templateRoot $name), $target, $false); $created.Add($name) } }
    $statePath = Join-Path $Root $script:StateFile
    if (-not [IO.File]::Exists($statePath)) {
        $current = Utc-Now
        $state = [ordered]@{
            schema_version='2'; profile_version='1'; progress_version='1'; capture_mode='prompt';
            created_at=$current; updated_at=$current; last_confirmed_at=''; next_review_at=''; review_stage='baseline';
            last_session_id=''; last_turn_id=''
        }
        Write-State $statePath $state; $created.Add($script:StateFile)
    }
    return @{'ok'=$true;'command'='init';'root'=$Root;'created'=$created.ToArray()}
}

function Validate-Space([string]$Root, [bool]$IgnoreTransaction = $false) {
    $issues = New-Object Collections.Generic.List[string]; $state = $null
    if (-not [IO.Directory]::Exists($Root)) { $issues.Add('Root directory does not exist') }
    else {
        if (-not $IgnoreTransaction -and [IO.File]::Exists((Join-Path $Root $script:TransactionFile))) { $issues.Add('Interrupted transaction exists; run recover --confirmed') }
        foreach ($name in $script:Files) { if (-not [IO.File]::Exists((Join-Path $Root $name))) { $issues.Add("Missing file: $name") } }
        foreach ($name in $script:Directories) { if (-not [IO.Directory]::Exists((Join-Path $Root $name))) { $issues.Add("Missing directory: $name") } }
        $statePath = Join-Path $Root $script:StateFile
        if (-not [IO.File]::Exists($statePath)) { $issues.Add("Missing file: $($script:StateFile)") }
        else { try { $state = Read-State $statePath; foreach ($issue in (Test-State $state)) { $issues.Add($issue) } } catch { $issues.Add($_.Exception.Message) } }
        if ($null -ne $state -and (Test-State $state).Count -eq 0) {
            try {
                foreach ($issue in (Test-ProfileContent (Read-Text (Join-Path $Root '个人全景档案.md')) ([int]$state['profile_version']))) { $issues.Add($issue) }
                foreach ($issue in (Test-ProgressContent (Read-Text (Join-Path $Root '访谈进度.md')) (Get-ProgressVersion $state) ($state['schema_version'] -eq '2'))) { $issues.Add($issue) }
                foreach ($issue in (Test-LogContent (Read-Text (Join-Path $Root '迭代日志.md')) ([int]$state['profile_version']))) { $issues.Add($issue) }
                $candidateIds = @([regex]::Matches((Read-Text (Join-Path $Root '待确认信息.md')), '(?m)^## (C-[0-9TZ-]+)\s*$') | ForEach-Object { $_.Groups[1].Value })
                if (($candidateIds | Select-Object -Unique).Count -ne $candidateIds.Count) { $issues.Add('Pending candidates contain duplicate ids') }
            } catch { $issues.Add($_.Exception.Message) }
        }
    }
    return @{'ok'=($issues.Count -eq 0);'command'='validate';'root'=$Root;'issues'=$issues.ToArray()}
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

function Get-Status([string]$Root) {
    $valid = Validate-Space $Root
    if (-not $valid.ok) { return @{'payload'=@{'ok'=$false;'command'='status';'root'=$Root;'issues'=$valid.issues};'code'=1} }
    $state = Read-State (Join-Path $Root $script:StateFile)
    $pending = ([regex]::Matches((Read-Text (Join-Path $Root '待确认信息.md')), '(?m)^## C-[0-9TZ-]+\s*$')).Count
    $payload = @{
        'ok'=$true;'command'='status';'root'=$Root;'profile_version'=[int]$state['profile_version'];
        'progress_version'=(Get-ProgressVersion $state);'capture_mode'=$state['capture_mode'];'review_stage'=$state['review_stage'];
        'last_confirmed_at'=$state['last_confirmed_at'];'next_review_at'=$state['next_review_at'];'last_session_id'=$state['last_session_id'];'last_turn_id'=$state['last_turn_id'];'pending_candidates'=$pending;
        'progress'=(Get-ProgressSummary (Read-Text (Join-Path $Root '访谈进度.md')))
    }
    return @{'payload'=$payload;'code'=0}
}

function Configure-Space([string]$Root,[string]$CaptureMode,[string]$NextReviewAt,[string]$ReviewStage,[bool]$Confirmed) {
    Require-Confirmed $Confirmed; $state = Require-Valid $Root
    if ([string]::IsNullOrWhiteSpace($CaptureMode) -and $null -eq $NextReviewAt -and [string]::IsNullOrWhiteSpace($ReviewStage)) { Fail 'configure requires at least one setting.' }
    if (-not [string]::IsNullOrWhiteSpace($CaptureMode)) { if (@('auto-stage','prompt','explicit') -notcontains $CaptureMode) { Fail '--capture-mode must be auto-stage, prompt, or explicit.' }; $state['capture_mode']=$CaptureMode }
    if (-not [string]::IsNullOrWhiteSpace($ReviewStage)) {
        if (@('baseline','first-review','stable') -notcontains $ReviewStage) { Fail '--review-stage must be baseline, first-review, or stable.' }
        if ($ReviewStage -eq 'first-review' -and ($null -eq $NextReviewAt -or $NextReviewAt -eq '' -or $NextReviewAt -eq 'none') -and [string]::IsNullOrWhiteSpace([string]$state['next_review_at'])) { Fail 'Entering first-review requires --next-review-at.' }
        $state['review_stage']=$ReviewStage
    }
    if ($null -ne $NextReviewAt) { if ($NextReviewAt -eq 'none' -or $NextReviewAt -eq '') { $state['next_review_at']='' } elseif (-not (Test-Iso $NextReviewAt $false)) { Fail '--next-review-at must be ISO 8601 or none.' } else { $state['next_review_at']=$NextReviewAt } }
    $state['updated_at']=Utc-Now; Write-State (Join-Path $Root $script:StateFile) $state
    return @{'ok'=$true;'command'='configure';'root'=$Root;'capture_mode'=$state['capture_mode'];'review_stage'=$state['review_stage'];'next_review_at'=$state['next_review_at']}
}

function Show-Diff([string]$Root,[string]$InputPath) {
    [void](Require-Valid $Root)
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

function Clean-Label([string]$Value,[string]$Fallback) { if([string]::IsNullOrWhiteSpace($Value)){return $Fallback}; $clean=([regex]::Replace($Value,'\s+',' ')).Trim(); if($clean.Length -gt 200){return $clean.Substring(0,200)}; return $clean }

function Stage-Candidate([string]$Root,[string]$InputPath,[string]$Kind,[string]$Source,[bool]$Confirmed) {
    Require-Confirmed $Confirmed; $state=Require-Valid $Root; $body=(Read-Text $InputPath).Trim(); if([string]::IsNullOrWhiteSpace($body)){Fail 'Candidate input is empty.'}
    $current=Utc-Now; $candidateId='C-'+(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')+'-'+$PID; $pendingPath=Join-Path $Root '待确认信息.md'
    $pending=(Read-Text $pendingPath).Replace("`n当前没有待确认信息。`n","`n")
    $block="`n## $candidateId`n`n- 暂存时间：$current`n- 类型：$(Clean-Label $Kind '未分类')`n- 来源：$(Clean-Label $Source '当前会话')`n- 状态：待确认`n`n$body`n"
    Write-Atomic $pendingPath ($pending.TrimEnd()+"`n"+$block); $state['updated_at']=$current; Write-State (Join-Path $Root $script:StateFile) $state
    return @{'ok'=$true;'command'='stage';'root'=$Root;'candidate_id'=$candidateId}
}

function Copy-Unique([string]$Source,[string]$Directory,[string]$Name) {
    [IO.Directory]::CreateDirectory($Directory)|Out-Null; $target=Join-Path $Directory $Name; $counter=1
    while([IO.File]::Exists($target)){ $target=Join-Path $Directory (([IO.Path]::GetFileNameWithoutExtension($Name))+'-'+$counter+[IO.Path]::GetExtension($Name));$counter++ }
    [IO.File]::Copy($Source,$target,$false); return $target
}

function Relative-ToRoot([string]$Root,[string]$Path) { $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'; $full=[IO.Path]::GetFullPath($Path); if(-not $full.StartsWith($rootFull,[StringComparison]::OrdinalIgnoreCase)){Fail "Transaction path escapes profile root: $Path"}; return $full.Substring($rootFull.Length).Replace('\','/') }
function Resolve-TransactionPath([string]$Root,[string]$Relative) { $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'; $full=[IO.Path]::GetFullPath((Join-Path $Root $Relative)); if(-not $full.StartsWith($rootFull,[StringComparison]::OrdinalIgnoreCase)){Fail 'Transaction backup path escapes profile root.'}; return $full }

function Begin-Transaction([string]$Root,[System.Collections.IDictionary]$Values) {
    $marker=Join-Path $Root $script:TransactionFile; if([IO.File]::Exists($marker)){Fail 'Interrupted transaction exists; run recover --confirmed.'}
    $builder=New-Object Text.StringBuilder; [void]$builder.Append("schema_version=1`n"); foreach($key in $Values.Keys){[void]$builder.Append($key).Append('=').Append([string]$Values[$key]).Append("`n")}; Write-Atomic $marker $builder.ToString()
}

function Recover-Transaction([string]$Root,[bool]$Confirmed) {
    Require-Confirmed $Confirmed; $marker=Join-Path $Root $script:TransactionFile; if(-not [IO.File]::Exists($marker)){Fail 'No interrupted transaction exists.'}; $values=Read-KeyValues $marker
    $map=[ordered]@{'profile_backup'='个人全景档案.md';'log_backup'='迭代日志.md';'state_backup'=$script:StateFile;'progress_backup'='访谈进度.md'}; $restored=New-Object Collections.Generic.List[string]
    foreach($key in $map.Keys){if($values.Contains($key)-and -not [string]::IsNullOrWhiteSpace([string]$values[$key])){$backup=Resolve-TransactionPath $Root $values[$key];if(-not [IO.File]::Exists($backup)){Fail "Missing transaction backup: $($values[$key])"};Write-Atomic (Join-Path $Root $map[$key]) (Read-Text $backup);$restored.Add($map[$key])}}
    if($values.Contains('record_path')-and $values['record_created'] -eq 'true'){$record=Resolve-TransactionPath $Root $values['record_path'];if([IO.File]::Exists($record)){[IO.File]::Delete($record)}}
    [IO.File]::Delete($marker);$valid=Validate-Space $Root;if(-not $valid.ok){Fail ('Recovery completed but profile space is invalid: '+($valid.issues -join '; '))}
    return @{'ok'=$true;'command'='recover';'root'=$Root;'restored'=$restored.ToArray()}
}

function Rollback-Failure([string]$Root,[Exception]$Original) { try{[void](Recover-Transaction $Root $true)}catch{Fail "Operation failed: $($Original.Message). Automatic rollback failed: $($_.Exception.Message). Run recover --confirmed."};Fail "Operation failed and was rolled back: $($Original.Message)" }

function Update-ProfileHeader([string]$Content,[int]$Version,[string]$ConfirmedAt) { $v=New-Object Text.RegularExpressions.Regex('(?m)^- 资料版本：.*$');$t=New-Object Text.RegularExpressions.Regex('(?m)^- 最近确认时间：.*$');if($v.Matches($Content).Count-ne1-or$t.Matches($Content).Count-ne1){Fail 'Candidate profile must contain 资料版本 and 最近确认时间 metadata lines.'};return $t.Replace($v.Replace($Content,"- 资料版本：$Version",1),"- 最近确认时间：$ConfirmedAt",1) }
function Update-ProgressHeader([string]$Content,[int]$Version){$r=New-Object Text.RegularExpressions.Regex('(?m)^- 进度版本：.*$');if($r.Matches($Content).Count-gt0){return $r.Replace($Content,"- 进度版本：$Version",1)};return $Content.Replace("# 访谈进度`n","# 访谈进度`n`n- 进度版本：$Version",1)}
function Canonical-Profile([string]$Content){return ([regex]::Replace([regex]::Replace($Content,'(?m)^- 资料版本：.*$','- 资料版本：<version>'),'(?m)^- 最近确认时间：.*$','- 最近确认时间：<time>')).Trim()}

function Test-Summary([string]$Summary){$invalid=New-Object Collections.Generic.List[string];foreach($field in $script:SummaryFields){if(([regex]::Matches($Summary,'(?m)^- '+[regex]::Escape($field)+'：.+$')).Count-ne1){$invalid.Add($field)}};if($invalid.Count){Fail ('Update summary requires exactly one of each field: '+($invalid -join ', '))};$type=[regex]::Match($Summary,'(?m)^- 更新类型：(.+)$').Groups[1].Value.Trim().TrimEnd([char[]]'。.;；');if(@('新增','状态变化','事实纠正','解释变化','假设验证','撤回隐藏')-contains$type){return};Fail 'Update summary contains an invalid update type.'}

function Apply-Profile([string]$Root,[string]$InputPath,[string]$SummaryPath,[int]$ExpectedVersion,[bool]$Confirmed,[bool]$SimulateFailure=$false) {
    Require-Confirmed $Confirmed;$state=Require-Valid $Root;$currentVersion=[int]$state['profile_version'];if($ExpectedVersion-ne$currentVersion){Fail "Version conflict: expected $ExpectedVersion, current $currentVersion."}
    $candidate=(Read-Text $InputPath).Trim()+"`n";$summary=(Read-Text $SummaryPath).Trim();$issues=Test-ProfileContent $candidate $null;if($issues.Count){Fail ('Invalid candidate profile: '+($issues -join '; '))};Test-Summary $summary
    $profilePath=Join-Path $Root '个人全景档案.md';$currentProfile=Read-Text $profilePath;if((Canonical-Profile $currentProfile)-ceq(Canonical-Profile $candidate)){Fail 'Candidate profile has no content changes.'}
    $current=Utc-Now;$newVersion=$currentVersion+1;$candidate=Update-ProfileHeader $candidate $newVersion $current;$name=(File-Stamp)+"-v$currentVersion-个人全景档案.md"
    $history=Copy-Unique $profilePath (Join-Path $Root '历史版本') $name;$backup=Copy-Unique $profilePath (Join-Path $Root '.backups\profile') $name;$transactionDir=Join-Path $Root '.backups\transactions';$logPath=Join-Path $Root '迭代日志.md';$statePath=Join-Path $Root $script:StateFile
    $logBackup=Copy-Unique $logPath $transactionDir ((File-Stamp)+"-v$currentVersion-迭代日志.md");$stateBackup=Copy-Unique $statePath $transactionDir ((File-Stamp)+"-v$currentVersion-hello-state")
    Begin-Transaction $Root ([ordered]@{'kind'='apply';'profile_backup'=(Relative-ToRoot $Root $backup);'log_backup'=(Relative-ToRoot $Root $logBackup);'state_backup'=(Relative-ToRoot $Root $stateBackup)})
    try{Write-Atomic $profilePath $candidate;if($SimulateFailure){Fail 'simulated failure after profile write'};$log=(Read-Text $logPath).Replace("`n当前没有正式迭代。`n","`n").TrimEnd();$entry="`n`n## R$newVersion · $current`n`n- 资料版本：$newVersion`n- 确认状态：用户已确认`n- 历史快照：``历史版本/$([IO.Path]::GetFileName($history))```n`n$summary`n";Write-Atomic $logPath ($log+$entry);$state['profile_version']=[string]$newVersion;$state['updated_at']=$current;$state['last_confirmed_at']=$current;Write-State $statePath $state;$valid=Validate-Space $Root $true;if(-not $valid.ok){Fail ('Post-write validation failed: '+($valid.issues -join '; '))}}catch{Rollback-Failure $Root $_.Exception}
    [IO.File]::Delete((Join-Path $Root $script:TransactionFile));return @{'ok'=$true;'command'='apply';'root'=$Root;'old_version'=$currentVersion;'profile_version'=$newVersion;'history'=$history;'backup'=$backup}
}

function Record-Turn([string]$Root,[string]$InputPath,[string]$ProgressInput,[string]$SessionId,[string]$TurnId,[int]$ExpectedProgressVersion,[bool]$Confirmed) {
    Require-Confirmed $Confirmed;$state=Require-Valid $Root
    if($SessionId-notmatch'^[0-9]{4}-[0-9]{2}-[0-9]{2}[A-Za-z0-9._-]{0,117}$'-or$TurnId-notmatch'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'){Fail 'session-id must start with YYYY-MM-DD; ids may only use ASCII letters, digits, dot, underscore, or hyphen.'}
    $body=(Read-Text $InputPath).Trim();if([string]::IsNullOrWhiteSpace($body)){Fail 'Turn input is empty.'};$year=$SessionId.Substring(0,4);$recordPath=Join-Path $Root "原始访谈\$year\$SessionId\$TurnId.md"
    if($state['last_session_id']-eq$SessionId-and$state['last_turn_id']-eq$TurnId-and[IO.File]::Exists($recordPath)){if((Read-Text $recordPath).Trim()-cne$body){Fail 'Idempotent turn retry has different content.'};return @{'ok'=$true;'command'='record-turn';'root'=$Root;'session_id'=$SessionId;'turn_id'=$TurnId;'record'=$recordPath;'created'=$false;'idempotent'=$true;'progress_version'=(Get-ProgressVersion $state)}}
    $currentVersion=Get-ProgressVersion $state;if($ExpectedProgressVersion-ne$currentVersion){Fail "Progress version conflict: expected $ExpectedProgressVersion, current $currentVersion."};if([IO.File]::Exists($recordPath)){Fail 'Turn id already exists but is not the current idempotency key.'}
    $progress=(Read-Text $ProgressInput).Trim()+"`n";$issues=Test-ProgressContent $progress $null $false;if($issues.Count){Fail ('Invalid progress input: '+($issues -join '; '))};$newVersion=$currentVersion+1;$progress=Update-ProgressHeader $progress $newVersion
    $transactionDir=Join-Path $Root '.backups\transactions';$progressPath=Join-Path $Root '访谈进度.md';$statePath=Join-Path $Root $script:StateFile;$tag=File-Stamp;$progressBackup=Copy-Unique $progressPath $transactionDir "$tag-p$currentVersion-访谈进度.md";$stateBackup=Copy-Unique $statePath $transactionDir "$tag-p$currentVersion-hello-state"
    Begin-Transaction $Root ([ordered]@{'kind'='record-turn';'progress_backup'=(Relative-ToRoot $Root $progressBackup);'state_backup'=(Relative-ToRoot $Root $stateBackup);'record_path'=(Relative-ToRoot $Root $recordPath);'record_created'='true'})
    try{Write-Atomic $recordPath ($body+"`n");Write-Atomic $progressPath $progress;$state['schema_version']='2';$state['progress_version']=[string]$newVersion;$state['last_session_id']=$SessionId;$state['last_turn_id']=$TurnId;$state['updated_at']=Utc-Now;Write-State $statePath $state;$valid=Validate-Space $Root $true;if(-not$valid.ok){Fail ('Post-write validation failed: '+($valid.issues -join '; '))}}catch{Rollback-Failure $Root $_.Exception}
    [IO.File]::Delete((Join-Path $Root $script:TransactionFile));return @{'ok'=$true;'command'='record-turn';'root'=$Root;'session_id'=$SessionId;'turn_id'=$TurnId;'record'=$recordPath;'created'=$true;'idempotent'=$false;'progress_version'=$newVersion}
}

function Withdraw-Candidate([string]$Root,[string]$CandidateId,[bool]$Confirmed){Require-Confirmed $Confirmed;$state=Require-Valid $Root;if($CandidateId-notmatch'^C-[0-9TZ-]+$'){Fail 'Invalid candidate id.'};$pendingPath=Join-Path $Root '待确认信息.md';$content=Read-Text $pendingPath;$pattern='(?ms)^## '+[regex]::Escape($CandidateId)+'\s*\r?\n.*?(?=^## C-[0-9TZ-]+\s*$|\z)';$match=[regex]::Match($content,$pattern);if(-not$match.Success){Fail "Candidate not found: $CandidateId"};$trashDir=Join-Path $Root '.trash\candidates';[IO.Directory]::CreateDirectory($trashDir)|Out-Null;$trash=Join-Path $trashDir ($CandidateId+'.md');if([IO.File]::Exists($trash)){$trash=Join-Path $trashDir ($CandidateId+'-'+(File-Stamp)+'.md')};Write-Atomic $trash ($match.Value.TrimEnd()+"`n");$remaining=($content.Remove($match.Index,$match.Length)).TrimEnd()+"`n";if($remaining-notmatch'(?m)^## C-[0-9TZ-]+\s*$'){$remaining=$remaining.TrimEnd()+"`n`n当前没有待确认信息。`n"};Write-Atomic $pendingPath $remaining;$state['updated_at']=Utc-Now;Write-State (Join-Path $Root $script:StateFile) $state;return @{'ok'=$true;'command'='withdraw';'root'=$Root;'candidate_id'=$CandidateId;'trash'=$trash}}

function SelfTest-Summary{return "- 触发原因：自测。`n- 信息来源：隔离测试。`n- 更新类型：新增。`n- 更新位置：当前起点。`n- 更新摘要：验证存储事务。`n- 用户确认状态：自测确认。`n- 执行工具：hello self-test。`n"}

function Invoke-SelfTest {
    $temporary=Join-Path ([IO.Path]::GetTempPath()) ('hello-self-test-'+[Guid]::NewGuid().ToString('N'))
    try{$root=Join-Path $temporary '中文 空格';try{[void](Initialize-Space $root $false);Fail 'Confirmation guard did not fail.'}catch{if($_.Exception.Message-notlike'Mutating commands require*'){throw}};[void](Initialize-Space $root $true);if((Initialize-Space $root $true).created.Count-ne0){Fail 'Self-test init overwrote existing space.'};$valid=Validate-Space $root;if(-not$valid.ok){Fail ('Self-test init failed: '+($valid.issues -join '; '))};$state=Read-State (Join-Path $root $script:StateFile);if($state['capture_mode']-ne'prompt'){Fail 'Self-test capture default failed.'}
        $note=Join-Path $temporary 'candidate.md';Write-Atomic $note "用户完成了一个重要项目。`n";$staged=Stage-Candidate $root $note '经历' '自测' $true;[void](Configure-Space $root 'auto-stage' $null $null $true)
        $candidate=Join-Path $temporary 'profile.md';Write-Atomic $candidate ((Read-Text (Join-Path $root '个人全景档案.md')).Replace('尚未访谈。','已完成一项自测。')) ;$summary=Join-Path $temporary 'summary.md';Write-Atomic $summary (SelfTest-Summary)
        try{[void](Apply-Profile $root $candidate $summary 1 $true $true);Fail 'Simulated failure did not fail.'}catch{if($_.Exception.Message-notlike'*rolled back*'){throw}};if((Read-State (Join-Path $root $script:StateFile))['profile_version']-ne'1'){Fail 'Rollback did not restore version.'};$applied=Apply-Profile $root $candidate $summary 1 $true;if($applied.profile_version-ne2){Fail 'Apply failed.'};if((Read-State (Join-Path $root $script:StateFile))['review_stage']-ne'baseline'){Fail 'Apply changed review stage.'}
        $turn=Join-Path $temporary 'turn.md';Write-Atomic $turn "# 单轮记录`n`n- 已确认：自测。`n";$progress=Join-Path $temporary 'progress.md';Write-Atomic $progress ((Read-Text (Join-Path $root '访谈进度.md')).Replace('尚未开始。','下一项自测。'));$recorded=Record-Turn $root $turn $progress '2030-01-01-session-1' 'turn-1' 1 $true;if($recorded.progress_version-ne2){Fail 'Record turn failed.'};$retry=Record-Turn $root $turn $progress '2030-01-01-session-1' 'turn-1' 1 $true;if(-not$retry.idempotent){Fail 'Record turn retry was not idempotent.'}
        try{[void](Configure-Space $root $null $null 'first-review' $true);Fail 'First review guard did not fail.'}catch{if($_.Exception.Message-notlike'Entering first-review*'){throw}};[void](Configure-Space $root $null '2030-01-01T00:00:00Z' 'first-review' $true);[void](Withdraw-Candidate $root $staged.candidate_id $true);$final=Validate-Space $root;if(-not$final.ok){Fail ('Self-test final validation failed: '+($final.issues -join '; '))};return @{'ok'=$true;'command'='self-test'}
    }finally{if([IO.Directory]::Exists($temporary)){Remove-Item -LiteralPath $temporary -Recurse -Force}}
}

try {
    if([string]::IsNullOrWhiteSpace($Command)){Fail 'Command is required.'};$allowed=@('resolve-root','init','validate','status','configure','diff','stage','apply','record-turn','withdraw','recover','self-test');if($allowed-notcontains$Command){Fail ('Unknown command: '+$Command)}
    if($Command-eq'self-test'){Write-Json (Invoke-SelfTest);exit 0};$parsed=Parse-Arguments $Remaining;$values=$parsed.values;$confirmed=[bool]$parsed.flags.confirmed;$root=Resolve-ProfileRoot $values['root']
    switch($Command){
        'resolve-root'{Write-Json @{'ok'=$true;'command'=$Command;'root'=$root};exit 0}
        'init'{Write-Json (Initialize-Space $root $confirmed);exit 0}
        'validate'{$result=Validate-Space $root;Write-Json $result;if($result.ok){exit 0}else{exit 1}}
        'status'{$result=Get-Status $root;Write-Json $result.payload;exit $result.code}
        'configure'{Write-Json (Configure-Space $root $values['capture-mode'] $values['next-review-at'] $values['review-stage'] $confirmed);exit 0}
        'diff'{if(-not$values.ContainsKey('input')){Fail 'diff requires --input.'};Show-Diff $root ([IO.Path]::GetFullPath($values['input']));exit 0}
        'stage'{if(-not$values.ContainsKey('input')){Fail 'stage requires --input.'};Write-Json (Stage-Candidate $root ([IO.Path]::GetFullPath($values['input'])) $values['kind'] $values['source'] $confirmed);exit 0}
        'apply'{foreach($name in @('input','summary-input','expected-version')){if(-not$values.ContainsKey($name)){Fail "apply requires --$name."}};$expected=0;if(-not[int]::TryParse($values['expected-version'],[ref]$expected)){Fail '--expected-version must be an integer.'};Write-Json (Apply-Profile $root ([IO.Path]::GetFullPath($values['input'])) ([IO.Path]::GetFullPath($values['summary-input'])) $expected $confirmed);exit 0}
        'record-turn'{foreach($name in @('input','progress-input','session-id','turn-id','expected-progress-version')){if(-not$values.ContainsKey($name)){Fail "record-turn requires --$name."}};$expected=0;if(-not[int]::TryParse($values['expected-progress-version'],[ref]$expected)){Fail '--expected-progress-version must be an integer.'};Write-Json (Record-Turn $root ([IO.Path]::GetFullPath($values['input'])) ([IO.Path]::GetFullPath($values['progress-input'])) $values['session-id'] $values['turn-id'] $expected $confirmed);exit 0}
        'withdraw'{if(-not$values.ContainsKey('id')){Fail 'withdraw requires --id.'};Write-Json (Withdraw-Candidate $root $values['id'] $confirmed);exit 0}
        'recover'{Write-Json (Recover-Transaction $root $confirmed);exit 0}
    }
} catch { Write-Json @{'ok'=$false;'command'=$Command;'error'=$_.Exception.Message};exit 2 }
