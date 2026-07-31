#requires -version 5.1
<#
.SYNOPSIS
Native Windows storage adapter for the writing-style skill.
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
$script:IdPattern = '^[a-z0-9][a-z0-9-]{0,63}$'
$script:SchemaVersion = '1'
$script:AllowedCommands = @(
    'resolve-root', 'init', 'validate', 'list', 'diff',
    'save', 'set-default', 'delete', 'self-test'
)

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
    $flags = @{}
    $flagNames = @('--confirmed', '--replace', '--clear-default')
    $valueNames = @('--root', '--kind', '--id', '--input', '--expected-version')
    for ($index = 0; $index -lt $Items.Count; $index++) {
        $item = $Items[$index]
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }
        if ($flagNames -contains $item) {
            $flags[$item] = $true
            continue
        }
        if ($valueNames -contains $item) {
            if ($index + 1 -ge $Items.Count) {
                Fail "Missing value for $item."
            }
            $index++
            $values[$item] = $Items[$index]
            continue
        }
        Fail "Unknown argument: $item"
    }
    return @{ Values = $values; Flags = $flags }
}

function Get-Option($Parsed, [string]$Name, [bool]$Required = $false) {
    if ($Parsed.Values.ContainsKey($Name)) {
        return [string]$Parsed.Values[$Name]
    }
    if ($Required) {
        Fail "Missing required argument: $Name"
    }
    return $null
}

function Has-Flag($Parsed, [string]$Name) {
    return $Parsed.Flags.ContainsKey($Name)
}

function Resolve-StoreRoot([string]$ExplicitRoot) {
    if ($ExplicitRoot) {
        $raw = $ExplicitRoot
        $source = 'explicit'
    }
    elseif ($env:WRITING_STYLE_HOME) {
        $raw = $env:WRITING_STYLE_HOME
        $source = 'environment'
    }
    else {
        $raw = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.writing-style'
        $source = 'home'
    }
    if ($raw -eq '~') {
        $raw = [Environment]::GetFolderPath('UserProfile')
    }
    elseif ($raw.StartsWith('~\') -or $raw.StartsWith('~/')) {
        $raw = Join-Path ([Environment]::GetFolderPath('UserProfile')) $raw.Substring(2)
    }
    $expanded = [Environment]::ExpandEnvironmentVariables($raw)
    return @{
        Root = [IO.Path]::GetFullPath($expanded)
        Source = $source
    }
}

function Assert-Confirmed([bool]$Confirmed) {
    if (-not $Confirmed) {
        Fail 'Mutating commands require --confirmed after explicit user confirmation.'
    }
}

function Assert-ProfileId([string]$ProfileId) {
    if (-not $ProfileId -or $ProfileId -notmatch $script:IdPattern) {
        Fail 'Profile id must match [a-z0-9][a-z0-9-]{0,63}.'
    }
}

function Assert-Kind([string]$Kind) {
    if ($Kind -ne 'personal' -and $Kind -ne 'reference') {
        Fail 'Kind must be personal or reference.'
    }
}

function Get-KindDirectory([string]$Kind) {
    Assert-Kind $Kind
    if ($Kind -eq 'personal') { return 'personal-profiles' }
    return 'reference-profiles'
}

function Read-Utf8([string]$Path) {
    if (-not [IO.File]::Exists($Path)) {
        Fail "Missing file: $Path"
    }
    try {
        return [IO.File]::ReadAllText($Path)
    }
    catch {
        Fail "Cannot read ${Path}: $($_.Exception.Message)"
    }
}

function Normalize-Text([string]$Content) {
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $normalized.EndsWith("`n")) {
        $normalized += "`n"
    }
    return $normalized
}

