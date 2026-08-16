[CmdletBinding()]
param(
    [ValidateSet('Staged', 'All')]
    [string] $Mode = 'Staged',

    [Parameter(ValueFromRemainingArguments)]
    [string[]] $Paths = @(),

    [switch] $SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$safeRoot = $repositoryRoot.Replace([System.IO.Path]::DirectorySeparatorChar, '/')

$forbiddenPathPatterns = @(
    '(?i)(^|/)(build|dist|coverage|tmp|temp|node_modules|\.tools|\.ai|\.codex|\.chatgpt)/',
    '(?i)(^|/)(prompts?|transcripts?|chat[-_ ]?exports?)(/|$)',
    '(?i)(^|/)(Nexus\.lua|SavedVariables(?:[-_].*)?\.(lua|txt|json)|.*profiler.*|.*runtime.*\.log)$',
    '(?i)\.(zip|7z|rar|bak|tmp|log|prof|pprof)$',
    '(?i)(^|/)(Nexus\.codex-backup-|Nexus-backup-|package-root)'
)
$privateContentPatterns = @(
    '(?i)[A-Z]:[\\/]Users[\\/][^\\/\s]+',
    '(?i)(api[_-]?key|client[_-]?secret|access[_-]?token|password)\s*[:=]\s*["''][^"'']{8,}["'']',
    '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
)
$fixturePrefix = 'tests/fixtures/sanitized/'

function ConvertTo-NormalizedPath([string] $Path) {
    $normalized = $Path.Replace([System.IO.Path]::DirectorySeparatorChar, '/')
    while ($normalized.StartsWith('./', [System.StringComparison]::Ordinal)) { $normalized = $normalized.Substring(2) }
    return $normalized
}

function Test-ArtifactPathSet([string[]] $Candidates, [switch] $ReadContent) {
    $violations = [System.Collections.Generic.List[string]]::new()
    foreach ($raw in @($Candidates | Sort-Object -Unique)) {
        $path = ConvertTo-NormalizedPath $raw
        if (-not $path -or $path.StartsWith($fixturePrefix, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        foreach ($pattern in $forbiddenPathPatterns) {
            if ($path -match $pattern) { $violations.Add("path:$path"); break }
        }
        if ($ReadContent) {
            $full = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $path))
            if (-not $full.StartsWith([System.IO.Path]::GetFullPath($repositoryRoot), [System.StringComparison]::OrdinalIgnoreCase)) {
                $violations.Add("outside-repository:$path")
                continue
            }
            if ((Test-Path -LiteralPath $full -PathType Leaf) -and (Get-Item -LiteralPath $full -Force).Length -le 1048576) {
                $text = Get-Content -Raw -LiteralPath $full -ErrorAction SilentlyContinue
                foreach ($pattern in $privateContentPatterns) {
                    if ($text -match $pattern) { $violations.Add("private-content:$path"); break }
                }
            }
        }
    }
    return @($violations | Sort-Object -Unique)
}

if ($SelfTest) {
    $bad = @(Test-ArtifactPathSet @('dist/Nexus.zip', 'Nexus.lua', '.ai/prompt.md', 'logs/runtime.log', 'node_modules/a.js'))
    $good = @(Test-ArtifactPathSet @('tools/Test-StagedArtifacts.ps1', 'tests/fixtures/sanitized/example.lua'))
    if ($bad.Count -ne 5 -or $good.Count -ne 0) { throw "Artifact self-test failed: bad=$($bad.Count) [$($bad -join ',')] good=$($good.Count)." }
    Write-Output 'staged artifact policy self-test: 5 rejected / 2 allowed -- OK'
    exit 0
}

if ($Paths.Count -eq 0) {
    Push-Location $repositoryRoot
    try {
        if ($Mode -eq 'All') {
            $Paths = @(git -c "safe.directory=$safeRoot" ls-files)
        }
        else {
            $Paths = @(git -c "safe.directory=$safeRoot" diff --cached --name-only --diff-filter=ACMR)
        }
        if ($LASTEXITCODE -ne 0) { throw 'Unable to enumerate repository paths.' }
    }
    finally { Pop-Location }
}

$violations = @(Test-ArtifactPathSet -Candidates $Paths -ReadContent)
if ($violations.Count -gt 0) {
    $violations | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Output "staged artifact policy: checked $($Paths.Count) path(s), violations=0"
