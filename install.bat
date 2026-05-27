@echo off
chcp 65001 >nul
title RustDesk Clipboard Fix Installer

echo ============================================
echo  RustDesk Clipboard Fix Installer
echo ============================================
echo.
echo This script will replace librustdesk.dll with
echo the clipboard crash fix version.
echo.

:: Check admin rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Please run this script as Administrator!
    echo         Right-click ^> "Run as administrator"
    pause
    exit /b 1
)

:: Kill RustDesk processes
echo [1/3] Stopping RustDesk...
taskkill /f /im rustdesk.exe >nul 2>&1
sc stop RustDesk >nul 2>&1
timeout /t 2 /nobreak >nul

:: Backup
echo [2/3] Backing up original DLL...
copy /y "C:\Program Files\RustDesk\librustdesk.dll" "C:\Program Files\RustDesk\librustdesk.dll.bak" >nul 2>&1

:: Copy fix
echo [3/3] Installing fixed DLL...
copy /y "%~dp0librustdesk.dll" "C:\Program Files\RustDesk\librustdesk.dll"

echo.
echo ============================================
echo  Done! The fix has been installed.
echo  Please restart RustDesk.
echo ============================================
pause