function Write-Atomic([string]$Path, [string]$Content) {
    $directory = [IO.Path]::GetDirectoryName($Path)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporary = Join-Path $directory ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, (Normalize-Text $Content), $script:Utf8NoBom)
        if ([IO.File]::Exists($Path)) {
            $replaceBackup = $temporary + '.replace-backup'
            [IO.File]::Replace($temporary, $Path, $replaceBackup, $true)
            [IO.File]::Delete($replaceBackup)
        }
        else {
            [IO.File]::Move($temporary, $Path)
        }
    }
    catch {
        if ([IO.File]::Exists($temporary)) {
            [IO.File]::Delete($temporary)
        }
        Fail "Cannot write ${Path}: $($_.Exception.Message)"
    }
}

function Render-Config([string]$DefaultProfile) {
    return "# 声纹用户空间`n`n- schema_version: $($script:SchemaVersion)`n- default_personal_profile: $DefaultProfile`n"
}

function Parse-Metadata([string]$Content) {
    $metadata = @{}
    foreach ($line in ($Content -split "`r?`n")) {
        if ($line -match '^##\s') { break }
        if ($line -match '^- ([a-z_]+):\s*(.*?)\s*$') {
            $metadata[$Matches[1]] = $Matches[2]
        }
    }
    return $metadata
}

function Parse-Config([string]$Content) {
    $values = Parse-Metadata $Content
    if ($values['schema_version'] -ne $script:SchemaVersion) {
        Fail "Unsupported or missing schema_version; expected $($script:SchemaVersion)."
    }
    $defaultProfile = $values['default_personal_profile']
    if (-not $defaultProfile) {
        Fail 'Missing default_personal_profile in config.md.'
    }
    if ($defaultProfile -ne 'none') {
        Assert-ProfileId $defaultProfile
    }
    return $values
}

function Load-Config([string]$Root) {
    $path = Join-Path $Root 'config.md'
    if (-not [IO.File]::Exists($path)) {
        Fail "Missing config: $path"
    }
    return Parse-Config (Read-Utf8 $path)
}

function Get-ProfilePath([string]$Root, [string]$Kind, [string]$ProfileId) {
    Assert-ProfileId $ProfileId
    return Join-Path (Join-Path $Root (Get-KindDirectory $Kind)) ($ProfileId + '.md')
}

function Parse-Profile([string]$Content, [string]$Kind, [string]$ProfileId) {
    Assert-Kind $Kind
    Assert-ProfileId $ProfileId
    $metadata = Parse-Metadata $Content
    foreach ($field in @('id', 'type', 'version', 'status', 'updated_at')) {
        if (-not $metadata[$field]) {
            Fail "Missing profile field: $field"
        }
    }
    if ($metadata['id'] -ne $ProfileId) {
        Fail "Profile id '$($metadata['id'])' does not match target '$ProfileId'."
    }
    if ($metadata['type'] -ne $Kind) {
        Fail "Profile type must be '$Kind'."
    }
    $version = 0
    if (-not [int]::TryParse($metadata['version'], [ref]$version) -or $version -lt 1) {
        Fail 'Profile version must be an integer of at least 1.'
    }
    if ($metadata['status'] -ne 'candidate' -and $metadata['status'] -ne 'confirmed') {
        Fail 'Profile status must be candidate or confirmed.'
    }
    $parsedDate = [DateTime]::MinValue
    if (-not [DateTime]::TryParseExact(
        $metadata['updated_at'],
        'yyyy-MM-dd',
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None,
        [ref]$parsedDate
    )) {
        Fail 'updated_at must use YYYY-MM-DD.'
    }
    $metadata['version'] = $version
    return $metadata
}

function Validate-ProfileFile([string]$Path, [string]$Kind, [string]$ProfileId) {
    if (-not [IO.File]::Exists($Path)) {
        Fail "Missing profile: $Path"
    }
    return Parse-Profile (Read-Utf8 $Path) $Kind $ProfileId
}

