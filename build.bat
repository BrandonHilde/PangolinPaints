@echo off
rem Builds PangolinPaints.exe (requires the Odin compiler on PATH; SDL3 and stb come from its vendor: collection, the font is embedded)
rem The GUI build has no console window; PangolinPaints-console.exe is the same program for --selftest / --bench output.
cd /d "%~dp0"
rem OdinUI and the shared Pangolin code are git submodules in libs: fetch them on the first build after a plain clone
set fetch=
if not exist libs\odinui\odinui set fetch=1
if not exist libs\shared\src set fetch=1
if defined fetch (
	git submodule update --init --recursive
	if errorlevel 1 exit /b 1
)
rem Odin compiles one folder as one package, so the shared code is copied in
call libs\shared\sync.bat
odin build src -out:PangolinPaints.exe -o:speed -subsystem:windows -collection:odinui=libs/odinui
if errorlevel 1 exit /b 1
odin build src -out:PangolinPaints-console.exe -o:speed -collection:odinui=libs/odinui
if errorlevel 1 exit /b 1
rem SDL3.dll has to sit next to the executables
for /f "delims=" %%i in ('odin root') do copy /Y "%%ivendor\sdl3\SDL3.dll" . >nul
echo Built PangolinPaints.exe and PangolinPaints-console.exe

