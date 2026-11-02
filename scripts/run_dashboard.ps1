$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
$python=Join-Path $projectRoot 'tools/oss-cad-suite/lib/python3.exe'
if(-not (Test-Path -LiteralPath $python)){throw 'Pinned OSS CAD Suite Python is missing. See docs/integration/reproduce.md.'}
& $python scripts/dashboard_server.py --open
if($LASTEXITCODE -ne 0){throw "Dashboard server exited with code $LASTEXITCODE"}
