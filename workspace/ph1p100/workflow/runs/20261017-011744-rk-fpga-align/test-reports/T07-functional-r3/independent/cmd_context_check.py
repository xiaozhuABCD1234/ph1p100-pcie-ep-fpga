# -*- coding: utf-8 -*-
"""cmd.exe-context spot check: run the frozen entry via cmd (shell=True) for one TB; capture evidence."""
import subprocess, os

ROOT = r'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道'
EV = ROOT + '/workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r3'
CO = 'workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r3/msim-default/cmd-context'
os.makedirs(ROOT + '/' + CO, exist_ok=True)

c = ('powershell -NoProfile -ExecutionPolicy Bypass -File tools/pcie_integration/run_sim.ps1 '
     '-Tb tb_ddr_wr_arb -OutDir ' + CO + ' -TbFiles tb/tb_ddr_wr_arb_peer.v')
p = subprocess.run(c, shell=True, capture_output=True, cwd=ROOT)
out = p.stdout.decode('gbk', errors='replace')
err = p.stderr.decode('gbk', errors='replace')
open(EV + '/msim-default/cmd-context-console.txt', 'w', encoding='utf-8').write(
    'exit code = %d\n==== stdout (tail) ====\n%s\n==== stderr ====\n%s\n' % (p.returncode, out[-1500:], err[:800]))
print('exit code =', p.returncode)
print('run.do  exists =', os.path.isfile(ROOT + '/' + CO + '/run.do'))
print('vsim.log exists =', os.path.isfile(ROOT + '/' + CO + '/vsim.log'))
vl = open(ROOT + '/' + CO + '/vsim.log', encoding='utf-8-sig', errors='replace').read()
print('vsim ALL PASS =', 'ALL PASS' in vl)
vl2 = open(ROOT + '/' + CO + '/vlog.log', encoding='utf-8-sig', errors='replace').read() if os.path.isfile(ROOT + '/' + CO + '/vlog.log') else ''
import re
m = re.findall(r'Errors: \d+, Warnings: \d+', vl2)
print('vlog tail:', m[-1] if m else 'n/a')
