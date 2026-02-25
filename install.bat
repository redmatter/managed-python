@echo off
if /i "%~1"=="--help" goto :help
if /i "%~1"=="-h"     goto :help
powershell -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
exit /b %ERRORLEVEL%

:help
powershell -ExecutionPolicy Bypass -Command "Get-Help '%~dp0install.ps1' -Detailed"
exit /b 0
