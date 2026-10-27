# =============================================================================
# run_sim.ps1 -- T11.BRD.P1 G1 simulation runner (ModelSim ASE)
#
#   compiles the td/filelist.tcl source set + sim/tb_brd_g1.v into sim/work,
#   then runs ONE scenario with a hard wall-clock timeout.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\board_integration\run_sim.ps1 -Test tb_brd_arb
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\board_integration\run_sim.ps1 -Test tb_brd_g1_top -Scen 0 -TimeoutMin 20
# =============================================================================
param(
    [string]$Test = "tb_brd_g1_top",
    [string]$Scen = "0",
    [int]$TimeoutMin = 20,
    [switch]$NoCompile,
    [string]$RunDir = ""
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ($RunDir -eq "") { $RunDir = Join-Path $root "workflow\runs\20261027-0726_fpga-board-integration" }
$task = Join-Path $RunDir "T11.BRD.P1"
$sim = Join-Path $task "sim"
$env:Path = "D:\intelFPGA\18.1\modelsim_ase\win32aloem;" + $env:Path

Push-Location $sim
try {
    if (-not $NoCompile) {
        if (Test-Path work) { } else { vlib work | Out-Null }
        # expand the guarded filelist
        $v = @()
        foreach ($l in Get-Content (Join-Path $task "td\filelist.tcl")) {
            if ($l -match 'lappend FL (.+\.v)\s*$') {
                $p = $matches[1]
                if     ($p -match '^\$R2X/(.+)$') { $p = "D:/fpga/ph1p100/workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4/r2-timing-experiment/" + $matches[1] }
                elseif ($p -match '^\$B18/(.+)$') { $p = "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b18-b17-b/r0/changed-src/" + $matches[1] }
                elseif ($p -match '^\$B20/(.+)$') { $p = "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b20-a-timing/r0/changed-src/" + $matches[1] }
                elseif ($p -match '^\$P/(.+)$')   { $p = "D:/fpga/ph1p100/fpga/csi2/pcie_integration/" + $matches[1] }
                elseif ($p -match '^\$R/(.+)$')   { $p = "D:/fpga/ph1p100/" + $matches[1] }
                else { $p = "" }
                if ($p -ne "") { $v += ($p -replace '/', '\') }
            }
        }
        $v += (Join-Path $sim "tb_brd_g1.v")
        Write-Output "SIM_FILELIST_COUNT=$($v.Count)"
        & vlog -quiet -work work @v 2>&1 | Tee-Object -FilePath (Join-Path $sim "compile.log") | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Error "vlog failed (see sim/compile.log)"; exit 6 }
    }

    $log = Join-Path $sim ("sim_" + $Test + "_scen" + $Scen + "_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
    $vs = Join-Path $env:Path.Split(';')[0] "vsim.exe"
    $args = @("-c", "-quiet", "-do", "run -all; quit -f", "work.$Test")
    if ($Test -eq "tb_brd_g1_top") { $args += "+SCEN=$Scen" }
    $p = Start-Process -FilePath $vs -ArgumentList $args -WorkingDirectory $sim `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -NoNewWindow
    $ok = $p.WaitForExit($TimeoutMin * 60 * 1000)
    if (-not $ok) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
        Write-Output "SIM_TIMEOUT test=$Test scen=$Scen minutes=$TimeoutMin log=$log"
        exit 3
    }
    $p.Refresh()
    $txt = Get-Content $log -Raw
    foreach ($m in [regex]::Matches($txt, '(?m)^#\s*(PASS|FAIL|POS_RESULT|NEG1_RESULT|NEG2_RESULT|ARB_RESULT)[^\r\n]*')) {
        Write-Output $m.Value.Trim()
    }
    Write-Output "SIM_LOG=$log"
} finally {
    Pop-Location
}
