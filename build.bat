@echo off
setlocal
REM Сборка YT-DPI.Core через dotnet (оба TFM: net472, net8.0). Запускать из корня репозитория.
cd /d "%~dp0"

where /q dotnet.exe
if errorlevel 1 (
    echo [build] dotnet.exe не найден в PATH. Установите .NET SDK.
    exit /b 1
)

echo [build] dotnet build YT-DPI.sln -c Release
dotnet build "YT-DPI.sln" -c Release -v minimal %*
set ERR=%ERRORLEVEL%
if %ERR% neq 0 (
    echo [build] Ошибка сборки, код %ERR%
    exit /b %ERR%
)

echo [build] Готово. Выход: src\YT-DPI.Core\bin\Release\net472\YT-DPI.Core.dll
echo [build]        и src\YT-DPI.Core\bin\Release\net8.0\YT-DPI.Core.dll
endlocal
exit /b 0
