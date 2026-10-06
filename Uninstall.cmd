@echo off
rem Double-click to remove everything Install.cmd added.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
pause
