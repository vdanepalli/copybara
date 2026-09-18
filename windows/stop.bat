@echo off
rem ===========================================================================
rem Copybara - stop the background sender (by PID from copybara.pid).
rem ===========================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0"
set "PIDFILE=%~dp0copybara.pid"

if not exist "%PIDFILE%" goto notrunning

set /p EXPID=<"%PIDFILE%"
tasklist /fi "PID eq !EXPID!" /nh 2>nul | find /i "python" >nul
if errorlevel 1 goto stale

taskkill /PID !EXPID! /T /F >nul 2>&1
del "%PIDFILE%" >nul 2>&1
echo [Copybara] Stopped PID !EXPID!.
pause
exit /b 0

:stale
echo [Copybara] Process !EXPID! was not running. Cleaned up the stale PID file.
del "%PIDFILE%" >nul 2>&1
pause
exit /b 0

:notrunning
echo [Copybara] Not running - no copybara.pid found.
pause
exit /b 0
