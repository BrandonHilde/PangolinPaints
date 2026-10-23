@echo off
rem Builds PangolinPaints.exe (requires the Odin compiler on PATH; raylib ships with Odin's vendor: collection)
odin build src -out:PangolinPaints.exe -o:speed
if errorlevel 1 exit /b 1
echo Built PangolinPaints.exe
