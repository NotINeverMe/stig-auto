@echo off
setlocal enabledelayedexpansion

:: Windows Docker STIG Testing Script
:: Simple wrapper for PowerShell script

echo Windows Docker STIG Testing
echo ============================

:: Check if Docker is running
docker version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Docker is not running or not accessible
    echo Please start Docker Desktop and switch to Windows containers
    pause
    exit /b 1
)

:: Check if we're in Windows container mode
for /f "delims=" %%i in ('docker info --format "{{.OSType}}"') do set DOCKER_OS=%%i
if not "%DOCKER_OS%"=="windows" (
    echo WARNING: Docker is not in Windows container mode
    echo Please switch to Windows containers in Docker Desktop
    echo Right-click Docker system tray icon ^> "Switch to Windows containers"
    pause
)

:: Run the PowerShell script with parameters
echo Running PowerShell test script...
powershell -ExecutionPolicy Bypass -File "%~dp0test-locally.ps1" %*

if errorlevel 1 (
    echo.
    echo Tests failed. Check the output above for details.
    pause
    exit /b 1
)

echo.
echo All tests completed successfully!
pause