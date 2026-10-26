# T10.b13-ddr-retry r0 (b13b) -- one TD session: synthesis + route, no bitgen.
$ErrorActionPreference = 'Stop'
$Root = 'D:\fpga\ph1p100'
$TdDir = Join-Path $Root 'workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b13-ddr-retry\r0\td'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'tools\td\td_env.ps1') -TdDir $TdDir -Force
if ($LASTEXITCODE -ne 0) { throw "td_env failed: $LASTEXITCODE" }
Set-Location 'T:\'
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' 01_build.tcl 2>&1 |
    Tee-Object -FilePath 'T:\build_console_b13f.log'
Write-Host "BUILD_EXIT=$LASTEXITCODE"
