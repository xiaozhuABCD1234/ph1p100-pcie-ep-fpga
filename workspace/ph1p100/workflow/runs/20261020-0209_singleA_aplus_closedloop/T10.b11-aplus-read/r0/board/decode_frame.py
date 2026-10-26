#!/usr/bin/env python3
"""decode_frame.py -- T10.b8-crop-geom r0 A1U1 frame decoder (offline, read only).

Scans a COM8 capture for the frozen 44-byte header (magic 0x31553141) and, for
every complete frame, checks header_crc and stream_crc, zlib-decompresses the
stream and checks the length against xform_len.  Writes frame_<n>.bin (the
decompressed xform stream) and decode.txt next to the other board artefacts.

raw_crc is reported but NOT verified: the stream is the A+ transformed domain
(PREP/PRED on), and the inverse transform is not part of this task.
"""
import argparse
import pathlib
import struct
import zlib

MAGIC = b"A1U1"
HDR = 44


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--outdir", required=True)
    a = ap.parse_args()
    data = pathlib.Path(a.inp).read_bytes()
    out = pathlib.Path(a.outdir)
    out.mkdir(parents=True, exist_ok=True)

    lines = []
    off = 0
    n_ok = n_bad = 0
    pos = data.find(MAGIC)
    while pos >= 0:
        if pos + HDR > len(data):
            lines.append("offset=%d TRUNCATED_HEADER have=%d" % (pos, len(data) - pos))
            break
        h = data[pos:pos + HDR]
        (magic, ver, flags, hlen, fid, w, hgt, raw_len, xlen, slen,
         raw_crc, xcrc, scrc, hcrc) = struct.unpack("<IBBHIHHIIIIIII", h)
        hdr_ok = (magic == 0x31553141 and ver == 1 and hlen == 44 and
                  zlib.crc32(h[:40]) & 0xFFFFFFFF == hcrc)
        body = data[pos + HDR: pos + HDR + slen]
        body_ok = (len(body) == slen and
                   zlib.crc32(body) & 0xFFFFFFFF == scrc)
        dec = None
        if body_ok:
            try:
                dec = zlib.decompress(body)
            except Exception:                       # noqa: BLE001
                # T10.b9: accept a raw deflate stream too (no zlib wrapper)
                try:
                    dec = zlib.decompressobj(-15).decompress(body)
                except Exception as e:              # noqa: BLE001
                    lines.append("  zlib_error=%s" % e)
        len_ok = dec is not None and len(dec) == xlen
        ok = hdr_ok and body_ok and len_ok
        lines.append(
            "offset=%d frame_id=%d ver=%d flags=0x%02X hlen=%d %dx%d raw_len=%d "
            "xform_len=%d stream_len=%d raw_crc=0x%08X xform_crc=0x%08X "
            "stream_crc=0x%08X header_crc=0x%08X hdr_ok=%d stream_ok=%d zlib_ok=%d "
            "VERDICT=%s"
            % (pos, fid, ver, flags, hlen, w, hgt, raw_len, xlen, slen,
               raw_crc, xcrc, scrc, hcrc, hdr_ok, body_ok, len_ok,
               "OK" if ok else "BAD"))
        if ok:
            n_ok += 1
            (out / ("frame_%02d.bin" % n_ok)).write_bytes(dec)
            lines.append("  saved frame_%02d.bin bytes=%d" % (n_ok, len(dec)))
        else:
            n_bad += 1
        pos = data.find(MAGIC, pos + 4)

    lines.append("frames_ok=%d frames_bad=%d" % (n_ok, n_bad))
    txt = "\n".join(lines) + "\n"
    (out / "decode.txt").write_text(txt)
    print(txt)
    return 0 if n_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
