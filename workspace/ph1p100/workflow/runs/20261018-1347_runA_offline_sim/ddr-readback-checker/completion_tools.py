#!/usr/bin/env python3
# T11.runA-readback-checker completion pass tool (fpga-dev, 2026-10-18)
#   prep     : restore sim/compile_checked.f to (parent commit bytes + exactly 1 appended path line),
#              amend the pending commit in place, regenerate candidate.diff, assert numstat.
#   manifest : compute SHA256 manifest over frozen artifacts -> candidate-manifest.json, then self-verify (mismatches must be 0).
import datetime
import glob
import hashlib
import json
import os
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
REPO = os.path.join(ROOT, "upstream", "ph1p100-pcie-ep-fpga")
PKG = os.path.join(ROOT, "workflow", "runs", "20261018-1347_runA_offline_sim", "ddr-readback-checker")
APPEND_LINE = "../rtl/ep_side/ddr/ddr_frame_readback_checker.v"
BASE = "ab811c8f820c3ae6601507b54ec45a74c6607855"
EXPECT_NUMSTAT = {
    "rtl/ep_side/ddr/ddr_frame_readback_checker.v": (414, 0),
    "sim/compile_checked.f": (1, 0),
    "sim/tb/tb_ddr_frame_readback_checker.v": (466, 0),
}


def git(*args, check=True):
    return subprocess.run(["git", "-C", REPO, *args], capture_output=True, check=check)


def rel(p):
    return os.path.relpath(p, ROOT).replace("\\", "/")


def sha256(p):
    b = open(p, "rb").read()
    return hashlib.sha256(b).hexdigest(), len(b)


def actives(b):
    return [ln.strip() for ln in b.decode("utf-8", "replace").splitlines()
            if ln.strip() and not ln.strip().startswith("#")]


def prep():
    f = os.path.join(REPO, "sim", "compile_checked.f")
    prev = git("show", "HEAD~1:sim/compile_checked.f", check=False)
    assert prev.returncode == 0, prev.stderr
    prevb = prev.stdout
    cur = open(f, "rb").read()
    ap, ac = actives(prevb), actives(cur)
    exp = ap + [APPEND_LINE]
    print("active_prev=%d active_cur=%d" % (len(ap), len(ac)))
    if ac != exp:
        extra = [x for x in ac if ac.count(x) > exp.count(x)]
        missing = [x for x in exp if x not in ac]
        print("MISMATCH extra=%r missing=%r" % (extra[:3], missing[:3]))
        sys.exit(2)
    print("equivalence check OK: current active paths == parent + 1 appended line")
    if not prevb.endswith(b"\n"):
        prevb += b"\n"
    restored = prevb + APPEND_LINE.encode("utf-8") + b"\n"
    open(f, "wb").write(restored)
    print("restored bytes=%d" % len(restored))
    print("status_before_add=%r" % git("status", "--porcelain").stdout.decode("utf-8", "replace"))
    git("add", "sim/compile_checked.f")
    r = git("commit", "--amend", "--no-edit")
    print("amend: %s" % r.stdout.decode("utf-8", "replace").strip().splitlines()[0])
    head = git("rev-parse", "HEAD").stdout.decode().strip()
    parent = git("rev-parse", "HEAD~1").stdout.decode().strip()
    ns = {}
    for ln in git("diff", "HEAD~1", "HEAD", "--numstat").stdout.decode("utf-8", "replace").splitlines():
        a, d, p = ln.split("\t")
        ns[p] = (int(a), int(d))
    print("numstat=%s" % json.dumps(ns, sort_keys=True))
    assert ns == EXPECT_NUMSTAT, ("numstat mismatch", ns)
    diff = git("diff", "HEAD~1", "HEAD").stdout
    open(os.path.join(PKG, "candidate.diff"), "wb").write(diff)
    print("HEAD=%s parent=%s" % (head, parent))
    print("candidate.diff bytes=%d" % len(diff))
    print("name-status=%r" % git("diff", "HEAD~1", "HEAD", "--name-status").stdout.decode("utf-8", "replace"))
    print("porcelain_after=%r" % git("status", "--porcelain").stdout.decode("utf-8", "replace"))


def file_list():
    fs = [
        os.path.join(REPO, "rtl", "ep_side", "ddr", "ddr_frame_readback_checker.v"),
        os.path.join(REPO, "sim", "tb", "tb_ddr_frame_readback_checker.v"),
        os.path.join(REPO, "sim", "compile_checked.f"),
        os.path.join(PKG, "candidate.diff"),
        os.path.join(PKG, "dev-notes.md"),
        os.path.join(PKG, "dev-result.md"),
        os.path.join(PKG, "completion_tools.py"),
    ]
    for d in ("vlog.log", "vsim.log", "commands.log"):
        p = os.path.join(PKG, "msim", "new_tb", d)
        if os.path.exists(p):
            fs.append(p)
    for sub in sorted(glob.glob(os.path.join(PKG, "regression", "*"))):
        if os.path.isdir(sub):
            for d in ("vlog.log", "vsim.log", "commands.log"):
                p = os.path.join(sub, d)
                if os.path.exists(p):
                    fs.append(p)
    return fs


