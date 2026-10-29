@echo off
chcp 65001 >nul 2>&1
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-dsh-purge.ps1" %*
echo.
pause
