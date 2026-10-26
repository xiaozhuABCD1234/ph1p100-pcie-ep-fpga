# T10.b14-cam-b r1 -- ONE TD session: synthesis + route, no bitgen.
# RTL input is the frozen r0/changed-src set (hash-checked below).
# r1 only changes build engineering: the file-list guard lives in 01_build.tcl.
$ErrorActionPreference = 'Stop'
$Root = 'D:\fpga\ph1p100'
$Pkg  = Join-Path $Root 'workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b14-cam-b'
$TdDir = Join-Path $Pkg 'r1\td'

# --- fail closed if the b14 RTL is not the frozen one ---
$expect = @{
    'camera_a1_uart_top.v'        = 'acc1eff329aa295d01b16123581fee48ef49d444efdce3b7fe62214555517405'
    'f9p_camera_display_core.v'   = 'e17206fb2e15f7590ee55c2ccc072677356ab2cb8efa41fd95ad6d52ab080760'
    'p2_a1_board_top.v'           = 'd61c079b6e1302f51463c3f9b9aef3e716d5b8d05bca04be44d4bb6b355287ca'
}
foreach ($k in $expect.Keys) {
    $got = (Get-FileHash (Join-Path $Pkg "r0\changed-src\$k") -Algorithm SHA256).Hash.ToLower()
    Write-Host "B14_R1_BUILD_HASH $k=$got"
    if ($got -ne $expect[$k]) { throw "frozen RTL hash mismatch: $k $got != $($expect[$k])" }
}
$sdc = (Get-FileHash (Join-Path $TdDir 'p2_board.sdc') -Algorithm SHA256).Hash.ToLower()
Write-Host "B14_R1_BUILD_HASH p2_board.sdc=$sdc"
if ($sdc -ne '3fe1641270eb0cd90a25a3d4724617f7f81103d83f8d364bb954cd41329cf2ed') {
    throw "frozen SDC hash mismatch: $sdc"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'tools\td\td_env.ps1') -TdDir $TdDir -Force
if ($LASTEXITCODE -ne 0) { throw "td_env failed: $LASTEXITCODE" }
Set-Location 'T:\'
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' 01_build.tcl 2>&1 |
    Tee-Object -FilePath 'T:\build_console_r1.log'
Write-Host "BUILD_EXIT=$LASTEXITCODE"
