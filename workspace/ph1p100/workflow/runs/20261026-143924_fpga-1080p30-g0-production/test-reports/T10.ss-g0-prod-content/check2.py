import hashlib, json, os, collections
RUN = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\T10.ss-g0-prod-content\r0"
P4 = r"D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict\T10.ss-4run-matrix\r0\src"
P3 = r"D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict\T10.ss-g0-closure\r0\src"


def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


src = os.path.join(RUN, 'src')
print("=== src vs P4/P3 frozen ===")
for fn in sorted(os.listdir(src)):
    if not fn.endswith('.v'):
        continue
    h = sha(os.path.join(src, fn))
    tag = []
    for base, lbl in ((P4, 'P4'), (P3, 'P3')):
        p = os.path.join(base, fn)
        tag.append(lbl + ('=SAME' if sha(p) == h else '=DIFF') if os.path.exists(p) else lbl + '=absent')
    print(f"{fn:26s} {h[:16]} {' '.join(tag)}")

print("=== l.log key lines ===")
for ln in open(os.path.join(RUN, 'logs', 'l.log'), encoding='utf-8', errors='replace'):
    if any(k in ln for k in ('SS_EVT', 'SS_PACE', 'SS_STALL', 'SS_RAW_MATCH', 'SS_STATS',
                             'B11_FULL_RESULT', 'Errors:', 'SS_META', 'SS_VEC_MATCH')):
        print(ln.rstrip())

print("=== run-status / precheck ===")
for f in ('out/run-status.json', 'out/precheck.json'):
    print(f, open(os.path.join(RUN, f)).read().strip())
print("=== negative-controls ===")
print(json.dumps(json.load(open(os.path.join(RUN, 'out', 'negative-controls.json'))), indent=1)[:2200])
print("=== commands.jsonl ===")
c = collections.Counter(); bad = []
for ln in open(os.path.join(RUN, 'sim', 'commands.jsonl'), encoding='utf-8'):
    try:
        j = json.loads(ln)
    except Exception:
        continue
    c[str(j.get('cmd') or j.get('action') or j.get('kind') or '?')[:44]] += 1
    s = json.dumps(j).lower()
    for w in ('quartus', 'td_', 'tang', 'bitgen', 'program', 'jtag', 'http', 'curl', 'flash'):
        if w in s:
            bad.append((w, ln.strip()[:150]))
print(dict(c)); print("flagged:", bad[:6])
