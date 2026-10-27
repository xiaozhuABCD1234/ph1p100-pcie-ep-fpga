#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T07.rk-align-backend 候选清单/来源记录生成器（可复跑）

产出（都写到 --out 指定的 backend 目录）：
  source-provenance.json  : 交付树逐文件 sha256 + 来源（peer 原样 / 本包修改 / 本包新增 / 本包复制）
  candidate-manifest.json : 冻结候选（生产输入 RTL/约束/IP/脚本 + TB + 最终 DB/STA/bit 证据）

判据：
  · 与 references/peer-fpga-2a4b253 下的同名文件逐字节比 → "peer_unchanged" / "modified"
  · 与 fpga/csi2/src/csi（本方 checked 源）逐字节比 → "local_copy_unchanged" / "local_copy_modified"
  · 其余新文件 → "new"
  · 候选项里出现的 HERMETIC 目录（runs/、work/、logs/）一律不纳入。

用法：
  python tools/pcie_integration/gen_manifest.py --root <项目根> --run <run目录名>
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

def collect(root, subdirs, exts=None, skip_dirs=(), exclude_names=()):
    out = []
    for sub in subdirs:
        base = os.path.join(root, sub)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d not in skip_dirs]
            for fn in sorted(filenames):
                if fn in exclude_names:
                    continue
                if exts and not any(fn.lower().endswith(e) for e in exts):
                    continue
                p = os.path.join(dirpath, fn)
                out.append((os.path.relpath(p, root).replace("\\", "/"), p))
    return sorted(out)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--run", default="workflow/runs/20261017-011744-rk-fpga-align")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    run = os.path.join(root, args.run.replace("/", os.sep))
    outdir = args.out or os.path.join(run, "backend")
    os.makedirs(outdir, exist_ok=True)

    tree = os.path.join(root, "fpga", "csi2", "pcie_integration")
    peer = os.path.join(run, "references", "peer-fpga-2a4b253")
    localcsi = os.path.join(root, "fpga", "csi2", "src", "csi")

    # ---------- 交付树逐文件来源 ----------
    prov = []
    files = collect(tree, ["rtl", "constraints", "al_ip", "sim", "docs"], skip_dirs=("work",))
    for rel, path in files:
        src = os.path.join(peer, rel[len(""):])  # peer 里的相对路径与本树一致（rtl/... constraints/... al_ip/...）
        origin = "new"
        if rel.startswith("rtl/checked/"):
            cand = os.path.join(localcsi, os.path.basename(rel))
            if not os.path.exists(cand):
                # rtl/checked/ 下的**本包新生成**文件（如 crc16_upd4.v）在本地原源里没有同名原型
                origin = "new"
            else:
                origin = "local_copy_unchanged" if sha256(cand) == sha256(path) else "local_copy_modified"
        elif os.path.exists(src):
            origin = "peer_unchanged" if sha256(src) == sha256(path) else "modified_by_t07"
        entry = {"path": rel, "sha256": sha256(path), "origin": origin}
        if origin == "modified_by_t07":
            entry["peer_sha256"] = sha256(src)
        if origin.startswith("local_copy"):
            entry["local_sha256"] = sha256(os.path.join(localcsi, os.path.basename(rel)))
        prov.append(entry)

    with open(os.path.join(outdir, "source-provenance.json"), "w", encoding="utf-8") as f:
        json.dump({"schema": 1,
                   "peer_frozen": "references/peer-fpga-2a4b253 (peer 2a4b253d9f2e56a943f1667b2a7a366824dcba34)",
                   "deliver_tree": "fpga/csi2/pcie_integration",
                   "files": prov}, f, ensure_ascii=False, indent=2)

    # ---------- 候选清单 ----------
    prod = []
    for rel, path in collect(tree, ["rtl", "constraints", "al_ip"], skip_dirs=("work",)):
        prod.append({"path": "fpga/csi2/pcie_integration/" + rel, "sha256": sha256(path)})
    scripts = []
    for rel, path in collect(root, ["tools/pcie_integration"]):
        scripts.append({"path": rel, "sha256": sha256(path)})
    tbs = []
    for rel, path in collect(tree, ["sim"], skip_dirs=("work",)):
        tbs.append({"path": "fpga/csi2/pcie_integration/" + rel, "sha256": sha256(path)})
    rk = []
    for rel, path in collect(run, ["backend/rk-driver-src", "backend/patches"]):
        rk.append({"path": rel, "sha256": sha256(path)})

    # 构建产物（TD 工程）——按存在性收集。
    # ★ round1（F3）：**易变日志不纳入清单**。它们是运行器/工具每次调用都会追加或重写的文件
    #   （commands.log、td_*.log、*.logw、abs.f、run.do、vsim_stdout.log 等），
    #   一旦纳入冻结清单，冻结后的任何一次调用都会让"基础哈希"失效（round0 实测 22 B 漂移）。
    #   这里显式排除并在 volatile_excluded 里列规则，候选身份只由 bit/DB/报告/稳定日志承担。
    VOLATILE_SUFFIX = (".logw",)
    VOLATILE_NAMES = {"commands.log", "abs.f", "run.do", "vsim_stdout.log"}
    prj = os.path.join(run, "backend", "candidate", "prj")
    arts = []
    for dirpath, dirnames, filenames in os.walk(prj):
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

    man = {
        "schema": 2,
        "task_id": "T07.rk-align-backend",
        "round": 3,
        "candidate_root": "workflow/runs/20261017-011744-rk-fpga-align/backend/candidate",
        "path_base": {
            "production_inputs": "项目根（project root）",
            "build_scripts": "项目根（project root）",
            "test_inputs": "项目根（project root）",
            "rk_patch_inputs": "run 目录（workflow/runs/<run>/）",
            "build_artifacts": "run 目录（workflow/runs/<run>/）",
        },
        "peer_frozen": "references/peer-fpga-2a4b253",
        "peer_driver_frozen": "references/peer-driver-a0215c5",
        "production_inputs": prod,
        "build_scripts": scripts,
        "test_inputs": tbs,
        "rk_patch_inputs": rk,
        "build_artifacts": arts,
        "volatile_excluded": {
            "names": ["commands.log", "abs.f", "run.do", "vsim_stdout.log"],
            "patterns": ["td_*.log", "*.logw"],
            "reason": "运行器/TD 每次调用都会追加或重写的易变日志：纳入清单会让冻结后的任何一次调用破坏基础哈希（round0 F3 实测）。候选身份由 bit/DB/报告/稳定日志承担。",
        },
        "notes": [
            "候选 = 生产 RTL/约束/IP（fpga/csi2/pcie_integration 下，排除 sim/tb 与 work/）",
            "测试输入（sim/tb、compile_checked.f）单独列出，不并入生产 RTL",
            "build_artifacts 是 TD 工程里可复现的 bit/DB/报告/稳定日志（按扩展名收集，已排除易变日志）",
            "round1：F1（相机感知 release）与 F2（重复声明）修复后的全部输入与构建产物；G1 证据见 backend/g1/msim/r1_*",
            "round2：G2 setup 时序 —— checked 完整性链本域有界重构（tail 小范围译码 + 扁平 XOR 树 CRC + 包尾计数寄存；rtl/checked/crc16_upd4.v 由 tools/pcie_integration/gen_crc16_flat.py 生成）；行为等价见 sim/tb/tb_csi_integrity_diff.v 差分 oracle；G1 证据见 backend/g1/msim/r2_*",
            "round3：仅工具/文档修复 —— run_sim.ps1 / run_td.ps1 前置 UTF-8 BOM（内容逐字节不变），修复 PS5.1/ACP=936 下按 ANSI 误解码吞换行导致的入口中止（r2 functional FAIL 的唯一原因）；RTL/SDC/约束/bit/DB 与本包测试输入一律未改；G1 证据（文档化默认命令原样复跑）见 backend/g1/msim/r3_*，入口负对照见 r3_entry_before_fix/，oracle 负对照见 r3_neg_m1/",
        ],
    }
    with open(os.path.join(outdir, "candidate-manifest.json"), "w", encoding="utf-8") as f:
        json.dump(man, f, ensure_ascii=False, indent=2)

    print("files(prov)=%d production=%d scripts=%d tbs=%d rk=%d artifacts=%d"
          % (len(prov), len(prod), len(scripts), len(tbs), len(rk), len(arts)))

    # ---------- 自检（round1 起）：逐条复算并报告不一致 ----------
    def resolve(entry_rel, base):
        return os.path.join(base, entry_rel.replace("/", os.sep))

    bad = []
    checks = 0
    for cat, base in (("production_inputs", root), ("build_scripts", root),
                      ("test_inputs", root), ("rk_patch_inputs", run),
                      ("build_artifacts", run)):
        for e in man[cat]:
            p = resolve(e["path"], base)
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
