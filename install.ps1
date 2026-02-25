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

# Read pinned uv version from distro.toml
$UvVersion = (Get-Content (Join-Path $ScriptDir "distro.toml") |
    Select-String '^uv_version').Line `
    -replace '^[^=]+=\s*"?([^"#]+)"?.*', '$1' |
    ForEach-Object { $_.Trim() }

Write-Host ""
Write-Host "managed-python bootstrap"
Write-Host "  prefix  $Prefix"
Write-Host ""

# Bootstrap uv
$currentVer = if (Test-Path $UvExe) { try { (& $UvExe --version 2>$null) -split " " | Select-Object -Last 1 } catch { "" } } else { "" }
if ($currentVer -eq $UvVersion) {
    Write-Host "  ✓ uv $UvVersion"
} else {
    Write-Host "  → Downloading uv $UvVersion"
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "aarch64" } else { "x86_64" }
    $url  = "https://github.com/astral-sh/uv/releases/download/$UvVersion/uv-${arch}-pc-windows-msvc.zip"
    New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
    $tmp    = [IO.Path]::GetTempFileName()
    $tmpDir = "$tmp.dir"
    try {
        Invoke-WebRequest $url -OutFile $tmp -UseBasicParsing
        Expand-Archive $tmp $tmpDir -Force
        Copy-Item (Get-ChildItem $tmpDir -Filter "uv.exe" -Recurse | Select-Object -First 1).FullName $UvExe -Force
    } finally {
        Remove-Item $tmp, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "  ✓ uv $UvVersion installed"
}

# Bootstrap venv
if (Test-Path $VenvPy) {
    Write-Host "  ✓ venv already exists"
} else {
    Write-Host "  → Creating Python $MinPython venv"
    & $UvExe venv --python $MinPython (Join-Path $Prefix "venv")
    Write-Host "  ✓ venv created"
}

Write-Host ""

# Hand off to setup.py
$setupArgs = @("--prefix", $Prefix, "--min-python", $MinPython, "--uv-env", $UvEnv, "--python-env", $PythonEnv)
if ($ShellProfile) { $setupArgs += "--shell-profile" }
& $VenvPy (Join-Path $ScriptDir "setup.py") @setupArgs
exit $LASTEXITCODE
