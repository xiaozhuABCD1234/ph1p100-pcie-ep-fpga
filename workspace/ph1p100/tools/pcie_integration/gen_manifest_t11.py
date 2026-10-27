#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T11.rk-align-raw 候选清单/来源记录生成器（可复跑；**不修改 T07 的 gen_manifest.py**）

产出（都写到 --out 指定的 raw 目录）：
  source-provenance.json  : 交付树逐文件 sha256 + 来源（peer 原样 / T07 修改 / T11 修改 / 本包新增 / 本地复制）
  candidate-manifest.json : 冻结候选（生产输入 RTL/约束/IP/脚本 + TB + 最终 DB/STA/bit 证据 + RK 增量）
  manifest-selfcheck.json : 逐条复算

用法：
  python tools/pcie_integration/gen_manifest_t11.py --root <项目根> --run <run目录名>
"""
import argparse
import hashlib
import json
import os
import sys


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def collect(base, skip_dirs=(), exclude_names=()):
    out = []
    if not os.path.isdir(base):
        return out
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in skip_dirs]
        for fn in sorted(filenames):
            if fn in exclude_names:
                continue
            p = os.path.join(dirpath, fn)
            out.append(p)
    return sorted(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--run", default="workflow/runs/20261017-011744-rk-fpga-align")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    run = os.path.join(root, args.run.replace("/", os.sep))
    outdir = args.out or os.path.join(run, "raw")
    os.makedirs(outdir, exist_ok=True)

    tree = os.path.join(root, "fpga", "csi2", "pcie_integration")
    peer = os.path.join(run, "references", "peer-fpga-2a4b253")
    localcsi = os.path.join(root, "fpga", "csi2", "src", "csi")
    t07 = os.path.join(run, "backend", "candidate-manifest.json")

    # T07 冻结清单（用于标注「相对 T07 变了什么」）
    t07_prod = {}
    if os.path.exists(t07):
        with open(t07, encoding="utf-8") as f:
            m7 = json.load(f)
        for e in m7.get("production_inputs", []):
            t07_prod[e["path"]] = e["sha256"]

    def rel_tree(p):
        return os.path.relpath(p, tree).replace("\\", "/")

    # ---------- 交付树逐文件来源 ----------
    prov = []
    files = collect(tree, skip_dirs=("work",))
    for path in files:
        rel = rel_tree(path)
        src = os.path.join(peer, rel)
        origin = "new"
        if rel.startswith("rtl/checked/"):
            cand = os.path.join(localcsi, os.path.basename(rel))
            if not os.path.exists(cand):
                origin = "new"
            else:
                origin = "local_copy_unchanged" if sha256(cand) == sha256(path) else "local_copy_modified"
        elif os.path.exists(src):
            origin = "peer_unchanged" if sha256(src) == sha256(path) else "peer_modified"
        entry = {"path": rel, "sha256": sha256(path), "origin": origin}
        if origin == "peer_modified":
            entry["peer_sha256"] = sha256(src)
        if origin.startswith("local_copy"):
            entry["local_sha256"] = sha256(os.path.join(localcsi, os.path.basename(rel)))
        full = "fpga/csi2/pcie_integration/" + rel
        if full in t07_prod:
            entry["t07_sha256"] = t07_prod[full]
            entry["changed_since_t07"] = (t07_prod[full] != entry["sha256"])
        prov.append(entry)

    with open(os.path.join(outdir, "source-provenance.json"), "w", encoding="utf-8") as f:
        json.dump({"schema": 1,
                   "peer_frozen": "references/peer-fpga-2a4b253 (peer 2a4b253d9f2e56a943f1667b2a7a366824dcba34)",
                   "deliver_tree": "fpga/csi2/pcie_integration",
                   "baseline_t07_manifest": args.run + "/backend/candidate-manifest.json",
                   "files": prov}, f, ensure_ascii=False, indent=2)

    # ---------- 候选清单 ----------
    prod = []
    for path in collect(os.path.join(tree, "rtl"), skip_dirs=("work",)) + \
            collect(os.path.join(tree, "constraints"), skip_dirs=("work",)) + \
            collect(os.path.join(tree, "al_ip"), skip_dirs=("work",)):
        prod.append({"path": "fpga/csi2/pcie_integration/" + rel_tree(path), "sha256": sha256(path)})
    prod = sorted(prod, key=lambda e: e["path"])

    scripts = []
    for path in collect(os.path.join(root, "tools", "pcie_integration")):
        scripts.append({"path": os.path.relpath(path, root).replace("\\", "/"), "sha256": sha256(path)})
    scripts = sorted(scripts, key=lambda e: e["path"])

    tbs = []
    for path in collect(os.path.join(tree, "sim"), skip_dirs=("work",)):
        tbs.append({"path": "fpga/csi2/pcie_integration/" + rel_tree(path), "sha256": sha256(path)})
    tbs = sorted(tbs, key=lambda e: e["path"])

    rk = []
    for path in collect(os.path.join(run, "raw", "rk-driver-src")) + \
            collect(os.path.join(run, "raw", "patches")):
        rk.append({"path": os.path.relpath(path, run).replace("\\", "/"), "sha256": sha256(path)})
    rk = sorted(rk, key=lambda e: e["path"])

    # 构建产物（TD 工程）——易变日志不纳入（与 T07 同一规则）
    VOLATILE_SUFFIX = (".logw",)
    VOLATILE_NAMES = {"commands.log", "abs.f", "run.do", "vsim_stdout.log"}
    prj = os.path.join(run, "raw", "candidate", "prj")
    arts = []
    for dirpath, dirnames, filenames in os.walk(prj):
        dirnames[:] = [d for d in dirnames if d != "work"]
        for fn in sorted(filenames):
            low = fn.lower()
            if fn in VOLATILE_NAMES or low.endswith(VOLATILE_SUFFIX) or low.startswith("td_"):
                continue
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, run).replace("\\", "/")
            if "/work/" in rel:
                continue
            if any(low.endswith(e) for e in
                   (".bit", ".sbit", ".db", ".tsr", ".rpt", ".log", ".al", ".area", ".timing", ".tsu",
                    ".ts", ".qor", ".bid", ".params", ".status")):
                arts.append({"path": rel, "sha256": sha256(p), "size": os.path.getsize(p)})
    arts = sorted(arts, key=lambda e: e["path"])

    man = {
        "schema": 2,
        "task_id": "T11.rk-align-raw",
        "round": 0,
        "candidate_root": "workflow/runs/20261017-011744-rk-fpga-align/raw/candidate",
        "path_base": {
            "production_inputs": "项目根（project root）",
            "build_scripts": "项目根（project root）",
            "test_inputs": "项目根（project root）",
            "rk_patch_inputs": "run 目录（workflow/runs/<run>/）",
            "build_artifacts": "run 目录（workflow/runs/<run>/）",
        },
        "peer_frozen": "references/peer-fpga-2a4b253",
        "peer_driver_frozen": "references/peer-driver-a0215c5",
        "baseline_candidate": {
            "task_id": "T07.rk-align-backend",
            "manifest_sha256": "68f9f4d05dd219cf4f66009a5bed1bdd6c1dcc7e1a4a386a8974725b733a4275",
            "bit_sha256": "0943cb36feeb873decc6ea5aae1c2777b3ab4881ebe2954b43bee040ceb38b0a",
            "note": "T11 在 T07 r3 候选的同一交付树上继续（新增 cam_r10f_writer + 顶层换接）；T07 manifest 的 production_inputs 引用同一棵树，T11 修改后其 SHA 已变 —— T07 manifest 只作历史冻结记录，当前唯一有效清单是本文件。",
        },
        "production_inputs": prod,
        "build_scripts": scripts,
        "test_inputs": tbs,
        "rk_patch_inputs": rk,
        "build_artifacts": arts,
        "volatile_excluded": {
            "names": ["commands.log", "abs.f", "run.do", "vsim_stdout.log"],
            "patterns": ["td_*.log", "*.logw"],
            "reason": "运行器/TD 每次调用都会追加或重写的易变日志（T07 round0 F3 实测会破坏基础哈希）。候选身份由 bit/DB/报告/稳定日志承担。",
        },
        "notes": [
            "候选 = 生产 RTL/约束/IP（fpga/csi2/pcie_integration 下，排除 sim/tb 与 work/）",
            "T11 新增/修改：rtl/ep_side/ddr/cam_r10f_writer.v（R10F 写者）、rtl/ep_side/ddr/crc32_upd4.v（含入）、rtl/ep_side/ph1p_pcie_ep_top.v（换接 A/B 两片 R10F 写者）、sim/tb/tb_cam_r10f_writer.v、sim/tb/tb_t11_r10f_e2e.v、sim/tb/tb_t11_csi_enable_corner.v、sim/compile_checked.f",
            "G1 证据：raw/g1/msim/ 下 p1_writer_v4（写者 P0..P10，含 1080p 81,024 拍/633+1 突发/尾零/头+CRC）、p2_e2e_v6（小几何全链路 E0..E4）、p3_enable（T07 遗留 I_enable 角落）、r_t07_* 五 TB 回归、neg_m1_pack_order（可重放负对照：packed 低2bit 顺序换成反序 → e2e/写者 TB 均 FAIL）",
            "G2 证据：raw/candidate/prj（TD 00_all 单会话：syn+phy+bit）；报告/DB/bit 同源 SHA 见 build_artifacts",
            "RK 增量：raw/rk-driver-src（T07 树 + T11 修正）+ raw/patches/t11-rka1-r10f-fix.patch（对 T07 完整体 git apply，离线 apply-check 通过）；未编译/未安装",
        ],
    }
    with open(os.path.join(outdir, "candidate-manifest.json"), "w", encoding="utf-8") as f:
        json.dump(man, f, ensure_ascii=False, indent=2)

    print("files(prov)=%d production=%d scripts=%d tbs=%d rk=%d artifacts=%d"
          % (len(prov), len(prod), len(scripts), len(tbs), len(rk), len(arts)))

    # ---------- 自检 ----------
    bad = []
    checks = 0
    for cat, base in (("production_inputs", root), ("build_scripts", root),
                      ("test_inputs", root), ("rk_patch_inputs", run),
                      ("build_artifacts", run)):
        for e in man[cat]:
            p = os.path.join(base, e["path"].replace("/", os.sep))
            checks += 1
            if not os.path.isfile(p):
                bad.append((cat, e["path"], "missing"))
            elif sha256(p) != e["sha256"]:
                bad.append((cat, e["path"], "sha-mismatch"))
    print("self-check: %d entries, %d mismatches" % (checks, len(bad)))
    for b in bad[:20]:
        print("  MISMATCH", b)
    with open(os.path.join(outdir, "manifest-selfcheck.json"), "w", encoding="utf-8") as f:
        json.dump({"entries": checks, "mismatches": [{"category": c, "path": p, "kind": k} for c, p, k in bad]},
                  f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    sys.exit(main())
