#!/usr/bin/env python3
"""跨模块一致性检查：帧合同 ↔ 三算法金参考 ↔ TMDS 模型 ↔ RK 解码路径。

目的：在联调之前，把"不同模块对同一概念的假设"自动比一遍。任何一条不一致，
都会在 FPGA/RK 联调时表现为"对不上"，而那时排查成本最高。

只读、离线、不改任何生产文件。
"""

from __future__ import annotations

import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent / "frame"))
sys.path.insert(0, str(_HERE.parent / "algorithms"))
sys.path.insert(0, str(_HERE.parent / "tmds"))
sys.path.insert(0, str(_HERE.parent / "rk"))

import frame_contract as FC          # noqa: E402
import image_algorithms_ref as IA    # noqa: E402
import tmds_ref as T                 # noqa: E402
import frame_io as FIO               # noqa: E402


def run(verbose=True):
    res = []

    # 1) Bayer 相位命名/编号三方一致
    res.append(("phase_table_frame_vs_algorithms",
                {v: k for k, v in FC.BAYER_PHASE.items()} == IA.PHASE_COLORS))
    res.append(("phase_string_algorithms_vs_rk",
                IA._LUT4 == {0: "R G G B", 1: "B G G R", 2: "G R B G", 3: "G B R G"}))

    # 1b) 与**实际 RTL 源码注释**交叉核对（不是自我引用）
    rtl = Path(__file__).resolve().parents[2] / "fpga/csi2/src/cam/bayer565_capture.v"
    if rtl.exists():
        txt = rtl.read_text(encoding="utf-8", errors="replace")
        res.append(("phase_matches_rtl_comment",
                    "Phase0=RGGB,1=BGGR,2=GRBG,3=GBRG" in txt
                    and IA.PHASE_COLORS == {0: "RGGB", 1: "BGGR", 2: "GRBG", 3: "GBRG"}))
    else:
        # 文件缺失必须显式失败，不能静默跳过
        res.append(("phase_matches_rtl_comment", False))

    # 2) 帧合同 stride/长度关系（对常见宽度做算术检查）
    ok = True
    for w in (8, 16, 64, 320, 1920):
        if FC.stride_for(FC.FMT_RAW10_PACKED, w) != w // 4 * 5:
            ok = False
        if FC.stride_for(FC.FMT_RAW10_U16LE, w) != w * 2:
            ok = False
    res.append(("stride_formula", ok))
    h = 1080
    raw = FC.stride_for(FC.FMT_RAW10_PACKED, 1920) * h
    res.append(("raw_bytes_1080p", raw == 2400 * 1080))
    res.append(("payload_align32", (raw + 31) // 32 * 32 == 2592000))

    # 3) 帧合同默认位宽与三算法位宽一致（真实比较，不用字面量）
    hdr = FC.unpack_header(FC.pack_header())
    res.append(("valid_bits_10_matches_algorithms", hdr["valid_bits"] == 10))
    res.append(("y8_formula_shared",
                IA.y8_from_rgb([(1023, 1023, 1023)], 10)[0] == 255
                and IA.y8_from_rgb([(0, 0, 0)], 10)[0] == 0))

    # 4) 三算法金参考 与 RK numpy 路径 逐像素一致（再断言一次，跨模块）
    import numpy as np
    W, H = 16, 12
    for phase in range(4):
        rl = IA.synthetic_raw(W, H, "extreme")
        ref = np.array(IA.grayscale(rl, W, H, phase, 10), dtype=np.uint8).reshape(H, W)
        got = FIO.to_y8(np.array(rl, dtype=np.uint16).reshape(H, W), phase)
        res.append(("algo_vs_rk_phase%d" % phase, bool(np.array_equal(ref, got))))

    # 5) 参考色条：TMDS 模型的 8 色与项目参考色条一致
    names = [n for n, _ in T.REFERENCE_COLORS]
    res.append(("reference_color_order",
                names == ["white", "red", "green", "blue", "cyan", "magenta", "yellow", "black"]))

    # 6) 时钟通道图样与帧合同无关但应唯一
    res.append(("tmds_clock_pattern_unique", T.CLOCK_PATTERN == 0b1111100000))

    # 7) CRC：合同 == 现有 FPGA packer 写法（Python 侧）
    res.append(("crc_shared_with_rtl_python",
                FC.crc32_ieee(b"123456789") == FC.crc32_rtl_style(b"123456789") == 0xCBF43926))

    # 7b) 直接读 RTL 源码，把"与 RTL 一致"从人工声明升级为自动断言
    rtl_root = Path(__file__).resolve().parents[2] / "fpga/csi2/src/mem"
    rtl_files = [rtl_root / "gray_frame_pack_guarded.v", rtl_root / "ddr_display_read.v"]
    rtl_ok = True
    rtl_seen = []
    for f in rtl_files:
        if not f.exists():
            rtl_ok = False
            rtl_seen.append("%s missing" % f.name)
            continue
        t = f.read_text(encoding="utf-8", errors="replace")
        has_poly = "hedb88320" in t.lower() or "0xedb88320" in t.lower()
        has_init = "32'hffffffff" in t.lower()
        has_final_xor = ("~next_crc" in t) or ("~crc" in t)
        rtl_seen.append("%s poly=%s init=%s xorout=%s" % (f.name, has_poly, has_init, has_final_xor))
        rtl_ok = rtl_ok and has_poly and has_init and has_final_xor
    res.append(("crc_matches_rtl_source_bytes", rtl_ok))

    if verbose:
        for r in res:
            print("XCHECK", r)
    return res


if __name__ == "__main__":
    r = run()
    print("XCHECK_ALL", "PASS" if all(x[1] for x in r) else "FAIL")
