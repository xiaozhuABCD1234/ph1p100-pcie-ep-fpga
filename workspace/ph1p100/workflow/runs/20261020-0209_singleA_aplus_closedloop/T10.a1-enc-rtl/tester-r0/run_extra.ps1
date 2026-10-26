$ErrorActionPreference = "Continue"
$ms  = "D:\intelFPGA\18.1\modelsim_ase\win32aloem"
$T   = "T:"
$run = "$T\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-enc-rtl\tester-r0"
$cases = "$run\cases"
$do  = "$run\run5ms.do"
$jobs = @(
  @{n='mix_fixed_then_stored'; extra=''},
  @{n='mix_stored_then_fixed'; extra=''},
  @{n='abort_after_block1'; extra='+ABORT_AT=8000'; in='p2_perf_1920x64_comp'},
  @{n='reset_after_block1'; extra='+RST_AT=8000'; in='p2_perf_1920x64_comp'}
)
foreach ($j in $jobs) {
  $nm=$j.n; $in = if ($j.ContainsKey('in')) { $j.in } else { $nm }
  $rd = "$run\runs\$nm"; New-Item -ItemType Directory -Force -Path $rd | Out-Null
  $src = if ($j.ContainsKey('in')) { "$T\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-enc-rtl\p2\cases\$in" } else { "$cases\$in" }
  $argv = @('-c','-lib',"$run\work",'tb_a1_deflate_core',"+IN=$src.hex","+META=$src.meta","+OUT=$rd\out.hex","+STAT=$rd\stats.txt",'-do',$do)
  if ($j.extra -ne '') { $argv += $j.extra.Split(' ') }
  & "$ms\vsim.exe" @argv *> "$rd\stdout.log"
  $rc=$LASTEXITCODE
  Write-Host "$nm rc=$rc"
  Get-Content "$rd\stats.txt" | Where-Object { $_ -match 'in_bytes|out_bytes|run_cycles|^done |out_last|stopped|stat_blocks|stat_fixed|stat_stored|stat_literals|stat_matches|stat_cand' } | ForEach-Object { "  $_" }
}
