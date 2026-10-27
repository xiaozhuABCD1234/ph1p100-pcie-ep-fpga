# setup_env.ps1 -- T11.export-arm-sim: rebuild the frozen r0 board candidate tree
# Copies read-only inputs into this task's work root (no source is modified).
# P4 core files come ONLY from T10.p4-core-recon\rtl (SHA-bound to manifest-r0b).
$ErrorActionPreference = "Stop"
$R    = 'D:\fpga\repos\ph1p100-pcie-ep-fpga'
$T11  = Join-Path $R 'workflow\runs\20261027-1604_fpga-sim-baseline-export\T11.export-arm-sim'
$T10  = Join-Path $R 'workflow\runs\20261027-1604_fpga-sim-baseline-export\T10.p4-core-recon'
$BF   = Join-Path $R 'handoff\fpga-sim-only-20261027\inputs\board-filelist'
$BRD  = Join-Path $R 'handoff\fpga-sim-only-20261027\inputs\board'
$OLD  = 'D:\fpga\ph1p100\fpga\csi2\pcie_integration\rtl\common'

foreach ($d in @('rtl\p4','rtl\board','rtl\ref\ep_side\ddr','rtl\ref\common','rtl\int','rtl\b18','rtl\b20','rtl\mem','tb','sim\logs','evidence')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $T11 $d) | Out-Null
}

# 1) P4 core: 14 files, byte-identical to manifest-r0b
Get-ChildItem (Join-Path $T10 'rtl') -Filter *.v | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $T11 ('rtl\p4\' + $_.Name)) -Force
}

# 2) board shell (brd_integrated_top.v deliberately excluded: not part of the sim DUT closure)
$boardFiles = @('a1_raw_crop.v','brd_a1_core_pll.v','brd_board_datapath.v','brd_cam_fe.v',
                'brd_cdc_mailboxes.v','brd_ddr_rd_arb.v','p2_ddr_bridge.v')
foreach ($f in $boardFiles) {
    Copy-Item (Join-Path $BF ('fpga\csi2\src\board_integration\' + $f)) (Join-Path $T11 ('rtl\board\' + $f)) -Force
}

# 3) ddr_frame_pusher (read-only reference RTL) + its two `include files
Copy-Item (Join-Path $BF 'fpga\csi2\pcie_integration\rtl\ep_side\ddr\ddr_frame_pusher.v') (Join-Path $T11 'rtl\ref\ep_side\ddr\ddr_frame_pusher.v') -Force
foreach ($f in @('TLP_FMT_TYPE.v','BDF.v')) {
    Copy-Item (Join-Path $OLD $f) (Join-Path $T11 ('rtl\ref\common\' + $f)) -Force
}

# 4) integrated delivery glue (P4 variants are provided by rtl\p4 instead)
$intFiles = @('aplus_pcie_egress_adapter.v','dual_channel_capture_scheduler.v','frame_good_publish_cancel.v',
              'integrated_delivery_top.v','integrated_input_processing_top.v','raw10_sample_vector_to_packed.v')
foreach ($f in $intFiles) {
    Copy-Item (Join-Path $BF ('fpga\csi2\src\integrated_delivery\' + $f)) (Join-Path $T11 ('rtl\int\' + $f)) -Force
}

# 5) b18 / b20 glue, mem primitive
Copy-Item (Join-Path $BF 'workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b18-b17-b\r0\changed-src\cam_diag_mailbox.v') (Join-Path $T11 'rtl\b18\cam_diag_mailbox.v') -Force
foreach ($f in @('a1_frame_top.v','a1_deflate_core.v','a1_ddr_slot_store.v','a1_ddr_arb2.v')) {
    Copy-Item (Join-Path $BF ('workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b20-a-timing\r0\changed-src\' + $f)) (Join-Path $T11 ('rtl\b20\' + $f)) -Force
}
Copy-Item (Join-Path $BF 'fpga\csi2\src\mem\capture_async_fifo.v') (Join-Path $T11 'rtl\mem\capture_async_fifo.v') -Force

# 6) TB (r0 byte copy; path adaptation happens in sources.f, not in the TB)
Copy-Item (Join-Path $BRD 'workflow\runs\20261027-0726_fpga-board-integration\T11.BRD.P1\sim\tb_brd_g1.v') (Join-Path $T11 'tb\tb_brd_g1.v') -Force

# 7) static sources.f (E7): one entry per manifest file, P4 first
$order = @('rtl\p4','rtl\int','rtl\board','rtl\b18','rtl\b20','rtl\mem','rtl\ref\ep_side\ddr','rtl\ref\common','tb')
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# T11.export-arm-sim static source closure (E7). Paths relative to this sim\ dir.')
$lines.Add('# P4 core entries are byte-identical copies of T10.p4-core-recon\rtl (manifest-r0b).')
foreach ($d in $order) {
    Get-ChildItem (Join-Path $T11 $d) -Filter *.v | Sort-Object Name | ForEach-Object {
        $rel = '..\' + $d.Replace('/','\') + '\' + $_.Name
        $lines.Add($rel)
    }
}
Set-Content -Path (Join-Path $T11 'sim\sources.f') -Value $lines -Encoding ASCII
Write-Output ("SOURCES_F_LINES=" + ($lines.Count - 2))

# 8) closure SHA + P4 binding check
$rows = New-Object System.Collections.Generic.List[string]
$rows.Add('relpath,sha256,bytes')
Get-ChildItem $T11 -Recurse -File | Where-Object { $_.FullName -notmatch '\\evidence\\' -and $_.FullName -notmatch '\\logs\\' -and $_.Name -ne 'closure-sha.csv' } | Sort-Object FullName | ForEach-Object {
    $rel = $_.FullName.Substring($T11.Length + 1).Replace('\','/')
    $rows.Add(('{0},{1},{2}' -f $rel, (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.Length))
}
Set-Content -Path (Join-Path $T11 'evidence\closure-sha.csv') -Value $rows -Encoding ASCII

$man = Get-Content (Join-Path $T10 'manifest-r0b.json') -Raw | ConvertFrom-Json
$bad = 0; $n = 0
foreach ($f in $man.files) {
    if ($f.path -notmatch '^rtl\\') { continue }
    $p = Join-Path $T11 ('rtl\p4\' + (Split-Path $f.path -Leaf))
    $h = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower()
    $n++
    if ($h -ne $f.sha256.ToLower()) { Write-Output ("P4_SHA_MISMATCH " + $f.path + " " + $h + " != " + $f.sha256); $bad++ }
}
Write-Output ("P4_FILES_CHECKED=$n P4_SHA_MISMATCH=$bad")
if ($bad -eq 0) { Write-Output 'P4_BINDING=OK' } else { Write-Output 'P4_BINDING=FAIL' }
