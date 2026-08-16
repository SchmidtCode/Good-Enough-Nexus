[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repositoryRoot 'tools/SecurityBootstrapPolicy.ps1')
$scratch = Join-Path $repositoryRoot 'build/security-bootstrap-policy-tests'

function New-SecurityFixtureArchive {
    param([string] $Path, [string[]] $EntryPath)
    Add-Type -AssemblyName System.IO.Compression
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create)
    $archive = [System.IO.Compression.ZipArchive]::new(
        $stream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        foreach ($entryPath in $EntryPath) {
            $entry = $archive.CreateEntry($entryPath)
            $writer = [System.IO.StreamWriter]::new($entry.Open())
            try { $writer.Write('fixture') } finally { $writer.Dispose() }
        }
    }
    finally {
        $archive.Dispose()
        $stream.Dispose()
    }
}

function New-SecurityFixtureTar {
    param([string] $Path, [string[]] $EntryPath)
    $file = [System.IO.File]::Create($Path)
    $gzip = [System.IO.Compression.GZipStream]::new(
        $file, [System.IO.Compression.CompressionLevel]::Optimal, $false)
    $archive = [System.Formats.Tar.TarWriter]::new($gzip, $false)
    try {
        foreach ($entryPath in $EntryPath) {
            $entry = [System.Formats.Tar.PaxTarEntry]::new(
                [System.Formats.Tar.TarEntryType]::RegularFile, $entryPath)
            $entry.DataStream = [System.IO.MemoryStream]::new(
                [System.Text.Encoding]::UTF8.GetBytes('fixture'))
            try { $archive.WriteEntry($entry) } finally { $entry.DataStream.Dispose() }
        }
    }
    finally {
        $archive.Dispose()
        $gzip.Dispose()
        $file.Dispose()
    }
}

function Assert-RejectedArchive {
    param([string] $Label, [string[]] $EntryPath, [string[]] $AllowedTopLevel, [string] $ExpectedExecutable = 'tool.exe')
    $archivePath = Join-Path $scratch "$Label.zip"
    New-SecurityFixtureArchive -Path $archivePath -EntryPath $EntryPath
    try {
        $records = @(Get-SecurityArchiveEntryRecord -ArchivePath $archivePath -ArchiveType 'zip')
        Resolve-SecurityArchiveExecutable -EntryRecord $records `
            -ExpectedExecutablePath $ExpectedExecutable -AllowedTopLevel $AllowedTopLevel
    }
    catch { return }
    throw "$Label archive was accepted."
}

function Copy-SecurityManifest {
    param([Parameter(Mandatory)][object] $Manifest)
    return ($Manifest | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
}

function Assert-RejectedManifestMutation {
    param([string] $Label, [object] $Manifest, [scriptblock] $Mutation)
    $hostile = Copy-SecurityManifest -Manifest $Manifest
    & $Mutation $hostile
    try {
        Resolve-SecurityBootstrapManifest -Manifest $hostile -RepositoryRoot $repositoryRoot `
            -ToolsRoot (Join-Path $repositoryRoot '.tools/security') -Platform 'windows-x64'
    }
    catch { return }
    throw "$Label manifest metadata was accepted."
}

