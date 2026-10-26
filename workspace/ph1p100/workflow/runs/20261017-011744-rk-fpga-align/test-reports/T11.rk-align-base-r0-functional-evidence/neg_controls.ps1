param(
  [Parameter(Mandatory=$true)][string]$Root,
  [Parameter(Mandatory=$true)][string]$OutDir
)
$ErrorActionPreference='Continue'
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$sc=Join-Path $Root 'tools\env\env_check.ps1'
$neg=Join-Path $OutDir 'neg'
New-Item -ItemType Directory -Force -Path $neg | Out-Null

Write-Host '--- subst state after my -TdProbe rerun ---'
$sub=(& subst 2>&1 | Out-String)
Write-Host $sub

Write-Host '--- NEG-1: tampered inventory (td.exe sha flipped) -> expect inventory_consistency FAIL, verdict FAIL, exit 1 ---'
$src=Join-Path $Root 'workflow\runs\20261017-011744-rk-fpga-align\env\environment-inventory.json'
$txt=[System.IO.File]::ReadAllText($src,[System.Text.Encoding]::UTF8)
$old='FA2A5AC6E5342B2F801EFA7A6AA345A5FD02D6F25FFA0D1E6380FF0EBD306A87'
$new='FA2A5AC6E5342B2F801EFA7A6AA345A5FD02D6F25FFA0D1E6380FF0EBD306A88'
if($txt.IndexOf($old) -lt 0){ Write-Host 'NEG-1 SETUP ERROR: original sha not found' } else {
  $txt2=$txt.Replace($old,$new)
  $invT=Join-Path $neg 'tampered-inventory.json'
  [System.IO.File]::WriteAllText($invT,$txt2,(New-Object System.Text.UTF8Encoding($false)))
  powershell -ExecutionPolicy Bypass -File $sc -Inventory $invT -LogDir (Join-Path $neg 'tampered-inventory') | Out-Null
  Write-Host ('tampered_exit=' + $LASTEXITCODE)
  $j=Get-ChildItem (Join-Path $neg 'tampered-inventory') -Filter '*.json' | Sort-Object LastWriteTime | Select-Object -Last 1
  $jj=[System.IO.File]::ReadAllText($j.FullName,[System.Text.Encoding]::UTF8) | ConvertFrom-Json
  Write-Host ('tampered verdict=' + $jj.verdict + ' PASS=' + $jj.summary.PASS + ' FAIL=' + $jj.summary.FAIL + ' WARN=' + $jj.summary.WARN)
  foreach($c in $jj.checks){ if($c.id -eq 'inventory_consistency'){ Write-Host ('  inventory_consistency status=' + $c.status + ' summary=' + $c.summary) } }
}

Write-Host '--- NEG-2: nonexistent inventory -> expect WARN, verdict PASS, exit 0 ---'
powershell -ExecutionPolicy Bypass -File $sc -Inventory (Join-Path $neg 'does-not-exist.json') -LogDir (Join-Path $neg 'missing-inventory') | Out-Null
Write-Host ('missing_exit=' + $LASTEXITCODE)
$j=Get-ChildItem (Join-Path $neg 'missing-inventory') -Filter '*.json' | Sort-Object LastWriteTime | Select-Object -Last 1
$jj=[System.IO.File]::ReadAllText($j.FullName,[System.Text.Encoding]::UTF8) | ConvertFrom-Json
Write-Host ('missing verdict=' + $jj.verdict + ' PASS=' + $jj.summary.PASS + ' FAIL=' + $jj.summary.FAIL + ' WARN=' + $jj.summary.WARN)
foreach($c in $jj.checks){ if($c.id -eq 'inventory_consistency'){ Write-Host ('  inventory_consistency status=' + $c.status + ' summary=' + $c.summary) } }

Write-Host '--- NEG-3: no-BOM copy of env_check.ps1 -> observe swallow/self-check behavior ---'
$bytes=[System.IO.File]::ReadAllBytes($sc)
if($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF){
  $stripped=New-Object byte[] ($bytes.Length-3)
  [Array]::Copy($bytes,3,$stripped,0,$bytes.Length-3)
  $copy=Join-Path $neg 'env_check_nobom.ps1'
  [System.IO.File]::WriteAllBytes($copy,$stripped)
  Write-Host ('no-BOM copy bytes=' + $stripped.Length + ' (original=' + $bytes.Length + ')')
  powershell -ExecutionPolicy Bypass -File $copy -Root $Root -LogDir (Join-Path $neg 'nobom') | Out-Null
  Write-Host ('nobom_exit=' + $LASTEXITCODE)
  $j=Get-ChildItem (Join-Path $neg 'nobom') -Filter '*.json' | Sort-Object LastWriteTime | Select-Object -Last 1
  $jj=[System.IO.File]::ReadAllText($j.FullName,[System.Text.Encoding]::UTF8) | ConvertFrom-Json
  Write-Host ('nobom verdict=' + $jj.verdict + ' PASS=' + $jj.summary.PASS + ' FAIL=' + $jj.summary.FAIL + ' WARN=' + $jj.summary.WARN)
  foreach($c in $jj.checks){ if($c.id -eq 'selfcheck_encoding'){ Write-Host ('  selfcheck status=' + $c.status + ' summary=' + $c.summary) } }
} else { Write-Host 'SETUP ERROR: source script has no BOM?' }

Write-Host '--- subst state after negatives ---'
$sub=(& subst 2>&1 | Out-String)
Write-Host $sub
