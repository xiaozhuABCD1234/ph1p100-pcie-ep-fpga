# =============================================================================
# run_bitgen_cwc_b19.ps1 -- T10.b19-cam-a r0, TD session 2: ONE bitgen + ONE CWC
# from the SAME r0 routed database (r0/td/a1_board_Runs/phy_1/a1_board_pr.db).
#
# 02_bitgen.tcl / 03_cwc.tcl are copies of the frozen b17 scripts (paths only):
# they fail closed on any negative setup/hold/period slack and require
# cw/compiled.bit == a1_board.bit.  No download, no Flash, no re-synthesis.
# =============================================================================
$ErrorActionPreference = 'Stop'
$Root = 'D:\fpga\ph1p100'
$Pkg  = Join-Path $Root 'workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b19-cam-a'
$TdDir = Join-Path $Pkg 'r0\td'

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'tools\td\td_env.ps1') -TdDir $TdDir -Force
if ($LASTEXITCODE -ne 0) { throw "td_env failed: $LASTEXITCODE" }
Set-Location 'T:\'
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' 02_bitgen.tcl 2>&1 |
    Tee-Object -FilePath 'T:\bitgen_console_r0.log'
$bg = $LASTEXITCODE
Write-Host "BITGEN_EXIT=$bg"
if ($bg -ne 0) { exit 2 }
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' 03_cwc.tcl 2>&1 |
    Tee-Object -FilePath 'T:\cwc_console_r0.log'
$cw = $LASTEXITCODE
Write-Host "CWC_EXIT=$cw"
if ($cw -ne 0) { exit 3 }

$rows = @()
foreach ($rel in @('a1_board.bit','a1_board.cwc','a1_board_inst.bid','cw\compiled.bit','cw\compiled.cwc')) {
    $p = Join-Path $TdDir $rel
    if (Test-Path $p) {
        $rows += ('{0}  {1}  {2}' -f (Get-FileHash $p -Algorithm SHA256).Hash, (Get-Item $p).Length, $rel)
    } else {
        $rows += ('MISSING  {0}' -f $rel)
    }
}
$parentBit = (Get-FileHash (Join-Path $TdDir 'a1_board.bit') -Algorithm SHA256).Hash
$compBit   = (Get-FileHash (Join-Path $TdDir 'cw\compiled.bit') -Algorithm SHA256).Hash
$parentCwc = (Get-FileHash (Join-Path $TdDir 'a1_board.cwc') -Algorithm SHA256).Hash
$compCwc   = (Get-FileHash (Join-Path $TdDir 'cw\compiled.cwc') -Algorithm SHA256).Hash
$rows += ('CHECK compiled.bit==a1_board.bit = {0}' -f ($parentBit -eq $compBit))
$rows += ('CHECK compiled.cwc==a1_board.cwc = {0}' -f ($parentCwc -eq $compCwc))
$cwcTxt = Get-Content (Join-Path $TdDir 'a1_board.cwc') -Raw
$rows += ('CHECK phy_eram_present = {0}' -f ($cwcTxt -match '<phy_eram '))
$rows += ('CHECK logic_eram_incomplete = {0}' -f ($cwcTxt -match '<logic_eram [^>]+/>'))
$rows | Set-Content (Join-Path $TdDir 'candidate_hashes_r0.txt')
$rows
if ($parentBit -ne $compBit) { exit 4 }
if ($parentCwc -ne $compCwc) { exit 5 }
Write-Host 'B19_R0_BITGEN_CWC_DONE'
