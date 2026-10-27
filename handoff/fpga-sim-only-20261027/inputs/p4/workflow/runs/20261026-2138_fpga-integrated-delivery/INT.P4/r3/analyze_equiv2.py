import re, io, sys
from collections import Counter

path = sys.argv[1] if len(sys.argv) > 1 else r'D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\INT.P4\r3\regression\equiv_seedmode2.log'
rec = {}
for ln in io.open(path, encoding='utf-8', errors='ignore'):
    m = re.search(r'CHECK_REF_NEW MISMATCH stream=(\d+) idx=(\d+) base=([0-9a-f]+) p4=([0-9a-f]+)', ln)
    if m:
        s = int(m.group(1)); i = int(m.group(2))
        rec.setdefault(s, {})[i] = (int(m.group(3), 16), int(m.group(4), 16))

def d(t):
    return (t >> 3) & 0xffffffff

def f(t):
    return t & 0x7

print('path', path)
for s in sorted(rec):
    idxs = sorted(rec[s])
    print('stream', s, 'mismatches', len(idxs), 'first', idxs[:16], 'last', idxs[-6:])
    # per-frame grouping (frames at 0, 768, 1536)
    for lo, hi, name in ((0, 767, 'f1'), (768, 1535, 'f2'), (1536, 1719, 'f3')):
        sub = [i for i in idxs if lo <= i <= hi]
        print('   ', name, len(sub), sub[:12])
    shifts = Counter()
    for i in idxs:
        b, p = rec[s][i]
        shifts[d(p) - d(b)] += 1
    print('    data delta hist', shifts.most_common(6))
    bad = [i for i in idxs if d(rec[s][i][1]) != rec[s][i][0] >> 3]
    # check whether p4[i] equals base[i-1] or base[i+1] data when available
    for i in idxs[:6]:
        b, p = rec[s][i]
        print('     i=%d base d=%08x f=%d | p4 d=%08x f=%d' % (i, d(b), f(b), d(p), f(p)))