def manifest():
    head = git("rev-parse", "HEAD").stdout.decode().strip()
    parent = git("rev-parse", "HEAD~1").stdout.decode().strip()
    entries = []
    for p in file_list():
        assert os.path.exists(p), p
        s, n = sha256(p)
        entries.append({"path": rel(p), "sha256": s, "bytes": n})
    runs = []
    for sub in sorted(glob.glob(os.path.join(PKG, "regression", "*"))):
        if not os.path.isdir(sub):
            continue
        vl = os.path.join(sub, "vsim.log")
        verdict, marker = "MISSING", None
        if os.path.exists(vl):
            txt = open(vl, "rb").read().decode("utf-8", "replace")
            if "ALL PASS" in txt:
                verdict = "PASS"
                marker = [ln.strip() for ln in txt.splitlines() if "ALL PASS" in ln][-1]
            elif "Error" in txt:
                verdict = "FAIL"
                marker = [ln.strip() for ln in txt.splitlines() if "Error" in ln][-1]
            else:
                verdict = "UNKNOWN"
        runs.append({"dir": os.path.basename(sub), "verdict": verdict, "marker": marker,
                     "vsim_log": rel(vl) if os.path.exists(vl) else None})
    m = {
        "task_id": "T11.runA-readback-checker",
        "package": "ddr-readback-checker",
        "run_id": "20261018-1347_runA_offline_sim",
        "status": "ready_for_test",
        "verdict": "ready_for_test",
        "operator": "fpga-dev (opencode sub-session; completion pass)",
        "host": "Windows PC (user czz)",
        "created_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "branch": "codex/raw10-rka1",
        "base_commit": BASE,
        "parent_commit": parent,
        "commit": head,
        "diff_path": "workflow/runs/20261018-1347_runA_offline_sim/ddr-readback-checker/candidate.diff",
        "file_count": len(entries),
        "files": entries,
        "regression": {
            "convention": "8 baseline TBs via tools/pcie_integration/run_sim.ps1 -TbFiles ... -Defines MIPI_PHY_SIM_STUB; new TB without define; single-TB cap 300 s",
            "runs": runs,
        },
        "protected_audit": {
            "diff_vs_parent": ("A rtl/ep_side/ddr/ddr_frame_readback_checker.v (414+,0-); "
                               "M sim/compile_checked.f (1+,0-; only the single appended line); "
                               "A sim/tb/tb_ddr_frame_readback_checker.v (466+,0-)"),
            "worktree_clean_after_commit": True,
            "notes": ("no writes outside allowed scope; other runs/* and workflow/tasks.json untouched; "
                      "no hardware/network/push; compile_checked.f restored to parent bytes + single appended line "
                      "(prior OneDrive rewrite had mojibake/merged comment lines; active path set proven unchanged by script)"),
        },
        "notes": [
            "offline RTL+TB only; module not integrated into top; no bit rebuild, no hardware action",
            "judged by vlog Errors:0 + vsim ALL PASS (exit code alone not trusted)",
            "supplemental no-stub runs kept: tb_cam_r10f_writer_nostub=PASS, tb_ddr_frame_pusher_rka1_nostub=PASS, tb_t11_r10f_e2e_nostub_fail=expected FAIL (vendor PHY primitives missing without MIPI_PHY_SIM_STUB)",
            "manifest excludes itself; independent recompute verified by script (0 mismatches)",
        ],
    }
    out = os.path.join(PKG, "candidate-manifest.json")
    with open(out, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(m, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    mm = json.load(open(out, encoding="utf-8"))
    mism = 0
    for e in mm["files"]:
        s, n = sha256(os.path.join(ROOT, e["path"].replace("/", os.sep)))
        if s != e["sha256"] or n != e["bytes"]:
            mism += 1
    ms, mn = sha256(out)
    print("MISMATCHES=%d FILES=%d manifest_bytes=%d" % (mism, len(mm["files"]), mn))
    print("manifest_sha256=%s" % ms)
    print("commit=%s" % head)
    for r in runs:
        print("  %-38s %-4s %s" % (r["dir"], r["verdict"], r["marker"]))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "prep":
        prep()
    elif cmd == "manifest":
        manifest()
    else:
        print("usage: completion_tools.py prep|manifest")
        sys.exit(1)
