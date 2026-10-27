param(
  [Parameter(Mandatory=$true)][string]$Root,
  [Parameter(Mandatory=$true)][string]$OutDir
)
$ErrorActionPreference='Continue'
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$lines=New-Object System.Collections.Generic.List[string]
function W([string]$t){ $lines.Add($t) | Out-Null; Write-Host $t }
function Sha([string]$p){ (Get-FileHash -Algorithm SHA256 -Path $p).Hash }
$runDir=Join-Path $Root 'workflow\runs\20261017-011744-rk-fpga-align'

foreach($pair in @(@('raw',(Join-Path $runDir 'raw\candidate-manifest.json')),@('backend',(Join-Path $runDir 'backend\candidate-manifest.json')))){
  $tag=$pair[0]; $mp=$pair[1]
  $j=[System.IO.File]::ReadAllText($mp,[System.Text.Encoding]::UTF8)|ConvertFrom-Json
  W ("[$tag] run-dir-relative sections:")
  foreach($sec in @('rk_patch_inputs','build_artifacts')){
    $arr=$j.$sec
    if($null -eq $arr){ W ("[$tag] section $sec : absent"); continue }
    $ok=0;$mm=0;$miss=0;$badlines=@()
    foreach($e in $arr){
      if($null -eq $e.path){ continue }
      $p=Join-Path $runDir ($e.path -replace '/','\')
      if(Test-Path $p){
        $h=Sha $p
        if($h -ieq $e.sha256){$ok++} else {$mm++; $badlines+=("MISMATCH "+$e.path+" manifest="+$e.sha256.Substring(0,16)+" actual="+$h.Substring(0,16))}
      } else {$miss++; $badlines+=("MISSING "+$e.path)}
    }
    W ("[$tag] $sec : total="+$arr.Count+" ok="+$ok+" mismatch="+$mm+" missing="+$miss)
    foreach($bl in $badlines){ W ("   "+$bl) }
  }
  $ve=$j.volatile_excluded
  W ("[$tag] volatile_excluded type=" + $ve.GetType().Name + " count=" + @($ve).Count)
  foreach($x in @($ve)){ W ("   ve: " + ($x | ConvertTo-Json -Compress -Depth 4)) }
}

W ''
W '== bit SHA checks =='
$rawBit=Join-Path $runDir 'raw\candidate\prj\ph1p_pcie_integration_Runs\phy_1\ph1p_pcie_integration.bit'
$bakBit=Join-Path $runDir 'backend\candidate\prj\ph1p_pcie_integration_Runs\phy_1\ph1p_pcie_integration.bit'
W ('raw bit sha256     = ' + (Sha $rawBit) + ' bytes=' + (Get-Item $rawBit).Length)
W ('backend bit sha256 = ' + (Sha $bakBit) + ' bytes=' + (Get-Item $bakBit).Length)
$rawBest=Join-Path $runDir 'raw\candidate\prj\ph1p_pcie_integration_Runs\best_result\ph1p_pcie_integration.bit'
$bakBest=Join-Path $runDir 'backend\candidate\prj\ph1p_pcie_integration_Runs\best_result\ph1p_pcie_integration.bit'
W ('raw best_result bit sha256     = ' + (Sha $rawBest))
W ('backend best_result bit sha256 = ' + (Sha $bakBest))

$lines | Out-File -FilePath (Join-Path $OutDir 'verify3_rundir_output.txt') -Encoding UTF8
Write-Host ('DONE -> ' + (Join-Path $OutDir 'verify3_rundir_output.txt'))
