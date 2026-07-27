@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_oxmysql.ps1"
if errorlevel 1 (
  echo.
  echo Installatie is mislukt. Lees README.md en controleer je internetverbinding.
  pause
  exit /b 1
)
echo.
echo oxmysql is geinstalleerd.
pause
