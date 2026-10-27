# make_manifest.ps1 -- freeze the T11.export-arm-sim working set + SHA256
$ErrorActionPreference = "Stop"
$R   = 'D:\fpga\repos\ph1p100-pcie-ep-fpga'
$T11 = Join-Path $R 'workflow\runs\20261027-1604_fpga-sim-baseline-export\T11.export-arm-sim'
$T10 = Join-Path $R 'workflow\runs\20261027-1604_fpga-sim-baseline-export\T10.p4-core-recon'
$BF  = Join-Path $R 'handoff\fpga-sim-only-20261027\inputs'

function Sha256Of($p) { (Get-FileHash $p -Algorithm SHA256).Hash.ToLower() }

# 1) P4 binding check against T10 manifest-r0b
$man = Get-Content (Join-Path $T10 'manifest-r0b.json') -Raw | ConvertFrom-Json
$p4 = @(); $bad = 0
foreach ($f in $man.files) {
    if ($f.path -notmatch '^rtl\\') { continue }
    $name = Split-Path $f.path -Leaf
    $h = Sha256Of (Join-Path $T11 ('rtl\p4\' + $name))
    $ok = ($h -eq $f.sha256.ToLower())
    if (-not $ok) { $bad++ }
    $p4 += [ordered]@{ file = $name; expected_sha256 = $f.sha256.ToLower(); actual_sha256 = $h; match = $ok }
}

# 2) file inventory (everything delivered under the task root except logs/work)
$files = @()
Get-ChildItem $T11 -Recurse -File | Where-Object {
    $_.FullName -notmatch '\\sim\\work\\' -and
    $_.Name -ne 'manifest-r0.json' -and $_.Extension -ne '.wlf' -and $_.Extension -ne '.qdb'
} | Sort-Object FullName | ForEach-Object {
    $files += [ordered]@{
        path   = $_.FullName.Substring($T11.Length + 1).Replace('\','/')
        sha256 = (Sha256Of $_.FullName)
        bytes  = $_.Length
    }
}

$sourcesF = Get-Content (Join-Path $T11 'sim\sources.f') | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' }

$m = [ordered]@{
    task_id      = 'T11.export-arm-sim'
    run_id       = '20261027-1604_fpga-sim-baseline-export'
    round        = '0'
    status       = 'blocked'
    status_note  = 'r0g (round3, final, blocked/SCOPE_CLARIFICATION): T03 70B oracle reproduced byte-exact (78 9c..., BYTE_DIFF=0) with the same store, so the store is not the defect; the export emits each 32B beat MSB-first while store/T03 are LSB-first, and the measured write path is word x128 vs the x32 spec. Both fixes land in the b20 store or the reference pusher (forbidden). See result-r0g.md'
    work_root    = $T11
    simulator    = 'ModelSim ASE 18.1 (vlib/vlog/vsim -c), D:\intelFPGA\18.1\modelsim_ase\win32aloem'
    frozen_at    = (Get-Date -Format 's')
    p4_binding   = [ordered]@{
        manifest_r0b_path   = (Join-Path $T10 'manifest-r0b.json')
        manifest_r0b_sha256 = (Sha256Of (Join-Path $T10 'manifest-r0b.json'))
        files_checked       = $p4.Count
        mismatch            = $bad
        verdict             = $(if ($bad -eq 0) { 'PASS' } else { 'FAIL' })
        files               = $p4
    }
    static_filelist = [ordered]@{
        path    = 'sim/sources.f'
        sha256  = (Sha256Of (Join-Path $T11 'sim\sources.f'))
        entries = @($sourcesF).Count
        note    = 'E7 static filelist; one entry per compiled RTL/TB file'
    }
    witness = [ordered]@{
        log                 = 'evidence/before-witness/before-fix_0_20261027_170306.log'
        tb_sha256           = (Sha256Of (Join-Path $BF 'board\workflow\runs\20261027-0726_fpga-board-integration\T11.BRD.P1\sim\tb_brd_g1.v'))
        tb_source           = 'r0 byte copy (r0 TB, unmodified at witness time)'
        rtl_state           = 'pre-fix: brd_board_datapath.v before the two minimal fixes'
        markers             = @('committed=1','pub=1','marshal=124','arm=0','exported=0','tlp=0','db=0','POS_RESULT=FAIL')
    }
    commands = @(
        'powershell -NoProfile -ExecutionPolicy Bypass -File sim\setup_env.ps1',
        'powershell -NoProfile -ExecutionPolicy Bypass -File sim\run_sim.ps1 -Scen 0 -Tag before-fix',
        'powershell -NoProfile -ExecutionPolicy Bypass -File sim\run_sim.ps1 -Scen 0 -Tag after-fix-nf3'
    )
    files = $files
}
$m | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $T11 'manifest-r0g.json') -Encoding UTF8
Write-Output ("MANIFEST_FILES=" + $files.Count)
Write-Output ("P4_BINDING=" + $m.p4_binding.verdict + " checked=" + $p4.Count + " mismatch=" + $bad)
Write-Output ("SOURCES_F_ENTRIES=" + @($sourcesF).Count)







