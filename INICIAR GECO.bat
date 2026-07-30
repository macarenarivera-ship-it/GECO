@echo off
echo Iniciando servidor GECO...
echo.
powershell.exe -ExecutionPolicy Bypass -File "%~dp0serve.ps1"
echo.
echo El servidor se detuvo.
pause
