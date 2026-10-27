# =============================================================================
# run_build.ps1 -- team-mate helper: filelist preflight + phased TD build
#
# The TD binaries are on the teammate machine; set TD_PROMPT to the
# td_commands_prompt.exe path (or put it on PATH).  This script never
# downloads, never writes Flash, and never opens a cable.
#
#   cd <repo>
#   powershell -File handoff/brd-p1-r2-20261027/build/run_build.ps1
# =============================================================================
param(
    [string]$TdPrompt = "td_commands_prompt.exe",
    [switch]$SkipCwc
)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$pkg = Join-Path $repo "handoff\brd-p1-r2-20261027"
Push-Location $repo
try {
    python (Join-Path $pkg "build\check_filelist.py")
    if ($LASTEXITCODE -ne 0) { throw "filelist preflight failed" }
    python (Join-Path $pkg "build\gen_al.py")
    if ($LASTEXITCODE -ne 0) { throw "gen_al failed" }

    foreach ($step in @("01_synth.tcl", "02_route.tcl", "03_bitgen.tcl")) {
        $log = Join-Path $pkg ("build\build_" + $step.Replace(".tcl", ".log"))
        & $TdPrompt -f (Join-Path $pkg "build\$step") 2>&1 | Tee-Object -FilePath $log
        if ($LASTEXITCODE -ne 0) { throw "$step failed (see $log)" }
    }
    if (-not $SkipCwc) {
        $log = Join-Path $pkg "build\build_04_cwc.log"
        & $TdPrompt -f (Join-Path $pkg "build\04_cwc.tcl") 2>&1 | Tee-Object -FilePath $log
        if ($LASTEXITCODE -ne 0) { throw "04_cwc.tcl failed (see $log)" }
    }
    Write-Output "BRD_BUILD_PHASES_DONE_NO_DOWNLOAD"
} finally {
    Pop-Location
}
