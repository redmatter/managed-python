#Requires -Version 5.1
<#
.SYNOPSIS
    managed-python bootstrap for Windows (PowerShell)

.DESCRIPTION
    Installs uv (pinned version from distro.toml) and creates a Python venv
    at the given prefix. Writes env.ps1 that exports env vars and optionally
    adds prefix\bin to PATH.

.PARAMETER Prefix
    Install location for uv binary, venv, and env.ps1

.PARAMETER MinPython
    Minimum Python version for the venv (e.g. "3.10")

.PARAMETER UvEnv
    Name of env var to export for the uv binary path

.PARAMETER PythonEnv
    Name of env var to export for the python binary path

.PARAMETER ShellProfile
    If set, append '. <prefix>\env.ps1' to the user's PowerShell profile

.EXAMPLE
    .\install.ps1 `
        -Prefix "$env:USERPROFILE\.claude\redmatter\python" `
        -MinPython "3.10" `
        -UvEnv "REDMATTER_UV" `
        -PythonEnv "REDMATTER_PYTHON"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Prefix,

    [Parameter(Mandatory = $true)]
    [string]$MinPython,

    [Parameter(Mandatory = $true)]
    [string]$UvEnv,

    [Parameter(Mandatory = $true)]
    [string]$PythonEnv,

    [switch]$ShellProfile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$DistroToml = Join-Path $ScriptDir "distro.toml"

# Expand environment variables in Prefix (e.g. $env:USERPROFILE)
$Prefix = [System.Environment]::ExpandEnvironmentVariables($Prefix)

$UvExe        = Join-Path $Prefix "uv.exe"
$VenvDir      = Join-Path $Prefix "venv"
$VenvPython   = Join-Path $VenvDir "Scripts\python.exe"
$BinDir       = Join-Path $Prefix "bin"
$EnvPs1Dest   = Join-Path $Prefix "env.ps1"
$EnvShDest    = Join-Path $Prefix "env.sh"
$DistroTomlDest = Join-Path $Prefix "distro.toml"

