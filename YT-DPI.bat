@echo off
setlocal
cd /d "%~dp0"
title YT-DPI v2.2.2
chcp 65001 >nul

where /q pwsh.exe
if not errorlevel 1 (
    set "PS_EXE=pwsh.exe"
) else (
    set "PS_EXE=powershell.exe"
)

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0YT-DPI.ps1" %*
exit /b %ERRORLEVEL%
