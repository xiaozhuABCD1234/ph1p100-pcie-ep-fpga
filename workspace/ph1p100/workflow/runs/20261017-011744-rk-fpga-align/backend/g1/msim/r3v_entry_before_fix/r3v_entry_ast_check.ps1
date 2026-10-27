# r3v entry AST semantic check (new repair instance; round3). ASCII-only.
# For frozen run_sim.ps1 / run_td.ps1 (UTF-8 with BOM) and their byte-identical
# no-BOM copies (pre-fix bytes): parse both under PS5.1 and count *real*
# assignment statements for $doPath / $tclDst. Expected: frozen => 1,
# no-BOM copy => 0 (the statement is merged into the previous Chinese comment
# line because .NET CP936 decoding swallows the dangling lead byte + LF).
$ErrorActionPreference = "Continue"
$here = $PSScriptRoot
$root = (Resolve-Path (Join-Path $here "..\..\..\..\..\..\..")).Path
$nobomDir = Join-Path $env:TEMP "opencode\r3v_nobom"
New-Item -ItemType Directory -Force -Path $nobomDir | Out-Null
$out = Join-Path $here "r3v_entry_ast.txt"
$lines = @()
$lines += ("# r3v entry AST semantic check " + (Get-Date -Format o))

foreach ($n in @('run_sim.ps1', 'run_td.ps1')) {
    $frozen = Join-Path $root ("tools\pcie_integration\" + $n)
    $raw = [System.IO.File]::ReadAllBytes($frozen)
    $hasBom = ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF)
    $nobomBytes = if ($hasBom) { $raw[3..($raw.Length - 1)] } else { $raw }
    $tmp = Join-Path $nobomDir $n
    [System.IO.File]::WriteAllBytes($tmp, $nobomBytes)
    $varName = if ($n -eq 'run_sim.ps1') { '$doPath' } else { '$tclDst' }
    foreach ($case in @(@('frozen(BOM)', $frozen), @('no-BOM(before-fix)', $tmp))) {
        $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($case[1], [ref]$null, [ref]$errs)
        $hits = @($ast.FindAll({
                    param($node)
                    ($node -is [System.Management.Automation.Language.AssignmentStatementAst]) -and
                    ($node.Left.Extent.Text -eq $varName)
                }, $true)).Count
        $lines += ("{0,-12} {1,-20} parse_errors={2} assignment({3})_found={4}" -f `
                $n, $case[0], @($errs).Count, $varName, $hits)
    }
}
$lines | Out-File -Encoding utf8 $out
Get-Content $out
