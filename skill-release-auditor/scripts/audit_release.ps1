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

function Test-YqParser {
    param([string]$Path, [string]$TempDirectory)
    $utf8 = New-Object Text.UTF8Encoding($false)
    $valid = Join-Path $TempDirectory 'parser-valid.yaml'
    $invalid = Join-Path $TempDirectory 'parser-invalid.yaml'
    [IO.File]::WriteAllText($valid, "name: sample-skill`ndescription: sample`n", $utf8)
    [IO.File]::WriteAllText($invalid, "name: [broken`n", $utf8)
    & $Path eval -e '.name == "sample-skill" and (.description | type == "!!str")' $valid *> $null
    $validCode = $LASTEXITCODE
    & $Path eval '.' $invalid *> $null
    $invalidCode = $LASTEXITCODE
    return ($validCode -eq 0 -and $invalidCode -ne 0)
}

function Install-TemporaryYq {
    param([string]$TempDirectory)

    $version = 'v4.53.3'
    $architecture = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE')
    switch -Regex ($architecture) {
        '^(AMD64|x86_64)$' {
            $asset = 'yq_windows_amd64.exe'
            $expectedHash = 'e279bc506a452eeafcdf364f91a025455e402a8001169083caf01f4b64a544e2'
        }
        '^(ARM64|aarch64)$' {
            $asset = 'yq_windows_arm64.exe'
            $expectedHash = 'c80ac96ff2a8d77d452d91304e11feef8fb23239900b3d1d88f47c2ec93be970'
        }
        default { throw "temporary yq is unsupported on architecture: $architecture" }
    }
    $path = Join-Path $TempDirectory 'yq.exe'
    $url = "https://github.com/mikefarah/yq/releases/download/$version/$asset"
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $curl) {
        & $curl.Source -fL --connect-timeout 15 --max-time 90 -o $path $url
        if ($LASTEXITCODE -ne 0) { throw 'temporary yq download failed' }
    } else {
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $path -TimeoutSec 90
    }
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        Remove-Item -LiteralPath $path -Force
        throw "temporary yq SHA-256 mismatch for $asset"
    }
    [pscustomobject]@{
        Path = $path
        Record = [ordered]@{
            name = 'yq'
            version = $version
            source = $url
            sha256 = $expectedHash
            hash_verified = $true
            temporary = $true
        }
    }
}

