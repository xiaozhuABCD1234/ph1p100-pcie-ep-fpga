$ErrorActionPreference='Stop'
$taskOut=$PSScriptRoot
$expected='D:\fpga\ph1p100\workflow\runs\20261026-144617_fpga-chain-detail-review\T10.chain-transform-review'
if((Resolve-Path -LiteralPath $taskOut).Path -ne $expected){throw 'Unexpected task output directory'}
$manifestPath=Join-Path $taskOut 'manifest-r0.json'
if(Test-Path -LiteralPath $manifestPath){throw 'Manifest already exists; never overwrite a frozen manifest'}
$qualified=Get-Content -LiteralPath (Join-Path $taskOut 'recovery-verification.json') -Raw|ConvertFrom-Json
if($qualified.marker -ne 'T10_RECOVERY_QUALIFIED_FOR_FREEZE'){throw 'Recovery not qualified'}
$runlog=Get-Content -LiteralPath (Join-Path $taskOut 'recovery-check-native-run.json') -Raw|ConvertFrom-Json
if($runlog.exit_code -ne 0 -or $runlog.timed_out){throw 'Recovery check not completed'}
$inputs=Get-Content -LiteralPath (Join-Path $taskOut 'freeze-inputs.json') -Raw|ConvertFrom-Json
$files=[System.Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($entry in $inputs.files){
  $actual=(Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash.ToLower()
  if($actual -ne $entry.sha256){throw "Frozen dependency drift: $($entry.path)"}
  $files[$entry.path]=$entry
}
# Every developer check has completed. No simulator/build/hardware was launched.
$ended=[DateTime]::UtcNow.ToString('o')
$activity=@{task_id='T10.chain-transform-review';round=0;activity_ended_utc=$ended;stopped_modifying=$true;owned_build_sim_hardware_processes=0;pending_worker_operations=0;hardware_actions=0;production_changes=0;actual_repairs=0;resume_authorization='user-feedback-20261026-195235.md';freeze_only_remaining=$true}
$activity|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskOut 'activity-ended-r0.json') -Encoding utf8
foreach($file in (Get-ChildItem -LiteralPath $taskOut -File -Recurse)){
  if($file.FullName -eq $manifestPath){continue}
  if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Unexpected task file reparse point'}
  $files[$file.FullName]=@{path=$file.FullName;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLower();size=$file.Length;role='T10_frozen_review_artifact_or_control'}
}
$manifest=@{schema_version=1;task_id='T10.chain-transform-review';task_ids=@('T10.chain-transform-review');round=0;status='ready_for_test';purpose='read-only transform/codec audit, not new DUT candidate';project_root='D:\fpga\ph1p100';task_output_dir=$taskOut;activity_ended_utc=$ended;development_modification_stopped=$true;frozen_utc=[DateTime]::UtcNow.ToString('o');actual_repairs=0;baseline_manifest_path='D:\fpga\ph1p100\workflow\runs\20261026-144617_fpga-chain-detail-review\baseline\source-manifest.json';recovery_authorization_path=(Join-Path $taskOut 'controls\user-feedback-20261026-195235.md');independent_acceptance=$false;files=@($files.Values|Sort-Object path)}
$manifest|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Output "T10_MANIFEST_FROZEN files=$($files.Count)"
Write-Output "manifest_path=$manifestPath"
Write-Output "manifest_sha256=$((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLower())"
