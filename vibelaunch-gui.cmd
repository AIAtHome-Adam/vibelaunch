@echo off
setlocal
set "ROOT=%~dp0"
set "EXE=%ROOT%gui\VibeLaunchGui.Fluent\bin\Release\net8.0-windows\VibeLaunchGui.Fluent.exe"
set "EXEDIR=%ROOT%gui\VibeLaunchGui.Fluent\bin\Release\net8.0-windows"

if exist "%EXE%" (
    start "" /D "%EXEDIR%" "%EXE%"
    exit /b 0
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%gui\vibelaunch-gui.ps1"
exit /b %ERRORLEVEL%
