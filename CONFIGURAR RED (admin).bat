@echo off
:: Si no tiene admin, se re-lanza solo con privilegios elevados
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Ya tiene admin - ejecutar el setup
powershell.exe -ExecutionPolicy Bypass -File "%~dp0setup_red.ps1"
