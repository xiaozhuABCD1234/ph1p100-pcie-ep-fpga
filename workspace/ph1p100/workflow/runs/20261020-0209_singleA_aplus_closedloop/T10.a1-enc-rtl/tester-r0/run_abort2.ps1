$ErrorActionPreference = "Continue"
$ms  = "D:\intelFPGA\18.1\modelsim_ase\win32aloem"
$T   = "T:"
$run = "$T\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-enc-rtl\tester-r0"
$do  = "$run\run5ms.do"
$src = "$T\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-enc-rtl\p2\cases\p2_perf_1920x64_comp"
foreach ($j in @(@{n='abort_after_output'; e='+ABORT_AT=40000'}, @{n='reset_after_output'; e='+RST_AT=40000'})) {
  $rd="$run\runs\$($j.n)"; New-Item -ItemType Directory -Force -Path $rd | Out-Null
  $argv=@('-c','-lib',"$run\work",'tb_a1_deflate_core',"+IN=$src.hex","+META=$src.meta","+OUT=$rd\out.hex","+STAT=$rd\stats.txt",'-do',$do)+$j.e.Split(' ')
  & "$ms\vsim.exe" @argv *> "$rd\stdout.log"; $rc=$LASTEXITCODE
  Write-Host "$($j.n) rc=$rc"
  Get-Content "$rd\stats.txt" | Where-Object { $_ -match 'in_bytes|out_bytes|^done |out_last|stopped|stat_blocks|stat_fixed|stat_stored|stat_cand' } | ForEach-Object { "  $_" }
}
