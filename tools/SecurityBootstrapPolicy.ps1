Set-StrictMode -Version Latest

function Get-SecurityArchiveEntryRecord {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $ArchivePath,
        [Parameter(Mandatory)][ValidateSet('zip', 'tar.gz')][string] $ArchiveType
    )

    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        throw "Security archive does not exist: $ArchivePath"
    }
    if ($ArchiveType -eq 'zip') {
        Add-Type -AssemblyName System.IO.Compression
        $stream = [System.IO.File]::OpenRead($ArchivePath)
        $archive = [System.IO.Compression.ZipArchive]::new(
            $stream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            foreach ($entry in $archive.Entries) {
                $unixType = (($entry.ExternalAttributes -shr 16) -band 0xF000)
                $kind = if ($unixType -eq 0xA000) {
                    'link'
                }
                elseif (-not $entry.Name) {
                    'directory'
                }
                else {
                    'file'
                }
                Write-Output ([pscustomobject]@{ Path = $entry.FullName; Kind = $kind })
            }
        }
        finally {
            $archive.Dispose()
            $stream.Dispose()
        }
        return
    }

    $file = [System.IO.File]::OpenRead($ArchivePath)
    $gzip = [System.IO.Compression.GZipStream]::new(
        $file, [System.IO.Compression.CompressionMode]::Decompress, $false)
    $reader = [System.Formats.Tar.TarReader]::new($gzip, $false)
    try {
        while ($entry = $reader.GetNextEntry()) {
            $kind = if ($entry.EntryType -in @(
                [System.Formats.Tar.TarEntryType]::RegularFile,
                [System.Formats.Tar.TarEntryType]::V7RegularFile
            )) {
                'file'
            }
            elseif ($entry.EntryType -eq [System.Formats.Tar.TarEntryType]::Directory) {
                'directory'
            }
            else {
                'link'
            }
            Write-Output ([pscustomobject]@{ Path = $entry.Name; Kind = $kind })
        }
    }
    finally {
        $reader.Dispose()
        $gzip.Dispose()
        $file.Dispose()
    }
}

function Resolve-SecurityArchiveExecutable {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $EntryRecord,
        [Parameter(Mandatory)][string] $ExpectedExecutablePath,
        [Parameter(Mandatory)][string[]] $AllowedTopLevel
    )

    $normalizedExpected = $ExpectedExecutablePath -replace '\\', '/'
    $seen = @{}
    $executableMatches = [System.Collections.Generic.List[string]]::new()
    $expectedKind = $null
    foreach ($record in $EntryRecord) {
        $raw = [string] $record.Path
        if (-not $raw -or $raw -match '[\x00-\x1f\x7f]') {
            throw 'Security archive contains an empty or control-character path.'
        }
        $normalized = $raw -replace '\\', '/'
        if ($normalized.StartsWith('/', [System.StringComparison]::Ordinal) `
            -or $normalized -match '^[A-Za-z]:' -or $normalized.StartsWith('//')) {
            throw "Security archive contains an absolute or drive-qualified path: $raw"
        }
        $normalized = $normalized.TrimEnd('/')
        $parts = @($normalized -split '/')
        if (-not $normalized -or $parts -contains '' -or $parts -contains '.' -or $parts -contains '..') {
            throw "Security archive contains an unsafe path: $raw"
        }
        if ($AllowedTopLevel -cnotcontains $parts[0]) {
            throw "Security archive contains unexpected top-level entry '$($parts[0])'."
        }
        $folded = $normalized.ToUpperInvariant()
        if ($seen.ContainsKey($folded)) {
            throw "Security archive contains duplicate or case-conflicting path: $normalized"
        }
        $seen[$folded] = $true
        if ([string] $record.Kind -notin @('file', 'directory')) {
            throw "Security archive contains unsupported link entry: $normalized"
        }
        if ([System.IO.Path]::GetFileName($normalized).Equals(
            [System.IO.Path]::GetFileName($normalizedExpected),
            [System.StringComparison]::OrdinalIgnoreCase)) {
            $executableMatches.Add($normalized)
        }
        if ($normalized -ceq $normalizedExpected) { $expectedKind = [string] $record.Kind }
    }
    if ($expectedKind -ne 'file') {
        throw "Security archive is missing expected executable '$normalizedExpected'."
    }
    if ($executableMatches.Count -ne 1 -or $executableMatches[0] -cne $normalizedExpected) {
        throw "Security archive contains an unexpected executable layout for '$normalizedExpected'."
    }
    return $normalizedExpected
}

function Confirm-SecurityFileHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string] $ExpectedHash,
        [Parameter(Mandatory)][string] $Label
    )

    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    if ($actual -cne $ExpectedHash) {
        throw "$Label checksum mismatch: expected $ExpectedHash, got $actual."
    }
}

function Confirm-PythonHashLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Line,
        [Parameter(Mandatory)][string[]] $ExpectedRequirement
    )

    $locked = @{}
    foreach ($raw in $Line) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        $match = [regex]::Match($line, '^(?<requirement>[A-Za-z0-9_.-]+==[^\s]+)(?<hashes>(?:\s+--hash=sha256:[0-9a-f]{64})+)\s*$')
        if (-not $match.Success) {
            throw "Python distribution lock contains an unhashed or malformed requirement: $line"
        }
        $requirement = $match.Groups['requirement'].Value
        $key = $requirement.ToLowerInvariant()
        if ($locked.ContainsKey($key)) { throw "Python distribution lock contains duplicate requirement '$requirement'." }
        $locked[$key] = $true
    }
    $expected = @{}
    foreach ($requirement in $ExpectedRequirement) {
        $key = $requirement.ToLowerInvariant()
        if ($expected.ContainsKey($key)) { throw "Expected Python requirements contain duplicate '$requirement'." }
        $expected[$key] = $true
    }
    $missing = @($expected.Keys | Where-Object { -not $locked.ContainsKey($_) })
    $extra = @($locked.Keys | Where-Object { -not $expected.ContainsKey($_) })
    if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
        throw "Python distribution lock mismatch: missing=$($missing -join ',') extra=$($extra -join ',')."
    }
}

function Invoke-SecurityTemporaryDirectory {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $AllowedParent,
        [Parameter(Mandatory)][scriptblock] $Action
    )

    $parent = [System.IO.Path]::GetFullPath($AllowedParent)
    $target = [System.IO.Path]::GetFullPath($Path)
    $relative = [System.IO.Path]::GetRelativePath($parent, $target)
    if ([System.IO.Path]::IsPathRooted($relative) -or $relative -eq '..' `
        -or $relative.StartsWith("..$([System.IO.Path]::DirectorySeparatorChar)") -or $relative -eq '.') {
        throw "Unsafe security temporary directory: $target"
    }
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    try { Write-Output (& $Action $target) }
    finally {
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    }
}
