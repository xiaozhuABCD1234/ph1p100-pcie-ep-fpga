param([int]$TimeoutSec = 1800)
$ErrorActionPreference = 'Stop'
$run  = "C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261018-1631_runA_fpga_side_readchannel\debug-build"
$repo = "C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\upstream\ph1p100-pcie-ep-fpga"
$root = Join-Path $run 'buildroot'
$out  = Join-Path $run 'prj'
$env:TD_BIN = 'D:\anlogic\TD_Release_2026.2\bin'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$log  = Join-Path $run 'run-build-wrapper.log'
$sw = [Diagnostics.Stopwatch]::StartNew()
"wrapper-start $(Get-Date -Format o) root=$root out=$out" | Out-File $log -Encoding utf8
$ps = Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $repo 'tools\pcie_integration\run_td.ps1'),'-Stage','00_all_debug','-Root',$root,'-OutDir',$out,'-TimeoutMin','30') -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $run 'run-td-stdout.log') -RedirectStandardError (Join-Path $run 'run-td-stderr.log')
$ok = $ps.WaitForExit($TimeoutSec * 1000)
if (-not $ok) {
  & taskkill /PID $ps.Id /T /F 2>&1 | Out-File $log -Append -Encoding utf8
  "wrapper-timeout pid=$($ps.Id)" | Out-File $log -Append -Encoding utf8
}
$sw.Stop()
$code = if ($ok) { $ps.ExitCode } else { 'TIMEOUT' }
"wrapper-end $(Get-Date -Format o) exited=$ok exitcode=$code wall_s=$([math]::Round($sw.Elapsed.TotalSeconds,1))" | Out-File $log -Append -Encoding utf8

