param([switch]$SkipFormal,[switch]$SkipSynthesis)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
$suite=Join-Path $projectRoot 'tools\oss-cad-suite'
$env:PATH="$suite\bin;$suite\lib;$env:PATH"
New-Item -ItemType Directory -Force build\comparison | Out-Null
function Invoke-Tool([string]$Exe,[string[]]$Arguments,[string]$Log) {
  $text=& $Exe @Arguments 2>&1
  $code=$LASTEXITCODE
  $text | Out-File -LiteralPath $Log -Encoding utf8
  if($code -ne 0) { throw "Tool failed with $code; see $Log" }
}
$rows=@(); $area=@(); $negativeChecks=@()
foreach($mode in 0,1) {
  $exe=Join-Path $projectRoot "build\comparison\mode$mode.out"
  Invoke-Tool 'iverilog' @('-g2012','-s','tb_update',"-Ptb_update.MODE=$mode",'-o',$exe,'rtl/firewall_update.sv','tb/tb_update.sv') "build/comparison/compile$mode.log"
  foreach($gap in 0,4,16) {
    foreach($stall in 0,64) {
      $run=Join-Path $projectRoot "build\comparison\mode$($mode)_gap$($gap)_stall$stall"
      New-Item -ItemType Directory -Force $run | Out-Null
      Push-Location $run
      try {
        Invoke-Tool 'vvp' @($exe,"+GAP=$gap","+STALL=$stall") "$run/simulation.log"
        if((Get-Content "$run/simulation.log" -Raw) -notmatch 'PASS update') { throw 'Missing simulation PASS' }
        $rows+=Import-Csv "$run/metrics.csv"
      } finally { Pop-Location }
      Write-Host "Simulation passed: shadow=$mode gap=$gap stall=$stall"
    }
  }
  if(!$SkipSynthesis) {
    $json="build/comparison/synthesis$mode.json"
    $flow="read_verilog -sv rtl/firewall_update.sv; chparam -set SHADOW $mode firewall_update; synth -top firewall_update -flatten; check; tee -o $json stat -json"
    Invoke-Tool 'yosys' @('-Q','-T','-p',$flow) "build/comparison/synthesis$mode.log"
    $stat=Get-Content $json -Raw | ConvertFrom-Json
    $cells=$stat.modules.'\firewall_update'
    $flops=0
    foreach($p in $cells.num_cells_by_type.PSObject.Properties) { if($p.Name -match 'DFF') { $flops+=[int]$p.Value } }
    $area+=[pscustomobject]@{shadow=$mode;generic_cells=$cells.num_cells;flip_flop_bits=$flops;other_cells=$cells.num_cells-$flops;interpretation='generic Yosys cells; no physical area or timing claim'}
  }
  if(!$SkipFormal) {
    $prefix=if($mode -eq 0) {'stop'} else {'shadow'}
    foreach($task in 'prove','bmc','cover') {
      Invoke-Tool 'sby' @('-f','-d',"build/comparison/$($prefix)_$task",'formal/update.sby',"$($prefix)_$task") "build/comparison/$($prefix)_$task.log"
      Write-Host "Formal passed: $prefix $task"
    }
  }
  # Deliberately break the drain condition in a private source copy.
  $badRoot=Join-Path $projectRoot "build\comparison\early_ack$mode"
  New-Item -ItemType Directory -Force "$badRoot\rtl","$badRoot\formal" | Out-Null
  $source=Get-Content -Raw rtl/firewall_update.sv
  $anchor='DRAIN: if(state==IDLE) begin'
  if(!$source.Contains($anchor)) { throw 'Missing early-ack mutation anchor' }
  [IO.File]::WriteAllText("$badRoot\rtl\firewall_update.sv",$source.Replace($anchor,"DRAIN: if(1'b1) begin"))
  Copy-Item formal\update.sby,formal\update_properties.svh "$badRoot\formal"
  Invoke-Tool 'iverilog' @('-g2012','-s','tb_update',"-Ptb_update.MODE=$mode",'-o',"$badRoot/sim.out","$badRoot/rtl/firewall_update.sv",'tb/tb_update.sv') "$badRoot/compile.log"
  Push-Location $badRoot
  try {
    $badOutput=& vvp sim.out +GAP=4 +STALL=64 2>&1
    $code=$LASTEXITCODE
    $badOutput | Out-File simulation.log -Encoding utf8
    if($code -eq 0 -or (($badOutput -join "`n") -notmatch 'FATAL:')) { throw 'Simulation did not detect early drain mutation' }
    $negativeChecks+=[pscustomobject]@{shadow=$mode;kind='simulation';fault='early_drain';detected=$true;exit_code=$code}
    if(!$SkipFormal) {
      $badOutput=& sby -f -d bmc formal/update.sby "$($prefix)_bmc" 2>&1
      $code=$LASTEXITCODE
      $badOutput | Out-File formal.log -Encoding utf8
      $body=$badOutput -join "`n"
      if($code -eq 0 -or $body -notmatch 'Assert failed' -or $body -match 'ERROR:') { throw 'Formal did not detect early drain mutation' }
      $negativeChecks+=[pscustomobject]@{shadow=$mode;kind='bounded_formal';fault='early_drain';detected=$true;exit_code=$code}
    }
  } finally { Pop-Location }
  Write-Host "Early-drain mutation detected: shadow=$mode"
}
$rows | Export-Csv build/comparison/metrics.csv -NoTypeInformation
if(!$SkipSynthesis) { $area | ConvertTo-Json -Depth 5 | Out-File build/comparison/area.json -Encoding utf8 }
$negativeChecks | ConvertTo-Json -Depth 5 | Out-File build/comparison/mutations.json -Encoding utf8
$hashes=Get-ChildItem rtl,tb,formal,scripts -File -Recurse | Get-FileHash -Algorithm SHA256 | Select-Object Path,Hash
[pscustomobject]@{utc=(Get-Date).ToUniversalTime().ToString('o');source_sha256=$hashes;formal_run=(!$SkipFormal);synthesis_run=(!$SkipSynthesis)} | ConvertTo-Json -Depth 6 | Out-File build/comparison/manifest.json -Encoding utf8
Write-Host 'Comparison evidence saved in build/comparison.'
