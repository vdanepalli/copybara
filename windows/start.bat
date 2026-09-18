@echo off
rem ===========================================================================
rem Copybara - start the sender in the background. Tracks PID in copybara.pid,
rem logs to copybara.log / copybara.err.log. Refuses to start a second copy.
rem ===========================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "PIDFILE=%~dp0copybara.pid"
set "PYEXE=%~dp0.venv\Scripts\python.exe"

if not exist "%PYEXE%" goto nosetup
if not exist "%PIDFILE%" goto launch

set /p EXPID=<"%PIDFILE%"
tasklist /fi "PID eq !EXPID!" /nh 2>nul | find /i "python" >nul
if errorlevel 1 goto launch
echo [Copybara] Already running with PID !EXPID!.
echo [Copybara] Use stop.bat first, or status.bat to check.
echo.
pause
exit /b 0

:launch
echo [Copybara] Starting...
set "NEWPID="
for /f "usebackq delims=" %%p in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Start-Process -FilePath '%PYEXE%' -ArgumentList '-X','utf8','-u','%~dp0copybara_win.py' -WorkingDirectory '%~dp0' -WindowStyle Hidden -RedirectStandardOutput '%~dp0copybara.log' -RedirectStandardError '%~dp0copybara.err.log' -PassThru; $p.Id"`) do set "NEWPID=%%p"
if not defined NEWPID goto failed
echo !NEWPID!>"%PIDFILE%"
echo [Copybara] Started with PID !NEWPID!.
echo.
echo   Check state : status.bat
echo   Stop        : stop.bat
echo   Live log    : copybara.log
echo.
pause
exit /b 0

:failed
echo [Copybara] Failed to start. See copybara.err.log
pause
exit /b 1

:nosetup
echo [Copybara] Not set up yet. Run setup.bat first.
pause
exit /b 1
