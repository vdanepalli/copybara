@echo off
rem ===========================================================================
rem Copybara - show whether the sender is running, plus recent log lines.
rem ===========================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0"
set "PIDFILE=%~dp0copybara.pid"
set "STATE=STOPPED"
set "SPID="

if not exist "%PIDFILE%" goto show
set /p SPID=<"%PIDFILE%"
tasklist /fi "PID eq !SPID!" /nh 2>nul | find /i "python" >nul
if not errorlevel 1 set "STATE=RUNNING"

:show
echo ============ Copybara status ============
if "!STATE!"=="RUNNING" echo   State : RUNNING   PID !SPID!
if "!STATE!"=="STOPPED" echo   State : STOPPED
echo =========================================
echo.
echo ----- recent activity (copybara.log) -----
if exist "%~dp0copybara.log" powershell -NoProfile -Command "Get-Content -LiteralPath '%~dp0copybara.log' -Tail 15"
if not exist "%~dp0copybara.log" echo   (no log yet - start it with start.bat)
echo.
if exist "%~dp0copybara.err.log" powershell -NoProfile -Command "if((Get-Item -LiteralPath '%~dp0copybara.err.log').Length -gt 0){Write-Host '----- errors (copybara.err.log) -----'; Get-Content -LiteralPath '%~dp0copybara.err.log' -Tail 10}"
echo.
pause
