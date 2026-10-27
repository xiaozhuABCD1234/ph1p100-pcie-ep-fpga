$ErrorActionPreference = 'Stop'
$taskRun = Split-Path -Parent $PSScriptRoot
$taskProbe = Join-Path $PSScriptRoot 'td-probe'
New-Item -ItemType Directory -Path $taskProbe -Force | Out-Null
$taskScript = @'
foreach name {open_project import_device launch_runs wait_run bitgen report_timing_summary create_ip get_ips get_property set_property generate_target} {
 if {[llength [info commands $name]] == 0} {puts stderr "MISSING $name"; exit 1}
 puts "REGISTERED $name"
}
puts "TCL_VERSION [info patchlevel]"
puts "READ_ONLY_CLI_PROBE_OK"
exit 0
'@
[System.IO.File]::WriteAllText((Join-Path $taskProbe 'probe.tcl'), $taskScript, [System.Text.UTF8Encoding]::new($false))
$taskTools = @()
foreach ($taskExe in @('D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe','D:/anlogic/TD_Release_2026.2/bin/td.exe','D:/anlogic/TD_Release_2026.2/bin/IpTool.exe','D:/anlogic/TD_Release_2026.2/bin/bw_commands_prompt.exe','D:/anlogic/TD_Release_2026.2/bin/bw.exe')) {
 $taskInfo = Get-Item -LiteralPath $taskExe
 $taskTools += [ordered]@{path=$taskInfo.FullName;bytes=$taskInfo.Length;sha256=(Get-FileHash -LiteralPath $taskExe -Algorithm SHA256).Hash.ToLower();file_version=$taskInfo.VersionInfo.FileVersion;product_version=$taskInfo.VersionInfo.ProductVersion}
}
$taskCommands = @(Get-Command python,git,iverilog,vvp,verilator,gcc,clang,tclsh -ErrorAction SilentlyContinue | Select-Object Name,Source)
$taskDevices = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.PNPDeviceID -like 'USB*' -and ($_.Name -match 'Anlogic|JTAG|FTDI|UART|Serial|CH34|CH91|USB-Blaster|CP210|USB Serial|USB Converter' -or $_.PNPDeviceID -match 'VID_0403|VID_1A86|VID_10C4') } | Select-Object Name,Status,PNPDeviceID,ConfigManagerErrorCode)
$taskPorts = @(Get-CimInstance Win32_SerialPort | Select-Object DeviceID,Name,PNPDeviceID,Status)
$taskSubstBefore = (& subst 2>&1 | Out-String).Trim()
$taskLetter = @('U','V','W','R','S') | Where-Object { -not (Test-Path -LiteralPath ($_+':/')) -and $taskSubstBefore -notmatch ('(?m)^'+$_+':') } | Select-Object -First 1
if (-not $taskLetter) { throw 'No unused ASCII alias drive found' }
$taskDrive = $taskLetter+':'
$taskAliasRemoved = $false
& subst $taskDrive $taskProbe
if ($LASTEXITCODE -ne 0) { throw 'subst creation failed' }
try {
 Push-Location ($taskDrive+'/')
 try {
  $taskStdout = & 'D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe' './probe.tcl' 2>&1 | Out-String
  $taskExit = $LASTEXITCODE
 } finally { Pop-Location }
 [System.IO.File]::WriteAllText((Join-Path $taskProbe 'stdout.log'),$taskStdout,[System.Text.UTF8Encoding]::new($false))
} finally {
 & subst $taskDrive /D
 $taskAliasRemoved = $LASTEXITCODE -eq 0
}
$taskInventory = [ordered]@{
 recorded_at=(Get-Date).ToString('o');tools=$taskTools;commands=$taskCommands
 cli_probe=[ordered]@{argv=@('D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe','./probe.tcl');cwd_alias=$taskDrive+'/';actual_cwd=$taskProbe;exit_code=$taskExit;marker=($taskStdout -match 'READ_ONLY_CLI_PROBE_OK');log=(Join-Path $taskProbe 'stdout.log');alias_target=$taskProbe;alias_removed=$taskAliasRemoved;scope='command registration and startup banner only; no project/build/IP generation/download'}
 devices=$taskDevices;serial_ports=$taskPorts;subst_before=$taskSubstBefore
 ip_tool_scope='IpTool binary identity inspected only. Prior 6.2.3 APB_GPIO generation success may be reused; previous DDR1333 failure is scoped, not a general CLI blocker. No repeated old IpTool experiment.'
 hardware_scope='PnP/serial enumeration only; no port opened, board identified through JTAG, or download performed; no RK endpoint inferred from any port.'
}
$taskInventory | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'tool-inventory.json') -Encoding utf8
Write-Output ('exit='+$taskExit+' marker='+($taskStdout -match 'READ_ONLY_CLI_PROBE_OK')+' alias_removed='+$taskAliasRemoved+' usb_devices='+$taskDevices.Count+' ports='+$taskPorts.Count)
if ($taskExit -ne 0 -or $taskStdout -notmatch 'READ_ONLY_CLI_PROBE_OK' -or -not $taskAliasRemoved) { exit 1 }
