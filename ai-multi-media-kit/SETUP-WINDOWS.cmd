@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SETUP-WINDOWS.ps1" %*
set STATUS=%ERRORLEVEL%
echo.
if not "%STATUS%"=="0" echo [ERROR] Bootstrap failed with exit code %STATUS%. Read the error and retry.
pause
exit /b %STATUS%
