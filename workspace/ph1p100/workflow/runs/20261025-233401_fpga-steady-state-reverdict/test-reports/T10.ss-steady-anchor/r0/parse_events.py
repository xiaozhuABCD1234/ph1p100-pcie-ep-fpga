"""Tester-independent parser / recomputation for T10.ss-steady-anchor r0.

Deliberately does NOT import or call the developer's sim/run_ss.py for the
recomputation.  Input is the raw vsim log (sim/logs/run4.log) plus the raw
stats/evt files for counters.  Negative controls are exercised locally.
"""
import json
import math
import os
import re
import sys

RUN = r"D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict"
TD = os.path.join(RUN, "T10.ss-steady-anchor", "r0")
LOG4 = os.path.join(TD, "sim", "logs", "run4.log")
STATS4 = os.path.join(TD, "sim", "caps", "ss4.stats")
SS_JSON = os.path.join(TD, "out", "steady-state.json")
SELF = os.path.join(TD, "out", "selfcheck.json")
CLK = 187.5e6
RAW_WORDS = 129600
DEMAND0 = 77.76
DEMAND25 = 97.20

EVT_RE = re.compile(r"SS_EVT t=(\d+) kind=(sof|cam_end|pub|read|enc|exp) frame=(\d+) n=(\d+)")
META_RE = re.compile(r"SS_META t_rst=(\d+) frames=(\d+) max_cycles=(\d+) uart_div=(\d+)")
PACE_RE = re.compile(r"SS_PACE frame=(\d+) slot=(\d+) t=(\d+) read=(\d+) slot_st=(\d+)")
STATS_RE = re.compile(r"SS_STATS cap=(\d+) enc=(\d+) exported=(\d+) read=(\d+) cycles=(\d+) frames=(\d+) ss_pass=(\d+)")


class Reject(Exception):
    def __init__(self, reason):
        super().__init__(reason)
        self.reason = reason


def parse_log(path):
    ev = {}
    meta = None
    pace = {}
    stats_line = None
    for line in open(path, encoding="utf-8", errors="replace"):
        m = META_RE.search(line)
        if m:
            meta = {"t_rst": int(m.group(1)), "frames": int(m.group(2)),
                    "max_cycles": int(m.group(3)), "uart_div": int(m.group(4))}
        m = PACE_RE.search(line)
        if m:
            pace[int(m.group(1))] = {"slot": int(m.group(2)), "t": int(m.group(3)),
                                     "read": int(m.group(4)), "slot_st": int(m.group(5))}
        m = STATS_RE.search(line)
        if m:
            stats_line = dict(zip(["cap", "enc", "exported", "read", "cycles", "frames", "ss_pass"],
                                  [int(x) for x in m.groups()]))
        m = EVT_RE.search(line)
        if m:
            t, kind, frame, n = int(m.group(1)), m.group(2), int(m.group(3)), int(m.group(4))
            ev.setdefault((frame, kind), []).append({"t": t, "n": n})
    return meta, ev, pace, stats_line


def require_kinds(ev, frames, kinds):
    missing = []
    dup = []
    for f in frames:
        for k in kinds:
            got = ev.get((f, k), [])
            if len(got) == 0:
                missing.append([f, k])
            elif len(got) > 1:
                dup.append([f, k, len(got)])
    if missing:
        if frames and max(frames) >= 4 and any(x[0] == 4 for x in missing):
            raise Reject("ONLY_3_FRAMES")
        raise Reject("MISSING_EVENTS")
    if dup:
        raise Reject("DUPLICATE_EVENTS")


def one(ev, frame, kind):
    return ev[(frame, kind)][0]["t"]


def maybe_one(ev, frame, kind):
    got = ev.get((frame, kind), [])
    return got[0]["t"] if got else None


