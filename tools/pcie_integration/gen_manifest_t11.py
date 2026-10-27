#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""FPGA 原仓检出候选清单生成器（repo 版；由 T11.rk-align-raw gen_manifest_t11.py 适配检出根）

用法：
  python tools/pcie_integration/gen_manifest_t11.py --root <检出根> [--out <输出目录>]
         [--run <项目 run 目录>] [--peer <冻结副本目录>] [--task-id <ID>]

产出（--out，默认 <root>/build/manifest）：
  source-provenance.json  : 检出树逐文件 sha256 + 来源（repo_copy / peer_unchanged / peer_modified）
  candidate-manifest.json : 生产输入（rtl/constraints/al_ip）+ 构建脚本（tools/pcie_integration）
                            + 测试输入（sim）+ 协议镜像（docs/protocol）+ 可选 RK/构建产物
  manifest-selfcheck.json : 逐条复算结果

说明：不修改、不删除任何源文件；无 --run 时 rk_patch_inputs/build_artifacts 为空；
无 --peer 时来源统一记 repo_copy。
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


def collect(base, skip_dirs=()):
    out = []
    if not os.path.isdir(base):
        return out
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in skip_dirs]
        for fn in sorted(filenames):
            out.append(os.path.join(dirpath, fn))
    return sorted(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True, help="FPGA 原仓检出根")
    ap.add_argument("--run", default=None, help="项目 run 目录（可选：RK 补丁/构建产物来源）")
    ap.add_argument("--peer", default=None, help="冻结 peer 副本目录（可选：来源比对）")
    ap.add_argument("--out", default=None)
    ap.add_argument("--task-id", default="T11.repo-merge-raw")
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    run = os.path.abspath(args.run) if args.run else None
    peer = os.path.abspath(args.peer) if args.peer else None
    outdir = args.out or os.path.join(root, "build", "manifest")
    os.makedirs(outdir, exist_ok=True)

    def rel_root(p):
        return os.path.relpath(p, root).replace("\\", "/")

    prov = []
    for path in collect(root, skip_dirs=(".git", "build", "work")):
        entry = {"path": rel_root(path), "sha256": sha256(path), "origin": "repo_copy"}
        if peer:
            src = os.path.join(peer, entry["path"].replace("/", os.sep))
            if os.path.exists(src):
                s = sha256(src)
                if s == entry["sha256"]:
                    entry["origin"] = "peer_unchanged"
                else:
                    entry["origin"] = "peer_modified"
                    entry["peer_sha256"] = s
        prov.append(entry)

    def entries(sub):
        base = os.path.join(root, sub.replace("/", os.sep))
        return sorted(({"path": rel_root(p), "sha256": sha256(p)} for p in collect(base)),
                      key=lambda e: e["path"])

    prod = []
    for sub in ("rtl", "constraints", "al_ip"):
        prod += entries(sub)
    prod.sort(key=lambda e: e["path"])
    scripts = entries("tools/pcie_integration")
    tbs = entries("sim")
    docs = entries("docs/protocol")

    rk = []
    arts = []
    if run:
        for base in (os.path.join(run, "raw", "rk-driver-src"), os.path.join(run, "raw", "patches")):
            for path in collect(base):
                rk.append({"path": os.path.relpath(path, run).replace("\\", "/"),
                           "sha256": sha256(path)})
        rk.sort(key=lambda e: e["path"])
        VOLATILE_SUFFIX = (".logw",)
        VOLATILE_NAMES = {"commands.log", "abs.f", "run.do", "vsim_stdout.log"}
        prj = os.path.join(run, "raw", "candidate", "prj")
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
                       (".bit", ".sbit", ".db", ".tsr", ".rpt", ".log", ".al", ".area", ".timing",
                        ".tsu", ".ts", ".qor", ".bid", ".params", ".status")):
                    arts.append({"path": rel, "sha256": sha256(p), "size": os.path.getsize(p)})
        arts.sort(key=lambda e: e["path"])

    man = {
        "schema": 2,
        "task_id": args.task_id,
        "round": 0,
        "candidate_root": "(checkout root)",
        "path_base": {
            "production_inputs": "checkout root",
            "build_scripts": "checkout root",
            "test_inputs": "checkout root",
            "protocol_mirror": "checkout root",
            "rk_patch_inputs": "run dir" if run else "",
            "build_artifacts": "run dir" if run else "",
        },
        "peer_frozen": args.peer or "",
        "production_inputs": prod,
        "build_scripts": scripts,
        "test_inputs": tbs,
        "protocol_mirror": docs,
        "rk_patch_inputs": rk,
        "build_artifacts": arts,
        "volatile_excluded": {
            "names": ["commands.log", "abs.f", "run.do", "vsim_stdout.log"],
            "patterns": ["td_*.log", "*.logw"],
        },
        "notes": [
            "生成器已适配 FPGA 原仓检出根：--root 指向检出根。",
            "生产输入=rtl/constraints/al_ip；构建脚本=tools/pcie_integration；测试输入=sim；协议镜像=docs/protocol。",
            "无 --run 时不含 RK 补丁与构建产物；无 --peer 时来源统一记 repo_copy。",
        ],
    }
    with open(os.path.join(outdir, "candidate-manifest.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(man, f, ensure_ascii=False, indent=2)
        f.write("\n")
    with open(os.path.join(outdir, "source-provenance.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump({"schema": 1, "checkout": "(root)", "files": prov}, f, ensure_ascii=False, indent=2)
        f.write("\n")

    bad = []
    checks = 0
    for cat, base in (("production_inputs", root), ("build_scripts", root),
                      ("test_inputs", root), ("protocol_mirror", root),
                      ("rk_patch_inputs", run), ("build_artifacts", run)):
        if base is None:
            continue
        for e in man[cat]:
            p = os.path.join(base, e["path"].replace("/", os.sep))
            checks += 1
            if not os.path.isfile(p):
                bad.append((cat, e["path"], "missing"))
            elif sha256(p) != e["sha256"]:
                bad.append((cat, e["path"], "sha-mismatch"))
    print("provenance=%d production=%d scripts=%d test_inputs=%d protocol=%d rk=%d artifacts=%d"
          % (len(prov), len(prod), len(scripts), len(tbs), len(docs), len(rk), len(arts)))
    print("self-check: %d entries, %d mismatches" % (checks, len(bad)))
    for b in bad[:20]:
        print("  MISMATCH", b)
    with open(os.path.join(outdir, "manifest-selfcheck.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump({"entries": checks,
                   "mismatches": [{"category": c, "path": p, "kind": k} for c, p, k in bad]},
                  f, ensure_ascii=False, indent=2)
        f.write("\n")
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
