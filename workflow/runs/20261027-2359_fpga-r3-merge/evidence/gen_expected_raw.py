#!/usr/bin/env python3
"""T11.BRD.P1 r2 — INDEPENDENT expected RAW10 frame model (contract only).

This script generates the expected 3840-byte packed RAW10 A+ input from the
frozen round-2 camera-stimulus contract and nothing else:

  ROI rows    r in [16, 63]          (ROI_Y = 16, H = 48)
  groups      g in [8, 23]           (ROI_X/4 = 8, W/4 = 16)
  value       v = (r*32 + g) & 0x3FF (TB camera formula)
  one beat    4 x 10-bit pixels, ALL FOUR = v
  byte offset ((r-16)*16 + (g-8)) * 5
  byte0..3    v[9:2]                  (P0..P3)
  byte4       {v[1:0], v[1:0], v[1:0], v[1:0]}
  total       48 * 16 * 5 = 3840 B
  first group r=16,g=8 -> v = 520   -> bytes 82 82 82 82 00

It does NOT read any DUT output, `pk_bytes.bin`, `slot_dump.bin`, the zlib
stream, the A1U1 frame or any developer intermediate.  The packed byte
definition is the frozen `raw10_sample_vector_to_packed.v` contract
(byte0 = P0[9:2] ... byte4 = {P3[1:0],P2[1:0],P1[1:0],P0[1:0]}).

The Python-zlib record printed here is a *reference encoder* record only: the
DUT's own RFC1950 encoder (`a1_deflate_core`) is not byte-compatible with
CPython zlib (proof: for the r1 frozen malformed stimulus both produce the same
Adler-32 0xc49f41ae, but CPython zlib needs 1391 B while the DUT emitted 3137 B).
So `stream_len` byte equality is NOT a valid criterion; the criteria are
"standard zlib decodes the slot to exactly this expected raw" plus the
independent Adler-32 below.

Outputs (in r2/evidence/): expected_raw.bin, expected_raw.json
"""
import hashlib
import json
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent

ROI_Y, H = 16, 48
ROI_G0, OG = 8, 16
PX_PER_GROUP = 4          # 4 x 10-bit pixels per 40-bit beat
PACKED_BYTES = 5          # 5 packed bytes per beat

EXPECTED_LEN = H * OG * PACKED_BYTES       # 3840


def value(r: int, g: int) -> int:
    return (r * 32 + g) & 0x3FF


def pack_group(p0: int, p1: int, p2: int, p3: int) -> bytes:
    """raw10_sample_vector_to_packed: byte0=P0[9:2] ... byte4=low bits."""
    return bytes([
        (p0 >> 2) & 0xFF,
        (p1 >> 2) & 0xFF,
        (p2 >> 2) & 0xFF,
        (p3 >> 2) & 0xFF,
        (((p3 & 3) << 6) | ((p2 & 3) << 4) | ((p1 & 3) << 2) | (p0 & 3)) & 0xFF,
    ])


def build() -> bytes:
    out = bytearray()
    for r in range(ROI_Y, ROI_Y + H):
        for g in range(ROI_G0, ROI_G0 + OG):
            v = value(r, g)
            out += pack_group(v, v, v, v)       # all four lanes carry v
    return bytes(out)


def main() -> int:
    raw = build()
    assert len(raw) == EXPECTED_LEN, (len(raw), EXPECTED_LEN)

    # geometric self-checks of the contract (not of the DUT)
    v_first = value(ROI_Y, ROI_G0)
    assert v_first == 520, v_first
    assert raw[0:5] == bytes([0x82, 0x82, 0x82, 0x82, 0x00]), raw[0:5].hex()
    # last group: r=63, g=23 -> v=1015 -> 0xFD.. byte4 = (3<<6)|(3<<4)|(3<<2)|3
    v_last = value(ROI_Y + H - 1, ROI_G0 + OG - 1)
    assert v_last == 1015, v_last
    assert raw[-5:] == bytes([0xFD, 0xFD, 0xFD, 0xFD, 0xFF]), raw[-5:].hex()

    adler = zlib.adler32(raw) & 0xFFFFFFFF
    crc = zlib.crc32(raw) & 0xFFFFFFFF

    # reference encoder record (informational; NOT a byte criterion)
    ref = zlib.compress(raw)                   # CPython 3.11.5 default level
    ref_sha = hashlib.sha256(ref).hexdigest().upper()

    (HERE / "expected_raw.bin").write_bytes(raw)
    meta = {
        "task_id": "T11.BRD.P1",
        "round": 2,
        "model": "independent RAW10 contract model (no DUT output read)",
        "contract": {
            "roi_rows": [ROI_Y, ROI_Y + H - 1],
            "groups": [ROI_G0, ROI_G0 + OG - 1],
            "value": "v = (r*32 + g) & 0x3FF, four identical pixels per beat",
            "byte_offset": "((r-16)*16 + (g-8))*5",
            "byte0_3": "v[9:2]",
            "byte4": "{v[1:0] x4}",
            "raw_len": EXPECTED_LEN,
            "first_group_v": v_first,
        },
        "expected_raw": {
            "file": "expected_raw.bin",
            "len": len(raw),
            "sha256": hashlib.sha256(raw).hexdigest().upper(),
            "adler32": f"{adler:08X}",
            "crc32": f"{crc:08X}",
            "first5": raw[0:5].hex(),
            "last5": raw[-5:].hex(),
        },
        "reference_encoder": {
            "compressor": "CPython 3.11.5 zlib.compress(raw), default level (-1 == 6)",
            "stream_len": len(ref),
            "sha256": ref_sha,
            "header": ref[0:2].hex(),
            "note": ("reference only: the DUT a1_deflate_core is a different "
                     "RFC1950 encoder (same Adler, different length), so the "
                     "compressed byte length is not a pass/fail criterion"),
        },
    }
    (HERE / "expected_raw.json").write_text(
        json.dumps(meta, indent=2) + "\n", encoding="utf-8")

    print(f"EXPECTED_RAW_LEN={len(raw)}")
    print(f"EXPECTED_RAW_SHA256={meta['expected_raw']['sha256']}")
    print(f"EXPECTED_RAW_ADLER32={meta['expected_raw']['adler32']}")
    print(f"EXPECTED_RAW_CRC32={meta['expected_raw']['crc32']}")
    print(f"EXPECTED_FIRST5={raw[0:5].hex()} FIRST_V={v_first} LAST_V={v_last} LAST5={raw[-5:].hex()}")
    print(f"REFERENCE_ENCODER_LEN={len(ref)} REFERENCE_ENCODER_SHA256={ref_sha}")
    print("EXPECTED_RAW_MODEL=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
