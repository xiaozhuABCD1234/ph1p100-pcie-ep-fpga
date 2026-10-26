import os, time, collections
ROOT = r"D:\fpga\ph1p100"
CUT = time.mktime(time.strptime("2026-10-26 00:00", "%Y-%m-%d %H:%M"))
WIN0 = time.mktime(time.strptime("2026-10-26 14:30", "%Y-%m-%d %H:%M"))
WIN1 = time.mktime(time.strptime("2026-10-26 15:50", "%Y-%m-%d %H:%M"))


def walk(base, pred):
    hits = []
    for dp, dn, fn in os.walk(base):
        for f in fn:
            p = os.path.join(dp, f)
            try:
                st = os.stat(p)
            except OSError:
                continue
            if pred(st.st_mtime):
                hits.append((st.st_mtime, p))
    return sorted(hits)


print("== fpga/ modified today ==")
h = walk(os.path.join(ROOT, "fpga"), lambda m: m > CUT)
for m, p in h[:12]:
    print(time.strftime("%H:%M:%S", time.localtime(m)), os.path.relpath(p, ROOT))
print("count:", len(h))

print("== old runs modified in dev window 14:30-15:50 (excl current run) ==")
base = os.path.join(ROOT, "workflow", "runs")
groups = collections.Counter()
for m, p in walk(base, lambda m: WIN0 < m < WIN1):
    if "20261026-143924" in p:
        continue
    rel = os.path.relpath(p, base).split(os.sep)
    groups[os.sep.join(rel[:2])] += 1
for k, v in groups.most_common(12):
    print(v, k)
print("total:", sum(groups.values()))
