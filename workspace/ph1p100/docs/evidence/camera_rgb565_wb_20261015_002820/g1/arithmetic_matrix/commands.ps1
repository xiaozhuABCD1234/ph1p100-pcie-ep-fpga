$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath 'D:/TD/work/csi2/_validation/wb565_pipeline_green_20261015_002513'
$modelSimBin = 'D:\intelFPGA\18.1\modelsim_ase\win32aloem'
& "$modelSimBin\vlib.exe" work 2>&1 | Tee-Object -FilePath 'vlib.log'
if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
& "$modelSimBin\vlog.exe" -sv +define+WB_GAIN_PARAMS -work work bayer565_capture.v tb_bayer565_white_balance.sv 2>&1 | Tee-Object -FilePath 'compile.log'
if ($LASTEXITCODE -ne 0) { throw 'vlog failed' }
if ((Get-Content -Raw -LiteralPath 'compile.log') -notmatch 'Errors: 0, Warnings: 0') { throw 'Compiler diagnostics were not clean' }
$vectors = @(
    @{ Name='measured_bl50'; R=2400; B=2062; BL=50 },
    @{ Name='unity_bl0'; R=1024; B=1024; BL=0 },
    @{ Name='unity_bl50'; R=1024; B=1024; BL=50 },
    @{ Name='unity_bl1023'; R=1024; B=1024; BL=1023 },
    @{ Name='maximum_bl50'; R=4096; B=4096; BL=50 },
    @{ Name='asymmetric_bl0'; R=1615; B=1509; BL=0 },
    @{ Name='zero_bl50'; R=0; B=0; BL=50 },
    @{ Name='negative_half_tie_bl50'; R=512; B=512; BL=50 }
)
$summary = foreach ($vector in $vectors) {
    $caseName = $vector.Name
    $caseR = $vector.R
    $caseB = $vector.B
    $caseBl = $vector.BL
    $nativeArguments = @('-c', '-l', "${caseName}_simulator.log", "-gR_GAIN=$caseR", "-gB_GAIN=$caseB", "-gBLACK_LEVEL=$caseBl", 'work.tb_bayer565_white_balance', '-do', 'run -all; quit -f')
    Write-Output "COMMAND vsim.exe $($nativeArguments -join ' ')" | Tee-Object -FilePath "${caseName}_command.txt"
    & "$modelSimBin\vsim.exe" @nativeArguments 2>&1 | Tee-Object -FilePath "${caseName}_run.log"
    if ($LASTEXITCODE -ne 0) { throw "Simulator failed: $caseName" }
    $caseLog = Get-Content -Raw -LiteralPath "${caseName}_run.log"
    $passLine = "WB565_PASS gains=$caseR,$caseB black_level=$caseBl frames=9 outputs=1152 output_checks=1152 stats_checks=13347 identity_checks=2048 raw_levels_R=1024 raw_levels_B=1024 fixture=GBRG"
    if (!$caseLog.Contains($passLine) -or $caseLog.Contains('WB565_FAIL') -or $caseLog -notmatch 'Errors: 0, Warnings: 0') { throw "Missing exact PASS counts or dirty diagnostics: $caseName" }
    [PSCustomObject]@{ Case=$caseName; R=$caseR; B=$caseB; BlackLevel=$caseBl; Frames=9; Outputs=1152; OutputChecks=1152; StatsChecks=13347; IdentityChecks=2048; RLevels=1024; BLevels=1024; Result='PASS' }
}
$summary | Where-Object { $_ -is [PSCustomObject] -and $_.PSObject.Properties.Name -contains 'Case' } | Export-Csv -NoTypeInformation -LiteralPath 'summary.csv'
Get-FileHash -Algorithm SHA256 -LiteralPath 'bayer565_capture.v','tb_bayer565_white_balance.sv','commands.ps1','compile.log','summary.csv' | Select-Object Algorithm,Hash,Path | ConvertTo-Json | Set-Content -LiteralPath 'sha256.json'
Write-Output 'WB565_MATRIX_PASS cases=8 outputs_per_case=1152'
