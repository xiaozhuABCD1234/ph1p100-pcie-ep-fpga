# =============================================================================
# T10.b17-paxi-native r1 -- ONE TD session: 1 bitgen + 1 CWC from the SAME
# r0 routed database (r1/td/a1_board_Runs/phy_1/a1_board_pr.db).
#
# Planner r1 decision: Routed 0 violations / SWNS +0.002 ns is ACCEPTED as a
# diagnostic candidate (timing_caveat=thin_margin_+0.002), explicitly overriding
# the r0 dev-plan +0.003 floor for this diagnostic bitstream only.  No source,
# SDC, seed, clock or DB change; no re-synthesis, no re-route.
# 02_bitgen.tcl / 03_cwc.tcl are byte-identical copies of the r0 scripts and
# still fail closed on any negative setup/hold/period slack.
# =============================================================================
$ErrorActionPreference = 'Stop'
$Root = 'D:\fpga\ph1p100'
$Pkg  = Join-Path $Root 'workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b17-paxi-native'
$TdDir = Join-Path $Pkg 'r1\td'

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'tools\td\td_env.ps1') -TdDir $TdDir -Force
if ($LASTEXITCODE -ne 0) { throw "td_env failed: $LASTEXITCODE" }
Set-Location 'T:\'
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' 02_bitgen.tcl 2>&1 |
    Tee-Object -FilePath 'T:\bitgen_console_r1.log'
$bg = $LASTEXITCODE
Write-Host "BITGEN_EXIT=$bg"
if ($bg -ne 0) { exit 2 }
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' 03_cwc.tcl 2>&1 |
    Tee-Object -FilePath 'T:\cwc_console_r1.log'
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
$rows | Set-Content (Join-Path $TdDir 'candidate_hashes_r1.txt')
$rows
if ($parentBit -ne $compBit) { exit 4 }
if ($parentCwc -ne $compCwc) { exit 5 }
Write-Host 'B17_R1_BITGEN_CWC_DONE'
