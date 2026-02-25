#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap for managed-python on Windows.

.DESCRIPTION
    Downloads uv, creates a Python venv, then hands off to setup.py.
    All configuration (env.ps1, env.sh, bin\ wrappers, shell profile) is
    handled by setup.py.

.EXAMPLE
    .\install.ps1 -Prefix "$env:USERPROFILE\.claude\redmatter\python" `
                  -MinPython "3.10" -UvEnv "REDMATTER_UV" -PythonEnv "REDMATTER_PYTHON"
#>
param(
    [Parameter(Mandatory=$true)]  [string]$Prefix,
    [Parameter(Mandatory=$true)]  [string]$MinPython,
    [Parameter(Mandatory=$true)]  [string]$UvEnv,
    [Parameter(Mandatory=$true)]  [string]$PythonEnv,
    [switch]$ShellProfile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Prefix    = [Environment]::ExpandEnvironmentVariables($Prefix)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$UvExe     = Join-Path $Prefix "uv.exe"
$VenvPy    = Join-Path $Prefix "venv\Scripts\python.exe"

Write-Host "[dbg] ScriptDir  = $ScriptDir"
Write-Host "[dbg] Prefix     = $Prefix"
Write-Host "[dbg] UvExe      = $UvExe"
Write-Host "[dbg] VenvPy     = $VenvPy"

# Read pinned uv version from distro.toml
$UvVersion = (Get-Content (Join-Path $ScriptDir "distro.toml") |
    Select-String '^uv_version').Line `
    -replace '^[^=]+=\s*"?([^"#]+)"?.*', '$1' |
    ForEach-Object { $_.Trim() }

Write-Host "[dbg] UvVersion  = '$UvVersion'"

Write-Host ""
Write-Host "managed-python bootstrap"
Write-Host "  prefix  $Prefix"
Write-Host ""

# Bootstrap uv
Write-Host "[dbg] Test-Path UvExe = $(Test-Path $UvExe)"
$currentVer = if (Test-Path $UvExe) { try { (& $UvExe --version 2>$null) -split " " | Select-Object -Last 1 } catch { "" } } else { "" }
Write-Host "[dbg] currentVer = '$currentVer'"

if ($currentVer -eq $UvVersion) {
    Write-Host "  ✓ uv $UvVersion"
} else {
    Write-Host "  → Downloading uv $UvVersion"
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "aarch64" } else { "x86_64" }
    $url  = "https://github.com/astral-sh/uv/releases/download/$UvVersion/uv-${arch}-pc-windows-msvc.zip"
    Write-Host "[dbg] url = $url"
    New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
    Write-Host "[dbg] prefix dir created"
    $tmp    = [IO.Path]::GetTempFileName()
    $tmpDir = "$tmp.dir"
    Write-Host "[dbg] tmp    = $tmp"
    Write-Host "[dbg] tmpDir = $tmpDir"
    try {
        $ProgressPreference = "SilentlyContinue"
        Write-Host "[dbg] starting Invoke-WebRequest"
        Invoke-WebRequest $url -OutFile $tmp -UseBasicParsing
        Write-Host "[dbg] download complete, size = $((Get-Item $tmp).Length) bytes"
        Write-Host "[dbg] starting Expand-Archive"
        Expand-Archive $tmp $tmpDir -Force
        Write-Host "[dbg] expand complete"
        $uvSrc = Get-ChildItem $tmpDir -Filter "uv.exe" -Recurse | Select-Object -First 1
        Write-Host "[dbg] uvSrc = $($uvSrc.FullName)"
        Copy-Item $uvSrc.FullName $UvExe -Force
        Write-Host "[dbg] copy complete"
    } finally {
        Remove-Item $tmp, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[dbg] temp files cleaned up"
    }
    if (-not (Test-Path $UvExe)) {
        Write-Error "  ✗ uv download failed — $UvExe not found"
        exit 1
    }
    Write-Host "  ✓ uv $UvVersion installed"
}

# Bootstrap venv
Write-Host "[dbg] Test-Path VenvPy = $(Test-Path $VenvPy)"
if (Test-Path $VenvPy) {
    Write-Host "  ✓ venv already exists"
} else {
    Write-Host "  → Creating Python $MinPython venv"
    & $UvExe venv --python $MinPython (Join-Path $Prefix "venv")
    Write-Host "[dbg] uv venv exited with LASTEXITCODE = $LASTEXITCODE"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "[dbg] Test-Path VenvPy after venv = $(Test-Path $VenvPy)"
    if (-not (Test-Path $VenvPy)) {
        Write-Host "[dbg] venv dir contents:"
        Get-ChildItem (Join-Path $Prefix "venv") -Recurse -ErrorAction SilentlyContinue |
            Select-Object FullName | ForEach-Object { Write-Host "  $($_.FullName)" }
        Write-Error "  ✗ venv created but python.exe not found at $VenvPy"
        exit 1
    }
    Write-Host "  ✓ venv created"
}

Write-Host ""

# Hand off to setup.py
$setupArgs = @("--prefix", $Prefix, "--min-python", $MinPython, "--uv-env", $UvEnv, "--python-env", $PythonEnv)
if ($ShellProfile) { $setupArgs += "--shell-profile" }
& $VenvPy (Join-Path $ScriptDir "setup.py") @setupArgs
exit $LASTEXITCODE
