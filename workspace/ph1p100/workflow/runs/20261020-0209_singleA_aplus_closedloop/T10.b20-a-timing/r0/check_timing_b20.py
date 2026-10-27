#!/usr/bin/env python3
"""check_timing_b20.py -- engineering gate for T10.b20-a-timing r0.

Reads the TD artifacts of the single build session and evaluates the frozen
gates (dev-plan S3): synth precondition, routed violations/WNS + thin-margin
caveat, per-clock-group table, cone break (a1_abort_reg -> smem*.addrb count in
the routed timing report), resources.

Usage: python check_timing_b20.py <r0/td>
Writes <r0/td>/routed_gate_b20.{txt,json}; exit 0 PASS, 3 thin-margin caveat
candidate (allowed to continue), 1 FAIL.
"""
import json
import pathlib
import re
import sys

TD = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")


def txt(name):
    p = TD / name
    return p.read_text(encoding="utf-8", errors="replace") if p.exists() else ""


syn = txt("syn_gate_timing.rpt")
syna = txt("syn_gate_area.rpt")
st = txt("routed_timing_status.rpt")
qor = txt("routed_qor.rpt")
rt = txt("routed_timing.rpt")


def f(pat, s, cast=float, default=None):
    m = re.search(pat, s)
    return cast(m.group(1)) if m else default


res = {}
res["syn_sws"] = f(r"SWNS:\s*(-?[0-9.]+)", syn)
res["syn_tns"] = f(r"STNS:\s*(-?[0-9.]+)", syn)
res["syn_slices"] = f(r"#slice\*\s+([0-9]+)", syna, int)
res["syn_eram"] = f(r"#eram\s+([0-9]+)", syna, int)
res["syn_reg"] = f(r"#reg\s+([0-9]+)", syna, int)
res["routed_sws"] = f(r"SWNS:\s*(-?[0-9.]+)ns", st)
res["routed_tns"] = f(r"STNS:\s*(-?[0-9.]+)ns", st)
res["routed_hws"] = f(r"HWNS:\s*(-?[0-9.]+)ns", st)
res["routed_hts"] = f(r"HTNS:\s*(-?[0-9.]+)ns", st)
res["viol_s_ep"] = f(r"Num of violated S-EP\s*\|\s*([0-9]+)", qor, int)
res["viol_h_ep"] = f(r"Num of violated H-EP\s*\|\s*([0-9]+)", qor, int)
res["slices"] = f(r"#slices\s*\|\s*([0-9]+)", qor, int)
res["rams"] = f(r"#RAMs\s*\|\s*([0-9]+)", qor, int)
res["dsps"] = f(r"#DSPs\s*\|\s*([0-9]+)", qor, int)
res["dramhardcon"] = f(r"#DRAMHARDCON\s*\|\s*([0-9]+)", qor, int)

# per-group table: "Path Group : a -> b" ... "Max : SWNS x, STNS y, N Viol Endpoints"
# The report repeats group sections (multiple analyses/corners); keep the WORST
# WNS and the MAX violated-endpoint count per group so the gate is not fooled by
# a later, better-looking section.
groups = {}
for m in re.finditer(r"Path Group\s+:\s+(\S+) -> (\S+).*?Max\s+:\s+SWNS\s+(-?[0-9.]+)ns,\s+STNS\s+(-?[0-9.]+)ns,\s+([0-9]+) Viol Endpoints",
                     rt, re.S):
    k = "%s->%s" % (m.group(1), m.group(2))
    w, t, v = float(m.group(3)), float(m.group(4)), int(m.group(5))
    g = groups.setdefault(k, {"wns": w, "tns": t, "viol_ep": v, "sections": 0})
    g["wns"] = min(g["wns"], w)
    g["tns"] = min(g["tns"], t)
    g["viol_ep"] = max(g["viol_ep"], v)
    g["sections"] += 1
res["groups"] = groups
res["group_viol_sum"] = sum(v["viol_ep"] for v in groups.values())

paths = []
cur = {}
for line in rt.splitlines():
    m = re.match(r"^Slack\s+:\s+(-?[0-9.]+)ns", line)
    if m:
        if cur:
            paths.append(cur)
        cur = {"slack": float(m.group(1))}
        continue
    m = re.match(r"^Begin Point\s+:\s+(\S+)", line)
    if m and cur is not None:
        cur["begin"] = m.group(1)
    m = re.match(r"^End Point\s+:\s+(\S+)", line)
    if m and cur is not None:
        cur["end"] = m.group(1)
if cur:
    paths.append(cur)
res["worst_paths"] = paths[:20]
abort_cone = [p for p in paths if "a1_abort_reg" in p.get("begin", "") and
              re.search(r"smem\w*\.addrb", p.get("end", ""))]
