#!/usr/bin/env python3
"""PCIe C2H 端到端**软件**通路验证：固定块 → TLP 分包 → 主机重组 → 校验。

把 F3 的数据面在纯软件里走通一遍，回答"分包再重组会不会丢/错字节"：
  1. `first_test_data` 生成固定块（带长度/序号/CRC）；
  2. `tlp_pack_ref` 按 MPS 与 4KiB 规则切成 Memory Write TLP；
  3. "主机侧"按地址把 TLP 数据拼回去；
  4. 用块校验器验证 → 内容/CRC/长度必须完全一致。

负对照（必须被拒）：丢一个 TLP、乱序、把某个 TLP 截短、把某个字节翻转。
不访问硬件、不生成 RTL/位流。
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(REPO / "parallel"))
import first_test_data as T   # noqa: E402
import tlp_pack_ref as P      # noqa: E402
import meta                   # noqa: E402

OUT = REPO / "parallel" / "evidence" / "pcie_e2e_soft_20261015"


def host_reassemble(tlps, base: int) -> bytes:
    """主机侧按地址拼回连续缓冲。"""
    if not tlps:
        return b""
    lo = min(t.addr for t in tlps)
    hi = max(t.addr + t.length for t in tlps)
    buf = bytearray(hi - lo)
    for t in tlps:
        buf[t.addr - lo:t.addr - lo + t.length] = t.data
    slice_ = buf[base - lo:base - lo + (hi - base)]
    return bytes(slice_)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    cases = []

    for seq, pattern, nbytes, base, mps in (
            (1, "counter", 1024, 0x1000, 256),
            (2, "prbs31", 6000, 0x1F00, 256),      # 跨 4KiB 边界
            (3, "seeded", 300, 0x1002, 256),       # 非 DW 对齐起点
            (4, "ones", 4096, 0x0000, 512),        # 恰好一页
    ):
        block = T.build_block(seq, pattern, nbytes)
        tlps = P.split_mem_write(block, base, mps)
        errs = P.check_tlps(tlps, block, base, mps)
        back = host_reassemble(tlps, base)
        chk = T.check_block(back)
        ok = (not errs) and chk["ok"] and back == block
        cases.append(("e2e_seq%d_%s_%dB" % (seq, pattern, nbytes), ok,
                      "tlps=%d plan_errs=%d block_ok=%s" % (len(tlps), len(errs), chk["ok"])))

    # 负对照
    block = T.build_block(9, "counter", 1024)
    base, mps = 0x1000, 256
    tlps = P.split_mem_write(block, base, mps)

    def rej(name, mutated):
        back = host_reassemble(mutated, base)
        ok = (back != block) and (not T.check_block(back)["ok"])
        cases.append((name, ok, "reassembled_ok=%s" % T.check_block(back)["ok"]))

    rej("nc_drop_one_tlp", tlps[:1] + tlps[2:])
    t0 = tlps[0]
    # 乱序对"按地址重组"无害——这是要**断言**的性质，不是负对照
    back_ro = host_reassemble([tlps[1], tlps[0]] + tlps[2:], base)
    cases.append(("p_reorder_is_harmless", back_ro == block and T.check_block(back_ro)["ok"],
                  "by-address reassembly is order independent"))
    # 真正的负对照：把某个 TLP 的地址挪走 → 重组出现空洞/错位
    rej("nc_shift_address",
        [P.Tlp(t0.addr + 64, t0.length, t0.first_be, t0.last_be, t0.data)] + tlps[1:])
    rej("nc_shorten_tlp", [P.Tlp(t0.addr, t0.length - 4, t0.first_be, t0.last_be,
                                 t0.data[:-4])] + tlps[1:])
    bad = bytearray(tlps[0].data); bad[7] ^= 0x01
    rej("nc_flip_byte", [P.Tlp(t0.addr, t0.length, t0.first_be, t0.last_be, bytes(bad))] + tlps[1:])

    ok = all(c[1] for c in cases)
    lines = ["%-28s %s  %s" % (n, "PASS" if o else "FAIL", d) for n, o, d in cases]
    (OUT / "result.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (OUT / "meta.json").write_text(
        __import__("json").dumps(meta.evidence_meta(__file__), indent=2), encoding="utf-8")
    for l in lines:
        print("PCIE_E2E", l)
    print("PCIE_E2E_DIR", OUT)
    print("PCIE_E2E", "PASS" if ok else "FAIL", "cases=%d" % len(cases))
    if not ok:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
