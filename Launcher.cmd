@echo off
REM ===========================================================================
REM  Windows Recovery Toolkit launcher
REM  Prefers PowerShell 7 (pwsh). Requests elevation via Launcher.ps1 itself.
REM ===========================================================================
setlocal
set "SCRIPT_DIR=%~dp0"

where pwsh >nul 2>&1
if %ERRORLEVEL%==0 (
    pwsh -NoProfile -STA -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Launcher.ps1" %*
    goto :eof
)

echo PowerShell 7 (pwsh) was not found.
echo Install it from the official source:  https://aka.ms/powershell
echo.
echo Attempting to run under Windows PowerShell 5.1 (limited compatibility)...
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Launcher.ps1" %*
endlocal
