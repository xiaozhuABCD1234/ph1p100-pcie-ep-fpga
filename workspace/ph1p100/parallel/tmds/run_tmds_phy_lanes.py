#!/usr/bin/env python3
"""用真实 vendor IO 模型校验明文 hdmi_tx_phy_wrapper 的 4 lane 组合。

只做功能仿真（+notimingchecks），不访问硬件、不生成位流、不修改生产 RTL。
覆盖 tb_hdmi_native_stream 没有的一层：wrapper 位反转 + lane 位反转 的组合。

包含一个负对照（mutant）：把 lane 的位反转改成直通，TB 必须拒绝，
以证明该测试确实能感知位序变化，而不是恒过。

用法：python tools/td/run_tmds_phy_lanes.py
"""

from __future__ import annotations

import datetime
import re
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
MODELS = Path(r"D:/downlaod/sim_release/ph1p")
BIN = Path(r"D:/intelFPGA/18.1/modelsim_ase/win32aloem")
IP = REPO / "fpga/csi2/prj/camera_peer/uisrc/03_ip/alip/ui_HDMI_TX"
TB = REPO / "parallel/tmds"
OUTROOT = Path(r"D:/TD/work/csi2/_validation")


def _safe(text: str) -> str:
    return text[-2500:].encode("ascii", "replace").decode("ascii")


def run_case(out: Path, lane: Path, expect_pass: bool, tag: str) -> bool:
    sources = [MODELS / "ph1p_phy_gsr.v", MODELS / "ph1p_phy_hr_pad.v",
               MODELS / "ph1p_logic_hrio.v", IP / "hdmi_phy_warpper.v",
               lane, TB / "tb_hdmi_phy_lanes.sv"]
    missing = [str(s) for s in sources if not s.exists()]
    if missing:
        print("PHY_LANES_INCOMPLETE missing:", missing)
        raise SystemExit(2)
    work = out / tag
    work.mkdir(parents=True, exist_ok=True)
    cmds = [[str(BIN / "vlib.exe"), "work"],
            [str(BIN / "vlog.exe"), "-sv", *[str(s) for s in sources]]]
    cmds += [[str(BIN / "vsim.exe"), "-c", "-t", "1fs", "+notimingchecks",
              "-voptargs=+acc", "-gPHASE_PS=%d" % ph, "work.tb_hdmi_phy_lanes",
              "work.PH1P_PHY_GSR", "-do", "run -all; quit -f"] for ph in (0, 250, 750)]
    logs = []
    ok = True
    for i, cmd in enumerate(cmds):
        r = subprocess.run(cmd, cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        text = r.stdout.decode("utf-8", errors="replace")
        logs.append(text)
        (work / "regression.log").write_text("\n".join(logs), encoding="utf-8")
        print(_safe(text), flush=True)
        passed = "PHY_LANES_PASS" in text and "PHY_LANES_FAIL" not in text
        if r.returncode or (i >= 2 and passed != expect_pass):
            ok = False
    return ok


def main():
    out = OUTROOT / ("tmds_phy_lanes_" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S_%f"))
    out.mkdir(parents=True, exist_ok=False)

    # 正常：生产 lane
    normal_ok = run_case(out, IP / "lane_lvds_10_1.v", True, "normal")

    # 负对照：把 lane PH1P 分支的位反转换成直通，TB 必须拒绝
    mut_text = re.sub(r"wire \[9:0\] native_data = \{[^;]*\};",
                      "wire [9:0] native_data = I_data_in;",
                      (IP / "lane_lvds_10_1.v").read_text(encoding="utf-8"), flags=re.S)
    if "native_data = I_data_in;" not in mut_text:
        print("PHY_LANES_INCOMPLETE mutant substitution failed")
        raise SystemExit(2)
    mut_lane = out / "lane_mutant.v"
    mut_lane.write_text(mut_text, encoding="utf-8")
    mutant_ok = run_case(out, mut_lane, False, "mutant")

    if normal_ok and mutant_ok:
        print("PHY_LANES_EVIDENCE", out)
    else:
        print("PHY_LANES_INCOMPLETE normal_ok=%s mutant_rejected=%s" % (normal_ok, mutant_ok), out)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
