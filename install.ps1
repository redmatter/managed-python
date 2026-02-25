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

Write-Host "DBG: ScriptDir  = $ScriptDir"
Write-Host "DBG: Prefix     = $Prefix"
Write-Host "DBG: UvExe      = $UvExe"
Write-Host "DBG: VenvPy     = $VenvPy"

# Read pinned uv version from distro.toml
$UvVersion = (Get-Content (Join-Path $ScriptDir "distro.toml") |
    Select-String '^uv_version').Line `
    -replace '^[^=]+=\s*"?([^"#]+)"?.*', '$1' |
    ForEach-Object { $_.Trim() }

Write-Host "DBG: UvVersion  = '$UvVersion'"

Write-Host ""
Write-Host "managed-python bootstrap"
Write-Host "  prefix  $Prefix"
Write-Host ""

# Bootstrap uv
Write-Host "DBG: Test-Path UvExe = $(Test-Path $UvExe)"
$currentVer = if (Test-Path $UvExe) { try { (& $UvExe --version 2>$null) -split " " | Select-Object -Last 1 } catch { "" } } else { "" }
Write-Host "DBG: currentVer = '$currentVer'"

Write-Host "DBG: comparison: ($currentVer) -eq ($UvVersion) = $($currentVer -eq $UvVersion)"
Write-Host "DBG: UvVersion bytes: $([System.Text.Encoding]::UTF8.GetBytes($UvVersion) -join ',')"
if ($currentVer -eq $UvVersion) {
    Write-Host "DBG: entering IF branch - uv already current"
    Write-Host "  uv $UvVersion (already current)"
} else {
    Write-Host "DBG: entering ELSE branch - download needed"
    Write-Host "  Downloading uv $UvVersion"
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "aarch64" } else { "x86_64" }
    $url  = "https://github.com/astral-sh/uv/releases/download/$UvVersion/uv-${arch}-pc-windows-msvc.zip"
    Write-Host "DBG: url = $url"
    New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
    Write-Host "DBG: prefix dir created"
    $tmp    = [IO.Path]::Combine([IO.Path]::GetTempPath(), [IO.Path]::ChangeExtension([IO.Path]::GetRandomFileName(), ".zip"))
    $tmpDir = "$tmp.dir"
    Write-Host "DBG: tmp    = $tmp"
    Write-Host "DBG: tmpDir = $tmpDir"
    try {
        $ProgressPreference = "SilentlyContinue"
        Write-Host "DBG: starting Invoke-WebRequest"
        Invoke-WebRequest $url -OutFile $tmp -UseBasicParsing
        Write-Host "DBG: download complete, size = $((Get-Item $tmp).Length) bytes"
        Write-Host "DBG: starting Expand-Archive"
        Expand-Archive $tmp $tmpDir -Force
        Write-Host "DBG: expand complete"
        $uvSrc = Get-ChildItem $tmpDir -Filter "uv.exe" -Recurse | Select-Object -First 1
        Write-Host "DBG: uvSrc = $($uvSrc.FullName)"
        Copy-Item $uvSrc.FullName $UvExe -Force
        Write-Host "DBG: copy complete"
    } finally {
        Remove-Item $tmp, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "DBG: temp files cleaned up"
    }
    if (-not (Test-Path $UvExe)) {
        Write-Error "  uv download failed: $UvExe not found"
        exit 1
    }
    Write-Host "  uv $UvVersion installed"
}

# Bootstrap venv
Write-Host "DBG: Test-Path VenvPy = $(Test-Path $VenvPy)"
if (Test-Path $VenvPy) {
    Write-Host "  venv already exists"
} else {
    Write-Host "  Creating Python $MinPython venv"
    & $UvExe venv --python $MinPython (Join-Path $Prefix "venv")
    Write-Host "DBG: uv venv exited with LASTEXITCODE = $LASTEXITCODE"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "DBG: Test-Path VenvPy after venv = $(Test-Path $VenvPy)"
    if (-not (Test-Path $VenvPy)) {
        Write-Host "DBG: venv dir contents:"
        Get-ChildItem (Join-Path $Prefix "venv") -Recurse -ErrorAction SilentlyContinue |
            Select-Object FullName | ForEach-Object { Write-Host "  $($_.FullName)" }
        Write-Error "  venv created but python.exe not found at $VenvPy"
        exit 1
    }
    Write-Host "  venv created"
}

Write-Host ""

# Hand off to setup.py
$setupArgs = @("--prefix", $Prefix, "--min-python", $MinPython, "--uv-env", $UvEnv, "--python-env", $PythonEnv)
if ($ShellProfile) { $setupArgs += "--shell-profile" }
& $VenvPy (Join-Path $ScriptDir "setup.py") @setupArgs
exit $LASTEXITCODE
