# -*- coding: utf-8 -*-
"""Run the verbatim no-BOM (pre-fix) copy of run_sim.ps1 in documented form (with -Root .) and capture evidence."""
import subprocess, os

ROOT = r'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道'
EV = ROOT + '/workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r3/neg-replay'
CO = 'workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r3/neg-replay/before-fix-run'
os.makedirs(ROOT + '/' + CO, exist_ok=True)

cmd = ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
       'workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r3/neg-replay/before-fix-run_sim.ps1',
       '-Tb', 'tb_csi_integrity_diff',
       '-OutDir', CO,
       '-TbFiles', 'tb/tb_csi_integrity_diff.v',
       '-Root', '.']
p = subprocess.run(cmd, cwd=ROOT, capture_output=True)
out = p.stdout.decode('gbk', errors='replace')
err = p.stderr.decode('gbk', errors='replace')
open(EV + '/before-fix-run/console-transcript.txt', 'w', encoding='utf-8').write(
    'exit code = %d\n==== stdout ====\n%s\n==== stderr ====\n%s\n' % (p.returncode, out, err))
res = []
for f in ('run.do', 'vsim.log', 'vlog.log', 'commands.log'):
    fp = ROOT + '/' + CO + '/' + f
    res.append('%s exists = %s' % (f, os.path.isfile(fp)))
txt = open(EV + '/before-fix-run-vs.log', 'w', encoding='utf-8')
txt.write('exit code = %d\n' % p.returncode + '\n'.join(res) + '\n')
txt.close()
print('exit code =', p.returncode)
print('\n'.join(res))
print('stderr head:')
print(err[:400])
