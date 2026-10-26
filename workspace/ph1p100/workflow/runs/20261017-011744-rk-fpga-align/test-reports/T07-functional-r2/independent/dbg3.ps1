# dbg3.ps1 -- ASCII-only minimal reproduction of the no-BOM UTF-8 .ps1 decoding defect (evidence file)
$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot
"PSVersion = $($PSVersionTable.PSVersion)"
"ANSI cp   = $([System.Text.Encoding]::Default.CodePage)"

# T1: WriteAllLines argument flavors
try { [System.IO.File]::WriteAllLines($null, @('a')); "WAL null  = OK" }
catch { "WAL null  = " + $_.Exception.GetType().Name + " : " + $_.Exception.Message }
try { [System.IO.File]::WriteAllLines('', @('a')); "WAL empty = OK" }
catch { "WAL empty = " + $_.Exception.GetType().Name + " : " + $_.Exception.Message }
$ctrlPath = "C:\x" + [char]10 + "y"
try { [System.IO.File]::WriteAllLines($ctrlPath, @('a')); "WAL ctrl  = OK" }
catch { "WAL ctrl  = " + $_.Exception.GetType().Name + " : " + $_.Exception.Message }

# T2: minimal no-BOM vs BOM script (Chinese built from char codes, source stays ASCII)
$cnLine = '# ' + [char]0x4E2D + [char]0x6587 + [char]0x53E5 + [char]0x53F7 + [char]0x3002   # "# ChineseSentence."
$lines = @($cnLine, '$x = 42', 'if ($null -eq $x) { "X_IS_NULL" } else { "X=$x" }')
$noBom = Join-Path $here 't1_nobom.ps1'
$withBom = Join-Path $here 't2_bom.ps1'
[System.IO.File]::WriteAllLines($noBom, $lines, (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllLines($withBom, $lines, (New-Object System.Text.UTF8Encoding($true)))
$r1 = (& powershell -NoProfile -ExecutionPolicy Bypass -File $noBom 2>&1 | Out-String).Trim() -replace "`r", '' -replace "`n", ' | '
$r2 = (& powershell -NoProfile -ExecutionPolicy Bypass -File $withBom 2>&1 | Out-String).Trim() -replace "`r", '' -replace "`n", ' | '
"run noBOM  : [" + $r1 + "]"
"run withBOM: [" + $r2 + "]"

# T3: same no-BOM script under chcp 65001
$cmd = 'chcp 65001 >nul & powershell -NoProfile -ExecutionPolicy Bypass -File "' + $noBom + '"'
$r3 = (cmd /c $cmd 2>&1 | Out-String).Trim() -replace "`r", '' -replace "`n", ' | '
"run noBOM chcp65001: [" + $r3 + "]"

# T4: .NET CP936 decode of the frozen runner, dumped for offline diff
$root = (Resolve-Path (Join-Path $here '..\..\..\..\..\..')).Path
$frozen = Join-Path $root 'tools\pcie_integration\run_sim.ps1'
$raw = [System.IO.File]::ReadAllBytes($frozen)
$ansiText = [System.Text.Encoding]::GetEncoding(936).GetString($raw)
$thisText = [System.Text.Encoding]::UTF8.GetString($raw)
"frozen LF count (bytes)     = " + (($raw | Where-Object { $_ -eq 10 }).Count)
"cp936 GetString LF count    = " + (($ansiText.ToCharArray() | Where-Object { [int]$_ -eq 10 }).Count)
"utf8  GetString LF count    = " + (($thisText.ToCharArray() | Where-Object { [int]$_ -eq 10 }).Count)
[System.IO.File]::WriteAllText((Join-Path $here 't4_cp936_view.txt'), $ansiText, (New-Object System.Text.UTF8Encoding($true)))
"dumped cp936 view to t4_cp936_view.txt"

# T5: parser line for frozen, and for the minimal t1
$tok = $null; $err = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($frozen, [ref]$tok, [ref]$err)
$wal = (New-Object System.Collections.ArrayList)
$ast = [System.Management.Automation.Language.Parser]::ParseFile($frozen, [ref]$tok, [ref]$err)
$found = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'WriteAllLines' }, $true)
foreach ($f in $found) { "frozen WriteAllLines AST line = $($f.Extent.StartLineNumber)" }
"frozen Get-Content default count = $((Get-Content $frozen).Count)"
"t1 parser errors = $($err.Count)"
"t1 Get-Content count = $((Get-Content $noBom).Count)  (true = 3)"
