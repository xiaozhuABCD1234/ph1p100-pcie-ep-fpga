#!/usr/bin/env python3
"""PCIe C2H 内存写 TLP 分包的独立参考模型（纯 Python，仅标准库）。

用途
----
给 FPGA→RK 的图像 DMA（F3）提供一份**与 RTL 无关的黄金**：给定一段字节载荷
与目标主机地址，算出应当发出的一串 Memory Write TLP 的
(地址, 长度, first_be, last_be, 数据切片)，供 FPGA 发送端与 RK 驱动侧对齐。

规则（按 PCIe 基规范的最小必要集，超出部分显式标注）
----------------------------------------------------
* 单个 Memory Write 的数据长度 ≤ MPS（Max Payload Size，DW 粒度）。
* 一个请求**不得跨越 4 KiB 边界**（基规范对 memory request 的要求）。
* 允许起始地址非 DW 对齐：用 first_be 屏蔽首 DW 中地址之前的字节；
  尾部不足一个 DW 时用 last_be 屏蔽。
* BE 定义：第 i 位 = 使能 DW 内偏移 i 的字节（i=0..3）。
* DW 数 = ceil((addr%4 + len)/4)。

**未覆盖（需 F3/官方文档确认，不要凭本模型推断）**：TLP 头字段/格式、
序列号/credit 流控、Max_Read_Request、完成包、MSI、switch 下的额外约束。

边界：这是软件参考，不是 RTL，也未与队友冻结；不能据此宣称 DMA 已实现。
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass

PCIE_4K = 4096


@dataclass
class Tlp:
    """`addr` 是**首个数据字节的字节地址**（可能非 DW 对齐）。

    Memory Write 头里的地址字段按 DW 对齐，等于 `tlp_header_addr()`；
    首 DW 内从 `addr % 4` 起的字节由 `first_be` 指示。
    """

    addr: int
    length: int
    first_be: int
    last_be: int
    data: bytes

    @property
    def dw(self) -> int:
        return (self.addr % 4 + self.length + 3) // 4

    def tlp_header_addr(self) -> int:
        """TLP 头 32bit 地址字段的值（DW 对齐）。"""
        return self.addr & ~0x3


def be_for(addr: int, length: int):
    """返回 (first_be, last_be)。BE 位 i = 使能 DW 内偏移 i 的字节。

    PCIe 规则（基规范 §2.2.5）：
      * 请求地址按 DW 对齐，first/last DW BE 指示该 DW 内哪些字节有效；
      * **Length = 1 DW 时，Last DW BE 必须为 0**，全部使能位放在 First DW BE；
      * Length > 1 时：First DW BE 为使能到该 DW 末尾的连续高位，
        Last DW BE 为从该 DW 起始的连续低位。
    """
    k = addr % 4
    m = (addr + length - 1) % 4
    dw = (k + length + 3) // 4
    if dw == 1:
        first = (((1 << length) - 1) << k) & 0xF
        last = 0
    else:
        first = (0xF & ~((1 << k) - 1)) & 0xF
        last = (1 << (m + 1)) - 1
    return first, last


def split_mem_write(payload: bytes, addr: int, mps: int = 256, boundary: int = PCIE_4K):
    """把 payload 切成满足 MPS 与 4KiB 不跨越约束的 Memory Write TLP 序列。"""
    if mps <= 0 or mps % 4:
        raise ValueError("MPS must be a positive multiple of 4")
    out = []
    pos = 0
    cur = addr
    total = len(payload)
    while pos < total:
        room = boundary - (cur % boundary)
        # MPS 是**每 TLP 的 DW 数**上限：非 DW 对齐的起始 DW 也要计入，
        # 因此首块可用字节数要减去 cur%4（后续块按 DW 对齐，等价于 mps）。
        n = min(mps - (cur % 4), room, total - pos)
        if n <= 0:
            raise AssertionError("no progress")
        data = payload[pos:pos + n]
        fb, lb = be_for(cur, n)
        out.append(Tlp(cur, n, fb, lb, data))
        pos += n
        cur += n
    return out


# --------------------------------------------------------------------------
# 检查器（用于正例与负例）
# --------------------------------------------------------------------------

def check_tlps(tlps, payload: bytes, addr: int, mps: int = 256, boundary: int = PCIE_4K):
    """**独立**校验：不调用 be_for，直接按 PCIe 规则重算，避免自我实现的自证。"""
    errs = []
    if not tlps and payload:
        errs.append("empty tlp list for non-empty payload")
    joined = b""
    cur = addr
    for i, t in enumerate(tlps):
        if t.length <= 0:
            errs.append("tlp%d length<=0" % i)
            continue
        k = t.addr % 4
        m = (t.addr + t.length - 1) % 4
        dw = (k + t.length + 3) // 4
        if dw * 4 > mps:
            errs.append("tlp%d dw=%d exceeds MPS/4=%d" % (i, dw, mps // 4))
        if (t.addr % boundary) + t.length > boundary:
            errs.append("tlp%d crosses 4KiB boundary (addr%%4k=%d len=%d)"
                        % (i, t.addr % boundary, t.length))
        if t.addr != cur:
            errs.append("tlp%d addr %d not contiguous (expected %d)" % (i, t.addr, cur))
        if t.dw != dw:
            errs.append("tlp%d dw mismatch got %d expect %d" % (i, t.dw, dw))
        if dw == 1:
            exp_first = (((1 << t.length) - 1) << k) & 0xF
            exp_last = 0
        else:
            exp_first = (0xF & ~((1 << k) - 1)) & 0xF
            exp_last = (1 << (m + 1)) - 1
        if (t.first_be, t.last_be) != (exp_first, exp_last):
            errs.append("tlp%d be mismatch got (%x,%x) expect (%x,%x)"
                        % (i, t.first_be, t.last_be, exp_first, exp_last))
        joined += t.data
        cur += t.length
    if joined != payload:
        errs.append("payload not preserved (%d vs %d bytes)" % (len(joined), len(payload)))
    if payload and cur != addr + len(payload):
        errs.append("end address mismatch")
    return errs


# --------------------------------------------------------------------------
# 故意的错误实现（负对照）：忽略 4KiB 边界
# --------------------------------------------------------------------------

def split_bad_ignores_4k(payload: bytes, addr: int, mps: int = 256):
    out = []
    pos = 0
    cur = addr
    while pos < len(payload):
        n = min(mps, len(payload) - pos)
        fb, lb = be_for(cur, n)
        out.append(Tlp(cur, n, fb, lb, payload[pos:pos + n]))
        pos += n
        cur += n
    return out


# --------------------------------------------------------------------------
# 自检
# --------------------------------------------------------------------------

def selftest(verbose=True):
    res = []
    data = bytes((i * 7 + 3) & 0xFF for i in range(1000))

    # 1) 基本切分与守恒
    t = split_mem_write(data, 0, mps=256)
    res.append(("basic_split", check_tlps(t, data, 0, 256) == []))
    res.append(("basic_split_count", len(t) == 4 and [x.length for x in t] == [256, 256, 256, 232]))

    # 2) 恰好一页（4KiB）
    d2 = bytes(range(256)) * 16          # 4096
    t2 = split_mem_write(d2, 0, mps=512)
    res.append(("exact_page", check_tlps(t2, d2, 0, 512) == [] and sum(x.length for x in t2) == 4096))

    # 3) 跨页：从页中开始，必须被 4KiB 截断
    t3 = split_mem_write(d2, 4000, mps=512)
    res.append(("cross_page_split", check_tlps(t3, d2, 4000, 512) == []))
    res.append(("cross_page_first_chunk", t3[0].length == 96))

    # 4) 非 DW 对齐起点 + 非 4 倍数尾部
    d4 = bytes([0xAA]) * 5
    t4 = split_mem_write(d4, 0x1002, mps=256)
    res.append(("misaligned_start", check_tlps(t4, d4, 0x1002, 256) == []))
    # addr=0x1002 起 5 字节：首 DW 用 2,3 字节 -> first_be=0b1100；
    # 末字节落在下一 DW 的偏移 2 -> last_be=0b0111
    res.append(("misaligned_be", t4[0].first_be == 0b1100 and t4[0].last_be == 0b0111))
    res.append(("misaligned_dw", t4[0].dw == 2))

    # 5) 负对照：忽略 4KiB 的实现在同一检查器下必须被拒绝
    bad = split_bad_ignores_4k(d2, 4000, mps=512)
    res.append(("negative_control_rejected", len(check_tlps(bad, d2, 4000, 512)) > 0))

    # 6) 空载荷
    res.append(("empty_payload", split_mem_write(b"", 0, 256) == []))

    # 7) 单 DW 请求：Last DW BE 必须为 0（PCIe 基规范 §2.2.5）
    cases = [
        (0x3567, b"\x5a" * 1, 0b1000, 0b0000, 1),
        (0x1001, b"\x5a" * 2, 0b0110, 0b0000, 1),
        (0x1000, b"\x5a" * 4, 0b1111, 0b0000, 1),
        (0x1001, b"\x5a" * 3, 0b1110, 0b0000, 1),
    ]
    ok_single = True
    for a, d, ef, el, edw in cases:
        t = split_mem_write(d, a, mps=256)[0]
        if (t.first_be, t.last_be, t.dw) != (ef, el, edw):
            ok_single = False
    res.append(("single_dw_be_rules", ok_single))
    res.append(("single_dw_checker_clean",
                all(check_tlps(split_mem_write(d, a, 256), d, a, 256) == [] for a, d, *_ in cases)))

    # 8) MPS 按 DW 口径：非对齐起始 300B 的首块必须是 64 DW（而不是 65）
    t8 = split_mem_write(b"\x11" * 300, 0x1002, mps=256)
    res.append(("mps_dw_limit", t8[0].dw == 64 and t8[0].length == 254
                and check_tlps(t8, b"\x11" * 300, 0x1002, 256) == []))

    # 9) 检查器能抓住"把单 DW 的 last_be 写错"的实现
    bad2 = split_mem_write(b"\x5a" * 1, 0x3567, mps=256)
    bad2[0].last_be = 0xF      # 故意写错
    res.append(("checker_catches_bad_single_dw_be",
                len(check_tlps(bad2, b"\x5a" * 1, 0x3567, 256)) > 0))

    if verbose:
        for r in res:
            print("TLP_SELFTEST", r)
    return res


def _main():
    ap = argparse.ArgumentParser(description="PCIe C2H Memory Write TLP 分包参考模型")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--emit", metavar="DIR", help="输出一份示例切分 JSON")
    ap.add_argument("--length", type=int, default=6000)
    ap.add_argument("--addr", type=lambda s: int(s, 0), default=0x1000)
    ap.add_argument("--mps", type=int, default=256)
    a = ap.parse_args()

    if a.selftest:
        res = selftest()
        print("TLP_PACK", "PASS" if all(r[1] for r in res) else "FAIL")
        return

    if a.emit:
        from pathlib import Path
        payload = bytes((i * 7 + 3) & 0xFF for i in range(a.length))
        tlps = split_mem_write(payload, a.addr, a.mps)
        errs = check_tlps(tlps, payload, a.addr, a.mps)
        sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
        import meta  # noqa: E402
        out = {
            "evidence_meta": meta.evidence_meta(__file__),
            "addr": a.addr, "length": a.length, "mps": a.mps,
            "tlp_count": len(tlps), "check_errors": errs,
            "tlps": [{"addr": "0x%X" % t.addr, "length": t.length, "dw": t.dw,
                      "first_be": "0x%X" % t.first_be, "last_be": "0x%X" % t.last_be}
                     for t in tlps],
        }
        p = Path(a.emit)
        p.mkdir(parents=True, exist_ok=True)
        (p / "tlp_plan.json").write_text(json.dumps(out, indent=2), encoding="utf-8")
        print("TLP_PLAN", p / "tlp_plan.json", "tlps=%d errors=%d" % (len(tlps), len(errs)))
        return

    ap.print_help()


if __name__ == "__main__":
    _main()
