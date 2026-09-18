@echo off
rem ===========================================================================
rem Copybara - one-time setup. Creates an ISOLATED virtual environment (.venv)
rem inside THIS folder and installs all dependencies there. Nothing is installed
rem system-wide or into your shared user packages, so other scripts are unaffected.
rem No admin rights required.
rem ===========================================================================
setlocal
cd /d "%~dp0"

echo [Copybara] Locating Python...
where python >nul 2>&1
if %errorlevel%==0 ( set "PY=python" ) else ( set "PY=py -3" )

echo [Copybara] Creating isolated environment in "%~dp0.venv" ...
%PY% -m venv .venv
if not exist ".venv\Scripts\python.exe" (
  echo [Copybara] ERROR: could not create the virtual environment.
  echo            Make sure Python 3 is installed ^(try: python --version^).
  pause
  exit /b 1
)

echo [Copybara] Installing dependencies into .venv ...
".venv\Scripts\python.exe" -m pip install --upgrade pip --quiet --disable-pip-version-check
".venv\Scripts\python.exe" -m pip install --quiet --disable-pip-version-check cryptography pywin32 pillow zeroconf
if errorlevel 1 (
  echo [Copybara] ERROR: dependency install failed ^(check your internet connection^).
  pause
  exit /b 1
)

rem pywin32 places its DLLs; harmless if it does nothing.
".venv\Scripts\python.exe" ".venv\Scripts\pywin32_postinstall.py" -install >nul 2>&1

echo.
echo [Copybara] Setup complete.
echo            Start it with  start.bat   (runs in the background)
echo            Watch it live  run-console.bat
echo.
pause