function Test-Structure {
    param(
        [string]$SkillFile,
        [bool]$AllowTempYamlParser,
        [string]$AuditTempDirectory
    )

    if (-not (Test-Path -LiteralPath $SkillFile -PathType Leaf)) {
        return [pscustomobject]@{
            Layer = New-Layer 'FAIL' 'SRA-STRUCT-001' 'SKILL.md is missing'
            AuthorizationRequired = $false
        }
    }

    $lines = [IO.File]::ReadAllLines($SkillFile)
    if ($lines.Count -lt 4 -or $lines[0] -ne '---') {
        return [pscustomobject]@{
            Layer = New-Layer 'FAIL' 'SRA-STRUCT-002' 'frontmatter must start on the first line'
            AuthorizationRequired = $false
        }
    }
    $closing = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq '---') { $closing = $i; break }
    }
    if ($closing -lt 2) {
        return [pscustomobject]@{
            Layer = New-Layer 'FAIL' 'SRA-STRUCT-002' 'frontmatter closing delimiter is missing'
            AuthorizationRequired = $false
        }
    }

    $frontmatter = @($lines[1..($closing - 1)])
    $nameCount = @($frontmatter | Where-Object { $_ -match '^name\s*:' }).Count
    $descriptionCount = @($frontmatter | Where-Object { $_ -match '^description\s*:' }).Count
    if ($nameCount -ne 1 -or $descriptionCount -ne 1) {
        return [pscustomobject]@{
            Layer = New-Layer 'FAIL' 'SRA-STRUCT-003' 'frontmatter must contain exactly one name and one description'
            AuthorizationRequired = $false
        }
    }

    $temp = Join-Path $AuditTempDirectory 'yaml'
    [IO.Directory]::CreateDirectory($temp) | Out-Null
    try {
        $toolRecord = $null
        $yq = Get-Command yq -ErrorAction SilentlyContinue | Select-Object -First 1
        $yqPath = if ($null -eq $yq) { $null } else { $yq.Source }
        if ($null -ne $yqPath -and -not (Test-YqParser $yqPath $temp)) { $yqPath = $null }
        if ($null -eq $yqPath -and -not $AllowTempYamlParser) {
            return [pscustomobject]@{
                Layer = New-Layer 'BLOCKED' 'SRA-STRUCT-004' 'strict YAML parser is unavailable or failed self-test'
                AuthorizationRequired = $true
                Tool = $null
                Name = $null
            }
        }
        if ($null -eq $yqPath) {
            try {
                $download = Install-TemporaryYq $temp
                $yqPath = $download.Path
                $toolRecord = $download.Record
                if (-not (Test-YqParser $yqPath $temp)) { throw 'temporary yq failed self-test' }
            } catch {
                return [pscustomobject]@{
                    Layer = New-Layer 'BLOCKED' 'SRA-STRUCT-004' $_.Exception.Message
                    AuthorizationRequired = $false
                    Tool = $null
                    Name = $null
                }
            }
        }
        $utf8 = New-Object Text.UTF8Encoding($false)
        $yaml = Join-Path $temp 'frontmatter.yaml'
        [IO.File]::WriteAllLines($yaml, $frontmatter, $utf8)
        & $yqPath eval -e 'type == "!!map" and (.name | type == "!!str") and (.description | type == "!!str")' $yaml *> $null
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{
                Layer = New-Layer 'FAIL' 'SRA-STRUCT-005' 'frontmatter is not valid strict YAML metadata'
                AuthorizationRequired = $false
                Tool = $toolRecord
                Name = $null
            }
        }
        $parsedName = (& $yqPath eval -r '.name' $yaml 2>$null).Trim()
        if ($parsedName.Length -gt 64 -or $parsedName -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
            return [pscustomobject]@{
                Layer = New-Layer 'FAIL' 'SRA-STRUCT-006' 'skill name does not match the portable naming contract'
                AuthorizationRequired = $false
                Tool = $toolRecord
                Name = $parsedName
            }
        }
        return [pscustomobject]@{
            Layer = New-Layer 'PASS' 'SRA-STRUCT-005' 'frontmatter passed strict YAML validation'
            AuthorizationRequired = $false
            Tool = $toolRecord
            Name = $parsedName
        }
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
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
    $allowTempYamlParser = $false
    $scope = 'full'
    $installer = 'direct'
    for ($i = 0; $i -lt $InputArguments.Count; $i++) {
        switch ($InputArguments[$i]) {
            '--source' {
                $i++
                if ($i -ge $InputArguments.Count) { throw '--source requires a value' }
                $source = $InputArguments[$i]
            }
            '--allow-temp-yaml-parser' { $allowTempYamlParser = $true }
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
        $structureCheck = Test-Structure $skillFile $allowTempYamlParser $auditTemp
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
            authorization_required = $structureCheck.AuthorizationRequired
            layers = $layers
            tools = @($structureCheck.Tool | Where-Object { $null -ne $_ })
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
    param([ValidateSet('missing-skill', 'valid', 'duplicate-name')][string]$Kind)
    $root = Join-Path ([IO.Path]::GetTempPath()) ('skill-release-auditor-test-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($root) | Out-Null
    try {
        if ($Kind -eq 'valid') {
            [IO.File]::WriteAllText((Join-Path $root 'SKILL.md'), "---`nname: sample-skill`ndescription: Sample skill for tests.`n---`n`n# Sample`n", (New-Object Text.UTF8Encoding($false)))
        }
        if ($Kind -eq 'duplicate-name') {
            [IO.File]::WriteAllText((Join-Path $root 'SKILL.md'), "---`nname: sample-skill`nname: other-skill`ndescription: Sample skill for tests.`n---`n", (New-Object Text.UTF8Encoding($false)))
        }
        Invoke-Audit @('--source', $root)
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
    Assert-Equal 'missing-yq exit' $case.ExitCode 2
    Assert-Equal 'missing-yq structure' $case.Result.layers.structure.status 'BLOCKED'
    Assert-Equal 'missing-yq authorization' $case.Result.authorization_required $true

    $case = Invoke-AuditFixture -Kind 'duplicate-name'
    Assert-Equal 'duplicate-name exit' $case.ExitCode 1
    Assert-Equal 'duplicate-name structure' $case.Result.layers.structure.status 'FAIL'

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

function Invoke-IntegrationTest {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('skill-release-auditor-integration-' + [Guid]::NewGuid().ToString('N'))
    $skillRoot = Join-Path $root 'sample-skill'
    [IO.Directory]::CreateDirectory($skillRoot) | Out-Null
    [IO.File]::WriteAllText((Join-Path $skillRoot 'SKILL.md'), "---`nname: sample-skill`ndescription: Sample skill for tests.`n---`n`n# Sample`n", (New-Object Text.UTF8Encoding($false)))
    try {
        $case = Invoke-Audit @('--source', $skillRoot, '--allow-temp-yaml-parser', '--scope', 'static', '--installer', 'direct')
        Assert-Equal 'integration exit' $case.ExitCode 0
        Assert-Equal 'integration structure' $case.Result.layers.structure.status 'PASS'
        Assert-Equal 'integration release' $case.Result.layers.release.status 'PASS'
        Assert-Equal 'integration install' $case.Result.layers.install.status 'PASS'
        Assert-Equal 'integration cleanup' $case.Result.cleanup.status 'PASS'
        Write-Output '{"integration_test":"PASS"}'
    } finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}

if ($Command -eq 'self-test') {
    Invoke-SelfTest
    exit 0
}

if ($Command -eq 'integration-test') {
    Invoke-IntegrationTest
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
