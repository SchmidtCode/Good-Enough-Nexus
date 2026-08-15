[CmdletBinding()]
param(
    [Parameter()]
    [string] $Archive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot

function Require-File {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $RelativePath)

    $path = Join-Path $repositoryRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required release-policy file is missing: $RelativePath"
    }
    return $path
}

function Require-Text {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Pattern
    )

    $content = Get-Content -Raw -LiteralPath $Path
    if (-not ($content -match [regex]::Escape($Pattern))) {
        throw "Required release-policy text is missing from $(Split-Path -Leaf $Path): $Pattern"
    }
}

$requiredFiles = @(
    'LICENSE.md',
    'AI_POLICY.md',
    'UPSTREAM.md',
    'RELEASE_SECURITY.md',
    'SECURITY.md',
    'README.md',
    'Nexus.toc',
    '.github/CODEOWNERS',
    '.github/workflows/release-policy.yml'
)

foreach ($relative in $requiredFiles) {
    Require-File $relative | Out-Null
}

$licensePath = Join-Path $repositoryRoot 'LICENSE.md'
$aiPolicyPath = Join-Path $repositoryRoot 'AI_POLICY.md'
$upstreamPath = Join-Path $repositoryRoot 'UPSTREAM.md'
$releaseSecurityPath = Join-Path $repositoryRoot 'RELEASE_SECURITY.md'
$securityPath = Join-Path $repositoryRoot 'SECURITY.md'

Require-Text $licensePath 'Copyright'
Require-Text $licensePath 'reserved for material'
Require-Text $aiPolicyPath 'AI-assisted tooling'
Require-Text $upstreamPath 'Better Nexus begins from a locally installed Nexus 1.19.3 snapshot'
Require-Text $releaseSecurityPath 'Release Security'
Require-Text $securityPath 'Security Policy'

if ($PSBoundParameters.ContainsKey('Archive') -and $Archive) {
    $archivePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Archive)
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
        throw "Release archive does not exist: $archivePath"
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $entries = @()
        $seenCaseInsensitive = @{}

        foreach ($entry in $zip.Entries) {
            $entryName = $entry.FullName -replace '\\', '/'
            if ($entryName -match '\\') {
                throw "Archive entry uses unsupported path separator: $entryName"
            }
            if ($entryName -match '(?i)(^|/)\.\.(?:/|$)') {
                throw "Archive entry contains path traversal: $entryName"
            }

            $lower = $entryName.ToLowerInvariant()
            if ($seenCaseInsensitive.ContainsKey($lower)) {
                throw "Archive contains case-insensitive duplicate entry: $entryName"
            }
            $seenCaseInsensitive[$lower] = $true
            $entries += $entryName
        }

        $topLevels = $entries |
            ForEach-Object { $_ -split '/' | Select-Object -First 1 } |
            Where-Object { $_ -and $_ -ne '__MACOSX' } |
            Select-Object -Unique

        if ($topLevels.Count -ne 1 -or $topLevels[0] -ne 'Nexus') {
            throw "Archive must contain exactly one top-level folder named Nexus. Found: $($topLevels -join ', ')"
        }

        $requiredEntries = @(
            'Nexus/Nexus.toc',
            'Nexus/LICENSE.md',
            'Nexus/AI_POLICY.md',
            'Nexus/UPSTREAM.md'
        )

        foreach ($requiredEntry in $requiredEntries) {
            if (-not ($entries -contains $requiredEntry)) {
                throw "Release archive is missing required entry: $requiredEntry"
            }
        }
    }
    finally {
        $zip.Dispose()
    }
}

Write-Output 'Release license and policy checks passed.'