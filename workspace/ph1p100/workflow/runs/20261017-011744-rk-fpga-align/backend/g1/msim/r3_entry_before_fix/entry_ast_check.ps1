# 入口修复的语义级校验（round3）：
#  对 run_sim.ps1 / run_td.ps1 分别解析两份内容——
#   (a) 冻结文件本身（UTF-8 with BOM）
#   (b) 同内容但去掉 BOM 的临时副本（= 修复前字节）
#  用 PowerShell AST 检查关键赋值语句（$doPath / $tclDst）是否为**真实语句**（而不是被并进注释的文本）。
# 输出写到本目录的 entry_ast_check.txt。
$here = $PSScriptRoot
$root = (Resolve-Path (Join-Path $here "..\..\..\..\..\..\..")).Path
$lines = @()
$lines += ("# entry AST check ({0})" -f (Get-Date -Format o))
$lines += ("# root = " + $root)

foreach ($n in @('run_sim.ps1', 'run_td.ps1')) {
    $frozen = Join-Path $root ("tools\pcie_integration\" + $n)
    $raw = [System.IO.File]::ReadAllBytes($frozen)
    $hasBom = ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF)
    $tmp = Join-Path $env:TEMP ("r3_nobom_" + $n)
    $nobom = if ($hasBom) { $raw[3..($raw.Length - 1)] } else { $raw }
    [System.IO.File]::WriteAllBytes($tmp, $nobom)

    $varName = if ($n -eq 'run_sim.ps1') { '$doPath' } else { '$tclDst' }
    $rows = @()
    foreach ($case in @(@('frozen(BOM)', $frozen), @('no-BOM(before-fix)', $tmp))) {
        $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($case[1], [ref]$null, [ref]$errs)
        $hits = $ast.FindAll({
                param($node)
                ($node -is [System.Management.Automation.Language.AssignmentStatementAst]) -and
                ($node.Left.Extent.Text -eq $varName)
            }, $true).Count
        $rows += ("  {0,-20} lines={1,-5} parse_errors={2,-3} assignment({3})_found={4}" -f `
                    $case[0], ([System.IO.File]::ReadAllLines($case[1])).Count, $errs.Count, $varName, $hits)
    }
    $lines += ("## {0} (frozen has BOM = {1})" -f $n, $hasBom)
    $lines += $rows
    Remove-Item $tmp -ErrorAction SilentlyContinue
}
$out = Join-Path $here "entry_ast_check.txt"
$lines | Out-File -Encoding utf8 $out
Get-Content $out
