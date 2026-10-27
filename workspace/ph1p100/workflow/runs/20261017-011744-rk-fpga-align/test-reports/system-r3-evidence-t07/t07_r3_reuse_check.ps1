# t07_r3_reuse_check.ps1 - T07 r3 system-dimension reuse-conditions verification
# (ASCII only on purpose: PowerShell 5.1 decodes BOM-less .ps1 as ANSI.)
# 1) full 232-entry SHA verification of the r3 manifest against disk
# 2) unchanged-evidence checks vs r0/r2 recorded hashes (RTL / bit / DB / reports / RK patch)
# 3) tool-only proof: newest mtime per manifest section vs the r2 freeze cutoff
# 4) BOM fix byte-identity: stripped-BOM SHA of run_sim.ps1 / run_td.ps1 vs r0 values
param(
    [string]$Root = "",
    [string]$RunDir = "workflow/runs/20261017-011744-rk-fpga-align",
    [string]$Cutoff = "2026-10-17 06:04:56"
)
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrEmpty($Root)) { $Root = (Get-Location).Path }
$manifestPath = Join-Path $Root "$RunDir/backend/candidate-manifest.json"
$manifestSha = (Get-FileHash $manifestPath -Algorithm SHA256).Hash
$m = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

# ---- expected values recorded at r0 (manifest) / r2 (onsite re-hash) ----
$exp = @{}
# RK patch inputs: identical to the r0-verified byte set (verified again at r2)
$rk0 = @{
 "backend/patches/apply-check-stat.txt"="ce0963708218376d85e83c12a186a85e3ef1647522f4e3e872cc57d330c69247";
 "backend/patches/rka1-driver.patch"="780d45745a7532cc0d16ded8ed9e7eb4615aecef2e54ac8799fd52422d6b380a";
 "backend/rk-driver-src/.gitignore"="7f034b84cac4fab1de20b5f3e90e8a43b8a1c4c72a0c61a81ae204b64af38beb";
 "backend/rk-driver-src/Makefile"="08d4a055960137dc5d5a35230c2bf0f1abc0c5e104189a58ef63def202ebd22a";
 "backend/rk-driver-src/README.md"="9ccde4574f0176384ed0389372a09551fb1672f18f3a8992cc27e618e302f060";
 "backend/rk-driver-src/app/rs/.cargo/config.toml"="87d22f3f408eaeec568184a56c860608674082acafa5b0b7a900f1dac1dc1145";
 "backend/rk-driver-src/app/rs/Cargo.lock"="c740afa544ae0a445e4bdbb924c6fddd26f00d0387d65556277500f9bfba102a";
 "backend/rk-driver-src/app/rs/Cargo.toml"="0c4f675c493528123b969da28cf24daf03d923c0760249d7cfcbd571fd227dd8";
 "backend/rk-driver-src/app/rs/src/bin/cam_grab.rs"="4d08566e61a6b29c46ad2a009bcdde31f2e9950cfb6331c2a8494ec3a69a7a53";
 "backend/rk-driver-src/app/rs/src/bin/frame_grab.rs"="f6d27bcd56388ce029260ed0016378f7f0416a3dc7be21d6243852e70891d1f3";
 "backend/rk-driver-src/app/rs/src/bin/link_ctl.rs"="c41a39e72a40c419bba26aa3a7e3060184fecdfb335bfba04d3ea9e34a1aff68";
 "backend/rk-driver-src/app/rs/src/bin/pci_bar.rs"="47f75260ada9b5c72f46cf7e81865481d64a3b1ccb8298586b3e3d65a2e7d78c";
 "backend/rk-driver-src/app/rs/src/bin/pcie_check.rs"="b9287a94b6a865560af1343e2f3c4b2add6bc387666f48a98b5a772ec38ed882";
 "backend/rk-driver-src/app/rs/src/getopt.rs"="ce96fcf9bdf83a651c894dc2f17f80e35c875ea94ff8f18108a68858c0ce89f8";
 "backend/rk-driver-src/app/rs/src/ioctl.rs"="de54b68d315e7c6910c172a5f1e282e6ddb48676b3ebc699ad03571ede0193b6";
 "backend/rk-driver-src/app/rs/src/lib.rs"="2c38fd8a65ec0b9d78ffc0eabfc3547aa231634766f7f0dae5c2c1a11a178cf3";
 "backend/rk-driver-src/app/rs/src/parse.rs"="5b05c5964f2ea5fcfccd06945a0e6b750bf30abe48e627df52196eeb2034d8cd";
 "backend/rk-driver-src/app/rs/src/rka1.rs"="3b457e387319c918cb7b0f5ea469c2fd692bc54bc81f8f09b2f8875836f5d558";
 "backend/rk-driver-src/app/rs/src/sys.rs"="8226c532c929eb13c44de65807e4ef7925133ee170454797e038e83beef1bcb9";
 "backend/rk-driver-src/include/anlogic_pci_ioctl.h"="f43f637c27d7d805d3146e96a7364280986d80b3e7e26e78a8c6fc322d148246";
 "backend/rk-driver-src/src/anlogic_pci.h"="6af3a2a732b62ebb5664f7a53ac9d45c48d4dd457dd6bab2bf3e004826ded9fb";
 "backend/rk-driver-src/src/anlogic_pci_chrdev.c"="f9a04ecfb991850747544beb4545454d8810d1a03c1f1171df83f05d6696fdce";
 "backend/rk-driver-src/src/anlogic_pci_ctrl.c"="f6962abbb411f21e433861f35ded2f8630861d566027a0c00401c2bbcd167d89";
 "backend/rk-driver-src/src/anlogic_pci_frame.c"="f48757a5291df1280040803febc4876d203f83f44e4b0df14faac9265329cd8a";
 "backend/rk-driver-src/src/anlogic_pci_hw.c"="1b075d4df7c5a1cdb4dafea6b6895f36a2102a2096a9f2495568c96b8dd9787d";
 "backend/rk-driver-src/src/anlogic_pci_link.c"="9b35da75debe5687722ff963b2f8ee817fd881926e1c6b3df7b0c3a5081bfc77";
 "backend/rk-driver-src/src/anlogic_pci_main.c"="c79f1ddb0e492504cc5152a2361865de6ab5d6533ebb4bf46f90d14d433c445c";
 "backend/rk-driver-src/src/anlogic_pci_rka1.c"="105791ecf34a47c4b0c7478fde7e9ac0d2d712a12b235eb14cf82994a23f1e7a"
}
# key build artifacts (full, on-site re-hash at r2)
$exp["backend/candidate/prj/ph1p_pcie_integration_Runs/best_result/ph1p_pcie_integration.bit"]="0943cb36feeb873decc6ea5aae1c2777b3ab4881ebe2954b43bee040ceb38b0a"
$exp["backend/candidate/prj/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration.bit"]="0943cb36feeb873decc6ea5aae1c2777b3ab4881ebe2954b43bee040ceb38b0a"
$exp["backend/candidate/prj/ph1p_pcie_integration_Runs/phy_1/final_timing.rpt"]="ada43e464b98d4bdae2b8ff008790c307c4fc3acf5da529c4035daa1a696c6c4"
$exp["backend/candidate/prj/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration_pr.db"]="692791c6ac2cbd89c82cb10b48b44dc6529d7aa11893bbb713a9abf32dad2efd"
$exp["backend/candidate/prj/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration_place.db"]="510b51877ce3f20942660f7210711a4bec0458602caaa2f02b5396344d48cb87"
$exp["backend/candidate/prj/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration_chk.timing"]="eed5b46fe79ff62b68036edee0faef1d40fbf6b5348e8937371c8157ce2a34e2"
# interface / core RTL (full values recorded at r0, re-confirmed identical at r2)
$exp["fpga/csi2/pcie_integration/rtl/ep_side/img/ep_bar_win.v"]="a3b6b57d60124409dcc1b3b9ce0afb122c3ac4d6aa89d583e19738f9dfd0cf30"
$exp["fpga/csi2/pcie_integration/rtl/ep_side/pcie_ep_engine.v"]="bf59991a8bca3f8b030c47369930be2580db380e185a47dadc0ec68dda006401"
$exp["fpga/csi2/pcie_integration/rtl/ep_side/cam/mipi_csi2_rx_ph1p_checked.v"]="60ed7770442e159f02b5b1ba51ea70e9048e3ea4fc5330e0d345e5369745f9ab"
$exp["fpga/csi2/pcie_integration/rtl/checked/csi_rx_10bit_unpack_checked.v"]="9b5421c55b0f09871f8a939fb3381d4c7d5726286b30f9d5450cc09404065a12"
# files changed in round1/round2 (16-char prefixes recorded from the r2 manifest on site)
$pref = @{
 "fpga/csi2/pcie_integration/rtl/checked/crc16_upd4.v"="20520d044773247b";
 "fpga/csi2/pcie_integration/rtl/checked/csi_rx_packet_integrity.v"="50b4c77be684f078";
 "fpga/csi2/pcie_integration/rtl/ep_side/ddr/cam_ddr_writer.v"="0207c111e4022e6a";
 "fpga/csi2/pcie_integration/rtl/ep_side/ddr/ddr_frame_pusher.v"="e0dd673cd19dd09c";
 "fpga/csi2/pcie_integration/rtl/ep_side/ph1p_pcie_ep_top.v"="7e90de202934f23c"
}

