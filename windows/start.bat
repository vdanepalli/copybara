@echo off
rem ===========================================================================
rem Copybara - start the sender in the background. Writes copybara.pid and logs
rem to copybara.log / copybara.err.log. Refuses to start a second copy.
rem ===========================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "PIDFILE=%~dp0copybara.pid"
set "PYEXE=%~dp0.venv\Scripts\python.exe"

if not exist "%PYEXE%" (
  echo [Copybara] Not set up yet. Run setup.bat first.
  pause
  exit /b 1
)

rem Already running?
if exist "%PIDFILE%" (
  set /p EXPID=<"%PIDFILE%"
  tasklist /fi "PID eq !EXPID!" 2>nul | find "!EXPID!" >nul
  if not errorlevel 1 (
    echo [Copybara] Already running ^(PID !EXPID!^). Use stop.bat first, or status.bat to check.
    pause
    exit /b 0
  )
)

echo [Copybara] Starting...
set "NEWPID="
for /f "usebackq delims=" %%p in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Start-Process -FilePath '%PYEXE%' -ArgumentList '-u','%~dp0copybara_win.py' -WorkingDirectory '%~dp0' -WindowStyle Hidden -RedirectStandardOutput '%~dp0copybara.log' -RedirectStandardError '%~dp0copybara.err.log' -PassThru; $p.Id"`) do set "NEWPID=%%p"

if not defined NEWPID (
  echo [Copybara] Failed to start. See copybara.err.log
  pause
  exit /b 1
)

echo !NEWPID!>"%PIDFILE%"
echo [Copybara] Started ^(PID !NEWPID!^).
echo.
echo   Check state : status.bat
echo   Stop        : stop.bat
echo   Live log    : copybara.log
echo.
pause
