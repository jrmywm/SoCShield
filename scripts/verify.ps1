param([switch]$SkipFormal,[switch]$SkipMutations)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
$suite=Join-Path $projectRoot 'tools\oss-cad-suite'
if(Test-Path -LiteralPath $suite) { $env:PATH="$suite\bin;$suite\lib;$env:PATH" }
New-Item -ItemType Directory -Force build\logs | Out-Null
$results=[System.Collections.Generic.List[object]]::new()
function Run-Check([string]$Name,[string]$Exe,[string[]]$Arguments,[switch]$ExpectedFailure) {
    $log=Join-Path $projectRoot "build\logs\$Name.log"
    $output=& $Exe @Arguments 2>&1
    $code=$LASTEXITCODE
    $output | Out-File -LiteralPath $log -Encoding utf8
    $body=$output -join "`n"
    if($ExpectedFailure) {
        $ok=($code -ne 0) -and ($body -match 'FATAL:|Assert failed') -and ($body -notmatch 'syntax error|ERROR:')
    } else { $ok=($code -eq 0) }
    $results.Add([pscustomobject]@{name=$Name;exit_code=$code;expected_failure=[bool]$ExpectedFailure;passed=$ok;log=$log})
    Write-Host "$Name : $ok (exit $code)"
    if(!$ok) { throw "Check failed: $Name. See $log" }
}
Run-Check 'compile_directed' 'iverilog' @('-g2012','-s','tb_firewall','-o','build/directed.out','rtl/firewall.sv','tb/tb_firewall.sv')
Push-Location build
try { Run-Check 'directed' 'vvp' @('directed.out') } finally { Pop-Location }
Run-Check 'compile_system' 'iverilog' @('-g2012','-s','tb_system','-o','build/system.out','rtl/firewall.sv','tb/tb_system.sv')
Push-Location build
try { Run-Check 'system' 'vvp' @('system.out') } finally { Pop-Location }
Run-Check 'structural' 'yosys' @('-Q','-T','-p','read_verilog -sv rtl/firewall.sv; hierarchy -check -top firewall; proc; check')
if(!$SkipFormal) {
    Run-Check 'prove' 'sby' @('-f','-d','build/prove','formal/firewall.sby','prove')
    Run-Check 'bmc' 'sby' @('-f','-d','build/bmc','formal/firewall.sby','bmc')
    Run-Check 'cover' 'sby' @('-f','-d','build/cover','formal/firewall.sby','cover')
}
if(!$SkipMutations) {
    $source=Get-Content -Raw rtl/firewall.sv
    $mutants=@(
        @{name='deny_bypass';old='if (allowed) state <= SEND;';new="if (1'b1) state <= SEND;"},
        @{name='live_payload';old='assign mem_req_addr = addr_q;';new='assign mem_req_addr = req_addr;'},
        @{name='reversed_priority';old='if (!found && enabled[j]';new='if (enabled[j]'},
        @{name='word_end_escape';old="({1'b0, req_addr} + 33'd3 <= {1'b0, limit[j]})";new="1'b1"}
    )
    foreach($mutant in $mutants) {
        if(!$source.Contains($mutant.old)) { throw "Mutation anchor missing: $($mutant.name)" }
        $root=Join-Path $projectRoot "build\mutations\$($mutant.name)"
        New-Item -ItemType Directory -Force "$root\rtl","$root\formal" | Out-Null
        [IO.File]::WriteAllText("$root\rtl\firewall.sv",$source.Replace($mutant.old,$mutant.new))
        Copy-Item formal\firewall_properties.svh,formal\firewall.sby "$root\formal"
        Run-Check "compile_$($mutant.name)" 'iverilog' @('-g2012','-s','tb_system','-o',"$root\sim.out","$root\rtl\firewall.sv",'tb/tb_system.sv')
        Push-Location $root
        try {
            Run-Check "sim_$($mutant.name)" 'vvp' @('sim.out') -ExpectedFailure
            if(!$SkipFormal) { Run-Check "bmc_$($mutant.name)" 'sby' @('-f','-d','bmc','formal/firewall.sby','bmc') -ExpectedFailure }
        } finally { Pop-Location }
    }
}
$hashes=Get-ChildItem rtl,tb,formal,scripts -File -Recurse | Get-FileHash -Algorithm SHA256 | Select-Object Path,Hash
$release=if(Test-Path tools/oss-cad-suite/VERSION) {(Get-Content tools/oss-cad-suite/VERSION -Raw).Trim()} else {'external PATH tools'}
$record=[pscustomobject]@{utc=(Get-Date).ToUniversalTime().ToString('o');checks=$results;source_sha256=$hashes;suite_release=$release}
$record | ConvertTo-Json -Depth 6 | Out-File build/results.json -Encoding utf8
Write-Host 'Verification completed. Evidence: build/results.json'
