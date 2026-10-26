# verify_scripts_r3.ps1 -- independent r3 checks of the two fixed entry scripts (ASCII-only evidence file)
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..\..")).Path
foreach ($f in 'run_sim.ps1', 'run_td.ps1') {
    $p = Join-Path $root ("tools\pcie_integration\" + $f)
    $b = [System.IO.File]::ReadAllBytes($p)
    $bom = ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
    $hFull = (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $body = New-Object byte[] ($b.Length - 3)
    [Array]::Copy($b, 3, $body, 0, $b.Length - 3)
    $hNoBom = ([BitConverter]::ToString($sha.ComputeHash($body))).Replace('-', '')
    $lf = 0; foreach ($x in $b) { if ($x -eq 10) { $lf++ } }
    $cr = 0; foreach ($x in $b) { if ($x -eq 13) { $cr++ } }
    $gcLines = (Get-Content -LiteralPath $p).Count
    $rawLines = ([System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)).Split("`n").Count
    $tok = $null; $err = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$tok, [ref]$err)
    $astMax = 0
    $wal = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'WriteAllLines' }, $true)
    $assign = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -match '^\$(doPath|tclDst)$' }, $true)
    $lines = [System.IO.File]::ReadAllLines($p, [System.Text.Encoding]::UTF8)
    Write-Output ("== " + $f)
    Write-Output ("   bytes=" + $b.Length + " BOM=" + $bom + " LF=" + $lf + " CR=" + $cr)
    Write-Output ("   sha_full   = " + $hFull)
    Write-Output ("   sha_no_bom = " + $hNoBom)
    Write-Output ("   GetContent_lines=" + $gcLines + "  ReadAllText_lines=" + $rawLines + "  parse_errors=" + $err.Count)
    foreach ($w in $wal) { Write-Output ("   AST WriteAllLines at line " + $w.Extent.StartLineNumber) }
    foreach ($a in $assign) { Write-Output ("   AST assignment " + $a.Left.Extent.Text + " at line " + $a.Extent.StartLineNumber + " : " + $a.Extent.Text.Substring(0, [Math]::Min(70, $a.Extent.Text.Length)).Replace("`n", " ").Replace("`r", "")) }
    if ($f -eq 'run_sim.ps1') { Write-Output ("   L123(raw) = [" + $lines[122] + "]"); Write-Output ("   L124(raw) = [" + $lines[123].Substring(0, [Math]::Min(80, $lines[123].Length)) + "]") }
    if ($f -eq 'run_td.ps1') { Write-Output ("   L57(raw) = [" + $lines[56].Substring(0, [Math]::Min(90, $lines[56].Length)) + "]"); Write-Output ("   L58(raw) = [" + $lines[57] + "]") }
}