def compute(path):
    meta, ev, pace, stats_line = parse_log(path)
    if meta is None:
        raise Reject("NO_META")
    require_kinds(ev, [1, 2, 3, 4], ["sof", "cam_end", "pub", "read", "enc", "exp"])
    t_rst = meta["t_rst"]
    t = {k: {f: one(ev, f, k) for f in (1, 2, 3, 4)} for k in ("sof", "cam_end", "pub", "read", "enc", "exp")}
    r = {"t_rst": t_rst, "t_sof": t["sof"], "t_cam_end": t["cam_end"], "t_pub": t["pub"],
         "t_read": t["read"], "t_enc": t["enc"], "t_exp": t["exp"], "pace": pace, "stats_line": stats_line}
    r["L_cold"] = t["exp"][1] - t_rst
    r["L_frame"] = t["exp"][1] - t["sof"][1]
    r["S_2"] = t["exp"][2] - t["exp"][1]
    r["S_23"] = t["exp"][3] - t["exp"][2]
    r["S_34"] = t["exp"][4] - t["exp"][3]
    r["S_ss"] = (r["S_23"] + r["S_34"]) / 2.0
    r["S_avg2"] = (t["exp"][2] - t_rst) / 2.0
    r["S_band"] = [min(r["S_23"], r["S_34"]), max(r["S_23"], r["S_34"])]
    r["S_spread_pct"] = abs(r["S_23"] - r["S_34"]) / r["S_ss"] * 100.0
    r["startup"] = r["L_cold"] - r["S_ss"]
    r["startup_pct"] = (r["L_cold"] / r["S_ss"] - 1.0) * 100.0
    r["capacity_MBps"] = 4.86e8 / r["S_ss"]
    r["fps"] = 1.875e8 / r["S_ss"]
    r["margin_0_pct"] = (r["capacity_MBps"] / DEMAND0 - 1.0) * 100.0
    r["margin_25_pct"] = (r["capacity_MBps"] / DEMAND25 - 1.0) * 100.0
    r["f_req_0_MHz"] = 30.0 * r["S_ss"] / 1e6
    r["f_req_25_MHz"] = 37.5 * r["S_ss"] / 1e6
    r["f_req_0_mhz"] = r["f_req_0_MHz"]
    r["f_req_25_mhz"] = r["f_req_25_MHz"]
    r["export_tail"] = {f: t["exp"][f] - t["enc"][f] for f in (1, 2, 3, 4)}
    r["export_cost_cycles"] = 40_032 * 10
    tails = list(r["export_tail"].values())
    tail_span = max(tails) - min(tails)
    r["sink_limited"] = bool(tail_span > 0.01 * r["S_ss"] or max(tails) >= 0.5 * r["S_ss"])
    r["c_excl_export_MBps"] = 4.86e8 / (r["S_ss"] - (sum(tails) / 4.0)) if r["sink_limited"] else r["capacity_MBps"]
    r["knife_edge_0pct"] = r["S_band"][0] <= 6_250_000 <= r["S_band"][1]
    r["knife_edge_25pct"] = r["S_band"][0] <= 5_000_000 <= r["S_band"][1]
    # V1-V6
    sl = stats_line or {}
    r["v1_counts"] = (sl.get("cap") == 4 and sl.get("enc") == 4 and sl.get("exported") == 4
                      and sl.get("read") == 4 * RAW_WORDS)
    r["v3_stable"] = r["S_spread_pct"] <= 2.0
    r["v4_bubble"] = []
    for k in (2, 3):
        if not t["pub"][k + 1] < t["exp"][k]:
            r["v4_bubble"].append({"k": k, "pub_next": t["pub"][k + 1], "exp_k": t["exp"][k]})
    cam_dur = {f: t["cam_end"][f] - t["sof"][f] for f in (1, 2, 3, 4)}
    r["cam_duration"] = cam_dur
    if any(cam_dur[f] >= 0.5 * r["S_ss"] for f in (2, 3, 4)):
        r["v4_bubble"].append({"cam_duration_too_long": cam_dur})
    r["v4_no_bubble"] = len(r["v4_bubble"]) == 0
    r["capacity_is_lower_bound"] = not r["v4_no_bubble"]
    r["v5_detail"] = []
    for k, slot in ((3, 0), (4, 1)):
        p = pace.get(k)
        bits = None if p is None else ((p["slot_st"] >> (2 * slot)) & 3)
        ok = bool(p) and p["t"] < t["sof"][k] and p["read"] >= RAW_WORDS * (k - 2) and bits == 0
        r["v5_detail"].append({"frame": k, "slot": slot, "pace": p, "slot_bits": bits, "ok": ok})
    r["v5_slot_free"] = all(x["ok"] for x in r["v5_detail"])
    r["v6_detail"] = []
    for f in (1, 2, 3, 4):
        order = [t["pub"][f], t["read"][f], t["enc"][f], t["exp"][f]]
        if order != sorted(order):
            r["v6_detail"].append({"frame": f, "order": order})
    if not (t["exp"][1] < t["exp"][2] < t["exp"][3] < t["exp"][4]):
        r["v6_detail"].append({"exp_not_monotone": [t["exp"][f] for f in (1, 2, 3, 4)]})
    r["v6_monotone"] = len(r["v6_detail"]) == 0
    r["validity"] = {k: r[k] for k in ("v1_counts", "v3_stable", "v4_no_bubble", "v5_slot_free", "v6_monotone")}
    r["steady_state_status"] = "measured" if r["v1_counts"] and r["v3_stable"] and r["v4_no_bubble"] and r["v5_slot_free"] and r["v6_monotone"] else "unstable"
    return r


