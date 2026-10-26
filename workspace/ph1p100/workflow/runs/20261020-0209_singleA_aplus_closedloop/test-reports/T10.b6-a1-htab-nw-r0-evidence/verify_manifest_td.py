import json, hashlib, pathlib, re, sys

root = pathlib.Path(r'D:\fpga\ph1p100')
pkg = root/'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw'
td = pkg/'r0/td'
man = json.loads((pkg/'CANDIDATE-MANIFEST-b6-a1-htab-nw-r0.json').read_text(encoding='utf-8'))

def sha(p):
    h = hashlib.sha256(); 
    with open(p,'rb') as f:
        for b in iter(lambda: f.read(1<<20), b''): h.update(b)
    return h.hexdigest()

print('=== A. manifest path/hash audit ===')
nodes = []
def walk(o, path):
    if isinstance(o, dict):
        if 'path' in o and isinstance(o['path'], str) and ('sha256' in o or 'exists' in o):
            nodes.append((path, o))
        for k,v in o.items(): walk(v, path+'.'+k)
    elif isinstance(o, list):
        for i,v in enumerate(o): walk(v, path+'[%d]'%i)
walk(man, '$')
bad = []
for path, o in nodes:
    p = pathlib.Path(o['path'])
    ok = p.exists()
    size = p.stat().st_size if ok else -1
    h = sha(p) if ok else ''
    sm = (size == o.get('bytes', size))
    hm = (h == o.get('sha256', h))
    if not (ok and sm and hm):
        bad.append((path, o['path'], ok, size, o.get('bytes'), h, o.get('sha256')))
print('nodes checked:', len(nodes), 'mismatches:', len(bad))
for b in bad: print('  MISMATCH', b)

print('\n=== B. candidate binding ===')
cand = man['candidate']
for k in ('bit','cwc','bid'):
    print(k, cand[k]['sha256'], cand[k]['bytes'], pathlib.Path(cand[k]['path']).stat().st_size)
cw = td/'cw'
print('cw dir:', [p.name for p in cw.glob('*')] if cw.exists() else 'MISSING')
for name, parent in (('compiled.bit','a1_board.bit'),('compiled.cwc','a1_board.cwc')):
    cp = cw/name
    if cp.exists():
        print(name, cp.stat().st_size, sha(cp), 'parent', sha(td/parent), 'match', sha(cp)==sha(td/parent))
    else:
        print(name, 'MISSING; glob:', [p.name for p in td.rglob(name)])

def lines(p):
    return pathlib.Path(p).read_text(errors='replace').splitlines()

def grab(rpt, pats, limit=12):
    out=[]
    for ln in lines(rpt):
        if any(re.search(p, ln) for p in pats):
            out.append(ln.rstrip())
            if len(out)>=limit: break
    return out

print('\n=== C. routed_qor.rpt raw ===')
print('\n'.join(lines(td/'routed_qor.rpt')))

print('\n=== D. routed_timing.rpt header/summary ===')
tl = lines(td/'routed_timing.rpt')
for ln in tl[:8]: print(' |', ln.rstrip())
for i,ln in enumerate(tl[:120]):
    if re.search(r'SWNS|STNS|HWNS|HTNS|Period|coverage|Confidence|Corner|Report Scheme|Total', ln):
        print(' %4d| %s' % (i, ln.rstrip()))

print('\n=== E. endpoint / violation counting ===')
pats = [r'Number of (violated|total|analysed|unconstrained)', r'^\s*Total\s+\d', r'violat', r'Unconstrained', r'No path', r'Endpoint']
seen=set(); c=0
for i,ln in enumerate(tl):
    if re.search(r'violated|Unconstrained|Total .*end|end point|endpoint', ln, re.I):
        key=ln.strip()
        if key in seen: continue
        seen.add(key); print(' %6d| %s' % (i, ln.rstrip())); c+=1
        if c>=40: break

print('\n=== F. structural: htab_p3v / bm_b occurrences in routed_timing.rpt ===')
txt = (td/'routed_timing.rpt').read_text(errors='replace')
for tok in ['htab_p3v','bm_b_syn','bm_b.addrb','addrb','bm_raddr_b','htab_b3','S_EXT','ext_mis']:
    print('%-14s count=%d' % (tok, txt.count(tok)))
idx = txt.find('bm_b')
print('first bm_b context:', repr(txt[max(0,idx-200):idx+200]) if idx>=0 else 'none')

print('\n=== G. routed_area.rpt ERAM / LUT / REG ===')
grab_area = [ln.rstrip() for ln in lines(td/'routed_area.rpt') if re.search(r'ERAM|RAM|LUT|REG|Slice|Slice|DSP|Total|Used|Available', ln, re.I)][:40]
print('\n'.join(grab_area))

print('\n=== H. routed_check_timing.rpt ===')
print('\n'.join(lines(td/'routed_check_timing.rpt')[:40]))

print('\n=== I. syn_gate_timing.rpt header ===')
for ln in lines(td/'syn_gate_timing.rpt')[:60]:
    if re.search(r'SWNS|STNS|HWNS|HTNS|Period|coverage|Total|Confidence', ln): print(' |', ln.rstrip())
stxt = (td/'syn_gate_timing.rpt').read_text(errors='replace')
for tok in ['htab_p3v','bm_b']:
    print('syn %s count=%d' % (tok, stxt.count(tok)))

print('\n=== J. console fatal scan ===')
for name in ['build_console_r0.log','bitgen_console_r0.log','cwc_console_r0.log']:
    p = td/name
    t = p.read_text(errors='replace')
    hits = [ln.rstrip() for ln in t.splitlines() if re.search(r'FATAL|ERROR|Error:|failed|FAIL', ln)]
    print(name, 'lines', len(t.splitlines()), 'fatal-ish', len(hits))
    for h in hits[:10]: print('    ', h[:200])

print('\n=== K. flow status ===')
for name in ['route_flow.status','place_flow.status']:
    print('--', name)
    print('\n'.join(lines(td/name)[:30]))

print('\n=== L. artifact-hashes.txt ===')
ah = pkg/'artifact-hashes.txt'
print(ah.exists(), ah.stat().st_size if ah.exists() else '')
if ah.exists(): print('\n'.join(lines(ah)[:40]))
