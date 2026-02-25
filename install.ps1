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
    [switch]$ShellProfile,
    [switch]$Quiet
)

function Write-Msg($msg) { if (-not $Quiet) { Write-Host $msg } }

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

Write-Msg ""
Write-Msg "managed-python bootstrap"
Write-Msg "  prefix  $Prefix"
Write-Msg ""

# Bootstrap uv
$currentVer = if (Test-Path $UvExe) { try { (& $UvExe --version 2>$null) -split " " | Select-Object -Last 1 } catch { "" } } else { "" }
if ($currentVer -eq $UvVersion) {
    Write-Msg "  ✓ uv $UvVersion"
} else {
    Write-Msg "  → Downloading uv $UvVersion"
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "aarch64" } else { "x86_64" }
    $url  = "https://github.com/astral-sh/uv/releases/download/$UvVersion/uv-${arch}-pc-windows-msvc.zip"
    New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
    $tmp    = [IO.Path]::Combine([IO.Path]::GetTempPath(), [IO.Path]::ChangeExtension([IO.Path]::GetRandomFileName(), ".zip"))
    $tmpDir = "$tmp.dir"
    try {
        $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest $url -OutFile $tmp -UseBasicParsing
        Expand-Archive $tmp $tmpDir -Force
        $uvSrc = Get-ChildItem $tmpDir -Filter "uv.exe" -Recurse | Select-Object -First 1
        Copy-Item $uvSrc.FullName $UvExe -Force
    } finally {
        Remove-Item $tmp, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path $UvExe)) {
        Write-Error "  uv download failed: $UvExe not found"
        exit 1
    }
    Write-Msg "  ✓ uv $UvVersion installed"
}

# Bootstrap venv
if (Test-Path $VenvPy) {
    Write-Msg "  ✓ venv already exists"
} else {
    Write-Msg "  → Creating Python $MinPython venv"
    & $UvExe venv --python $MinPython (Join-Path $Prefix "venv")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    if (-not (Test-Path $VenvPy)) {
        Write-Error "  venv created but python.exe not found at $VenvPy"
        exit 1
    }
    Write-Msg "  ✓ venv created"
}

Write-Msg ""

# Hand off to setup.py
$setupArgs = @("--prefix", $Prefix, "--min-python", $MinPython, "--uv-env", $UvEnv, "--python-env", $PythonEnv)
if ($ShellProfile) { $setupArgs += "--shell-profile" }
if ($Quiet) { $setupArgs += "--quiet" }
& $VenvPy (Join-Path $ScriptDir "setup.py") @setupArgs
exit $LASTEXITCODE
