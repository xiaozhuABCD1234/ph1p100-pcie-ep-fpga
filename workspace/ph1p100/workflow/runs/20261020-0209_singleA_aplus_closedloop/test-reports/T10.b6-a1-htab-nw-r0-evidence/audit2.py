import json, hashlib, pathlib, re, subprocess

root = pathlib.Path(r'D:\fpga\ph1p100')
pkg = root/'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw'
ev = root/'workflow/runs/20261020-0209_singleA_aplus_closedloop/test-reports/T10.b6-a1-htab-nw-r0-evidence'
td = pkg/'r0/td'
b5 = root/'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b5-a1-htab-pipe/r0'
b5td = b5/'td'

def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''): h.update(b)
    return h.hexdigest()

print('=== 1. tester P1 cycles from own stats STAT line ===')
for name in ['micro8x2', 'mid64x8', 'full_grad']:
    p = ev/'sim-rerun'/(name+'.stats')
    txt = p.read_text(errors='replace').strip() if p.exists() else '<missing>'
    m = re.search(r'cycles=(\d+)', txt)
    print('%-10s cycles=%s | %s' % (name, m.group(1) if m else 'NONE', txt[:170]))

print('\n=== 2. P2 arithmetic cross-check ===')
pj = json.loads((ev/'sim-rerun/tester-sim-run.json').read_text())
c = pj['p2']['comp']
print('comp run_cycles=%s matches=%s done=%s out_last=%s timeout=%s bp=%s gap=%s in_bytes=%s' % (
    c['run_cycles'], c['stats'].get('stat_matches'), c['stats'].get('done'), c['stats'].get('out_last'),
    c['stats'].get('timeout_hit'), c['stats'].get('bp'), c['stats'].get('gap'), c['stats'].get('in_bytes')))
print('comp 355261 + matches 19200 =', 355261 + 19200, '(r5 claim 374461)')
print('rand run_cycles=%s sha=%s' % (pj['p2']['rand']['run_cycles'], pj['p2']['rand']['output_sha256']))
print('comp identical_to_dev_stream=%s zlib_ok=%s mismatch=%s' % (
    c['identical_to_dev_stream'], c['zlib_ok'], c['zlib_mismatch']))

print('\n=== 3. routed_timing.rpt path blocks mentioning htab_p3v / bm_b ===')
txt = (td/'routed_timing.rpt').read_text(errors='replace')
lines = txt.splitlines()
blocks = []
cur = None
for ln in lines:
    s = ln.strip()
    if s.startswith('Begin Point'):
        cur = {'begin': s, 'end': '', 'type': '', 'slack': '', 'required': '', 'arrival': ''}
        blocks.append(cur)
    elif cur is not None:
        if s.startswith('End Point'): cur['end'] = s
        elif s.startswith('Check Type'): cur['type'] = s
        elif s.startswith('Slack'): cur['slack'] = s
        elif s.startswith('Required'): cur['required'] = s
        elif s.startswith('Arrival'): cur['arrival'] = s
hit = [b for b in blocks if 'htab_p3v' in b['begin'] + b['end'] or 'bm_b' in b['begin'] + b['end']]
print('total path blocks parsed:', len(blocks), '| blocks touching htab_p3v/bm_b:', len(hit))
for b in hit:
    print('  BEGIN', b['begin'][:150])
    print('    END', b['end'][:150])
    print('    TYPE', b['type'], '|', b['slack'], '|', b['required'], '|', b['arrival'])
pairs = [(b['begin'], b['end']) for b in blocks if ('htab_p3v' in b['begin'] and 'bm_b' in b['end'])]
print('htab_p3v -> bm_b blocks:', len(pairs))
print('blocks with end containing bm_b.addrb:', sum(1 for b in blocks if 'bm_b' in b['end'] and 'addrb' in b['end']))

print('\n=== 4. rtl diff scope: b6 core vs r5 core and vs r4 upstream ===')
import difflib
a = (b5/'changed-src/a1_deflate_core.v').read_text(errors='replace').splitlines()
b = (pkg/'r0/changed-src/a1_deflate_core.v').read_text(errors='replace').splitlines()
sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
add = dele = 0; hunks = []
for tag, i1, i2, j1, j2 in sm.get_opcodes():
    if tag == 'equal': continue
    add += j2 - j1; dele += i2 - i1
    hunks.append((tag, i1+1, i2, j1+1, j2))
print('vs r5: hunks=%d added=%d deleted=%d' % (len(hunks), add, dele))
for h in hunks[:20]: print('   ', h)
d = (b5/'changed-src/a1_deflate_core.v').read_text(errors='replace')
print('b6 core has htab_b3:', b'\n' in b'' or 'htab_b3' in '\n'.join(b))
chg = [ln.strip() for ln in b if ('htab_b3' in ln or 'bm_raddr_b' in ln or 'ext_rf_byte' in ln or 'bm_b_spec' in ln)]
print('key lines (count %d):' % len(chg))
for ln in chg[:18]: print('   ', ln[:150])
print('bm_b_spec occurrences in b6 core:', '\n'.join(b).count('bm_b_spec'), '| in r5 core:', d.count('bm_b_spec'))

print('\n=== 5. SDC / pins / tcl vs b5 r0 ===')
for name in ['p2_board.sdc', 'a1_small_top.sdc', 'board_p2.adc', '01_build.tcl', '02_bitgen.tcl', '03_cwc.tcl']:
    p6, p5 = td/name, b5td/name
    if p6.exists() and p5.exists():
        print('%-18s b6=%s b5=%s same=%s' % (name, sha(p6)[:16], sha(p5)[:16], sha(p6) == sha(p5)))
    else:
        print('%-18s missing b6=%s b5=%s' % (name, p6.exists(), p5.exists()))
ta = (b5td/'01_build.tcl').read_text(errors='replace').splitlines()
tb = (td/'01_build.tcl').read_text(errors='replace').splitlines()
print('01_build.tcl diff vs b5 r0:')
for ln in difflib.unified_diff(ta, tb, lineterm='', n=0):
    if ln.startswith(('---', '+++', '@@')): continue
    print('   ', ln[:170])

print('\n=== 6. candidate_abnormal.rpt + bitgen/cwc markers ===')
print('candidate_abnormal.rpt:', (td/'candidate_abnormal.rpt').read_text(errors='replace').strip()[:400])
for name in ['bitgen_console_r0.log', 'cwc_console_r0.log', 'build_console_r0.log']:
    t = (td/name).read_text(errors='replace')
    dl = [ln.strip() for ln in t.splitlines() if re.search(r'download|flash|program_|jtag|\.bit', ln, re.I)]
    print(name, 'bit/download-related lines:', len(dl))
    for ln in dl[:8]: print('    ', ln[:170])

print('\n=== 7. b5 r0 baseline claim 374461 ===')
for p in [b5/'result-r0.md', b5/'CANDIDATE-MANIFEST-b5-a1-htab-pipe-r0.json']:
    if p.exists():
        t = p.read_text(errors='replace')
        for m in re.finditer(r'374[,\s]?461', t):
            print(p.name, repr(t[max(0, m.start()-90):m.start()+40].replace('\n', ' ')))
            break
print('\n=== 8. drift: current hashes of core/manifests ===')
print('core', sha(pkg/'r0/changed-src/a1_deflate_core.v'))
print('manifest', sha(pkg/'CANDIDATE-MANIFEST-b6-a1-htab-nw-r0.json'))
print('bit', sha(td/'a1_board.bit'))
print('cwc', sha(td/'a1_board.cwc'))
