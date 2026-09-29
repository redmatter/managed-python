#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap for managed-python on Windows.

.DESCRIPTION
    Downloads uv, creates a Python venv, then hands off to setup.py.
    All configuration (env.ps1, env.sh, bin\ wrappers, shell profile) is
    handled by setup.py.

.EXAMPLE
    .\install.ps1 -Prefix "$env:USERPROFILE\.local\redmatter\python" -Python "3.10" -EnvPrefix "REDMATTER"

.EXAMPLE
    .\install.ps1 -Prefix "$env:USERPROFILE\.local\redmatter\python" `
                  -Python "3.10" -UvEnv "REDMATTER_UV" -UvxEnv "REDMATTER_UVX" -PythonEnv "REDMATTER_PYTHON"
#>
param(
    [Parameter(Mandatory=$true)]  [string]$Prefix,
    [Parameter(Mandatory=$true)]  [string]$Python,
    [Parameter(Mandatory=$false)] [string]$EnvPrefix,
    [Parameter(Mandatory=$false)] [string]$UvEnv,
    [Parameter(Mandatory=$false)] [string]$UvxEnv,
    [Parameter(Mandatory=$false)] [string]$PythonEnv,
    [Parameter(Mandatory=$false)] [string]$Cooldown,
    [switch]$ShellProfile,
    [switch]$Quiet,
    [switch]$Isolated
)

if ($EnvPrefix) {
    if ($UvEnv -or $UvxEnv -or $PythonEnv) {
        Write-Error "-EnvPrefix cannot be combined with -UvEnv, -UvxEnv, or -PythonEnv"
        exit 1
    }
} else {
    $missing = @()
    if (-not $UvEnv)     { $missing += "-UvEnv" }
    if (-not $UvxEnv)    { $missing += "-UvxEnv" }
    if (-not $PythonEnv) { $missing += "-PythonEnv" }
    if ($missing.Count -gt 0) {
        Write-Error "The following parameters are required: $($missing -join ', ') (or use -EnvPrefix)"
        exit 1
    }
}

function Write-Msg($msg) { if (-not $Quiet) { Write-Host $msg } }

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Prefix     = [Environment]::ExpandEnvironmentVariables($Prefix)
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$DistroToml = Join-Path $ScriptDir "distro.toml"
$UvExe      = Join-Path $Prefix "uv.exe"
$UvxExe     = Join-Path $Prefix "uvx.exe"
$VenvPy     = Join-Path $Prefix "venv\Scripts\python.exe"

# Read pinned versions from distro.toml. Select-Object -First 1 keeps each result a
# single string, so a duplicated line cannot quietly become a two-element array.
$UvVersion = Get-Content $DistroToml | Select-String '^uv_version\s*=\s*"?([^"#]+)"?' |
    Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() }

$PyyamlVersion = Get-Content $DistroToml | Select-String '^pyyaml_version\s*=\s*"([^"]+)"' |
    Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() }

# Both versions go straight to uv, so a hand-typed distro.toml should fail here,
# loudly, rather than somewhere deeper with a bewildering message.
# A missing key yields AutomationNull, and -notmatch treats a collection as a
# filter (returning an empty array, which is falsy), so test for null separately -
# otherwise a missing uv_version slips through with a blank version.
$VersionPattern = '^\d+(\.\d+)+$'
if ($null -eq $UvVersion -or $UvVersion -notmatch $VersionPattern) {
    Write-Error "Missing or invalid uv_version in distro.toml: '$UvVersion' (expected digits and dots, e.g. 0.10.12)"
    exit 1
}
if ($null -eq $PyyamlVersion -or $PyyamlVersion -notmatch $VersionPattern) {
    Write-Error "Missing or invalid pyyaml_version in distro.toml: '$PyyamlVersion' (expected digits and dots, e.g. 6.0.3)"
    exit 1
}

Write-Msg ""
Write-Msg "managed-python bootstrap"
Write-Msg "  prefix  $Prefix"
Write-Msg ""

# Bootstrap uv
$currentVer = if (Test-Path $UvExe) { try { (& $UvExe --version 2>$null) -split " " | Select-Object -Last 1 } catch { "" } } else { "" }
# uvx.exe must exist too - a prefix predating uvx can match the pinned version
# while missing it entirely, and skipping the download would leave it that way.
if (($currentVer -eq $UvVersion) -and (Test-Path $UvxExe)) {
    Write-Msg "  ✓ uv $UvVersion"
} else {
    Write-Msg "  → Downloading uv $UvVersion"
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "aarch64" } else { "x86_64" }
    $url  = "https://github.com/astral-sh/uv/releases/download/$UvVersion/uv-${arch}-pc-windows-msvc.zip"
    New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
    $tmp    = [IO.Path]::Combine([IO.Path]::GetTempPath(), [IO.Path]::ChangeExtension([IO.Path]::GetRandomFileName(), ".zip"))
    $tmpDir = "$tmp.dir"
    $tomlMatch    = Get-Content (Join-Path $ScriptDir "distro.toml") |
                        Select-String "^${arch}-pc-windows-msvc\s*=\s*`"([^`"]+)`""
    $expectedHash = $tomlMatch.Matches[0].Groups[1].Value.ToUpper()
    if (-not $expectedHash) {
        Write-Error "No pinned checksum for ${arch}-pc-windows-msvc in distro.toml"
        exit 1
    }
    try {
        $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest $url -OutFile $tmp -UseBasicParsing
        $actualHash = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToUpper()
        if ($actualHash -ne $expectedHash) {
            Write-Error "uv $UvVersion checksum verification failed — download may be corrupt or tampered`n  expected: $expectedHash`n  actual:   $actualHash"
            exit 1
        }
        Expand-Archive $tmp $tmpDir -Force
        $uvSrc = Get-ChildItem $tmpDir -Filter "uv.exe" -Recurse | Select-Object -First 1
        Copy-Item $uvSrc.FullName $UvExe -Force
        $uvxSrc = Get-ChildItem $tmpDir -Filter "uvx.exe" -Recurse | Select-Object -First 1
        if (-not $uvxSrc) { Write-Error "Failed to locate uvx.exe in archive"; exit 1 }
        Copy-Item $uvxSrc.FullName $UvxExe -Force
    } catch {
        Write-Error "Failed to download uv $UvVersion from $url`: $_"
        exit 1
    } finally {
        Remove-Item $tmp, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path $UvExe)) {
        Write-Error "Failed to download uv $UvVersion — binary not found after extraction"
        exit 1
    }
    if (-not (Test-Path $UvxExe)) {
        Write-Error "Failed to download uv $UvVersion — uvx.exe not found after extraction"
        exit 1
    }
    Write-Msg "  ✓ uv $UvVersion installed"
}

