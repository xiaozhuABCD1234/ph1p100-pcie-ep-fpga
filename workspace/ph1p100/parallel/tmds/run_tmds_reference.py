#!/usr/bin/env python3
"""运行独立 TMDS 参考模型并归档证据。

不访问硬件、不调用 TD、不修改任何 RTL/约束/位流。仅：
  1) 自检（控制令牌 / 全 256 往返 / DC 界 / 参考色往返）；
  2) 与 Project F 的 MIT 算法**独立交叉核对**（另一个实现，bias=0 全 256）；
  3) 输出参考色条、灰阶、压力图样的码字与物理层度量；
  4) 写证据目录 + result.json。

用法：
  python tools/td/run_tmds_reference.py            # 时间戳目录
  python tools/td/run_tmds_reference.py --out DIR  # 指定目录
"""

from __future__ import annotations

import argparse
import datetime
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tmds_ref as T  # noqa: E402

REPO = Path(__file__).resolve().parents[2]


# --- Project F 的 MIT 算法（独立实现，用于交叉核对），原样搬入便于比对 ---
def _pf_bin_array_8(integer):
    b = [int(i) for i in reversed(bin(integer)[2:])]
    return b + [0 for _ in range(8 - len(b))]


def _pf_tmds(d, _decimal):
    q_m = [None] * 9
    one_cnt_d = sum(d)
    if one_cnt_d > 4 or (one_cnt_d == 4 and d[0] == 0):
        q_m[0] = d[0]
        for i in range(1, 8):
            q_m[i] = int(q_m[i - 1] == d[i])
        q_m[8] = 0
    else:
        q_m[0] = d[0]
        for i in range(1, 8):
            q_m[i] = int(q_m[i - 1] ^ d[i])
        q_m[8] = 1
    return q_m


def _pf_bias(q_m, bias):
    q_out = [None] * 10
    one_cnt = sum(q_m[0:8])
    zero_cnt = 8 - one_cnt
    if bias == 0 or one_cnt == 4:
        q_out[9] = int(not q_m[8])
        q_out[8] = q_m[8]
        if q_m[8] == 0:
            q_out[:8] = [int(not i) for i in q_m[:8]]
            bias = bias + zero_cnt - one_cnt
        else:
            q_out[:8] = q_m[:8]
            bias = bias + one_cnt - zero_cnt
    else:
        if (bias > 0 and one_cnt > zero_cnt) or (bias < 0 and one_cnt < zero_cnt):
            q_out[9] = 1
            q_out[8] = q_m[8]
            q_out[:8] = [int(not i) for i in q_m[:8]]
            bias = bias + 2 * q_m[8] + zero_cnt - one_cnt
        else:
            q_out[9] = 0
            q_out[8] = q_m[8]
            q_out[:8] = q_m[:8]
            bias = bias - 2 * (not q_m[8]) + one_cnt - zero_cnt
    return q_out, bias


def _pf_encode(d, bias=0):
    q_m = _pf_tmds(_pf_bin_array_8(d), d)
    q_out, _ = _pf_bias(q_m, bias)
    return T.bits_to_int(q_out)


def crosscheck_projectf():
    """我们与 Project F 在 bias=0、全 256 数据上的输出必须逐位一致。"""
    mismatches = [d for d in range(256) if T.encode_channel(d, 0, True, 0)[0] != _pf_encode(d, 0)]
    return mismatches


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    # 固定目录 + 证据版本字段（避免每次回归刷出一堆时间戳目录）
    out = Path(a.out) if a.out else REPO / "parallel" / "evidence" / "tmds_reference"
    out.mkdir(parents=True, exist_ok=True)

    sys.path.insert(0, str(REPO / "parallel"))
    import meta  # noqa: E402
    result = {"kind": "tmds-independence-check", "date": datetime.date.today().isoformat(),
              "evidence_meta": meta.evidence_meta(__file__)}

    # 1) 自检
    st = T.selftest(verbose=False)
    result["selftest"] = [{"name": n, "ok": bool(ok), "extra": (e[0] if e else None)} for n, ok, *e in st]
    selftest_ok = all(ok for _, ok, *_ in st)

    # 2) 与 Project F 独立交叉核对
    mism = crosscheck_projectf()
    result["projectf_crosscheck"] = {"checked": 256, "mismatches": mism,
                                     "ok": len(mism) == 0}

    # 3) 参考色条
    color_rows = []
    for name, rgb, (c0, c1, c2, clk) in T.encode_sequence(T.REFERENCE_COLORS):
        color_rows.append({
            "name": name, "rgb": "%02X%02X%02X" % rgb,
            "ch0": T.format_msb(c0, 10), "ch1": T.format_msb(c1, 10),
            "ch2": T.format_msb(c2, 10), "clk": T.format_msb(clk, 10),
        })
    (out / "reference_colors.txt").write_text(
        "\n".join("{} {} ch0={} ch1={} ch2={} clk={}".format(
            r["name"], r["rgb"], r["ch0"], r["ch1"], r["ch2"], r["clk"]) for r in color_rows),
        encoding="utf-8")
    result["reference_colors"] = color_rows

    # 4) 灰阶
    gray_rows = []
    for name, rgb, (c0, c1, c2, clk) in T.encode_sequence(T.grayscale_ramp(16)):
        gray_rows.append({"name": name, "gray": rgb[0],
                          "ch0": T.format_msb(c0, 10), "ch1": T.format_msb(c1, 10),
                          "ch2": T.format_msb(c2, 10)})
    (out / "grayscale16.txt").write_text(
        "\n".join("{} value={} ch0={} ch1={} ch2={}".format(
            r["name"], r["gray"], r["ch0"], r["ch1"], r["ch2"]) for r in gray_rows),
        encoding="utf-8")

    # 5) 压力图样度量
    stress = {}
    for kind in ("extreme_alt", "checker", "gray_alt", "flat"):
        enc = T.TmdsEncoder()
        stream = []
        for _, rgb in T.stress_pattern(kind):
            codes = enc.encode(rgb[0], rgb[1], rgb[2], True)
            stream.extend(enc.serial_bits(codes[:3]))
        stress[kind] = {"transition_density": round(T.transition_density(stream), 6),
                        "serial_imbalance_peak": T.serial_imbalance_peak(stream)}
    result["stress"] = stress

    # 6) DC 平衡行为：同一颜色连续多拍，码字会交替（说明不能只看几个像素）
    runs = {}
    for name, value in (("white", 0xFF), ("black", 0x00), ("mid", 0x80)):
        enc = T.TmdsEncoder()
        codes = [enc.encode(value, value, value, True)[0] for _ in range(8)]
        runs[name] = [T.format_msb(c, 10) for c in codes]
    result["dc_balance_runs"] = runs
    (out / "dc_balance_runs.txt").write_text(
        "\n".join("{}: {}".format(k, " ".join(v)) for k, v in runs.items()), encoding="utf-8")

    ok = selftest_ok and result["projectf_crosscheck"]["ok"]
    result["result"] = "pass" if ok else "fail"
    (out / "result.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")

    print("TMDS_REFERENCE_DIR", out)
    print("TMDS_REFERENCE", "PASS" if ok else "FAIL",
          "selftest=%s projectf_mismatch=%d" % (selftest_ok, len(mism)))
    if not ok:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