res["abort_to_addrb_paths"] = abort_cone
clk_a1 = [p for p in paths if p.get("begin", "").startswith(("u_a1/", "auto_created"))]
res["worst_clk_a1_path"] = clk_a1[0] if clk_a1 else (paths[0] if paths else None)

G = {}
G["syn_gate"] = (res["syn_sws"] is not None and res["syn_sws"] >= 0 and
                 (res["syn_tns"] or 0) >= 0 and (res["syn_eram"] or 0) <= 103 and
                 (res["syn_slices"] or 0) <= 25800)
G["syn_precondition_0p127"] = res["syn_sws"] is not None and res["syn_sws"] >= 0.127
G["route_zero_viol"] = res["viol_s_ep"] == 0 and (res["viol_h_ep"] or 0) == 0 and \
    res["group_viol_sum"] == 0
G["route_hold_pos"] = res["routed_hws"] is not None and res["routed_hws"] >= 0
G["route_wnS_ge_0p003"] = res["routed_sws"] is not None and res["routed_sws"] >= 0.003
G["route_wnS_ge_0p05"] = res["routed_sws"] is not None and res["routed_sws"] >= 0.05
G["cone_break"] = len(abort_cone) == 0
G["res_slices"] = (res["slices"] or 0) <= 25800
G["res_eram"] = (res["rams"] or 0) <= 103
G["res_dsp"] = (res["dsps"] or 0) == 0
pg = groups
G["group_clk_a1"] = (pg.get("clk_a1->clk_a1", {}).get("wns", -9) >= 0.05)
G["group_ddr_user"] = (pg.get("ddr_user->ddr_user", {}).get("wns", -9) >= 0.003)
G["group_mipi_a"] = (pg.get("mipi_a_byte_clk->mipi_a_byte_clk", {}).get("wns", -9) >= 0.05)
G["group_sys50m"] = (pg.get("sys_clk50m->sys_clk50m", {}).get("wns", -9) >= 1.0)
G["group_pclkx1"] = (pg.get("pclkx1->pclkx1", {}).get("wns", -9) >= 0.5)
G["group_others_zero"] = all(v["viol_ep"] == 0 for k, v in pg.items()
                             if k not in ("clk_a1->clk_a1", "ddr_user->ddr_user",
                                          "mipi_a_byte_clk->mipi_a_byte_clk",
                                          "sys_clk50m->sys_clk50m", "pclkx1->pclkx1"))
res["gates"] = G

if not (G["syn_gate"] and G["syn_precondition_0p127"]):
    verdict = "FAIL_synth"
elif not (G["route_zero_viol"] and G["route_hold_pos"] and G["cone_break"] and
          G["res_slices"] and G["res_eram"] and G["res_dsp"]) or \
        not all(G[k] for k in ("group_ddr_user", "group_mipi_a", "group_sys50m",
                               "group_pclkx1", "group_others_zero")):
    verdict = "FAIL_route_timing"
elif G["route_wnS_ge_0p05"] and G["group_clk_a1"]:
    verdict = "PASS"
elif G["route_wnS_ge_0p003"]:
    verdict = "CAVEAT_thin_margin"
else:
    verdict = "FAIL_route_timing"
res["verdict"] = verdict

(TD / "routed_gate_b20.json").write_text(json.dumps(res, indent=2))
lines = ["ROUTED_GATE verdict=%s" % verdict,
         "syn SWNS=%s STNS=%s slice=%s eram=%s reg=%s" %
         (res["syn_sws"], res["syn_tns"], res["syn_slices"], res["syn_eram"], res["syn_reg"]),
         "routed SWNS=%s STNS=%s HWNS=%s HTNS=%s viol_s=%s viol_h=%s" %
         (res["routed_sws"], res["routed_tns"], res["routed_hws"], res["routed_hts"],
          res["viol_s_ep"], res["viol_h_ep"]),
         "resources slices=%s rams=%s dsp=%s dramhardcon=%s" %
         (res["slices"], res["rams"], res["dsps"], res["dramhardcon"]),
         "abort_to_addrb_paths=%d" % len(abort_cone),
         "worst_clk_a1=%s" % json.dumps(res["worst_clk_a1_path"]),
         "groups=%s" % json.dumps(groups)]
lines += ["gate %s=%s" % (k, v) for k, v in G.items()]
(TD / "routed_gate_b20.txt").write_text("\n".join(lines) + "\n")
print("\n".join(lines))
return_code = 0 if verdict == "PASS" else (3 if verdict == "CAVEAT_thin_margin" else 1)
sys.exit(return_code)
