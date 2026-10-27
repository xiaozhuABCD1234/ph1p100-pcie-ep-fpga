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

W '== 1. input-snapshot 36 files (SHA + mtime) =='
$snap=[System.IO.File]::ReadAllText((Join-Path $runDir 'env\input-snapshot.json'),[System.Text.Encoding]::UTF8)|ConvertFrom-Json
$same=0;$drift=0;$mtdiff=0
foreach($f in $snap.files){
  $p=Join-Path $Root ($f.path -replace '/','\')
  if(Test-Path $p){
    $h=Sha $p
    if($h -ieq $f.sha256){ $same++ } else { $drift++; W ("  DRIFT " + $f.path + " snap=" + $f.sha256.Substring(0,16) + " act=" + $h.Substring(0,16)) }
    $mt=(Get-Item $p).LastWriteTime.ToString('o')
    if($mt -ne $f.mtime){ $mtdiff++; W ("  MTIME " + $f.path + " snap=" + $f.mtime + " act=" + $mt) }
  } else { $drift++; W ("  MISSING " + $f.path) }
}
W ("snapshot: total=" + $snap.files.Count + " same=$same drift=$drift mtime_diff=$mtdiff")
$dp=Join-Path $runDir 'dev-plan.md'
W ('dev-plan.md current sha256 = ' + (Sha $dp) + ' mtime=' + (Get-Item $dp).LastWriteTime.ToString('o'))

W ''
W '== 2. round1_reads (10 files) =='
$rr=$snap.round1_reads
$ok=0;$bad=0
foreach($f in $rr.files){
  $p=Join-Path $Root ($f.path -replace '/','\')
  if(Test-Path $p){
    $h=Sha $p; $len=(Get-Item $p).Length; $mt=(Get-Item $p).LastWriteTime.ToString('o')
    if(($h -ieq $f.sha256) -and ($len -eq $f.bytes)){ $ok++ } else { $bad++; W ("  MISMATCH " + $f.path + " exp=" + $f.sha256.Substring(0,16) + "/" + $f.bytes + " act=" + $h.Substring(0,16) + "/" + $len) }
    if($mt -ne $f.mtime){ W ("  MTIME-DIFF " + $f.path + " snap=" + $f.mtime + " act=" + $mt) }
  } else { $bad++; W ("  MISSING " + $f.path) }
}
W ("round1_reads: total=" + $rr.files.Count + " ok=$ok bad=$bad")

W ''
W '== 3. raw/backend manifest full recompute =='
foreach($pair in @(@('raw',(Join-Path $runDir 'raw\candidate-manifest.json')),@('backend',(Join-Path $runDir 'backend\candidate-manifest.json')))){
  $tag=$pair[0]; $mp=$pair[1]
  $j=[System.IO.File]::ReadAllText($mp,[System.Text.Encoding]::UTF8)|ConvertFrom-Json
  W ("[$tag] manifest sha256 = " + (Sha $mp))
  foreach($sec in @('production_inputs','build_scripts','test_inputs')){
    $arr=$j.$sec; $okc=0;$mm=0;$ms=0
    foreach($e in $arr){ $p=Join-Path $Root ($e.path -replace '/','\'); if(Test-Path $p){ $h=Sha $p; if($h -ieq $e.sha256){$okc++} else {$mm++; W ("  MISMATCH [$tag/$sec] " + $e.path)} } else {$ms++; W ("  MISSING [$tag/$sec] " + $e.path)} }
    W ("[$tag] $sec : total=" + $arr.Count + " ok=$okc mismatch=$mm missing=$ms")
  }
  foreach($sec in @('rk_patch_inputs','build_artifacts')){
    $arr=$j.$sec; $okc=0;$mm=0;$ms=0
    foreach($e in $arr){ $p=Join-Path $runDir ($e.path -replace '/','\'); if(Test-Path $p){ $h=Sha $p; if($h -ieq $e.sha256){$okc++} else {$mm++; W ("  MISMATCH [$tag/$sec] " + $e.path)} } else {$ms++; W ("  MISSING [$tag/$sec] " + $e.path)} }
    W ("[$tag] $sec : total=" + $arr.Count + " ok=$okc mismatch=$mm missing=$ms")
  }
}
$rawBit=Join-Path $runDir 'raw\candidate\prj\ph1p_pcie_integration_Runs\phy_1\ph1p_pcie_integration.bit'
$bakBit=Join-Path $runDir 'backend\candidate\prj\ph1p_pcie_integration_Runs\phy_1\ph1p_pcie_integration.bit'
W ('raw bit sha256     = ' + (Sha $rawBit))
W ('backend bit sha256 = ' + (Sha $bakBit))

W ''
W '== 4. residual absolute-claim scan =='
$envDir=Join-Path $runDir 'env'
$hits=@()
Get-ChildItem $envDir -File | ForEach-Object { $h=Select-String -Path $_.FullName -Pattern '全库检索' -ErrorAction SilentlyContinue; if($h){ foreach($x in $h){ $hits+=($_.Name + ' L' + $x.LineNumber) } } }
if($hits.Count -eq 0){ W '  env/ : no 全库检索 hit' } else { $hits | ForEach-Object { W ('  env/ ' + $_) } }
$r1ev=Join-Path $runDir 'test-reports\T11.rk-align-base-r1-doc-example-evidence'
W ('r1 evidence dir listing:')
Get-ChildItem $r1ev -Recurse | ForEach-Object { W ('  ' + $_.FullName.Replace($r1ev,'')) }

W ''
W '== 5. raw r0 three-dim reports first lines =='
foreach($f in @('T11.rk-align-raw-r0-functional.md','T11.rk-align-raw-r0-system.md','T11.rk-align-raw-r0-engineering.md')){
  $p=Join-Path $runDir ('test-reports\' + $f)
  if(Test-Path $p){ $first=(Get-Content $p -TotalCount 1); W ("  $f : $first") } else { W ("  $f MISSING") }
}
$r1me=Join-Path $runDir 'test-reports\T11.rk-align-base-r0-functional-evidence\verify_independent_output.txt'
if(Test-Path $r1me){ W ('my r0 evidence file sha256 = ' + (Sha $r1me)) }

$lines | Out-File -FilePath (Join-Path $OutDir 'r1_checks_output.txt') -Encoding UTF8
Write-Host ('DONE -> ' + (Join-Path $OutDir 'r1_checks_output.txt'))
