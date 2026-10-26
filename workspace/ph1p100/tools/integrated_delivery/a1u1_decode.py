#!/usr/bin/env python3
"""INT.P2 A1U1 (compressed frame) decode tool.

A1U1 wire format (little-endian, 44-byte header):
  0  u32 magic      = 0x31553141  (file bytes 'A','1','U','1')
  4  u8  version    = 0x01
  5  u8  flags      = {6'b0, pred, prep}
  6  u16 header_len = 44
  8  u32 frame_id
 12  u16 width
 14  u16 height
 16  u32 raw_len     (bytes, W*H*10/8)
 20  u32 xform_len   (bytes fed to A+ core)
 24  u32 stream_len  (zlib bytes)
 28  u32 raw_crc     (CRC-32 of raw bytes)
 32  u32 xform_crc   (CRC-32 of transform bytes)
 36  u32 stream_crc  (CRC-32 of zlib stream)
 40  u32 header_crc   (CRC-32 of bytes 0..39)
 then stream_len payload bytes (zlib stream).

This tool validates the header, header CRC, stream CRC, exact lengths and
transport tail padding (zeros).  It does NOT claim real PCIe transport.
"""
from __future__ import annotations

import struct
import sys
import zlib

MAGIC = 0x31553141
HEADER_LEN = 44


def crc32(data: bytes) -> int:
    return zlib.crc32(data) & 0xFFFFFFFF


def parse(data: bytes):
    if len(data) < HEADER_LEN:
        raise ValueError(f"file too short: {len(data)} < {HEADER_LEN}")
    magic, = struct.unpack_from("<I", data, 0)
    if magic != MAGIC:
        raise ValueError(f"bad magic: 0x{magic:08x}")
    version = data[4]
    flags = data[5]
    header_len, = struct.unpack_from("<H", data, 6)
    if header_len != HEADER_LEN:
        raise ValueError(f"bad header_len: {header_len}")
    frame_id, = struct.unpack_from("<I", data, 8)
    width, height = struct.unpack_from("<HH", data, 12)
    raw_len, xform_len, stream_len = struct.unpack_from("<III", data, 16)
    raw_crc, xform_crc, stream_crc = struct.unpack_from("<III", data, 28)
    header_crc, = struct.unpack_from("<I", data, 40)
    # header crc covers bytes 0..39
    calc_header_crc = crc32(data[0:40])
    if header_crc != calc_header_crc:
        raise ValueError(f"header_crc mismatch: file=0x{header_crc:08x} calc=0x{calc_header_crc:08x}")
    if len(data) < HEADER_LEN + stream_len:
        raise ValueError(f"truncated: need {HEADER_LEN+stream_len}, got {len(data)}")
    payload = data[HEADER_LEN:HEADER_LEN + stream_len]
    tail = data[HEADER_LEN + stream_len:]
    # stream crc covers payload
    calc_stream_crc = crc32(payload)
    if stream_crc != calc_stream_crc:
        raise ValueError(f"stream_crc mismatch: file=0x{stream_crc:08x} calc=0x{calc_stream_crc:08x}")
    # tail padding must be all zero (transport padding)
    if any(b != 0 for b in tail):
        raise ValueError("non-zero transport tail padding")
    # try decompress
    try:
        decompressed = zlib.decompress(payload)
    except Exception as e:
        raise ValueError(f"zlib decompress failed: {e}")
    return {
        "version": version,
        "flags": flags,
        "prep": bool(flags & 0x01),
        "pred": bool(flags & 0x02),
        "frame_id": frame_id,
        "width": width,
        "height": height,
        "raw_len": raw_len,
        "xform_len": xform_len,
        "stream_len": stream_len,
        "raw_crc": raw_crc,
        "xform_crc": xform_crc,
        "stream_crc": stream_crc,
        "header_crc": header_crc,
        "payload_bytes": len(payload),
        "tail_bytes": len(tail),
        "decompressed_bytes": len(decompressed),
        "raw_len_ok": raw_len == width * height * 10 // 8,
    }


def main():
    if len(sys.argv) < 2:
        print("usage: a1u1_decode.py <file.a1u1> [transport_aligned_bytes]")
        sys.exit(2)
    path = sys.argv[1]
    with open(path, "rb") as f:
        data = f.read()
    info = parse(data)
    print("A1U1_DECODE OK")
    for k, v in info.items():
        print(f"  {k}: {v}")
    if len(sys.argv) >= 3:
        aligned = int(sys.argv[2])
        if (HEADER_LEN + info["stream_len"]) > aligned:
            print("WARN: stream exceeds aligned transport size")
        else:
            pad = aligned - (HEADER_LEN + info["stream_len"])
            print(f"  transport_padding: {pad} bytes (aligned={aligned})")
    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("A1U1_DECODE FAIL:", e)
        sys.exit(1)