# ---- 1) full verification ----
$sections = @("production_inputs","build_scripts","test_inputs","rk_patch_inputs","build_artifacts")
$bad = @(); $checked = 0; $maxMtime = @{}
foreach ($sec in $sections) {
    $base = "root"; if ($m.path_base -and ($m.path_base.$sec -match "run")) { $base = "run" }
    $mx = [datetime]"2000-01-01"
    foreach ($e in $m.$sec) {
        $p = if ($base -eq "run") { Join-Path $Root (Join-Path $RunDir $e.path) } else { Join-Path $Root $e.path }
        if (-not (Test-Path -LiteralPath $p)) { $bad += "MISSING: $($e.path)"; continue }
        $checked++
        $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower()
        if ($h -ne $e.sha256) { $bad += "SHA_MISMATCH: $($e.path)" }
        $t = (Get-Item -LiteralPath $p).LastWriteTime
        if ($t -gt $mx) { $mx = $t }
    }
    $maxMtime[$sec] = $mx.ToString("yyyy-MM-dd HH:mm:ss")
}

# ---- 2) unchanged-evidence checks ----
$reuse = @()
foreach ($k in $rk0.Keys) {
    $e = $m.rk_patch_inputs | Where-Object { $_.path -eq $k }
    if (-not $e) { $reuse += "RK_MISSING: $k" } elseif ($e.sha256 -ne $rk0[$k]) { $reuse += "RK_CHANGED: $k" }
}
foreach ($k in $exp.Keys) {
    $e = if ($k -like "backend/*") { $m.build_artifacts | Where-Object { $_.path -eq $k } } else { $m.production_inputs | Where-Object { $_.path -eq $k } }
    if (-not $e) { $reuse += "EXP_MISSING: $k" }
    elseif ($e.sha256.ToLower() -ne $exp[$k]) { $reuse += "CHANGED: $k" }
}
foreach ($k in $pref.Keys) {
    $e = $m.production_inputs | Where-Object { $_.path -eq $k }
    if (-not $e) { $reuse += "PREF_MISSING: $k" }
    elseif ($e.sha256.Substring(0,16) -ne $pref[$k]) { $reuse += "PREFIX_CHANGED: $k (r3=" + $e.sha256.Substring(0,16) + ")" }
}

