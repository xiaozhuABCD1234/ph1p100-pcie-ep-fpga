$ErrorActionPreference = "Continue"
try {
    $doPath = $null
    [System.IO.File]::WriteAllLines($doPath, @("run -all", "quit -f"))
    $doCheck = [System.IO.File]::ReadAllText($doPath)
    if ($doCheck -notmatch "run -all") { throw "run.do write failed: $doCheck" }
    Write-Host "REACHED-AFTER"
} finally { Write-Host "FINALLY-RAN" }
Write-Host "SCRIPT-END"
