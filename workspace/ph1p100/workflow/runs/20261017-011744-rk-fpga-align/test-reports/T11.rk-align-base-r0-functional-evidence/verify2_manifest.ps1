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
$sections=@('production_inputs','build_scripts','test_inputs','rk_patch_inputs','build_artifacts')

foreach($pair in @(@('raw',(Join-Path $runDir 'raw\candidate-manifest.json')),@('backend',(Join-Path $runDir 'backend\candidate-manifest.json')))){
  $tag=$pair[0]; $mp=$pair[1]
  $j=[System.IO.File]::ReadAllText($mp,[System.Text.Encoding]::UTF8)|ConvertFrom-Json
  W ("[$tag] manifest sha256 = " + (Sha $mp))
  foreach($sec in $sections){
    $arr=$j.$sec
    if($null -eq $arr){ W ("[$tag] section $sec : absent"); continue }
    $ok=0;$mm=0;$miss=0;$skip=0;$badlines=@()
    foreach($e in $arr){
      if($null -eq $e.path){ continue }
      if(-not $e.sha256){ $skip++; $badlines+=("NO-SHA "+$e.path); continue }
      $p=Join-Path $Root ($e.path -replace '/','\')
      if(Test-Path $p){
        $h=Sha $p
        if($h -ieq $e.sha256){$ok++} else {$mm++; $badlines+=("MISMATCH "+$e.path+" manifest="+$e.sha256.Substring(0,16)+" actual="+$h.Substring(0,16))}
      } else {$miss++; $badlines+=("MISSING "+$e.path)}
    }
    W ("[$tag] $sec : total="+$arr.Count+" ok="+$ok+" mismatch="+$mm+" missing="+$miss+" no_sha="+$skip)
    foreach($bl in $badlines){ W ("   "+$bl) }
  }
  $ve=$j.volatile_excluded
  if($ve){ W ("[$tag] volatile_excluded entries = " + $ve.Count) }
}

W ''
$ec=Join-Path $Root 'tools\env\env_check.ps1'
$code=0
foreach($ln in [System.IO.File]::ReadAllLines($ec,[System.Text.Encoding]::UTF8)){
  if($ln.Trim() -eq '$script:SelfCheck++'){ $code++ }
}
W ("env_check strict code-line '`$script:SelfCheck++' count = " + $code)

W ''
$gitsrc=(Get-Command git).Source
$dirty=@((& $gitsrc -C $Root status --porcelain 2>&1 | Out-String) -split "`r?`n" | Where-Object {$_.Trim() -ne ''})
W ("git dirty total = " + $dirty.Count)
foreach($d in $dirty){ if($d -match 'test-reports|dev-plan|tools/env'){ W ("   git: " + $d) } }

$lines | Out-File -FilePath (Join-Path $OutDir 'verify2_manifest_output.txt') -Encoding UTF8
Write-Host ('DONE -> ' + (Join-Path $OutDir 'verify2_manifest_output.txt'))
