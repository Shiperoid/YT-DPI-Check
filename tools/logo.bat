@echo off
setlocal
REM Лого из YT-DPI.ps1 (блок YT-DPI-LOGO-BEGIN … END), по центру; отдельное окно — без промпта CMD.
cd /d "%~dp0"
chcp 65001 >nul

where /q pwsh.exe
if not errorlevel 1 (
    set "PS_EXE=pwsh.exe"
) else (
    set "PS_EXE=powershell.exe"
)

set "LOGO_PS=%~dp0logo.ps1"
if not exist "%LOGO_PS%" (
    echo [logo] logo.ps1 not found next to this file.
    exit /b 1
)

REM Явный заголовок окна + стартовый каталог: иначе start "" ломает передачу аргументов в части конфигураций CMD.
start "YT-DPI Logo" /D "%~dp0" %PS_EXE% -NoProfile -ExecutionPolicy Bypass -File "%LOGO_PS%"
endlocal
exit /b 0
