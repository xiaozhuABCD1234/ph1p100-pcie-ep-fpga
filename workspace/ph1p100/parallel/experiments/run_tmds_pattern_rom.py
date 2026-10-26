#!/usr/bin/env python3
"""运行 B3 的 ROM → wrapper 串行位序验证（需要 ModelSim）。

步骤：
  1) `gen_rom.py` 产出 ROM 内容（位反转字段）与**自然形式**的期望码；
  2) 用真实 vendor IO 模型编译 ROM + 明文 `hdmi_tx_phy_wrapper` + TB；
  3) 正常情形必须 `ROM_TB_PASS`；
  4) 负对照：把 ROM 里某个字段改成**不反转**（模拟"位序搞反"）→ 必须 `ROM_TB_FAIL`。

不生成位流、不访问硬件、不改主仓库任何文件。
"""

from __future__ import annotations

import datetime
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BIN = Path(r"D:/intelFPGA/18.1/modelsim_ase/win32aloem")
MODELS = Path(r"D:/downlaod/sim_release/ph1p")
IP = REPO / "fpga/csi2/prj/camera_peer/uisrc/03_ip/alip/ui_HDMI_TX"
EXP = REPO / "parallel" / "experiments"
OUTROOT = Path(r"D:/TD/work/csi2/_validation")
DEPTH = 20


