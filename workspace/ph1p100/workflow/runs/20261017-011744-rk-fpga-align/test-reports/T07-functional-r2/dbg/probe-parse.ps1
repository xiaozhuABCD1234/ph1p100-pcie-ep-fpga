# probe-parse.ps1 - report how PowerShell decodes/parses a target script file
param([Parameter(Mandatory=$true)][string]$Target)
$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Target, [ref]$t, [ref]$e)
$found = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'WriteAllLines' }, $true)
"PSVersion        = $($PSVersionTable.PSVersion)"
"Default ANSI cp  = $([System.Text.Encoding]::Default.CodePage)"
"Console Input cp = $([Console]::InputEncoding.CodePage)"
"Console Output cp= $([Console]::OutputEncoding.CodePage)"
"WriteAllLines at parse line = $($found[0].Extent.StartLineNumber)"
"parse errors     = $($e.Count)"
