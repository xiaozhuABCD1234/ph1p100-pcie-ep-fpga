# -*- coding: utf-8 -*-
"""Compare before/after input snapshots -> drift check; then emit a compact evidence index for the report."""
import json, os

ROOT = r'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道'
EV = ROOT + '/workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r2'
b = json.load(open(EV + '/independent/input_snapshot_before.json', encoding='utf-8'))['files']
a = json.load(open(EV + '/independent/input_snapshot_after.json', encoding='utf-8'))['files']
drift = []
for k in sorted(set(b) | set(a)):
    sb = b.get(k, 'MISSING'); sa = a.get(k, 'MISSING')
    if isinstance(sb, dict) and isinstance(sa, dict):
        if sb['sha256'] != sa['sha256'] or sb['size'] != sa['size']:
            drift.append({'file': k, 'before': sb, 'after': sa})
    elif sb != sa:
        drift.append({'file': k, 'before': sb, 'after': sa})
res = {'files_compared': len(set(b) | set(a)), 'drifted': drift}
json.dump(res, open(EV + '/independent/drift_check.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('files compared:', res['files_compared'], ' drifted:', len(drift))
for d in drift:
    print('DRIFT', d)

# evidence index: key markers from my runs
idx = []
def tail(path, n=3):
    lines = open(path, encoding='utf-8', errors='replace').read().splitlines()
    return [l.strip() for l in lines[-n:]]
for run in ('tb_csi_integrity_diff', 'tb_csi_checked', 'tb_ddr_frame_pusher_rka1', 'tb_ep_bar_win_rka1', 'tb_ddr_wr_arb'):
    d = EV + '/msim-utf8/' + run
    vlog = tail(d + '/vlog.log', 2)
    vsim = tail(d + '/vsim.log', 8)
    idx.append({'run': run, 'vlog_tail': vlog, 'vsim_tail': vsim})
json.dump(idx, open(EV + '/independent/evidence_index.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
for e in idx:
    print('\n##', e['run'])
    print('  vlog:', e['vlog_tail'])
    print('  vsim:', e['vsim_tail'][:4])
