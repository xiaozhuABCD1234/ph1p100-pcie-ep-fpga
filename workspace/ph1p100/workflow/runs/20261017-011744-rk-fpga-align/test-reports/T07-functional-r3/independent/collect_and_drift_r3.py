# -*- coding: utf-8 -*-
"""Collect markers of my default-entry runs + drift check (before vs after snapshot) for the r3 report."""
import json, os

ROOT = r'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道'
EV = ROOT + '/workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r3'


def read_text(p):
    raw = open(p, 'rb').read()
    if raw[:2] in (b'\xff\xfe', b'\xfe\xff'):
        return raw.decode('utf-16', errors='replace')
    if raw[:3] == b'\xef\xbb\xbf':
        return raw.decode('utf-8-sig', errors='replace')
    return raw.decode('utf-8', errors='replace')


idx = []
for run in ('tb_csi_integrity_diff', 'tb_csi_checked', 'tb_ddr_frame_pusher_rka1', 'tb_ep_bar_win_rka1', 'tb_ddr_wr_arb'):
    d = EV + '/msim-default/' + run
    vlog = read_text(d + '/vlog.log').splitlines()
    vsim = read_text(d + '/vsim.log').splitlines()
    cmds = read_text(d + '/commands.log').splitlines()
    errs = [l.strip() for l in vlog if 'Errors:' in l]
    marks = [l.strip() for l in vsim if 'ALL PASS' in l or 'FAIL' in l or 'mismatches =' in l]
    c = [l for l in cmds if l.startswith('cmd /c') or l.startswith('vsim exit')]
    idx.append({'run': run, 'vlog_errors': errs[-1] if errs else None,
                'vsim_markers': marks[-3:], 'cmd_lines': c,
                'run_do': os.path.isfile(d + '/run.do'), 'vsim_log': os.path.isfile(d + '/vsim.log')})
json.dump(idx, open(EV + '/independent/evidence_index.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
for e in idx:
    print('##', e['run'])
    print('   vlog:', e['vlog_errors'], '| run.do:', e['run_do'], '| cmd:', e['cmd_lines'][-1] if e['cmd_lines'] else None)
    for m in e['vsim_markers']:
        print('   vsim:', m)

# drift check
b = json.load(open(EV + '/independent/input_snapshot_before.json', encoding='utf-8'))['files']
a = json.load(open(EV + '/independent/input_snapshot_after.json', encoding='utf-8'))['files']
drift = []
for k in sorted(set(b) | set(a)):
    sb, sa = b.get(k), a.get(k)
    if isinstance(sb, dict) and isinstance(sa, dict):
        if sb['sha256'] != sa['sha256'] or sb['size'] != sa['size']:
            drift.append({'file': k, 'before': sb, 'after': sa})
    elif sb != sa:
        drift.append({'file': k, 'before': sb, 'after': sa})
json.dump({'files_compared': len(set(b) | set(a)), 'drifted': drift},
          open(EV + '/independent/drift_check.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('\nDRIFT: files=%d drifted=%d' % (len(set(b) | set(a)), len(drift)))
for d in drift:
    print('  ', d)
