[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = 'audit',

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

$ErrorActionPreference = 'Stop'

function Assert-Equal {
    param([string]$Name, $Actual, $Expected)
    if ($Actual -ne $Expected) {
        throw "self-test failed: $Name expected '$Expected', got '$Actual'"
    }
}

function New-Layer {
    param([string]$Status, [string]$RuleId, [string]$Evidence, [string]$TargetHost = 'portable')
    [ordered]@{
        status = $Status
        rule_id = $RuleId
        source = 'skill-release-auditor/validation-contract-v1'
        host = $TargetHost
        evidence = $Evidence
    }
}

function ConvertFrom-PortableScalar {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -ne $Value.Trim()) { return $null }
    if ($Value -match '^"[^"\\]*"$' -or $Value -match "^'[^']*'$" ) {
        return $Value.Substring(1, $Value.Length - 2)
    }
    if ($Value -match '[\[\]{}&*!|>@`#]' -or $Value -match ':\s' -or $Value -match '["'']') { return $null }
    return $Value
}

function Test-Structure {
    param([string]$SkillFile)

    if (-not (Test-Path -LiteralPath $SkillFile -PathType Leaf)) {
        return [pscustomobject]@{
            Layer = New-Layer 'FAIL' 'SRA-STRUCT-001' 'SKILL.md is missing'
        }
    }

    $lines = [IO.File]::ReadAllLines($SkillFile)
    if ($lines.Count -lt 4 -or $lines[0] -ne '---') {
        return [pscustomobject]@{
            Layer = New-Layer 'FAIL' 'SRA-STRUCT-002' 'frontmatter must start on the first line'
        }
    }
    $closing = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq '---') { $closing = $i; break }
    }
    if ($closing -lt 2) {
        return [pscustomobject]@{
            Layer = New-Layer 'FAIL' 'SRA-STRUCT-002' 'frontmatter closing delimiter is missing'
        }
    }

    $frontmatter = @($lines[1..($closing - 1)])
    if ($frontmatter.Count -ne 2) {
        return [pscustomobject]@{
            Layer = New-Layer 'FAIL' 'SRA-STRUCT-003' 'frontmatter must contain only name and description'
            Name = $null
        }
    }
    $values = @{}
    foreach ($line in $frontmatter) {
        if ($line -notmatch '^(name|description): (.+)$' -or $values.ContainsKey($Matches[1])) {
            return [pscustomobject]@{
                Layer = New-Layer 'FAIL' 'SRA-STRUCT-003' 'frontmatter must contain name and description exactly once'
                Name = $null
            }
        }
        $parsed = ConvertFrom-PortableScalar $Matches[2]
        if ($null -eq $parsed -or $parsed.Length -eq 0) {
            return [pscustomobject]@{
                Layer = New-Layer 'FAIL' 'SRA-STRUCT-004' 'frontmatter uses a value outside the portable scalar subset'
                Name = $null
            }
        }
        $values[$Matches[1]] = $parsed
    }
    $parsedName = $values.name
    if ($parsedName.Length -gt 64 -or $parsedName -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        return [pscustomobject]@{
            Layer = New-Layer 'FAIL' 'SRA-STRUCT-006' 'skill name does not match the portable naming contract'
            Name = $parsedName
        }
    }
    return [pscustomobject]@{
        Layer = New-Layer 'PASS' 'SRA-STRUCT-005' 'frontmatter matches the portable two-field subset'
        Name = $parsedName
    }
}

function Test-Release {
    param([string]$SkillRoot)
    $textFiles = Get-ChildItem -LiteralPath $SkillRoot -Recurse -File | Where-Object { $_.Length -le 1MB }
    foreach ($file in $textFiles) {
        $content = [IO.File]::ReadAllText($file.FullName)
        if ($content -match '-----BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----') {
            return New-Layer 'FAIL' 'SRA-RELEASE-004' "private key material detected in $($file.Name)"
        }
        if ($file.Extension -in @('.md', '.yaml', '.yml', '.json', '.txt') -and
            $content -match '(?i)<owner>|<repo>|YOUR_GITHUB_USERNAME|TODO:\s*replace') {
            return New-Layer 'FAIL' 'SRA-RELEASE-003' "unresolved release placeholder detected in $($file.Name)"
        }
    }
    return New-Layer 'PASS' 'SRA-RELEASE-001' 'no deterministic release blocker was found'
}

