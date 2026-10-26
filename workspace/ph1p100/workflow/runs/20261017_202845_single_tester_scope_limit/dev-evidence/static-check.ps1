$ErrorActionPreference = 'Stop'
$root = 'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道'
$run = Join-Path $root 'workflow/runs/20261017_202845_single_tester_scope_limit'
$evidence = Join-Path $run 'dev-evidence'
$encoding = [Text.UTF8Encoding]::new($false)
$baseline = Get-Content -LiteralPath (Join-Path $run 'config-baseline.json') -Raw | ConvertFrom-Json
$dispatch = Get-Content -LiteralPath (Join-Path $run 'dispatch.json') -Raw | ConvertFrom-Json
$allowed = @($dispatch.write_scope.configuration_paths)
$checks = [Collections.Generic.List[object]]::new()
$commands = [Collections.Generic.List[object]]::new()
function Check([string]$name, [bool]$condition, $detail) {
    $checks.Add([pscustomobject]@{ name=$name; pass=$condition; detail=$detail })
}
function Git([string]$arguments) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = 'git'
    $info.Arguments = $arguments
    $info.WorkingDirectory = $root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $encoding
    $info.StandardErrorEncoding = $encoding
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(60000)) {
        $process.Kill()
        $process.WaitForExit()
        $entry = [pscustomobject]@{ command=('git '+$arguments); cwd=$root; exit_code=124; deadline_seconds=60; stdout=$stdout.Result; stderr=$stderr.Result; timed_out=$true }
        $commands.Add($entry)
        throw 'OWN_GIT_PROCESS_DEADLINE'
    }
    $entry = [pscustomobject]@{ command=('git '+$arguments); cwd=$root; exit_code=$process.ExitCode; deadline_seconds=60; stdout=$stdout.Result; stderr=$stderr.Result; timed_out=$false }
    $commands.Add($entry)
    return $entry
}
function Text([string]$relative) { [IO.File]::ReadAllText((Join-Path $root $relative)) }
function Before([string]$relative) { [IO.File]::ReadAllText((Join-Path (Join-Path $evidence 'before') $relative)) }
function Sha([byte[]]$bytes) { [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-','').ToLowerInvariant() }
$agentBytes = [IO.File]::ReadAllBytes((Join-Path $root 'AGENTS.md'))
$prefix = [byte[]]$agentBytes[0..([int]$baseline.agents_protected_prefix.byte_length-1)]
Check 'AGENTS_PROTECTED_PREFIX_BYTES' ((Sha $prefix) -eq $baseline.agents_protected_prefix.sha256) (Sha $prefix)
$expectedIgnore = (Before '.gitignore').Replace("!/.agents/skills/fpga-dev/`n", "!/.agents/skills/fpga-dev/`n!/.agents/skills/fpga-tester/`n")
Check 'EXACT_GITIGNORE_WHITELIST_ONLY' ((Text '.gitignore') -ceq $expectedIgnore) 'One exact fpga-tester directory exception; no broad ignore change.'
$yaml = Text '.agents/skills/fpga-orchestrator/agents/openai.yaml'
Check 'MINIMAL_EXPLICIT_ONLY_YAML_SCHEMA' ($yaml -ceq "policy:`n  allow_implicit_invocation: false`n") 'Exact mapping, boolean false, no extra fields.'
$linkCount = 0
$missingLinks = [Collections.Generic.List[string]]::new()
$frontmatterErrors = [Collections.Generic.List[string]]::new()
foreach ($relative in $allowed) {
    if ($relative.EndsWith('.md')) {
        $text = Text $relative
        foreach ($match in [regex]::Matches($text, '\[[^\]]+\]\(([^)]+)\)')) {
            $target = $match.Groups[1].Value.Trim('<','>')
            if ($target -match '^(https?://|#|app://|codex://)') { continue }
            $target = ($target -split '#',2)[0]
            if (-not $target) { continue }
            $linkCount++
            $resolved = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent (Join-Path $root $relative)) $target))
            if (-not (Test-Path -LiteralPath $resolved)) { $missingLinks.Add($relative+' -> '+$target) }
        }
        if ($relative.EndsWith('/SKILL.md')) {
            $expectedName = (Split-Path -Leaf (Split-Path -Parent $relative))
            $match = [regex]::Match($text, '\A---\r?\nname: ([^\r\n]+)\r?\ndescription: ([^\r\n]+)\r?\n---\r?\n')
            if (-not $match.Success -or $match.Groups[1].Value -cne $expectedName) { $frontmatterErrors.Add($relative) }
        }
    }
}
Check 'MARKDOWN_RELATIVE_LINKS_EXIST' ($missingLinks.Count -eq 0) @{count=$linkCount; missing=@($missingLinks)}
Check 'SKILL_FRONTMATTER_NAMES' ($frontmatterErrors.Count -eq 0) @($frontmatterErrors)
foreach ($dimension in @('functional','engineering','system')) {
    $relative = '.agents/skills/fpga-tester-'+$dimension+'/SKILL.md'
    $old = Before $relative
    $now = Text $relative
    $oldBody = $old.Substring($old.IndexOf("`n`n", $old.IndexOf('# FPGA')))
    $nowBody = $now.Substring($now.IndexOf("`n`n", $now.IndexOf('# FPGA')))
    $nowBody = [regex]::Replace($nowBody, '\A\r?\n\r?\n> \*\*历史参考，当前不独立派发。\*\*[^\r\n]*', '')
    Check ('LEGACY_BODY_PRESERVED_'+$dimension) ($nowBody -ceq $oldBody) 'Original professional checklist and history retained verbatim after historical notice.'
}
$oldReadme = Before 'workflow/README.md'
$newReadme = Text 'workflow/README.md'
$protectedSections = '(?s)## 1\. 我们要完成什么.*?(?=## 5\. 每次验证绑定到什么)'
Check 'README_G_LAYER_AND_REQUIREMENTS_PRESERVED' ([regex]::Match($oldReadme,$protectedSections).Value -ceq [regex]::Match($newReadme,$protectedSections).Value) 'Sections 1-4 unchanged.'
$oldTail = $oldReadme.Substring($oldReadme.IndexOf('## 5. 每次验证绑定到什么'))
$newTail = $newReadme.Substring($newReadme.IndexOf('## 5. 每次验证绑定到什么'))
$oldTail = [regex]::Replace($oldTail, '(?m)^6\. .*?\r?\n', '')
$newTail = [regex]::Replace($newTail, '(?m)^6\. .*?\r?\n', '')
Check 'README_ONLY_DELIVERY_ROLE_ITEM_CHANGED' ($oldTail -ceq $newTail) 'Section 5 onward unchanged except 5.1 item 6.'
$limits = Text '.agents/skills/fpga-orchestrator/references/work-limits.md'
$required = @('1个主要可验收目标','4个正式工作包','两级','5项语义实现步骤','3条后续主题','30次实际工具调用','15分钟','45分钟','3轮有目标','连续2次','60000ms','60秒','5分钟','30分钟','最多2次','round1—3','TOOL_CONTROL_MISSING','new_information=false','转交重置')
$missingRules = @($required | Where-Object { -not $limits.Contains($_) })
Check 'FROZEN_NUMERIC_AND_STOP_CONTRACT_PRESENT' ($missingRules.Count -eq 0) $missingRules
$activeConflicts = [Collections.Generic.List[string]]::new()
foreach ($relative in $allowed) {
    if (-not $relative.EndsWith('.md') -or $relative -match 'fpga-tester-(functional|engineering|system)/') { continue }
    $text = Text $relative
    foreach ($phrase in @('spawn_three_testers','新三测试','三测试并行','三个新测试','三个独立测试完成','必要时`list_agents`')) {
        if ($text.Contains($phrase)) { $activeConflicts.Add($relative+' : '+$phrase) }
    }
}
Check 'NO_ACTIVE_OLD_DISPATCH_OR_MONITORING' ($activeConflicts.Count -eq 0) @($activeConflicts)
$head = Git 'rev-parse HEAD'
$branch = Git 'branch --show-current'
$status = Git '-c core.quotepath=false status --short'
Check 'HEAD_BASELINE_MATCH' ($head.exit_code -eq 0 -and $head.stdout.Trim() -eq $baseline.head) $head.stdout.Trim()
$currentStatus = @($status.stdout -split '\r?\n' | Where-Object { $_ })
$missingProtectedStatus = @($baseline.protected_dirty_status | Where-Object { $_ -notin $currentStatus })
Check 'PREEXISTING_DIRTY_STATUS_RETAINED' ($missingProtectedStatus.Count -eq 0) $missingProtectedStatus
$quoted = ($allowed | ForEach-Object { '"'+$_+'"' }) -join ' '
$diffCheck = Git ('diff --check -- '+$quoted)
Check 'GIT_DIFF_CHECK' ($diffCheck.exit_code -eq 0) $diffCheck.stdout
$ignoreVerbose = Git 'check-ignore -v --no-index .agents/skills/fpga-tester/SKILL.md'
$ignoreQuiet = Git 'check-ignore -q --no-index .agents/skills/fpga-tester/SKILL.md'
$yamlQuiet = Git 'check-ignore -q --no-index .agents/skills/fpga-orchestrator/agents/openai.yaml'
$visible = Git 'ls-files --others --exclude-standard -- .agents/skills/fpga-tester/SKILL.md .agents/skills/fpga-orchestrator/agents/openai.yaml .agents/skills/fpga-orchestrator/references/work-limits.md'
Check 'NEW_SKILL_PRECISE_RULE' ($ignoreVerbose.stdout.Contains('!/.agents/skills/fpga-tester/')) $ignoreVerbose.stdout
Check 'NEW_SKILL_AND_YAML_NOT_IGNORED' ($ignoreQuiet.exit_code -eq 1 -and $yamlQuiet.exit_code -eq 1) @{skill=$ignoreQuiet.exit_code; yaml=$yamlQuiet.exit_code}
Check 'NEW_INPUTS_TRACKING_VISIBLE' ($visible.exit_code -eq 0 -and @($visible.stdout -split '\r?\n' | Where-Object { $_ }).Count -eq 3) $visible.stdout
$diff = Git ('-c core.quotepath=false diff --no-ext-diff -- '+$quoted)
$diffText = $diff.stdout
foreach ($relative in @('.agents/skills/fpga-tester/SKILL.md','.agents/skills/fpga-orchestrator/references/work-limits.md','.agents/skills/fpga-orchestrator/agents/openai.yaml')) {
    $lines = (Text $relative).TrimEnd("`n").Split("`n")
    $diffText += "diff --git a/$relative b/$relative`nnew file mode 100644`n--- /dev/null`n+++ b/$relative`n@@ -0,0 +1,$($lines.Count) @@`n"
    foreach ($line in $lines) { $diffText += '+'+$line+"`n" }
}
[IO.File]::WriteAllText((Join-Path $run 'candidate.diff'),$diffText,$encoding)
Check 'CANDIDATE_DIFF_GENERATED' ($diff.exit_code -eq 0 -and $diffText.Length -gt 0) 'Tracked config-only diff plus 3 explicit new configuration files.'
$result = [pscustomobject]@{ task_id='CFG-SINGLE-TESTER-LIMITS'; plan_revision=2; observed_at_utc=[DateTime]::UtcNow.ToString('o'); check_scope='developer local static checks only'; commands=@($commands); checks=@($checks); head=$head.stdout.Trim(); branch=$branch.stdout.Trim(); dirty_status=$currentStatus; verdict=$(if (@($checks | Where-Object { -not $_.pass }).Count -eq 0) {'PASS'} else {'FAIL'}) }
[IO.File]::WriteAllText((Join-Path $evidence 'static-check.json'),($result | ConvertTo-Json -Depth 12),$encoding)
$failed = @($checks | Where-Object { -not $_.pass })
Write-Output ($result | Select-Object task_id,plan_revision,verdict,@{n='checks';e={$checks.Count}},@{n='failed';e={$failed}} | ConvertTo-Json -Depth 6)
if ($failed.Count -gt 0) { exit 1 }