# Bootstrap venv
if (Test-Path $VenvPy) {
    Write-Msg "  ✓ venv already exists"
} else {
    Write-Msg "  → Creating Python $Python venv"
    $pythonPref = if ($Isolated) { "only-managed" } else { "system" }
    $venvArgs = @("venv", "--python", $Python, "--python-preference", $pythonPref)
    if ($Quiet) { $venvArgs += "--quiet" }
    & $UvExe @venvArgs (Join-Path $Prefix "venv")
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create Python $Python venv — see uv error above"
        exit $LASTEXITCODE
    }
    if (-not (Test-Path $VenvPy)) {
        Write-Error "Failed to create Python $Python venv — python.exe not found at $VenvPy"
        exit 1
    }
    Write-Msg "  ✓ venv created"
}

# Probe for pyyaml, then install only if the pinned version is missing.
# The probe exits non-zero (and writes a traceback to stderr) on a fresh venv, which
# is exactly the case we want to install. Under Windows PowerShell 5.1 a redirected
# native stderr line is escalated to a terminating error by $ErrorActionPreference,
# so relax the preference for the probe alone and restore it straight away.
$savedEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $VenvPy -c "import sys, yaml; sys.exit(0 if yaml.__version__ == sys.argv[1] else 1)" $PyyamlVersion 2>$null
$ErrorActionPreference = $savedEap

if ($LASTEXITCODE -eq 0) {
    Write-Msg "  ✓ pyyaml $PyyamlVersion"
} else {
    Write-Msg "  → Installing pyyaml $PyyamlVersion"
    $pipArgs = @("pip", "install", "--python", $VenvPy, "pyyaml==$PyyamlVersion")
    if ($Quiet) { $pipArgs += "--quiet" }
    & $UvExe @pipArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to install pyyaml $PyyamlVersion"
        exit $LASTEXITCODE
    }
    Write-Msg "  ✓ pyyaml $PyyamlVersion installed"
}

Write-Msg ""

# Hand off to setup.py
if ($EnvPrefix) {
    $setupArgs = @("--prefix", $Prefix, "--python", $Python, "--env-prefix", $EnvPrefix)
} else {
    $setupArgs = @("--prefix", $Prefix, "--python", $Python, "--uv-env", $UvEnv, "--uvx-env", $UvxEnv, "--python-env", $PythonEnv)
}
if ($Cooldown) { $setupArgs += @("--cooldown", $Cooldown) }
if ($ShellProfile) { $setupArgs += "--shell-profile" }
if ($Isolated) { $setupArgs += "--isolated" }
if ($Quiet) { $setupArgs += "--quiet" }
& $VenvPy (Join-Path $ScriptDir "setup.py") @setupArgs
exit $LASTEXITCODE
