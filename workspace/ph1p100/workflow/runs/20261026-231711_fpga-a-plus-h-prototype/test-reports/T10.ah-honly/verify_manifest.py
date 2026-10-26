#!/usr/bin/env python3
"""Independent tester verification for T10.ah-honly r0.

Checks (read-only; writes only a JSON summary under the tester evidence dir):
 1. manifest SHA-256 and every artifact's bytes/SHA-256.
 2. artifact path set: no missing, no extra files under r0/ outside the manifest.
 3. frozen input hashes vs the declared frozen values and vs the upstream
    P1/P2/b11/b6 source files.
 4. write-scope scan of the run dir.
"""
import hashlib
import json
import os
import sys

RUN = r"D:/fpga/ph1p100/workflow/runs/20261026-231711_fpga-a-plus-h-prototype"
TASK = os.path.join(RUN, "T10.ah-honly")
R0 = os.path.join(TASK, "r0")
MAN = os.path.join(R0, "manifest-r0.json")
OUT = os.path.join(RUN, "test-reports", "T10.ah-honly", "verify-manifest-result.json")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    res = {"manifest": {}, "artifacts": {"missing": [], "size_mismatch": [], "sha_mismatch": [], "ok": 0},
           "extra_files": [], "frozen_inputs": {}, "write_scope": {}}
    res["manifest"]["path"] = MAN
    res["manifest"]["sha256"] = sha256(MAN)
    res["manifest"]["bytes"] = os.path.getsize(MAN)
    with open(MAN, "r", encoding="utf-8") as f:
        man = json.load(f)

    listed = set()
    for a in man["artifacts"]:
        rel = a["path"]
        listed.add(rel.replace("/", os.sep))
        p = os.path.join(R0, rel)
        if not os.path.isfile(p):
            res["artifacts"]["missing"].append(rel)
            continue
        actual_bytes = os.path.getsize(p)
        actual_sha = sha256(p)
        if actual_bytes != a["bytes"]:
            res["artifacts"]["size_mismatch"].append([rel, a["bytes"], actual_bytes])
        if actual_sha != a["sha256"]:
            res["artifacts"]["sha_mismatch"].append([rel, a["sha256"], actual_sha])
        if actual_bytes == a["bytes"] and actual_sha == a["sha256"]:
            res["artifacts"]["ok"] += 1
    res["artifacts"]["declared"] = len(man["artifacts"])
    res["artifacts"]["counts_field"] = man.get("counts", {}).get("artifacts")
    res["artifacts"]["stopped_modifying"] = man.get("stopped_modifying")
    res["artifacts"]["active_commands"] = man.get("active_commands")
    res["artifacts"]["write_scope"] = man.get("write_scope")
    res["artifacts"]["frozen_inputs_field"] = man.get("frozen_inputs")

    # Extra files under r0/ that are not in the manifest
    for root, dirs, files in os.walk(R0):
        for fn in files:
            full = os.path.join(root, fn)
            rel = os.path.relpath(full, R0)
            if rel not in listed:
                res["extra_files"].append(rel.replace(os.sep, "/"))

    # Frozen input checks: manifest-first, then the canonical source paths
    expected = {
        "src/a1_deflate_core.v": "a91c2ed82fbef654c4e065b64ae1cc268ca232feaa26fdd313c58d8740f81b3e",
        "src/a1_frame_top.v": "0064607aceb20ae3ef14133f0aaf5f8b3f489943011a66a1ddc005350dba7109",
        "src/ref_b11_a1_deflate_core.v": "a91c2ed82fbef654c4e065b64ae1cc268ca232feaa26fdd313c58d8740f81b3e",
        "src/ref_b11_a1_frame_top.v": "0064607aceb20ae3ef14133f0aaf5f8b3f489943011a66a1ddc005350dba7109",
        "src/ref_b6_a1_deflate_core.v": "6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb",
        "src/tb_a1_deflate_core.v": "910aea54e0d8d40a02a7d5e7844b053fff1f86e24cbfc43d1c33f083da5af09e",
        "src/tb_ss_4run_wd.v": "785c3ef1d044f8529b7232ae37ed3a67172b6c4cd512c47a713103675090b79a",
        "src/tb_ss_4run_wd_probe.v": "d2aa6cc09b8c091a3581dee02f2d556c2384f67d1ee2ee2a705c250933f86c31",
        "src/content/raw40_n.hex": "e44fe7bc89aaa3ada2422a41fcfb8e283d5f66cdffda29b2caf4da10d2cd7b53",
        "src/content/raw40_l.hex": "e7e3c21cd2e4cc18e115b4cf18692596450cfcfc7605297046e3840c67deefa2",
    }
    for rel, exp in expected.items():
        p = os.path.join(R0, rel)
        got = sha256(p) if os.path.isfile(p) else "missing"
        res["frozen_inputs"][rel] = {"expected": exp, "actual": got, "ok": got == exp}

    # Canonical upstream files (same run project): the src copies must equal them.
    upstream = {
        "src/a1_deflate_core.v": r"D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read/r0/changed-src/a1_deflate_core.v",
        "src/a1_frame_top.v": r"D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read/r0/changed-src/a1_frame_top.v",
        "src/ref_b6_a1_deflate_core.v": r"D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw/r0/changed-src/a1_deflate_core.v",
        "src/tb_a1_deflate_core.v": r"D:/fpga/ph1p100/upstream/ph1p100-pcie-ep-fpga/sim/tb/codec/tb_a1_deflate_core.v",
        "src/tb_ss_4run_wd.v": r"D:/fpga/ph1p100/workflow/runs/20261026-143924_fpga-1080p30-g0-production/T10.ss-g0-prod-content/r0/src/tb_ss_4run_wd.v",
        "src/tb_ss_4run_wd_probe.v": r"D:/fpga/ph1p100/workflow/runs/20261026-143924_fpga-1080p30-g0-production/T10.ss-g0-prod-coregap/r0/src/tb_ss_4run_wd_probe.v",
        "src/content/raw40_n.hex": r"D:/fpga/ph1p100/workflow/runs/20261026-143924_fpga-1080p30-g0-production/T10.ss-g0-prod-content/r0/content/raw40_n.hex",
        "src/content/raw40_l.hex": r"D:/fpga/ph1p100/workflow/runs/20261026-143924_fpga-1080p30-g0-production/T10.ss-g0-prod-content/r0/content/raw40_l.hex",
    }
    res["upstream_sources"] = {}
    for rel, up in upstream.items():
        p = os.path.join(R0, rel)
        got = sha256(p) if os.path.isfile(p) else "missing"
        ups = sha256(up) if os.path.isfile(up) else "missing"
        res["upstream_sources"][rel] = {"copy": got, "upstream": ups, "ok": got == ups}

    # 10 unchanged DUT copies vs the P1 frozen src dir
    p1src = r"D:/fpga/ph1p100/workflow/runs/20261026-143924_fpga-1080p30-g0-production/T10.ss-g0-prod-content/r0/src"
    other = ["a1_ddr_arb2.v", "a1_ddr_model.v", "a1_ddr_slot_store.v", "a1_raw_crop.v",
             "a1_uart_export.v", "camera_a1_uart_top.v", "cam_diag_mailbox.v",
             "capture_async_fifo.v", "p2_ddr_bridge.v", "p2_paxi_model_b11.v"]
    res["unchanged_dut"] = {}
    for n in other:
        p = os.path.join(R0, "src", n)
        q = os.path.join(p1src, n)
        got = sha256(p) if os.path.isfile(p) else "missing"
        ref = sha256(q) if os.path.isfile(q) else "missing"
        res["unchanged_dut"][n] = {"copy": got, "p1": ref, "ok": got == ref}

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(res, f, indent=2)
    print("manifest sha256:", res["manifest"]["sha256"])
    print("artifacts ok:", res["artifacts"]["ok"], "/", res["artifacts"]["declared"])
    print("missing:", res["artifacts"]["missing"])
    print("size_mismatch:", res["artifacts"]["size_mismatch"])
    print("sha_mismatch:", res["artifacts"]["sha_mismatch"])
    print("extra_files:", res["extra_files"])
    print("frozen_inputs_all_ok:", all(v["ok"] for v in res["frozen_inputs"].values()))
    print("upstream_all_ok:", all(v["ok"] for v in res["upstream_sources"].values()))
    print("unchanged_dut_all_ok:", all(v["ok"] for v in res["unchanged_dut"].values()))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
