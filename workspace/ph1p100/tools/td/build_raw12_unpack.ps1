$ErrorActionPreference = 'Stop'
$repoPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fffffff'
$runPath = Join-Path 'D:\TD\work\csi2\_validation\raw12' ('syn_' + $stamp)
New-Item -ItemType Directory -Path $runPath | Out-Null
$rtlPath = Join-Path $repoPath 'fpga\csi2\rtl\csi2_raw12_unpack.v'
$livePath = 'D:\TD\work\csi2\rtl\csi2_raw12_unpack.v'
New-Item -ItemType Directory -Force -Path (Split-Path $livePath -Parent) | Out-Null
# Refuse to overwrite a changed live source; review differences explicitly.
if ((Test-Path -LiteralPath $livePath) -and
    ((Get-FileHash -LiteralPath $rtlPath).Hash -ne (Get-FileHash -LiteralPath $livePath).Hash)) {
    throw 'Live RAW12 RTL differs; review before synchronization'
}
Copy-Item -LiteralPath $rtlPath -Destination $livePath
Copy-Item -LiteralPath $rtlPath -Destination (Join-Path $runPath 'csi2_raw12_unpack.v')
Copy-Item -LiteralPath (Join-Path $repoPath 'fpga\csi2\constraints\raw12_unpack.sdc') -Destination (Join-Path $runPath 'raw12_unpack.sdc')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'build_raw12_unpack.tcl') -Destination (Join-Path $runPath 'build.tcl')
Push-Location $runPath
try {
    & 'D:\downlaod\bin\td_commands_prompt.exe' ./build.tcl 2>&1 | Tee-Object -FilePath (Join-Path $runPath 'cli.log')
    $tdExitCode = $LASTEXITCODE
} finally { Pop-Location }
if ($tdExitCode -ne 0) { throw "TD exited $tdExitCode; inspect $runPath" }
$cliText = Get-Content -LiteralPath (Join-Path $runPath 'cli.log') -Raw
if ($cliText -notmatch 'RAW12_SYN_COMMANDS_RETURNED_CHECK_LOGS' -or $cliText -match 'RAW12_SYN_TCL_ERROR') {
    throw "TD did not reach the expected marker; inspect $runPath"
}
if (!(Test-Path -LiteralPath (Join-Path $runPath 'raw12_unpack.area'))) {
    throw "Missing area report; inspect $runPath"
}
Write-Output ('RAW12_SYN_EVIDENCE ' + $runPath)
Write-Output ('RTL_SHA256 ' + (Get-FileHash -LiteralPath $rtlPath -Algorithm SHA256).Hash)
# Caller must inspect actual synthesis run log and reports before claiming success.
