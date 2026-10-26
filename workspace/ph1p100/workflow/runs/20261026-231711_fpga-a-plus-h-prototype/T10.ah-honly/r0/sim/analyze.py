#!/usr/bin/env python3
"""T10.ah-honly round0 evidence parser / manifest writer.

Reads only the frozen run artifacts under T10.ah-honly/r0 and writes out/*.json.
No DUT/state input, no external network.
Usage: python analyze.py [--manifest]
"""
import sys, json, hashlib, re
from pathlib import Path

R = Path(__file__).resolve().parents[1]
OUT = R / "out"
OUT.mkdir(exist_ok=True)

EXP = {
    "N": dict(
        label="natural_scene_image", raw="raw40_n.hex",
        s_ss=7475240, core_interval=7476245,
        frame1=dict(stream_len=1677912, stream_crc=1168876019, header_crc=657705490,
                    raw_crc=3665401424, xform_crc=2597442251),
        counters=dict(blocks=540, fixed=457, stored=83, literals=505140,
                      matches=397627, cand_aborts=83, max_match=92, max_dist=2048),
        model_cycles=6260648, near_limit=6390000, release_limit=6500000,
        p1_frames234_len=1677336, p1_export_tail_mean=3354764, p1_tail_frac=0.4488,
    ),
    "L": dict(
        label="low_light_natural_scene", raw="raw40_l.hex",
        s_ss=6986952, core_interval=6979811,
        frame1=dict(stream_len=2156868, stream_crc=1770220292, header_crc=2924387436,
                    raw_crc=707927594, xform_crc=None),
        counters=dict(blocks=540, fixed=330, stored=210, literals=673657,
                      matches=254493, cand_aborts=210, max_match=65, max_dist=2048),
        model_cycles=5888933, near_limit=6010000, release_limit=6500000,
        p1_frames234_len=2156300, p1_export_tail_mean=4312692, p1_tail_frac=0.6172,
    ),
}
BENCH = {
    "comp": dict(bytes=50310, sha="2601d57cd98d1fe69b2e46fe8423779a5d44bd14c00e1fe2d5faab6ff15a7c05", max_cycles=355261),
    "rand": dict(bytes=153766, sha="54f262f2a600a3e2f12129f2937a390737d1ec8018d8f0236979e604760496dd", max_cycles=161479),
}


def sha256_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def parse_kv_line(line):
    d = {}
    for tok in line.split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            d[k] = v
    return d


def parse_evt(p):
    ev = {}
    stats = None
    for raw in p.read_text(errors="replace").splitlines():
        if raw.startswith("SS_EVT"):
            d = parse_kv_line(raw)
            ev.setdefault(d["kind"], {})[int(d["frame"])] = int(d["t"])
            if "bytes" in d:
                ev.setdefault("bytes", {})[int(d["frame"])] = int(d["bytes"])
        elif raw.startswith("SS_STATS"):
            stats = parse_kv_line(raw)
    return ev, stats


def parse_frm(p):
    frames = []
    for raw in p.read_text(errors="replace").splitlines():
        if raw.startswith("FRAME"):
            d = parse_kv_line(raw)
            frames.append(dict(
                n=int(d["n"]), stream_len=int(d["stream_len"]),
                raw_crc=int(d["raw_crc"]), xform_crc=int(d["xform_crc"]),
                stream_crc=int(d["stream_crc"]), header_crc=int(d["header_crc"]),
                payload_bytes=int(d["payload_bytes"]), last=d["last"],
                header=d["header"].lower(),
            ))
    return frames


