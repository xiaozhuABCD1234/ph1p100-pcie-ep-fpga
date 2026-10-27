# =============================================================================
# td_env.ps1 -- establish the TD drive-letter contract.
#
#   T:  -> the TD run directory (must contain a1_eng_top.v + a1_small_top.sdc)
#   Y:  -> the project root      (must contain upstream/ph1p100-pcie-ep-fpga)
#   X:  is NOT touched here. It is reserved for a TD run directory; simulation
#       scripts use P: for the project root (they used to take X:, which broke
#       the TD project after every simulation run).
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\td\td_env.ps1 `
#       -TdDir "workflow\runs\...\T10.a1-eng-freeze\r10\td"
#
# Add -Force only when you intentionally want to replace a different mapping.
# =============================================================================
param(
    [Parameter(Mandatory = $true)][string]$TdDir,
    [string]$Root = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

if ($Root -eq "") {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}
$TdDir = (Resolve-Path -LiteralPath $TdDir).Path
$Root = (Resolve-Path -LiteralPath $Root).Path

foreach ($name in @("a1_eng_top.v", "a1_small_top.sdc")) {
    if (-not (Test-Path -LiteralPath (Join-Path $TdDir $name))) {
        throw "TD dir is missing ${name}: $TdDir"
    }
}
$rtl = Join-Path $Root "upstream\ph1p100-pcie-ep-fpga\rtl\ep_side\codec\a1_deflate_core.v"
if (-not (Test-Path -LiteralPath $rtl)) {
    throw "project root is missing upstream RTL: $Root"
}

if (-not ("DosDevice" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class DosDevice {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool QueryDosDevice(string name, StringBuilder target, int max);

    public static string Target(string drive) {
        var sb = new StringBuilder(32768);
        if (!QueryDosDevice(drive.TrimEnd('\\'), sb, sb.Capacity)) return null;
        return sb.ToString();
    }
}
'@
}

function Get-SubstTarget([string]$Drive) {
    $target = [DosDevice]::Target($Drive)
    if (-not $target) { return $null }
    if ($target.StartsWith("\??\")) { $target = $target.Substring(4) }
    return $target
}

function Ensure-Map([string]$Drive, [string]$Target) {
    $current = Get-SubstTarget $Drive
    if ($current) {
        if ([string]::Equals($current.TrimEnd("\"), $Target.TrimEnd("\"), [StringComparison]::OrdinalIgnoreCase)) {
            Write-Host ("{0} already -> {1}" -f $Drive, $Target)
            return
        }
        if (-not $Force) {
            throw ("{0} is mapped to {1}, expected {2}. Close the tool using it or pass -Force." -f $Drive, $current, $Target)
        }
        cmd /c "subst $Drive /D" | Out-Null
    }
    cmd /c "subst $Drive `"$Target`"" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "subst $Drive failed (exit $LASTEXITCODE)" }
    $now = Get-SubstTarget $Drive
    if (-not $now) { throw "subst $Drive did not take effect" }
    Write-Host ("{0} -> {1}" -f $Drive, $now)
}

Ensure-Map "T:" $TdDir
Ensure-Map "Y:" $Root

$x = Get-SubstTarget "X:"
if ($x -and [string]::Equals($x.TrimEnd("\"), $Root.TrimEnd("\"), [StringComparison]::OrdinalIgnoreCase)) {
    Write-Warning "X: still maps to the project root (left by an old simulation run). Simulation scripts now use P:; X: is reserved for TD."
}

Write-Host ""
Write-Host "TD environment ready."
Write-Host "  T: = $TdDir"
Write-Host "  Y: = $Root"
