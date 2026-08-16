[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'security-tools.json') | ConvertFrom-Json
$toolsRoot = Join-Path $repositoryRoot '.tools/security'
$binRoot = Join-Path $toolsRoot 'bin'
$downloadRoot = Join-Path $toolsRoot 'downloads'
$isWindowsPlatform = $env:OS -eq 'Windows_NT'
$isLinuxPlatform = -not $isWindowsPlatform -and [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)
$platform = if ($isWindowsPlatform) { 'windows-x64' } elseif ($isLinuxPlatform) { 'linux-x64' } else { throw 'Only Windows x64 and Linux x64 are supported.' }

New-Item -ItemType Directory -Path $binRoot,$downloadRoot -Force | Out-Null

foreach ($name in @('gitleaks', 'actionlint', 'zizmor')) {
    $tool = $manifest.tools.$name
    $asset = $tool.$platform
    if (-not $asset) { throw "No $name asset is pinned for $platform." }
    $archiveName = [System.IO.Path]::GetFileName(([uri] $asset.url).AbsolutePath)
    $archivePath = Join-Path $downloadRoot $archiveName
    if (-not (Test-Path -LiteralPath $archivePath)) {
        Invoke-WebRequest -UseBasicParsing -Uri $asset.url -OutFile $archivePath
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash.ToLowerInvariant()
    if ($actual -ne $asset.sha256) { throw "$name checksum mismatch: expected $($asset.sha256), got $actual." }

    $extractRoot = Join-Path $toolsRoot "extract-$name"
    if (Test-Path -LiteralPath $extractRoot) { Remove-Item -LiteralPath $extractRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
    if ($archivePath.EndsWith('.zip')) {
        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot -Force
    }
    else {
        & tar -xzf $archivePath -C $extractRoot
        if ($LASTEXITCODE -ne 0) { throw "Unable to extract $archiveName." }
    }
    $source = Get-ChildItem -LiteralPath $extractRoot -Recurse -File -Filter $asset.executable | Select-Object -First 1
    if (-not $source) { throw "$name archive did not contain $($asset.executable)." }
    Copy-Item -LiteralPath $source.FullName -Destination (Join-Path $binRoot $asset.executable) -Force
    if (-not $isWindowsPlatform) { & chmod +x (Join-Path $binRoot $asset.executable) }
    Remove-Item -LiteralPath $extractRoot -Recurse -Force
}

$pssa = $manifest.psscriptanalyzer
$packagePath = Join-Path $downloadRoot "PSScriptAnalyzer.$($pssa.version).nupkg"
if (-not (Test-Path -LiteralPath $packagePath)) {
    Invoke-WebRequest -UseBasicParsing -Uri $pssa.url -OutFile $packagePath
}
$actualPssa = (Get-FileHash -Algorithm SHA256 -LiteralPath $packagePath).Hash.ToLowerInvariant()
if ($actualPssa -ne $pssa.sha256) { throw "PSScriptAnalyzer checksum mismatch: expected $($pssa.sha256), got $actualPssa." }
$moduleRoot = Join-Path $toolsRoot "modules/PSScriptAnalyzer/$($pssa.version)"
if (-not (Test-Path -LiteralPath (Join-Path $moduleRoot 'PSScriptAnalyzer.psd1'))) {
    New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
    Expand-Archive -LiteralPath $packagePath -DestinationPath $moduleRoot -Force
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
if ($python) {
    $venv = Join-Path $toolsRoot 'pre-commit'
    if (-not (Test-Path -LiteralPath $venv)) {
        if ($python.Name -eq 'py.exe') { & $python.Source -3 -m venv $venv } else { & $python.Source -m venv $venv }
        if ($LASTEXITCODE -ne 0) { throw 'Unable to create the pre-commit virtual environment.' }
    }
    $venvPython = if ($isWindowsPlatform) { Join-Path $venv 'Scripts/python.exe' } else { Join-Path $venv 'bin/python' }
    & $venvPython -m pip install --disable-pip-version-check --no-input @($manifest.pre_commit.packages)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to install the pinned pre-commit version.' }
}
else {
    Write-Warning 'Python is unavailable; pre-commit was not installed.'
}

Write-Output "Security tools bootstrapped for $platform with verified checksums."
