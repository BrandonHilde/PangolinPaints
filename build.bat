@echo off
rem Builds PangolinPaints.exe (requires the Odin compiler on PATH; SDL3 and stb come from its vendor: collection, the font is embedded)
rem The GUI build has no console window; PangolinPaints-console.exe is the same program for --selftest / --bench output.
cd /d "%~dp0"
rem OdinUI is a git submodule in libs\odinui: fetch it on the first build after a plain clone
if not exist libs\odinui\odinui (
	git submodule update --init --recursive
	if errorlevel 1 exit /b 1
)
odin build src -out:PangolinPaints.exe -o:speed -subsystem:windows -collection:odinui=libs/odinui
if errorlevel 1 exit /b 1
odin build src -out:PangolinPaints-console.exe -o:speed -collection:odinui=libs/odinui
if errorlevel 1 exit /b 1
rem SDL3.dll has to sit next to the executables
for /f "delims=" %%i in ('odin root') do copy /Y "%%ivendor\sdl3\SDL3.dll" . >nul
echo Built PangolinPaints.exe and PangolinPaints-console.exe