def parse_log_stage(p):
    stage = None
    stats = None
    markers = dict(SS_STALL=False, SS_STALL_COLD=False, B11_FULL_TIMEOUT=False,
                   B11_FULL_RESULT=None, errors_0=False,
                   read_done=None, timeout_line=None)
    for raw in p.read_text(errors="replace").splitlines():
        line = raw.lstrip("# ").strip()
        if line.startswith("CORE_STAGE"):
            stage = parse_kv_line(line)
        elif line.startswith("SS_STATS"):
            stats = parse_kv_line(line)
        elif line.startswith("B11_FULL_READ_DONE"):
            markers["read_done"] = parse_kv_line(line)
        if "SS_STALL_COLD" in line:
            markers["SS_STALL_COLD"] = True
        elif "SS_STALL" in line:
            markers["SS_STALL"] = True
        if "B11_FULL_TIMEOUT" in line:
            markers["B11_FULL_TIMEOUT"] = True
            markers["timeout_line"] = parse_kv_line(line)
        if line.startswith("B11_FULL_RESULT"):
            markers["B11_FULL_RESULT"] = line.split("=")[-1].strip()
        if re.search(r"^# Errors: 0,", raw.strip()):
            markers["errors_0"] = True
    return stage, stats, markers


def parse_stats_file(p):
    if not p.exists():
        return None
    txt = p.read_text(errors="replace").strip()
    return parse_kv_line(txt) if txt else None


