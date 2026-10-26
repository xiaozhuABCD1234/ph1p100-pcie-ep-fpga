# r3v entry negative-control re-run (new repair instance; round3).
# Purpose: demonstrate that the frozen entry .ps1 files carry a UTF-8 BOM, and
# that their byte-identical no-BOM copies (= pre-fix bytes) still lose the
# $doPath / $tclDst statements under PS5.1 (ACP=936) and abort the documented
# command before writing run.do (no vsim.log).
# Reads frozen files only. Writes only into this evidence directory and
# %TEMP%\opencode\r3v_nobom\ (no-BOM byte copies). ASCII-only script on purpose
# (PS5.1/ANSI-safe).
$ErrorActionPreference = "Continue"
$here = $PSScriptRoot
$root = (Resolve-Path (Join-Path $here "..\..\..\..\..\..\..")).Path
$evid = $here
$nobomDir = Join-Path $env:TEMP "opencode\r3v_nobom"
New-Item -ItemType Directory -Force -Path $nobomDir | Out-Null

$lines = @()
$lines += ("# r3v entry negative-control re-run " + (Get-Date -Format o))
$lines += ("# root = " + $root)

foreach ($n in @('run_sim.ps1', 'run_td.ps1')) {
    $frozen = Join-Path $root ("tools\pcie_integration\" + $n)
    $raw = [System.IO.File]::ReadAllBytes($frozen)
    $hasBom = ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF)
    $nobomBytes = if ($hasBom) { $raw[3..($raw.Length - 1)] } else { $raw }
    $nobom = Join-Path $nobomDir $n
    [System.IO.File]::WriteAllBytes($nobom, $nobomBytes)
    $shaF = (Get-FileHash -Algorithm SHA256 $frozen).Hash.ToLower()
    $shaN = (Get-FileHash -Algorithm SHA256 $nobom).Hash.ToLower()
    $psLinesN = @(Get-Content $nobom).Count
    $netLinesN = @([System.IO.File]::ReadAllLines($nobom)).Count
    $psLinesF = @(Get-Content $frozen).Count
    $netLinesF = @([System.IO.File]::ReadAllLines($frozen)).Count
    $lines += ("## " + $n + " : frozen_has_bom=" + $hasBom)
    $lines += ("   frozen sha256      = " + $shaF)
    $lines += ("   no-BOM copy sha256 = " + $shaN)
    $lines += ("   PS5.1-Get-Content lines: frozen=" + $psLinesF + "  no-BOM copy=" + $psLinesN)
    $lines += ("   .NET-ReadAllLines lines: frozen=" + $netLinesF + "  no-BOM copy=" + $netLinesN)
    $lines += ("   expected pre-fix sha prefix: run_sim=33399210  run_td=760c5524 ; match=" + ($shaN.StartsWith("33399210") -or $shaN.StartsWith("760c5524")))
}

# pre-fix reproduction: run the byte-identical no-BOM run_sim.ps1 copy with the
# documented command form, root pinned explicitly (-Root) since the copy lives
# outside the project. Expect: vlog Errors: 0, then abort at WriteAllLines
# (empty path) before run.do / vsim.log, process exit 0.
$outDir = "workflow/runs/20261017-011744-rk-fpga-align/backend/g1/msim/r3v_entry_before_fix/run"
$nobomSim = Join-Path $nobomDir 'run_sim.ps1'
$so = Join-Path $evid "stdout.txt"
$se = Join-Path $evid "stderr.txt"
$proc = Start-Process powershell -ArgumentList @(
    '-ExecutionPolicy', 'Bypass', '-File', $nobomSim, '-Root', $root,
    '-Tb', 'tb_csi_integrity_diff', '-OutDir', $outDir,
    '-TbFiles', 'tb/tb_csi_integrity_diff.v') -WorkingDirectory $root -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput $so -RedirectStandardError $se

$runDirAbs = Join-Path $root ($outDir -replace '/', '\')
$lines += ("## pre-fix no-BOM copy run (documented command form)")
$lines += ("   exitcode = " + $proc.ExitCode)
$lines += ("   run.do exists      = " + (Test-Path (Join-Path $runDirAbs 'run.do')))
$lines += ("   vsim.log exists    = " + (Test-Path (Join-Path $runDirAbs 'vsim.log')))
$lines += ("   vlog.log exists    = " + (Test-Path (Join-Path $runDirAbs 'vlog.log')))
$lines += ("   commands.log       = " + (Test-Path (Join-Path $runDirAbs 'commands.log')))
if (Test-Path (Join-Path $runDirAbs 'vlog.log')) {
    $lines += ("   vlog.log tail      = " + (Get-Content (Join-Path $runDirAbs 'vlog.log') -Tail 1))
}
$lines | Out-File -Encoding utf8 (Join-Path $evid "decode_view.txt")

$art = @()
foreach ($fn in @('run.do', 'vsim.log', 'vlog.log', 'commands.log')) {
    $art += ("{0}={1}" -f $fn, (Test-Path (Join-Path $runDirAbs $fn)))
}
$art | Out-File -Encoding utf8 (Join-Path $evid "artifacts_after.txt")

Get-Content (Join-Path $evid "decode_view.txt")
