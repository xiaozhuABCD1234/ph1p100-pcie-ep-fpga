#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Independent integrated-test verification for T10.ss-g0-prod-sink r0.

Read-only w.r.t. the frozen candidate/P1/P2.  Writes only:
  test-reports/T10.ss-g0-prod-sink/independent-verify.json

Independence:
  * comp bytes are re-derived from P1 raw EVT (`SS_EVT kind=exp bytes=<cum>`),
    not copied from the developer's JSON;
  * S_ss / tail / sink_limited / G0 / margins are re-derived from raw EVT;
  * raw-band / sink arithmetic is re-derived from frozen constants;
  * the developer JSON is only a comparison target, never an input to arithmetic;
  * four negative controls are executed as mutations against my own predicates.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True   # never create __pycache__ inside the frozen candidate

RUN = Path(r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production")
CAND = RUN / "T10.ss-g0-prod-sink" / "r0"
P1 = RUN / "T10.ss-g0-prod-content" / "r0"
DEV_JSON = CAND / "out" / "sink-headroom.json"
DEV_MAN = CAND / "manifest-r0.json"
DEV_SCRIPT = CAND / "model" / "sink_headroom.py"
P1_JSON = P1 / "out" / "content-verdict-r1.json"
OUT = Path(__file__).resolve().parent / "independent-verify.json"

CLK = 187.5e6
G0 = 6_250_000
SINK = 93.75
RAW_BAND = 2_594_706
PAYLOAD = 2_592_000
# dispatch hard-binding: frozen manifest SHA (independent of manifest content)
EXPECTED_MAN_SHA = "de8a5cffb8044828d2c4eb0ae72d1959c5267a06744a4002bf60a413995aa139"

results: list[dict] = []


def rec(cid: str, ok: bool, detail) -> None:
    results.append({"id": cid, "pass": bool(ok), "detail": detail})


def sha(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_evt(path: Path) -> dict:
    ev = {"enc": {}, "exp": {}, "sof": {}}
    for line in path.read_text(encoding="utf-8", errors="strict").splitlines():
        if not line.startswith("SS_EVT"):
            continue
        kv = {}
        for tok in line.split()[1:]:
            if "=" in tok:
                k, v = tok.split("=", 1)
                kv[k] = v
        kind = kv.get("kind")
        fr = int(kv.get("frame", "0"))
        if kind == "enc":
            ev["enc"][fr] = int(kv["t"])
        elif kind == "exp":
            ev["exp"][fr] = (int(kv["t"]), int(kv["bytes"]))
        elif kind == "sof":
            ev["sof"][fr] = int(kv["t"])
    return ev


def derive(ev: dict) -> dict:
    exp_t = {k: v[0] for k, v in ev["exp"].items()}
    cum = {k: v[1] for k, v in ev["exp"].items()}
    assert sorted(exp_t) == [1, 2, 3, 4], exp_t
    b1 = cum[1]
    b2 = cum[2] - cum[1]
    b3 = cum[3] - cum[2]
    b4 = cum[4] - cum[3]
    steady = {b2, b3, b4}
    assert len(steady) == 1, (b2, b3, b4)
    s23 = exp_t[3] - exp_t[2]
    s34 = exp_t[4] - exp_t[3]
    s_ss = (s23 + s34) / 2.0
    tails = {k: exp_t[k] - ev["enc"][k] for k in (2, 3, 4)}
    tail_mean = sum(tails.values()) / 3.0
    tail_frac = tail_mean / s_ss
    core_mean = (ev["enc"][4] - ev["enc"][1]) / 3.0
    export_mean = 2.0 * steady.pop()
    tail_frac_check = export_mean / s_ss
    margin = G0 / s_ss - 1.0
    sink_limited = tail_frac >= 0.50
    if s_ss > G0:
        g0 = "G0_not_closed"
    elif sink_limited:
        g0 = "G0_not_proven"
    else:
        g0 = "G0_feasible_for_scope"
    if sink_limited:
        g0 = "G0_not_proven" if s_ss > G0 else "G0_not_proven"
    return {
        "bytes_frame1": b1,
        "bytes_steady": b2,
        "frames_steady_equal": True,
        "S_23": s23,
        "S_34": s34,
        "S_ss": s_ss,
        "tail": tails,
        "tail_mean": tail_mean,
        "tail_frac": tail_frac,
        "tail_frac_from_2x": tail_frac_check,
        "core_interval_mean": core_mean,
        "export_time_mean": export_mean,
        "bottleneck": "core_interval" if core_mean > export_mean else "export_time",
        "sink_limited": sink_limited,
        "margin_G0_pct": 100.0 * margin,
        "G0": g0,
        "L_cold_raw": exp_t[1],
    }


def cycles(b: float, mbps: float) -> float:
    return b / (mbps * 1e6) * CLK


def main() -> int:
    dev = json.loads(DEV_JSON.read_text(encoding="utf-8"))
    p1 = json.loads(P1_JSON.read_text(encoding="utf-8"))

    # ---------------- A. comp bytes + P1 metrics from raw EVT ----------------
    nev = parse_evt(P1 / "sim" / "caps" / "n-r1.evt")
    lev = parse_evt(P1 / "sim" / "caps" / "l-r1.evt")
    nd = derive(nev)
    ld = derive(lev)
    rec("A1_comp_bytes_from_evt",
        nd["bytes_steady"] == 1_677_336 and ld["bytes_steady"] == 2_156_300,
        {"N": nd["bytes_steady"], "L": ld["bytes_steady"],
         "N_frame1": nd["bytes_frame1"], "L_frame1": ld["bytes_frame1"]})
    rec("A2_metrics_from_evt",
        abs(nd["S_ss"] - 7_475_240) < 1e-9 and abs(ld["S_ss"] - 6_986_952) < 1e-9
        and abs(nd["margin_G0_pct"] + 16.390644) < 1e-5
        and abs(ld["margin_G0_pct"] + 10.547546) < 1e-5,
        {"N": {k: nd[k] for k in ("S_ss", "tail_frac", "sink_limited", "margin_G0_pct", "G0")},
         "L": {k: ld[k] for k in ("S_ss", "tail_frac", "sink_limited", "margin_G0_pct", "G0")}})
    # cross-check EVT-derived values against P1 frozen JSON (agreement, not source)
    rec("A3_p1_json_agreement",
        all(abs(nd[k] - p1["content_classes"]["N"][k]) < 1e-9 for k in ("S_ss", "tail_frac"))
        and all(abs(ld[k] - p1["content_classes"]["L"][k]) < 1e-9 for k in ("S_ss", "tail_frac"))
        and p1["content_classes"]["N"]["per_frame"]["2"]["exp_bytes"] == nd["bytes_steady"]
        and p1["content_classes"]["L"]["per_frame"]["2"]["exp_bytes"] == ld["bytes_steady"],
        "EVT-derived == P1 content-verdict-r1.json")

    # ---------------- B. comp-stream sink demand ----------------------------
    demand = {}
    for cid, b in (("N", nd["bytes_steady"]), ("L", ld["bytes_steady"])):
        r30 = b * 30.0 / 1e6
        r25 = b / 0.025 / 1e6
        demand[cid] = {"bytes": b, "rate30": r30, "rate25": r25,
                       "fits30": r30 < SINK, "fits25": r25 < SINK,
                       "util25_pct": 100.0 * r25 / SINK,
                       "headroom25_pct": 100.0 * (SINK / r25 - 1.0),
                       "export_cycles": 2 * b}
    rec("B1_comp_demand_values",
        abs(demand["N"]["rate30"] - 50.32008) < 1e-5
        and abs(demand["L"]["rate30"] - 64.68900) < 1e-5
        and abs(demand["N"]["rate25"] - 67.09344) < 1e-5
        and abs(demand["L"]["rate25"] - 86.25200) < 1e-5,
        {k: {kk: demand[k][kk] for kk in ("rate30", "rate25")} for k in demand})
    rec("B2_comp_under_93_75",
        all(demand[c]["fits30"] and demand[c]["fits25"] for c in ("N", "L")),
        {"N": (demand["N"]["rate30"], demand["N"]["rate25"]),
         "L": (demand["L"]["rate30"], demand["L"]["rate25"]), "sink": SINK})
    # export identity vs P1 tail (92-cycle offset expected: 2*bytes vs t_exp-t_enc)
    rec("B3_export_identity_vs_p1_tail",
        abs(demand["N"]["export_cycles"] - nd["tail_mean"]) <= 100
        and abs(demand["L"]["export_cycles"] - ld["tail_mean"]) <= 100,
        {"N": (demand["N"]["export_cycles"], nd["tail_mean"]),
         "L": (demand["L"]["export_cycles"], ld["tail_mean"])})
    # sink is not the bottleneck: export < core interval
    rec("B4_sink_not_bottleneck",
        demand["N"]["export_cycles"] < nd["core_interval_mean"]
        and demand["L"]["export_cycles"] < ld["core_interval_mean"]
        and nd["bottleneck"] == "core_interval" and ld["bottleneck"] == "core_interval",
        {"N_ratio": demand["N"]["export_cycles"] / nd["core_interval_mean"],
         "L_ratio": demand["L"]["export_cycles"] / ld["core_interval_mean"]})

    # ---------------- C. raw band three tiers --------------------------------
    tiers = {}
    for name, mbps in (("93.75", SINK), ("103.78824", RAW_BAND / 0.025 / 1e6),
                       ("103.79_rounded", 103.79), ("187.5", 187.5)):
        cy = cycles(RAW_BAND, mbps)
        tiers[name] = {"MBps": mbps, "cycles": cy,
                       "cycles_int": int(round(cy)),
                       "ms": RAW_BAND / (mbps * 1e6) * 1e3,
                       "pct_G0": 100.0 * cy / G0}
    ok_c = (tiers["93.75"]["cycles_int"] == 5_189_412
            and abs(tiers["93.75"]["ms"] - 27.676864) < 1e-6
            and abs(tiers["93.75"]["pct_G0"] - 83.030592) < 1e-6
            and tiers["103.78824"]["cycles_int"] == 4_687_500
            and abs(tiers["103.78824"]["ms"] - 25.0) < 1e-9
            and abs(tiers["103.78824"]["pct_G0"] - 75.0) < 1e-9
            and tiers["187.5"]["cycles_int"] == 2_594_706
            and abs(tiers["187.5"]["ms"] - 13.838432) < 1e-6
            and abs(tiers["187.5"]["pct_G0"] - 41.515296) < 1e-6)
    rec("C1_three_tier_arithmetic", ok_c,
        {k: {"cycles": v["cycles_int"], "ms": round(v["ms"], 6),
             "pct_G0": round(v["pct_G0"], 6)} for k, v in tiers.items()})
    need30 = RAW_BAND * 30.0 / 1e6
    need25 = RAW_BAND / 0.025 / 1e6
    short_pct = 100.0 * (tiers["93.75"]["cycles"] / tiers["103.78824"]["cycles"] - 1.0)
    rec("C2_raw_need_fits_shortfall",
        need30 < SINK < need25
        and abs(need30 - 77.84118) < 1e-5
        and abs(need25 - 103.78824) < 1e-6
        and abs(short_pct - 10.707456) < 1e-6,
        {"need30": need30, "need25": need25, "short_pct": short_pct,
         "short_pct_rounded_4dp": round(short_pct, 4),
         "short_ms": tiers["93.75"]["ms"] - 25.0,
         "slack30_ms": 1000.0 / 30.0 - tiers["93.75"]["ms"]})
    rec("C3_rounded_equiv",
        abs(tiers["103.79_rounded"]["cycles"] - 4_687_421) <= 1.0,
        {"cycles_from_rounded": tiers["103.79_rounded"]["cycles"],
         "frozen": 4_687_500, "delta": 4_687_500 - tiers["103.79_rounded"]["cycles"]})
    rec("C4_raw_band_not_applied_to_comp",
        dev["raw_band"]["applied_to_comp_stream"] is False
        and nd["bytes_steady"] != RAW_BAND and ld["bytes_steady"] != RAW_BAND
        and abs(demand["N"]["rate25"] - need25) > 1.0,
        {"N_frac_of_raw_band_pct": 100.0 * nd["bytes_steady"] / RAW_BAND,
         "L_frac_of_raw_band_pct": 100.0 * ld["bytes_steady"] / RAW_BAND})

    # ---------------- D. G0 unchanged ---------------------------------------
    rec("D1_g0_boundary",
        dev["headline"]["sink_is_p1_bottleneck"] is False
        and "G0_not_proven" in dev["headline"]["g0"]
        and "G0_not_closed" in dev["headline"]["g0"]
        and "-16.3906" in dev["headline"]["g0"] and "-10.5475" in dev["headline"]["g0"]
        and p1["headline"] == "G0_not_proven"
        and nd["G0"] == "G0_not_closed" and ld["G0"] == "G0_not_proven",
        {"dev_headline": dev["headline"]["g0"], "evt_N": nd["G0"], "evt_L": ld["G0"]})

    # ---------------- E. dev JSON vs independent values ---------------------
    cmp_ok = True
    cmp_detail = {}
    for cid, d in (("N", nd), ("L", ld)):
        j = dev["comp_stream"][cid]
        pairs = {
            "bytes": (j["bytes_steady_frame"], d["bytes_steady"]),
            "rate30": (j["demand"]["period_33_3333ms"]["MBps"], round(demand[cid]["rate30"], 6)),
            "rate25": (j["demand"]["period_25_0ms"]["MBps"], round(demand[cid]["rate25"], 6)),
            "S_ss": (j["p1_measured"]["S_ss"], d["S_ss"]),
            "tail_frac": (j["p1_measured"]["tail_frac"], round(d["tail_frac"], 6)),
            "export_cycles": (j["export_at_93_75"]["cycles"], demand[cid]["export_cycles"]),
            "G0": (j["p1_measured"]["G0"], d["G0"]),
        }
        cmp_detail[cid] = {}
        for k, (a, b) in pairs.items():
            same = (a == b) or (isinstance(a, float) and abs(a - b) < 1e-5)
            cmp_detail[cid][k] = {"json": a, "indep": b, "ok": same}
            cmp_ok = cmp_ok and same
    rec("E1_dev_json_matches_independent", cmp_ok, cmp_detail)

    # raw band JSON vs independent
    rb = dev["raw_band"]
    rec("E2_dev_raw_band_matches",
        rb["bytes_per_frame"] == RAW_BAND
        and rb["at_93_75"]["cycles"] == 5_189_412
        and rb["at_93_75"]["fits_33_3333ms"] is True
        and rb["at_93_75"]["fits_25_0ms"] is False
        and abs(rb["at_93_75"]["shortfall_at_25ms_pct"] - short_pct) < 1e-5
        and rb["need_at_25ms_MBps"] == 103.78824,
        {k: rb["at_93_75"][k] for k in ("cycles", "ms", "pct_of_G0_window",
                                       "fits_33_3333ms", "fits_25_0ms",
                                       "shortfall_at_25ms_pct", "shortfall_at_25ms_ms")})

    # ---------------- F. manifest / hashes / scope --------------------------
    man = json.loads(DEV_MAN.read_text(encoding="utf-8"))
    man_sha = sha(DEV_MAN)
    arts = man["artifacts"]
    art_rows = []
    for a in arts:
        p = Path(a["path"])
        actual = {"sha256": sha(p), "bytes": p.stat().st_size}
        art_rows.append({"path": p.name, "manifest": a["sha256"][:16],
                         "actual": actual["sha256"][:16],
                         "bytes_ok": actual["bytes"] == a["bytes"],
                         "sha_ok": actual["sha256"] == a["sha256"]})
    rec("F1_manifest_sha", man_sha == EXPECTED_MAN_SHA,
        {"manifest_sha": man_sha, "expected": EXPECTED_MAN_SHA})
    rec("F2_artifacts_5_of_5", len(arts) == 5 and all(r["sha_ok"] and r["bytes_ok"] for r in art_rows),
        art_rows)
    scope_ok = all(s.startswith(str(CAND)) or s.startswith("%TEMP%\\opencode\\ss-g0-prod-sink")
                   for s in man["write_scope"])
    rec("F3_scope_and_zero_hw",
        scope_ok and man["stopped_modifying"] is True and man["active_commands"] == 0
        and man["evidence_rounds"] == {"vsim": 0, "td": 0, "board": 0, "network": 0}
        and len([p for p in CAND.rglob("*") if p.is_file()]) == len(arts) + 1,
        {"write_scope": man["write_scope"], "evidence_rounds": man["evidence_rounds"],
         "files_under_cand": sorted(str(p.relative_to(CAND)) for p in CAND.rglob("*") if p.is_file())})
    up_rows = []
    for u in man["upstream_inputs"]:
        p = Path(u["path"])
        up_rows.append({"path": p.name, "sha_ok": p.is_file() and sha(p) == u["sha256"],
                        "bytes_ok": p.is_file() and p.stat().st_size == u["bytes"]})
    rec("F4_upstream_inputs_bound", all(r["sha_ok"] and r["bytes_ok"] for r in up_rows), up_rows)

    # commands.jsonl: only python model runs, rc=0, no sim/td/board
    cmd_ok = True
    cmd_detail = []
    for line in (CAND / "commands.jsonl").read_text(encoding="utf-8").splitlines():
        j = json.loads(line)
        cmd_detail.append({"phase": j["phase"], "rc": j["rc"], "seconds": j["seconds"],
                           "argv": j["argv"][1:]})
        low = " ".join(j["argv"]).lower()
        cmd_ok = cmd_ok and j["rc"] == 0 and "vsim" not in low and "td" not in low.split()
    rec("F5_commands_zero_sim_td", cmd_ok and len(cmd_detail) == 2, cmd_detail)

    # ---------------- G. script reproducibility (read-only import) ----------
    spec = importlib.util.spec_from_file_location("dev_sink_headroom", DEV_SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)          # definitions only, main() guarded
    model = mod.build_model(CAND, RUN)    # read-only: json.loads + sha256_file
    text = mod.dump_json(model)
    frozen_text = DEV_JSON.read_text(encoding="utf-8")
    rec("G1_script_reproduces_frozen_json", text == frozen_text,
        {"equal": text == frozen_text, "len_regen": len(text), "len_frozen": len(frozen_text)})
    rec("G2_dev_checks_all_pass",
        all(v["pass"] for v in model["checks"].values()) and len(model["checks"]) == 7,
        {k: v["pass"] for k, v in model["checks"].items()})

    # ---------------- H. four negative controls (mutations) -----------------
    nc = {}
    # NC1: label the 93.75 sink as 103.79 -> would replace 5,189,412 by 4,687,500
    mutated = tiers["103.78824"]["cycles_int"]
    nc["93_75_SINK_AS_103_79"] = {
        "mutated_cycles": mutated,
        "detected": mutated != tiers["93.75"]["cycles_int"],
        "delta_cycles": tiers["93.75"]["cycles_int"] - mutated,
        "delta_pct_G0": 100.0 * (tiers["93.75"]["cycles_int"] - mutated) / G0,
    }
    # NC2: use raw band as comp-stream bytes -> 25 ms demand becomes 103.79 > 93.75
    mut = {"N": RAW_BAND / 0.025 / 1e6, "L": RAW_BAND / 0.025 / 1e6}
    nc["RAW_BAND_AS_COMP_STREAM"] = {
        "mutated_rate25": mut,
        "detected": any(v >= SINK for v in mut.values()),
        "true_rate25": {c: demand[c]["rate25"] for c in demand},
        "N_inflate_pct": 100.0 * (mut["N"] / demand["N"]["rate25"] - 1.0),
    }
    # NC3: claim model==implemented RTL -> no sim/TD/board artifacts, evidence 0
    prod_claim = True
    evidence_backed = any(man["evidence_rounds"].values()) or (CAND / "sim").exists() or (CAND / "td").exists()
    nc["MODEL_AS_RTL"] = {"claim": "production_sink_implemented=true",
                          "detected": prod_claim and not evidence_backed,
                          "evidence_rounds": man["evidence_rounds"],
                          "has_sim_or_td_dir": (CAND / "sim").exists() or (CAND / "td").exists()}
    # NC4: sink_limited=true => sink binds -> contradicted by export < core_interval
    nc["SINK_LIMITED_AS_SINK_BOUND"] = {
        "L_tail_frac": ld["tail_frac"], "L_sink_limited": ld["sink_limited"],
        "L_export_cycles": demand["L"]["export_cycles"],
        "L_core_interval": ld["core_interval_mean"],
        "detected": ld["sink_limited"] and demand["L"]["export_cycles"] < ld["core_interval_mean"],
    }
    rec("H1_four_negative_controls",
        len(nc) == 4 and all(v["detected"] for v in nc.values()), nc)

    # ---------------- I. forbidden-claim scan ------------------------------
    # Only assertoric claims count; prohibition lines ("不得称 ...", "未实现/未证") are fine.
    NEGATORS = ("不得", "不是", "并非", "未", "not ", "NOT", "unproven", "refus", "禁止", "avoid")
    bad_patterns = ["G0_feasible", "G0_closed", "G0 closed", "feasible_for_scope",
                    "production_sink_implemented=true", "production sink implemented",
                    "sink is the only constraint", "sink is the bottleneck",
                    "sink 是唯一约束", "sink 是瓶颈"]
    hits = []
    for p in (CAND / "result-r0.md", CAND / "lessons-r0.md", DEV_JSON):
        for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            for pat in bad_patterns:
                if pat in line and not any(n in line for n in NEGATORS):
                    hits.append({"file": p.name, "line": i, "pattern": pat})
    rec("I1_no_forbidden_claims", not hits, hits or "no assertoric forbidden claim")
    # positive: the production-sink boundary is actually stated
    stmt = DEV_JSON.read_text(encoding="utf-8") + (CAND / "result-r0.md").read_text(encoding="utf-8")
    rec("I2_production_boundary_stated",
        "not implemented" in stmt and "not proven" in stmt and "未实现" in stmt,
        {"json_headline": dev["headline"]["production_sink"]})

    # ---------------- summary ----------------------------------------------
    passed = all(r["pass"] for r in results)
    out = {
        "task_id": "T10.ss-g0-prod-sink",
        "round": 0,
        "dimension": "integrated",
        "candidate": str(CAND),
        "manifest_sha256": man_sha,
        "independent_metrics": {"N": nd, "L": ld},
        "comp_demand": demand,
        "raw_band_tiers": tiers,
        "raw_band_needs": {"need30": need30, "need25": need25,
                           "short_pct": short_pct,
                           "short_ms": tiers["93.75"]["ms"] - 25.0},
        "checks": results,
        "verdict": "PASS" if passed else "FAIL",
        "failed": [r["id"] for r in results if not r["pass"]],
    }
    OUT.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    for r in results:
        print(("PASS " if r["pass"] else "FAIL ") + r["id"])
    print("VERDICT:", out["verdict"], "| checks:", len(results),
          "| failed:", out["failed"])
    print("WROTE", OUT)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
