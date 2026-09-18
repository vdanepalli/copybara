@echo off
setlocal
rem Copybara — Windows sender launcher. No admin required.
rem Installs dependencies into your user profile, then runs the sender.

echo Installing/updating dependencies (first run may take a minute)...
python -m pip install --user --quiet --disable-pip-version-check cryptography pywin32 pillow zeroconf
if errorlevel 1 (
  echo.
  echo Failed to install dependencies. Make sure "python" works in this terminal.
  echo If your Python is the Microsoft Store build, try replacing "python" with "py".
  pause
  exit /b 1
)

echo Starting Copybara sender...
python "%~dp0copybara_win.py"
pause
