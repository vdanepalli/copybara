@echo off
rem ===========================================================================
rem Copybara - run in THIS window so you can watch the live log. Ctrl+C to stop.
rem Good for the first test / debugging. For normal use, prefer start.bat.
rem ===========================================================================
setlocal
cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
  echo [Copybara] Not set up yet. Run setup.bat first.
  pause
  exit /b 1
)

echo [Copybara] Running in this window. Press Ctrl+C to stop.
echo.
".venv\Scripts\python.exe" -X utf8 -u "%~dp0copybara_win.py"
echo.
echo [Copybara] Sender exited.
pause