if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
try {
    $manifest = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot 'tools/security-tools.json') | ConvertFrom-Json
    $validatedManifest = Resolve-SecurityBootstrapManifest -Manifest $manifest -RepositoryRoot $repositoryRoot `
        -ToolsRoot (Join-Path $repositoryRoot '.tools/security') -Platform 'windows-x64'
    if ($validatedManifest.RequirementsPath -cne (Join-Path $repositoryRoot 'tools/pre-commit-requirements.txt')) {
        throw 'Valid manifest resolved an unexpected requirements path.'
    }
    Assert-RejectedManifestMutation 'traversal executable' $manifest { param($value) $value.tools.gitleaks.'windows-x64'.executable = '../outside.exe' }
    Assert-RejectedManifestMutation 'unsafe version' $manifest { param($value) $value.tools.gitleaks.version = '../8.30.1' }
    Assert-RejectedManifestMutation 'traversal expected executable' $manifest { param($value) $value.tools.gitleaks.'windows-x64'.expected_executable_path = '../gitleaks.exe' }
    Assert-RejectedManifestMutation 'unsafe allowed root' $manifest { param($value) $value.tools.gitleaks.'windows-x64'.allowed_top_level = @('..') }
    Assert-RejectedManifestMutation 'requirements escape' $manifest { param($value) $value.pre_commit.requirements_file = '../outside.txt' }

    $validArchive = Join-Path $scratch 'valid.zip'
    New-SecurityFixtureArchive -Path $validArchive -EntryPath @('LICENSE', 'tool.exe')
    $validRecords = @(Get-SecurityArchiveEntryRecord -ArchivePath $validArchive -ArchiveType 'zip')
    $resolved = Resolve-SecurityArchiveExecutable -EntryRecord $validRecords `
        -ExpectedExecutablePath 'tool.exe' -AllowedTopLevel @('LICENSE', 'tool.exe')
    if ($resolved -cne 'tool.exe') { throw "Valid archive resolved unexpected path '$resolved'." }
    $validTar = Join-Path $scratch 'valid.tar.gz'
    New-SecurityFixtureTar -Path $validTar -EntryPath @('LICENSE', 'tool')
    $validTarRecords = @(Get-SecurityArchiveEntryRecord -ArchivePath $validTar -ArchiveType 'tar.gz')
    $resolvedTar = Resolve-SecurityArchiveExecutable -EntryRecord $validTarRecords `
        -ExpectedExecutablePath 'tool' -AllowedTopLevel @('LICENSE', 'tool')
    if ($resolvedTar -cne 'tool') { throw "Valid tar archive resolved unexpected path '$resolvedTar'." }

    Assert-RejectedArchive -Label 'traversal' -EntryPath @('../escape.exe') -AllowedTopLevel @('escape.exe')
    Assert-RejectedArchive -Label 'absolute' -EntryPath @('/absolute.exe') -AllowedTopLevel @('absolute.exe')
    Assert-RejectedArchive -Label 'drive' -EntryPath @('C:/drive.exe') -AllowedTopLevel @('C:')
    Assert-RejectedArchive -Label 'alternate-separator' -EntryPath @('..\escape.exe') -AllowedTopLevel @('escape.exe')
    Assert-RejectedArchive -Label 'wrong-root' -EntryPath @('wrong/tool.exe') -AllowedTopLevel @('expected')
    Assert-RejectedArchive -Label 'case-conflict' -EntryPath @('tool.exe', 'TOOL.EXE') -AllowedTopLevel @('tool.exe', 'TOOL.EXE')
    Assert-RejectedArchive -Label 'recursive-decoy' -EntryPath @('decoy/tool.exe', 'tool.exe') -AllowedTopLevel @('decoy', 'tool.exe')
    Assert-RejectedArchive -Label 'missing-executable' -EntryPath @('LICENSE') -AllowedTopLevel @('LICENSE')
    $linkRejected = $false
    try {
        Resolve-SecurityArchiveExecutable -EntryRecord @(
            [pscustomobject]@{ Path = 'tool.exe'; Kind = 'link' }
        ) -ExpectedExecutablePath 'tool.exe' -AllowedTopLevel @('tool.exe')
    }
    catch { $linkRejected = $true }
    if (-not $linkRejected) { throw 'Archive executable link was accepted.' }

    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $validArchive).Hash.ToLowerInvariant()
    Confirm-SecurityFileHash -Path $validArchive -ExpectedHash $actualHash -Label 'valid fixture'
    $badArchiveHashRejected = $false
    try { Confirm-SecurityFileHash -Path $validArchive -ExpectedHash ('0' * 64) -Label 'bad archive fixture' }
    catch { $badArchiveHashRejected = $true }
    if (-not $badArchiveHashRejected) { throw 'Bad archive checksum was accepted.' }

    $requirements = @('demo==1.0 --hash=sha256:' + ('a' * 64))
    Confirm-PythonHashLock -Line $requirements -ExpectedRequirement @('demo==1.0')
    $missingHashRejected = $false
    try { Confirm-PythonHashLock -Line @('demo==1.0') -ExpectedRequirement @('demo==1.0') }
    catch { $missingHashRejected = $true }
    if (-not $missingHashRejected) { throw 'Missing Python distribution hash was accepted.' }
    $badPythonHashRejected = $false
    try { Confirm-SecurityFileHash -Path $validArchive -ExpectedHash ('b' * 64) -Label 'Python distribution fixture' }
    catch { $badPythonHashRejected = $true }
    if (-not $badPythonHashRejected) { throw 'Incorrect Python distribution hash was accepted.' }

    $temporary = Join-Path $scratch 'temporary-extract'
    $simulatedFailure = $false
    try {
        Invoke-SecurityTemporaryDirectory -Path $temporary -AllowedParent $scratch -Action {
            param($path)
            Set-Content -LiteralPath (Join-Path $path 'partial.txt') -Value 'partial'
            throw 'simulated extraction failure'
        }
    }
    catch { $simulatedFailure = $true }
    if (-not $simulatedFailure -or (Test-Path -LiteralPath $temporary)) {
        throw 'Failed extraction retained its temporary directory.'
    }
    Invoke-SecurityTemporaryDirectory -Path $temporary -AllowedParent $scratch -Action {
        param($path)
        Set-Content -LiteralPath (Join-Path $path 'complete.txt') -Value 'complete'
    }
    if (Test-Path -LiteralPath $temporary) { throw 'Successful extraction retained its temporary directory.' }
}
finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}

Write-Output 'security bootstrap fixtures: manifest containment, ZIP/tar layouts, 8 hostile archives plus link rejection, checksum/hash lock, failure cleanup -- OK'
