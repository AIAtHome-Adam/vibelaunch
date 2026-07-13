@echo off
REM VibeLaunch entry — session manager for VibeKeys / vibetty
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0vibelaunch.ps1" %*
