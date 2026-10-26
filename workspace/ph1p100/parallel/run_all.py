#!/usr/bin/env python3
"""parallel 轨道统一回归入口：一条命令跑完本轨所有自检。

只读运行、不访问硬件、不修改生产文件。逐个子进程执行，收集各自的 PASS/FAIL 标记。

用法：
  python parallel/run_all.py                    # 不含 ModelSim 项
  python parallel/run_all.py --with-modelsim    # 追加 wrapper 4 lane 仿真（需要 ModelSim）
"""

from __future__ import annotations

import argparse
import datetime
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
OUTROOT = REPO / "parallel" / "evidence"

CASES = [
    ("tmds.model",      ["parallel/tmds/tmds_ref.py", "--selftest"],               "TMDS_SELFTEST PASS"),
    ("tmds.reference",  ["parallel/tmds/run_tmds_reference.py"],                   "TMDS_REFERENCE PASS"),
    ("frame.selftest",  ["parallel/frame/frame_contract.py", "--selftest"],        "FRAME_CONTRACT PASS"),
    ("frame.vectors",   ["parallel/frame/run_frame_contract.py"],                  "FRAME_CONTRACT_RUN PASS"),
    ("algo.selftest",   ["parallel/algorithms/image_algorithms_ref.py", "--selftest"], "IMG_ALGO PASS"),
    ("algo.vectors",    ["parallel/algorithms/run_image_algorithms_ref.py"],       "IMG_ALGO_RUN PASS"),
    ("pcie.tlp",        ["parallel/pcie/tlp_pack_ref.py", "--selftest"],           "TLP_PACK PASS"),
    ("rk.frame_io",     ["parallel/rk/frame_io.py"],                              "RK_FRAME_IO PASS"),
    ("rk.offline",      ["parallel/rk/run_rk_offline.py"],                        "RK_OFFLINE PASS"),
    ("rk.frame_stereo", ["parallel/rk/run_frame_to_stereo.py"],                   "FRAME_TO_STEREO PASS"),
    ("checks.xcross",   ["parallel/checks/cross_consistency.py"],                 "XCHECK_ALL PASS"),
    ("analysis.sparkle",["parallel/analysis/sparkle_stress.py"],                  "SPARKLE_STRESS PASS"),
    ("tmds.known_color",["parallel/tmds/known_color_record.py"],                  "HDMI_KNOWN_COLOR PASS"),
    ("pcie.first_test", ["parallel/pcie/first_test_data.py", "--selftest"],       "PCIE_TTD PASS"),
    ("pcie.e2e_soft",   ["parallel/pcie/run_e2e_soft_path.py"],                   "PCIE_E2E PASS"),
    ("rk.ingest_raw",   ["parallel/rk/ingest_raw.py", "--selftest"],              "INGEST PASS"),
    ("rk.c_cross",      ["parallel/rk/run_c_cross_check.py"],                     "C_CROSS_CHECK PASS"),
    ("rk.stereo_pipe",  ["parallel/rk/run_stereo_pipeline_check.py"],             "STEREO_CHECK PASS"),
]
MODELSIM_CASES = [
    ("tmds.physlanes", ["parallel/tmds/run_tmds_phy_lanes.py"], "PHY_LANES_EVIDENCE"),
    ("algo.rtl_tb",    ["parallel/algorithms/run_algo_tb.py"], "ALGO_TB_EVIDENCE"),
    ("b3.rom_serial",  ["parallel/experiments/run_tmds_pattern_rom.py"], "ROM_TB_EVIDENCE"),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--with-modelsim", action="store_true")
    a = ap.parse_args()

    cases = list(CASES) + (MODELSIM_CASES if a.with_modelsim else [])
    out = OUTROOT / ("run_all_" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S"))
    out.mkdir(parents=True, exist_ok=True)

    rows = []
    all_ok = True
    for name, argv, marker in cases:
        cmd = [sys.executable, str(REPO / argv[0])] + list(argv[1:])
        r = subprocess.run(cmd, cwd=REPO, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=1800)
        text = r.stdout.decode("utf-8", errors="replace")
        (out / (name + ".log")).write_text(text, encoding="utf-8")
        # 各 runner 失败时会 SystemExit(1)；因此以退出码 + 成功标记为准
        ok = (r.returncode == 0) and (marker in text)
        all_ok = all_ok and ok
        tail = text.strip().splitlines()[-1] if text.strip() else ""
        rows.append({"case": name, "ok": ok, "exit": r.returncode,
                     "marker": marker, "tail": tail})
        line = "%-16s %s  (%s)" % (name, "PASS" if ok else "FAIL", tail[:90])
        print(line.encode("ascii", "replace").decode("ascii"))

    summary = {"date": datetime.date.today().isoformat(), "cases": rows,
               "result": "pass" if all_ok else "fail"}
    (out / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    print("RUN_ALL_DIR", out)
    print("RUN_ALL", "PASS" if all_ok else "FAIL", "cases=%d" % len(rows))
    if not all_ok:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
