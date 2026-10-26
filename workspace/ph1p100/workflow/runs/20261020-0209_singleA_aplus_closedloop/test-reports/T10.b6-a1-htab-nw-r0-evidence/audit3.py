import json, hashlib, pathlib, re

root = pathlib.Path(r'D:\fpga\ph1p100')
runs = root/'workflow/runs/20261020-0209_singleA_aplus_closedloop'
pkg = runs/'T10.b6-a1-htab-nw'
td = pkg/'r0/td'
b5 = runs/'T10.b5-a1-htab-pipe/r0'
b2r4 = runs/'T10.b2-a1-uart-impl/r4'

def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''): h.update(b)
    return h.hexdigest()

print('=== 1. b5 r0 P2 baseline (the 374,461 regression) ===')
for f in ['comp.stats.txt', 'rand.stats.txt']:
    p = b5/'sim'/f
    print(f, p.exists(), p.read_text(errors='replace').strip()[:220] if p.exists() else '')
for f in ['comp.out.hex', 'rand.out.hex']:
    p = b5/'sim'/f
    print(f, p.exists(), sha(p) if p.exists() else '')

print('\n=== 2. r4 directory tree (top 2 levels) + captures ===')
if b2r4.exists():
    for p in sorted(b2r4.rglob('*')):
        rel = p.relative_to(b2r4)
        if len(rel.parts) <= 3 and p.is_file():
            print('  ', rel, p.stat().st_size)
else:
    print('  missing', b2r4)
caps = list(b2r4.rglob('*.dec')) if b2r4.exists() else []
print('r4 .dec files:', [(str(p.relative_to(b2r4)), p.stat().st_size, sha(p)[:16]) for p in caps])

print('\n=== 3. golden chain: b5 r0 captures vs b6 rerun ===')
g5 = b5/'sim/captures'
mine = runs/'test-reports/T10.b6-a1-htab-nw-r0-evidence/sim-rerun'
for name in ['micro8x2', 'mid64x8', 'full_grad']:
    p5 = g5/(name+'.dec'); pm = mine/(name+'.dec')
    p4 = [p for p in caps if p.name == name+'.dec']
    print('%-10s b5=%s b6rerun=%s r4=%s' % (name, sha(p5)[:16] if p5.exists() else '-',
          sha(pm)[:16] if pm.exists() else '-', (sha(p4[0])[:16] if p4 else '-')))
    if p5.exists() and p4: print('           b5==r4:', sha(p5) == sha(p4[0]))

print('\n=== 4. bit file identity ===')
bit = td/'a1_board.bit'
raw = bit.read_bytes()
print('size', len(raw), 'sha', sha(bit))
print('first 64 bytes hex:', raw[:64].hex())
txt = raw[:4096].decode('latin-1', errors='replace')
for kw in ['PH1P100', 'SBG484', 'Anlogic', 'AL3']:
    print('  header contains %-8s : %s' % (kw, kw in txt))
print('zeros-tail check: all-0xff?', raw[-16:] == b'\xff'*16, 'last16', raw[-16:].hex())

print('\n=== 5. cwc / bitgen console key lines ===')
cwc = (td/'cwc_console_r0.log').read_text(errors='replace')
keys = [ln.strip() for ln in cwc.splitlines() if re.search(r'ERAM|eram|capture|cwc|CWC|coverage|Virtual|window|trigger', ln)]
print('cwc marker lines:', len(keys))
for ln in keys[:25]: print('   ', ln[:180])
bg = (td/'bitgen_console_r0.log').read_text(errors='replace')
k2 = [ln.strip() for ln in bg.splitlines() if re.search(r'bit|Bit|setup|hold|period|WNS|TNS|export|generate|candidate', ln)]
print('bitgen marker lines:', len(k2))
for ln in k2[:30]: print('   ', ln[:180])

print('\n=== 6. download/flash evidence scan across all b6 logs/tcl ===')
pat = re.compile(r'download|flash|program\b|sram_load|jtag', re.I)
tot = 0
for p in sorted(pkg.rglob('*')):
    if p.is_file() and p.suffix.lower() in ('.log', '.tcl', '.json', '.md', '.txt', '.status') and p.stat().st_size < 20_000_000:
        try: t = p.read_text(errors='replace')
        except Exception: continue
        for ln in t.splitlines():
            if pat.search(ln):
                tot += 1
                if tot <= 25: print('  %-52s %s' % (str(p.relative_to(pkg))[:52], ln.strip()[:140]))
print('total download/flash/jtag mentions:', tot)

print('\n=== 7. manifest self hash + size ===')
mp = pkg/'CANDIDATE-MANIFEST-b6-a1-htab-nw-r0.json'
print(mp.name, mp.stat().st_size, sha(mp))
