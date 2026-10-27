# T10.b13-ddr-retry r1 -- ONE TD session: synthesis + route, no bitgen.
# Builds from the frozen final RTL in r0/changed-src (6 changed + 4 unchanged copies).
$ErrorActionPreference = 'Stop'
$Root = 'D:\fpga\ph1p100'
$Pkg  = Join-Path $Root 'workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b13-ddr-retry'
$TdDir = Join-Path $Pkg 'r1\td'

# --- fail closed if the final (orphan-drain) camera top is not the frozen one ---
$expect = 'acc1eff329aa295d01b16123581fee48ef49d444efdce3b7fe62214555517405'
$cam = Join-Path $Pkg 'r0\changed-src\camera_a1_uart_top.v'
$got = (Get-FileHash $cam -Algorithm SHA256).Hash.ToLower()
Write-Host "R1_BUILD_CAM_HASH=$got"
if ($got -ne $expect) { throw "final RTL hash mismatch: $got != $expect" }

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'tools\td\td_env.ps1') -TdDir $TdDir -Force
if ($LASTEXITCODE -ne 0) { throw "td_env failed: $LASTEXITCODE" }
Set-Location 'T:\'
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' 01_build.tcl 2>&1 |
    Tee-Object -FilePath 'T:\build_console_r1.log'
Write-Host "BUILD_EXIT=$LASTEXITCODE"
