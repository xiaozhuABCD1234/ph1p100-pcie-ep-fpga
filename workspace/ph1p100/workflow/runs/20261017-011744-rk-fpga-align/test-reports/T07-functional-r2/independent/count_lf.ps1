# count_lf.ps1 -- measure how many LF breaks .NET CP936 decoding swallows in the frozen PS1 scripts (ASCII only)
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..\..")).Path
foreach ($f in 'run_sim.ps1', 'run_td.ps1') {
    $p = Join-Path $root ("tools\pcie_integration\" + $f)
    $b = [System.IO.File]::ReadAllBytes($p)
    $t = [System.Text.Encoding]::GetEncoding(936).GetString($b)
    $lfTrue = 0
    foreach ($x in $b) { if ($x -eq 10) { $lfTrue++ } }
    $lfGot = 0
    foreach ($c in $t.ToCharArray()) { if ([int]$c -eq 10) { $lfGot++ } }
    $crTrue = 0
    foreach ($x in $b) { if ($x -eq 13) { $crTrue++ } }
    Write-Output ($f + " bytes=" + $b.Length + " LF_true=" + $lfTrue + " LF_cp936=" + $lfGot + " swallowed=" + ($lfTrue - $lfGot) + " CR=" + $crTrue)
}
