"""Tester-independent input/manifest/scope verification for T10.ss-steady-anchor r0.

Read-only: reads the frozen task dir, the b11/b6/P2 inputs and the repo.
Writes nothing except stdout (the caller tees it into test-reports).
"""
import hashlib
import json
import os
import re
import sys
from datetime import datetime

RUN = r"D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict"
TD = os.path.join(RUN, "T10.ss-steady-anchor", "r0")
MANIFEST = os.path.join(TD, "manifest-r0.json")
B11 = r"D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b11-aplus-read\r0"
B6 = r"D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b6-a1-htab-nw\r0"
P2 = r"D:\fpga\ph1p100\workflow\runs\20261025-195604_fpga-dual-aplus-core-feasibility\T10.dual-aplus-service-verdict\r0"

def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def norm(p):
    return os.path.normcase(os.path.abspath(p))

out = {"checks": {}, "fail": []}

# ---- 1. frozen manifest self-consistency
raw = open(MANIFEST, "rb").read()
man = json.loads(raw.decode("utf-8"))
out["checks"]["manifest_sha256"] = hashlib.sha256(raw).hexdigest()
out["checks"]["manifest_task"] = man["task_id"]
out["checks"]["stopped_modifying"] = man["stopped_modifying"]
out["checks"]["active_commands"] = man["active_commands"]
bad = []
for a in man["artifacts"]:
    p = os.path.join(TD, a["path"].replace("/", os.sep))
    if not os.path.exists(p):
        bad.append([a["path"], "missing"])
    elif os.path.getsize(p) != a["bytes"] or sha(p) != a["sha256"]:
        bad.append([a["path"], "bytes/sha mismatch"])
out["checks"]["artifact_count"] = [man["artifact_count"], len(man["artifacts"])]
out["checks"]["artifact_mismatches"] = bad
if bad or man["artifact_count"] != 41 or len(man["artifacts"]) != 41:
    out["fail"].append("manifest_artifacts")

# unexpected files in task dir (manifest covers everything except itself)
listed = {norm(os.path.join(TD, a["path"])) for a in man["artifacts"]}
listed.add(norm(MANIFEST))
extra = []
for root, _dirs, files in os.walk(TD):
    for f in files:
        fp = norm(os.path.join(root, f))
        if fp not in listed:
            extra.append(os.path.relpath(fp, TD))
out["checks"]["unlisted_files_in_task_dir"] = extra
if extra:
    out["fail"].append("unlisted_task_files")

# ---- 2. 14 copied files vs b11 manifest (0 mismatch)
bm = json.load(open(os.path.join(B11, "CANDIDATE-MANIFEST-b11-aplus-read-r0.json"), encoding="utf-8"))
b11_entries = []
def walk(o):
    if isinstance(o, dict):
        if "path" in o and "sha256" in o:
            b11_entries.append(o)
        for v in o.values():
            walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)
walk(bm)
b11_by_path = {norm(e["path"]): e for e in b11_entries if isinstance(e["path"], str)}
b11_by_base = {}
for e in b11_entries:
    if isinstance(e.get("path"), str):
        b11_by_base.setdefault(os.path.basename(e["path"]).lower(), []).append(e)

iv = json.load(open(os.path.join(TD, "input-verified.json"), encoding="utf-8"))
copy_rows = []
copied_bases = set()
for c in iv["copied_files"]:
    dest = c["dest"]
    actual = sha(dest)
    e = b11_by_path.get(norm(c["source"]))
    match_by = "path"
    if e is None:
        cand = b11_by_base.get(os.path.basename(c["source"]).lower(), [])
        e = cand[0] if len(cand) == 1 else None
        match_by = "basename"
    ok = bool(e) and e.get("sha256") == actual and (e.get("bytes") in (None, os.path.getsize(dest)))
    copy_rows.append({"dest": os.path.basename(dest), "bytes": os.path.getsize(dest), "sha256": actual,
                      "b11_sha256": (e or {}).get("sha256"), "matched_by": match_by, "match": ok,
                      "claimed_match": c.get("match_manifest")})
    copied_bases.add(os.path.basename(dest).lower())
out["checks"]["copied_count_claimed"] = iv["copied_count"]
out["checks"]["copied_count_actual"] = len(copy_rows)
out["checks"]["copied_files"] = copy_rows
out["checks"]["copied_mismatch"] = [r["dest"] for r in copy_rows if not r["match"]]
out["checks"]["copied_claim_mismatch"] = [r["dest"] for r in copy_rows if not r["claimed_match"]]
if out["checks"]["copied_mismatch"] or len(copy_rows) != 14:
    out["fail"].append("copied_vs_b11")

# compile list (13) is exactly 12 copied DUT/model + derived TB
compiled = [os.path.basename(x) for x in man["commands"][1]["argv"] if x.lower().endswith(".v")]
out["checks"]["compile_list"] = compiled
out["checks"]["compile_count"] = len(compiled)
out["checks"]["compile_missing_from_copies"] = [b for b in compiled if b.lower() != "tb_ss_anchor.v" and b.lower() not in copied_bases]
if len(compiled) != 13 or out["checks"]["compile_missing_from_copies"]:
    out["fail"].append("compile_list")

