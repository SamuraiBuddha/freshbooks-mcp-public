@echo off
echo Pushing FreshBooks MCP to GitHub...
echo.

REM Make sure we're on main branch
git branch -m master main 2>nul

REM Add all files
git add -A

REM Commit if needed
git commit -m "Initial release v1.0.0 - FreshBooks MCP for Claude Desktop" 2>nul

REM Remove old origin if exists
git remote remove origin 2>nul

REM Add new origin (update username if different)
git remote add origin https://github.com/SamuraiBuddha/freshbooks-mcp.git

REM Push to GitHub
echo.
echo Pushing to GitHub...
git push -u origin main

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo SUCCESS! Repository pushed to GitHub
    echo ========================================
    echo.
    echo View your repo at:
    echo https://github.com/SamuraiBuddha/freshbooks-mcp
    echo.
    echo Next steps:
    echo 1. Add a Release on GitHub with the MSI/EXE files
    echo 2. Submit to FreshBooks Marketplace
) else (
    echo.
    echo ERROR: Push failed
    echo.
    echo Make sure you:
    echo 1. Created the repository on GitHub first
    echo 2. Have the correct username/repo name
    echo 3. Are logged in to git (try: git config --global user.name "YourName")
)

pause