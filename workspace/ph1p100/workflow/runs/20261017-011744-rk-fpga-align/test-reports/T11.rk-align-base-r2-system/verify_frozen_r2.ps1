# =============================================================================
#  verify_frozen_r2.ps1 - T11.rk-align-base r2 system retest:
#  independent check of the NEW frozen manifest (FF079FFA...) + frozen-input
#  cross-checks + round1/round2 reads + handbook OutDir safety scan.
#  Read-only. ASCII only. Writes report JSON/log next to itself.
# =============================================================================
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..")).Path
$run  = Join-Path $root "workflow\runs\20261017-011744-rk-fpga-align"
$out  = $PSScriptRoot

$results = New-Object System.Collections.ArrayList
function Add-Result {
    param([string]$Id, [string]$Expected, [string]$Actual, [bool]$Match, [string]$Note = "")
    $results.Add([pscustomobject]@{ id = $Id; expected = $Expected; actual = $Actual; match = $Match; note = $Note }) | Out-Null
    $tag = if ($Match) { "[OK]  " } else { "[FAIL]" }
    Write-Host ($tag + " " + $Id + " | exp=" + $Expected + " | act=" + $Actual + " | " + $Note)
}
function Sha256([string]$Path) { (Get-FileHash -Algorithm SHA256 -Path $Path).Hash }
function Has-Bom([string]$Path) {
    $b = [System.IO.File]::ReadAllBytes($Path)
    return ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
}

Write-Host ("root = " + $root)

# ---- 1. artifacts-manifest.json itself (r2 refreeze) ----
$manifestPath = Join-Path $run "env\artifacts-manifest.json"
$mSha = Sha256 $manifestPath
Add-Result "manifest_sha256" "FF079FFAC43BC7007DA9C3BF8D92CDD6ECF5749C46EBE44A4BC091B6A38FC069" $mSha ($mSha -eq "FF079FFAC43BC7007DA9C3BF8D92CDD6ECF5749C46EBE44A4BC091B6A38FC069")

