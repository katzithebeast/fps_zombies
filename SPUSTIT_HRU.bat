@echo off
chcp 65001 >nul
cd /d "%~dp0"
set GODOT=_godot\Godot_v4.7.2-stable_win64.exe
if not exist "%GODOT%" (
  echo Nenasel jsem %GODOT%. Otevri projekt v Godotu 4.7 rucne ^(soubor project.godot^).
  pause
  exit /b 1
)
echo Kontroluji a importuji soubory projektu...
"_godot\Godot_v4.7.2-stable_win64_console.exe" --path . --import
start "" "%GODOT%" --path .
