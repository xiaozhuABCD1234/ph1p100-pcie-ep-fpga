# T10.b17-paxi-native r0 -- ONE TD session: synthesis + route, no bitgen.
# Builds from the frozen b17 changed-src (11 files: 7 byte-identical to b15,
# 4 allowed functional/diagnostic edits).  Fails closed if a frozen file drifts.
$ErrorActionPreference = 'Stop'
$Root = 'D:\fpga\ph1p100'
$Pkg  = Join-Path $Root 'workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b17-paxi-native'
$TdDir = Join-Path $Pkg 'r0\td'
$Cs   = Join-Path $Pkg 'r0\changed-src'

$expect = @{
  'f9p_camera_display_core.v'     = 'c9de0d9c176e830df35833eff7e91b811d954fb5480bc13e1fb122ef23305089'
  'a1_ddr_slot_store.v'           = '6c619cf90e54385d667f1ec0f63cc87ee58aadd3c42143330ac4945eb47defe9'
  'a1_ddr_arb2.v'                 = 'b84019bda057afe82ff558e0848d6171fa12732bd8cdb7c6239cb71b3f81d6ba'
  'a1_frame_top.v'                = '0064607aceb20ae3ef14133f0aaf5f8b3f489943011a66a1ddc005350dba7109'
  'a1_deflate_core.v'             = 'a91c2ed82fbef654c4e065b64ae1cc268ca232feaa26fdd313c58d8740f81b3e'
  'a1_raw_crop.v'                 = '33a6fee77fd1aa67a31cacf26dd5530e5e2ea474ee655cbd5f1d98d887c5d72d'
  'cam_diag_mailbox.v'            = '352af7c85094ea99b575e99da952af8d33871352140e4c6efddff9e6c2407278'
}
foreach ($k in $expect.Keys) {
  $got = (Get-FileHash (Join-Path $Cs $k) -Algorithm SHA256).Hash.ToLower()
  Write-Host "B17_BUILD_HASH $k=$got"
  if ($got -ne $expect[$k]) { throw "frozen RTL hash mismatch: $k $got != $($expect[$k])" }
}
foreach ($k in @('p2_ddr_bridge.v','camera_a1_uart_top.v','p2_a1_board_top.v','a1_uart_export.v')) {
  $got = (Get-FileHash (Join-Path $Cs $k) -Algorithm SHA256).Hash.ToLower()
  Write-Host "B17_BUILD_EDITABLE $k=$got"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'tools\td\td_env.ps1') -TdDir $TdDir -Force
if ($LASTEXITCODE -ne 0) { throw "td_env failed: $LASTEXITCODE" }
Set-Location 'T:\'
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' 01_build.tcl 2>&1 |
    Tee-Object -FilePath 'T:\build_console_r0.log'
Write-Host "BUILD_EXIT=$LASTEXITCODE"
