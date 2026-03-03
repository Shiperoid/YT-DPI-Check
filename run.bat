@echo off
if not exist "YT-DPI-Check.ps1" (
    echo [ERROR] File YT-DPI-Check.ps1 not found!
    pause
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "YT-DPI-Check.ps1"

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] The script encountered an error.
    pause
)