# ---- 3. input drift: frozen snapshot vs current bytes
snap = iv["input_snapshot"]
drift = []
for k, v in snap.items():
    if not os.path.exists(v["path"]):
        drift.append([k, "missing"])
        continue
    if os.path.getsize(v["path"]) != v["bytes"] or sha(v["path"]) != v["sha256"]:
        drift.append([k, "drift"])
out["checks"]["input_snapshot_drift"] = drift
if drift:
    out["fail"].append("input_drift")

# ---- 4. no TD / board / COM / JTAG evidence in dev records
txt = ""
for rel in ["sim/logs/control2.log", "sim/logs/run4.log", "sim/logs/vlog.log", "sim/commands.jsonl",
            "result-r0.md", "out/steady-state.json"]:
    p = os.path.join(TD, rel.replace("/", os.sep))
    if os.path.exists(p):
        txt += open(p, encoding="utf-8", errors="replace").read().lower()
patterns = {"td_flow": r"\b(tang|td_|bitgen|place[_ ]?route|pnr|bitstream|\.bit\b|\.sof\b)",
            "board": r"\b(board|download|flash|jtag|programmer)\b",
            "com": r"\bcom[0-9]{1,2}\b"}
hits = {k: sorted(set(re.findall(p, txt))) for k, p in patterns.items()}
out["checks"]["forbidden_token_hits"] = hits
if any(hits.values()):
    # mentions in prose are allowed only if clearly negated; flag for manual review
    out["checks"]["forbidden_token_note"] = "tokens present; manual review of context required"

# ---- 5. protected trees not modified during dev window (00:20-00:52 on 2026-10-26)
t0 = datetime(2026, 10, 26, 0, 20, 0).timestamp()
t1 = datetime(2026, 10, 26, 0, 55, 0).timestamp()
touched = []
for base in [B11, B6, P2, r"D:\fpga\ph1p100\fpga\csi2\src"]:
    for root, _dirs, files in os.walk(base):
        for f in files:
            p = os.path.join(root, f)
            try:
                m = os.path.getmtime(p)
            except OSError:
                continue
            if t0 <= m <= t1:
                touched.append(p)
out["checks"]["protected_touched_in_window"] = touched
out["checks"]["tasks_json_sha256"] = sha(r"D:\fpga\ph1p100\workflow\tasks.json")
out["checks"]["tasks_json_snapshot"] = snap["tasks_json"]["sha256"]
if touched:
    out["fail"].append("protected_tree_written")
if out["checks"]["tasks_json_sha256"] != snap["tasks_json"]["sha256"]:
    out["fail"].append("tasks_json_drift")

# ---- 6. exclusivity of work lib/INI/logs
recs = [json.loads(l) for l in open(os.path.join(TD, "sim", "commands.jsonl"), encoding="utf-8") if l.strip()]
cwd_ok = all(norm(r["cwd"]) == norm(r"C:\Users\czz\AppData\Local\Temp\opencode\ss-anchor\work") for r in recs)
log_ok = all(norm(r["log"]).startswith(norm(TD)) for r in recs)
out["checks"]["dev_cwd_all_exclusive"] = cwd_ok
out["checks"]["dev_logs_all_in_task_dir"] = log_ok
out["checks"]["dev_command_count"] = len(recs)
out["checks"]["dev_vsim_count"] = sum(1 for r in recs if "vsim" in os.path.basename(r["argv"][0]).lower())
out["checks"]["dev_vlog_count"] = sum(1 for r in recs if "vlog" in os.path.basename(r["argv"][0]).lower())
ini_copy = r"C:\Users\czz\AppData\Local\Temp\opencode\ss-anchor\modelsim.ini"
out["checks"]["dev_ini_temp_exists"] = os.path.exists(ini_copy)
out["checks"]["dev_ini_temp_sha256"] = sha(ini_copy) if os.path.exists(ini_copy) else None
out["checks"]["dev_ini_archive_sha256"] = sha(os.path.join(TD, "sim", "modelsim.ini"))
if not (cwd_ok and log_ok and len(recs) == 5 and out["checks"]["dev_vsim_count"] == 2):
    out["fail"].append("dev_command_isolation")
if out["checks"]["dev_ini_temp_sha256"] != out["checks"]["dev_ini_archive_sha256"]:
    out["fail"].append("dev_ini_copy")

# ---- 7. modelsim/python versions
out["checks"]["python"] = sys.version.split()[0]
out["checks"]["modelsim_dir_exists"] = os.path.isdir(r"D:\intelFPGA\18.1\modelsim_ase\win32aloem")

out["pass"] = not out["fail"]
print(json.dumps(out, indent=1, ensure_ascii=False))
