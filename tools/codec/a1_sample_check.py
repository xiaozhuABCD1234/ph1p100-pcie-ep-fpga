#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T10 A+ v1 test-record checker (P1, test-only).

Validates the 32-byte A1T1 record, then the exact zlib stream (via the
independent strict parser), then the xform/raw CRCs and the inverse Bayer
transform. It never calls zlib; the verifier runs zlib separately.

Record layout (little endian, see format-v1.md §6):
  0x00 A1T1 | 0x04 u16 version | 0x06 u16 flags
  0x08 raw_len | 0x0C xform_len | 0x10 stream_len
  0x14 raw_crc32 | 0x18 xform_crc32 | 0x1C header_crc32
Header CRC covers [0x00,0x1C).
"""
import struct
import sys

sys.dont_write_bytecode = True

import a1_inflate_strict as strict
import a1_ref

E_RECORD_TRUNCATED = "E_RECORD_TRUNCATED"
E_BAD_MAGIC = "E_BAD_MAGIC"
E_BAD_VERSION = "E_BAD_VERSION"
E_BAD_FLAGS = "E_BAD_FLAGS"
E_BAD_HEADER_CRC = "E_BAD_HEADER_CRC"
E_STREAM_LEN_MISMATCH = "E_STREAM_LEN_MISMATCH"
E_BAD_RAW_LEN = "E_BAD_RAW_LEN"
E_BAD_XFORM_LEN = "E_BAD_XFORM_LEN"
E_BAD_XFORM_CRC = "E_BAD_XFORM_CRC"
E_BAD_RAW_CRC = "E_BAD_RAW_CRC"
E_BAD_GEOMETRY = "E_BAD_GEOMETRY"

REC_SIZE = 32


class RecordError(Exception):
    def __init__(self, code, detail=""):
        self.code = code
        self.detail = detail
        super().__init__(code + (": " + detail if detail else ""))


def parse_record(rec):
    if len(rec) < REC_SIZE:
        raise RecordError(E_RECORD_TRUNCATED, "len=%d" % len(rec))
    magic, version, flags, raw_len, xform_len, stream_len, raw_crc, xform_crc, hdr_crc = \
        struct.unpack_from("<4sHHIIIIII", rec, 0)
    if magic != a1_ref.TEST_MAGIC:
        raise RecordError(E_BAD_MAGIC, repr(magic))
    if version != a1_ref.TEST_VERSION:
        raise RecordError(E_BAD_VERSION, "version=%d" % version)
    if flags & ~0x3:
        raise RecordError(E_BAD_FLAGS, "flags=%04X" % flags)
    calc = a1_ref.crc32(bytes(rec[:0x1C]))
    if calc != hdr_crc:
        raise RecordError(E_BAD_HEADER_CRC, "stored=%08X calc=%08X" % (hdr_crc, calc))
    return {
        "version": version,
        "flags": flags,
        "prep_en": flags & 1,
        "pred_en": (flags >> 1) & 1,
        "raw_len": raw_len,
        "xform_len": xform_len,
        "stream_len": stream_len,
        "raw_crc32": raw_crc,
        "xform_crc32": xform_crc,
        "header_crc32": hdr_crc,
    }


def check_record(rec, w, h):
    info = parse_record(rec)
    try:
        stride = a1_ref.validate_geometry(w, h, info["prep_en"], info["pred_en"])
    except ValueError as e:
        raise RecordError(E_BAD_GEOMETRY, str(e))
    expected_raw = stride * h
    if info["raw_len"] != expected_raw:
        raise RecordError(E_BAD_RAW_LEN, "declared=%d expected=%d" % (info["raw_len"], expected_raw))
    if info["xform_len"] != info["raw_len"]:
        raise RecordError(E_BAD_XFORM_LEN, "raw=%d xform=%d" % (info["raw_len"], info["xform_len"]))
    if len(rec) != REC_SIZE + info["stream_len"]:
        raise RecordError(E_STREAM_LEN_MISMATCH,
                          "record=%d declared_stream=%d" % (len(rec), info["stream_len"]))
    stream = bytes(rec[REC_SIZE:])
    try:
        xform, st = strict.inflate(stream, expected_len=info["xform_len"])
    except strict.A1Error as e:
        raise RecordError(e.code, e.detail)
    if a1_ref.crc32(xform) != info["xform_crc32"]:
        raise RecordError(E_BAD_XFORM_CRC,
                          "stored=%08X calc=%08X" % (info["xform_crc32"], a1_ref.crc32(xform)))
    raw = a1_ref.inverse_frame(xform, w, h, info["prep_en"], info["pred_en"])
    if a1_ref.crc32(raw) != info["raw_crc32"]:
        raise RecordError(E_BAD_RAW_CRC,
                          "stored=%08X calc=%08X" % (info["raw_crc32"], a1_ref.crc32(raw)))
    info.update({"w": w, "h": h, "raw": raw, "xform": xform, "stream": stream,
                 "strict_stats": st})
    return info


def main(argv):
    import argparse
    ap = argparse.ArgumentParser(description="A1T1 test-record checker")
    ap.add_argument("record")
    ap.add_argument("--width", type=int, required=True)
    ap.add_argument("--height", type=int, required=True)
    args = ap.parse_args(argv)
    data = open(args.record, "rb").read()
    try:
        info = check_record(data, args.width, args.height)
    except RecordError as e:
        print("SAMPLE_REJECT %s %s" % (e.code, e.detail))
        return 1
    print("SAMPLE_OK raw_len=%d xform_len=%d stream_len=%d blocks=%d raw_crc=%08X xform_crc=%08X raw_sha256=%s"
          % (info["raw_len"], info["xform_len"], info["stream_len"],
             info["strict_stats"]["blocks"], info["raw_crc32"], info["xform_crc32"],
             a1_ref.sha256(info["raw"])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
