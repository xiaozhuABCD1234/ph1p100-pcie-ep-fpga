$ErrorActionPreference = "Continue"
$ms  = "D:\intelFPGA\18.1\modelsim_ase\win32aloem"
$T   = "T:"
$run = "$T\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-enc-rtl\tester-r0"
$do  = "$run\run5ms.do"
$src = "$T\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-enc-rtl\p2\cases\p2_perf_1920x64_comp"
foreach ($j in @(@{n='p2_perf_comp_bp'; e='+BP=1'}, @{n='p2_perf_comp_gapbp'; e='+BP=1 +GAP=1'})) {
  $rd="$run\runs\$($j.n)"; New-Item -ItemType Directory -Force -Path $rd | Out-Null
  $argv=@('-c','-lib',"$run\work",'tb_a1_deflate_core',"+IN=$src.hex","+META=$src.meta","+OUT=$rd\out.hex","+STAT=$rd\stats.txt",'-do',$do)+$j.e.Split(' ')
  & "$ms\vsim.exe" @argv *> "$rd\stdout.log"; $rc=$LASTEXITCODE
  Write-Host "$($j.n) rc=$rc"
  Get-Content "$rd\stats.txt" | Where-Object { $_ -match 'out_bytes|run_cycles|^done |out_last|timeout' } | ForEach-Object { "  $_" }
}
