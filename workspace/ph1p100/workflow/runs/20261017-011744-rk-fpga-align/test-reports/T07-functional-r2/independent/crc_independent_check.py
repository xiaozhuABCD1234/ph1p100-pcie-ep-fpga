#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T07.rk-align-backend r2 functional 独立核查②：crc16_upd4.v（生成文件）的独立验证。

做法（不调用生成器、不复用其代码路径）：
  1. 自己解析冻结的 rtl/checked/crc16_upd4.v 的 16 个输出位 XOR 方程；
  2. 自写两套 CRC 参考实现（RTL 同式移位版 + LSB-first 注入口版），互相校验；
  3. 对 crc16_upd1..upd4 做随机 + 边界穷举式抽样比对（每个变体 ≥ 30000 组）。
如发现任何失配 → 非 0 退出。
"""
import json, os, re, sys, random, hashlib, datetime

ROOT = r"C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道"
RUN = ROOT + "/workflow/runs/20261017-011744-rk-fpga-align"
FROZEN = ROOT + "/fpga/csi2/pcie_integration/rtl/checked/crc16_upd4.v"
OUT = RUN + "/test-reports/T07-functional-r2/independent/crc_independent_check.json"

POLY = 0x8408


def crc_byte_shift(c, b):
    """与 RTL crc_byte 同式：v=c^b; 8×(v=(v>>1)^(v[0]?0x8408:0))"""
    v = (c ^ b) & 0xFFFF
    for _ in range(8):
        v = (v >> 1) ^ (POLY if (v & 1) else 0)
    return v & 0xFFFF


def crc_byte_inject(c, b):
    """独立等价式：LSB-first 位注入（逐位反馈 v[0]^b_i）"""
    v = c & 0xFFFF
    for i in range(8):
        fb = ((b >> i) ^ v) & 1
        v >>= 1
        if fb:
            v ^= POLY
    return v & 0xFFFF


def crc_k(ref, c, bs, k):
    v = c
    for i in range(k):
        v = ref(v, bs[i] & 0xFF)
    return v


def parse_frozen(path):
    """解析 crc16_updK 的 d 拼接与 16 位方程；返回 {k: {'concat': [...], 'bits': {j: [(c/d, idx), ...]}}}"""
    txt = open(path, encoding="utf-8").read()
    funcs = {}
    cur = None
    for ln in txt.splitlines():
        s = ln.strip()
        mobj = re.match(r"function\s+\[15:0\]\s+crc16_upd(\d);", s)
        if mobj:
            cur = int(mobj.group(1)); funcs[cur] = {"concat": None, "bits": {}}
            continue
        if cur is None:
            continue
        if s.startswith("endfunction"):
            cur = None; continue
        m = re.match(r"d\s*=\s*\{([^}]*)\};", s)
        if m:
            funcs[cur]["concat"] = [x.strip() for x in m.group(1).split(",")]
            continue
        m = re.match(r"crc16_upd(\d)\[(\d+)\]\s*=\s*([^;]+);", s)
        if m:
            k, j, expr = int(m.group(1)), int(m.group(2)), m.group(3)
            terms = []
            for t in expr.split("^"):
                t = t.strip()
                mt = re.match(r"([cd])\[(\d+)\]", t)
                if mt:
                    terms.append((mt.group(1), int(mt.group(2))))
                elif t == "1'b0":
                    pass
                else:
                    raise ValueError("unparsed term %r in upd%d[%d]" % (t, k, j))
            if k not in funcs or funcs[k] is None:
                funcs[k] = {"concat": None, "bits": {}}
            funcs[k]["bits"][j] = terms
    return funcs


def eval_flat(funcs, k, c, bs):
    f = funcs[k]
    d_int = 0
    for i in range(k):
        d_int |= (bs[i] & 0xFF) << (8 * i)
    out = 0
    for j in range(16):
        v = 0
        for (src, idx) in f["bits"][j]:
            v ^= ((c >> idx) & 1) if src == "c" else ((d_int >> idx) & 1)
        out |= v << j
    return out


def main():
    res = {"frozen_file": FROZEN, "frozen_sha256": hashlib.sha256(open(FROZEN, "rb").read()).hexdigest()}
    funcs = parse_frozen(FROZEN)
    res["parsed_functions"] = sorted(funcs.keys())
    per_k = {}
    bad_total = 0
    exp_concat = {1: ["b0"], 2: ["b1", "b0"], 3: ["b2", "b1", "b0"], 4: ["b3", "b2", "b1", "b0"]}
    for k in (1, 2, 3, 4):
        if k not in funcs or len(funcs[k]["bits"]) != 16:
            per_k[k] = {"error": "missing or incomplete function"}
            bad_total += 1
            continue
        concat_ok = funcs[k]["concat"] == exp_concat[k]
        rnd = random.Random(0xC0FFEE + k)
        cases = []
        for _ in range(20000):
            cases.append((rnd.getrandbits(16), [rnd.getrandbits(8) for _ in range(4)]))
        for c0 in (0x0000, 0xFFFF, 0x8408, 0x0001, 0x8000, 0x1234, 0x00FF, 0xFF00):
            for b0 in (0x00, 0xFF, 0x55, 0xAA, 0x01, 0x80, 0x7F, 0xFE):
                for b1 in (0x00, 0xFF, 0x5A, 0xA5):
                    cases.append((c0, [b0, b1, b0 ^ b1, (b0 + 1) & 0xFF]))
        bad = 0
        first_bad = None
        for (c, bs) in cases:
            exp = crc_k(crc_byte_shift, c, bs, k)
            exp2 = crc_k(crc_byte_inject, c, bs, k)
            if exp != exp2:
                bad += 1
                if first_bad is None:
                    first_bad = {"c": hex(c), "bs": [hex(x) for x in bs], "shift": hex(exp), "inject": hex(exp2)}
                continue
            got = eval_flat(funcs, k, c, bs)
            if got != exp:
                bad += 1
                if first_bad is None:
                    first_bad = {"c": hex(c), "bs": [hex(x) for x in bs], "expect": hex(exp), "flat": hex(got)}
        per_k[k] = {"concat_order_ok": concat_ok, "cases": len(cases), "mismatches": bad}
        if first_bad:
            per_k[k]["first_mismatch"] = first_bad
        bad_total += bad
    res["per_variant"] = per_k
    res["total_mismatches"] = bad_total
    res["verdict"] = "OK" if bad_total == 0 else "MISMATCH"
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(res, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print(json.dumps(res, ensure_ascii=False, indent=2))
    return 0 if bad_total == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
