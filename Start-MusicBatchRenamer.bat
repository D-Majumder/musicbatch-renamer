@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0MusicBatchRenamer.ps1"
if errorlevel 1 (
  echo.
  echo MusicBatch Renamer exited with an error.
  pause
)
endlocal