function Get-Timestamp {
    return [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')
}

function Backup-File([string]$Root, [string]$Source, [string]$Category) {
    $directory = Join-Path (Join-Path $Root '.backups') $Category
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $name = [IO.Path]::GetFileNameWithoutExtension($Source) + '-' + (Get-Timestamp) + [IO.Path]::GetExtension($Source)
    $backup = Join-Path $directory $name
    [IO.File]::Copy($Source, $backup, $false)
    return $backup
}

function Initialize-Space([string]$Root, [bool]$Confirmed) {
    Assert-Confirmed $Confirmed
    $created = @()
    foreach ($name in @('personal-profiles', 'reference-profiles')) {
        $directory = Join-Path $Root $name
        if ([IO.File]::Exists($directory)) {
            Fail "Expected directory but found file: $directory"
        }
        if (-not [IO.Directory]::Exists($directory)) {
            [IO.Directory]::CreateDirectory($directory) | Out-Null
            $created += $directory
        }
    }
    $configPath = Join-Path $Root 'config.md'
    if ([IO.Directory]::Exists($configPath)) {
        Fail "Expected file but found directory: $configPath"
    }
    if (-not [IO.File]::Exists($configPath)) {
        Write-Atomic $configPath (Render-Config 'none')
        $created += $configPath
    }
    [void](Load-Config $Root)
    return @{
        ok = $true
        command = 'init'
        root = $Root
        created = $created
        idempotent = ($created.Count -eq 0)
    }
}

function Test-Space([string]$Root) {
    $errors = @()
    $profiles = @()
    $config = $null
    try { $config = Load-Config $Root } catch { $errors += $_.Exception.Message }
    foreach ($kind in @('personal', 'reference')) {
        $directory = Join-Path $Root (Get-KindDirectory $kind)
        if (-not [IO.Directory]::Exists($directory)) {
            $errors += "Missing directory: $directory"
            continue
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $directory -Filter '*.md' -File | Sort-Object Name)) {
            $profileId = [IO.Path]::GetFileNameWithoutExtension($file.Name)
            try {
                $metadata = Validate-ProfileFile $file.FullName $kind $profileId
                $profiles += @{
                    kind = $kind
                    path = $file.FullName
                    id = $metadata['id']
                    type = $metadata['type']
                    version = $metadata['version']
                    status = $metadata['status']
                    updated_at = $metadata['updated_at']
                }
            }
            catch {
                $errors += "$($file.FullName): $($_.Exception.Message)"
            }
        }
    }
    if ($null -ne $config -and $config['default_personal_profile'] -ne 'none') {
        $defaultPath = Get-ProfilePath $Root 'personal' $config['default_personal_profile']
        if (-not [IO.File]::Exists($defaultPath)) {
            $errors += "Default personal profile does not exist: $defaultPath"
        }
    }
    return @{
        ok = ($errors.Count -eq 0)
        command = 'validate'
        root = $Root
        platform = 'windows'
        profiles = $profiles
        errors = $errors
    }
}

function Get-Profiles([string]$Root, [string]$Kind) {
    $kinds = if ($Kind) { Assert-Kind $Kind; @($Kind) } else { @('personal', 'reference') }
    $profiles = @()
    $errors = @()
    try {
        [void](Load-Config $Root)
    }
    catch {
        $errors += $_.Exception.Message
    }
    foreach ($selectedKind in $kinds) {
        $directory = Join-Path $Root (Get-KindDirectory $selectedKind)
        if (-not [IO.Directory]::Exists($directory)) {
            $errors += "Missing directory: $directory"
            continue
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $directory -Filter '*.md' -File | Sort-Object Name)) {
            $profileId = [IO.Path]::GetFileNameWithoutExtension($file.Name)
            try {
                $metadata = Validate-ProfileFile $file.FullName $selectedKind $profileId
                $profiles += @{
                    kind = $selectedKind
                    path = $file.FullName
                    id = $metadata['id']
                    type = $metadata['type']
                    version = $metadata['version']
                    status = $metadata['status']
                    updated_at = $metadata['updated_at']
                }
            }
            catch {
                $errors += "$($file.FullName): $($_.Exception.Message)"
            }
        }
    }
    return @{
        ok = ($errors.Count -eq 0)
        command = 'list'
        root = $Root
        profiles = $profiles
        errors = $errors
    }
}

