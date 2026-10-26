# -*- coding: utf-8 -*-
"""Minimal probe of the frozen script's exact control flow when $doPath is null (mirrors lines 123-130)."""
import subprocess

EV = r'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r2/independent'
p = EV + '/t9_flow_probe.ps1'
open(p, 'w', encoding='ascii', newline='\n').write(
    '$ErrorActionPreference = "Continue"\n'
    'try {\n'
    '    $doPath = $null\n'
    '    [System.IO.File]::WriteAllLines($doPath, @("run -all", "quit -f"))\n'
    '    $doCheck = [System.IO.File]::ReadAllText($doPath)\n'
    '    if ($doCheck -notmatch "run -all") { throw "run.do write failed: $doCheck" }\n'
    '    Write-Host "REACHED-AFTER"\n'
    '} finally { Write-Host "FINALLY-RAN" }\n'
    'Write-Host "SCRIPT-END"\n')
r = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', p], capture_output=True)
out = r.stdout.decode('cp936', errors='replace')
err = r.stderr.decode('cp936', errors='replace')
res = ('returncode=%d\nSTDOUT:\n%s\nSTDERR:\n%s\n' % (r.returncode, out, err))
open(EV + '/t9_flow_probe_result.txt', 'w', encoding='utf-8').write(res)
print(res[:900])