# ---- 3) tool-only proof: newest mtime per section vs cutoff ----
$cut = [datetime]$Cutoff
$late = @()
foreach ($sec in $sections) {
    if ([datetime]$maxMtime[$sec] -gt $cut -and $sec -ne "build_scripts") { $late += "$sec max_mtime=$($maxMtime[$sec])" }
}

# ---- 4) BOM fix byte-identity ----
$bomChecks = @()
foreach ($pair in @(@("tools/pcie_integration/run_sim.ps1","33399210c389818a8601b2710ff08fc1b46312976b35d6fb9a0de1b50674229e"), @("tools/pcie_integration/run_td.ps1","760c5524c3dddf1627d32d0d323a3a48cd727740d87091d173253c75a77fed0f"))) {
    $p = Join-Path $Root $pair[0]
    $bytes = [System.IO.File]::ReadAllBytes($p)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $sha = New-Object System.Security.Cryptography.SHA256Managed
    if ($hasBom) { $stripped = New-Object byte[] ($bytes.Length - 3); [Array]::Copy($bytes, 3, $stripped, 0, $bytes.Length - 3) } else { $stripped = $bytes }
    $hs = ([System.BitConverter]::ToString($sha.ComputeHash($stripped)) -replace '-','').ToLower()
    $bomChecks += [pscustomobject]@{ path=$pair[0]; has_bom=$hasBom; size=$bytes.Length; stripped_sha256=$hs; equals_r0=($hs -eq $pair[1]) }
}

$out = [pscustomobject]@{
    manifest_sha256 = $manifestSha
    round = $m.round; schema = $m.schema
    checked = $checked; problems = $bad
    section_max_mtime = $maxMtime
    cutoff = $Cutoff
    sections_later_than_cutoff_except_build_scripts = $late
    reuse_problems = $reuse
    bom_checks = $bomChecks
}
$outPath = Join-Path $PSScriptRoot "r3-reuse-check-result.json"
$out | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $outPath -Encoding UTF8
Write-Output ("checked=$checked problems=" + $bad.Count + " reuse_problems=" + $reuse.Count + " late_sections=" + $late.Count)
$bad | ForEach-Object { Write-Output $_ }
$reuse | ForEach-Object { Write-Output $_ }
Write-Output ("section_max_mtime: " + ($maxMtime.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } | Out-String))
$bomChecks | ForEach-Object { Write-Output ("BOM: " + $_.path + " has_bom=" + $_.has_bom + " size=" + $_.size + " equals_r0=" + $_.equals_r0) }
Write-Output ("RESULT_JSON=" + $outPath)
