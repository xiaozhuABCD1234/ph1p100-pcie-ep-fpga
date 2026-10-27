#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T07.rk-align-backend r2 functional：独立复核脚本（新测试实例，不在任何冻结输入上写）。

用法:
  python functional_checks.py manifest          # 全量复算 candidate-manifest.json 232 条 + 候选树冻结后写入扫描
  python functional_checks.py snapshot before|after  # 冻结输入（compile_checked.f 引用 + TB + 入口脚本）哈希快照
  python functional_checks.py binding           # 证据时间绑定（RTL 末次修改 vs 开发/测试运行时间）
"""
import json, hashlib, os, sys, datetime

ROOT = r"C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道"
RUN = ROOT + "/workflow/runs/20261017-011744-rk-fpga-align"
MANIFEST = RUN + "/backend/candidate-manifest.json"
OUT = RUN + "/test-reports/T07-functional-r2/independent"
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
    man_sha = sha256_file(MANIFEST)
    man_mtime = mt(MANIFEST)
    # 候选树：manifest 生成后被写入的文件（内容哈希已核对；这里查出“时间上晚于冻结”的项，供漂移登记）
    cand = RUN + "/backend/candidate"
    late = []
    for dp, dns, fns in os.walk(cand):
        for fn in fns:
            p = os.path.join(dp, fn)
            t = os.path.getmtime(p)
            if t > os.path.getmtime(MANIFEST) + 1:  # 1s 容差
                rel = os.path.relpath(p, RUN).replace("\\", "/")
                late.append([rel, mt(p)])
    res = {
        "manifest": MANIFEST, "manifest_sha256": man_sha, "manifest_mtime": man_mtime,
        "entries_checked": total, "sha_ok": ok, "missing": missing, "sha_mismatch": mismatch,
        "size_mismatch": size_bad,
        "candidate_files_newer_than_manifest": sorted(late),
        "note": "sha_ok 应为 232；missing/sha_mismatch 必须为空；late 列表是候选树里 mtime 晚于 manifest 的文件（内容哈希仍按上表核对）",
    }
    json.dump(res, open(OUT + "/manifest_recompute.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("manifest entries=%d sha_ok=%d missing=%d sha_mismatch=%d size_mismatch=%d late_files=%d"
          % (total, ok, len(missing), len(mismatch), len(size_bad), len(late)))
    print("manifest_sha256 =", man_sha)
    for x in mismatch[:10]:
        print("  MISMATCH", x)
    for x in late[:20]:
        print("  LATE", x)
    return 0


def compile_list_files():
    """解析 compile_checked.f（相对 sim/ 展开），返回绝对路径列表 + TB + 入口脚本"""
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
    fl.append(MANIFEST)
    # 生产域补充（时间绑定要覆盖本包引入的 checked 源与 oracle 源）
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
    res = {"stage": stage, "files": items}
    json.dump(res, open(OUT + "/input_snapshot_%s.json" % stage, "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)
    print("snapshot %s: %d files" % (stage, len(items)))
    return 0


def binding():
    """证据时间绑定：输入末次修改时间、开发 r2 日志时间、本测试运行时间"""
    fl = compile_list_files()
    rtl = [p for p in fl if p.endswith(".v") or p.endswith(".vh")]
    enters = {}
    for p in fl:
        if os.path.isfile(p):
            enters[os.path.relpath(p, ROOT).replace("\\", "/")] = mt(p)
    dev = {}
    g1 = RUN + "/backend/g1/msim"
    for d in sorted(os.listdir(g1)):
        if not d.startswith("r2_"):
            continue
        dd = os.path.join(g1, d)
        vs = os.path.join(dd, "vsim.log")
        vl = os.path.join(dd, "vlog.log")
        if os.path.isfile(vs):
            dev[d] = {"vlog_mtime": mt(vl), "vsim_mtime": mt(vs)}
    # 本测试 r2 证据
    mine = {}
    mr = RUN + "/test-reports/T07-functional-r2"
    for d in sorted(os.listdir(mr)):
        dd = os.path.join(mr, d)
        if not os.path.isdir(dd):
            continue
        for sub in sorted(os.listdir(dd)):
            sd = os.path.join(dd, sub)
            vs = os.path.join(sd, "vsim.log")
            if os.path.isfile(vs):
                mine[d + "/" + sub] = {"vlog_mtime": mt(os.path.join(sd, "vlog.log")),
                                        "vsim_mtime": mt(vs)}
    res = {"input_mtimes": enters, "dev_r2_evidence": dev, "my_r2_evidence": mine}
    json.dump(res, open(OUT + "/time_binding.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    mx = max((v, k) for k, v in enters.items())
    print("latest input mtime:", mx[0], "->", mx[1])
    print("dev r2 runs:", json.dumps(dev, ensure_ascii=False))
    print("my r2 runs:", json.dumps(mine, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    if cmd == "manifest":
        sys.exit(manifest_check())
    elif cmd == "snapshot":
        sys.exit(snapshot(sys.argv[2]))
    elif cmd == "binding":
        sys.exit(binding())
    else:
        print("unknown command"); sys.exit(2)