def analyze(capture: Path, expect_dir: Path, dep: int):
    """在 Python 里分析抓到的串行流：真实位率（周期）与位序。"""
    lanes = []
    with capture.open(encoding="utf-8") as f:
        cols = [[], [], [], []]
        for line in f:
            parts = line.split()
            if len(parts) != 4:
                continue
            for i in range(4):
                cols[i].append(parts[i])
    exp = {}
    for name in ("ch0", "ch1", "ch2", "clk"):
        exp[name] = [int(x, 16) for x in
                     (expect_dir / ("short_expect_%s.hex" % name)).read_text().split()]

    def natural_bits(codes, msb_first=True):
        out = []
        for c in codes:
            bits = format(c, "010b")
            out.extend(bits if msb_first else bits[::-1])
        return out

    report = {}
    for li, lname in enumerate(("ch0", "ch1", "ch2", "clk")):
        s = cols[li]
        ones = sum(1 for b in s if b == "1")
        # 自相关找周期
        best_period, best_score = None, -1
        for p in range(50, min(600, len(s) // 2)):
            score = sum(1 for i in range(len(s) - p) if s[i] == s[i + p])
            if score > best_score:
                best_score, best_period = score, p
        report[lname] = {"ones": ones, "len": len(s), "period": best_period,
                         "period_score": best_score}
        # 在最佳周期/对齐下比较两种位序
        if best_period:
            spb = best_period / (dep * 10.0)      # 每个 bit 占多少采样点
            win = min(best_period, 300)
            for order, msb in (("MSB", True), ("LSB", False)):
                eb = natural_bits(exp[lname], msb)
                best, best_start = 0, 0
                for start in range(0, max(1, min(300, len(s) - win - 1))):
                    ok = 0
                    for j in range(win):
                        k = int(j / spb)
                        if k >= len(eb):
                            break
                        if (s[start + j] == "1") == bool(eb[k]):
                            ok += 1
                    if ok > best:
                        best, best_start = ok, start
                report[lname]["match_" + order] = {"ok": best, "of": win, "start": best_start}
    return report


def run_case(work: Path, rom: Path, expect_pass: bool, phase: int = 500) -> bool:
    work.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(rom, work / "pattern_rom.hex")
    for suffix in ("ch0", "ch1", "ch2", "clk"):
        shutil.copyfile(EXP / ("short_expect_%s.hex" % suffix), work / ("expect_%s.hex" % suffix))
    vecdir = str(work).replace("\\", "/")
    sources = [MODELS / "ph1p_phy_gsr.v", MODELS / "ph1p_phy_hr_pad.v", MODELS / "ph1p_logic_hrio.v",
               IP / "hdmi_phy_warpper.v", IP / "lane_lvds_10_1.v",
               EXP / "tmds_pattern_rom.v", EXP / "tb_tmds_pattern_rom.sv"]
    missing = [str(s) for s in sources if not s.exists()]
    if missing:
        print("ROM_TB_INCOMPLETE missing:", missing)
        raise SystemExit(2)
    cmds = [[str(BIN / "vlib.exe"), "work"],
            [str(BIN / "vlog.exe"), "-sv", *[str(s) for s in sources]],
            [str(BIN / "vsim.exe"), "-c", "-t", "1fs", "+notimingchecks", "-voptargs=+acc",
             "-gDEPTH=%d" % DEPTH, "work.tb_tmds_pattern_rom", "work.PH1P_PHY_GSR",
             "+VECDIR=" + vecdir, "+DIAG", "+PHASE=%d" % phase, "-do", "run -all; quit -f"]]
    logs = []
    for i, cmd in enumerate(cmds):
        r = subprocess.run(cmd, cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=600)
        text = r.stdout.decode("utf-8", errors="replace")
        logs.append(text)
        (work / "regression.log").write_text("\n".join(logs), encoding="utf-8")
        print(text[-1500:].encode("ascii", "replace").decode("ascii"), flush=True)
        if i == 2:
            if expect_pass:
                if r.returncode or "ROM_TB_PASS" not in text or "ROM_TB_FAIL" in text:
                    return False
            else:
                if r.returncode or "ROM_TB_FAIL" not in text or "ROM_TB_PASS" in text:
                    return False
    return True


def make_mutant(src: Path, dst: Path) -> bool:
    """把第 0 个 ROM 字的 ch0 字段改成**不反转**的形式（位序搞反）。"""
    lines = src.read_text(encoding="utf-8").strip().splitlines()
    w = int(lines[0], 16)
    ch0_rev = w & 0x3FF
    ch0_nat = int(format(ch0_rev, "010b")[::-1], 2)          # 反转回去 = 自然码
    mutated = (w & ~0x3FF) | (ch0_nat & 0x3FF)
    lines[0] = "%010X" % mutated
    dst.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return mutated != w


def main():
    out = OUTROOT / ("rom_tb_" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S_%f"))
    out.mkdir(parents=True, exist_ok=False)

    gen = subprocess.run([sys.executable, str(EXP / "gen_rom.py"), "--out", str(EXP),
                          "--name", "short", "--length", str(DEPTH)],
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    print(gen.stdout.decode("utf-8", errors="replace").encode("ascii", "replace").decode("ascii"))
    rom = EXP / "short_rom.hex"

    # TB 自身已做 8× 过采样 + 8 相位扫描，采样相位不再需要外部指定。
    ok_normal = run_case(out / "normal", rom, True, 500)

    if not ok_normal:
        import json
        cap = out / "normal" / "capture.txt"
        rep = analyze(cap, EXP, DEPTH) if cap.exists() else {"error": "no capture"}
        (out / "capture_analysis.json").write_text(json.dumps(rep, indent=2), encoding="utf-8")
        print("ROM_TB_ANALYSIS", json.dumps(rep, ensure_ascii=False))
        print("ROM_TB_NOT_PASSING", out)
        raise SystemExit(2)

    mut = out / "mutant" / "short_rom_mutant.hex"
    mut.parent.mkdir(parents=True, exist_ok=True)
    if not make_mutant(rom, mut):
        print("ROM_TB_INCOMPLETE mutant not created")
        raise SystemExit(2)
    ok_mutant = run_case(out / "mutant", mut, False)
    if ok_mutant:
        print("ROM_TB_EVIDENCE", out)
    else:
        print("ROM_TB_INCOMPLETE normal=1 mutant_rejected=%s" % ok_mutant, out)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