# ---------------------------------------------------------------------------
# Parse distro.toml (no external deps)
# ---------------------------------------------------------------------------
function Get-TomlValue {
    param([string]$File, [string]$Key)
    $line = Select-String -Path $File -Pattern "^${Key}\s*=" | Select-Object -First 1
    if (-not $line) { throw "Key '$Key' not found in $File" }
    $line.Line -replace "^[^=]+=\s*`"?([^`"#]+)`"?.*", '$1' | ForEach-Object { $_.Trim() }
}

$DistroVersion = Get-TomlValue -File $DistroToml -Key "version"
$UvVersion     = Get-TomlValue -File $DistroToml -Key "uv_version"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Step  { param([string]$Msg) Write-Host "`n==> $Msg" -ForegroundColor Blue }
function Write-Ok    { param([string]$Msg) Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Info  { param([string]$Msg) Write-Host "  [i] $Msg" -ForegroundColor Cyan }
function Write-Warn  { param([string]$Msg) Write-Host "  [!] $Msg" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# Step 1: Download uv.exe
# ---------------------------------------------------------------------------
function Install-Uv {
    Write-Step "Installing uv $UvVersion"

    # Check if existing uv matches pinned version
    if (Test-Path $UvExe) {
        try {
            $currentVer = (& $UvExe --version 2>$null).Split(" ")[1]
            if ($currentVer -eq $UvVersion) {
                Write-Ok "uv $UvVersion already installed — skipping download"
                return
            }
            Write-Info "Updating uv $currentVer → $UvVersion"
        } catch { }
    }

    New-Item -ItemType Directory -Force -Path $Prefix | Out-Null

    # Detect architecture
    $arch = if ([System.Environment]::Is64BitOperatingSystem) {
        if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "aarch64" } else { "x86_64" }
    } else {
        throw "32-bit Windows is not supported"
    }

    $target = "${arch}-pc-windows-msvc"
    $url    = "https://github.com/astral-sh/uv/releases/download/${UvVersion}/uv-${target}.zip"

    Write-Info "Downloading from: $url"

    $tmpDir  = [System.IO.Path]::GetTempPath() + [System.IO.Path]::GetRandomFileName()
    $tmpZip  = "${tmpDir}.zip"

    try {
        Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing
        Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force

        # Find uv.exe in extracted archive
        $uvBinSrc = Get-ChildItem -Path $tmpDir -Filter "uv.exe" -Recurse | Select-Object -First 1
        if (-not $uvBinSrc) {
            throw "Could not find uv.exe in downloaded archive"
        }

        Copy-Item -Path $uvBinSrc.FullName -Destination $UvExe -Force
        Write-Ok "uv $UvVersion installed to $UvExe"

        # Also copy uvx.exe if present
        $uvxBinSrc = Get-ChildItem -Path $tmpDir -Filter "uvx.exe" -Recurse | Select-Object -First 1
        if ($uvxBinSrc) {
            Copy-Item -Path $uvxBinSrc.FullName -Destination (Join-Path $Prefix "uvx.exe") -Force
        }
    } finally {
        if (Test-Path $tmpZip)  { Remove-Item $tmpZip  -Force }
        if (Test-Path $tmpDir)  { Remove-Item $tmpDir  -Recurse -Force }
    }
}

# ---------------------------------------------------------------------------
# Step 2: Create Python venv
# ---------------------------------------------------------------------------
function New-PythonVenv {
    Write-Step "Creating Python venv (>= $MinPython)"

    if (Test-Path $VenvPython) {
        try {
            $currentVer = (& $VenvPython --version 2>&1).Split(" ")[1]
            Write-Ok "Python venv already exists ($currentVer) — skipping creation"
            return
        } catch { }
    }

    & $UvExe venv --python $MinPython $VenvDir
    if ($LASTEXITCODE -ne 0) {
        throw "uv venv creation failed with exit code $LASTEXITCODE"
    }

    $actualVer = (& $VenvPython --version 2>&1).Split(" ")[1]
    Write-Ok "Venv created at $VenvDir"
    Write-Ok "Python version: $actualVer"
}

# ---------------------------------------------------------------------------
# Step 3: Create bin\ wrapper scripts
# ---------------------------------------------------------------------------
function New-BinWrappers {
    Write-Step "Creating bin\ wrapper scripts"

    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

    # python.cmd wrapper
    $pythonCmd = Join-Path $BinDir "python.cmd"
    Set-Content -Path $pythonCmd -Value "@`"$VenvPython`" %*"
    Write-Ok "bin\python.cmd -> $VenvPython"

    # uv.cmd wrapper
    $uvCmd = Join-Path $BinDir "uv.cmd"
    Set-Content -Path $uvCmd -Value "@`"$UvExe`" %*"
    Write-Ok "bin\uv.cmd -> $UvExe"
}

# ---------------------------------------------------------------------------
# Step 4: Determine PATH logic and write env.ps1
# ---------------------------------------------------------------------------
function Write-EnvPs1 {
    Write-Step "Writing env.ps1"

    $pythonOnPath = $null -ne (Get-Command python -ErrorAction SilentlyContinue) -or
                   $null -ne (Get-Command python3 -ErrorAction SilentlyContinue)
    $uvOnPath     = $null -ne (Get-Command uv -ErrorAction SilentlyContinue)

    $addToPath = -not ($pythonOnPath -and $uvOnPath)

    $lines = @()
    $lines += "# managed-python v${DistroVersion} -- generated by install.ps1"
    $lines += "# Do not edit manually; re-run install.ps1 to regenerate"
    $lines += ""
    $lines += "# Env vars (always set -- these are the reliable contract)"
    $lines += "`$env:${UvEnv} = `"${UvExe}`""
    $lines += "`$env:${PythonEnv} = `"${VenvPython}`""
    $lines += ""

    if ($addToPath) {
        if ($pythonOnPath -and -not $uvOnPath) {
            $sysPython = (Get-Command python -ErrorAction SilentlyContinue)?.Source
            $lines += "# Note: system python found at $sysPython -- will be shadowed by managed version"
        } elseif ($uvOnPath -and -not $pythonOnPath) {
            $sysUv = (Get-Command uv -ErrorAction SilentlyContinue)?.Source
            $lines += "# Note: system uv found at $sysUv -- will be shadowed by managed version"
        }
        $lines += "# PATH (added because python/uv were not already on system PATH)"
        $lines += "`$env:PATH = `"${BinDir};`" + `$env:PATH"
    } else {
        $lines += "# python and uv already on PATH. To use managed versions:"
        $lines += "# `$env:PATH = `"${BinDir};`" + `$env:PATH"
    }

    $lines | Set-Content -Path $EnvPs1Dest -Encoding UTF8
    Write-Ok "env.ps1 written to $EnvPs1Dest"

    if ($addToPath) {
        if (-not $pythonOnPath -and -not $uvOnPath) {
            Write-Info "Added python and uv to PATH via $BinDir"
        } elseif ($pythonOnPath) {
            Write-Warn "system python found -- managed version will shadow it when env.ps1 is sourced"
        } else {
            Write-Warn "system uv found -- managed version will shadow it when env.ps1 is sourced"
        }
    } else {
        Write-Info "python and uv already on PATH -- PATH not modified"
        Write-Info "To use managed versions: `$env:PATH = `"${BinDir};`" + `$env:PATH"
    }
}

# ---------------------------------------------------------------------------
# Step 5: Write env.sh (bash equivalent, for WSL compatibility)
# ---------------------------------------------------------------------------
function Write-EnvSh {
    Write-Step "Writing env.sh (WSL/bash compatibility)"

    # Use forward slashes for WSL paths (best-effort)
    $uvBinFwd     = $UvExe -replace "\\", "/"
    $venvPythonFwd = $VenvPython -replace "\\", "/"
    $binDirFwd    = $BinDir -replace "\\", "/"

    $content = @"
# managed-python v${DistroVersion} -- generated by install.ps1 (Windows)
# Do not edit manually; re-run install.ps1 to regenerate
# Note: Windows paths -- source in WSL after mounting the Windows filesystem

export ${UvEnv}="${uvBinFwd}"
export ${PythonEnv}="${venvPythonFwd}"
"@

    Set-Content -Path $EnvShDest -Value $content -Encoding UTF8
    Write-Ok "env.sh written to $EnvShDest"
}

# ---------------------------------------------------------------------------
# Step 6: Copy distro.toml to prefix
# ---------------------------------------------------------------------------
function Copy-DistroToml {
    Copy-Item -Path $DistroToml -Destination $DistroTomlDest -Force
    Write-Ok "distro.toml copied to $DistroTomlDest"
}

# ---------------------------------------------------------------------------
# Step 7: Optionally update PowerShell profile
# ---------------------------------------------------------------------------
function Update-ShellProfile {
    if (-not $ShellProfile) { return }

    Write-Step "Updating PowerShell profile"

    $profilePath = $PROFILE.CurrentUserCurrentHost
    $sourceLine  = ". `"$EnvPs1Dest`""

    if (-not (Test-Path (Split-Path $profilePath))) {
        New-Item -ItemType Directory -Force -Path (Split-Path $profilePath) | Out-Null
    }
    if (-not (Test-Path $profilePath)) {
        New-Item -ItemType File -Force -Path $profilePath | Out-Null
    }

    $content = Get-Content -Path $profilePath -Raw -ErrorAction SilentlyContinue
    if ($content -and $content.Contains($sourceLine)) {
        Write-Ok "PowerShell profile already configured: $profilePath"
        return
    }

    Add-Content -Path $profilePath -Value "`n# managed-python`n$sourceLine"
    Write-Ok "Appended to $profilePath"
    Write-Info "Restart PowerShell or run: . `"$EnvPs1Dest`""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "managed-python v$DistroVersion" -ForegroundColor Cyan
Write-Host "  prefix  $Prefix"
Write-Host "  uv      $UvVersion   python >= $MinPython"
Write-Host ""

Install-Uv
New-PythonVenv
New-BinWrappers
Write-EnvPs1
Write-EnvSh
Copy-DistroToml
Update-ShellProfile

Write-Host ""
Write-Host "┌─────────────────────────────────────────┐" -ForegroundColor Green
Write-Host "│  Install complete!                       │" -ForegroundColor Green
Write-Host "└─────────────────────────────────────────┘" -ForegroundColor Green
Write-Host ""
Write-Host "  . `"$EnvPs1Dest`""
Write-Host ""
Write-Host "  Then:  & `"`$env:$PythonEnv`" C:\path\to\script.py"
Write-Host "         & `"`$env:$UvEnv`" run --project C:\path\to\app script.py"
Write-Host ""