function Compare-Profile([string]$Root, [string]$Kind, [string]$ProfileId, [string]$InputPath) {
    $candidate = Read-Utf8 $InputPath
    [void](Parse-Profile $candidate $Kind $ProfileId)
    $target = Get-ProfilePath $Root $Kind $ProfileId
    $current = if ([IO.File]::Exists($target)) { Read-Utf8 $target } else { '' }
    if ((Normalize-Text $current) -eq (Normalize-Text $candidate)) {
        return "No changes.`n"
    }
    $oldName = if ($current) { $target } else { '/dev/null' }
    $lines = @("--- $oldName", "+++ $target", '@@ full-file replacement @@')
    if ($current) {
        $lines += (($current -split "`r?`n") | ForEach-Object { '-' + $_ })
    }
    $lines += (($candidate -split "`r?`n") | ForEach-Object { '+' + $_ })
    return (($lines -join "`n") + "`n")
}

function Save-Profile(
    [string]$Root,
    [string]$Kind,
    [string]$ProfileId,
    [string]$InputPath,
    [bool]$Confirmed,
    [bool]$Replace,
    [int]$ExpectedVersion
) {
    Assert-Confirmed $Confirmed
    [void](Load-Config $Root)
    $candidate = Read-Utf8 $InputPath
    $newMetadata = Parse-Profile $candidate $Kind $ProfileId
    $target = Get-ProfilePath $Root $Kind $ProfileId
    $backup = $null
    if ([IO.File]::Exists($target)) {
        if (-not $Replace) {
            Fail "Profile already exists; use --replace with --expected-version: $target"
        }
        $oldMetadata = Validate-ProfileFile $target $Kind $ProfileId
        $oldVersion = [int]$oldMetadata['version']
        if ($ExpectedVersion -ne $oldVersion) {
            Fail "Expected version must match current version $oldVersion."
        }
        if ([int]$newMetadata['version'] -ne $oldVersion + 1) {
            Fail "Replacement version must be $($oldVersion + 1)."
        }
        $backup = Backup-File $Root $target $Kind
    }
    elseif ($Replace) {
        Fail 'Cannot use --replace for a profile that does not exist.'
    }
    elseif ([int]$newMetadata['version'] -ne 1) {
        Fail 'A new profile must start at version 1.'
    }
    Write-Atomic $target $candidate
    return @{
        ok = $true
        command = 'save'
        root = $Root
        operation = $(if ($backup) { 'replace' } else { 'create' })
        path = $target
        version = [int]$newMetadata['version']
        backup = $backup
    }
}

function Set-DefaultProfile([string]$Root, [string]$ProfileId, [bool]$Confirmed) {
    Assert-Confirmed $Confirmed
    $config = Load-Config $Root
    if ($ProfileId -ne 'none') {
        [void](Validate-ProfileFile (Get-ProfilePath $Root 'personal' $ProfileId) 'personal' $ProfileId)
    }
    $oldDefault = $config['default_personal_profile']
    if ($oldDefault -eq $ProfileId) {
        return @{
            ok = $true
            command = 'set-default'
            root = $Root
            changed = $false
            default_personal_profile = $ProfileId
        }
    }
    $configPath = Join-Path $Root 'config.md'
    $backup = Backup-File $Root $configPath 'config'
    Write-Atomic $configPath (Render-Config $ProfileId)
    return @{
        ok = $true
        command = 'set-default'
        root = $Root
        changed = $true
        old_default = $oldDefault
        default_personal_profile = $ProfileId
        backup = $backup
    }
}