function Test-DirectInstall {
    param([string]$SkillRoot, [string]$SkillName, [string]$AuditTempDirectory)
    $destination = Join-Path $AuditTempDirectory ('install\.agents\skills\' + $SkillName)
    [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
    Copy-Item -LiteralPath $SkillRoot -Destination $destination -Recurse
    if (-not (Test-Path -LiteralPath (Join-Path $destination 'SKILL.md') -PathType Leaf)) {
        return New-Layer 'FAIL' 'SRA-INSTALL-002' 'direct install did not create SKILL.md'
    }
    $sourceFiles = @(Get-ChildItem -LiteralPath $SkillRoot -Recurse -File)
    $installedFiles = @(Get-ChildItem -LiteralPath $destination -Recurse -File)
    if ($sourceFiles.Count -ne $installedFiles.Count) {
        return New-Layer 'FAIL' 'SRA-INSTALL-003' 'direct install file count differs from source'
    }
    foreach ($file in $sourceFiles) {
        $relative = $file.FullName.Substring($SkillRoot.TrimEnd('\').Length).TrimStart('\')
        $installed = Join-Path $destination $relative
        if (-not (Test-Path -LiteralPath $installed -PathType Leaf) -or
            (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash) {
            return New-Layer 'FAIL' 'SRA-INSTALL-003' "direct install content differs at $relative"
        }
    }
    return New-Layer 'PASS' 'SRA-INSTALL-001' 'direct isolated install matches the checked source'
}

function Invoke-Audit {
    param([string[]]$InputArguments)

    $source = $null
    $scope = 'full'
    $installer = 'direct'
    for ($i = 0; $i -lt $InputArguments.Count; $i++) {
        switch ($InputArguments[$i]) {
            '--source' {
                $i++
                if ($i -ge $InputArguments.Count) { throw '--source requires a value' }
                $source = $InputArguments[$i]
            }
            '--scope' {
                $i++
                if ($i -ge $InputArguments.Count -or $InputArguments[$i] -notin @('static', 'full')) { throw '--scope must be static or full' }
                $scope = $InputArguments[$i]
            }
            '--installer' {
                $i++
                if ($i -ge $InputArguments.Count -or $InputArguments[$i] -notin @('direct', 'none')) { throw '--installer must be direct or none' }
                $installer = $InputArguments[$i]
            }
            default { throw "unknown argument: $($InputArguments[$i])" }
        }
    }
    if ([string]::IsNullOrWhiteSpace($source)) { throw '--source is required' }
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw 'only local source paths are implemented' }
    $skillRoot = (Resolve-Path -LiteralPath $source).Path
    $auditTemp = Join-Path ([IO.Path]::GetTempPath()) ('skill-release-auditor-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($auditTemp) | Out-Null
    $result = $null
    try {
        $skillFile = Join-Path $skillRoot 'SKILL.md'
        $structureCheck = Test-Structure $skillFile
        $structure = $structureCheck.Layer
        $release = New-Layer 'NOT_RUN' 'SRA-RELEASE-000' 'stopped after structure'
        $install = New-Layer 'NOT_RUN' 'SRA-INSTALL-000' 'stopped after structure'
        if ($structure.status -eq 'PASS') {
            $release = Test-Release $skillRoot
            if ($release.status -eq 'PASS') {
                if ($installer -eq 'direct') {
                    $install = Test-DirectInstall $skillRoot $structureCheck.Name $auditTemp
                } else {
                    $install = New-Layer 'NOT_RUN' 'SRA-INSTALL-000' 'installer disabled by caller'
                }
            }
        }
        $layers = [ordered]@{
            remote = New-Layer 'NOT_RUN' 'SRA-REMOTE-000' 'local source path'
            structure = $structure
            release = $release
            install = $install
            discovery = New-Layer 'NOT_RUN' 'SRA-DISCOVERY-000' 'requires observable Codex host evidence' 'codex'
            behavior = New-Layer 'NOT_RUN' 'SRA-BEHAVIOR-000' 'requires confirmed behavior samples' 'codex'
        }
        $selected = @($structure.status, $release.status, $install.status)
        if ($scope -eq 'full') { $selected += @($layers.discovery.status, $layers.behavior.status) }
        $exitCode = if ($selected -contains 'FAIL') { 1 } elseif ($selected -contains 'BLOCKED' -or $selected -contains 'NOT_RUN') { 2 } else { 0 }
        $result = [ordered]@{
            schema_version = 1
            target = [ordered]@{ source = $skillRoot; skill = $structureCheck.Name; commit = $null }
            scope = $scope
            overall = if ($exitCode -eq 0) { 'PASS' } elseif ($exitCode -eq 1) { 'FAIL' } else { 'INCOMPLETE' }
            layers = $layers
            cleanup = [ordered]@{ status = 'PENDING'; residual_path = $auditTemp }
        }
    } finally {
        if (Test-Path -LiteralPath $auditTemp) { Remove-Item -LiteralPath $auditTemp -Recurse -Force }
        if ($null -ne $result) {
            if (Test-Path -LiteralPath $auditTemp) {
                $result.cleanup.status = 'FAIL'
                $result.cleanup.residual_path = $auditTemp
                if ($exitCode -eq 0) { $exitCode = 2; $result.overall = 'INCOMPLETE' }
            } else {
                $result.cleanup.status = 'PASS'
                $result.cleanup.residual_path = $null
            }
        }
    }
    [pscustomobject]@{ ExitCode = $exitCode; Result = $result }
}

function Invoke-AuditFixture {
    param([ValidateSet('missing-skill', 'valid', 'duplicate-name', 'complex-yaml')][string]$Kind)
    $root = Join-Path ([IO.Path]::GetTempPath()) ('skill-release-auditor-test-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($root) | Out-Null
    try {
        if ($Kind -eq 'valid') {
            [IO.File]::WriteAllText((Join-Path $root 'SKILL.md'), "---`nname: sample-skill`ndescription: Sample skill for tests.`n---`n`n# Sample`n", (New-Object Text.UTF8Encoding($false)))
        }
        if ($Kind -eq 'duplicate-name') {
            [IO.File]::WriteAllText((Join-Path $root 'SKILL.md'), "---`nname: sample-skill`nname: other-skill`ndescription: Sample skill for tests.`n---`n", (New-Object Text.UTF8Encoding($false)))
        }
        if ($Kind -eq 'complex-yaml') {
            [IO.File]::WriteAllText((Join-Path $root 'SKILL.md'), "---`nname: sample-skill`ndescription: >`n  Multiline descriptions are outside the portable subset.`n---`n", (New-Object Text.UTF8Encoding($false)))
        }
        Invoke-Audit @('--source', $root, '--scope', 'static')
    } finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

function Invoke-SelfTest {
    $case = Invoke-AuditFixture -Kind 'missing-skill'
    Assert-Equal 'missing-skill exit' $case.ExitCode 1
    Assert-Equal 'missing-skill structure' $case.Result.layers.structure.status 'FAIL'

    $case = Invoke-AuditFixture -Kind 'valid'
    Assert-Equal 'native-frontmatter exit' $case.ExitCode 0
    Assert-Equal 'native-frontmatter structure' $case.Result.layers.structure.status 'PASS'

    $case = Invoke-AuditFixture -Kind 'duplicate-name'
    Assert-Equal 'duplicate-name exit' $case.ExitCode 1
    Assert-Equal 'duplicate-name structure' $case.Result.layers.structure.status 'FAIL'

    $case = Invoke-AuditFixture -Kind 'complex-yaml'
    Assert-Equal 'complex-yaml exit' $case.ExitCode 1
    Assert-Equal 'complex-yaml structure' $case.Result.layers.structure.status 'FAIL'

    $root = Join-Path ([IO.Path]::GetTempPath()) ('skill-release-auditor-contract-' + [Guid]::NewGuid().ToString('N'))
    $skillRoot = Join-Path $root 'sample-skill'
    [IO.Directory]::CreateDirectory($skillRoot) | Out-Null
    [IO.File]::WriteAllText((Join-Path $skillRoot 'SKILL.md'), "---`nname: sample-skill`ndescription: Sample skill for tests.`n---`n", (New-Object Text.UTF8Encoding($false)))
    try {
        Assert-Equal 'release pass' (Test-Release $skillRoot).status 'PASS'
        Assert-Equal 'direct install pass' (Test-DirectInstall $skillRoot 'sample-skill' $root).status 'PASS'
        [IO.File]::WriteAllText((Join-Path $skillRoot 'notes.md'), 'Install from https://github.com/<owner>/<repo>.', (New-Object Text.UTF8Encoding($false)))
        Assert-Equal 'release placeholder' (Test-Release $skillRoot).status 'FAIL'
    } finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
    Assert-Equal 'auditor release scan' (Test-Release (Split-Path -Parent $PSScriptRoot)).status 'PASS'
    Write-Output '{"self_test":"PASS"}'
}

if ($Command -eq 'self-test') {
    Invoke-SelfTest
    exit 0
}

if ($Command -ne 'audit') { throw "unknown command: $Command" }
try {
    $audit = Invoke-Audit $Arguments
    $audit.Result | ConvertTo-Json -Depth 8 -Compress
    exit $audit.ExitCode
} catch {
    [ordered]@{
        schema_version = 1
        overall = 'ERROR'
        error = $_.Exception.Message
    } | ConvertTo-Json -Compress
    exit 3
}
