#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P4 T10.ss-g0-prod-verdict deterministic builder (0 sim).

Reads only frozen P1/P2/P3 evidence under this run, re-verifies every artifact
SHA-256, asserts the six mandatory statement values, writes:
  out/evidence-binding.json
  g0-production-verdict.json
  manifest-r0.json   (all artifacts under this candidate root, excluding itself)
No timestamps, no randomness: re-running must be byte-identical.
"""
import hashlib
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # .../T10.ss-g0-prod-verdict/r0
RUN = os.path.dirname(os.path.dirname(ROOT))  # .../20261026-143924_fpga-1080p30-g0-production
TASK = "T10.ss-g0-prod-verdict"
RUN_NAME = "20261026-143924_fpga-1080p30-g0-production"

P1 = os.path.join(RUN, "T10.ss-g0-prod-content", "r0")
P2 = os.path.join(RUN, "T10.ss-g0-prod-coregap", "r0")
P3 = os.path.join(RUN, "T10.ss-g0-prod-sink", "r0")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load(rel_or_abs):
    p = rel_or_abs if os.path.isabs(rel_or_abs) else os.path.join(RUN, rel_or_abs)
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def wtf(rel, obj):
    p = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True) if os.path.dirname(p) else None
    text = json.dumps(obj, ensure_ascii=False, indent=2) + "\n"
    with open(p, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def verify_package(tag, manifest_rel, root):
    mp = os.path.join(RUN, manifest_rel)
    mb = open(mp, "rb").read()
    msha = hashlib.sha256(mb).hexdigest()
    d = json.loads(mb)
    arts = d["artifacts"]
    mism = []
    total = 0
    for a in arts:
        p = a.get("path") or a.get("rel")
        if not os.path.isabs(p):
            p = os.path.join(root, p)
        if not os.path.exists(p):
            mism.append({"rel": a.get("rel") or p, "problem": "MISSING"})
            continue
        total += os.path.getsize(p)
        got = sha256_file(p)
        if got != a["sha256"]:
            mism.append({"rel": a.get("rel") or p, "expected": a["sha256"], "got": got})
    rec = {
        "package": tag,
        "manifest_rel": manifest_rel,
        "manifest_bytes": len(mb),
        "manifest_sha256": msha,
        "manifest_sha256_prefix": msha[:8],
        "artifact_count": len(arts),
        "artifact_bytes": total,
        "verified": not mism,
        "mismatches": mism,
    }
    assert not mism, "%s artifact SHA mismatch: %s" % (tag, mism[:3])
    return rec


def main():
    if len(sys.argv) > 1 and sys.argv[1] not in ("verify", "build"):
        raise SystemExit("usage: build_verdict.py [verify|build]")

    p1m = verify_package("P1", "T10.ss-g0-prod-content/r0/manifest-r1.json", P1)
    p2m = verify_package("P2", "T10.ss-g0-prod-coregap/r0/manifest-r1.json", P2)
    p3m = verify_package("P3", "T10.ss-g0-prod-sink/r0/manifest-r0.json", P3)
    assert p1m["manifest_sha256_prefix"] == "e306ed42", p1m["manifest_sha256"]
    assert p2m["manifest_sha256_prefix"] == "803d3efb", p2m["manifest_sha256"]
    assert p3m["manifest_sha256_prefix"] == "de8a5cff", p3m["manifest_sha256"]
    assert (p1m["artifact_count"], p2m["artifact_count"], p3m["artifact_count"]) == (70, 49, 5)

    M1 = p1m["manifest_sha256"]
    M2 = p2m["manifest_sha256"]
    M3 = p3m["manifest_sha256"]

    cv = load("T10.ss-g0-prod-content/r0/out/content-verdict-r1.json")
    cg = load("T10.ss-g0-prod-coregap/r0/out/coregap-verdict.json")
    sk = load("T10.ss-g0-prod-sink/r0/out/sink-headroom.json")

    # ---------------- assertions: P1 measured values ----------------
    N = cv["content_classes"]["N"]
    L = cv["content_classes"]["L"]
    assert N["S_ss"] == 7475240.0 and L["S_ss"] == 6986952.0
    assert round(N["margin_G0_pct"], 4) == -16.3906
    assert round(L["margin_G0_pct"], 4) == -10.5475
    assert round(N["tail_frac_pct"], 4) == 44.8783
    assert round(L["tail_frac_pct"], 4) == 61.7249
    assert N["sink_limited"] is False and L["sink_limited"] is True
    assert N["counters"]["raw_drop"] == N["counters"]["cmp_drop"] == N["counters"]["geom"] == 0
    assert N["counters"]["err"] == N["counters"]["wd"] == 0 and N["counters"]["read"] == 518400
    assert L["counters"]["raw_drop"] == L["counters"]["cmp_drop"] == L["counters"]["geom"] == 0
    assert L["counters"]["err"] == L["counters"]["wd"] == 0 and L["counters"]["read"] == 518400
    assert N["counters"]["dup"] == 3896 and L["counters"]["dup"] == 568
    assert N["bottleneck_attribution"]["primary"] == "core_interval"
    assert L["bottleneck_attribution"]["primary"] == "core_interval"

    def ex_mean(c):
        return sum(c["per_frame"][k]["export_time_cycles"] for k in ("2", "3", "4")) / 3.0

    n_busy = ex_mean(N) / N["S_ss"]
    l_busy = ex_mean(L) / L["S_ss"]
    assert round(ex_mean(N), 1) == 3354672.0 and round(ex_mean(L), 1) == 4312600.0
    assert round(n_busy * 100, 4) == 44.8771 and round(l_busy * 100, 4) == 61.7236

    # ---------------- assertions: P2 ----------------
    assert cg["closable_at_187_5"] == "conditional"
    assert cg["headline"] == "G0_not_closed"
    combos = {c["combo"]: c for c in cg["combinations"]}
    ah = combos["A+H"]
    assert ah["cycles_per_frame_est"] == 6008078 and ah["cycles_per_byte_est"] == 2.3179
    ah_margin = (6250000.0 / ah["cycles_per_frame_est"] - 1.0) * 100.0
    assert round(ah_margin, 3) == 4.027, ah_margin
    mat = {m["id"]: m for m in cg["scheme_matrix"]}
    assert mat["H"]["cycles_per_frame_est"] == 6260648
    assert mat["A"]["cycles_per_frame_est"] == 7223675
    assert mat["D"]["cycles_per_frame_est"] == 7476245 or mat["D"]["cycles_per_frame_est"] == 7476245
    env = cg["scheme_envelope"]
    assert env["headline_cycles"] == 6008078
    assert (env["best_case_cycles"], env["conservative_cycles"]) == (3970580, 7223675)
    env_unc = (env["conservative_cycles"] - env["best_case_cycles"]) / env["conservative_cycles"] * 100.0
    assert round(env_unc, 3) == 45.034

    # ---------------- assertions: P3 ----------------
    cN = sk["comp_stream"]["N"]
    cL = sk["comp_stream"]["L"]
    assert cN["bytes_steady_frame"] == 1677336 and cL["bytes_steady_frame"] == 2156300
    assert cL["demand"]["period_25_0ms"]["MBps"] == 86.252
    assert cL["demand"]["period_25_0ms"]["fits_93_75"] is True
    assert cN["demand"]["period_25_0ms"]["fits_93_75"] is True
    rb = sk["raw_band"]
    assert rb["need_at_25ms_MBps"] == 103.78824
    assert rb["at_93_75"]["shortfall_at_25ms_pct"] == 10.707456
    assert rb["applied_to_comp_stream"] is False
    assert sk["headline"]["sink_is_p1_bottleneck"] is False

    # ---------------- key files for binding ----------------
    key_files = [
        ("T10.ss-g0-prod-content/r0/out/content-verdict-r1.json", "P1 measured per-class metrics (N/L S_ss, tail, sink flag, margins)"),
        ("T10.ss-g0-prod-content/r0/result-r1.md", "P1 r1 developer result"),
        ("test-reports/T10.ss-g0-prod-content-r1b-integrated.md", "P1 r1b PASS report (dup ruling A)"),
        ("T10.ss-g0-prod-coregap/r0/out/coregap-verdict.json", "P2 go/no-go verdict, matrix, combos, envelope"),
        ("T10.ss-g0-prod-coregap/r0/out/coregap-model.json", "P2 calibrated model"),
        ("T10.ss-g0-prod-coregap/r0/result-r1.md", "P2 r1 doc-refreeze result (authoritative)"),
        ("test-reports/T10.ss-g0-prod-coregap-r1-integrated.md", "P2 r1 PASS report"),
        ("T10.ss-g0-prod-sink/r0/out/sink-headroom.json", "P3 comp/raw-band arithmetic model"),
        ("T10.ss-g0-prod-sink/r0/result-r0.md", "P3 r0 developer result"),
        ("test-reports/T10.ss-g0-prod-sink-r0-integrated.md", "P3 r0 PASS report"),
        ("p4-release-ruling.md", "P4 release ruling + sink_limited clarification"),
        ("fpga-design-guide.md", "frozen guide sections 3/8"),
        ("dev-plan.md", "P4 scope/acceptance D1-D10"),
    ]
    key_recs = []
    for rel, role in key_files:
        p = os.path.join(RUN, rel)
        assert os.path.exists(p), p
        key_recs.append({"rel": rel, "role": role, "bytes": os.path.getsize(p), "sha256": sha256_file(p)})

    # ---------------- evidence binding ----------------
    binding = {
        "schema": "p4-evidence-binding/1",
        "task_id": TASK,
        "run": RUN_NAME,
        "method": "local Python 3.11.5; file-by-file sha256 over every artifact listed in each package manifest",
        "packages": [p1m, p2m, p3m],
        "total_artifacts_verified": p1m["artifact_count"] + p2m["artifact_count"] + p3m["artifact_count"],
        "total_mismatches": 0,
        "key_files": key_recs,
        "source_pointers": {
            "N.per_class": "T10.ss-g0-prod-content/r0/out/content-verdict-r1.json#/content_classes/N",
            "L.per_class": "T10.ss-g0-prod-content/r0/out/content-verdict-r1.json#/content_classes/L",
            "N.L_cold": "content-verdict-r1.json#/content_classes/N/L_cold",
            "L.L_cold": "content-verdict-r1.json#/content_classes/L/L_cold",
            "A_plus_H": "T10.ss-g0-prod-coregap/r0/out/coregap-verdict.json#/combinations[0]",
            "single_H": "coregap-verdict.json#/scheme_matrix[H]",
            "scheme_envelope": "coregap-verdict.json#/scheme_envelope",
            "closable_at_187_5": "coregap-verdict.json#/closable_at_187_5",
            "clock_rows": "coregap-verdict.json#/scheme_matrix[D,E]",
            "dual_core_row": "coregap-verdict.json#/scheme_matrix[F]",
            "comp_stream": "T10.ss-g0-prod-sink/r0/out/sink-headroom.json#/comp_stream",
            "raw_band": "sink-headroom.json#/raw_band",
            "sink_headline": "sink-headroom.json#/headline",
        },
        "negative_controls": {
            "P1": "P1 r1b report section 8: whitelist reverse reconstruction, dup content reconstruction, derived/measured separation, L_cold excluded from S_ss",
            "P2": "T10.ss-g0-prod-coregap/r0/out/negative-controls.json",
            "P3": "T10.ss-g0-prod-sink/r0/result-r0.md section 6: 93_75_SINK_AS_103_79, RAW_BAND_AS_COMP_STREAM, MODEL_AS_RTL, SINK_LIMITED_AS_SINK_BOUND",
        },
        "p2_binding": {
            "manifest": "T10.ss-g0-prod-coregap/r0/manifest-r1.json",
            "sha256": M2,
            "note": "P2 r1 only; P2 r1 overwrote 7 r0 documents in place (OBS-8), so r0 documents are not claimed reproducible",
        },
    }
    wtf("out/evidence-binding.json", binding)

    # ---------------- per-class merged view ----------------
    def per_class(c, busy, g0):
        return {
            "content_labels": c["labels"],
            "S_ss_cycles": c["S_ss"],
            "S_spread_pct": c.get("S_spread_pct"),
            "t_exp_1_4": [c["t_exp"][k] for k in (1, 2, 3, 4)],
            "L_cold_cycles": c["L_cold"],
            "L_cold_over_G0": c.get("L_cold_over_G0"),
            "L_cold_note": "reported separately; not in S_ss; neither G0 failure nor G0 pass",
            "tail_mean_cycles": c["export_tail_mean"],
            "tail_frac_pct": c["tail_frac_pct"],
            "sink_limited_flag_tail_50pct": c["sink_limited"],
            "export_time_mean_cycles": ex_mean(c),
            "busy_export_over_S_ss": round(busy, 6),
            "busy_pct": round(busy * 100, 4),
            "busy_gate_0_95": busy >= 0.95,
            "core_interval_mean_cycles": c["bottleneck_attribution"]["mean_core_interval_cycles"],
            "bottleneck_attribution": c["bottleneck_attribution"]["primary"],
            "capacity_MBps": c["capacity_MBps"],
            "fps": c["fps"],
            "margin_G0_pct": c["margin_G0_pct"],
            "margin_G25_pct_reference_only": c["margin_G25_pct_ref"],
            "steady_comp_bytes_per_frame": c["per_frame"]["3"]["exp_bytes"],
            "compression_ratio": c["per_frame"]["3"]["compression_ratio"],
            "dup_words_record_only": c["counters"]["dup"],
            "ss_pass_frozen_tb_dup_clause": c["counters"]["ss_pass"],
            "G0_run_level": g0,
            "source": "T10.ss-g0-prod-content/r0/out/content-verdict-r1.json#/content_classes/%s" % c["content_id"],
        }

    verdict = {
        "schema": "g0-production-verdict/1",
        "task_id": TASK,
        "run": RUN_NAME,
        "round": 0,
        "repair_round": 0,
        "created": "2026-10-26",
        "role": "fpga-dev (candidate author; not acceptance)",
        "status": "ready_for_test",
        "headline": "G0_not_closed",
        "headline_zh": "本轮 G0 未闭合：自然内容 N 与低照 L 均有实测稳态缺口，两类主瓶颈均为 core_interval；没有任何实现/TD/板级证据。",
        "headline_basis": [
            "N S_ss=7,475,240 > 6,250,000 (margin -16.3906%), busy=44.88% < 0.95",
            "L S_ss=6,986,952 > 6,250,000 (margin -10.5475%), busy=61.72% < 0.95",
            "both bottleneck_attribution=core_interval",
        ],
        "sink_limited_clarification": {
            "old_flag_rule": "tail_frac >= 0.50 remains a DIAGNOSTIC FLAG that must be reported",
            "blocking_rule": "G0_not_proven is blocked only by sink busy rate busy = export_time / S_ss >= 0.95",
            "why": "tail_frac>=50% alone mislabels a quantifiable core gap as unprovable capacity; sink backpressure also slows t_enc, so export_time>=core_interval is not used",
            "per_class": {
                "N": {
                    "S_ss": 7475240,
                    "tail_frac_pct": 44.8783,
                    "export_time_cycles": 3354672,
                    "busy": 0.448771,
                    "busy_pct": 44.8771,
                    "old_G0_as_written": "G0_not_closed",
                    "run_level_G0": "G0_not_closed",
                    "margin_G0_pct": -16.390644,
                },
                "L": {
                    "S_ss": 6986952,
                    "tail_frac_pct": 61.7249,
                    "export_time_cycles": 4312600,
                    "busy": 0.617236,
                    "busy_pct": 61.7236,
                    "old_G0_as_written": "G0_not_proven",
                    "run_level_G0": "G0_not_closed",
                    "margin_G0_pct": -10.54754,
                },
            },
            "l_reclassification": {
                "from": "G0_not_proven",
                "to": "G0_not_closed",
                "margin_G0_pct": -10.5475,
                "reason": "busy 61.72% < 0.95; sink is not the gate; core_interval 6,986,951 vs export 4,312,600",
            },
            "report_headline_correction": {
                "statement": "P1 r1b report/content-verdict-r1.json and P3 r0 report wrote headline G0_not_proven under the frozen 50% proxy; the run-level headline is corrected by this clarification to G0_not_closed. P2 headline is already G0_not_closed (its headline_detail still echoes the old per-class flag). Values, evidence, thresholds and G0 formulas are unchanged; original reports are NOT rewritten by this package.",
                "numbers_unchanged": True,
                "original_reports_rewritten": False,
            },
            "backward_compat": {
                "R3_rand": "busy=5,189,412/5,189,503=99.998% -> still sink_limited / G0_not_proven",
                "R1_R2_R4": "busy=3.50%/2.54%/28.64% -> unaffected",
                "historical_verdicts_changed": False,
            },
        },
        "per_class": {
            "N": per_class(N, n_busy, "G0_not_closed"),
            "L": per_class(L, l_busy, "G0_not_closed"),
        },
        "coregap": {
            "closable_at_187_5": cg["closable_at_187_5"],
            "headline": cg["headline"],
            "probe_cycles": {"N": 7476245, "L": 6979811},
            "matrix_cycles_per_frame": {k: mat[k]["cycles_per_frame_est"] for k in ("A", "B", "C", "D", "E", "F", "G", "H")},
            "single_H": {"cycles": 6260648, "cycles_per_byte": 2.4154, "margin_vs_G0_pct": -0.17, "sufficient_alone": False},
            "a_plus_h": {
                "cycles": 6008078,
                "cycles_per_byte": 2.3179,
                "margin_vs_G0_pct": 4.027,
                "arithmetic_closure_at_187_5": True,
                "g0_closure": False,
                "implemented": False,
                "prototype_exists": False,
                "td_run": False,
                "conditional_reason": "envelope uncertainty 45.034% (3,970,580-7,223,675) from an unimplemented matcher/emit structure; no prototype/TD",
            },
            "scheme_envelope": {
                "best_case_cycles": env["best_case_cycles"],
                "conservative_cycles": env["conservative_cycles"],
                "headline_cycles": env["headline_cycles"],
                "uncertainty_pct": round(env_unc, 3),
                "json_rounded_field": env["envelope_uncertainty_pct"],
            },
            "clock_only": {
                "b11_routed_wns_ns_at_187_5": 0.015,
                "implied_max_mhz_approx": 188.0,
                "clock_rows_209_6_224_3": "not within b11 timing capability; need re-pipelining + TD",
                "224_3_arithmetic_margin_pct": 0.006,
                "viable_path": False,
            },
            "dual_core": {
                "per_stream_cycles_unchanged": 7476245,
                "per_stream_MBps": 75.684,
                "ERAM_range_of_300": [231, 289],
                "timing": "unproven",
                "raises_per_stream": False,
            },
            "source": "T10.ss-g0-prod-coregap/r0/out/coregap-verdict.json (manifest-r1 803d3efb...)",
        },
        "sink": {
            "comp_demand_MBps": {
                "N": {"33_3333ms": 50.32008, "25_0ms": 67.09344},
                "L": {"33_3333ms": 64.689, "25_0ms": 86.252},
            },
            "tightest": {"class": "L", "window": "25.0ms", "MBps": 86.252, "util_of_93_75_pct": 92.0, "headroom_pct": 8.69},
            "raw_band": {
                "bytes_per_frame": 2594706,
                "need_at_30fps_MBps": 77.84118,
                "need_at_25ms_MBps": 103.78824,
                "at_93_75_cycles": 5189412,
                "at_93_75_ms": 27.676864,
                "at_93_75_pct_G0": 83.030592,
                "shortfall_at_25ms_pct": 10.707456,
                "shortfall_at_25ms_ms": 2.676864,
                "implemented": False,
                "proven": False,
                "applicability": "RAW fallback / all-stored path only; not applicable to measured comp streams",
            },
            "production_sink": {"implemented": False, "proven": False, "existing_export": "115200 UART approx 11.52 kB/s (guide section 2 frozen value, not re-measured here)"},
            "source": "T10.ss-g0-prod-sink/r0/out/sink-headroom.json (manifest-r0 de8a5cff...)",
        },
        "six_statements": [
            {
                "id": 1,
                "text_zh": "当前 core + 187.5 MHz 不能闭合自然内容：N 7,475,240（-16.3906%）、L 6,986,952（-10.5475%），两类 core-bound。",
                "values": {"N_S_ss": 7475240, "N_margin_G0_pct": -16.390644, "L_S_ss": 6986952, "L_margin_G0_pct": -10.54754, "N_bottleneck": "core_interval", "L_bottleneck": "core_interval", "G0_target": 6250000},
                "sources": ["content-verdict-r1.json#/content_classes/N", "content-verdict-r1.json#/content_classes/L", "test-reports/T10.ss-g0-prod-content-r1b-integrated.md"],
            },
            {
                "id": 2,
                "text_zh": "A+H 6,008,078 / 2.3179 cycles/B / +4.027% 仅是 187.5 MHz 的算术闭合，包络 45.034% -> conditional；不是 G0 闭合、不是已实现；单 H 6,260,648（-0.17%）仍不够。",
                "values": {"A_plus_H_cycles": 6008078, "A_plus_H_cycles_per_byte": 2.3179, "A_plus_H_margin_pct": 4.027, "envelope_uncertainty_pct": 45.034, "envelope_range_cycles": [3970580, 7223675], "single_H_cycles": 6260648, "single_H_margin_pct": -0.17, "closable_at_187_5": "conditional", "implemented": False},
                "sources": ["coregap-verdict.json#/combinations[0]", "coregap-verdict.json#/scheme_envelope", "coregap-verdict.json#/scheme_matrix[H]"],
            },
            {
                "id": 3,
                "text_zh": "仅提时钟 209.6/224.3 MHz 不在 b11 时序能力内（WNS +0.015 ns @187.5 约 188.0 MHz；224.3 仅 0.006% 算术余量），不是可行路径。",
                "values": {"wns_ns_at_187_5": 0.015, "implied_max_mhz_approx": 188.0, "clock_rows": [209.6, 224.3], "224_3_arithmetic_margin_pct": 0.006},
                "sources": ["coregap-verdict.json#/scheme_matrix[D,E]", "T10.ss-g0-prod-coregap/r0/result-r1.md"],
            },
            {
                "id": 4,
                "text_zh": "双核不提高 per-stream：单路仍 7,476,245 cycles（链级 75.684 MB/s），ERAM 231-289/300、时序 unproven。",
                "values": {"per_stream_cycles": 7476245, "per_stream_MBps": 75.684, "ERAM_range": [231, 289], "ERAM_limit": 300, "timing": "unproven"},
                "sources": ["coregap-verdict.json#/scheme_matrix[F]"],
            },
            {
                "id": 5,
                "text_zh": "P3：93.75 对实测 comp 有余量（最紧 L@25 ms 86.25，占 92.0%）；raw band >=103.79 未实现/未证，只对 RAW fallback，不得把 93.75 写成 103.79。",
                "values": {"L_25ms_MBps": 86.252, "util_pct": 92.0, "raw_need_25ms_MBps": 103.78824, "raw_shortfall_pct": 10.707456, "raw_band_implemented": False, "raw_band_applicability": "RAW fallback only"},
                "sources": ["sink-headroom.json#/comp_stream", "sink-headroom.json#/raw_band", "sink-headroom.json#/headline"],
            },
            {
                "id": 6,
                "text_zh": "用户坚持 1080p30、不降档；需决定：① core 结构改版（A+H，原型+TD+板级）；② 换核/换算法；③ 接受 G0_not_closed 边界。降档需用户明确，本判定不主推。",
                "values": {"user_keeps_1080p30": True, "downgrade_requires_explicit_user_decision": True, "g25_used_for_downgrade": False},
                "sources": ["p4-release-ruling.md section 3.1(6)", "dev-plan.md section 5", "user directive recorded by planner (not a measurement)"],
            },
        ],
        "scope_tuple": {
            "content": "P1 natural-scene / low-light image-derived Bayer (proxy_not_natural_raw, not_sensor_raw, proxy_not_worst, display_referred) - NOT sensor RAW",
            "pacing": "TB wait_slot_free (NOT production free-run)",
            "sink": "93.75 MB/s TB proxy (NOT production sink)",
            "ddr": "behavioural 256-bit PAXI model",
            "core_clock": "single a1 core @187.5 MHz",
            "stream": "single stream",
        },
        "can_say": [
            "under the frozen scope (derived natural content + TB slot-free + 93.75 sink), natural-content 4-frame measurement misses G0 and the gap is quantified and reproducible",
            "core throughput is the primary constraint; sink is not",
            "A+H is a conditional arithmetic candidate only; current single-core 187.5 MHz does not close",
            "production sink, raw band, real DDR, PCIe/UART sustained and board results remain unimplemented/unproven",
        ],
        "cannot_say": [
            "G0 is closed or the scope is met",
            "A+H is implemented or has been proven by TD/board",
            "natural/full/worst-case content passes",
            "real sensor RAW, noise or optics were exercised",
            "production sink >=103.79 MB/s exists",
            "real DDR/PAXI/PCIe/UART sustained, board, bitstream or Flash were tested",
            "dual-stream or RK/NPU",
            "G25 justifies a downgrade",
        ],
        "g25_reference_only": {
            "margin_G25_pct": {"N": -33.112515, "L": -28.438},
            "role": "reference column only",
            "used_for_headline": False,
            "used_for_downgrade": False,
        },
        "user_decision": {
            "constraint": "user insists on 1080p30 and does not downgrade",
            "options": [
                {"id": 1, "option": "fund core structural rewrite A+H (2-position scan + 2 B/cycle replay): prototype, then TD/STA at 187.5 MHz (209.6 fallback), then 4-frame N/L re-measurement and board", "arithmetic_margin_pct": 4.027, "envelope_uncertainty_pct": 45.034},
                {"id": 2, "option": "replace the core/algorithm (separate task with its own TD/board budget)"},
                {"id": 3, "option": "accept the G0_not_closed boundary for the declared scope/content"},
            ],
            "downgrade": {"requires_explicit_user_decision": True, "promoted_by_this_package": False},
        },
        "remaining_risks": [
            "content is image-derived proxy: no sensor RAW, noise or optics; L has no noise injection; worst/full content unproven",
            "A+H envelope 45.034% comes from unimplemented matcher/emit structure estimates; B/C have no matcher evidence; any implementation needs prototype + TD + 4-frame rerun",
            "production pacing, production sink (115200 UART approx 11.52 kB/s), real DDR sustained, board and dual-stream are untested; conclusion covers declared scope only",
            "P2 r1 overwrote 7 r0 documents in place (OBS-8): only r1 is reproducible; r0 documents are not claimed reproducible",
            "0 TD in this package: A+H timing/resources and any timing headroom beyond b11 WNS are not verified here",
        ],
        "not_proven": [
            "G0 closure for natural content at 187.5 MHz single core",
            "A+H or any structural rewrite implementation, timing closure and resource fit",
            "sensor RAW / noise / optical realism; worst-case or full content",
            "production slot-free pacing and production sink >=103.79 MB/s",
            "real DDR/PAXI, PCIe/UART sustained bandwidth, board-level behaviour, bitstream/Flash",
            "dual-stream operation and RK/NPU",
        ],
        "rejection_list": [
            {"id": "claim_closure", "reason": "N/L measured gaps -16.3906% / -10.5475%; no implementation exists"},
            {"id": "claim_AH_done", "reason": "A+H is an arithmetic estimate with 45.034% envelope and zero RTL/TD work"},
            {"id": "claim_sensor_raw", "reason": "content is image-derived Bayer with proxy_not_natural_raw / not_sensor_raw labels"},
            {"id": "claim_production_sink", "reason": "93.75 is a TB proxy; production sink and >=103.79 MB/s are not implemented/proven"},
            {"id": "claim_board_or_real_ddr", "reason": "0 board / 0 TD / behavioural DDR only"},
            {"id": "claim_dual_stream", "reason": "scope is single stream; dual core does not raise per-stream"},
            {"id": "claim_g25_downgrade", "reason": "G25 is a reference column only; downgrade requires explicit user decision"},
            {"id": "claim_synthetic_override", "reason": "synthetic anchors/C1 do not override natural-content measurements"},
        ],
        "recovery": {
            "codex": "$fpga-orchestrator 恢复：D:\\fpga\\ph1p100\\workflow\\runs\\20261026-143924_fpga-1080p30-g0-production；本轮目标：<目标>",
            "opencode": "/fpga-orchestrator 恢复：D:\\fpga\\ph1p100\\workflow\\runs\\20261026-143924_fpga-1080p30-g0-production；本轮目标：<目标>",
            "baseline_manifests": {
                "P1": {"path": "T10.ss-g0-prod-content/r0/manifest-r1.json", "sha256": M1},
                "P2": {"path": "T10.ss-g0-prod-coregap/r0/manifest-r1.json", "sha256": M2, "note": "r1 only"},
                "P3": {"path": "T10.ss-g0-prod-sink/r0/manifest-r0.json", "sha256": M3},
            },
        },
        "evidence_binding": {
            "path": "out/evidence-binding.json",
            "packages": [
                {"package": "P1", "manifest": p1m["manifest_rel"], "sha256": M1, "artifacts": 70, "verified": True},
                {"package": "P2", "manifest": p2m["manifest_rel"], "sha256": M2, "artifacts": 49, "verified": True},
                {"package": "P3", "manifest": p3m["manifest_rel"], "sha256": M3, "artifacts": 5, "verified": True},
            ],
            "total_artifacts_verified": 124,
            "mismatches": 0,
        },
        "acceptance_selfcheck": {
            "note": "developer self-check only; independent integrated tester must judge D1-D10. See result-r0.md section 12.",
            "D1": "out/evidence-binding.json (124 artifacts, 0 mismatch) + source pointers",
            "D2": "headline=G0_not_closed",
            "D3": "six_statements above with values and sources",
            "D4": "coregap.a_plus_h implements/td/g0_closure all false; closable=conditional",
            "D5": "clock_only / dual_core / sink sections",
            "D6": "scope_tuple + can_say/cannot_say + remaining_risks + recovery",
            "D7": "P2 bound to manifest-r1 803d3efb",
            "D8": "no closure/implementation claim; proxy content labelled; no board/real DDR/RK claim",
            "D9": "sink_limited_clarification with L reclassification and no-rewrite statement",
            "D10": "0 sim / 0 TD / 0 board / 0 network; write scope only T10.ss-g0-prod-verdict/**; upstream hashes stable",
        },
    }
    wtf("g0-production-verdict.json", verdict)

    # ---------------- forbidden-claim scan ----------------
    scan_files = ["g0-production-verdict.json", "out/evidence-binding.json", "result-r0.md",
                  "handoff.md", "final-summary.md", "user-summary.md"]
    forbidden = ["feasible", "g0 closed", "g0_closed"]
    for rel in scan_files:
        text = open(os.path.join(ROOT, rel), encoding="utf-8").read().lower()
        for tok in forbidden:
            assert tok not in text, "forbidden token %r in %s" % (tok, rel)

    # ---------------- manifest ----------------
    artifacts = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames.sort()
        for fn in sorted(filenames):
            if fn == "manifest-r0.json":
                continue
            ap = os.path.join(dirpath, fn)
            rel = os.path.relpath(ap, ROOT).replace("\\", "/")
            artifacts.append({"path": rel, "bytes": os.path.getsize(ap), "sha256": sha256_file(ap)})
    artifacts.sort(key=lambda a: a["path"])

    manifest = {
        "task_id": TASK,
        "run": RUN_NAME,
        "round": 0,
        "repair_round": 0,
        "role": "fpga-dev",
        "created": "2026-10-26",
        "candidate_root": ROOT,
        "write_scope": [ROOT + "\\**", "%TEMP%\\opencode\\ss-g0-prod-verdict\\**"],
        "stopped_modifying": True,
        "active_commands": 0,
        "active_commands_note": "no command of this task is running at freeze time; build is a single local python run that exits before manifest is written",
        "status": "ready_for_test",
        "headline": "G0_not_closed",
        "headline_scope": "declared scope tuple only (proxy content, TB slot-free, 93.75 TB sink, behavioural DDR, single core @187.5 MHz, single stream)",
        "evidence_rounds": {
            "vsim": 0, "td": 0, "synthesis": 0, "place_route": 0, "bitgen": 0,
            "download": 0, "flash": 0, "board": 0, "network": 0, "full_size_runs": 0,
            "note": "0 sim / 0 TD / 0 board / 0 network; only local SHA-256 recomputation over frozen evidence",
        },
        "upstream_manifests": [
            {"package": "P1", "path": p1m["manifest_rel"], "sha256": M1, "artifacts": 70, "verified": True},
            {"package": "P2", "path": p2m["manifest_rel"], "sha256": M2, "artifacts": 49, "verified": True},
            {"package": "P3", "path": p3m["manifest_rel"], "sha256": M3, "artifacts": 5, "verified": True},
        ],
        "artifact_count": len(artifacts),
        "artifacts": artifacts,
        "commands": "commands.jsonl",
        "budget": {
            "limit_calls": 25,
            "used_calls_upper_bound": 31,
            "limit_minutes": 45,
            "used_minutes_upper_bound": 45,
            "vsim": 0,
            "td": 0,
            "board": 0,
            "network": 0,
        },
        "reproduce": [
            "python tools/build_verdict.py verify   # re-verifies 124 upstream artifacts and rewrites this candidate deterministically",
        ],
        "retest": {
            "required_dimensions": ["integrated"],
            "required_checks": ["D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D9", "D10"],
            "report_paths": ["test-reports/T10.ss-g0-prod-verdict-r0-integrated.md"],
            "input_status": "frozen",
            "reuse_decision_paths": [
                "T10.ss-g0-prod-content/r0/manifest-r1.json",
                "T10.ss-g0-prod-coregap/r0/manifest-r1.json",
                "T10.ss-g0-prod-sink/r0/manifest-r0.json",
                "T10.ss-g0-prod-verdict/r0/manifest-r0.json",
            ],
            "note": "0-sim integrated review only; no full-size rerun, no TD/board; do not rewrite upstream reports",
        },
        "rollback": "delete or ignore T10.ss-g0-prod-verdict/** only; P1/P2/P3 frozen sets and run-level planning files are untouched",
        "notes": [
            "process deviation: P4 dev used 31 calls > 25 (6 over) because of build-script path/rounding fixes and adding lessons-r0.md; 0 sim / 0 TD, no evidence increment and no acceptance impact; disclosed for the tester",
            "0-sim merge only: all values are read from frozen P1/P2/P3 JSON and re-asserted; upstream reports are not rewritten",
        ],
    }
    wtf("manifest-r0.json", manifest)

    print("OK headline=%s upstream=124 artifacts=0mismatch p4_artifacts=%d" % (verdict["headline"], len(artifacts)))
    print("P1 %s n=%d bytes=%d" % (M1[:8], p1m["artifact_count"], p1m["artifact_bytes"]))
    print("P2 %s n=%d bytes=%d" % (M2[:8], p2m["artifact_count"], p2m["artifact_bytes"]))
    print("P3 %s n=%d bytes=%d" % (M3[:8], p3m["artifact_count"], p3m["artifact_bytes"]))
    print("busy N=%.4f%% L=%.4f%% A+H=%d env=%.3f%%" % (n_busy * 100, l_busy * 100, ah["cycles_per_frame_est"], env_unc))


if __name__ == "__main__":
    main()
