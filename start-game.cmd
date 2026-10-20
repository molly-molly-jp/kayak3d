@echo off
rem ============================================================
rem  3D KAYAK RIVER RUSH - start a local server and open the game
rem  index.html works when opened directly, but this is safer!
rem
rem  The ?cb= parameter is a cache buster. It changes the URL
rem  every launch, so the browser always fetches the newest
rem  index.html. Without it the browser can keep serving an
rem  old copy and the game will not reflect your edits.
rem ============================================================
cd /d "%~dp0.."

set "PORT=8123"
set "CB=%RANDOM%%RANDOM%%RANDOM%"
set "GAME=http://localhost:%PORT%/kayak3d/index.html?cb=%CB%"

echo Starting local server on http://localhost:%PORT% ...
start "kayak3d-server" /min cmd /c "py -3 -m http.server %PORT% 2>nul || python -m http.server %PORT%"

timeout /t 2 /nobreak >nul
start "" "%GAME%"

echo.
echo  Game:   %GAME%
echo.
echo  With a VRM avatar, add ^&vrm=mollymolly.vrm to the URL:
echo  %GAME%^&vrm=mollymolly.vrm
echo.
echo  Close the minimized "kayak3d-server" window to stop the server.
timeout /t 8 /nobreak >nul