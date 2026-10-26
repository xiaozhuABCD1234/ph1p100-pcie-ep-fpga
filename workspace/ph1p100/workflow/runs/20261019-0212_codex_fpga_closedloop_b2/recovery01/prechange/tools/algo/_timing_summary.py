# -*- coding: utf-8 -*-
"""Summarise the worst setup paths per module from a TD final_timing.rpt."""
import re
import sys
from collections import defaultdict

path = sys.argv[1]
txt = open(path, encoding="utf-8", errors="replace").read().splitlines()
slacks, begins, ends = [], [], []
for i, line in enumerate(txt):
    m = re.match(r"^Slack\s+:\s+(-?\d+\.\d+)ns", line)
    if m and len(slacks) < 80:
        slacks.append(float(m.group(1)))
        for j in range(i + 1, min(i + 8, len(txt))):
            if txt[j].startswith("Begin Point"):
                begins.append(txt[j])
            if txt[j].startswith("End Point"):
                ends.append(txt[j])
                break
mod = re.compile(r"u_top/u_([a-z0-9_]+)/")
per = defaultdict(list)
for s, b in zip(slacks, begins):
    m = mod.search(b)
    per[m.group(1) if m else "wrapper"].append(s)
for k, v in sorted(per.items(), key=lambda kv: min(kv[1])):
    print("%-8s n=%-3d worst=%+.3f best=%+.3f" % (k, len(v), min(v), max(v)))
print("total listed:", len(slacks))
