"""Tester-independent check of the FRAMES=2 control re-run.

Uses the tester's own work library/log/stats under test-reports/.../r0.
Compares the first 16 b11 stats fields value-by-value and the event stream
against the developer's frozen control run.
"""
import hashlib
import json
import os
import re

RUN = r"D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict"
DEV = os.path.join(RUN, "T10.ss-steady-anchor", "r0")
TEST = os.path.join(RUN, "test-reports", "T10.ss-steady-anchor", "r0")
EXPECTED = {
    "cap": 2, "enc": 2, "exported": 2, "exp_bytes": 80068, "raw_pub": 2,
    "raw_drop": 0, "cmp_drop": 0, "geom": 0, "err": 0, "read": 259200,
    "dup": 0, "cap_bytes": 80156, "cycles": 11445988, "wd": 0,
    "ar": 261704, "r": 261704,
}

def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()

def parse_stats(p):
    s = open(p, encoding="utf-8").read().strip().split()
    d = {}
    for kv in s:
        k, v = kv.split("=", 1)
        d[k] = int(v)
    return d

def evt_lines(p):
    return [l.strip() for l in open(p, encoding="utf-8", errors="replace") if l.strip().startswith("SS_EVT")]

def log_evt_lines(p):
    out = []
    for l in open(p, encoding="utf-8", errors="replace"):
        m = re.search(r"(SS_EVT .*)$", l.strip())
        if m:
            out.append(m.group(1))
    return out

res = {"tester_work_lib": r"C:\Users\czz\AppData\Local\Temp\opencode\ss-anchor-test\work",
       "tester_log": os.path.join(TEST, "logs", "control2-test.log"),
       "expected": EXPECTED}
stats = parse_stats(os.path.join(TEST, "caps", "ss2-test.stats"))
res["actual"] = stats
diffs = [[k, EXPECTED[k], stats.get(k)] for k in EXPECTED if stats.get(k) != EXPECTED[k]]
res["mismatches"] = diffs
res["first16_exact"] = len(diffs) == 0
res["appended_fields"] = {k: stats[k] for k in ("frames", "ss_pass") if k in stats}

test_evt = evt_lines(os.path.join(TEST, "caps", "ss2-test.evt"))
dev_evt = evt_lines(os.path.join(DEV, "sim", "caps", "ss2.evt"))
dev_log_evt = log_evt_lines(os.path.join(DEV, "sim", "logs", "control2.log"))
res["evt_count"] = [len(test_evt), len(dev_evt)]
res["evt_identical_to_dev_evt"] = test_evt == dev_evt
res["evt_identical_to_dev_log"] = test_evt == dev_log_evt
res["evt_mismatches"] = [i for i, (a, b) in enumerate(zip(test_evt, dev_evt)) if a != b]

# stats line compare: dev control2 first 16 fields must equal tester first 16
dev_stats = parse_stats(os.path.join(DEV, "sim", "caps", "ss2.stats"))
res["dev_control2_first16"] = {k: dev_stats[k] for k in EXPECTED}
res["tester_equals_dev_control2"] = all(dev_stats[k] == stats[k] for k in EXPECTED)

# log completion evidence
log = open(os.path.join(TEST, "logs", "control2-test.log"), encoding="utf-8", errors="replace").read()
res["log_has_pass_marker"] = "# B11_FULL_RESULT pass=1" in log
res["log_errors_zero"] = "# Errors: 0" in log
res["log_has_finish"] = "$finish" in log
m = re.search(r"# End time: ([^\n]+)", log)
res["log_end_time"] = m.group(1) if m else None
res["launcher_rc_note"] = ("PowerShell Start-Process did not populate ExitCode (null); normal completion is "
                           "evidenced by $finish + Errors: 0 + B11_FULL_RESULT pass=1 + fresh stats, and no timeout")

res["artifacts"] = {rel: {"bytes": os.path.getsize(os.path.join(TEST, rel)), "sha256": sha(os.path.join(TEST, rel))}
                    for rel in ("caps/ss2-test.stats", "caps/ss2-test.evt", "caps/ss2-test.dec",
                                "logs/control2-test.log")}
res["dec_lines"] = sum(1 for _ in open(os.path.join(TEST, "caps", "ss2-test.dec"), encoding="utf-8", errors="replace"))
res["dec_lines_equals_cap_bytes"] = res["dec_lines"] == stats["cap_bytes"]
res["pass"] = bool(res["first16_exact"] and res["evt_identical_to_dev_evt"] and res["tester_equals_dev_control2"]
                   and res["log_has_pass_marker"] and res["log_errors_zero"] and res["log_has_finish"]
                   and res["dec_lines_equals_cap_bytes"])
print(json.dumps(res, indent=1, ensure_ascii=False))
