$ErrorActionPreference='Stop'
$run='D:\fpga\ph1p100\workflow\runs\20261026-144617_fpga-chain-detail-review'
$pkg=Join-Path $run 'T11.chain-egress-review'
$out=Join-Path $run 'test-reports\T11.chain-egress-review'
$issues=[System.Collections.Generic.List[string]]::new()
$original=@{}
$reuse=@()
foreach($task in @('T02.chain-input-review','T06.chain-storage-review','T10.chain-transform-review','T11.chain-egress-review')){
  $d=Join-Path $run $task
  $f=Get-Content -LiteralPath (Join-Path $d 'findings.json') -Raw|ConvertFrom-Json
  $findings=if($f -is [array]){$f}else{$f.findings}
  foreach($x in $findings){
    $original[$x.finding_id]=$x
    foreach($key in @('finding_id','severity','kind','claim','evidence_refs','reproduction','impact','recommendation','expected_benefit','tradeoff','validation','disposition')){if(-not $x.$key){$issues.Add('empty finding field '+$x.finding_id+':'+$key)}}
  }
  if($task -ne 'T11.chain-egress-review'){$reuse+=@{task_id=$task;findings=$findings.Count;review_sha256=(Get-FileHash -LiteralPath (Join-Path $d 'review.md') -Algorithm SHA256).Hash.ToLower();report_sha256=(Get-FileHash -LiteralPath (Join-Path $run ('test-reports\'+$task+'-r0-integrated.md')) -Algorithm SHA256).Hash.ToLower();reuse_scope='Same frozen source, parameters, review conclusions and original independent report scope; no old DUT/board PASS promoted; no old witness rerun.'}}
}
$c=Get-Content -LiteralPath (Join-Path $pkg 'chain-findings.json') -Raw|ConvertFrom-Json
$groupMembers=@($c.groups|ForEach-Object{$_.original_finding_ids})
$rootMembers=@($c.root_index|ForEach-Object{$_.original_finding_ids})
$composites=@($c.inherited_composite_summaries|ForEach-Object{$_.original_finding_id})
if($groupMembers.Count -ne $original.Count -or @($groupMembers|Group-Object|Where-Object Count -ne 1).Count -ne 0){$issues.Add('group membership conservation')}
if(@(Compare-Object ($original.Keys|Sort-Object) ($groupMembers|Sort-Object)).Count){$issues.Add('original/group ID set differs')}
if(@(Compare-Object ($original.Keys|Sort-Object) (($rootMembers+$composites)|Sort-Object)).Count){$issues.Add('root/composite ID conservation')}
foreach($g in @($c.groups)+@($c.root_index)){
  foreach($claim in $g.claims){$x=$original[$claim.finding_id]; if(-not $x -or $x.claim -cne $claim.claim -or $x.kind -cne $claim.kind){$issues.Add('claim copy differs '+$claim.finding_id)}}
}
$rootIDs=@($c.root_index.root_id)
foreach($composite in $c.inherited_composite_summaries){foreach($r in $composite.references){if($r -notin $rootIDs){$issues.Add('unknown composite root '+$r)}}}
$sourceMap=Get-Content -LiteralPath (Join-Path $pkg 'source-map.json') -Raw|ConvertFrom-Json
$aliases=0
foreach($task in @('T02.chain-input-review','T06.chain-storage-review','T10.chain-transform-review')){
  $ds=(Get-Content -LiteralPath (Join-Path $run ($task+'\source-map.json')) -Raw|ConvertFrom-Json).sources
  $entries=if($ds -is [array]){@($ds|ForEach-Object{[PSCustomObject]@{Name=$_.source_id;Value=$_}})}else{@($ds.PSObject.Properties)}
  foreach($entry in $entries){$a=$sourceMap.inherited_source_aliases.($task+':'+$entry.Name);$aliases++;if(-not $a -or $a.sha256 -ne $entry.Value.sha256 -or $a.snapshot_path -ne $entry.Value.snapshot_path){$issues.Add('inherited source alias '+$task+':'+$entry.Name)}}
}
$refs=[System.Collections.Generic.List[object]]::new()
function Check-Ref($r,$loc){
  $path=$r.snapshot_path
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){$issues.Add('missing '+$loc);return}
  $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
  $ok=$hash -eq $r.sha256
  if(-not $ok){$issues.Add('hash '+$loc)}
  $range=$true
  if($r.line_start){$count=@(Get-Content -LiteralPath $path).Count;$range=[int]$r.line_start -ge 1 -and [int]$r.line_end -ge [int]$r.line_start -and [int]$r.line_end -le $count;if(-not $range){$issues.Add('range '+$loc)}}
  $refs.Add(@{location=$loc;path=$path;sha256=$hash;hash_ok=$ok;range_ok=$range})
}
$f=(Get-Content -LiteralPath (Join-Path $pkg 'findings.json') -Raw|ConvertFrom-Json).findings
foreach($x in $f){foreach($r in $x.evidence_refs){Check-Ref $r $x.finding_id}}
$checkpoints=Import-Csv -LiteralPath (Join-Path $pkg 'checkpoints.csv')
foreach($cp in $checkpoints){foreach($v in $cp.PSObject.Properties){if(-not $v.Value){$issues.Add('empty checkpoint '+$cp.checkpoint+':'+$v.Name)}};Check-Ref ([PSCustomObject]@{snapshot_path=$cp.source_path;sha256=$cp.source_sha256;line_start=$cp.line_start;line_end=$cp.line_end}) $cp.checkpoint}
foreach($g in $c.groups){foreach($r in $g.evidence_refs){Check-Ref $r $g.group_id}}
$coverage=Import-Csv -LiteralPath (Join-Path $pkg 'coverage.csv')
$map=Get-Content -LiteralPath (Join-Path $pkg 'chain-map.mmd') -Raw
foreach($e in $coverage){foreach($v in $e.PSObject.Properties){if(-not $v.Value){$issues.Add('empty coverage '+$e.edge_id+':'+$v.Name)}};if($map -notmatch [regex]::Escape($e.edge_id)){$issues.Add('graph edge '+$e.edge_id)};Check-Ref ($e.source_binding|ConvertFrom-Json) $e.edge_id}
$opt=Import-Csv -LiteralPath (Join-Path $pkg 'optimization.csv')
$priority=@{correctness=0;observability=1;throughput=2;resources=3};$last=0
foreach($o in $opt){foreach($v in $o.PSObject.Properties){if(-not $v.Value){$issues.Add('empty optimization '+$o.group_id+':'+$v.Name)}};if($priority[$o.priority] -lt $last){$issues.Add('priority order '+$o.group_id)};$last=$priority[$o.priority];foreach($id in $o.root_ids.Split(';')){if($id.Trim() -notin $rootIDs){$issues.Add('unknown optimization root '+$id)}}}
$result=@{status=if($issues.Count){'fail'}else{'pass'};method='Direct PowerShell checks after manual reading of actual JSON schemas; failed Python aggregate not rerun';errors=@($issues);original_findings=$original.Count;thematic_groups=$c.groups.Count;root_entries=$c.root_index.Count;composite_entries=$composites.Count;T11_findings=$f.Count;checkpoints=$checkpoints.Count;edges=$coverage.Count;optimization_rows=$opt.Count;inherited_aliases_checked=$aliases;reference_objects=$refs.Count;references=@($refs);dependencies=$reuse}
$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $out 'manual-structure-and-reuse.json') -Encoding utf8
$result|Select-Object * -ExcludeProperty references|ConvertTo-Json -Depth 5
