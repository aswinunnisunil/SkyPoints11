@echo off
set "PATH=C:\Users\HP\AppData\Local\Programs\Git\cmd;%PATH%"
echo ========================================================
echo Pushing SkyPoints11 project to GitHub (branch: main)
echo Remote: https://github.com/aswinunnisunil/SkyPoints11.git
echo ========================================================
git push -u origin main
if %ERRORLEVEL% EQU 0 (
    echo.
    echo Successfully pushed to https://github.com/aswinunnisunil/SkyPoints11
) else (
    echo.
    echo If prompted, please authenticate with your GitHub account or Personal Access Token (PAT).
)
pause
