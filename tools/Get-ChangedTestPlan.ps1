[CmdletBinding()]
param(
    [Parameter()]
    [string[]] $Paths = @(),

    [Parameter()]
    [string] $BaseRef
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$safeRepositoryRoot = $repositoryRoot -replace '\\', '/'
$mapPath = Join-Path $repositoryRoot 'tests/validation-map.json'
$map = Get-Content -Raw -LiteralPath $mapPath | ConvertFrom-Json
if ($map.schema -ne 1) {
    throw "Unsupported validation-map schema: $($map.schema)"
}

function Invoke-GitLines {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]] $Arguments)

    $rows = & git -c "safe.directory=$safeRepositoryRoot" @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
    return @($rows)
}

$changed = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
if ($Paths.Count -gt 0) {
    foreach ($candidate in $Paths) {
        if ($candidate) {
            [void] $changed.Add(($candidate -replace '\\', '/').TrimStart('./'))
        }
    }
}
else {
    foreach ($row in Invoke-GitLines @('diff', '--name-only', '--diff-filter=ACMR')) {
        if ($row) { [void] $changed.Add(($row -replace '\\', '/')) }
    }
    foreach ($row in Invoke-GitLines @('diff', '--cached', '--name-only', '--diff-filter=ACMR')) {
        if ($row) { [void] $changed.Add(($row -replace '\\', '/')) }
    }
    foreach ($row in Invoke-GitLines @('ls-files', '--others', '--exclude-standard')) {
        if ($row) { [void] $changed.Add(($row -replace '\\', '/')) }
    }
    if ($BaseRef) {
        foreach ($row in Invoke-GitLines @('diff', '--name-only', '--diff-filter=ACMR', "$BaseRef...HEAD")) {
            if ($row) { [void] $changed.Add(($row -replace '\\', '/')) }
        }
    }
}

$groups = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$tests = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$fullRequired = $false
$allDocumentation = $changed.Count -gt 0

foreach ($path in @($changed | Sort-Object)) {
    $matched = $false
    $documentationMatch = $false
    foreach ($route in $map.routes) {
        $routeMatch = $false
        foreach ($pattern in $route.patterns) {
            if ($path -match $pattern) {
                $routeMatch = $true
                break
            }
        }
        if (-not $routeMatch) { continue }
        $matched = $true
        if ($route.id -eq 'documentation') { $documentationMatch = $true }
        foreach ($group in $route.groups) { [void] $groups.Add([string] $group) }
        foreach ($test in $route.tests) { [void] $tests.Add([string] $test) }
        if ($route.full_required) { $fullRequired = $true }
    }
    if (-not $matched) {
        foreach ($group in $map.default.groups) { [void] $groups.Add([string] $group) }
        foreach ($test in $map.default.tests) { [void] $tests.Add([string] $test) }
        if ($map.default.full_required) { $fullRequired = $true }
    }
    if (-not $documentationMatch) { $allDocumentation = $false }
}

[ordered]@{
    schema = 1
    paths = @($changed | Sort-Object)
    groups = @($groups | Sort-Object)
    tests = @($tests | Sort-Object)
    full_required = [bool] $fullRequired
    documentation_only = [bool] $allDocumentation
} | ConvertTo-Json -Depth 5
