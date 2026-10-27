#!/usr/bin/env python3
"""INT.P4 independent verification of the integrated-delivery A1U1 sample.

The sample is produced by the RTL simulation of integrated_delivery_top
(a1_frame_top -> slot store -> PCIe egress adapter), not by a Python generator.
This check is independent of the RTL: it re-parses the 44-byte A1U1 header,
re-computes the header CRC, re-computes the raw-byte CRC over the packed RAW10
bytes that the RTL actually handed to the A+ entrance (integrated_sample.raw),
re-computes the stream CRC, inflates the payload with zlib and compares it
byte-for-byte with the raw input (the sample frame uses prep=0/pred=0, so the
transform is the identity).

Usage: verify_integrated_sample.py <sample.a1u1> <sample.raw> [<sample.json>]
Exit 0 = PASS, 1 = FAIL, 2 = usage.
"""
from __future__ import annotations

import json
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from a1u1_decode import HEADER_LEN, crc32, parse


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: verify_integrated_sample.py <sample.a1u1> <sample.raw> [sample.json]")
        return 2
    sample_path, raw_path = sys.argv[1], sys.argv[2]
    json_path = sys.argv[3] if len(sys.argv) > 3 else None

    with open(sample_path, "rb") as f:
        data = f.read()
    with open(raw_path, "rb") as f:
        raw = f.read()

    failures = []

    def check(name: str, cond: bool, detail: str = "") -> None:
        print(("  ok   : " if cond else "  FAIL : ") + name + ((" " + detail) if detail else ""))
        if not cond:
            failures.append(name)

    info = parse(data)  # raises on header/stream CRC or zlib errors
    payload = data[HEADER_LEN:HEADER_LEN + info["stream_len"]]

    check("header CRC recomputed", True)
    check("stream CRC recomputed", True)
    check("zlib inflate", True)
    check("raw bytes == W*H*10/8", len(raw) == info["raw_len"],
          f"raw={len(raw)} header_raw_len={info['raw_len']}")
    check("raw CRC (python) == RTL raw_crc", crc32(raw) == info["raw_crc"],
          f"py=0x{crc32(raw):08x} rtl=0x{info['raw_crc']:08x}")
    check("stream_len == payload bytes", len(payload) == info["stream_len"])
    check("xform_len == raw_len (prep=0)", info["xform_len"] == info["raw_len"])
    check("prep flag == 0", info["prep"] is False)

    inflated = zlib.decompress(payload)
    check("inflated transform bytes == raw packed bytes", inflated == raw,
          f"inflated={len(inflated)} raw={len(raw)}")
    check("inflated length == xform_len", len(inflated) == info["xform_len"])

    if json_path:
        with open(json_path, "r", encoding="utf-8") as f:
            meta = json.load(f)
        check("json stream_len == header stream_len",
              meta.get("stream_len") == info["stream_len"])
        check("json raw_crc == header raw_crc", meta.get("raw_crc") == info["raw_crc"])
        check("json payload_bytes == header stream_len",
              meta.get("payload_bytes") == info["stream_len"])
        check("json frame_bytes 4096 aligned", meta.get("frame_bytes") == 4096)
        check("json src_sel == 0 (DDR compressed source)", meta.get("src_sel") == 0)
        check("json camera/slot captured", meta.get("camera_id") in (0, 1))
        check("json notes RTL simulation (no real PCIe claim)",
              "RTL simulation" in str(meta.get("source", "")))

    print(f"  info : raw_crc=0x{info['raw_crc']:08x} stream_crc=0x{info['stream_crc']:08x} "
          f"stream_len={info['stream_len']} raw_len={info['raw_len']}")
    if failures:
        print("VERIFY_INTEGRATED_SAMPLE FAIL", failures)
        return 1
    print("VERIFY_INTEGRATED_SAMPLE PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
