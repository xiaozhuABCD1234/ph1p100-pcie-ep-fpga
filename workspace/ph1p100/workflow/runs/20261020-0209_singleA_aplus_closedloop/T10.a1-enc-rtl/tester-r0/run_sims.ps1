param()
$ErrorActionPreference = "Continue"
$ms  = "D:\intelFPGA\18.1\modelsim_ase\win32aloem"
$T   = "T:"
$run = "$T\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-enc-rtl\tester-r0"
$cases = "$T\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-enc-rtl\p2\cases"
$do  = "$run\run5ms.do"
$doContent = "run 5 ms`nquit -f`n"
Set-Content -Path $do -Value $doContent -Encoding ascii

$jobs = @(
  @{n='p1_p_8x4_flat_prep0_pred0'; extra=''},
  @{n='p1_p_8x4_grad_prep1_pred0'; extra=''},
  @{n='p1_p_8x4_grad_prep1_pred1'; extra=''},
  @{n='p1_p_1920x4_repeat_prep0_pred0'; extra=''},
  @{n='p1_p_1920x4_repeat_prep1_pred1'; extra=''},
  @{n='p1_p_32x5_tail_prep1_pred1'; extra=''},
  @{n='p2_random_4800'; extra=''},
  @{n='p2_dist2048_len258'; extra=''},
  @{n='p2_len3_dist4'; extra=''},
  @{n='p2_frame_8x5_tail'; extra=''},
  @{n='p2_frame_16x8'; extra=''},
  @{n='p2_frame_16x8_bp'; in='p2_frame_16x8'; extra='+BP=1'},
  @{n='p2_frame_16x8_gapbp'; in='p2_frame_16x8'; extra='+BP=1 +GAP=1'},
  @{n='abort_midblock'; in='p2_frame_16x8'; extra='+ABORT_AT=50'},
  @{n='reset_midblock'; in='p2_frame_16x8'; extra='+RST_AT=50'},
  @{n='p2_perf_1920x64_comp'; extra=''},
  @{n='p2_perf_1920x64_rand'; extra=''}
)
$rows = @()
foreach ($j in $jobs) {
  $nm = $j.n
  $in = if ($j.ContainsKey('in')) { $j.in } else { $nm }
  $rd = "$run\runs\$nm"
  New-Item -ItemType Directory -Force -Path $rd | Out-Null
  $argv = @('-c','-lib',"$run\work",'tb_a1_deflate_core',
            "+IN=$cases\$in.hex","+META=$cases\$in.meta",
            "+OUT=$rd\out.hex","+STAT=$rd\stats.txt",'-do',$do)
  if ($j.extra -ne '') { $argv += $j.extra.Split(' ') }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  & "$ms\vsim.exe" @argv *> "$rd\stdout.log"
  $rc = $LASTEXITCODE
  $sw.Stop()
  $rows += [pscustomobject]@{name=$nm; rc=$rc; sec=[math]::Round($sw.Elapsed.TotalSeconds,1)}
  Write-Host ("{0} rc={1} {2}s" -f $nm,$rc,[math]::Round($sw.Elapsed.TotalSeconds,1))
}
$rows | Export-Csv -NoTypeInformation -Path "$run\sim-exitcodes.csv"
# extract key stats
$summary = foreach ($j in $jobs) {
  $f = "$run\runs\$($j.n)\stats.txt"
  if (Test-Path $f) {
    $h=@{}; Get-Content $f | ForEach-Object { $p=$_ -split ' ',2; if($p.Count -eq 2){$h[$p[0]]=$p[1]} }
    [pscustomobject]@{name=$j.n; in=$h.in_bytes; out=$h.out_bytes; cyc=$h.run_cycles; done=$h.done; last=$h.out_last; early=$h.stopped_early; blocks=$h.stat_blocks; fixed=$h.stat_fixed; stored=$h.stat_stored; lit=$h.stat_literals; match=$h.stat_matches; aborts=$h.stat_cand_aborts; maxmatch=$h.stat_max_match; maxdist=$h.stat_max_dist; tmo=$h.timeout_hit}
  }
}
$summary | Format-Table -AutoSize | Out-String -Width 250
$summary | Export-Csv -NoTypeInformation -Path "$run\sim-summary.csv"
