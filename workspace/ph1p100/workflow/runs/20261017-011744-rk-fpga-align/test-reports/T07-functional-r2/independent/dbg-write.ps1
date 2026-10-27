# dbg-write.ps1 -- ASCII-only diagnostic for run_sim.ps1 WriteAllLines failure (evidence file, no frozen input touched)
$ErrorActionPreference = 'Continue'
"PSVersion            = $($PSVersionTable.PSVersion)"
"Default ANSI cp      = $([System.Text.Encoding]::Default.CodePage)"
"Console Output cp    = $([Console]::OutputEncoding.CodePage)"
"Console Input  cp    = $([Console]::InputEncoding.CodePage)"
"chcp                 = $((chcp) 2>&1)"
"Invalid PATH chars   = " + (([int[]][char[]][System.IO.Path]::GetInvalidPathChars()) -join ',')

# project root via relative walk: this file is <root>/workflow/runs/<run>/test-reports/T07-functional-r2/independent/
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..\..")).Path
"root                 = $root"
"root char codes      = " + (([int[]][char[]]$root) -join ',')

$frozen = Join-Path $root "tools\pcie_integration\run_sim.ps1"
"frozen exists        = $(Test-Path $frozen)"

# 1) how does PowerShell itself parse the frozen script?
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($frozen, [ref]$tokens, [ref]$errors)
"parse errors         = $($errors.Count)"
$wals = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'WriteAllLines' }, $true)
foreach ($w in $wals) { "WriteAllLines AST at line = $($w.Extent.StartLineNumber)" }
"script line count (Get-Content) = $((Get-Content $frozen).Count)"

# 2) construct the same paths as the runner
$outDirRel = "workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r2/msim-recheck-dbg/tb_x"
$outDirF = Join-Path $root $outDirRel
New-Item -ItemType Directory -Force -Path $outDirF | Out-Null
$doPath = Join-Path $outDirF "run.do"
"doPath               = $doPath"
$bad = @()
for ($i = 0; $i -lt $doPath.Length; $i++) { $c = [int]$doPath[$i]; if ($c -lt 0x20 -or $c -gt 0x7E) { $bad += ("{0}:{1}" -f $i, $c) } }
"non-ASCII/low chars  = " + ($bad -join ' , ')
try { [int[]][char[]]$doPath | Out-Null; "cast ok" } catch { "cast fail: $($_.Exception.Message)" }

# 3) the exact failing call
try {
    [System.IO.File]::WriteAllLines($doPath, @("run -all", "quit -f"))
    "WriteAllLines(doPath)  = OK"
} catch {
    "WriteAllLines(doPath)  = FAIL"
    "  type    = $($_.Exception.GetType().FullName)"
    "  message = $($_.Exception.Message)"
    if ($_.Exception.InnerException) { "  inner   = $($_.Exception.InnerException.GetType().FullName): $($_.Exception.InnerException.Message)" }
}

# 4) ASCII-path control in approved temp dir
$ascii = "C:\Users\czz\AppData\Local\Temp\opencode\dbg-write-run.do"
try { [System.IO.File]::WriteAllLines($ascii, @("run -all", "quit -f")); "WriteAllLines(ascii)   = OK" }
catch { "WriteAllLines(ascii)   = FAIL: $($_.Exception.Message)" }

# 5) WriteAllText on the same doPath
try { [System.IO.File]::WriteAllText($doPath, "run -all`nquit -f"); "WriteAllText(doPath)   = OK" }
catch { "WriteAllText(doPath)   = FAIL: $($_.Exception.Message)" }

# 6) Set-Content (PowerShell cmdlet) on same doPath
try { Set-Content -Path $doPath -Value @("run -all", "quit -f") -Encoding ASCII; "Set-Content(doPath)    = OK" }
catch { "Set-Content(doPath)    = FAIL: $($_.Exception.Message)" }

# 7) current directory sensitivity: WriteAllLines with relative name after Push-Location to outDirF
Push-Location $outDirF
try { [System.IO.File]::WriteAllLines("run2.do", @("run -all", "quit -f")); "WriteAllLines(rel)     = OK (cwd $(Get-Location))" }
catch { "WriteAllLines(rel)     = FAIL: $($_.Exception.Message)" }
Pop-Location

# 8) GetFullPath behaviour
try { $fp = [System.IO.Path]::GetFullPath($doPath); "GetFullPath(doPath)    = OK: $fp" }
catch { "GetFullPath(doPath)    = FAIL: $($_.Exception.Message)" }
