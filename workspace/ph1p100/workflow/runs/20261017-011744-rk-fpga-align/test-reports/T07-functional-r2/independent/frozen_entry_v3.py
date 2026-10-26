# -*- coding: utf-8 -*-
"""Final full-capture reproduction of the frozen-entry failure (v3). Saves raw stdout/stderr and inspects the script's own commands.log."""
import subprocess

ROOT = r'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道'
EV = ROOT + '/workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r2/msim-entry-repro'
OUT = 'workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r2/msim-entry-repro/tb_csi_integrity_diff_v3'

cmd = ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
       'tools/pcie_integration/run_sim.ps1',
       '-Tb', 'tb_csi_integrity_diff',
       '-OutDir', OUT,
       '-TbFiles', 'tb/tb_csi_integrity_diff.v']
p = subprocess.run(cmd, cwd=ROOT, capture_output=True)
out = p.stdout.decode('gbk', errors='replace')
err = p.stderr.decode('gbk', errors='replace')
open(EV + '/v3_stdout.txt', 'w', encoding='utf-8').write(out)
open(EV + '/v3_stderr.txt', 'w', encoding='utf-8').write(err)
print('returncode =', p.returncode)
print('stderr error-record count =', err.count('WriteAllLines时发生异常') + err.count('run.do write failed'))
import os
d = ROOT + '/' + OUT
for f in ('commands.log', 'run.do', 'vsim.log'):
    fp = os.path.join(d, f)
    print(f, 'exists =', os.path.isfile(fp))
fl = os.path.join(d, 'commands.log')
if os.path.isfile(fl):
    cb = open(fl, 'rb').read()
    if cb[:2] in (b'\xff\xfe', b'\xfe\xff'):
        ct = cb.decode('utf-16', errors='replace')
    else:
        ct = cb.decode('utf-8', errors='replace')
    print('---- commands.log ----')
    print(ct)
