@echo off
setlocal EnableDelayedExpansion
REM =============================================================================
REM YT-DPI release gate (launcher)
REM
REM Scope: compatibility smoke only — AST parse, embedded C# Add-Type, minimal PS
REM patterns (see smoke-yt-dpi-engines.ps1), then the same checks under extra
REM processes (Windows PowerShell 5.1 x64/WOW64, discovered pwsh).
REM NOT a full functional/E2E test (no real scan, proxy UI, traceroute UI, etc.).
REM
REM Usage:
REM   release-gate.cmd              full matrix (child processes)
REM   release-gate.cmd quick        current process only (-SkipChildProcesses)
REM   release-gate.cmd quick -Quiet   forward extra switches to release-gate.ps1
REM
REM After finish, waits for a key so the window stays open when launched from Explorer.
REM Skip: set YT_DPI_GATE_NO_PAUSE=1  (CI/scripts). Nested quick launcher sets
REM YT_DPI_GATE_PAUSE_SUPPRESSED so only the outer .cmd shows one prompt.
REM =============================================================================

cd /d "%~dp0"
chcp 65001 >nul 2>&1

for %%I in ("%~dp0..") do set "REPO=%%~fI"

where pwsh.exe >nul 2>&1 && (set "PSBIN=pwsh.exe") || (set "PSBIN=powershell.exe")

set "PS_EXTRA="
set "REST="
if /i "%~1"=="quick" (
    set "PS_EXTRA=-SkipChildProcesses"
    shift
)
:collect
if "%~1"=="" goto run
set "REST=!REST! %~1"
shift
goto collect

:run
echo.
echo ========================================
echo   YT-DPI release gate ^(CMD launcher^)
echo   RepoRoot: !REPO!
echo   Shell:    !PSBIN!
echo ========================================
echo.

"%PSBIN%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0release-gate.ps1" -RepoRoot "!REPO!" !PS_EXTRA! !REST!

set "EC=%ERRORLEVEL%"
echo.
echo ========================================
if %EC% neq 0 (
    echo   [FAIL] release-gate exit code: %EC%
    echo   Logs: see PowerShell output above.
    echo   Temp: %%TEMP%%\yt-dpi-release-gate-* ^(kept on failure^)
    echo   Hint: set YT_DPI_GATE_KEEP_TEMP=1 to preserve temp dir on success.
) else (
    echo   [PASS] release-gate exit code: 0
)
echo ========================================
if /i not "%YT_DPI_GATE_NO_PAUSE%"=="1" (
    if /i not "%YT_DPI_GATE_PAUSE_SUPPRESSED%"=="1" (
        echo.
        echo Press any key to close this window...
        pause >nul
    )
)
endlocal & exit /b %EC%
