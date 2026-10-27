# gen_dbg_top.ps1 - T11.runB-debug-rtl: mechanically generate the debug top wrapper
# from ph1p_pcie_ep_top.v port list (single source of truth). ASCII script.
param([string]$Repo)
$ErrorActionPreference='Stop'
Write-Host ("REPO={0}" -f $Repo)
$topPath = Join-Path $Repo 'rtl\ep_side\ph1p_pcie_ep_top.v'
$lines = [System.IO.File]::ReadAllLines($topPath)
$start = -1; for ($i=0;$i -lt $lines.Count;$i++){ if ($lines[$i] -match '^\s*module\s+ph1p_pcie_ep_top\b'){ $start=$i; break } }
if ($start -lt 0) { throw "module line not found" }
$end = -1; for ($i=$start+1;$i -lt $lines.Count;$i++){ if ($lines[$i] -match '^\s*\)\s*;\s*$'){ $end=$i; break } }
if ($end -lt 0) { throw "port-list end not found" }
$ports = @()
for ($i=$start+1; $i -lt $end; $i++) {
  $code = ($lines[$i] -replace '//.*$','')
  if ($code -match '^\s*(input|output|inout)\s+(wire|reg)\s*(\[[^\]]+\])?\s*(\w+)\s*,?\s*$') {
    $ports += [pscustomobject]@{ dir=$Matches[1]; kind=$Matches[2]; width=$Matches[3]; name=$Matches[4]; decl=$code.Trim().TrimEnd(',') }
  }
}
Write-Host ("PORTS_PARSED={0} (after hdr line {1}, end line {2})" -f $ports.Count, ($start+2), ($end+1))
if ($ports.Count -lt 40) { throw "too few ports parsed" }
$o = New-Object System.Collections.Generic.List[string]
$o.Add("///////////////////////////////////////////////////////////////////////////////")
$o.Add("//  ph1p_pcie_ep_top_dbg.v - T11.runB-debug-rtl debug-build top wrapper")
$o.Add("//")
$o.Add("//  ONLY used by the debug build entry: tools/pcie_integration/td/00_all_debug.tcl")
$o.Add("//  Overrides DBG_CTRL_DEFAULT_EN=1'b1 into ph1p_pcie_ep_top -> ep_bar_win, so")
$o.Add("//  the debug bit resets with CTRL bit0(enable)/bit5(ddr_en)=1 ONLY (TX / push /")
$o.Add("//  doorbell domain stays 0). Production 00_all does NOT compile this file and")
$o.Add("//  keeps defaults 0 (behaviour unchanged).")
$o.Add("//  Port list mechanically generated from ph1p_pcie_ep_top.v port block by")
$o.Add("//  run debug-rtl/gen_dbg_top.ps1 (single source of truth; passthrough u_top).")
$o.Add("//")
$o.Add("//  Expected CWC probe path (P2 confirms by elaboration, write back probe-map):")
$o.Add("//    ph1p_pcie_ep_top_dbg/u_top/u_pcie_ep_engine/u_ep_bar_win/dbg_bank[287:0]")
$o.Add("//    and dbg_bank_word0..dbg_bank_word8")
$o.Add("///////////////////////////////////////////////////////////////////////////////")
$o.Add('`timescale 1ns/1ps')
$o.Add("")
$o.Add("module ph1p_pcie_ep_top_dbg (")
for ($k=0; $k -lt $ports.Count; $k++) {
  $suf = if ($k -lt $ports.Count-1) { "," } else { "" }
  $o.Add("    " + $ports[$k].decl + $suf)
}
$o.Add(");")
$o.Add("")
$o.Add("    ph1p_pcie_ep_top #(")
$o.Add("        .DBG_CTRL_DEFAULT_EN (1'b1)")
$o.Add("    ) u_top (")
for ($k=0; $k -lt $ports.Count; $k++) {
  $suf = if ($k -lt $ports.Count-1) { "," } else { "" }
  $o.Add("        ." + $ports[$k].name + "(" + $ports[$k].name + ")" + $suf)
}
$o.Add("    );")
$o.Add("")
$o.Add("endmodule")
$outDir = Join-Path $Repo 'rtl\ep_side\debug'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outPath = Join-Path $outDir 'ph1p_pcie_ep_top_dbg.v'
[System.IO.File]::WriteAllText($outPath, ($o -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
$gen = [System.IO.File]::ReadAllLines($outPath)
$gp = @()
foreach ($ln in $gen) {
  $code = ($ln -replace '//.*$','')
  if ($code -match '^\s*(input|output|inout)\s+(wire|reg)\s*(\[[^\]]+\])?\s*(\w+)\s*,?\s*$') {
    $gp += ("{0}|{1}|{2}" -f $Matches[1], $Matches[3], $Matches[4])
  }
}
$sp = $ports | ForEach-Object { ("{0}|{1}|{2}" -f $_.dir, $_.width, $_.name) }
$dif = Compare-Object -ReferenceObject $sp -DifferenceObject $gp
if ($dif) { Write-Host "PORTS_MISMATCH:"; $dif | ForEach-Object { "  " + $_.SideIndicator + " " + $_.InputObject }; throw "port roundtrip mismatch" }
Write-Host ("PORTS_MATCH={0} (wrapper decls == top decls: dir/width/name)" -f $gp.Count)
Write-Host ("WRAPPER_WRITTEN={0}" -f $outPath)