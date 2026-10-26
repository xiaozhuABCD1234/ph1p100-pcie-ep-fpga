#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T07.rk-align-backend r3 functional: independent recheck (manifest recompute + snapshots + time binding)."""
import json, hashlib, os, sys, datetime

ROOT = r"C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道"
RUN = ROOT + "/workflow/runs/20261017-011744-rk-fpga-align"
MANIFEST = RUN + "/backend/candidate-manifest.json"
OUT = RUN + "/test-reports/T07-functional-r3/independent"
INT = ROOT + "/fpga/csi2/pcie_integration"


def sha256_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def mt(p):
    return datetime.datetime.fromtimestamp(os.path.getmtime(p)).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]


def manifest_check():
    m = json.load(open(MANIFEST, encoding="utf-8-sig"))
    groups = (("production_inputs", ROOT), ("build_scripts", ROOT),
              ("test_inputs", ROOT), ("rk_patch_inputs", RUN), ("build_artifacts", RUN))
    total = ok = 0
    missing, mismatch, size_bad = [], [], []
    for cat, base in groups:
        for e in m[cat]:
            total += 1
            p = os.path.join(base, e["path"].replace("/", os.sep))
            if not os.path.isfile(p):
                missing.append([cat, e["path"]])
                continue
            s = sha256_file(p)
            if s.lower() != e["sha256"].lower():
                mismatch.append([cat, e["path"], e["sha256"], s])
            else:
                ok += 1
            if "size" in e and os.path.getsize(p) != e["size"]:
                size_bad.append([cat, e["path"], e["size"], os.path.getsize(p)])
    late = []
    cand = RUN + "/backend/candidate"
    for dp, dns, fns in os.walk(cand):
        for fn in fns:
            p = os.path.join(dp, fn)
            if os.path.getmtime(p) > os.path.getmtime(MANIFEST) + 1:
                late.append([os.path.relpath(p, RUN).replace("\\", "/"), mt(p)])
    res = {"manifest": MANIFEST, "manifest_sha256": sha256_file(MANIFEST), "manifest_mtime": mt(MANIFEST),
           "entries_checked": total, "sha_ok": ok, "missing": missing, "sha_mismatch": mismatch,
           "size_mismatch": size_bad, "candidate_files_newer_than_manifest": sorted(late)}
    json.dump(res, open(OUT + "/manifest_recompute.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("manifest entries=%d sha_ok=%d missing=%d sha_mismatch=%d size_mismatch=%d late=%d"
          % (total, ok, len(missing), len(mismatch), len(size_bad), len(late)))
    print("manifest_sha256 =", res["manifest_sha256"])
    for x in mismatch[:10]:
        print("  MISMATCH", x)
    for x in late[:20]:
        print("  LATE", x)
    # record bit hash from manifest for cross-check
    bits = [e for e in m["build_artifacts"] if e["path"].endswith(".bit")]
    for b in bits:
        print("  BIT", b["path"], b["sha256"])
    return 0


def compile_list_files():
    simf = INT + "/sim/compile_checked.f"
    fl = [simf]
    for ln in open(simf, encoding="utf-8-sig"):
        t = ln.strip()
        if not t or t.startswith("#"):
            continue
        if os.path.isabs(t):
            fl.append(t.replace("\\", "/"))
        else:
            fl.append(os.path.normpath(os.path.join(INT + "/sim", t)).replace("\\", "/"))
    for tb in ("tb_ddr_frame_pusher_rka1.v", "tb_ep_bar_win_rka1.v", "tb_csi_checked.v",
               "tb_ddr_wr_arb_peer.v", "tb_csi_integrity_diff.v"):
        fl.append(INT + "/sim/tb/" + tb)
    fl.append(ROOT + "/tools/pcie_integration/run_sim.ps1")
    fl.append(ROOT + "/tools/pcie_integration/run_td.ps1")
    fl.append(MANIFEST)
    fl.append(ROOT + "/fpga/csi2/src/csi/csi_rx_packet_integrity.v")
    return sorted(set(fl))


def snapshot(stage):
    fl = compile_list_files()
    items = {}
    for p in fl:
        if os.path.isfile(p):
            items[p] = {"sha256": sha256_file(p), "size": os.path.getsize(p), "mtime": mt(p)}
        else:
            items[p] = "MISSING"
    json.dump({"stage": stage, "files": items}, open(OUT + "/input_snapshot_%s.json" % stage, "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)
    print("snapshot %s: %d files" % (stage, len(items)))
    return 0


def compare_r2():
    """Compare current files against my r2 snapshot: expect only run_sim.ps1 (BOM) and the manifest to differ."""
    r2 = json.load(open(RUN + "/test-reports/T07-functional-r2/independent/input_snapshot_before.json", encoding="utf-8"))["files"]
    diffs = []
    same = 0
    for p, rec in sorted(r2.items()):
        if not isinstance(rec, dict):
            continue
        if not os.path.isfile(p):
            diffs.append({"file": p, "r2": rec, "now": "MISSING"})
            continue
        s = sha256_file(p)
        if s.lower() == rec["sha256"].lower():
            same += 1
        else:
            diffs.append({"file": os.path.relpath(p, ROOT).replace("\\", "/"),
                          "r2_sha": rec["sha256"], "now_sha": s,
                          "r2_mtime": rec["mtime"], "now_mtime": mt(p)})
    res = {"r2_files": len([1 for v in r2.values() if isinstance(v, dict)]), "unchanged": same, "changed": diffs}
    json.dump(res, open(OUT + "/r2_compare.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("r2 compare: files=%d unchanged=%d changed=%d" % (res["r2_files"], same, len(diffs)))
    for d in diffs:
        print("  CHANGED", d["file"], d.get("r2_sha", "?")[:12], "->", d.get("now_sha", "?")[:12])
    return 0


def binding():
    fl = compile_list_files()
    enters = {}
    for p in fl:
        if os.path.isfile(p):
            enters[os.path.relpath(p, ROOT).replace("\\", "/")] = mt(p)
    dev = {}
    g1 = RUN + "/backend/g1/msim"
    for d in sorted(os.listdir(g1)):
        if d.startswith("r3_") or d.startswith("r3v_"):
            vs = os.path.join(g1, d, "vsim.log")
            vl = os.path.join(g1, d, "vlog.log")
            if os.path.isfile(vs):
                dev[d] = {"vlog_mtime": mt(vl), "vsim_mtime": mt(vs)}
    mine = {}
    mr = RUN + "/test-reports/T07-functional-r3"
    for d in sorted(os.listdir(mr)):
        dd = os.path.join(mr, d)
        if not os.path.isdir(dd):
            continue
        for sub in sorted(os.listdir(dd)):
            vs = os.path.join(dd, sub, "vsim.log")
            if os.path.isfile(vs):
                mine[d + "/" + sub] = {"vlog_mtime": mt(os.path.join(dd, sub, "vlog.log")),
                                       "vsim_mtime": mt(vs)}
    res = {"input_mtimes": enters, "dev_r3_evidence": dev, "my_r3_evidence": mine}
    json.dump(res, open(OUT + "/time_binding.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    mx = max((v, k) for k, v in enters.items())
    print("latest input mtime:", mx[0], "->", mx[1])
    print("dev r3 runs:", len(dev))
    print("my r3 runs:", len(mine))
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    if cmd == "manifest":
        sys.exit(manifest_check())
    elif cmd == "snapshot":
        sys.exit(snapshot(sys.argv[2]))
    elif cmd == "r2compare":
        sys.exit(compare_r2())
    elif cmd == "binding":
        sys.exit(binding())
    else:
        print("unknown command"); sys.exit(2)
