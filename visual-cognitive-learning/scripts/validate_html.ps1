[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$ViolationOrder = @(
    'missing-doctype',
    'missing-html',
    'missing-head',
    'missing-body',
    'missing-lang',
    'missing-title',
    'missing-viewport',
    'external-resource',
    'css-external-url',
    'network-api',
    'dynamic-code',
    'module-import',
    'duplicate-id',
    'unlabeled-control',
    'missing-reduced-motion',
    'missing-inline-style',
    'missing-static-content'
)

function Test-Pattern {
    param([string]$Pattern, [string]$Text)
    return [regex]::IsMatch(
        $Text,
        $Pattern,
        [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
        [Text.RegularExpressions.RegexOptions]::Singleline
    )
}

function Get-Attributes {
    param([string]$Tag)
    $result = @{}
    $pattern = "\b([\w:-]+)\s*=\s*([`"'])(.*?)\2"
    foreach ($match in [regex]::Matches($Tag, $pattern, 'IgnoreCase,Singleline')) {
        $result[$match.Groups[1].Value.ToLowerInvariant()] = $match.Groups[3].Value
    }
    return $result
}

function Get-Violations {
    param([string]$Content)
    $found = @{}

    if (-not (Test-Pattern '<!doctype\s+html\s*>' $Content)) { $found['missing-doctype'] = $true }
    if (-not (Test-Pattern '<html\b[^>]*>.*?</html\s*>' $Content)) { $found['missing-html'] = $true }
    if (-not (Test-Pattern '<head\b[^>]*>.*?</head\s*>' $Content)) { $found['missing-head'] = $true }
    if (-not (Test-Pattern '<body\b[^>]*>.*?</body\s*>' $Content)) { $found['missing-body'] = $true }

    $htmlMatch = [regex]::Match($Content, '<html\b[^>]*>', 'IgnoreCase,Singleline')
    if (-not $htmlMatch.Success) {
        $found['missing-lang'] = $true
    } else {
        $htmlAttributes = Get-Attributes $htmlMatch.Value
        if (-not $htmlAttributes.ContainsKey('lang') -or [string]::IsNullOrWhiteSpace($htmlAttributes['lang'])) {
            $found['missing-lang'] = $true
        }
    }

    $titleMatch = [regex]::Match($Content, '<title\b[^>]*>(.*?)</title\s*>', 'IgnoreCase,Singleline')
    if (-not $titleMatch.Success -or [string]::IsNullOrWhiteSpace($titleMatch.Groups[1].Value)) {
        $found['missing-title'] = $true
    }
    if (-not (Test-Pattern '<meta\b[^>]*\bname\s*=\s*(["''])viewport\1' $Content)) {
        $found['missing-viewport'] = $true
    }

    foreach ($tagMatch in [regex]::Matches($Content, '<(?:script|img|iframe|source|video|audio|link)\b[^>]*>', 'IgnoreCase,Singleline')) {
        $attrs = Get-Attributes $tagMatch.Value
        foreach ($key in @('src', 'href')) {
            if (-not $attrs.ContainsKey($key)) { continue }
            $value = $attrs[$key].Trim()
            if ($value -and -not $value.StartsWith('data:', [StringComparison]::OrdinalIgnoreCase) -and -not $value.StartsWith('#')) {
                $found['external-resource'] = $true
            }
        }
    }

    $cssParts = New-Object System.Collections.Generic.List[string]
    foreach ($styleMatch in [regex]::Matches($Content, '<style\b[^>]*>(.*?)</style\s*>', 'IgnoreCase,Singleline')) {
        $cssParts.Add($styleMatch.Groups[1].Value)
    }
    foreach ($attrMatch in [regex]::Matches($Content, "\bstyle\s*=\s*([`"'])(.*?)\1", 'IgnoreCase,Singleline')) {
        $cssParts.Add($attrMatch.Groups[2].Value)
    }
    $cssText = [string]::Join("`n", $cssParts)
    foreach ($urlMatch in [regex]::Matches($cssText, "url\(\s*([`"']?)(.*?)\1\s*\)", 'IgnoreCase,Singleline')) {
        $value = $urlMatch.Groups[2].Value.Trim()
        if ($value -and -not $value.StartsWith('data:', [StringComparison]::OrdinalIgnoreCase) -and -not $value.StartsWith('#')) {
            $found['css-external-url'] = $true
        }
    }

    $scriptParts = New-Object System.Collections.Generic.List[string]
    foreach ($scriptMatch in [regex]::Matches($Content, '<script\b[^>]*>(.*?)</script\s*>', 'IgnoreCase,Singleline')) {
        $scriptParts.Add($scriptMatch.Groups[1].Value)
    }
    $scriptText = [string]::Join("`n", $scriptParts)
    if (Test-Pattern '\b(?:fetch|XMLHttpRequest|WebSocket|EventSource)\s*\(|\bnavigator\s*\.\s*sendBeacon\s*\(' $scriptText) {
        $found['network-api'] = $true
    }
    if (Test-Pattern '\beval\s*\(|\bnew\s+Function\s*\(' $scriptText) {
        $found['dynamic-code'] = $true
    }
    if ((Test-Pattern '<script\b[^>]*\btype\s*=\s*(["''])module\1' $Content) -or
        (Test-Pattern '\bimport\s*(?:\(|[^;\n]*\bfrom\s*["''])' $scriptText)) {
        $found['module-import'] = $true
    }

    $idCounts = @{}
    foreach ($idMatch in [regex]::Matches($Content, "\bid\s*=\s*([`"'])(.*?)\1", 'IgnoreCase,Singleline')) {
        $id = $idMatch.Groups[2].Value.Trim()
        if (-not $id) { continue }
        if ($idCounts.ContainsKey($id)) { $idCounts[$id]++ } else { $idCounts[$id] = 1 }
        if ($idCounts[$id] -gt 1) { $found['duplicate-id'] = $true }
    }

    $labelTargets = @{}
    foreach ($labelMatch in [regex]::Matches($Content, "<label\b[^>]*\bfor\s*=\s*([`"'])(.*?)\1", 'IgnoreCase,Singleline')) {
        $target = $labelMatch.Groups[2].Value.Trim()
        if ($target) { $labelTargets[$target] = $true }
    }
    foreach ($controlMatch in [regex]::Matches($Content, '<(?:input|select|textarea)\b[^>]*>', 'IgnoreCase,Singleline')) {
        $attrs = Get-Attributes $controlMatch.Value
        if ($attrs.ContainsKey('type') -and $attrs['type'].Equals('hidden', [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($attrs.ContainsKey('aria-label') -and -not [string]::IsNullOrWhiteSpace($attrs['aria-label'])) { continue }
        if ($attrs.ContainsKey('aria-labelledby') -and -not [string]::IsNullOrWhiteSpace($attrs['aria-labelledby'])) { continue }
        if ($attrs.ContainsKey('id') -and $labelTargets.ContainsKey($attrs['id'].Trim())) { continue }
        $found['unlabeled-control'] = $true
        break
    }

    if ($Content.IndexOf('prefers-reduced-motion', [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        $found['missing-reduced-motion'] = $true
    }
    if (-not (Test-Pattern '<style\b[^>]*>.*?</style\s*>' $Content)) {
        $found['missing-inline-style'] = $true
    }

    $bodyMatch = [regex]::Match($Content, '<body\b[^>]*>(.*?)</body\s*>', 'IgnoreCase,Singleline')
    $visible = if ($bodyMatch.Success) { $bodyMatch.Groups[1].Value } else { '' }
    $visible = [regex]::Replace($visible, '<(?:script|style)\b[^>]*>.*?</(?:script|style)\s*>', ' ', 'IgnoreCase,Singleline')
    $visible = [regex]::Replace($visible, '<[^>]+>', ' ', 'Singleline')
    $visible = [Net.WebUtility]::HtmlDecode($visible)
    if (([regex]::Replace($visible, '\s+', '')).Length -lt 40) {
        $found['missing-static-content'] = $true
    }

    $result = New-Object System.Collections.Generic.List[string]
    foreach ($code in $ViolationOrder) {
        if ($found.ContainsKey($code)) { $result.Add($code) }
    }
    return @($result)
}

function Get-ValidatedFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Path is not a regular file: $Path"
    }
    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
    $content = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8
    return [pscustomobject]@{
        Path = $resolved
        Violations = @(Get-Violations $content)
    }
}

function Write-Json {
    param([hashtable]$Payload)
    Write-Output ($Payload | ConvertTo-Json -Compress -Depth 4)
}

function Invoke-SelfTest {
    $valid = '<!doctype html><html lang="zh-CN"><head><meta name="viewport" content="width=device-width"><title>流程学习</title><style>body{color:#111}@media (prefers-reduced-motion: reduce){*{animation:none}}</style></head><body><main><h1>理解交付流程</h1><p>这个页面保留足够的静态说明，让脚本失效时仍能理解阶段、检查、异常处理和最终交付之间的关系。</p><label for="step">选择阶段</label><select id="step"><option>分析</option></select></main><script>document.documentElement.dataset.ready="true";</script></body></html>'
    $invalid = '<script type="module" src="https://example.com/a.js">fetch("https://example.com");eval("1");import("./x.js")</script><img src="https://example.com/x.png"><input id="same"><div id="same" style="background:url(https://example.com/x.png)"></div>'
    $root = Join-Path ([IO.Path]::GetTempPath()) ('visual-cognitive-learning-' + [guid]::NewGuid().ToString('N'))
    $caseRoot = Join-Path $root '中文 path'
    try {
        [void](New-Item -ItemType Directory -Path $caseRoot -Force)
        $utf8 = New-Object Text.UTF8Encoding($false)
        $goodPath = Join-Path $caseRoot 'good.html'
        $badPath = Join-Path $caseRoot 'bad.html'
        [IO.File]::WriteAllText($goodPath, $valid, $utf8)
        [IO.File]::WriteAllText($badPath, $invalid, $utf8)
        $goodResult = Get-ValidatedFile $goodPath
        $badResult = Get-ValidatedFile $badPath
        if ($goodResult.Violations.Count -ne 0) { throw "valid fixture failed: $($goodResult.Violations -join ',')" }
        if (($badResult.Violations -join ',') -ne ($ViolationOrder -join ',')) {
            throw "invalid fixture mismatch: $($badResult.Violations -join ',')"
        }
        try {
            [void](Get-ValidatedFile (Join-Path $caseRoot 'missing.html'))
            throw 'missing path did not fail'
        } catch {
            if ($_.Exception.Message -eq 'missing path did not fail') { throw }
        }
    } finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}

try {
    $argsList = @($RemainingArgs | Where-Object { $null -ne $_ -and $_ -ne '' })
    if ($Command -eq 'self-test') {
        if ($argsList.Count -ne 0) { throw 'self-test does not accept arguments' }
        Invoke-SelfTest
        Write-Json @{ ok = $true; command = 'self-test'; tests = 3 }
        exit 0
    }
    if ($Command -eq 'check') {
        if ($argsList.Count -ne 2 -or $argsList[0] -ne '--path') {
            throw 'check requires --path <html-file>'
        }
        $result = Get-ValidatedFile $argsList[1]
        $violations = @($result.Violations)
        Write-Json @{ ok = ($violations.Count -eq 0); command = 'check'; path = $result.Path; violations = $violations }
        if ($violations.Count -gt 0) { exit 1 }
        exit 0
    }
    throw 'Expected: check --path <html-file> | self-test'
} catch {
    Write-Json @{ ok = $false; command = [string]$Command; error = $_.Exception.Message }
    exit 2
}
