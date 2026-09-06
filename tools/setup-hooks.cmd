@echo off
setlocal

cd /d "%~dp0.."

echo.
echo ========================================
echo  CPU Router - Git hooks setup
echo ========================================
echo.

git rev-parse --show-toplevel >nul 2>&1

if errorlevel 1 (
    echo ERROR: This is not a Git repository.
    exit /b 1
)

git config core.hooksPath githooks

if errorlevel 1 (
    echo ERROR: Failed to configure Git hooks path.
    exit /b 1
)

echo Git hooks path configured:
git config --get core.hooksPath

echo.
echo Git hooks are enabled.
echo.

endlocal
