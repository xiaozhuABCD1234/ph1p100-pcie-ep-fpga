# -*- coding: utf-8 -*-
"""Analyze the cp936 view of run_sim.ps1 vs the true UTF-8 text: find merged lines and the fate of $doPath."""
import difflib

ROOT = r'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道'
TRUE_F = ROOT + '/tools/pcie_integration/run_sim.ps1'
VIEW_F = ROOT + '/workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r2/independent/t4_cp936_view.txt'
OUT_F = ROOT + '/workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r2/independent/cp936_view_analysis.txt'

true = open(TRUE_F, encoding='utf-8').read().replace('\r', '')
view = open(VIEW_F, encoding='utf-8-sig').read().replace('\r', '')
tl = true.split('\n')
vl = view.split('\n')
out = []
out.append('true lines=%d  view lines=%d  (LF true=%d view=%d)' % (len(tl), len(vl), true.count('\n'), view.count('\n')))
out.append('--- view lines mentioning doPath/WriteAllLines/vsimCmd/flist/abs.f/cmd /c ---')
for i, l in enumerate(vl, 1):
    if any(k in l for k in ('doPath', 'WriteAllLines', 'vsimCmd', 'cmd /c', 'abs.f', 'ReadAllText')):
        out.append('VIEW %4d: %r' % (i, l[:200]))
out.append('--- opcodes where view differs from true ---')
sm = difflib.SequenceMatcher(a=tl, b=vl, autojunk=False)
for tag, i1, i2, j1, j2 in sm.get_opcodes():
    if tag == 'equal':
        continue
    out.append('== %s true[%d:%d] view[%d:%d]' % (tag, i1, i2, j1, j2))
    for k in range(i1, min(i2, i1 + 6)):
        out.append('  T%4d: %r' % (k + 1, tl[k][:160]))
    for k in range(j1, min(j2, j1 + 6)):
        out.append('  V%4d: %r' % (k + 1, vl[k][:160]))
open(OUT_F, 'w', encoding='utf-8').write('\n'.join(out))
print('written', OUT_F)