def validate_claim(r, claimed_S_ss, claimed_kind=None):
    """Reject the three forbidden substitutions; only the true interval may pass."""
    if abs(claimed_S_ss - r["S_avg2"]) <= 1.0:
        raise Reject("S_AVG2_AS_STEADY")
    if abs(claimed_S_ss - r["L_cold"]) <= 1.0:
        raise Reject("COLD_LATENCY_AS_THROUGHPUT")
    if abs(claimed_S_ss - r["S_ss"]) > 1.0:
        raise Reject("STEADY_INCONSISTENT")
    if not r["v3_stable"]:
        raise Reject("UNSTABLE_INTERVALS")
    return True


def cmp_json(r, js):
    diffs = []
    exact = ["t_rst", "L_cold", "L_frame", "S_2", "S_23", "S_34", "startup",
             "capacity_is_lower_bound", "sink_limited", "steady_state_status"]
    for k in exact:
        if k in js and js[k] != r[k] and not (isinstance(js[k], (int, float)) and isinstance(r[k], (int, float))
                                              and abs(float(js[k]) - float(r[k])) <= 0.51):
            diffs.append([k, js.get(k), r[k]])
    approx = ["S_ss", "S_avg2", "S_spread_pct", "startup_pct", "capacity_MBps", "fps", "margin_0_pct",
              "margin_25_pct", "f_req_0_mhz", "f_req_25_mhz", "c_excl_export_MBps"]
    for k in approx:
        if k in js and abs(float(js[k]) - float(r[k])) > max(1e-9, abs(float(r[k])) * 1e-9):
            diffs.append([k, js.get(k), r[k]])
    for f in (1, 2, 3, 4):
        if js["t_exp"][f] != r["t_exp"][f]:
            diffs.append([f"t_exp[{f}]", js["t_exp"][f], r["t_exp"][f]])
        if js["export_tail"][f] != r["export_tail"][f]:
            diffs.append([f"export_tail[{f}]", js["export_tail"][f], r["export_tail"][f]])
    return diffs


