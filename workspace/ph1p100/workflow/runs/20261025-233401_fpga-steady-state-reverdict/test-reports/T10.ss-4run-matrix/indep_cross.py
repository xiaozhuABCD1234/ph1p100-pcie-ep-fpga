#!/usr/bin/env python3
"""Cross-checks: P3 anchor binding, task-dir inventory, scope/forbidden actions,
and (when present) the tester's own R4 control rerun."""
import json, os, re, glob, hashlib, zlib, struct, subprocess, csv

RUN = r"D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict"
TASK = os.path.join(RUN, "T10.ss-4run-matrix", "r0")
P3 = os.path.join(RUN, "T10.ss-g0-closure", "r0")
OUT = os.path.join(RUN, "test-reports", "T10.ss-4run-matrix")
RE = os.path.join(OUT, "rerun")

def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()

def jload(p):
    try:
        return json.load(open(p, encoding="utf-8"))
    except Exception as e:
        return {"__error__": str(e)}

res = {}

# 1) P3 manifest-r2 binds the r3_frozen control artifacts
p3man = jload(os.path.join(P3, "manifest-r2.json"))
p3art = {a["path"]: a for a in p3man.get("artifacts", [])}
bind = {}
for k in ("sim/caps/r3_frozen.stats", "sim/caps/r3_frozen.evt", "sim/caps/r3_frozen.hdr",
          "sim/logs/r3_frozen.log", "src/tb_ss_g0.v"):
    a = p3art.get(k)
    p = os.path.join(P3, k)
    bind[k] = {"in_manifest": a is not None,
               "file_exists": os.path.exists(p),
               "sha_match": (a is not None and os.path.exists(p) and sha(p) == a["sha256"]),
               "sha256": a["sha256"] if a else None}
res["p3_binding"] = bind
res["p3_manifest_status"] = {k: p3man.get(k) for k in ("stopped_modifying", "active_commands", "status", "repair_round")}

# 2) P3 frozen proxy metadata (independent of P4 content-map) vs R4 header
proxy = jload(os.path.join(P3, "out", "content-proxy.json"))
def find_key(d, key, acc):
    if isinstance(d, dict):
        for k, v in d.items():
            if k == key:
                acc.append(v)
            find_key(v, key, acc)
    elif isinstance(d, list):
        for v in d:
            find_key(v, key, acc)
raw_c, xf_c = [], []
find_key(proxy, "raw_crc32", raw_c); find_key(proxy, "xform_crc32", xf_c)
res["p3_content_proxy"] = {"raw_crc32": sorted(set(raw_c)), "xform_crc32": sorted(set(xf_c))}

# 3) task dir inventory vs manifest
man = jload(os.path.join(TASK, "manifest-r0.json"))
listed = {a["path"].replace("\\", "/") for a in man["artifacts"]}
actual = set()
for root, _, files in os.walk(TASK):
    for f in files:
        actual.add(os.path.relpath(os.path.join(root, f), TASK).replace("\\", "/"))
res["inventory"] = {"listed": len(listed), "actual": len(actual),
                    "unlisted": sorted(actual - listed), "missing": sorted(listed - actual)}

# 4) forbidden actions from the recorded command list
cmds = [json.loads(l) for l in open(os.path.join(TASK, "sim", "commands.jsonl"), encoding="utf-8") if l.strip()]
tools = sorted({os.path.basename(c["argv"][0]).lower() for c in cmds})
allargs = " ".join(" ".join(map(str, c["argv"])) for c in cmds).lower()
res["commands"] = {"count": len(cmds), "tools": tools,
                   "rc_all_zero": all(c.get("rc") == 0 for c in cmds),
                   "timeouts": [c["log"] for c in cmds if c.get("timed_out")],
                   "full_size": [round(c.get("seconds", 0), 1) for c in cmds if "+STAT=" in " ".join(c["argv"]) and "FRAMES=4" in " ".join(c["argv"])],
                   "forbidden_hits": sorted({w for w in ("td", "td_", "bitgen", "chipwatcher", "cwc", "quartus", "jtag", "programmer",
                                                         "flash", "com3", "com4", "openocd", "rk", "synthesis") if re.search(r"\b" + w, allargs)})}

