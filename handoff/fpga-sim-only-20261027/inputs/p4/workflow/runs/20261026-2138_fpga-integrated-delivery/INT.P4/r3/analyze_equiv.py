import re, io, sys
from collections import Counter

p = r'D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\INT.P4\r3\regression\equiv_seedmode0.log'
base = {}
p4 = {}
for ln in io.open(p, encoding='utf-8', errors='ignore'):
    m = re.search(r'CHECK_REF_NEW MISMATCH stream=0 idx=(\d+) base=([0-9a-f]+) p4=([0-9a-f]+)', ln)
    if m:
        i = int(m.group(1))
        base[i] = int(m.group(2), 16)
        p4[i] = int(m.group(3), 16)

def d(t):
    return (t >> 3) & 0xffffffff

def f(t):
    return t & 0x7

print('entries', len(base))
bad = [k for k in range(1, 1719) if k in base and k in p4 and d(p4[k]) != d(base[k - 1])]
print('H1 fails', len(bad))
print('first bad', bad[:24])
for lo, hi, name in ((1, 767, 'f1'), (769, 1535, 'f2'), (1537, 1718, 'f3')):
    ok = sum(1 for k in range(lo, hi + 1) if k in base and k in p4 and d(p4[k]) == d(base[k - 1]))
    print(name, ok, '/', hi - lo + 1)
c = Counter(k % 16 for k in bad)
print('bad by j', sorted(c.items()))
rows = Counter((k // 16) for k in bad)
print('bad rows', len(rows), sorted(rows.items())[:10])
hist = Counter()
for k in bad:
    if k - 1 in base:
        hist[bin(d(p4[k]) ^ d(base[k - 1])).count('1')] += 1
print('bitdiff hist', sorted(hist.items())[:12])
# flags check on bad tokens
print('flag eq same idx', sum(1 for k in range(0, 1719) if k in base and k in p4 and f(p4[k]) == f(base[k])))
# check tokens where data equals the same index for any i (is p4 a permutation?)
idx_of = {}
for k, v in base.items():
    idx_of.setdefault(d(v), []).append(k)
perm = 0
for k, v in p4.items():
    if d(v) in idx_of:
        perm += 1
print('p4 data found in base stream', perm, '/', len(p4))
# offsets of the token position in base for p4[k]
off = Counter()
for k, v in p4.items():
    if d(v) in idx_of:
        cand = min(idx_of[d(v)], key=lambda x: abs(x - k))
        off[cand - k] += 1
print('offset hist', sorted(off.items())[:10])
