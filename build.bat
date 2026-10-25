@echo off
rem Builds PangolinPaints.exe (requires the Odin compiler on PATH; SDL3 and stb come from its vendor: collection, the font is embedded)
rem The GUI build has no console window; PangolinPaints-console.exe is the same program for --selftest / --bench output.
odin build src -out:PangolinPaints.exe -o:speed -subsystem:windows
if errorlevel 1 exit /b 1
odin build src -out:PangolinPaints-console.exe -o:speed
if errorlevel 1 exit /b 1
rem SDL3.dll has to sit next to the executables
for /f "delims=" %%i in ('odin root') do copy /Y "%%ivendor\sdl3\SDL3.dll" . >nul
echo Built PangolinPaints.exe and PangolinPaints-console.exe
