@echo off
cd /d "%~dp0"
title Probador del flujo n8n - SIG Minimarket
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0probar_n8n.ps1" %*
echo.
pause
