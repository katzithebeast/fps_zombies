@echo off
chcp 65001 >nul
cd /d "%~dp0"
set GODOT=_godot\Godot_v4.7.2-stable_win64.exe
if not exist "%GODOT%" (
  echo Godot 4.7.2 tu jeste neni, stahuju ho ^(asi 70 MB, jen poprve^)...
  if not exist _godot mkdir _godot
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri 'https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip' -OutFile '_godot\godot.zip'; Expand-Archive -Force '_godot\godot.zip' '_godot'; Remove-Item '_godot\godot.zip'"
)
if not exist "%GODOT%" (
  echo Stazeni se nepovedlo. Stahni Godot 4.7.2 ^(Windows, Standard^) z https://godotengine.org
  echo a oba .exe soubory dej do slozky _godot vedle tohoto souboru.
  pause
  exit /b 1
)
echo Kontroluji a importuji soubory projektu ^(poprve to chvili trva^)...
"_godot\Godot_v4.7.2-stable_win64_console.exe" --path . --import
start "" "%GODOT%" --path .
