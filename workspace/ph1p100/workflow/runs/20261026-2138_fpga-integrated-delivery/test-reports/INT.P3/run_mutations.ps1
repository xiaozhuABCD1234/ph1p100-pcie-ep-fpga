# INT.P3 round1 mutation negative controls (tester-owned).
# Purpose: prove the independent TB detects (a) missing valid/ready stall gating and
# (b) missing epoch check in release identity matching. Frozen RTL is only read;
# mutated copies live under test-reports/INT.P3/mut* (never in the candidate tree).
$ErrorActionPreference = 'Stop'
$root = 'D:\fpga\ph1p100'
$run  = "$root\workflow\runs\20261026-2138_fpga-integrated-delivery"
$ev   = "$run\test-reports\INT.P3"
$rtl  = "$root\fpga\csi2\src\integrated_delivery\dual_channel_capture_scheduler.v"
$tb   = "$ev\tb_intp3_indep.v"
$env:PATH = "D:\intelFPGA\18.1\modelsim_ase\win32aloem;" + $env:PATH

$src   = Get-Content -Raw $rtl
$tbsrc = Get-Content -Raw $tb

function Prepare-Mut([string]$dir, [string]$modname, [string]$body) {
    New-Item -ItemType Directory -Force $dir | Out-Null
    [IO.File]::WriteAllText("$dir\$modname.v", $body)
    $t = $tbsrc -replace 'module tb_intp3_indep;', 'module tb_intp3_indep_mut;'
    $t = $t -replace 'dual_channel_capture_scheduler dut', "$modname dut"
    [IO.File]::WriteAllText("$dir\tb_intp3_indep_mut.v", $t)
    Set-Location $dir
    vlib work | Out-Null
    vlog "$modname.v" tb_intp3_indep_mut.v 2>&1 | Out-File -Encoding utf8 compile.log
    vsim -c -do "run -all; quit -f" work.tb_intp3_indep_mut 2>&1 | Out-File -Encoding utf8 sim.log
    $verdict = (Select-String -Path sim.log -Pattern 'TB_INTP3_INDEP FAIL|TB_INTP3_INDEP PASS|TB_INTP3_INDEP TIMEOUT' | Select-Object -Last 1).Line
    return $verdict
}

# MUT1: remove !out_stall gating from both channel accept conditions
$m1 = $src -replace 'module dual_channel_capture_scheduler', 'module dual_channel_capture_scheduler_mut'
$m1 = $m1 -replace 'wire a_can   = a_desc_valid && !a_busy && a_enable && a_id_ok && !out_stall;', 'wire a_can   = a_desc_valid && !a_busy && a_enable && a_id_ok;'
$m1 = $m1 -replace 'wire b_can   = b_desc_valid && !b_busy && b_id_ok && !out_stall;', 'wire b_can   = b_desc_valid && !b_busy && b_id_ok;'
if ($m1 -notmatch 'module dual_channel_capture_scheduler_mut') { throw 'MUT1 module rename failed' }
if ($m1 -match '!out_stall') { throw 'MUT1 stall gate still present' }
$v1 = Prepare-Mut "$ev\mut1_stallgate" 'dual_channel_capture_scheduler_mut' $m1

# MUT2: drop epoch from release identity match (both channels)
$m2 = $src -replace 'module dual_channel_capture_scheduler', 'module dual_channel_capture_scheduler_mut'
$n1 = ([regex]::Matches($m2, '\(a_inf_epoch == rel_epoch\) &&')).Count
$n2 = ([regex]::Matches($m2, '\(b_inf_epoch == rel_epoch\) &&')).Count
if ($n1 -ne 1 -or $n2 -ne 1) { throw "MUT2 epoch match sites unexpected: a=$n1 b=$n2" }
$m2 = $m2 -replace '\(a_inf_epoch == rel_epoch\) &&', ''
$m2 = $m2 -replace '\(b_inf_epoch == rel_epoch\) &&', ''
$v2 = Prepare-Mut "$ev\mut2_rel_epoch" 'dual_channel_capture_scheduler_mut' $m2

"RESULT_MUT1: $v1"
"RESULT_MUT2: $v2"
Set-Location $ev
