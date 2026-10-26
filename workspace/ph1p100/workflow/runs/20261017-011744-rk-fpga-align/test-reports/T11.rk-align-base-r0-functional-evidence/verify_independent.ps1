param(
  [Parameter(Mandatory=$true)][string]$Root,
  [Parameter(Mandatory=$true)][string]$OutDir
)
$ErrorActionPreference='Continue'
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$lines=New-Object System.Collections.Generic.List[string]
function W([string]$t){ $lines.Add($t) | Out-Null; Write-Host $t }
function Sha([string]$p){ (Get-FileHash -Algorithm SHA256 -Path $p).Hash }

$runDir = Join-Path $Root 'workflow\runs\20261017-011744-rk-fpga-align'

W '== A. candidate manifests: recompute every listed file =='
$rawM = Join-Path $runDir 'raw\candidate-manifest.json'
$bakM = Join-Path $runDir 'backend\candidate-manifest.json'
W ('raw candidate-manifest.json sha256     = ' + (Sha $rawM))
W ('backend candidate-manifest.json sha256 = ' + (Sha $bakM))

$rawJ=$null; $bakJ=$null
foreach($pair in @(@('raw',$rawM),@('backend',$bakM))){
  $tag=$pair[0]; $mp=$pair[1]
  $j = [System.IO.File]::ReadAllText($mp,[System.Text.Encoding]::UTF8) | ConvertFrom-Json
  if($tag -eq 'raw'){ $rawJ=$j } else { $bakJ=$j }
  $keys = ($j.PSObject.Properties.Name -join ',')
  W ("[$tag] top-level keys: " + $keys)
  $files = $j.files
  if($null -eq $files){ W "[$tag] no .files array"; continue }
  $mm=0; $ok=0; $miss=0
  foreach($f in $files){
    $p = Join-Path $Root ($f.path -replace '/','\')
    if(Test-Path $p){
      $h = Sha $p
      if($h -ieq $f.sha256){ $ok++ } else {
        $mm++; W ("  MISMATCH [$tag] " + $f.path + " manifest=" + $f.sha256.Substring(0,16) + " actual=" + $h.Substring(0,16))
      }
    } else { $miss++; W ("  MISSING [$tag] " + $f.path) }
  }
  W ("[$tag] files: total=" + $files.Count + " ok=" + $ok + " mismatch=" + $mm + " missing=" + $miss)
}

W ''
W '== B. input-snapshot.json recompute (36 files) =='
$snapPath = Join-Path $runDir 'env\input-snapshot.json'
$s = [System.IO.File]::ReadAllText($snapPath,[System.Text.Encoding]::UTF8) | ConvertFrom-Json
$same=0; $drift=0
foreach($f in $s.files){
  $p = Join-Path $Root ($f.path -replace '/','\')
  if(Test-Path $p){
    $h = Sha $p
    if($h -ieq $f.sha256){ $same++ } else {
      $drift++
      $mt=(Get-Item $p).LastWriteTime.ToString('o')
      W ("  DRIFT " + $f.path + " snapshot=" + $f.sha256.Substring(0,16) + " actual=" + $h.Substring(0,16) + " mtime=" + $mt)
    }
  } else { $drift++; W ("  MISSING " + $f.path) }
}
W ("snapshot files: total=" + $s.files.Count + " same=" + $same + " drift=" + $drift)
$dp = Join-Path $runDir 'dev-plan.md'
W ('dev-plan.md current sha256 = ' + (Sha $dp) + ' | mtime=' + (Get-Item $dp).LastWriteTime.ToString('o') + ' | bytes=' + (Get-Item $dp).Length)
W ('snapshot registered dev-plan post-drift sha256 = ' + $s.post_read_drift.files[0].current_sha256 + ' @ ' + $s.post_read_drift.files[0].current_mtime)

W ''
W '== C. snapshot manifest crosscheck vs raw manifest entries =='
$map=@{}
foreach($f in $rawJ.files){ $map[$f.path]=$f.sha256 }
$bad=0
foreach($e in $s.manifest_crosscheck.production_inputs_checked){
  if($map.ContainsKey($e.path)){
    if($map[$e.path] -ne $e.manifest_sha){ $bad++; W ("  PROD CROSS MISMATCH " + $e.path) }
  } else { $bad++; W ("  PROD CROSS MISSING IN MANIFEST " + $e.path) }
}
W ("production inputs crosscheck: checked=" + $s.manifest_crosscheck.production_inputs_checked.Count + " bad=" + $bad)
$ft = Join-Path $runDir 'raw\candidate\prj\ph1p_pcie_integration_Runs\phy_1\final_timing.rpt'
W ('raw final_timing.rpt sha256 = ' + (Sha $ft))

W ''
W '== D. env_check.ps1 static properties =='
$ec = Join-Path $Root 'tools\env\env_check.ps1'
$b=[System.IO.File]::ReadAllBytes($ec)
W ('env_check BOM (EF BB BF) = ' + ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) + ' | bytes=' + $b.Length)
$txt=[System.IO.File]::ReadAllText($ec,[System.Text.Encoding]::UTF8)
W ('SelfCheck++ occurrence count = ' + ([regex]::Matches($txt,'\$script:SelfCheck\+\+')).Count)
W ('SelfCheckExpected decl = ' + ([regex]::Match($txt,'SelfCheckExpected\s*=\s*\d+')).Value)
W ('script sha256 = ' + (Sha $ec))

W ''
W '== E. environment facts vs inventory =='
$inv = [System.IO.File]::ReadAllText((Join-Path $runDir 'env\environment-inventory.json'),[System.Text.Encoding]::UTF8) | ConvertFrom-Json
$tdBin='D:\anlogic\TD_Release_2026.2\bin'
foreach($f in @('td_commands_prompt.exe','td.exe','IpTool.exe','bw.exe','bw_commands_prompt.exe')){
  $p = Join-Path $tdBin $f
  if(Test-Path $p){
    $h=Sha $p; $len=(Get-Item $p).Length
    $exp=$inv.tools_td.$f
    W ("TD " + $f + " sha_match=" + ($h -ieq $exp.sha256) + " bytes_match=" + ($len -eq $exp.bytes))
  } else { W ("TD " + $f + " MISSING") }
}
$lp='D:\anlogic\TD_Release_2026.2\license\Anlogic.lic'
W ('TD license sha_match=' + ((Sha $lp) -ieq $inv.td_license.sha256))
$ms='D:\intelFPGA\18.1\modelsim_ase\win32aloem'
W ('ModelSim vsim.exe=' + (Test-Path (Join-Path $ms 'vsim.exe')) + ' vlog.exe=' + (Test-Path (Join-Path $ms 'vlog.exe')))
$r = (& (Join-Path $ms 'vsim.exe') -version 2>&1 | Out-String); W ('vsim first line: ' + ($r -split "`r?`n" | Where-Object {$_ -ne ''} | Select-Object -First 1))
$r = (& (Join-Path $ms 'vlog.exe') -version 2>&1 | Out-String); W ('vlog first line: ' + ($r -split "`r?`n" | Where-Object {$_ -ne ''} | Select-Object -First 1))
foreach($t in @(@('python',@('--version')),@('gcc',@('--version')),@('git',@('--version')))){
  $src=(Get-Command $t[0] -ErrorAction SilentlyContinue).Source
  $o = (& $src @($t[1]) 2>&1 | Out-String)
  W ($t[0] + ' path=' + $src + ' | first line: ' + ($o -split "`r?`n" | Where-Object {$_ -ne ''} | Select-Object -First 1))
}
$tclSrc=(Get-Command tclsh -ErrorAction SilentlyContinue).Source
$probe = Join-Path $OutDir 'tcl_version_probe_mine.tcl'
[System.IO.File]::WriteAllText($probe, "puts [info patchlevel]`n", (New-Object System.Text.UTF8Encoding($false)))
$o = (& $tclSrc $probe 2>&1 | Out-String)
W ('tclsh path=' + $tclSrc + ' | version: ' + $o.Trim())

W ''
W '== F. host / subst / git / refs =='
$acp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage').ACP
$oemcp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage').OEMCP
W ('PS=' + $PSVersionTable.PSVersion.ToString() + ' edition=' + $PSVersionTable.PSEdition + ' ACP=' + $acp + ' OEMCP=' + $oemcp + ' culture=' + (Get-Culture).Name)
W ('[Console]::OutputEncoding=' + [Console]::OutputEncoding.WebName)
$sub = (& subst 2>&1 | Out-String).Trim()
W ('subst now: ' + $(if($sub -eq ''){'(none)'} else {$sub -replace "`r?`n", ' ; '}))
$gitsrc=(Get-Command git).Source
$head=(& $gitsrc -C $Root rev-parse HEAD 2>&1 | Out-String).Trim()
$dirty=@((& $gitsrc -C $Root status --porcelain 2>&1 | Out-String) -split "`r?`n" | Where-Object {$_.Trim() -ne ''})
W ('git HEAD=' + $head + ' dirty_count=' + $dirty.Count)
$refRoot=Join-Path $env:LOCALAPPDATA 'Temp\opencode'
$refs=@(Get-ChildItem -Path $refRoot -Directory -Filter 'ref_*' -ErrorAction SilentlyContinue | ForEach-Object {$_.Name})
W ('temp ref dirs: ' + ($refs -join ','))

W ''
W '== G. protected tree coverage in raw manifest =='
$prefixes = @{}
foreach($f in $rawJ.files){
  $top = ($f.path -split '/')[0..1] -join '/'
  if(-not $prefixes.ContainsKey($top)){ $prefixes[$top]=0 }
  $prefixes[$top]=$prefixes[$top]+1
}
foreach($k in ($prefixes.Keys | Sort-Object)){ W ('  manifest entries under ' + $k + ' = ' + $prefixes[$k]) }

$lines | Out-File -FilePath (Join-Path $OutDir 'verify_independent_output.txt') -Encoding UTF8
Write-Host ('DONE -> ' + (Join-Path $OutDir 'verify_independent_output.txt'))
