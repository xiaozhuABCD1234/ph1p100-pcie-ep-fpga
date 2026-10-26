# dbg2.ps1 -- data collection on how PowerShell reads the frozen run_sim.ps1 (ASCII-only evidence file)
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..\..")).Path
$frozen = Join-Path $root "tools\pcie_integration\run_sim.ps1"
"frozen = $frozen"
$fi = Get-Item $frozen
"Length        = $($fi.Length)"
"LastWriteTime = $($fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss.fff'))"
"Hash          = $((Get-FileHash -Algorithm SHA256 $frozen).Hash)"
$raw = [System.IO.File]::ReadAllBytes($frozen)
"raw bytes     = $($raw.Length)"
$cntLF = ($raw | Where-Object { $_ -eq 10 }).Count
$cntCR = ($raw | Where-Object { $_ -eq 13 }).Count
"raw LF=$cntLF  CR=$cntCR"
"Get-Content Default .Count = $((Get-Content $frozen).Count)"
"Get-Content UTF8    .Count = $((Get-Content $frozen -Encoding UTF8).Count)"
"Get-Content OEM     .Count = $((Get-Content $frozen -Encoding OEM).Count)"
$txtAll = [System.IO.File]::ReadAllText($frozen)
"ReadAllText(no enc) chars = $($txtAll.Length)"
$txtUtf8 = [System.IO.File]::ReadAllText($frozen, [System.Text.Encoding]::UTF8)
"ReadAllText(UTF8)   chars = $($txtUtf8.Length)"
[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot "dbg2-readtext-samefile.txt"), $txtAll, (New-Object System.Text.UTF8Encoding($false)))
"written dump of ReadAllText content to dbg2-readtext-samefile.txt"
"---- Get-Content lines 105..130 with numbers:"
$ln = 0
foreach ($l in (Get-Content $frozen)) { $ln++; if ($ln -ge 105 -and $ln -le 130) { "{0,4}: {1}" -f $ln, $l } }
"---- raw-text lines 105..130 with numbers (ReadAllText split on LF):"
$lines = $txtAll -split "`n"
for ($i = 105; $i -le 130 -and $i -le $lines.Count; $i++) { "{0,4}: {1}" -f $i, $lines[$i-1].Substring(0, [Math]::Min(80, $lines[$i-1].Length)) }