def main():
    res = {"source_log": LOG4}
    r = compute(LOG4)
    js = json.load(open(SS_JSON, encoding="utf-8"))
    res["metrics"] = {k: r[k] for k in ("t_rst", "L_cold", "L_frame", "S_2", "S_23", "S_34", "S_ss",
                                        "S_avg2", "S_band", "S_spread_pct", "startup", "startup_pct",
                                        "capacity_MBps", "fps", "margin_0_pct", "margin_25_pct",
                                        "f_req_0_MHz", "f_req_25_MHz", "export_tail",
                                        "export_cost_cycles", "sink_limited", "c_excl_export_MBps",
                                        "knife_edge_0pct", "knife_edge_25pct", "cam_duration")}
    res["validity_recomputed"] = {k: r[k] for k in r["validity"]}
    res["validity_recomputed"]["v2_control_exact"] = "checked separately by independent FRAMES=2 re-run"
    res["v4_bubble"] = r["v4_bubble"]
    res["v5_detail"] = r["v5_detail"]
    res["v6_detail"] = r["v6_detail"]
    res["json_diffs"] = cmp_json(r, js)
    res["developer_validity"] = js.get("validity")
    res["validity_match"] = all(js["validity"][k] == r["validity"][k] for k in r["validity"])
    res["stats_line"] = r["stats_line"]

    # independent counter arithmetic
    res["counter_checks"] = {
        "cap_bytes_equals_44F_plus_exp_bytes": r["stats_line"]["cap"] * 0 + 0,  # placeholder replaced below
    }
    expb = 0
    st = open(STATS4, encoding="utf-8").read()
    for kv in st.strip().split():
        if "=" in kv:
            k, v = kv.split("=", 1)
            if k == "exp_bytes":
                expb = int(v)
    rows = [x for x in st.strip().split()]
    d = dict(x.split("=", 1) for x in rows if "=" in x)
    d = {k: int(v) for k, v in d.items()}
    res["stats"] = d
    res["counter_checks"] = {
        "exp_bytes_expected": 40034 * 4,
        "cap_bytes_expected": 44 * 4 + 40034 * 4,
        "read_expected": RAW_WORDS * 4,
        "exp_bytes_ok": d["exp_bytes"] == 40034 * 4,
        "cap_bytes_ok": d["cap_bytes"] == 44 * 4 + 40034 * 4,
        "read_ok": d["read"] == RAW_WORDS * 4,
        "drops_zero": all(d[k] == 0 for k in ("raw_drop", "cmp_drop", "geom", "err", "dup", "wd")),
        "ss_pass": d.get("ss_pass"),
        "cycles_minus_last_exp": d["cycles"] - r["t_exp"][4],
    }

    # ---------------- negative controls (independent mutations) ----------------
    neg = []
    meta, ev, pace, _ = parse_log(LOG4)
    # NEG A: only frames 1-3
    ev3 = {k: v for k, v in ev.items() if k[0] <= 3}
    try:
        require_kinds(ev3, [1, 2, 3, 4], ["sof", "cam_end", "pub", "read", "enc", "exp"])
        neg.append({"id": "ONLY_3_FRAMES", "rejected": False})
    except Reject as e:
        neg.append({"id": "ONLY_3_FRAMES", "rejected": True, "reason": e.reason})
    # NEG B: S_avg2 passed as S_ss
    try:
        validate_claim(r, r["S_avg2"])
        neg.append({"id": "S_AVG2_AS_STEADY", "rejected": False})
    except Reject as e:
        neg.append({"id": "S_AVG2_AS_STEADY", "rejected": True, "reason": e.reason})
    # NEG C: L_cold passed as S_ss
    try:
        validate_claim(r, r["L_cold"])
        neg.append({"id": "COLD_LATENCY_AS_THROUGHPUT", "rejected": False})
    except Reject as e:
        neg.append({"id": "COLD_LATENCY_AS_THROUGHPUT", "rejected": True, "reason": e.reason})
    # positive control: true S_ss must pass
    try:
        validate_claim(r, r["S_ss"])
        neg.append({"id": "TRUE_S_SS_ACCEPTED", "rejected": False, "accepted": True})
    except Reject as e:
        neg.append({"id": "TRUE_S_SS_ACCEPTED", "rejected": True, "reason": e.reason})
    res["negative_controls"] = neg

    # developer selfcheck claims
    sc = json.load(open(SELF, encoding="utf-8"))
    res["dev_selfcheck"] = sc
    res["dev_selfcheck_consumed"] = True

    ok = (not res["json_diffs"] and res["validity_match"] and all(n["rejected"] for n in neg if n["id"] != "TRUE_S_SS_ACCEPTED")
          and all(n.get("accepted") for n in neg if n["id"] == "TRUE_S_SS_ACCEPTED")
          and all(res["counter_checks"][k] for k in ("exp_bytes_ok", "cap_bytes_ok", "read_ok", "drops_zero"))
          and res["counter_checks"]["ss_pass"] == 1 and 0 <= res["counter_checks"]["cycles_minus_last_exp"] <= 3000)
    res["pass"] = bool(ok)
    print(json.dumps(res, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
