#!/usr/bin/env python3
"""运行三算法测试台（B1）。

用金参考向量（checker 帧 + ramp 帧的 LUT）驱动 `tb_image_algo_stream.sv`：
  * 正常 DUT（回放 stub）→ 必须 ALGO_TB_PASS（验证测试台管线可用）
  * mutant（stub 注入一处错误）→ 必须 ALGO_TB_FAIL（验证测试台真的会报错）

注意：本 runner 验证的是**测试台**，不是算法 RTL——真正的算法由主线实现后替换
编译列表里的 stub 即可。需要 ModelSim。
"""

from __future__ import annotations

import datetime
import shutil
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BIN = Path(r"D:/intelFPGA/18.1/modelsim_ase/win32aloem")
VEC = REPO / "parallel" / "evidence" / "image_algorithms_20261015"
TB = REPO / "parallel" / "algorithms" / "tb_image_algo_stream.sv"
STUB = REPO / "parallel" / "algorithms" / "algo_tb_stub.sv"
OUTROOT = Path(r"D:/TD/work/csi2/_validation")

# 用 checker 帧 + ramp 帧的 LUT：三路都非平凡
FILES = {
    "raw10.hex": "checker_raw10.hex",
    "y8.hex": "checker_y8.hex",
    "gauss.hex": "checker_gauss.hex",
    "he.hex": "he_frameB.hex",
}
LUT = "he_lut_after_ramp.hex"


def run_case(work: Path, plusarg: str, expect_pass: bool) -> bool:
    work.mkdir(parents=True, exist_ok=True)
    for dst, src in FILES.items():
        shutil.copyfile(VEC / src, work / dst)
    shutil.copyfile(VEC / LUT, work / "lut.hex")
    vecdir = str(work).replace("\\", "/")

    vlog = [str(BIN / "vlog.exe"), "-sv", str(TB), str(STUB)]
    vsim = [str(BIN / "vsim.exe"), "-c", "-t", "1ns", "-voptargs=+acc",
            "work.tb_image_algo_stream", "+VECDIR=" + vecdir]
    if plusarg:
        vsim.append(plusarg)          # 运行时负对照开关（不用 +define+，避免被当成文件名）
    vsim += ["-do", "run -all; quit -f"]
    cmds = [[str(BIN / "vlib.exe"), "work"], vlog, vsim]
    logs = []
    for i, cmd in enumerate(cmds):
        r = subprocess.run(cmd, cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
        text = r.stdout.decode("utf-8", errors="replace")
        logs.append(text)
        (work / "regression.log").write_text("\n".join(logs), encoding="utf-8")
        print(text[-1200:].encode("ascii", "replace").decode("ascii"), flush=True)
        if i == 2:
            if expect_pass:
                # 通过情形必须出现 PASS 且无 FAIL
                if r.returncode or "ALGO_TB_PASS" not in text or "ALGO_TB_FAIL" in text:
                    return False
            else:
                # 负对照必须出现明确的 FAIL 标记（不能只靠"没有 PASS"）
                if r.returncode or "ALGO_TB_FAIL" not in text or "ALGO_TB_PASS" in text:
                    return False
    return True


def main():
    out = OUTROOT / ("algo_tb_" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S_%f"))
    out.mkdir(parents=True, exist_ok=False)
    missing = [str(p) for p in (BIN / "vsim.exe", TB, STUB) if not p.exists()]
    missing += [str(VEC / f) for f in list(FILES.values()) + [LUT] if not (VEC / f).exists()]
    if missing:
        print("ALGO_TB_INCOMPLETE missing:", missing)
        raise SystemExit(2)

    ok_normal = run_case(out / "normal", "", True)
    ok_mutant = run_case(out / "mutant", "+STUB_MUTATE", False)
    if ok_normal and ok_mutant:
        print("ALGO_TB_EVIDENCE", out)
    else:
        print("ALGO_TB_INCOMPLETE normal=%s mutant_rejected=%s" % (ok_normal, ok_mutant), out)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