function Remove-Profile(
    [string]$Root,
    [string]$Kind,
    [string]$ProfileId,
    [bool]$Confirmed,
    [bool]$ClearDefault
) {
    Assert-Confirmed $Confirmed
    $config = Load-Config $Root
    $target = Get-ProfilePath $Root $Kind $ProfileId
    [void](Validate-ProfileFile $target $Kind $ProfileId)
    $isDefault = $Kind -eq 'personal' -and $config['default_personal_profile'] -eq $ProfileId
    if ($isDefault -and -not $ClearDefault) {
        Fail 'Profile is the default; use --clear-default after user confirmation.'
    }
    $trashDirectory = Join-Path (Join-Path $Root '.trash') $Kind
    [IO.Directory]::CreateDirectory($trashDirectory) | Out-Null
    $trash = Join-Path $trashDirectory ($ProfileId + '-' + (Get-Timestamp) + '.md')
    [IO.File]::Move($target, $trash)
    try {
        if ($isDefault) {
            [void](Set-DefaultProfile $Root 'none' $true)
        }
    }
    catch {
        [IO.File]::Move($trash, $target)
        throw
    }
    return @{
        ok = $true
        command = 'delete'
        root = $Root
        deleted = $target
        recoverable_at = $trash
        default_cleared = $isDefault
    }
}

function New-SampleProfile([string]$ProfileId, [int]$Version) {
    $today = [DateTime]::UtcNow.ToString('yyyy-MM-dd')
    return @"
# 测试风格

- id: $ProfileId
- type: personal
- version: $Version
- status: confirmed
- updated_at: $today

## 来源

- 作者：测试
"@
}

function Expect-Failure([scriptblock]$Action) {
    try {
        & $Action
    }
    catch {
        return $true
    }
    return $false
}

