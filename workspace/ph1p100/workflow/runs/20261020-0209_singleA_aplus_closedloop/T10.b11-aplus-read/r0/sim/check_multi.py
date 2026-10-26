#!/usr/bin/env python3
"""check_multi.py -- strict sequential parser for the tb_b10_multi capture.

The stream must be exactly: frame, (177-byte status packet)*, frame, ... with no
byte inserted inside a frame.  Every frame header CRC, stream CRC and zlib
decode (to W*H*10/8 bytes) is verified; every status packet ver/len/XOR is
checked.
"""
import pathlib
import struct
import sys
import zlib

MAGIC = b"A1U1"
HDR = 44
STS = 177


def parse_status(buf, off):
    p = buf[off:off + STS]
    if len(p) != STS:
        return None, "truncated"
    if p[0] != 0xA5 or p[1] != 0x5A or p[2] != STS or p[3] != 3:
        return None, "bad header %02x %02x %02x %02x" % (p[0], p[1], p[2], p[3])
    x = 0
    for b in p[:STS - 1]:
        x ^= b
    if x != p[STS - 1]:
        return None, "xor %02x != %02x" % (x, p[STS - 1])
    return p, None


def main():
    dec = pathlib.Path(sys.argv[1])
    stat = pathlib.Path(sys.argv[2])
    outdir = pathlib.Path(sys.argv[3])
    outdir.mkdir(parents=True, exist_ok=True)
    buf = bytes(int(x) for x in dec.read_text().split())
    stats = stat.read_text().strip() if stat.exists() else ""
    off = 0
    frames = 0
    sts = 0
    bad = 0
    lines = []
    while off < len(buf):
        if buf[off:off + 4] == MAGIC:
            if off + HDR > len(buf):
                lines.append("TRUNC_HEADER off=%d" % off)
                bad += 1
                break
            h = buf[off:off + HDR]
            (magic, ver, flags, hlen, fid, w, hgt, raw_len, xlen, slen,
             raw_crc, xcrc, scrc, hcrc) = struct.unpack("<IBBHIHHIIIIIII", h)
            hdr_ok = (magic == 0x31553141 and ver == 1 and hlen == 44 and
                      (zlib.crc32(h[:40]) & 0xFFFFFFFF) == hcrc)
            body = buf[off + HDR:off + HDR + slen]
            body_ok = len(body) == slen and (zlib.crc32(body) & 0xFFFFFFFF) == scrc
            dec_ok = False
            dec_len = 0
            if body_ok:
                try:
                    d = zlib.decompress(body)
                except Exception:                        # noqa: BLE001
                    try:
                        d = zlib.decompressobj(-15).decompress(body)
                    except Exception as e:               # noqa: BLE001
                        d = None
                        lines.append("  zlib_error=%s" % e)
                if d is not None:
                    dec_len = len(d)
                    dec_ok = (len(d) == xlen)
                    (outdir / ("frame_%02d.bin" % (frames + 1))).write_bytes(d)
            ok = hdr_ok and body_ok and dec_ok
            lines.append("frame=%d off=%d id=%d %dx%d raw_len=%d xform_len=%d stream_len=%d "
                         "hdr_ok=%d stream_ok=%d zlib_ok=%d dec_len=%d %s"
                         % (frames + 1, off, fid, w, hgt, raw_len, xlen, slen,
                            hdr_ok, body_ok, dec_ok, dec_len, "OK" if ok else "BAD"))
            bad += 0 if ok else 1
            frames += 1
            off += HDR + slen
        elif buf[off:off + 2] == b"\xA5\x5A":
            p, err = parse_status(buf, off)
            if err:
                lines.append("status off=%d BAD %s" % (off, err))
                bad += 1
                break
            sts += 1
            lines.append("status=%d off=%d OK" % (sts, off))
            off += STS
        else:
            lines.append("UNEXPECTED byte 0x%02x at off=%d" % (buf[off], off))
            bad += 1
            break
    verdict = (bad == 0 and frames == 3 and sts >= 1)
    lines.append("frames=%d status=%d bad=%d" % (frames, sts, bad))
    lines.append(stats)
    lines.append("MULTI_CHECK_%s" % ("OK" if verdict else "FAIL"))
    txt = "\n".join(lines) + "\n"
    (outdir / "check.txt").write_text(txt)
    print(txt)
    return 0 if verdict else 1


if __name__ == "__main__":
    raise SystemExit(main())
