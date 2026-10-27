#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T09.rk-align-algo r1 tester: independent review scan of developer evidence."""
import json
import pathlib

HERE = pathlib.Path(__file__).resolve()
RUN = HERE.parents[4]  # .../<run>/test-reports/evidence/T09.rk-align-algo-r1/scripts/x.py
g1 = RUN / "algo" / "g1" / "msim"
rows = []
for d in sorted(g1.iterdir()):
    rp = d / "report.json"
    if not rp.exists():
        continue
    r = json.loads(rp.read_text(encoding="utf-8"))
    lut = r.get("lut_check")
    rows.append((d.name, r.get("case"), r.get("mutation"), r.get("verdict"),
                 r.get("pass_marker"), r.get("simulator_errors"),
                 len(r.get("mismatch_sample") or []), r.get("coverage"),
                 lut and lut.get("match")))
print("total report.json:", len(rows))
for row in rows:
    print(f"{row[0]} | {row[1]} {row[2]} | verdict={row[3]} pass_marker={row[4]} sim_err={row[5]} mismatch_samples={row[6]} lut_ok={row[8]}")
    print("    cov:", row[7])

print()
print("== G2 dev builds ==")
g2 = RUN / "algo" / "g2"
for d in sorted(g2.iterdir()):
    log = d / "td_00_all.log"
    marker = "MISSING"
    if log.exists():
        t = log.read_text(encoding="utf-8", errors="replace")
        marker = "ALL_DONE" if "T09_ALGO_ALL_DONE" in t else ("NO_MARKER")
        m1424 = "PRJ-1424" in t
        print(d.name, marker, "PRJ-1424" if m1424 else "")
    else:
        print(d.name, marker)
