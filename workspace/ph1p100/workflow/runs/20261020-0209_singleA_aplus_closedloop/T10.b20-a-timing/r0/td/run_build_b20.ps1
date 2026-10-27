# =============================================================================
# run_build_b20.ps1 -- T10.b20-a-timing r0, TD session 1: synthesis + ONE route.
#
# Builds only from this package (r0/changed-src, r0/td).  Fails closed if a
# frozen file drifts.  The only RTL delta vs T10.b19-cam-a r0 is a1_frame_top.v
# (one registered abort stage for the drain side); the other 10 changed-src
# files, p2_board.sdc and board_p2.adc must be byte-identical to b19.
# No bitgen here (02_bitgen.tcl is a separate single attempt), no download, no Flash.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File r0\td\run_build_b20.ps1
# =============================================================================
$ErrorActionPreference = 'Stop'
$Root = 'D:\fpga\ph1p100'
$Pkg  = Join-Path $Root 'workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b20-a-timing'
$B19  = Join-Path $Root 'workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b19-cam-a'
$TdDir = Join-Path $Pkg 'r0\td'
$Cs   = Join-Path $Pkg 'r0\changed-src'
$B19Cs = Join-Path $B19 'r0\changed-src'

# b19 frozen set: the 10 files that must stay byte-identical.
$expect = @{
  'f9p_camera_display_core.v'   = 'e17206fb2e15f7590ee55c2ccc072677356ab2cb8efa41fd95ad6d52ab080760'
  'p2_ddr_bridge.v'             = '790d8226ec69499c87b92b0e4a05ac0f26915f57b96bd541affdcdac8e740a61'
  'a1_uart_export.v'            = 'b3d61597534aa0609c53634313e4d14f222839f8b9b8ed83afc140daa04c298d'
  'camera_a1_uart_top.v'        = '73d10388c4a802421563b5b4c66f9cc37d600e7ec49fc0fa94b3d3ea0cbd3ff2'
  'a1_ddr_arb2.v'               = 'b84019bda057afe82ff558e0848d6171fa12732bd8cdb7c6239cb71b3f81d6ba'
  'a1_ddr_slot_store.v'         = '6c619cf90e54385d667f1ec0f63cc87ee58aadd3c42143330ac4945eb47defe9'
  'a1_deflate_core.v'           = 'a91c2ed82fbef654c4e065b64ae1cc268ca232feaa26fdd313c58d8740f81b3e'
  'a1_raw_crop.v'               = '33a6fee77fd1aa67a31cacf26dd5530e5e2ea474ee655cbd5f1d98d887c5d72d'
  'cam_diag_mailbox.v'          = '352af7c85094ea99b575e99da952af8d33871352140e4c6efddff9e6c2407278'
}
foreach ($k in $expect.Keys) {
  $got = (Get-FileHash (Join-Path $Cs $k) -Algorithm SHA256).Hash.ToLower()
  Write-Host "B20_BUILD_HASH $k=$got"
  if ($got -ne $expect[$k]) { throw "frozen RTL hash mismatch: $k $got != $($expect[$k])" }
}
# the single RTL delta: a1_frame_top.v (b19 0064607a... -> b20 cda28c94...)
$ft = (Get-FileHash (Join-Path $Cs 'a1_frame_top.v') -Algorithm SHA256).Hash.ToLower()
Write-Host "B20_BUILD_FRAME_TOP a1_frame_top.v=$ft"
if ($ft -ne 'cda28c941321f28df8318dacaf291f6268ea5e4d6ea9faf9921ed824b3a2160c') {
  throw "a1_frame_top.v is not the b20 abort_d candidate ($ft)"
}
# delta guard: 10 of 11 byte-identical to b19, a1_frame_top.v different
$drift = @()
foreach ($f in (Get-ChildItem $B19Cs -Filter *.v)) {
  $a = (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLower()
  $b = (Get-FileHash (Join-Path $Cs $f.Name) -Algorithm SHA256).Hash.ToLower()
  if ($a -ne $b) { $drift += $f.Name }
}
Write-Host ("B20_BUILD_DELTA_VS_B19 " + ($drift -join ','))
if (($drift.Count -ne 1) -or ($drift[0] -ne 'a1_frame_top.v')) { throw "delta vs b19 is not a1_frame_top.v only: $($drift -join ',')" }
# top: CAM_SEL=0 candidate, unchanged from b19
$topPath = Join-Path $Cs 'p2_a1_board_top.v'
$topTxt = [IO.File]::ReadAllText($topPath)
if ([regex]::Matches($topTxt, [regex]::Escape("localparam CAM_SEL = 1'b0;")).Count -ne 1) {
  throw "p2_a1_board_top.v is not the CAM_SEL=0 candidate"
}
if ($topTxt.Contains("localparam CAM_SEL = 1'b1;")) { throw "stale CAM_SEL=1 text in top" }
$top = (Get-FileHash $topPath -Algorithm SHA256).Hash.ToLower()
Write-Host "B20_BUILD_TOP p2_a1_board_top.v=$top"
if ($top -ne 'b08438e82adcb82726e6632a765e4ac134caea3bb79e0c0a3468274c135981d0') {
  throw "p2_a1_board_top.v is not the b19 CAM_SEL=0 top ($top)"
}
$sdc = (Get-FileHash (Join-Path $TdDir 'p2_board.sdc') -Algorithm SHA256).Hash.ToLower()
Write-Host "B20_BUILD_SDC p2_board.sdc=$sdc"
if ($sdc -ne '0888b6a705a039a6cbabebacf323244a36257b5f29fb51bab7d81ef003220f5e') {
  throw "p2_board.sdc is not the frozen b19 SDC"
}
$sdcTxt = [IO.File]::ReadAllText((Join-Path $TdDir 'p2_board.sdc'))
if (-not $sdcTxt.Contains('-group {mipi_a_clk_hs mipi_a_byte_clk}')) {
  throw "p2_board.sdc lost the A clock group"
}
if ($sdcTxt.Contains('-group {mipi_b_clk_hs mipi_b_byte_clk}')) {
  throw "p2_board.sdc still references the trimmed B byte clock group"
}
$adc = (Get-FileHash (Join-Path $TdDir 'board_p2.adc') -Algorithm SHA256).Hash.ToLower()
if ($adc -ne '1cb30346fa17da6bb0e77802ca72c4b4bb4aecc1445711e19391cf4ee2271580') {
  throw "board_p2.adc is not the b17 r1 file"
}
Write-Host "B20_BUILD_ADC board_p2.adc=$adc"

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'tools\td\td_env.ps1') -TdDir $TdDir -Force
if ($LASTEXITCODE -ne 0) { throw "td_env failed: $LASTEXITCODE" }
Set-Location 'T:\'
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' 01_build.tcl 2>&1 |
    Tee-Object -FilePath 'T:\build_console_r0.log'
$rc = $LASTEXITCODE
Write-Host "BUILD_EXIT=$rc"
Get-ChildItem 'T:\a1_board_Runs' -ErrorAction SilentlyContinue | Select-Object Name
exit $rc
