@echo off
rem Solar-cell micro-crack inspector: double-click to start the GUI (Windows).
rem Uses MATLAB if the "matlab" command is available, otherwise GNU Octave if found.
setlocal
cd /d "%~dp0"
set "HERE=%~dp0"

where matlab >nul 2>nul
if not errorlevel 1 (
    echo Starting MATLAB ... the window may take 20-60 seconds to appear.
    start "" matlab -nosplash -r "cd('%HERE%'); crack_app"
    goto :done
)

set "OCT="
for /d %%D in ("%ProgramFiles%\GNU Octave\Octave-*") do (
    if exist "%%D\mingw64\bin\octave-gui.exe" set "OCT=%%D\mingw64\bin\octave-gui.exe"
    if exist "%%D\mingw64\bin\octave-launch.exe" set "OCT=%%D\mingw64\bin\octave-launch.exe"
    if exist "%%D\octave-launch.exe" set "OCT=%%D\octave-launch.exe"
)
if defined OCT (
    echo Starting GNU Octave ...
    start "" "%OCT%" --gui --persist --eval "cd('%HERE%'); crack_app"
    goto :done
)

echo.
echo Could not find MATLAB or GNU Octave on this computer.
echo  - MATLAB:  open MATLAB, set the Current Folder to this folder, then type  crack_app
echo  - Octave:  install it from https://octave.org/download , then run this file again
echo.
pause
:done
endlocal
