#!/usr/bin/env python3
"""Independent tester evidence checks for T10.ah-honly r0 (read-only).

- baseline control N/L: recompute S_ss / frame-1 core_interval from the raw
  SS_EVT files, compare with the frozen P1 values; check 4 per-frame headers.
- H core bench: decode OUT hex independently, SHA-256, size, cycles; decode the
  zlib member with the Python stdlib decoder and compare with the bench input.
- H N probe: recompute core_interval, compare frame-1 header fields and
  deterministic counters with the frozen baseline; scan the log for markers.
- H L probe: confirm not_run.
- budget: count full/probe and bench vsim runs from the manifest commands.
"""
import hashlib
import json
import os
import re
import sys
import zlib

RUN = r"D:/fpga/ph1p100/workflow/runs/20261026-231711_fpga-a-plus-h-prototype"
R0 = os.path.join(RUN, "T10.ah-honly", "r0")
OUT = os.path.join(RUN, "test-reports", "T10.ah-honly", "verify-caps-result.json")
res = {}


def sha(b):
    return hashlib.sha256(b).hexdigest()


def read_text(p):
    with open(p, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def parse_evt(p):
    t = {}
    for line in read_text(p).splitlines():
        m = re.match(r"SS_EVT t=(\d+) kind=(\w+) frame=(\d+)", line)
        if m:
            t.setdefault(m.group(2), []).append((int(m.group(3)), int(m.group(1))))
    return t


def parse_frm(p):
    frames = []
    for line in read_text(p).splitlines():
        if not line.startswith("FRAME "):
            continue
        d = dict(kv.split("=", 1) for kv in line.split()[1:])
        for k in ("n", "stream_len", "raw_crc", "xform_crc", "stream_crc",
                  "header_crc", "payload_bytes"):
            d[k] = int(d[k])
        frames.append(d)
    return frames


def parse_hdr(p):
    """Parse the raw 44-byte header capture + last-byte file (hex dump)."""
    raw = read_text(p).strip()
    return raw


def stats_kv(p):
    d = {}
    for line in read_text(p).splitlines():
        parts = line.split()
        if len(parts) == 2:
            d[parts[0]] = parts[1]
    return d


def decode_out_hex(p):
    out = bytearray()
    with open(p, "r", encoding="ascii", newline="") as f:
        for line in f:
            s = line.strip()
            if not s:
                continue
            if len(s) != 2:
                raise ValueError(f"{p}: unexpected line {s!r}")
            if not re.fullmatch(r"[0-9a-fA-F]{2}", s):
                raise ValueError(f"{p}: non-hex line {s!r} (X?)")
            out.append(int(s, 16))
    return bytes(out)


def decode_in_hex(p):
    return decode_out_hex(p)


# ---------- 1. baseline control ----------
FROZEN = {
    "N": {"s_ss": 7475240, "core_interval": 7476245,
          "frame1": {"stream_len": 1677912, "stream_crc": 1168876019,
                     "header_crc": 657705490, "raw_crc": 3665401424,
                     "xform_crc": 2597442251, "last": "1b"}},
    "L": {"s_ss": 6986952, "core_interval": 6979811,
          "frame1": {"stream_len": 2156868, "stream_crc": 1770220292,
                     "header_crc": 2924387436, "raw_crc": 707927594,
                     "xform_crc": 2647552023, "last": "66"}},
}
base = {}
for c in ("N", "L"):
    evt = parse_evt(os.path.join(R0, "sim", "caps", f"{c.lower()}-4f.evt"))
    fr = parse_frm(os.path.join(R0, "sim", "caps", f"{c.lower()}-4f.frm"))
    st = stats_kv(os.path.join(R0, "sim", "caps", f"{c.lower()}-4f.stats"))
    exps = dict(evt["exp"])
    pubs = dict(evt["pub"])
    encs = dict(evt["enc"])
    s23 = exps[3] - exps[2]
    s34 = exps[4] - exps[3]
    s_ss = (s23 + s34) / 2
    ci = encs[1] - pubs[1]
    fz = FROZEN[c]
    hdr_ok = all(
        (int(f["header"][44:52], 16) == f["stream_len"]) and
        (int(f["header"][24:32], 16) == f["stream_len"]) and
        (int(f["header"][72:80], 16) == f["stream_crc"]) and
        (int(f["header"][80:88], 16) == f["header_crc"])
        for f in fr) if fr else False
    base[c] = {
        "s_ss": s_ss, "s23": s23, "s34": s34, "core_interval": ci,
        "s_ss_exact": s_ss == fz["s_ss"],
        "core_interval_exact": ci == fz["core_interval"],
        "four_exp": len(exps) == 4, "four_frames": len(fr) == 4,
        "frame1_len_crc_headercrc_rawcrc_exact":
            fr and fr[0]["stream_len"] == fz["frame1"]["stream_len"]
            and fr[0]["stream_crc"] == fz["frame1"]["stream_crc"]
            and fr[0]["header_crc"] == fz["frame1"]["header_crc"]
            and fr[0]["raw_crc"] == fz["frame1"]["raw_crc"]
            and fr[0]["xform_crc"] == fz["frame1"]["xform_crc"]
            and fr[0]["last"] == fz["frame1"]["last"],
        "payload_bytes_eq_len": all(f["payload_bytes"] == f["stream_len"] for f in fr),
        "header_bytes_consistent_with_fields": hdr_ok,
        "stats_cap_enc_exp4": st.get("cap") == "4" and st.get("enc") == "4"
            and st.get("exported") == "4",
        "stats_read_518400": st.get("read") == "518400",
        "stats_err_zero": all(st.get(k) == "0" for k in
                              ("raw_drop", "cmp_drop", "geom", "err", "wd")),
        "stats_dup": st.get("dup"),
        "frames": [{k: f[k] for k in ("n", "stream_len", "stream_crc",
                                     "header_crc", "raw_crc", "last")} for f in fr],
        "exps": exps, "pubs": pubs, "encs": encs,
    }
res["baseline_control"] = base

# ---------- 2. H core bench ----------
bench = {}
for name, cap, vec, exp_sha, exp_bytes, lim in (
        ("8b-comp", "b8-comp", "comp", "2601d57cd98d1fe69b2e46fe8423779a5d44bd14c00e1fe2d5faab6ff15a7c05", 50310, 355261),
        ("8b-rand", "b8-rand", "rand", "54f262f2a600a3e2f12129f2937a390737d1ec8018d8f0236979e604760496dd", 153766, 161479),
        ("16b-comp", "b16-comp", "comp", "2601d57cd98d1fe69b2e46fe8423779a5d44bd14c00e1fe2d5faab6ff15a7c05", 50310, 355261),
        ("16b-rand", "b16-rand", "rand", "54f262f2a600a3e2f12129f2937a390737d1ec8018d8f0236979e604760496dd", 153766, 161479)):
    outp = os.path.join(R0, "sim", "caps", f"{cap}.out.hex")
    stp = os.path.join(R0, "sim", "caps", f"{cap}.stats")
    data = decode_out_hex(outp)
    st = stats_kv(stp)
    inp = decode_in_hex(os.path.join(R0, "src", "bench-" + vec, "in.hex"))
    entry = {"bytes": len(data), "sha256": sha(data),
             "sha_ok": sha(data) == exp_sha, "bytes_ok": len(data) == exp_bytes,
             "cycles": int(st["run_cycles"]),
             "cycles_ok": int(st["run_cycles"]) <= lim,
             "done": st.get("done") == "1", "out_last": st.get("out_last") == "1",
             "timeout_hit": st.get("timeout_hit") == "0",
             "in_bytes": int(st["in_bytes"]), "in_hex_decoded": len(inp)}
    try:
        dec = zlib.decompress(data)
        entry["zlib_decode_bytes"] = len(dec)
        entry["zlib_decode_matches_input"] = dec == inp
        entry["zlib_decode_sha"] = sha(dec)
    except Exception as e:  # noqa: BLE001
        entry["zlib_decode_error"] = repr(e)
    bench[name] = entry
bench["8b_vs_16b_shas_equal"] = (
    bench["8b-comp"]["sha256"] == bench["16b-comp"]["sha256"]
    and bench["8b-rand"]["sha256"] == bench["16b-rand"]["sha256"])
res["bench"] = bench

# ---------- 3. H N probe ----------
logp = os.path.join(R0, "sim", "logs", "h-n-probe2.log")
log = read_text(logp)
evt = parse_evt(os.path.join(R0, "sim", "caps", "h-n-probe2.evt"))
fr = parse_frm(os.path.join(R0, "sim", "caps", "h-n-probe2.frm"))
m = re.search(r"CORE_STAGE t=(\d+) exp_bytes=(\d+) blocks=(\d+) fixed=(\d+) stored=(\d+) "
              r"literals=(\d+) matches=(\d+) cand_aborts=(\d+) stall=(\d+) max_match=(\d+) "
              r"max_dist=(\d+) t_pub1=(\d+) t_enc1=(\d+) core_interval=(\d+) "
              r"replay_cycles=(\d+) replay_stall=(\d+) fifo_max=(\d+) out_valid_cycles=(\d+) "
              r"core_ready_low=(\d+) core_stall=(\d+) svalid_wait=(\d+) xfer2=(\d+) "
              r"total_cycles=(\d+)", log)
core = None
if m:
    keys = ["t", "exp_bytes", "blocks", "fixed", "stored", "literals", "matches",
            "cand_aborts", "stall", "max_match", "max_dist", "t_pub1", "t_enc1",
            "core_interval", "replay_cycles", "replay_stall", "fifo_max",
            "out_valid_cycles", "core_ready_low", "core_stall", "svalid_wait",
            "xfer2", "total_cycles"]
    core = {k: int(v) for k, v in zip(keys, m.groups())}
encs = dict(evt["enc"])
pubs = dict(evt["pub"])
exps = dict(evt["exp"])
ci = encs[1] - pubs[1]
BASE_N_COUNTERS = {"blocks": 540, "fixed": 457, "stored": 83, "literals": 505140,
                   "matches": 397627, "cand_aborts": 83, "max_match": 92,
                   "max_dist": 2048}
probe = {
    "core_stage_present": core is not None,
    "core_interval_from_evt": ci,
    "core_interval_matches_core_stage": core is not None and core["core_interval"] == ci,
    "cycles_per_byte": ci / 2592000.0,
    "near_model_N_6390000": ci <= 6390000,
    "release_N_6500000": ci <= 6500000,
    "frame1": fr[0] if fr else None,
    "frame1_matches_base_N": bool(fr) and all(
        fr[0][k] == base["N"]["frames"][0][k]
        for k in ("stream_len", "stream_crc", "header_crc", "raw_crc", "last")),
    "counters": {k: (core[k] if core else None) for k in BASE_N_COUNTERS},
    "counters_equal_baseline": core is not None and all(
        core[k] == v for k, v in BASE_N_COUNTERS.items()),
    "exp_events": len(exps), "export_bytes": exps.get(1),
    "markers_SS_STALL": "SS_STALL" in log,
    "markers_SS_STALL_COLD": "SS_STALL_COLD" in log,
    "markers_B11_FULL_TIMEOUT": "B11_FULL_TIMEOUT" in log,
    "exported_1_read_129600_timeout_line":
        bool(re.search(r"B11_FULL_TIMEOUT cycles=\d+ exported=1 read=129600", log)),
    "read_done_line": re.findall(r"B11_FULL_READ_DONE[^\n]*", log),
    "read_evt_129600": evt.get("read") == [(1, evt["read"][0][1])] if evt.get("read") else False,
    "no_x_in_log": not re.search(r"\bX{2,}\b", log),
    "errors_line": re.findall(r"# Errors: \d+, Warnings: \d+", log),
    "core": core,
}
res["probe_N"] = probe

# failed first probe evidence
flog = read_text(os.path.join(R0, "sim", "logs", "h-n-probe.log"))
res["probe_N_first_failed"] = {
    "frame_hdr_line": re.findall(r"# FRAME_HDR[^\n]*", flog),
    "exported_0": bool(re.search(r"B11_FULL_TIMEOUT cycles=\d+ exported=0", flog)),
    "core_stage_present": "CORE_STAGE" in flog,
}

# ---------- 4. H L probe not run ----------
hp = os.path.join(R0, "out", "h-probe-l.json")
hj = json.load(open(hp, "r", encoding="utf-8"))
res["probe_L"] = {"status": hj.get("status"), "near_model_not_proven": hj.get("near_model_not_proven"),
                  "caps_l_probe_exists": os.path.exists(os.path.join(R0, "sim", "caps", "h-l-probe.evt"))}

# ---------- 5. budget from manifest commands ----------
man = json.load(open(os.path.join(R0, "manifest-r0.json"), "r", encoding="utf-8"))
tp = [c for c in man["commands"] if os.path.basename(c["argv"][0]).lower() == "vsim.exe"]
full = [c for c in tp if "tb_ss_4run" in c["argv"]]
bench_cmds = [c for c in tp if "tb_a1_deflate_core" in c["argv"]]
res["budget"] = {
    "vsim_total": len(tp),
    "full_probe_runs": [{"note": c["note"], "seconds": c["seconds"], "rc": c["rc"]} for c in full],
    "full_probe_count": len(full),
    "full_probe_wall_s": sum(c["seconds"] for c in full),
    "bench_runs": [{"note": c["note"], "seconds": c["seconds"], "rc": c["rc"]} for c in bench_cmds],
    "bench_count": len(bench_cmds),
    "bench_wall_s": sum(c["seconds"] for c in bench_cmds),
    "bench_max_single_s": max((c["seconds"] for c in bench_cmds), default=0),
    "all_rc_zero": all(c["rc"] == 0 for c in man["commands"]),
    "timeouts": [c["note"] for c in man["commands"] if c.get("timed_out")],
    "command_count": len(man["commands"]),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(res, f, indent=2)

def show(k, v):
    print(f"{k}: {v}")

for c in ("N", "L"):
    b = base[c]
    print(f"baseline {c}: s_ss={b['s_ss']} exact={b['s_ss_exact']} "
          f"ci={b['core_interval']} exact={b['core_interval_exact']} "
          f"4exp={b['four_exp']} 4frames={b['four_frames']} "
          f"frame1={b['frame1_len_crc_headercrc_rawcrc_exact']} "
          f"hdr_consistent={b['header_bytes_consistent_with_fields']} "
          f"stats4={b['stats_cap_enc_exp4']} read={b['stats_read_518400']} "
          f"err0={b['stats_err_zero']}")
for n, e in bench.items():
    if isinstance(e, dict):
        print(f"bench {n}: bytes={e['bytes']} sha_ok={e['sha_ok']} cycles={e['cycles']} "
              f"cyc_ok={e['cycles_ok']} done={e['done']} last={e['out_last']} "
              f"zlib={e.get('zlib_decode_bytes')} zlib_match={e.get('zlib_decode_matches_input')} "
              f"err={e.get('zlib_decode_error')}")
print("bench 8b==16b shas:", bench["8b_vs_16b_shas_equal"])
print("probe N: core_stage=%s ci=%s c/B=%.5f near=%s release=%s f1=%s counters=%s "
      "SS_STALL=%s COLD=%s exported_line=%s errors=%s" % (
          probe["core_stage_present"], probe["core_interval_from_evt"], probe["cycles_per_byte"],
          probe["near_model_N_6390000"], probe["release_N_6500000"],
          probe["frame1_matches_base_N"], probe["counters_equal_baseline"],
          probe["markers_SS_STALL"], probe["markers_SS_STALL_COLD"],
          probe["exported_1_read_129600_timeout_line"], probe["errors_line"]))
print("first failed probe:", res["probe_N_first_failed"])
print("probe L:", res["probe_L"])
print("budget:", json.dumps(res["budget"], indent=1))
print("wrote", OUT)