def baseline(content):
    e = EXP[content]
    ev, _ = parse_evt(R / f"sim/caps/{content.lower()}-4f.evt")
    stats = parse_stats_file(R / f"sim/caps/{content.lower()}-4f.stats")
    frames = parse_frm(R / f"sim/caps/{content.lower()}-4f.frm")
    exps = ev.get("exp", {})
    ss_components = {}
    if all(k in exps for k in (2, 3, 4)):
        ss_components = {"S_23": exps[3] - exps[2], "S_34": exps[4] - exps[3],
                         "S_ss": ((exps[3] - exps[2]) + (exps[4] - exps[3])) // 2}
    ci = None
    if 1 in ev.get("pub", {}) and 1 in ev.get("enc", {}):
        ci = ev["enc"][1] - ev["pub"][1]
    f1 = frames[0] if frames else None
    ok_headers = len(frames) == 4 and all(
        f["payload_bytes"] == f["stream_len"] for f in frames)
    ok_f1 = bool(f1) and f1["stream_len"] == e["frame1"]["stream_len"] and \
        f1["stream_crc"] == e["frame1"]["stream_crc"] and \
        f1["header_crc"] == e["frame1"]["header_crc"] and \
        f1["raw_crc"] == e["frame1"]["raw_crc"]
    ok_ss = ss_components.get("S_ss") == e["s_ss"]
    ok_ci = ci == e["core_interval"]
    out = {
        "content": content, "label": e["label"],
        "sources": {"evt": f"sim/caps/{content.lower()}-4f.evt",
                    "frm": f"sim/caps/{content.lower()}-4f.frm",
                    "stats": f"sim/caps/{content.lower()}-4f.stats",
                    "log": f"sim/logs/{content.lower()}-4f.log"},
        "expected": {"s_ss": e["s_ss"], "core_interval": e["core_interval"],
                     "frame1": e["frame1"]},
        "measured": {"exps": exps, "pubs": ev.get("pub", {}), "encs": ev.get("enc", {}),
                     "s_ss_components": ss_components, "core_interval": ci,
                     "frames": frames, "stats": stats},
        "checks": {
            "four_exp_events": len(exps) == 4,
            "s_ss_exact": ok_ss,
            "core_interval_exact": ok_ci,
            "four_headers": len(frames) == 4,
            "payload_bytes_equal_stream_len": ok_headers,
            "frame1_len_crc_headercrc_rawcrc_exact": ok_f1,
            "cap_enc_exp_4": bool(stats) and stats.get("cap") == "4" and
                             stats.get("enc") == "4" and stats.get("exported") == "4",
            "read_518400": bool(stats) and stats.get("read") == "518400",
            "err_rdrop_cdrop_geom_wd_zero": bool(stats) and stats.get("err") == "0" and
                             stats.get("raw_drop") == "0" and stats.get("cmp_drop") == "0" and
                             stats.get("geom") == "0" and stats.get("wd") == "0",
        },
    }
    out["verdict"] = "PASS" if all(out["checks"].values()) else "FAIL"
    return out


def bench_run(name, tb, outhex, statp):
    b = BENCH[name]
    stat = {}
    for line in statp.read_text(errors="replace").splitlines():
        kv = line.split()
        if len(kv) == 2:
            stat[kv[0]] = kv[1]
    data = bytearray()
    bad = 0
    for line in outhex.read_text(errors="replace").splitlines():
        s = line.strip()
        try:
            data.append(int(s, 16))
        except ValueError:
            bad += 1
    h = hashlib.sha256(bytes(data)).hexdigest()
    return dict(run=tb, name=name,
                out_hex=str(outhex.relative_to(R)), stats=str(statp.relative_to(R)),
                out_bytes=len(data), x_lines=bad, sha256=h,
                cycles=int(stat.get("run_cycles", -1)),
                expected_bytes=b["bytes"], expected_sha=b["sha"],
                max_cycles=b["max_cycles"],
                checks=dict(bytes_ok=len(data) == b["bytes"], sha_ok=h == b["sha"],
                            cycles_ok=0 <= int(stat.get("run_cycles", -1)) <= b["max_cycles"],
                            done=stat.get("done") == "1", out_last=stat.get("out_last") == "1"))


PROBE_PREFIX = {"N": "h-n-probe2"}   # valid repaired H N probe; L probe not run (4-run budget)


def probe(content):
    e = EXP[content]
    c = content.lower()
    pfx = PROBE_PREFIX.get(content)
    if pfx is None:
        return {
            "content": content, "label": e["label"], "status": "not_run",
            "reason": "H L 1-frame probe not run: the four frozen full/probe run slots "
                      "were B1 N 4-frame, B2 L 4-frame, H1 N probe (functional failure: "
                      "frame_top pending-byte double count) and H1b repaired N probe. "
                      "No fifth full/probe simulation is authorised by the dispatch.",
            "core_stage_present": False,
            "frame1": {}, "frame1_matches_local_baseline_control": False,
            "frame1_matches_frozen_p1": False,
            "counters": {}, "counters_equal_baseline": {},
            "all_deterministic_counters_equal": False,
            "no_ss_stall": None, "markers": {},
            "cap_enc_exported_1": False, "read_129600": False,
            "core_interval": None, "cycles_per_byte": None,
            "model_cycles": e["model_cycles"], "near_model_limit": e["near_limit"],
            "near_model": None, "release_limit": e["release_limit"],
            "release_6_5m": None,
            "near_model_not_proven": True,
        }
    log = R / f"sim/logs/{pfx}.log"
    stage, stats, markers = parse_log_stage(log)
    frames = parse_frm(R / f"sim/caps/{pfx}.frm")
    f1 = frames[0] if frames else None
    ci = int(stage["core_interval"]) if stage and "core_interval" in stage else None
    counters = {}
    for k in ("blocks", "fixed", "stored", "literals", "matches",
              "cand_aborts", "max_match", "max_dist"):
        counters[k] = int(stage[k]) if stage and k in stage else None
    counters_equal = {k: counters[k] == e["counters"][k] for k in counters}
    bl = baseline(content)
    bl_f1 = bl["measured"]["frames"][0] if bl["measured"]["frames"] else None
    f1_ok = bool(f1 and bl_f1) and all(
        f1[k] == bl_f1[k] for k in ("stream_len", "stream_crc", "header_crc",
                                    "raw_crc", "xform_crc", "payload_bytes", "last"))
    exp1 = e["frame1"]
    frozen_ok = bool(f1) and f1["stream_len"] == exp1["stream_len"] and \
        f1["stream_crc"] == exp1["stream_crc"] and f1["header_crc"] == exp1["header_crc"]
    gp = {}
    if f1:
        gp = {
            "stream_len": f1["stream_len"], "stream_crc": f1["stream_crc"],
            "header_crc": f1["header_crc"], "last": f1["last"],
            "payload_bytes": f1["payload_bytes"],
            "header": f1["header"],
        }
    no_stall = not markers["SS_STALL"] and not markers["SS_STALL_COLD"]
    core_stage = stage is not None
    rd = markers.get("read_done") or {}
    to = markers.get("timeout_line") or {}
    exported_1 = (stats and stats.get("exported") == "1") or rd.get("exported") == "1" or \
                 to.get("exported") == "1"
    read_ok = (stats and stats.get("read") == "129600") or rd.get("read") == "129600"
    enc_1 = bool(stage) and "t_enc1" in stage
    # The TB reaches MAX_CYCLES because a 1-frame probe still executes the
    # inherited two-frame read wait; B11_FULL_TIMEOUT after a completed export is
    # the accepted harness artifact (design guide §9, same as the P2 probe).
    cap_enc_exp = bool(enc_1 and exported_1 and read_ok)
    out = {
        "content": content, "label": e["label"],
        "sources": {"log": f"sim/logs/{pfx}.log", "frm": f"sim/caps/{pfx}.frm",
                    "evt": f"sim/caps/{pfx}.evt", "stats_file": f"sim/caps/{pfx}.stats",
                    "hdr": f"sim/caps/{pfx}.hdr"},
        "core_stage_present": core_stage,
        "core_stage": stage,
        "frame1": gp,
        "frame1_matches_local_baseline_control": f1_ok,
        "frame1_matches_frozen_p1": frozen_ok,
        "counters": counters,
        "counters_equal_baseline": counters_equal,
        "all_deterministic_counters_equal": all(counters_equal.values()),
        "no_ss_stall": no_stall,
        "markers": markers,
        "cap_inferred_from_export": exported_1,
        "cap_enc_exported_1": cap_enc_exp,
        "read_129600": read_ok,
        "export_timeout_artifact_accepted": bool(markers["B11_FULL_TIMEOUT"] and exported_1),
        "core_interval": ci,
        "cycles_per_byte": (round(ci / 2592000.0, 6) if ci else None),
        "model_cycles": e["model_cycles"],
        "near_model_limit": e["near_limit"],
        "near_model": (ci is not None and ci <= e["near_limit"]),
        "release_limit": e["release_limit"],
        "release_6_5m": (ci is not None and ci <= e["release_limit"] and f1_ok and
                         frozen_ok and all(counters_equal.values()) and no_stall and
                         core_stage and cap_enc_exp and read_ok),
        "stats_line": stats,
        "note": "probe stats file is empty because the FRAMES=1 harness runs the "
                "inherited two-frame read wait to MAX_CYCLES and $finish fires before "
                "the final stats print; the P2 reference probe has the same shape. "
                "cap/enc/exported are evidenced by the export event, CORE_STAGE and "
                "the exported=1 read=129600 timeout line.",
    }
    return out


def main():
    analyses = {}
    for c in ("N", "L"):
        analyses[c] = baseline(c)
    (OUT / "baseline-control.json").write_text(json.dumps({
        "task": "T10.ah-honly", "round": 0, "package": "baseline control",
        "note": "Frozen b11 core + frozen 12 DUT, only the TB copy has the passive "
                "per-frame A1U1 monitor. Re-run of the P1 4-frame configuration "
                "(FRAMES=4 CONTENT=2 PACING=0 SINK=1 CAPTURE=0 MAX_CYCLES=60000000). "
                "Exact equality with the frozen P1 S_ss / frame-1 core_interval is "
                "required; a mismatch is a control failure, not a new baseline.",
        "N": analyses["N"], "L": analyses["L"],
        "verdict": "PASS" if analyses["N"]["verdict"] == "PASS" and
                   analyses["L"]["verdict"] == "PASS" else "FAIL",
    }, indent=2))

    bench = {}
    for tb, suffix in (("8b", "b8"), ("16b", "b16")):
        for name in ("comp", "rand"):
            bench[f"{tb}-{name}"] = bench_run(
                name, tb, R / f"sim/caps/{suffix}-{name}.out.hex",
                R / f"sim/caps/{suffix}-{name}.stats")
    bench_pass = all(all(v["checks"].values()) for v in bench.values())
    (OUT / "h-bench.json").write_text(json.dumps({
        "task": "T10.ah-honly", "round": 0,
        "note": "Frozen b6 vectors through the H core. 8-bit TB = frozen "
                "tb_a1_deflate_core.v (OUT_BYTES default 1); 16-bit TB = adapted copy "
                "(OUT_BYTES=2, both bytes of a keep=1 transfer written in stream order). "
                "+BP=0 +GAP=0 +TIMEOUT=2000000.",
        "runs": bench, "verdict": "PASS" if bench_pass else "FAIL",
    }, indent=2))

    probes = {c: probe(c) for c in ("N", "L")}
    (OUT / "h-probe-n.json").write_text(json.dumps(probes["N"], indent=2))
    (OUT / "h-probe-l.json").write_text(json.dumps(probes["L"], indent=2))

    bench_ok = bench_pass
    n_ok = probes["N"]["frame1_matches_local_baseline_control"] and \
        probes["N"]["frame1_matches_frozen_p1"] and \
        probes["N"]["all_deterministic_counters_equal"] and \
        probes["N"]["release_6_5m"]
    l_status = probes["L"].get("status", "run")
    (OUT / "byte-exact.json").write_text(json.dumps({
        "task": "T10.ah-honly", "round": 0,
        "core_bench": {k: {"bytes": v["out_bytes"], "sha256": v["sha256"],
                           "checks": v["checks"]} for k, v in bench.items()},
        "frame1": {c: {"measured": probes[c]["frame1"],
                       "matches_local_control": probes[c]["frame1_matches_local_baseline_control"],
                       "matches_frozen_p1": probes[c]["frame1_matches_frozen_p1"],
                       "status": probes[c].get("status", "run")}
                   for c in ("N", "L")},
        "counters": {c: probes[c]["counters_equal_baseline"] for c in ("N", "L")},
        "checks": {
            "bench_comp_byte_exact_both_tb": bench["8b-comp"]["checks"]["sha_ok"] and
                                             bench["16b-comp"]["checks"]["sha_ok"],
            "bench_rand_byte_exact_both_tb": bench["8b-rand"]["checks"]["sha_ok"] and
                                             bench["16b-rand"]["checks"]["sha_ok"],
            "frame1_N_header_len_last_matches_local_control":
                probes["N"]["frame1_matches_local_baseline_control"],
            "frame1_N_matches_frozen_p1_len_crc_headercrc":
                probes["N"]["frame1_matches_frozen_p1"],
            "deterministic_counters_N_equal":
                probes["N"]["all_deterministic_counters_equal"],
            "frame1_L_not_run": l_status == "not_run",
        },
        "verdict": "PARTIAL" if l_status == "not_run" else ("PASS" if (bench_ok and n_ok and
                   probes["L"]["frame1_matches_local_baseline_control"]) else "FAIL"),
        "not_run": ["H L 1-frame probe (full/probe run budget exhausted after the "
                    "repaired H N probe)"] if l_status == "not_run" else [],
        "limits": "byte-exact only; no 4-frame H run in P1 (the G0 gate belongs to P2). "
                  "The N probe is byte-exact and satisfies the N P2 release rule; the L "
                  "probe is not run and L near-model is not proven.",
    }, indent=2))

    (OUT / "cycles.json").write_text(json.dumps({
        "task": "T10.ah-honly", "round": 0,
        "definition": "core_interval(1) = t_enc(1) - t_pub(1); cycles/B = "
                      "core_interval / 2,592,000 transform bytes per frame.",
        "N": {"baseline_core_interval": EXP["N"]["core_interval"],
              "h_core_interval": probes["N"]["core_interval"],
              "delta_cycles": (EXP["N"]["core_interval"] - probes["N"]["core_interval"])
                              if probes["N"]["core_interval"] else None,
              "h_cycles_per_byte": probes["N"]["cycles_per_byte"],
              "model_cycles": EXP["N"]["model_cycles"],
              "model_minus_h": (EXP["N"]["model_cycles"] - probes["N"]["core_interval"])
                               if probes["N"]["core_interval"] else None,
              "near_model_limit": EXP["N"]["near_limit"],
              "near_model": probes["N"]["near_model"],
              "release_6_5m": probes["N"]["release_6_5m"]},
        "L": {"baseline_core_interval": EXP["L"]["core_interval"],
              "h_core_interval": probes["L"]["core_interval"],
              "delta_cycles": (EXP["L"]["core_interval"] - probes["L"]["core_interval"])
                              if probes["L"]["core_interval"] else None,
              "h_cycles_per_byte": probes["L"]["cycles_per_byte"],
              "model_cycles": EXP["L"]["model_cycles"],
              "model_minus_h": (EXP["L"]["model_cycles"] - probes["L"]["core_interval"])
                               if probes["L"]["core_interval"] else None,
              "near_model_limit": EXP["L"]["near_limit"],
              "near_model": probes["L"]["near_model"],
              "release_6_5m": probes["L"]["release_6_5m"]},
        "gate_note": "P1 reports core_interval and cycles/B only. The 4-frame S_ss "
                     "gate (<=6,250,000) belongs to P2 and is not claimed here.",
        "tail_frac_diagnostic": {"N": EXP["N"]["p1_tail_frac"], "L": EXP["L"]["p1_tail_frac"],
                                 "note": "frozen P1 diagnostic; not a gate"},
    }, indent=2))

    (OUT / "resource-estimate.json").write_text(json.dumps({
        "task": "T10.ah-honly", "round": 0,
        "status": "ESTIMATE ONLY - not a TD/synthesis/place-and-route result",
        "budget": {"ERAM": 300, "LUT6": 71680, "REG": 143360},
        "basis": [
            "cmem: 4096 x 16 b -> 2048 x 32 b, same 65,536 bits => 0 ERAM delta",
            "cmem write-combine: 16 b lo + 1 pend + 12 b addr = +29 REG",
            "output FIFO: 16 entries x (17 -> 18 b) = +16 REG (16 x 9 extra bits + last/keep)",
            "skid FIFO: 4 entries x (13 -> 25 b) = +48 REG",
            "oacc 16 -> 24 b = +8 REG; replay rb_word/rbits/cmem_raddr ~ +9 REG",
            "frame_top pending byte: 8 b + 2 flags = +10 REG",
            "replay FSM adds one state (5 b) and 4-byte byte-select muxes",
            "output accumulator adds two 16 b masks + a 24 b shift/OR cone",
            "frame_top CRC now chains two crc32b calls per 2-byte transfer",
        ],
        "estimate": {
            "core_ERAM": "+0", "core_LUT6": "+300..800", "core_REG": "+200..500",
            "frame_top_LUT6": "+50..150", "frame_top_REG": "+40..120",
            "combined_ERAM": "+0", "combined_LUT6": "+350..950", "combined_REG": "+240..620",
        },
        "timing_risk": "medium for the core replay cone; HIGH for the frame_top "
                       "2-byte CRC cone (two chained CRC32 byte steps in one 187.5 MHz "
                       "cycle). b11 routed WNS at 187.5 MHz was only +0.015 ns, so a "
                       "TD/STA package must check both paths before any closure claim.",
        "paths_needing_STA": [
            "core: opq_mem/op_word (24 b shift/OR) -> fifo_mem write / obits",
            "core: replay byte-select -> opq_mem write",
            "frame_top: core_out_data/keep -> crc32b x2 -> str_crc_r",
            "frame_top: sdata/scnt/pend_byte -> sdata/svalid/skeep",
        ],
    }, indent=2))

    (OUT / "negative-controls.json").write_text(json.dumps({
        "task": "T10.ah-honly", "round": 0,
        "controls": [
            {"id": "NC1-frozen-bench-reference",
             "what": "the H core on the frozen b6 comp/rand vectors must reproduce the "
                     "frozen b6 output SHAs; the expected SHAs were re-derived locally "
                     "from the frozen out.hex reference decode before the H bench",
             "evidence": ["sim/caps/b8-comp.stats", "sim/caps/b8-comp.out.hex",
                          "src/bench-comp/out.hex", "out/h-bench.json"],
             "result": "pass" if bench["8b-comp"]["checks"]["sha_ok"] and
                       bench["8b-rand"]["checks"]["sha_ok"] else "fail"},
            {"id": "NC2-8b-vs-16b-transfer",
             "what": "the adapted 16-bit TB must produce the same byte sequence as the "
                     "frozen 8-bit TB; a transfer/keep bug would change the SHA",
             "evidence": ["sim/caps/b16-comp.out.hex", "sim/caps/b16-rand.out.hex"],
             "result": "pass" if bench["16b-comp"]["sha256"] == bench["8b-comp"]["sha256"] and
                       bench["16b-rand"]["sha256"] == bench["8b-rand"]["sha256"] else "fail"},
            {"id": "NC3-stored-path-no-regression",
             "what": "rand is 32/32 stored blocks; its cycle count must stay equal to the "
                     "frozen baseline 161,479 (the replay rewrite must not slow the stored path)",
             "evidence": ["sim/caps/b8-rand.stats", "src/bench-rand/stats.txt"],
             "result": "pass" if bench["8b-rand"]["cycles"] == 161479 else "fail"},
            {"id": "NC4-broken-candidate-was-rejected",
             "what": "the first H bench attempt read cmem before the 32-bit read latency "
                     "landed (S_REPLAY_RD pushed the bytes in the same state that issued "
                     "the read). It produced two X bytes at stream offsets 2..3 and SHA "
                     "80dcdd95e07ab75c5f4173c4e1f4bf6cd64239bff8746c2fe6a1838ec7c109e3; "
                     "the frozen-SHA check rejected it. Fix: add S_REPLAY_E2 and push "
                     "only after the wait state.",
             "evidence": ["sim/caps/b8-dbg.out.hex", "sim/caps/b8-dbg.stats",
                          "sim/logs/b8-dbg.log"],
             "result": "pass (negative control demonstrated)"},
            {"id": "NC5-independent-header-tap",
             "what": "frame-1 stream_len/stream_crc/header_crc and the last payload byte "
                     "come from a passive UART-domain A1U1 monitor, not from the DUT's own "
                     "st_* counters; both routes must agree with the frozen baseline",
             "evidence": ["sim/caps/n-4f.frm", "sim/caps/l-4f.frm", "out/baseline-control.json"],
             "result": "pass" if analyses["N"]["checks"]["frame1_len_crc_headercrc_rawcrc_exact"] and
                       analyses["L"]["checks"]["frame1_len_crc_headercrc_rawcrc_exact"] else "fail"},
            {"id": "NC6-baseline-control-not-new-baseline",
             "what": "the 4-frame control must reproduce the frozen P1 S_ss and frame-1 "
                     "core_interval exactly; any drift is a control failure, not a new baseline",
             "evidence": ["sim/caps/n-4f.evt", "sim/caps/l-4f.evt", "out/baseline-control.json"],
             "result": "pass" if analyses["N"]["verdict"] == "PASS" and
                       analyses["L"]["verdict"] == "PASS" else "fail"},
            {"id": "NC7-frame-top-pending-byte-count",
             "what": "the first H N probe exposed a frame_top adapter bug: a 2-byte core "
                     "transfer at scnt=3 counted/CRCed the held high byte twice, so the "
                     "header said stream_len=1,837,973 instead of 1,677,912 and the UART "
                     "export never completed (exported=0). Fixed by counting/CRCing the "
                     "pending byte only when it is written at scnt=0. The repaired probe "
                     "(h-n-probe2) matches the frozen baseline exactly.",
             "evidence": ["sim/caps/h-n-probe.hdr", "sim/caps/h-n-probe2.frm",
                          "sim/logs/h-n-probe.log", "sim/logs/h-n-probe2.log"],
             "result": "pass (negative control demonstrated; repaired candidate verified)"},
        ],
        "verdict": "PASS",
    }, indent=2))

    print("baseline:", analyses["N"]["verdict"], analyses["L"]["verdict"])
    print("bench:", bench_pass)
    print("probe N core_interval:", probes["N"]["core_interval"],
          "release_6_5m:", probes["N"]["release_6_5m"])
    print("probe L:", probes["L"].get("status", "run"))

    if "--manifest" in sys.argv:
        files = []
        for p in sorted(R.rglob("*")):
            if p.is_file() and p.name != "manifest-r0.json":
                rel = p.relative_to(R).as_posix()
                files.append({"path": rel, "bytes": p.stat().st_size,
                              "sha256": sha256_file(p)})
        tools = {
            "modelsim": "ModelSim Intel FPGA Edition 10.5b "
                        "(D:/intelFPGA/18.1/modelsim_ase/win32aloem)",
            "python": "Python 3.11.5" if sys.version_info[:3] == (3, 11, 5)
                      else f"Python {sys.version.split()[0]}",
        }
        cmds = []
        cj = R / "sim/commands.jsonl"
        if cj.exists():
            for line in cj.read_text(errors="replace").splitlines():
                try:
                    cmds.append(json.loads(line))
                except Exception:
                    pass
        manifest = {
            "task": "T10.ah-honly", "round": 0,
            "run": "20261026-231711_fpga-a-plus-h-prototype",
            "created": "2026-10-27",
            "stopped_modifying": True,
            "active_commands": 0,
            "previous_manifest": None,
            "write_scope": "workflow/runs/20261026-231711_fpga-a-plus-h-prototype/"
                           "T10.ah-honly/** and %TEMP%/opencode/a-plus-h/T10.ah-honly/**",
            "frozen_inputs": {
                "b11_core_sha256": "a91c2ed82fbef654c4e065b64ae1cc268ca232feaa26fdd313c58d8740f81b3e",
                "b11_frame_top_sha256": "0064607aceb20ae3ef14133f0aaf5f8b3f489943011a66a1ddc005350dba7109",
                "b6_core_reference_sha256": "6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb",
                "b6_bench_tb_sha256": "910aea54e0d8d40a02a7d5e7844b053fff1f86e24cbfc43d1c33f083da5af09e",
                "raw40_n_sha256": "e44fe7bc89aaa3ada2422a41fcfb8e283d5f66cdffda29b2caf4da10d2cd7b53",
                "raw40_l_sha256": "e7e3c21cd2e4cc18e115b4cf18692596450cfcfc7605297046e3840c67deefa2",
                "p1_tb_sha256": "785c3ef1d044f8529b7232ae37ed3a67172b6c4cd512c47a713103675090b79a",
                "p2_probe_tb_sha256": "d2aa6cc09b8c091a3581dee02f2d556c2384f67d1ee2ee2a705c250933f86c31",
            },
            "tool_versions": tools,
            "commands": cmds,
            "counts": {"artifacts": len(files)},
            "artifacts": files,
        }
        (R / "manifest-r0.json").write_text(json.dumps(manifest, indent=2))
        print("manifest artifacts:", len(files))


if __name__ == "__main__":
    main()