# 5) git status of the repo (tracked modifications only)
try:
    g = subprocess.run(["git", "-C", r"D:\fpga\ph1p100", "status", "--porcelain"], capture_output=True, text=True, timeout=60)
    lines = [l for l in g.stdout.splitlines() if l.strip()]
    mod = [l for l in lines if not l.startswith("??")]
    res["git"] = {"lines": len(lines), "tracked_modified": mod[:40], "tracked_modified_n": len(mod)}
except Exception as e:
    res["git"] = {"error": str(e)}

# 6) stray temp files around the declared write scope
tmp = r"C:\Users\czz\AppData\Local\Temp\opencode"
try:
    ent = []
    for n in os.listdir(tmp):
        p = os.path.join(tmp, n)
        if os.path.isfile(p):
            ent.append((n, os.path.getsize(p), round(os.path.getmtime(p))))
    res["temp_root_files"] = sorted(ent)
except Exception as e:
    res["temp_root_files"] = str(e)
dbg = os.path.join(tmp, "dbg_comp.py")
if os.path.exists(dbg):
    txt = open(dbg, encoding="utf-8", errors="replace").read()
    res["dbg_comp"] = {"bytes": os.path.getsize(dbg), "lines": txt.count("\n") + 1,
                       "imports": sorted(set(re.findall(r"^(?:import|from)\s+(\w+)", txt, re.M))),
                       "has_write_calls": bool(re.search(r"open\([^)]*['\"]w|fwrite|write_text", txt)),
                       "sha256": sha(dbg), "head": txt.splitlines()[:6]}

# 7) tester rerun of R4 (if it exists)
statp = os.path.join(RE, "r4-rerun.stats")
logp = os.path.join(RE, "r4-rerun.log")
hdrp = os.path.join(RE, "r4-rerun.hdr")
if os.path.exists(statp) and os.path.exists(logp) and os.path.exists(hdrp) and os.path.getsize(statp) > 0:
    ev = {}
    for ln in open(logp, encoding="utf-8", errors="replace"):
        s = ln.strip()
        if s.startswith("#"):
            s = s[1:].strip()
        m = re.match(r"SS_EVT t=(\d+) kind=(\w+) frame=(\d+) n=(\d+)", s)
        if m:
            ev.setdefault(m.group(2), {})[int(m.group(3))] = int(m.group(1))
    t = [ev["exp"][k] for k in (1, 2, 3, 4)]
    enc = [ev["enc"][k] for k in (1, 2, 3, 4)]
    st = dict(tok.split("=", 1) for tok in open(statp).read().split())
    st = {k: int(v) for k, v in st.items()}
    b = bytes(int(x.strip(), 16) for x in open(hdrp) if x.strip())
    S23, S34 = t[2] - t[1], t[3] - t[2]
    tail = [t[i] - enc[i] for i in range(4)]
    tail_mean = sum(tail[1:]) / 3.0
    rr = {"t_exp": t, "L_cold": t[0] - 20, "S_2": t[1] - t[0], "S_23": S23, "S_34": S34,
          "S_ss": (S23 + S34) / 2.0, "tail": tail, "tail_mean_2_4": tail_mean,
          "sink_limited": tail_mean >= 0.5 * ((S23 + S34) / 2.0),
          "stats": st, "hdr_raw_crc": struct.unpack_from("<I", b, 28)[0],
          "hdr_xform_crc": struct.unpack_from("<I", b, 32)[0],
          "hdr_stream_len": struct.unpack_from("<I", b, 24)[0],
          "header_crc_ok": struct.unpack_from("<I", b, 40)[0] == (zlib.crc32(b[0:40]) & 0xFFFFFFFF),
          "capacity_MBps": 4.86e8 / ((S23 + S34) / 2.0)}
    rr["margin_0_pct"] = (rr["capacity_MBps"] / 77.76 - 1) * 100
    rr["margin_25_pct"] = (rr["capacity_MBps"] / 97.20 - 1) * 100
    res["rerun"] = rr
    res["rerun_status"] = jload(os.path.join(RE, "rerun-status.json"))
else:
    res["rerun"] = "not_present_or_empty"

json.dump(res, open(os.path.join(OUT, "indep-cross.json"), "w"), indent=1, default=str)
print(json.dumps(res, indent=1, default=str)[:12000])
