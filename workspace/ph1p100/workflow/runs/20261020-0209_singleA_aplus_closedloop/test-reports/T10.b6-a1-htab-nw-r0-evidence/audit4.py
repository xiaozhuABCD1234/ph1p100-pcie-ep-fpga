import sys, re, pathlib, hashlib
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
root = pathlib.Path(r'D:\fpga\ph1p100')
runs = root/'workflow/runs/20261020-0209_singleA_aplus_closedloop'
pkg = runs/'T10.b6-a1-htab-nw'
td = pkg/'r0/td'
b5 = runs/'T10.b5-a1-htab-pipe/r0'

def rd(p):
    b = p.read_bytes()
    for enc in ('utf-8-sig', 'utf-16', 'gb18030', 'latin-1'):
        try: return b.decode(enc)
        except Exception: pass
    return b.decode('latin-1', errors='replace')

print('=== 1. find b5 P2 baseline 374461 ===')
hits = 0
for p in b5.rglob('*'):
    if p.is_file() and p.stat().st_size < 5_000_000 and p.suffix.lower() in ('.md', '.json', '.txt', '.log', '.stats'):
        t = rd(p)
        for ln in t.splitlines():
            if '374461' in ln or '374,461' in ln:
                hits += 1
                print('  %-60s %s' % (str(p.relative_to(b5))[:60], ln.strip()[:130]))
                break
print('  b5 files mentioning 374461:', hits)

print('\n=== 2. b5 r0 P2 core-level evidence files ===')
for p in b5.rglob('*'):
    if p.is_file() and re.search(r'(comp|rand|p2)', p.name, re.I):
        print('  ', str(p.relative_to(b5)), p.stat().st_size)

print('\n=== 3. cwc console key lines ===')
t = rd(td/'cwc_console_r0.log')
print('chars', len(t), 'lines', len(t.splitlines()))
keys = [ln.strip() for ln in t.splitlines() if re.search(r'cwc|CWC|ERAM|eram|capture|Capture|window|trigger|clock', ln)]
print('marker lines', len(keys))
for ln in keys[:30]: print('   ', ln[:170])

print('\n=== 4. bitgen console key lines ===')
t2 = rd(td/'bitgen_console_r0.log')
print('chars', len(t2), 'lines', len(t2.splitlines()))
keys2 = [ln.strip() for ln in t2.splitlines() if re.search(r'bit|Bit|setup|hold|period|WNS|TNS|export|generate|candidate|\.al|sta', ln)]
print('marker lines', len(keys2))
for ln in keys2[:40]: print('   ', ln[:170])

print('\n=== 5. full download/flash/jtag scan (b6 pkg) ===')
pat = re.compile(r'download|flash|program\b|sram_load|jtag', re.I)
tot = 0
for p in sorted(pkg.rglob('*')):
    if p.is_file() and p.suffix.lower() in ('.log', '.tcl', '.json', '.md', '.txt', '.status', '.py'):
        t3 = rd(p)
        for ln in t3.splitlines():
            if pat.search(ln):
                tot += 1
                if tot <= 30: print('  %-45s %s' % (str(p.relative_to(pkg))[:45], ln.strip()[:120]))
print('total mentions:', tot)
print('tcl scripts present in r0/td:', sorted(x.name for x in td.glob('*.tcl')))

print('\n=== 6. build console outcome lines ===')
t4 = rd(td/'build_console_r0.log')
for ln in t4.splitlines():
    if re.search(r'RUN-\d|issue|Timing|timing check|route|Route|finish|Error', ln):
        print('   ', ln.strip()[:170])
