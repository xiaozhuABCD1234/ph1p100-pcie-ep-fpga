# gen_validate_dbg_sdc.ps1 — T11.runB-debug-rtl P1-fix: mechanical debug SDC variant + fail-closed checks
# Rule: production SDC stays byte-identical; debug SDC = production + "u_top/" prefix on the 3
# hierarchical object references only (rename_clock clock object + 2 create_generated_clock pins).
param([string]$Repo, [string]$OutDir)
$ErrorActionPreference = 'Stop'
$prodPath = Join-Path $Repo 'constraints\ph1p_pcie_case_ep.sdc'
$dbgPath  = Join-Path $Repo 'constraints\ph1p_pcie_case_ep_dbg.sdc'
$prodSha  = '3f999c447abbb8908e0c830c1b2bf0313dc8a30b3f50a2ed899f3793bfa4c13a'
$fail = @()
function Chk($cond, $msg) { if (-not $cond) { $script:fail += $msg; Write-Host ("FAIL: " + $msg) } else { Write-Host ("ok  : " + $msg) } }
# 1) production SDC unchanged
$h = (Get-FileHash -Algorithm SHA256 -Path $prodPath).Hash.ToLower()
Chk ($h -eq $prodSha) ("production SDC byte-identical (sha=" + $h.Substring(0,16) + "..)")
$pl = [System.IO.File]::ReadAllLines($prodPath)
# 2) mechanical transform: exactly 3 prefix insertions
$dl = New-Object System.Collections.Generic.List[string]
$nPll = 0; $nCa = 0; $nCb = 0
foreach ($ln in $pl) {
  $t = $ln
  if ($t.Contains('get_clocks {u_pcie_pll_ep/')) { $t = $t.Replace('get_clocks {u_pcie_pll_ep/', 'get_clocks {u_top/u_pcie_pll_ep/'); $nPll++ }
  if ($t.Contains('get_pins {u_csi_a/')) { $t = $t.Replace('get_pins {u_csi_a/', 'get_pins {u_top/u_csi_a/'); $nCa++ }
  if ($t.Contains('get_pins {u_csi_b/')) { $t = $t.Replace('get_pins {u_csi_b/', 'get_pins {u_top/u_csi_b/'); $nCb++ }
  $dl.Add($t)
}
Chk (($nPll -eq 1) -and ($nCa -eq 1) -and ($nCb -eq 1)) ("exactly 3 hierarchical refs prefixed (pll=" + $nPll + " csi_a=" + $nCa + " csi_b=" + $nCb + ")")
# 3) diff audit: same line count, exactly 3 changed lines, each = prod line with one "u_top/" insertion
$diffCount = 0
for ($i = 0; $i -lt $pl.Count; $i++) {
  if ($pl[$i] -ne $dl[$i]) {
    $diffCount++
    $restored = $dl[$i].Replace('u_top/', '')
    if ($restored -ne $pl[$i]) { $fail += "line $($i+1) diff is not a pure u_top prefix insertion" }
  }
}
Chk (($pl.Count -eq $dl.Count) -and ($diffCount -eq 3)) ("diff == 3 lines, same line count (" + $diffCount + "/" + $pl.Count + ")")
# 4) no other hierarchical object refs left unprefixed (except clock-name wildcard *usr_clk)
foreach ($ln in $dl) {
  foreach ($m in [regex]::Matches($ln, '\{([^}]*)\}')) {
    $obj = $m.Groups[1].Value
    if ($obj -match '^[A-Za-z_][A-Za-z0-9_]*(\[|$)' ) { }
    if ($obj.Contains('/') -and (-not $obj.StartsWith('u_top/')) -and (-not $obj.StartsWith('*'))) { $fail += ("unprefixed hierarchical object: " + $obj) }
  }
}
Chk (($fail | Where-Object { $_ -like 'unprefixed*' }).Count -eq 0) "no unprefixed hierarchical objects outside u_top/"
# 5) clock table identical to production (names/periods/waveforms/generated args)
$clkOf = { param($lines) $lines | Where-Object { $_ -match 'create_clock|create_generated_clock|rename_clock' } | ForEach-Object { ($_ -replace '\[get_(pins|clocks|ports)\s*\{[^}]*\}\]','[OBJ]') } }
$pt = & $clkOf $pl; $dt = & $clkOf $dl
$cmp = Compare-Object -ReferenceObject $pt -DifferenceObject $dt
Chk ($null -eq $cmp) ("clock definition table identical (names/periods/args; " + $pt.Count + " defs)")
# 6) clock groups: exactly 1 set_clock_groups with 4 -group
$grp = ($dl | Where-Object { $_ -match 'set_clock_groups' }).Count
$gl = ($dl -join "`n")
$groupCount = ([regex]::Matches($gl, '-group\s+\[get_clocks')).Count
Chk (($grp -eq 1) -and ($groupCount -eq 4)) ("clock groups: 1 command, 4 groups (" + $grp + "/" + $groupCount + ")")
# 7) write only if all checks pass (fail-closed)
if ($fail.Count -eq 0) {
  [System.IO.File]::WriteAllText($dbgPath, (($dl -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
  Write-Host ("WROTE=" + $dbgPath)
  Write-Host ("DBG_SDC_SHA=" + (Get-FileHash -Algorithm SHA256 -Path $dbgPath).Hash.ToLower())
} else { throw ("fail-closed: " + $fail.Count + " validation failure(s); debug SDC NOT written") }
Write-Host "RESULT=PASS"