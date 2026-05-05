@echo off
REM Shortcut: same host only / no child powershell.exe or pwsh processes.
REM Suppress pause inside release-gate.cmd so we show one "press key" here (window stays open).
set "YT_DPI_GATE_PAUSE_SUPPRESSED=1"
call "%~dp0release-gate.cmd" quick %*
set "EC=%ERRORLEVEL%"
if /i not "%YT_DPI_GATE_NO_PAUSE%"=="1" (
    echo.
    echo Press any key to close this window...
    pause >nul
)
exit /b %EC%
