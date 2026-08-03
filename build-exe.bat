@echo off
setlocal
title CP9X - Build Windows Installer
pushd "%~dp0"

echo ============================================
echo    CP9X Desktop - Build Windows Installer
echo ============================================
echo.

where npm.cmd >nul 2>nul
if errorlevel 1 goto NONODE

if exist "node_modules" goto BUILD
echo [1/2] Installing dependencies (1-3 min, downloads ~100MB)...
echo.
call npm.cmd install --no-audit --no-fund
if errorlevel 1 goto FAILINSTALL
echo.

:BUILD
echo [2/2] Building installer...
echo.
call npm.cmd run build
if errorlevel 1 goto FAILBUILD

echo.
echo ============================================
echo    DONE - see the "dist" folder
echo ============================================
if exist "dist" start "" explorer "%CD%\dist"
goto END

:NONODE
echo [ERROR] Node.js not found. Install it from https://nodejs.org
goto END

:FAILINSTALL
echo [ERROR] npm install failed. Check your internet connection.
goto END

:FAILBUILD
echo [ERROR] Build failed. Read the error message above.
goto END

:END
echo.
pause
popd
endlocal
