#!/usr/bin/env python3
"""PCIe C2H 首次联调用的"固定块"测试数据：生成 + 校验（纯 Python）。

用途：F3 的第一步是"先搬固定/随机数据，再搬图像"。本工具给双方一份**同一份**
可复现的测试块与校验器：
  * FPGA 侧：把 block 当成要发的内容（长度/序号/CRC 都已定义）；
  * RK 侧：收到后用它校验长度、序号、CRC 与内容。

块布局（32B 头 + 载荷，小端）：
  0x00 magic 4B "PCIT"
  0x04 version_major u16 / 0x06 version_minor u16
  0x08 seq u32
  0x0C pattern_id u32      （0=counter 1=PRBS31 2=seeded 3=全0 4=全1）
  0x10 payload_bytes u32
  0x14 crc32 u32           （覆盖 header[0:0x14] 且本字段置 0 后，再拼 payload）
  0x18 reserved 8B
CRC32：与本项目其它合同一致（IEEE 反射 0xEDB88320，init/final xor 0xFFFFFFFF）。

边界：软件参考；不生成 RTL、不生成位流、不访问硬件。
"""

from __future__ import annotations

import argparse
import json
import random
import struct
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent / "frame"))
sys.path.insert(0, str(_HERE.parent))
import frame_contract as FC   # noqa: E402
import meta                   # noqa: E402

MAGIC = b"PCIT"
VERSION = (1, 0)
HEADER_BYTES = 32
CRC_OFF = 0x14

PATTERNS = {"counter": 0, "prbs31": 1, "seeded": 2, "zero": 3, "ones": 4}


def make_payload(pattern: str, n: int, seed: int = 20261015) -> bytes:
    if pattern == "counter":
        return bytes(i & 0xFF for i in range(n))
    if pattern == "prbs31":
        out = bytearray()
        lfsr = 0x7FFFFFFF
        for _ in range(n):
            bit = ((lfsr >> 30) ^ (lfsr >> 27)) & 1
            lfsr = ((lfsr << 1) | bit) & 0xFFFFFFFF
            out.append(lfsr & 0xFF)
        return bytes(out)
    if pattern == "seeded":
        rng = random.Random(seed)
        return bytes(rng.randrange(256) for _ in range(n))
    if pattern == "zero":
        return b"\x00" * n
    if pattern == "ones":
        return b"\xff" * n
    raise ValueError("unknown pattern %r" % pattern)


def build_block(seq: int, pattern: str, nbytes: int) -> bytes:
    payload = make_payload(pattern, nbytes)
    hdr = bytearray(HEADER_BYTES)
    struct.pack_into("4sHHIII", hdr, 0, MAGIC, VERSION[0], VERSION[1], seq,
                     PATTERNS[pattern], nbytes)
    struct.pack_into("<I", hdr, CRC_OFF, 0)
    crc = FC.crc32_ieee(bytes(hdr[:CRC_OFF]) + payload)
    struct.pack_into("<I", hdr, CRC_OFF, crc)
    return bytes(hdr) + payload


def check_block(blob: bytes) -> dict:
    res = {"ok": False, "errors": []}
    if len(blob) < HEADER_BYTES:
        res["errors"].append("shorter than header")
        return res
    magic, vmaj, vmin, seq, pid, nbytes = struct.unpack_from("4sHHIII", blob, 0)
    res.update({"magic": magic.decode(errors="replace"), "seq": seq,
                "pattern_id": pid, "payload_bytes": nbytes})
    if magic != MAGIC:
        res["errors"].append("bad magic")
    if (vmaj, vmin) != VERSION:
        res["errors"].append("bad version")
    if nbytes > len(blob) - HEADER_BYTES:
        res["errors"].append("payload truncated")
        return res
    payload = blob[HEADER_BYTES:HEADER_BYTES + nbytes]
    name = next((k for k, v in PATTERNS.items() if v == pid), None)
    if name is None:
        res["errors"].append("unknown pattern_id %d" % pid)
        return res
    if payload != make_payload(name, nbytes):
        res["errors"].append("payload content mismatch")
    stored = struct.unpack_from("<I", blob, CRC_OFF)[0]
    hdr = bytearray(blob[:HEADER_BYTES])
    struct.pack_into("<I", hdr, CRC_OFF, 0)
    if FC.crc32_ieee(bytes(hdr[:CRC_OFF]) + payload) != stored:
        res["errors"].append("crc mismatch")
    res["ok"] = not res["errors"]
    return res


def selftest(verbose=True):
    res = []
    for pat in PATTERNS:
        b = build_block(7, pat, 512)
        r = check_block(b)
        res.append(("roundtrip_%s" % pat, r["ok"]))
    b = build_block(3, "counter", 300)
    # 负对照：改一字节 / 改序号 / 截断
    bad = bytearray(b); bad[HEADER_BYTES + 5] ^= 0x01
    res.append(("detect_payload_flip", not check_block(bytes(bad))["ok"]))
    bad = bytearray(b); struct.pack_into("<I", bad, 0x08, 999)
    res.append(("detect_seq_change", not check_block(bytes(bad))["ok"]))
    res.append(("detect_truncation", not check_block(b[:HEADER_BYTES + 10])["ok"]))
    bad = bytearray(b); struct.pack_into("<I", bad, 0x10, 301)
    res.append(("detect_length_change", not check_block(bytes(bad))["ok"]))
    if verbose:
        for r in res:
            print("PCIE_TTD_SELFTEST", r)
    return res


def main():
    ap = argparse.ArgumentParser(description="PCIe C2H 固定块测试数据")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--emit", metavar="DIR")
    ap.add_argument("--check", metavar="FILE")
    ap.add_argument("--seq", type=int, default=1)
    ap.add_argument("--bytes", type=int, default=1024)
    ap.add_argument("--pattern", default="counter", choices=list(PATTERNS))
    a = ap.parse_args()

    if a.selftest:
        res = selftest()
        print("PCIE_TTD", "PASS" if all(x[1] for x in res) else "FAIL")
        return

    if a.check:
        blob = Path(a.check).read_bytes()
        r = check_block(blob)
        print("PCIE_TTD_CHECK", json.dumps(r, ensure_ascii=False))
        print("PCIE_TTD_CHECK", "PASS" if r["ok"] else "FAIL")
        if not r["ok"]:
            raise SystemExit(1)
        return

    if a.emit:
        out = Path(a.emit)
        out.mkdir(parents=True, exist_ok=True)
        blob = build_block(a.seq, a.pattern, a.bytes)
        (out / "block.bin").write_bytes(blob)
        info = {"evidence_meta": meta.evidence_meta(__file__),
                "seq": a.seq, "pattern": a.pattern, "payload_bytes": a.bytes,
                "block_bytes": len(blob),
                "crc32": "0x%08X" % struct.unpack_from("<I", blob, CRC_OFF)[0],
                "check": check_block(blob)}
        (out / "expected.json").write_text(json.dumps(info, indent=2, ensure_ascii=False),
                                          encoding="utf-8")
        print("PCIE_TTD_DIR", out, "block=%d payload=%d" % (len(blob), a.bytes))
        print("PCIE_TTD_EMIT", "PASS" if info["check"]["ok"] else "FAIL")
        return
    ap.print_help()


if __name__ == "__main__":
    main()
