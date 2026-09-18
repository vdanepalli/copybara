@echo off
rem ===========================================================================
rem Copybara - show whether the sender is running, plus recent log lines.
rem ===========================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0"
set "PIDFILE=%~dp0copybara.pid"

echo ============ Copybara status ============
if exist "%PIDFILE%" (
  set /p EXPID=<"%PIDFILE%"
  tasklist /fi "PID eq !EXPID!" 2>nul | find "!EXPID!" >nul
  if not errorlevel 1 (
    echo  State : RUNNING  ^(PID !EXPID!^)
  ) else (
    echo  State : STOPPED  ^(stale PID file - run stop.bat to clear^)
  )
) else (
  echo  State : STOPPED
)
echo =========================================
echo.
echo ----- recent activity (copybara.log) -----
if exist "%~dp0copybara.log" (
  powershell -NoProfile -Command "Get-Content -LiteralPath '%~dp0copybara.log' -Tail 12"
) else (
  echo (no log yet - start it with start.bat)
)
echo.
if exist "%~dp0copybara.err.log" (
  for %%s in ("%~dp0copybara.err.log") do if %%~zs GTR 0 (
    echo ----- errors (copybara.err.log) -----
    powershell -NoProfile -Command "Get-Content -LiteralPath '%~dp0copybara.err.log' -Tail 8"
    echo.
  )
)
pause
