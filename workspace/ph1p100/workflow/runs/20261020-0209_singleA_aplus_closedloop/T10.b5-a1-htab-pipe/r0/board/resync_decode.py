#!/usr/bin/env python3
"""T10.b2-a1-uart-impl r4 -- resynchronising front end for pc_decode.py.

The r4 candidate adds an idle beacon: a single 0x55 byte every HB_DIV clk_a1
cycles (HB_DIV = 4194304 -> ~44.7 Hz at 187.5 MHz), emitted only while the
exporter has no descriptor pending and no frame open.  The beacon can never
appear inside a 44-byte header or a payload, so the frame format, CRCs and byte
order are unchanged; only the PC-side reader has to skip bytes between frames.

This tool scans the raw capture for 0x31553141, accepts a frame only when the
44-byte header is self-consistent (version 1, header_len 44, header_crc ok,
stream_len <= worst case, whole frame present), then hands the concatenated
frame bytes to tools/a1/pc_decode.py for the full zlib/CRC/RAW10 verification.

Usage:
  python resync_decode.py <capture.bin> <outdir>
Exit code 0 only when at least one frame decodes and every per-frame check in
pc_decode passes.
"""
import hashlib
import json
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, *([".."] * 6)))
sys.path.insert(0, os.path.join(ROOT, "tools", "a1"))

import pc_decode  # noqa: E402

MAGIC = b"A1U1"
HDR = 44
WORST = pc_decode.WORST_CASE_EXPANSION


def find_frames(buf):
    frames = []
    gaps = []
    off = 0
    n = len(buf)
    last_end = 0
    while off + HDR <= n:
        if buf[off:off + 4] != MAGIC:
            off += 1
            continue
        (magic, ver, flags, hlen, fid, w, hgt, raw_len, xlen, slen,
         raw_crc, xf_crc, st_crc, hcrc) = struct.unpack("<IBBHIHHIIIIIII",
                                                       buf[off:off + HDR])
        ok = (ver == 1 and hlen == HDR and 0 < slen <= WORST and
              (zlib.crc32(buf[off:off + 40]) & 0xFFFFFFFF) == hcrc and
              off + HDR + slen <= n)
        if not ok:
            off += 1
            continue
        frames.append((off, HDR + slen))
        if off > last_end:
            gaps.append(off - last_end)
        last_end = off + HDR + slen
        off += HDR + slen
    tail = n - last_end
    return frames, gaps, tail


def main(argv):
    if len(argv) < 3:
        print("usage: resync_decode.py <capture.bin> <outdir>")
        return 2
    src, outdir = argv[1], argv[2]
    with open(src, "rb") as f:
        buf = f.read()
    os.makedirs(outdir, exist_ok=True)

    frames, gaps, tail = find_frames(buf)
    clean = bytearray()
    for off, ln in frames:
        clean += buf[off:off + ln]

    res = {
        "input": src,
        "raw_bytes": len(buf),
        "raw_sha256": hashlib.sha256(buf).hexdigest(),
        "frames_found": len(frames),
        "frame_offsets": [o for o, _ in frames],
        "gap_bytes_between_frames": gaps,
        "gap_total": sum(gaps),
        "tail_bytes": tail,
        "gap_all_beacon_0x55": all(
            all(b == 0x55 for b in buf[frames[i][0] + frames[i][1]:
                                       frames[i + 1][0]])
            for i in range(len(frames) - 1)),
    }

    decoded, dtail = pc_decode.decode_stream(bytes(clean), outdir, write=True)
    res["decoded_frames"] = len(decoded)
    res["decoded_trailing"] = dtail
    res["frames"] = decoded

    ok = (len(frames) > 0 and dtail == 0 and len(decoded) == len(frames) and
          all(f["header_crc_ok"] and f["stream_crc_ok"] and f["zlib_ok"] and
              f["xform_len_ok"] and f["xform_crc_ok"] and f["raw_len_ok"] and
              f["raw_crc_ok"] and f["worstcase_ok"] for f in decoded))
    res["all_checks_ok"] = bool(ok)

    with open(os.path.join(outdir, "decode_r4.json"), "w") as f:
        json.dump(res, f, indent=1)
    print(json.dumps({k: v for k, v in res.items() if k != "frames"}, indent=1))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
