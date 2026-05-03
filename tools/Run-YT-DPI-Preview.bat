@echo off
setlocal
cd /d "%~dp0.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-YT-DPI-Preview.ps1" -Configuration Release %*
