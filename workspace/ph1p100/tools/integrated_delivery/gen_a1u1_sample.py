#!/usr/bin/env python3
"""Generate a reproducible A1U1 sample file for RK offline validation.

Produces a small A1U1 frame: 44-byte header + zlib payload + zero transport padding.
The payload is a deterministic zlib stream over a known byte pattern so RK can
verify header CRC, stream CRC, length and tail padding without real FPGA/RK link.
"""
from __future__ import annotations

import struct
import zlib
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from a1u1_decode import crc32, HEADER_LEN, MAGIC

W, H = 64, 48  # small reproducible geometry
RAW_LEN = W * H * 10 // 8


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "a1u1_sample.a1u1"
    aligned = int(sys.argv[2]) if len(sys.argv) > 2 else 4096
    # deterministic raw bytes
    raw = bytes((i * 37 + 11) & 0xFF for i in range(RAW_LEN))
    # transform = identity (bypass) for the sample
    xform = raw
    # compress
    compressor = zlib.compressobj(level=6, wbits=15)
    payload = compressor.compress(xform) + compressor.flush()
    stream_len = len(payload)
    raw_crc = crc32(raw)
    xform_crc = crc32(xform)
    stream_crc = crc32(payload)
    header = bytearray(HEADER_LEN)
    struct.pack_into("<I", header, 0, MAGIC)
    header[4] = 0x01
    header[5] = 0x00  # prep=0,pred=0 (bypass)
    struct.pack_into("<H", header, 6, HEADER_LEN)
    struct.pack_into("<I", header, 8, 1)  # frame_id
    struct.pack_into("<HH", header, 12, W, H)
    struct.pack_into("<III", header, 16, RAW_LEN, len(xform), stream_len)
    struct.pack_into("<III", header, 28, raw_crc, xform_crc, stream_crc)
    header_crc = crc32(bytes(header[0:40]))
    struct.pack_into("<I", header, 40, header_crc)
    body = bytes(header) + payload
    if len(body) < aligned:
        body = body + b"\x00" * (aligned - len(body))
    with open(out, "wb") as f:
        f.write(body)
    print(f"generated {out}: stream_len={stream_len} aligned={aligned} total={len(body)}")


if __name__ == "__main__":
    main()
