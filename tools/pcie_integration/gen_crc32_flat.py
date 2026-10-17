#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T11.rk-align-raw：把「4 字节/拍」的 CRC-32 递推写成合成友好并行形式（扁平 XOR 方程）。

用途：cam_r10f_writer.v（DDR 用户域 100MHz）在把 packed RAW10 载荷写进 DDR 的同时
每拍（4 字节）递推 R10F 的 payload_crc32 / raw_crc32（两者同值）。CRC 定义与合同
frame_contract.py 的 crc32_rtl_style 逐位一致：

    c = 0xFFFFFFFF
    每字节: v = c ^ b; 8 × (v = (v>>1) ^ (v[0] ? 0xEDB88320 : 0)); c = v
    final = ~c

本脚本：
  1) 用与合同相同的逐位定义在 Python 里重建递推；对 1..4 个实际字节做 GF(2)
     线性化：crc'(32) = L·crc(32) XOR D·data(8k)；
  2) 输出 Verilog 函数 crc32_upd1..upd4（按实际字节数推进，无 final XOR；末值由
     调用方取反），每个输出位是扁平 XOR 树（综合友好，逻辑深度 ~log6）；
  3) 自检：4 个变体各 20000 组随机 + 边界（全 0/全 F/交替/单 bit）与参考递推逐位
     一致，否则非 0 退出。

用法：
  python tools/pcie_integration/gen_crc32_flat.py            # 自检 + 打印 Verilog
  python tools/pcie_integration/gen_crc32_flat.py --out <file>
"""
import argparse
import random
import sys

POLY = 0xEDB88320  # reflected poly（与合同一致）


def crc32_byte_ref(c, b):
    """与合同 crc32_rtl_style 的每字节步逐位等价（c 为 32bit 内部状态）"""
    v = (c ^ b) & 0xFFFFFFFF
    for _ in range(8):
        v = (v >> 1) ^ (POLY if (v & 1) else 0)
    return v & 0xFFFFFFFF


def crc32_k_ref(crc, data, k):
    v = crc
    for i in range(k):
        v = crc32_byte_ref(v, data[i])
    return v & 0xFFFFFFFF


def build_matrices(k):
    """线性映射：crc'(32) = L·crc(32) XOR D·data(8k)（GF(2)），按 k 个实际字节推进"""
    L = [0] * 32   # L[j] = 32bit 掩码：输出位 j 对 32 个 crc 输入位的依赖
    D = [0] * 32   # D[j] = 32bit 掩码：输出位 j 对 8k 个数据输入位的依赖
    for i in range(32):
        base = crc32_k_ref(1 << i, [0] * 4, k)
        for j in range(32):
            if (base >> j) & 1:
                L[j] |= (1 << i)
    for i in range(8 * k):
        byte_idx, bit = i // 8, i % 8
        data = [0, 0, 0, 0]
        data[byte_idx] = 1 << bit
        base = crc32_k_ref(0, data, k)
        for j in range(32):
            if (base >> j) & 1:
                D[j] |= (1 << i)
    return L, D


def verify(n=20000, seed=0x7A11C0DE):
    rnd = random.Random(seed)
    total_bad = 0
    for k in (1, 2, 3, 4):
        L, D = build_matrices(k)
        cases = [(rnd.getrandbits(32), [rnd.getrandbits(8) for _ in range(4)]) for _ in range(n)]
        for c in (0x00000000, 0xFFFFFFFF, 0xEDB88320, 0x00000001, 0x80000000, 0x12345678,
                  0xDEADBEEF, 0xCBF43926):
            for d in ([0, 0, 0, 0], [0xFF, 0xFF, 0xFF, 0xFF], [0x00, 0xFF, 0x00, 0xFF],
                      [0x55, 0xAA, 0x55, 0xAA], [0x01, 0x02, 0x04, 0x08]):
                cases.append((c, d))
        bad = 0
        for crc, d in cases:
            exp = crc32_k_ref(crc, d, k)
            got = 0
            data32 = d[0] | (d[1] << 8) | (d[2] << 16) | (d[3] << 24)
            for j in range(32):
                bit = 0
                m = L[j]
                while m:
                    lsb = m & -m
                    bit ^= (crc >> (lsb.bit_length() - 1)) & 1
                    m ^= lsb
                m = D[j]
                while m:
                    lsb = m & -m
                    bit ^= (data32 >> (lsb.bit_length() - 1)) & 1
                    m ^= lsb
                if bit:
                    got |= (1 << j)
            if got != exp:
                bad += 1
                if bad <= 2:
                    print("MISMATCH k=%d crc=%08x d=%s got=%08x exp=%08x" % (k, crc, d, got, exp))
        print("verify k=%d: %d cases, %d mismatches" % (k, len(cases), bad))
        total_bad += bad
    # 标准检查值：crc32("123456789") = 0xCBF43926（合同/check_contract.py 同）
    std = ~crc32_k_ref(0xFFFFFFFF, list(b"123456789"), 9) & 0xFFFFFFFF
    print("crc32('123456789') = 0x%08X (expect 0xCBF43926)" % std)
    return total_bad == 0 and std == 0xCBF43926


def terms(mask, names):
    out = []
    for i, nm in enumerate(names):
        if (mask >> i) & 1:
            out.append(nm)
    return out


def emit():
    lines = []
    lines.append("// ---- 由 tools/pcie_integration/gen_crc32_flat.py 生成（请勿手改）----")
    lines.append("// R10F payload/raw CRC-32（IEEE reflected poly 0xEDB88320，init 全 1；")
    lines.append("// 末值由调用方取反）按**实际字节数**推进的扁平 XOR 形式：")
    lines.append("//   crc32_upd1(c,b0) / upd2(c,b0,b1) / upd3(...b2) / upd4(...b3)")
    lines.append("// 与合同 frame_contract.py 的逐位定义逐位等价（脚本 4 个变体各 2 万+ 自检）。")
    crc_names = ["c[%d]" % i for i in range(32)]
    dat_names = ["d[%d]" % i for i in range(32)]
    for k in (1, 2, 3, 4):
        L, D = build_matrices(k)
        args = ", ".join(["b%d" % i for i in range(k)])
        lines.append("function [31:0] crc32_upd%d;" % k)
        lines.append("    input [31:0] c;")
        lines.append("    input [7:0]  %s;" % args)
        lines.append("    reg   [%d:0] d;" % (8 * k - 1))
        lines.append("    begin")
        concat = ", ".join(["b%d" % i for i in range(k - 1, -1, -1)])
        lines.append("        d = {%s};" % concat)
        for j in range(32):
            t = terms(L[j], crc_names) + terms(D[j], dat_names)
            expr = " ^ ".join(t) if t else "1'b0"
            lines.append("        crc32_upd%d[%d] = %s;" % (k, j, expr))
        lines.append("    end")
        lines.append("endfunction")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None)
    ap.add_argument("--selfcheck-only", action="store_true")
    a = ap.parse_args()
    ok = verify()
    txt = emit()
    if a.out:
        with open(a.out, "w", encoding="utf-8", newline="\n") as f:
            f.write(txt + "\n")
        print("wrote", a.out)
    if not a.selfcheck_only:
        print(txt)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