# ---- 2. every artifact in the manifest ----
$manifest = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$count = 0; $bad = 0
foreach ($a in $manifest.artifacts) {
    $p = Join-Path $root ($a.path -replace '/', '\')
    $count++
    if (-not (Test-Path $p)) {
        Add-Result ("artifact:" + $a.path) ($a.sha256 + "/" + $a.bytes) "(MISSING)" $false
        $bad++
        continue
    }
    $h = Sha256 $p
    $b = (Get-Item $p).Length
    $ok = (($h -eq ([string]$a.sha256).ToUpper()) -and ($b -eq [long]$a.bytes))
    if (-not $ok) { $bad++ }
    Add-Result ("artifact:" + $a.path) ($a.sha256 + "/" + $a.bytes) ($h + "/" + $b) $ok
}
Add-Result "artifacts_count" "26" ([string]$count) ($count -eq 26)
Add-Result "artifacts_mismatch_count" "0" ([string]$bad) ($bad -eq 0)

# ---- 3. candidate manifest cross-check SHAs ----
$rawMan = Join-Path $run "raw\candidate-manifest.json"
$bkMan  = Join-Path $run "backend\candidate-manifest.json"
$rawSha = Sha256 $rawMan
$bkSha  = Sha256 $bkMan
Add-Result "raw_candidate_manifest_sha"    "AAB0CC08EF0134D5FCB18B25E0B70C43E9AF1D577513CA2996DC46F22DE76975" $rawSha ($rawSha -eq "AAB0CC08EF0134D5FCB18B25E0B70C43E9AF1D577513CA2996DC46F22DE76975")
Add-Result "backend_candidate_manifest_sha" "68F9F4D05DD219CF4F66009A5BED1BDD6C1DCC7E1A4A386A8974725B733A4275" $bkSha ($bkSha -eq "68F9F4D05DD219CF4F66009A5BED1BDD6C1DCC7E1A4A386A8974725B733A4275")

# ---- 4. raw manifest production_inputs (current valid freeze list) ----
$rawJson = [System.IO.File]::ReadAllText($rawMan, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$pi = @($rawJson.production_inputs)
Add-Result "raw_production_inputs_count" "155" ([string]$pi.Count) ($pi.Count -eq 155)
$badPi = 0
foreach ($e in $pi) {
    $p = Join-Path $root ($e.path -replace '/', '\')
    if (-not (Test-Path $p)) { Add-Result ("prod:" + $e.path) $e.sha256 "(MISSING)" $false; $badPi++; continue }
    $h = Sha256 $p
    $ok = ($h -eq ([string]$e.sha256).ToUpper())
    if (-not $ok) { $badPi++ }
    Add-Result ("prod:" + $e.path) ([string]$e.sha256) $h $ok
}
Add-Result "raw_production_inputs_mismatch_count" "0" ([string]$badPi) ($badPi -eq 0)

# ---- 4b. build_scripts + test_inputs ----
$bs = @($rawJson.build_scripts)
Add-Result "raw_build_scripts_count" "12" ([string]$bs.Count) ($bs.Count -eq 12)
$badBs = 0
foreach ($e in $bs) {
    $p = Join-Path $root ($e.path -replace '/', '\')
    if (-not (Test-Path $p)) { Add-Result ("bs:" + $e.path) $e.sha256 "(MISSING)" $false; $badBs++; continue }
    $h = Sha256 $p
    $ok = ($h -eq ([string]$e.sha256).ToUpper())
    if (-not $ok) { $badBs++ }
    Add-Result ("bs:" + $e.path) ([string]$e.sha256) $h $ok
}
Add-Result "raw_build_scripts_mismatch_count" "0" ([string]$badBs) ($badBs -eq 0)
$ti = @($rawJson.test_inputs)
Add-Result "raw_test_inputs_count" "12" ([string]$ti.Count) ($ti.Count -eq 12)
$badTi = 0
foreach ($e in $ti) {
    $p = Join-Path $root ($e.path -replace '/', '\')
    if (-not (Test-Path $p)) { Add-Result ("ti:" + $e.path) $e.sha256 "(MISSING)" $false; $badTi++; continue }
    $h = Sha256 $p
    $ok = ($h -eq ([string]$e.sha256).ToUpper())
    if (-not $ok) { $badTi++ }
    Add-Result ("ti:" + $e.path) ([string]$e.sha256) $h $ok
}
Add-Result "raw_test_inputs_mismatch_count" "0" ([string]$badTi) ($badTi -eq 0)

# ---- 4b2. build_artifacts (candidate identity) + rk_patch_inputs ----
$ba = @($rawJson.build_artifacts)
Add-Result "raw_build_artifacts_count" "35" ([string]$ba.Count) ($ba.Count -eq 35)
$badBa = 0
foreach ($e in $ba) {
    $p = Join-Path $run ($e.path -replace '/', '\')
    if (-not (Test-Path $p)) { Add-Result ("ba:" + $e.path) $e.sha256 "(MISSING)" $false; $badBa++; continue }
    $h = Sha256 $p
    $ok = ($h -eq ([string]$e.sha256).ToUpper())
    if (-not $ok) { $badBa++ }
    Add-Result ("ba:" + $e.path) ([string]$e.sha256) $h $ok
}
Add-Result "raw_build_artifacts_mismatch_count" "0" ([string]$badBa) ($badBa -eq 0)
$rk = @($rawJson.rk_patch_inputs)
Add-Result "raw_rk_patch_inputs_count" "29" ([string]$rk.Count) ($rk.Count -eq 29)
$badRk = 0
foreach ($e in $rk) {
    $p = Join-Path $run ($e.path -replace '/', '\')
    if (-not (Test-Path $p)) { Add-Result ("rk:" + $e.path) $e.sha256 "(MISSING)" $false; $badRk++; continue }
    $h = Sha256 $p
    $ok = ($h -eq ([string]$e.sha256).ToUpper())
    if (-not $ok) { $badRk++ }
    Add-Result ("rk:" + $e.path) ([string]$e.sha256) $h $ok
}
Add-Result "raw_rk_patch_inputs_mismatch_count" "0" ([string]$badRk) ($badRk -eq 0)

# ---- 4c. package's 17-RTL subset (env/input-snapshot.json) ----
$snapPath = Join-Path $run "env\input-snapshot.json"
$snap = [System.IO.File]::ReadAllText($snapPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$sub = @($snap.manifest_crosscheck.production_inputs_checked)
Add-Result "pkg_crosscheck17_count" "17" ([string]$sub.Count) ($sub.Count -eq 17)
$badSub = 0
foreach ($e in $sub) {
    $p = Join-Path $root ($e.path -replace '/', '\')
    if (-not (Test-Path $p)) { Add-Result ("sub:" + $e.path) $e.actual_sha "(MISSING)" $false; $badSub++; continue }
    $h = Sha256 $p
    $ok = ($h -eq ([string]$e.actual_sha).ToUpper())
    if (-not $ok) { $badSub++ }
    Add-Result ("sub:" + $e.path) ([string]$e.actual_sha) $h $ok
}
Add-Result "pkg_crosscheck17_mismatch_count" "0" ([string]$badSub) ($badSub -eq 0)

# ---- 4d. round1_reads (10) + round2_reads (6) ----
$r1 = @($snap.round1_reads.files)
Add-Result "round1_reads_count" "10" ([string]$r1.Count) ($r1.Count -eq 10)
$badR1 = 0
foreach ($e in $r1) {
    $p = Join-Path $root ($e.path -replace '/', '\')
    if (-not (Test-Path $p)) { Add-Result ("r1:" + $e.path) $e.sha256 "(MISSING)" $false; $badR1++; continue }
    $h = Sha256 $p
    $ok = ($h -eq ([string]$e.sha256).ToUpper())
    if (-not $ok) { $badR1++ }
    Add-Result ("r1:" + $e.path) ([string]$e.sha256) $h $ok
}
Add-Result "round1_reads_mismatch_count" "0" ([string]$badR1) ($badR1 -eq 0)
$r2 = @($snap.round2_reads.files)
Add-Result "round2_reads_count" "6" ([string]$r2.Count) ($r2.Count -eq 6)
$badR2 = 0
foreach ($e in $r2) {
    $p = Join-Path $root ($e.path -replace '/', '\')
    if (-not (Test-Path $p)) { Add-Result ("r2:" + $e.path) $e.sha256 "(MISSING)" $false; $badR2++; continue }
    $h = Sha256 $p
    $ok = ($h -eq ([string]$e.sha256).ToUpper())
    if (-not $ok) { $badR2++ }
    Add-Result ("r2:" + $e.path) ([string]$e.sha256) $h $ok
}
Add-Result "round2_reads_mismatch_count" "0" ([string]$badR2) ($badR2 -eq 0)

# ---- 5. candidate bits ----
$rawBit = Join-Path $run "raw\candidate\prj\ph1p_pcie_integration_Runs\phy_1\ph1p_pcie_integration.bit"
$bkBit  = Join-Path $run "backend\candidate\prj\ph1p_pcie_integration_Runs\phy_1\ph1p_pcie_integration.bit"
if (Test-Path $rawBit) {
    $h = Sha256 $rawBit
    Add-Result "raw_candidate_bit_sha" "14B32037EB0B4AFF4F9EA1F61B75160C11FF9381E23F11563F97ECAF5BF5686B" $h ($h -eq "14B32037EB0B4AFF4F9EA1F61B75160C11FF9381E23F11563F97ECAF5BF5686B")
} else { Add-Result "raw_candidate_bit_sha" "14B32037..." "(MISSING)" $false }
if (Test-Path $bkBit) {
    $h = Sha256 $bkBit
    Add-Result "backend_r3_bit_sha" "0943CB36FEEB873DECC6EA5AAE1C2777B3AB4881EBE2954B43BEE040CEB38B0A" $h ($h -eq "0943CB36FEEB873DECC6EA5AAE1C2777B3AB4881EBE2954B43BEE040CEB38B0A")
} else { Add-Result "backend_r3_bit_sha" "0943CB36..." "(MISSING)" $false }

# ---- 6. entry scripts + BOM ----
$entries = @(
    @{ p = "tools\pcie_integration\run_sim.ps1"; sha = "204D17067989C1AF3D1D522FB469B97B85D5646379304068D9C99A93C580A6BB" },
    @{ p = "tools\pcie_integration\run_td.ps1";  sha = "9B8492FCAE97A563D99EBD430E4B650B66D0B32AA408218C800C1DD0C0EBC02C" },
    @{ p = "tools\pcie_integration\td\00_all.tcl"; sha = "2448C17023DE4C8AF2D7485AC7E076204D0B6A906C047D398F2501612F0E3115" },
    @{ p = "tools\pcie_integration\r10f_strict.py"; sha = "59C772A37F941183C5C950D4A7DF01A1002FF73B94B6E9559AAB7BC2F4BEB1EE" }
)
foreach ($e in $entries) {
    $p = Join-Path $root $e.p
    if (Test-Path $p) {
        $h = Sha256 $p
        Add-Result ("entry:" + $e.p) $e.sha $h ($h -eq $e.sha)
    } else { Add-Result ("entry:" + $e.p) $e.sha "(MISSING)" $false }
}
foreach ($p in @("tools\pcie_integration\run_sim.ps1", "tools\pcie_integration\run_td.ps1", "tools\env\env_check.ps1")) {
    $full = Join-Path $root $p
    $bom = Has-Bom $full
    Add-Result ("bom:" + $p) "True" ([string]$bom) $bom
}

# ---- 7. support files ----
$support = @(
    "tools\pcie_integration\r10f_strict.py",
    "workflow\runs\20261017-011744-rk-fpga-align\raw\rk-change-list.md",
    "workflow\runs\20261017-011744-rk-fpga-align\backend\hardware-ready.md",
    "workflow\runs\20261017-011744-rk-fpga-align\raw\hardware-ready.md",
    "D:\anlogic\TD_Release_2026.2\bin\bw_commands_prompt.exe",
    "D:\anlogic\TD_Release_2026.2\license\Anlogic.lic",
    "D:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe",
    "D:\TD\work\csi2\prj\camera_rgb565_wb_20261015_002820"
)
foreach ($s in $support) {
    $ok = Test-Path $s
    Add-Result ("exists:" + $s) "True" ([string]$ok) $ok
}

# ---- 8. handbook OutDir safety scan (SYS-D2) ----
$handbook = Join-Path $run "env\environment-handbook.md"
$hbText = [System.IO.File]::ReadAllText($handbook, [System.Text.Encoding]::UTF8)
$matches = [regex]::Matches($hbText, "-OutDir\s+([^\s]+)")
Add-Result "handbook_outdir_count" "3" ([string]$matches.Count) ($matches.Count -eq 3)
$badOd = 0
foreach ($m in $matches) {
    $od = ($m.Groups[1].Value -split [char]96)[0]
    $forbidden = ($od -match "(^|/)raw/" -or $od -match "(^|/)backend/" -or $od -match "env/logs" -or $od -match "candidate")
    if ($forbidden) { $badOd++ }
    Add-Result ("outdir:" + $od) "safe" $(if ($forbidden) { "FORBIDDEN" } else { "safe" }) (-not $forbidden)
}

# ---- 9. summary ----
$failCount = @($results | Where-Object { -not $_.match }).Count
$summary = [ordered]@{
    script       = "test-reports/T11.rk-align-base-r2-system/verify_frozen_r2.ps1"
    generated_at = (Get-Date -Format o)
    root         = $root
    checks       = $results
    total        = $results.Count
    failed       = $failCount
    verdict      = if ($failCount -eq 0) { "PASS" } else { "FAIL" }
}
$jsonPath = Join-Path $out "verify_frozen_r2.json"
$logPath  = Join-Path $out "verify_frozen_r2.log"
[System.IO.File]::WriteAllText($jsonPath, ($summary | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# verify_frozen_r2 - " + $summary.generated_at)
$lines.Add("root = " + $root)
$lines.Add("total = " + $summary.total + "  failed = " + $failCount + "  verdict = " + $summary.verdict)
$lines.Add("")
foreach ($r in $results) {
    $tag = "[FAIL]"
    if ($r.match) { $tag = "[OK]  " }
    $lines.Add($tag + " " + $r.id + " | exp=" + $r.expected + " | act=" + $r.actual + " | " + $r.note)
}
[System.IO.File]::WriteAllLines($logPath, $lines, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("verify_frozen_r2 verdict = " + $summary.verdict + " (total=" + $summary.total + " failed=" + $failCount + ")")
Write-Host ("json: " + $jsonPath)
if ($failCount -eq 0) { exit 0 } else { exit 1 }
