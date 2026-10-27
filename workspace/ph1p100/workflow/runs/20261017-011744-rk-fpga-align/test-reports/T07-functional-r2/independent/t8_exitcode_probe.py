# -*- coding: utf-8 -*-
"""Isolated exit-code probe: script with a terminated .NET call inside try/finally, run via powershell -File."""
import subprocess, os

EV = r'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r2/independent'
p = EV + '/t8_exitcode_probe.ps1'
open(p, 'w', encoding='ascii', newline='\n').write(
    'try { [System.IO.File]::WriteAllLines($null, @(\'a\')) } finally { Write-Host "FINALLY-RAN" }\n'
    'Write-Host "AFTER-STATEMENT"\n')
r = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', p], capture_output=True)
out = r.stdout.decode('cp936', errors='replace')
err = r.stderr.decode('cp936', errors='replace')
res = 'returncode=%d\nSTDOUT:\n%s\nSTDERR:\n%s\n' % (r.returncode, out, err)
open(EV + '/t8_exitcode_probe_result.txt', 'w', encoding='utf-8').write(res)
print('returncode', r.returncode)
print(out)
print(err[:300])
