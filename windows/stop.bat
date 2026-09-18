@echo off
rem ===========================================================================
rem Copybara - stop the background sender (by PID from copybara.pid).
rem ===========================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0"
set "PIDFILE=%~dp0copybara.pid"

if not exist "%PIDFILE%" (
  echo [Copybara] Not running ^(no copybara.pid found^).
  pause
  exit /b 0
)

set /p EXPID=<"%PIDFILE%"
tasklist /fi "PID eq !EXPID!" 2>nul | find "!EXPID!" >nul
if errorlevel 1 (
  echo [Copybara] Process !EXPID! was not running. Cleaning up.
  del "%PIDFILE%" >nul 2>&1
  pause
  exit /b 0
)

taskkill /PID !EXPID! /T /F >nul 2>&1
del "%PIDFILE%" >nul 2>&1
echo [Copybara] Stopped ^(PID !EXPID!^).
pause
