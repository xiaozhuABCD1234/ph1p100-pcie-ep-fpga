# T10.b15-ddr-pace r0 -- ONE TD session for the single bitgen + single CWC.
# 02_bitgen.tcl is fail-closed on STA; 03_cwc.tcl requires the paired CWC.
$ErrorActionPreference = 'Stop'
$Root = 'D:\fpga\ph1p100'
$Pkg  = Join-Path $Root 'workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b15-ddr-pace'
$TdDir = Join-Path $Pkg 'r0\td'

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'tools\td\td_env.ps1') -TdDir $TdDir -Force
if ($LASTEXITCODE -ne 0) { throw "td_env failed: $LASTEXITCODE" }
Set-Location 'T:\'
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' 02_bitgen.tcl 2>&1 |
    Tee-Object -FilePath 'T:\bitgen_console_r0.log'
if ($LASTEXITCODE -ne 0) { Write-Host "BITGEN_EXIT=$LASTEXITCODE"; exit 2 }
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' 03_cwc.tcl 2>&1 |
    Tee-Object -FilePath 'T:\cwc_console_r0.log'
Write-Host "CWC_EXIT=$LASTEXITCODE"
