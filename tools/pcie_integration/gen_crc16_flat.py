#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T07 round2：把「4 字节/拍」的 CRC-16 递推写成**合成友好并行形式**（扁平 XOR 方程）。

背景（见 backend/g2/README.md §3.4）：相机字节域 187.5 MHz（5.332 ns），checked 包层每拍必须
按原样吃满 4 字节（CSI 不可反压），而 CRC 是逐拍递推：`crc <= crc_byte×4(crc, 本拍 4 字节)`。
RTL 现在写成「8 次移位 + 条件异或」串行展开，综合器未必把这条**线性**函数展开成 XOR 树，
实测最差路径 7.7 ns（10 级逻辑、61% 布线）。

本脚本做两件事（都可复跑、可复核）：
  1) 用**与 RTL 完全相同的** crc_byte 定义（reflected poly 0x8408、init 0xFFFF、无 final XOR）
     在 Python 里重建递推；对 4 字节/拍做**线性代数**：把 crc'(16bit) 表示成
     [crc(16) | 数据(32)] 的 GF(2) 线性映射（L 16×16、D 32×16）。
  2) 输出 Verilog 函数 `crc16_upd4(crc, b0, b1, b2, b3)`——16 个输出位各自是一个扁平 XOR 树
     （深度 ~log2(项数) ≈ 3–4 级 LUT6），并**自检**：随机 20000 组 + 边界组（全 0/全 F/0x00 混排等）
     与参考递推逐位一致，否则非 0 退出。

用法：
  python tools/pcie_integration/gen_crc16_flat.py            # 自检 + 打印 Verilog
  python tools/pcie_integration/gen_crc16_flat.py --out <file>
"""
import argparse
import random
import sys

POLY = 0x8408  # reflected X^16+X^15+X^2+1


def crc_byte_ref(c, b):
    """与 RTL `crc_byte` 逐位等价：v = c ^ b; 8 × (v = (v>>1) ^ (v[0]?0x8408:0))"""
    v = (c ^ b) & 0xFFFF
    for _ in range(8):
        v = (v >> 1) ^ (POLY if (v & 1) else 0)
    return v & 0xFFFF


def crc4_ref(crc, b0, b1, b2, b3):
    v = crc
    for b in (b0, b1, b2, b3):
        v = crc_byte_ref(v, b)
    return v & 0xFFFF


def build_matrices(k=4):
    """线性映射：crc'(16) = L·crc(16) XOR D·data(32)（GF(2)），按**k 个实际字节**推进"""
    L = [0] * 16   # L[j] = 16bit 掩码：输出位 j 对所有 crc 输入位的依赖
    D = [0] * 32   # D[j] = 16bit 掩码：输出位 j 对所有数据输入位的依赖
    def crc_k(crc, data):
        v = crc
        for i in range(k):
            v = crc_byte_ref(v, data[i])
        return v
    for i in range(16):
        base = crc_k(1 << i, [0, 0, 0, 0])
        for j in range(16):
            if (base >> j) & 1:
                L[j] |= (1 << i)
    for i in range(32):
        byte_idx = i // 8
        bit = i % 8
        if byte_idx >= k:
            continue          # 超过本变体处理的字节数 → 无贡献
        data = [0, 0, 0, 0]
        data[byte_idx] = 1 << bit
        base = crc_k(0, data)
        for j in range(16):
            if (base >> j) & 1:
                D[j] |= (1 << i)
    return L, D


def verify(n=20000, seed=0x5EED07):
    """对 4 种「实际字节数」变体各做随机+边界自检（与参考递推逐位一致）"""
    rnd = random.Random(seed)
    total_bad = 0
    for k in (1, 2, 3, 4):
        L, D = build_matrices(k)
        cases = [(rnd.getrandbits(16), [rnd.getrandbits(8) for _ in range(4)]) for _ in range(n)]
        for c in (0x0000, 0xFFFF, 0x8408, 0x0001, 0x8000, 0x1234):
            for d in ([0, 0, 0, 0], [0xFF, 0xFF, 0xFF, 0xFF], [0x00, 0xFF, 0x00, 0xFF],
                      [0x55, 0xAA, 0x55, 0xAA], [0x01, 0x02, 0x04, 0x08]):
                cases.append((c, d))
        bad = 0
        for crc, d in cases:
            exp = crc
            for i in range(k):
                exp = crc_byte_ref(exp, d[i])
            got = 0
            data32 = d[0] | (d[1] << 8) | (d[2] << 16) | (d[3] << 24)
            for j in range(16):
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
                    print("MISMATCH k=%d crc=%04x d=%s got=%04x exp=%04x" % (k, crc, d, got, exp))
        print("verify k=%d: %d cases, %d mismatches" % (k, len(cases), bad))
        total_bad += bad
    return total_bad == 0


def terms(mask, names):
    """把 16/32 位掩码转成 XOR 项列表（低位在前）"""
    out = []
    for i, nm in enumerate(names):
        if (mask >> i) & 1:
            out.append(nm)
    return out


def emit():
    """输出 4 个变体函数：crc16_upd1..upd4（按**实际字节数**推进，与参考递推逐位等价）"""
    lines = []
    lines.append("// ---- 由 tools/pcie_integration/gen_crc16_flat.py 生成（请勿手改）----")
    lines.append("// 按实际字节数推进的 CRC-16 递推（poly 0x8408 reflected、无 final XOR）：")
    lines.append("//   crc16_upd1(c,b0) / upd2(c,b0,b1) / upd3(...b2) / upd4(...b3)")
    lines.append("// 与原 RTL 的 crc_byte×k 逐位等价（脚本已对 4 个变体各做 2 万+ 随机/边界自检）；")
    lines.append("// 每个输出位写成扁平 XOR 树（综合友好）。调用方按本拍实际有效字节数选择。")
    crc_names = ["c[%d]" % i for i in range(16)]
    dat_names = ["d[%d]" % i for i in range(32)]
    for k in (1, 2, 3, 4):
        L, D = build_matrices(k)
        args = ", ".join(["b%d" % i for i in range(k)])
        lines.append("function [15:0] crc16_upd%d;" % k)
        lines.append("    input [15:0] c;")
        lines.append("    input [7:0]  %s;" % args)
        lines.append("    reg   [%d:0] d;" % (8 * k - 1))
        lines.append("    begin")
        concat = ", ".join(["b%d" % i for i in range(k - 1, -1, -1)])
        lines.append("        d = {%s};" % concat)
        for j in range(16):
            t = terms(L[j], crc_names) + terms(D[j], dat_names)
            expr = " ^ ".join(t) if t else "1'b0"
            lines.append("        crc16_upd%d[%d] = %s;" % (k, j, expr))
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
        with open(a.out, "w", encoding="utf-8", newline="") as f:
            f.write(txt + "\n")
        print("wrote", a.out)
    if not a.selfcheck_only:
        print(txt)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
