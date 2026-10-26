#!/usr/bin/env python3
"""A1 UART byte-stream decoder (PC side, independent of the RTL parser).

Input : a text file with one decimal byte per line (the exact bytes captured
        from the UART transmitter, in order).
Output: per frame -- parsed header, CRC checks, zlib stream, transform bytes,
        reconstructed packed RAW10 image and SHA256 of each artefact.

Header (little endian, 44 bytes):
  0 u32 magic 0x31553141 ('A1U1') | 4 u8 version | 5 u8 flags {pred,prep}
  6 u16 header_len | 8 u32 frame_id | 12 u16 width | 14 u16 height
  16 u32 raw_len | 20 u32 xform_len | 24 u32 stream_len
  28 u32 raw_crc | 32 u32 xform_crc | 36 u32 stream_crc | 40 u32 header_crc
All CRCs are zlib CRC-32 (poly 0xEDB88320, init 0xFFFFFFFF, final xor).
"""
import hashlib
import json
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from a1_pattern import inverse_xform

MAGIC = 0x31553141
HDR = 44
WORST_CASE_EXPANSION = 2594706   # 2,592,000 raw + 540 blocks * 5 + 6 (zlib wrap)


def read_bytes(path):
    out = bytearray()
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("STAT"):
                continue
            out.append(int(line) & 0xFF)
    return bytes(out)


def parse_header(h):
    if len(h) < HDR:
        raise ValueError("short header")
    (magic, ver, flags, hlen, fid, w, hgt, raw_len, xlen, slen,
     raw_crc, xf_crc, st_crc, hcrc) = struct.unpack("<IBBHIHHIIIIIII", h[:HDR])
    return dict(magic=magic, version=ver, flags=flags, header_len=hlen,
                frame_id=fid, width=w, height=hgt, raw_len=raw_len,
                xform_len=xlen, stream_len=slen, raw_crc=raw_crc,
                xform_crc=xf_crc, stream_crc=st_crc, header_crc=hcrc)


def decode_stream(data, outdir=None, write=True):
    frames = []
    off = 0
    n = len(data)
    while off + HDR <= n:
        h = parse_header(data[off:off + HDR])
        if h["magic"] != MAGIC:
            raise ValueError("bad magic 0x%08x at offset %d" % (h["magic"], off))
        if h["version"] != 1:
            raise ValueError("bad version %d" % h["version"])
        if h["header_len"] != HDR:
            raise ValueError("bad header_len %d" % h["header_len"])
        hc = zlib.crc32(data[off:off + 40]) & 0xFFFFFFFF
        hdr_ok = (hc == h["header_crc"])
        pay = data[off + HDR: off + HDR + h["stream_len"]]
        if len(pay) != h["stream_len"]:
            raise ValueError("truncated payload: want %d got %d" % (h["stream_len"], len(pay)))
        prep = h["flags"] & 1
        pred = (h["flags"] >> 1) & 1
        st_crc_ok = (zlib.crc32(pay) & 0xFFFFFFFF) == h["stream_crc"]
        try:
            xf = zlib.decompress(pay)
            zd_ok = True
        except Exception as exc:                                  # pragma: no cover
            xf = b""
            zd_ok = False
            h["zlib_error"] = str(exc)
        len_ok = (len(xf) == h["xform_len"])
        xf_crc_ok = (zlib.crc32(xf) & 0xFFFFFFFF) == h["xform_crc"]
        raw = inverse_xform(xf, prep, pred, h["width"], h["height"]) if zd_ok else b""
        raw_len_ok = (len(raw) == h["raw_len"])
        raw_crc_ok = (zlib.crc32(raw) & 0xFFFFFFFF) == h["raw_crc"]
        rec = dict(h)
        rec.update(dict(prep=prep, pred=pred,
                        header_crc_ok=hdr_ok, stream_crc_ok=st_crc_ok,
                        zlib_ok=zd_ok, xform_len_ok=len_ok, xform_crc_ok=xf_crc_ok,
                        raw_len_ok=raw_len_ok, raw_crc_ok=raw_crc_ok,
                        stream_sha256=hashlib.sha256(pay).hexdigest(),
                        xform_sha256=hashlib.sha256(xf).hexdigest(),
                        raw_sha256=hashlib.sha256(raw).hexdigest(),
                        worstcase_ok=(h["stream_len"] <= WORST_CASE_EXPANSION)))
        if write and outdir:
            d = os.path.join(outdir, "frame_%03d" % h["frame_id"])
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "stream.zlib"), "wb") as f:
                f.write(pay)
            with open(os.path.join(d, "xform.bin"), "wb") as f:
                f.write(xf)
            with open(os.path.join(d, "raw.bin"), "wb") as f:
                f.write(raw)
            rec["dir"] = d
        frames.append(rec)
        off += HDR + h["stream_len"]
    return frames, n - off


def main(argv):
    if len(argv) < 2:
        print("usage: pc_decode.py <bytes.dec> [outdir]")
        return 2
    data = read_bytes(argv[1])
    outdir = argv[2] if len(argv) > 2 else None
    frames, tail = decode_stream(data, outdir)
    res = dict(input=argv[1], bytes=len(data), frames=len(frames), trailing=tail,
               decoded=frames)
    print(json.dumps(res, indent=1))
    ok = tail == 0 and frames and all(
        f["header_crc_ok"] and f["stream_crc_ok"] and f["zlib_ok"] and
        f["xform_len_ok"] and f["xform_crc_ok"] and f["raw_len_ok"] and
        f["raw_crc_ok"] and f["worstcase_ok"] for f in frames)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
