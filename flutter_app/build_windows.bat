@echo off
rem Double-click to build Monkey App for Windows.
rem Extra options go straight to the script, e.g.:  build_windows.bat -Update -Installer
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_windows.ps1" %*
echo.
pause