function Invoke-SelfTest {
    $base = Join-Path ([IO.Path]::GetTempPath()) ('writing-style-原生 测试-' + [Guid]::NewGuid().ToString('N'))
    $root = Join-Path $base '用户 空间'
    $checks = @()
    try {
        [IO.Directory]::CreateDirectory($base) | Out-Null

        $savedEnvironment = $env:WRITING_STYLE_HOME
        $env:WRITING_STYLE_HOME = Join-Path $base '环境'
        $resolved = Resolve-StoreRoot $root
        $checks += @{ name = 'root precedence'; passed = ($resolved.Root -eq [IO.Path]::GetFullPath($root) -and $resolved.Source -eq 'explicit') }
        $env:WRITING_STYLE_HOME = $savedEnvironment

        $checks += @{ name = 'confirmation guard'; passed = (Expect-Failure { Initialize-Space $root $false | Out-Null }) }
        $checks += @{ name = 'unicode and space path'; passed = ($root -match '原生 测试' -and $root -match '用户 空间') }

        $init = Initialize-Space $root $true
        $checks += @{ name = 'initialize'; passed = ($init.ok -and [IO.File]::Exists((Join-Path $root 'config.md'))) }

        $invalid = Join-Path $base 'invalid-root'
        [IO.File]::WriteAllText($invalid, 'not a directory', $script:Utf8NoBom)
        $invalidResult = Test-Space $invalid
        $checks += @{ name = 'invalid root'; passed = (-not $invalidResult.ok) }

        $candidate1 = Join-Path $base 'candidate-1.md'
        [IO.File]::WriteAllText($candidate1, (New-SampleProfile 'my-style' 1), $script:Utf8NoBom)
        $created = Save-Profile $root 'personal' 'my-style' $candidate1 $true $false -1
        $checks += @{ name = 'create profile'; passed = ($created.operation -eq 'create' -and $created.version -eq 1) }

        $defaultResult = Set-DefaultProfile $root 'my-style' $true
        $checks += @{ name = 'set default'; passed = ($defaultResult.default_personal_profile -eq 'my-style') }

        $candidate2 = Join-Path $base 'candidate-2.md'
        [IO.File]::WriteAllText($candidate2, (New-SampleProfile 'my-style' 2), $script:Utf8NoBom)
        $difference = Compare-Profile $root 'personal' 'my-style' $candidate2
        $checks += @{ name = 'diff'; passed = ($difference -match '^--- ' -and $difference -match '\+\+\+ ') }

        $checks += @{ name = 'expected version guard'; passed = (Expect-Failure { Save-Profile $root 'personal' 'my-style' $candidate2 $true $true 9 | Out-Null }) }

        $updated = Save-Profile $root 'personal' 'my-style' $candidate2 $true $true 1
        $checks += @{ name = 'versioned update'; passed = ($updated.operation -eq 'replace' -and $updated.version -eq 2 -and $updated.backup) }

        $validation = Test-Space $root
        $checks += @{ name = 'validate'; passed = ($validation.ok -and $validation.profiles.Count -eq 1) }

        $checks += @{ name = 'default delete guard'; passed = (Expect-Failure { Remove-Profile $root 'personal' 'my-style' $true $false | Out-Null }) }

        $deleted = Remove-Profile $root 'personal' 'my-style' $true $true
        $checks += @{ name = 'recoverable delete'; passed = ([IO.File]::Exists($deleted.recoverable_at) -and -not [IO.File]::Exists($deleted.deleted)) }

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
    if (-not $Command -or $script:AllowedCommands -notcontains $Command) {
        Fail ('Command must be one of: ' + ($script:AllowedCommands -join ', ') + '.')
    }
    $parsed = Parse-Options @($RemainingArgs)
    if ($Command -eq 'self-test') {
        if (@($RemainingArgs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
            Fail 'self-test does not accept arguments.'
        }
        Write-Json (Invoke-SelfTest)
        exit 0
    }

    $rootInfo = Resolve-StoreRoot (Get-Option $parsed '--root')
    $root = $rootInfo.Root
    switch ($Command) {
        'resolve-root' {
            Write-Json @{
                ok = $true
                command = $Command
                root = $root
                source = $rootInfo.Source
                platform = 'windows'
                adapter = 'powershell'
                runtime = $PSVersionTable.PSVersion.ToString()
            }
            exit 0
        }
        'init' {
            Write-Json (Initialize-Space $root (Has-Flag $parsed '--confirmed'))
            exit 0
        }
        'validate' {
            $result = Test-Space $root
            $result['source'] = $rootInfo.Source
            Write-Json $result
            if ($result.ok) { exit 0 } else { exit 1 }
        }
        'list' {
            $result = Get-Profiles $root (Get-Option $parsed '--kind')
            Write-Json $result
            if ($result.ok) { exit 0 } else { exit 1 }
        }
        'diff' {
            $kind = Get-Option $parsed '--kind' $true
            $profileId = Get-Option $parsed '--id' $true
            $inputPath = Get-Option $parsed '--input' $true
            [Console]::Out.Write((Compare-Profile $root $kind $profileId $inputPath))
            exit 0
        }
        'save' {
            $expectedText = Get-Option $parsed '--expected-version'
            $expected = -1
            if ($expectedText) {
                $parsedVersion = 0
                if (-not [int]::TryParse($expectedText, [ref]$parsedVersion) -or $parsedVersion -lt 1) {
                    Fail '--expected-version must be a positive integer.'
                }
                $expected = $parsedVersion
            }
            Write-Json (Save-Profile `
                $root `
                (Get-Option $parsed '--kind' $true) `
                (Get-Option $parsed '--id' $true) `
                (Get-Option $parsed '--input' $true) `
                (Has-Flag $parsed '--confirmed') `
                (Has-Flag $parsed '--replace') `
                $expected)
            exit 0
        }
        'set-default' {
            Write-Json (Set-DefaultProfile $root (Get-Option $parsed '--id' $true) (Has-Flag $parsed '--confirmed'))
            exit 0
        }
        'delete' {
            Write-Json (Remove-Profile `
                $root `
                (Get-Option $parsed '--kind' $true) `
                (Get-Option $parsed '--id' $true) `
                (Has-Flag $parsed '--confirmed') `
                (Has-Flag $parsed '--clear-default'))
            exit 0
        }
    }
}
catch {
    Write-Json @{ ok = $false; command = $Command; error = $_.Exception.Message } $true
    exit 2
}
