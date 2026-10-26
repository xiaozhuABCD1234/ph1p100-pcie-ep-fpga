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

W '== 1. new manifest =='
$mp=Join-Path $runDir 'env\artifacts-manifest.json'
W ('manifest sha256 = ' + (Sha $mp))
$mf=[System.IO.File]::ReadAllText($mp,[System.Text.Encoding]::UTF8)|ConvertFrom-Json
W ('round = ' + $mf.round + ' ; entries = ' + $mf.artifacts.Count)
$mm=0
foreach($a in $mf.artifacts){ $p=Join-Path $Root $a.path; if(Test-Path $p){ $h=Sha $p; $len=(Get-Item $p).Length; if(($h -ne $a.sha256) -or ($len -ne $a.bytes)){ $mm++; W ("  MISMATCH " + $a.path) } } else { $mm++; W ("  MISSING " + $a.path) } }
W ("manifest entry mismatches = " + $mm)

W ''
W '== 2. snapshot 36 + round1_reads + round2_reads =='
$snap=[System.IO.File]::ReadAllText((Join-Path $runDir 'env\input-snapshot.json'),[System.Text.Encoding]::UTF8)|ConvertFrom-Json
$same=0;$drift=0
foreach($f in $snap.files){ $p=Join-Path $Root ($f.path -replace '/','\'); if(Test-Path $p){ $h=Sha $p; if($h -ieq $f.sha256){ $same++ } else { $drift++; W ("  DRIFT " + $f.path) } } else { $drift++; W ("  MISSING " + $f.path) } }
W ("snapshot: total=" + $snap.files.Count + " same=$same drift=$drift")
foreach($setName in @('round1_reads','round2_reads')){
  $set=$snap.$setName; $ok=0;$bad=0
  foreach($f in $set.files){ $p=Join-Path $Root ($f.path -replace '/','\'); if(Test-Path $p){ $h=Sha $p; $len=(Get-Item $p).Length; if(($h -ieq $f.sha256) -and ($len -eq $f.bytes)){ $ok++ } else { $bad++; W ("  MISMATCH [$setName] " + $f.path) } } else { $bad++; W ("  MISSING [$setName] " + $f.path) } }
  W ("$setName : total=" + $set.files.Count + " ok=$ok bad=$bad")
}

W ''
W '== 3. raw/backend manifest full recompute + bits =='
foreach($pair in @(@('raw',(Join-Path $runDir 'raw\candidate-manifest.json')),@('backend',(Join-Path $runDir 'backend\candidate-manifest.json')))){
  $tag=$pair[0]; $j=[System.IO.File]::ReadAllText($pair[1],[System.Text.Encoding]::UTF8)|ConvertFrom-Json
  W ("[$tag] manifest sha256 = " + (Sha $pair[1]))
  foreach($sec in @('production_inputs','build_scripts','test_inputs','rk_patch_inputs','build_artifacts')){
    $arr=$j.$sec; $base=if($sec -in @('rk_patch_inputs','build_artifacts')){$runDir}else{$Root}
    $okc=0;$m=0
    foreach($e in $arr){ $p=Join-Path $base ($e.path -replace '/','\'); if(Test-Path $p){ $h=Sha $p; if($h -ieq $e.sha256){$okc++} else {$m++; W ("  MISMATCH [$tag/$sec] " + $e.path)} } else {$m++; W ("  MISSING [$tag/$sec] " + $e.path)} }
    W ("[$tag] $sec : total=" + $arr.Count + " ok=$okc bad=$m")
  }
}
W ('raw bit sha256     = ' + (Sha (Join-Path $runDir 'raw\candidate\prj\ph1p_pcie_integration_Runs\phy_1\ph1p_pcie_integration.bit')))
W ('backend bit sha256 = ' + (Sha (Join-Path $runDir 'backend\candidate\prj\ph1p_pcie_integration_Runs\phy_1\ph1p_pcie_integration.bit')))

W ''
W '== 4. MIPI_PHY_SIM_STUB statistics (r2 fix core) =='
foreach($pair in @(@('raw/g1',(Join-Path $runDir 'raw\g1\msim')),@('backend/g1',(Join-Path $runDir 'backend\g1\msim')))){
  $tag=$pair[0]; $dir=$pair[1]
  $fs=Get-ChildItem $dir -Recurse -File -Filter 'commands.log' -ErrorAction SilentlyContinue
  $with=0;$withNames=@();$without=0
  foreach($f in $fs){ $c=Get-Content $f.FullName -Raw; if($c -match 'defines\s*=\s*MIPI_PHY_SIM_STUB'){ $with++; $tb=([regex]::Match($c,'tb\s*=\s*(\S+)')).Groups[1].Value; $withNames+=($f.Directory.Name+':'+$tb) } else { $without++ } }
  W ("$tag : total=" + $fs.Count + " with_define=$with without=$without")
  if($tag -eq 'backend/g1'){ foreach($n in $withNames){ W ("   WITH " + $n) } }
}

W ''
W '== 5. absolute-marker scan in env docs + script + manifest =='
$scanFiles=@()
Get-ChildItem (Join-Path $runDir 'env') -File | Where-Object { $_.Extension -in '.md','.json' } | ForEach-Object { $scanFiles+=$_.FullName }
$scanFiles+=(Join-Path $Root 'tools\env\env_check.ps1')
$pat='全部|所有|均带|唯一|全库|全树|永不|必带'
foreach($f in $scanFiles){ $hits=Select-String -Path $f -Pattern $pat -ErrorAction SilentlyContinue; foreach($x in $hits){ W ("  " + $f.Replace($runDir,'') + " L" + $x.LineNumber + " : " + $x.Line.Trim().Substring(0,[Math]::Min(110,$x.Line.Trim().Length))) } }

W ''
W '== 6. targeted checks =='
$tcl=Join-Path $Root 'tools\pcie_integration\td\00_all.tcl'
$rc=Select-String -Path $tcl -Pattern 'rc_side' -ErrorAction SilentlyContinue
W ('rc_side in 00_all.tcl : hits=' + @($rc).Count)
$rcDir=Join-Path $Root 'fpga\csi2\pcie_integration\rtl\rc_side'
W ('rtl/rc_side exists under pcie_integration = ' + (Test-Path $rcDir))
$eng=Join-Path $runDir 'test-reports\T11.rk-align-raw-r0-engineering.md'
$engLine=Select-String -Path $eng -Pattern '文档单值笔误' -ErrorAction SilentlyContinue | Select-Object -First 1
W ('raw engineering report item-4 line = ' + $engLine.LineNumber)
$sup=Join-Path $runDir 'test-reports\T11.rk-align-raw-r0-engineering\verify_supplement.txt'
$supLine=Select-String -Path $sup -Pattern '文档数值登记项' -ErrorAction SilentlyContinue | Select-Object -First 1
W ('verify_supplement G-section line = ' + $supLine.LineNumber)
$inv=Join-Path $runDir 'env\environment-inventory.json'
$invHit=Select-String -Path $inv -Pattern '唯一' -ErrorAction SilentlyContinue
foreach($x in $invHit){ W ('  inventory 唯一 L' + $x.LineNumber + ' : ' + $x.Line.Trim().Substring(0,[Math]::Min(110,$x.Line.Trim().Length))) }

$lines | Out-File -FilePath (Join-Path $OutDir 'r2_checks_output.txt') -Encoding UTF8
Write-Host ('DONE -> ' + (Join-Path $OutDir 'r2_checks_output.txt'))
