param([ValidateSet('boot','demo','verify','evaluate','map','all')][string]$Task='demo')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
$suite=Join-Path $projectRoot 'tools/oss-cad-suite'
$env:PATH="$suite\bin;$suite\lib;$env:PATH"
$python=Join-Path $suite 'lib/python3.exe'
function Python-Check([string[]]$Arguments){
  & $python @Arguments
  if($LASTEXITCODE -ne 0){throw "Failed Python step: $($Arguments -join ' ')"}
}
if($Task -in 'boot','all'){Python-Check @('scripts/soc.py','--boot','--out','build/soc/boot')}
if($Task -in 'demo','all'){
  Python-Check @('scripts/soc.py','--mode','0','--trace','--out','build/soc/demo-stop')
  Python-Check @('scripts/soc.py','--mode','1','--trace','--out','build/soc/demo-shadow')
}
if($Task -in 'verify','all'){Python-Check @('scripts/verify_integration.py')}
if($Task -in 'evaluate','all'){Python-Check @('scripts/evaluate_soc.py')}
if($Task -in 'map','all'){Python-Check @('scripts/mapped_soc.py')}
