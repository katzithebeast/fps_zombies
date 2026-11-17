$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimeExe = Join-Path $projectRoot '_godot/Godot_v4.7.2-stable_win64.exe'
$consoleExe = Join-Path $projectRoot '_godot/Godot_v4.7.2-stable_win64_console.exe'
$packDirectory = Join-Path $projectRoot 'dist/Hladina-Multiplayer-v0.1'
$packFile = Join-Path $packDirectory 'Hladina.pck'
$archiveFile = Join-Path $projectRoot 'dist/Hladina-Multiplayer-v0.1.zip'
New-Item -ItemType Directory -Path $packDirectory -Force | Out-Null
& $consoleExe --headless --path $projectRoot --export-pack 'Windows Multiplayer' $packFile
if ($LASTEXITCODE -ne 0) { throw 'Godot export balíčku selhal.' }
Copy-Item -LiteralPath $runtimeExe -Destination (Join-Path $packDirectory 'Hladina.exe') -Force
& $consoleExe --headless --path $projectRoot --script res://tools/build_multiplayer_pack.gd
if ($LASTEXITCODE -ne 0) { throw 'Příprava licencí selhala.' }
Compress-Archive -LiteralPath $packDirectory -DestinationPath $archiveFile -Force
$hash = Get-FileHash -LiteralPath $archiveFile -Algorithm SHA256
Set-Content -LiteralPath ($archiveFile + '.sha256') -Value ($hash.Hash + '  Hladina-Multiplayer-v0.1.zip')
Get-Item -LiteralPath $archiveFile | Select-Object FullName, Length
