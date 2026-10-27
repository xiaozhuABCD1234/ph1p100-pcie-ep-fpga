param([ValidateSet('before','after')][string]$Phase)
$ErrorActionPreference='Stop'
$root='D:\fpga\repos\ph1p100-pcie-ep-fpga'
$run=Join-Path $root 'workflow\runs\20261027-060708_fpga-parallel-offline-delivery'
$pkg=Join-Path $run 'T04.real-raw10-benchmark'
$ev=Join-Path $run 'test-reports\T04.real-raw10-benchmark'
$manifestPath=Join-Path $pkg 'manifest-r0.json'
$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
$manifestSha=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
$items=@($manifest.files)+@($manifest.external_readonly_sources)
$rows=@(foreach($i in $items){
  $fi=Get-Item -LiteralPath $i.path -Force
  $actual=(Get-FileHash -LiteralPath $i.path -Algorithm SHA256).Hash.ToLowerInvariant()
  [pscustomobject]@{path=$fi.FullName;expected_bytes=$i.bytes;actual_bytes=$fi.Length;expected_sha256=$i.sha256;actual_sha256=$actual;match=($actual -eq $i.sha256.ToLowerInvariant() -and $fi.Length -eq $i.bytes);reparse_point=[bool]($fi.Attributes -band [IO.FileAttributes]::ReparsePoint)}
})
$actualPackage=@(Get-ChildItem -LiteralPath $pkg -File -Recurse|ForEach-Object{$_.FullName})
$expectedPackage=@($manifest.files|ForEach-Object{[IO.Path]::GetFullPath($_.path)})+@($manifestPath)
$listingDifference=@(Compare-Object -ReferenceObject ($expectedPackage|Sort-Object) -DifferenceObject ($actualPackage|Sort-Object))
$binding=Get-Content -LiteralPath $manifest.source_binding_path -Raw|ConvertFrom-Json
$bindingDiff=@(Compare-Object -ReferenceObject @($manifest.external_readonly_sources|ForEach-Object{"$($_.path)|$($_.bytes)|$($_.sha256)"}|Sort-Object) -DifferenceObject @($binding.sources|ForEach-Object{"$($_.path)|$($_.bytes)|$($_.sha256)"}|Sort-Object))
$drift=@()
if($Phase -eq 'after'){
  $before=Get-Content -LiteralPath (Join-Path $ev 'audit-before.json') -Raw|ConvertFrom-Json
  $drift=@(Compare-Object -ReferenceObject @($before.entries|ForEach-Object{"$($_.path)|$($_.actual_bytes)|$($_.actual_sha256)"}|Sort-Object) -DifferenceObject @($rows|ForEach-Object{"$($_.path)|$($_.actual_bytes)|$($_.actual_sha256)"}|Sort-Object))
  if($before.manifest_sha256 -ne $manifestSha){$drift+= 'manifest SHA drift'}
}
$result=[ordered]@{phase=$Phase;utc=[DateTime]::UtcNow.ToString('o');manifest_path=$manifestPath;manifest_sha256=$manifestSha;manifest_expected_sha256='3765d01d6e8c370ba0cdc72a2700f492d01bfe7dda9e956c6b9fbcaeb6af972e';stopped_modifying=$manifest.stopped_modifying;active_commands=$manifest.active_commands;candidate_status=$manifest.status;manifest_package_count=@($manifest.files).Count;source_count=@($manifest.external_readonly_sources).Count;total_count=$rows.Count;actual_package_files_including_manifest=$actualPackage.Count;hash_mismatches=@($rows|Where-Object{-not $_.match});package_listing_difference=$listingDifference;source_binding_difference=$bindingDiff;drift=$drift;entries=$rows}
$result|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $ev "audit-$Phase.json") -Encoding UTF8
if($manifestSha -ne $result.manifest_expected_sha256 -or -not $manifest.stopped_modifying -or $manifest.active_commands -ne 0 -or $rows.Count -ne 151 -or @($manifest.files).Count -ne 132 -or @($manifest.external_readonly_sources).Count -ne 19 -or @($result.hash_mismatches).Count -or $listingDifference.Count -or $bindingDiff.Count -or $drift.Count){throw "AUDIT_FAIL phase=$Phase"}
Write-Output "AUDIT_PASS phase=$Phase package=132 sources=19 total=151 mismatch=0 listing=0 binding=0 drift=0 manifest=$manifestSha status=$($manifest.status) stopped_modifying=$($manifest.stopped_modifying) active_commands=$($manifest.active_commands)"
