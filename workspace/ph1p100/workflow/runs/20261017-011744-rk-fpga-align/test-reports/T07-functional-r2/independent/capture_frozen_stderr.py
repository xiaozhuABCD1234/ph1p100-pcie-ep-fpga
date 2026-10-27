# -*- coding: utf-8 -*-
"""Run the frozen entry once more capturing stderr/stdout with correct cp936 decoding (clean evidence)."""
import subprocess, os

ROOT = r'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道'
OUTDIR = 'workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r2/msim-entry-repro/tb_csi_integrity_diff_v2'
EV = ROOT + '/workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r2/independent/frozen_entry_stderr_decoded.txt'

cmd = ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
       'tools/pcie_integration/run_sim.ps1',
       '-Tb', 'tb_csi_integrity_diff',
       '-OutDir', OUTDIR,
       '-TbFiles', 'tb/tb_csi_integrity_diff.v']
p = subprocess.run(cmd, cwd=ROOT, capture_output=True)
out = p.stdout.decode('gbk', errors='replace')
err = p.stderr.decode('gbk', errors='replace')
with open(EV, 'w', encoding='utf-8') as f:
    f.write('exit code = %d\n' % p.returncode)
    f.write('==== stdout (cp936-decoded) ====\n')
    f.write(out)
    f.write('\n==== stderr (cp936-decoded) ====\n')
    f.write(err)
print('exit', p.returncode, '->', EV)
