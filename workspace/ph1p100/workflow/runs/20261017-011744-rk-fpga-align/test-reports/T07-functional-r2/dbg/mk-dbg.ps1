# mk-dbg.ps1 - build an instrumented diagnostic copy of run_sim.ps1 (my own evidence file; ASCII only)
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..\..")).Path
$src = Join-Path $root "tools\pcie_integration\run_sim.ps1"
$dstDir = $PSScriptRoot
$raw = [System.IO.File]::ReadAllText($src, [System.Text.Encoding]::UTF8)
$anchor = '$doPath = Join-Path $outDirF "run.do"'
$idx = $raw.IndexOf($anchor)
Write-Output ("anchor index: " + $idx)
$ins = @'
    "DBG doPath=[$doPath] len=$($doPath.Length)"
    "DBG cwd=$(Get-Location)"
    $dbgSnip = ($doPath.ToCharArray() | ForEach-Object { [int]$_ }) -join ','
    "DBG chars=$dbgSnip"
    try { $null = [System.IO.Path]::GetFullPath($doPath); "DBG GetFullPath OK" } catch { "DBG GetFullPath FAIL: $($_.Exception.Message)" }
'@
$raw2 = $raw.Replace($anchor, $anchor + "`n" + $ins)
Write-Output ("delta bytes: " + ($raw2.Length - $raw.Length))
[System.IO.File]::WriteAllText((Join-Path $dstDir "run_sim_dbg.ps1"), $raw2, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "written"
