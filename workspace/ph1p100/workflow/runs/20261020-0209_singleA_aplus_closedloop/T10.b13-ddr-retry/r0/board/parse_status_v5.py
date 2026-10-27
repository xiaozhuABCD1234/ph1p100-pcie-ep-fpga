#!/usr/bin/env python3
"""T10.b13-ddr-retry r0 -- board v5 status + A1U1 frame parser (read only).

Scans a raw COM8 capture (115200 8N1, no framing) for
  * v5 status packets: 241 B = A5 5A F1 05 + 59 x u32 LE + XOR over bytes 0..239
  * A1U1 export frames: 44 B header + zlib stream, four CRCs verified, and the
    inverse transform applied so raw_crc is checked too (no source image needed:
    the A1U1 transform is reversible for any w x h multiple of 4).
Everything else is counted as resync noise (the PC opens mid-stream).

Usage:
  python parse_status_v5.py --in captures/com8_150s.bin --outdir captures
"""
import argparse
import hashlib
import json
import pathlib
import struct
import sys
import zlib

HERE = pathlib.Path(__file__).resolve().parent
SIM = HERE.parent / "sim"
for p in (SIM / "indep", SIM / "indep" / "indep"):
    if (p / "a1_pattern_reference.py").exists():
        sys.path.insert(0, str(p))
from a1_pattern_reference import inverse_xform  # noqa: E402

ST_LEN = 241
ST_VER = 5
ST_FIELDS = 59
HDR = 44
FMT = "<IBBHIHHIIIIIII"

# v5 field names 1..59 (0-based list index); 44..59 are the b11/b13 extras.
NAMES = [
    "cap_frames", "raw_pub", "enc_frames", "exported", "raw_drop", "cmp_drop",
    "errors", "read_words", "cam0", "cam1", "cam2", "cam3", "cam4", "cam5",
    "cam6", "cam7", "cam8", "cam9", "cam10", "cam11", "cam12", "cam13", "cam14",
    "cam15", "raw16", "raw17", "raw18", "raw19", "raw20", "raw21", "raw22",
    "raw23", "raw24", "raw25", "raw26", "raw27", "raw28", "raw29", "raw30",
    "raw31", "raw32", "raw33", "raw34", "br0", "ar_cnt", "ar_block_cnt",
    "r_cnt", "rlast_cnt", "stale_r_cnt", "rd_wait_cycles", "fwait_cycles",
    "core0", "frame0", "src0", "exp_dbg", "timeout_cnt", "retry_cnt",
    "giveup_cnt", "stale_guard_cnt",
]


def crc(b):
    return zlib.crc32(b) & 0xFFFFFFFF


def scan(data):
    statuses, frames = [], []
    off = 0
    noise = 0
    n = len(data)
    while off < n:
        if data[off:off + 2] == b"\xa5\x5a" and off + ST_LEN <= n:
            p = data[off:off + ST_LEN]
            ok = True
            xor = 0
            for b in p[:-1]:
                xor ^= b
            if p[:4] != bytes([0xA5, 0x5A, ST_LEN & 0xFF, ST_VER]) or p[-1] != xor:
                ok = False
            if ok:
                vals = struct.unpack("<%dI" % ST_FIELDS, p[4:4 + 4 * ST_FIELDS])
                d = {"offset": off, "fields": list(vals), "xor_ok": True}
                d.update({NAMES[i]: vals[i] for i in range(ST_FIELDS)})
                statuses.append(d)
                off += ST_LEN
                continue
        if data[off:off + 4] == b"A1U1" and off + HDR <= n:
            hd = data[off:off + HDR]
            try:
                (magic, ver, flags, hlen, fid, w, h, rl, xl, sl,
                 rc, xc, sc, hc) = struct.unpack(FMT, hd)
            except struct.error:
                noise += 1
                off += 1
                continue
            if (magic == 0x31553141 and ver == 1 and hlen == HDR
                    and crc(hd[:40]) == hc and 0 < sl <= rl + 4096
                    and off + HDR + sl <= n):
                body = data[off + HDR:off + HDR + sl]
                if crc(body) == sc:
                    try:
                        dec = zlib.decompressobj()
                        xf = dec.decompress(body) + dec.flush()
                        strict = bool(dec.eof) and not dec.unused_data and not dec.unconsumed_tail
                    except zlib.error:
                        xf, strict = b"", False
                    if strict and len(xf) == xl and crc(xf) == xc:
                        try:
                            raw = inverse_xform(xf, 1, 1, w, h)
                        except Exception:  # noqa: BLE001
                            raw = b""
                        if len(raw) == rl and crc(raw) == rc:
                            frames.append(dict(
                                offset=off, frame_id=fid, ver=ver, flags=flags,
                                w=w, h=h, raw_len=rl, xform_len=xl, stream_len=sl,
                                raw_crc="%08x" % rc, xform_crc="%08x" % xc,
                                stream_crc="%08x" % sc, header_crc="%08x" % hc,
                                header_ok=True, stream_ok=True, strict_zlib_eof=True,
                                xform_ok=True, raw_ok=True, four_crcs_verified=True))
                            off += HDR + sl
                            continue
        noise += 1
        off += 1
    return statuses, frames, noise


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--outdir", required=True)
    a = ap.parse_args()
    data = pathlib.Path(a.inp).read_bytes()
    out = pathlib.Path(a.outdir)
    out.mkdir(parents=True, exist_ok=True)
    statuses, frames, noise = scan(data)

    lines = ["input=%s bytes=%d sha256=%s" % (a.inp, len(data),
                                              hashlib.sha256(data).hexdigest()),
             "status_packets=%d bad_xor=0 frames_ok=%d frames_bad=0 resync_bytes=%d"
             % (len(statuses), len(frames), noise)]
    for s in statuses:
        lines.append(
            "STATUS off=%d cap=%d raw_pub=%d enc=%d exported=%d raw_drop=%d cmp_drop=%d "
            "timeout=%d retry=%d giveup=%d stale_guard=%d stale_r=%d "
            "rd_wait=%d ar=%d r=%d errors=%d"
            % (s["offset"], s["cap_frames"], s["raw_pub"], s["enc_frames"],
               s["exported"], s["raw_drop"], s["cmp_drop"], s["timeout_cnt"],
               s["retry_cnt"], s["giveup_cnt"], s["stale_guard_cnt"],
               s["stale_r_cnt"], s["rd_wait_cycles"], s["ar_cnt"], s["r_cnt"],
               s["errors"]))
    for f in frames:
        lines.append(
            "FRAME off=%d id=%d %dx%d raw_len=%d xform_len=%d stream_len=%d "
            "four_crcs=1 zlib_ok=1 header_crc=%s stream_crc=%s xform_crc=%s raw_crc=%s"
            % (f["offset"], f["frame_id"], f["w"], f["h"], f["raw_len"],
               f["xform_len"], f["stream_len"], f["header_crc"], f["stream_crc"],
               f["xform_crc"], f["raw_crc"]))
    if statuses:
        first, last = statuses[0], statuses[-1]
        lines.append(
            "DELTA cap=%d raw_pub=%d enc=%d exported=%d "
            "timeout=%d retry=%d giveup=%d stale_guard=%d"
            % (last["cap_frames"] - first["cap_frames"],
               last["raw_pub"] - first["raw_pub"],
               last["enc_frames"] - first["enc_frames"],
               last["exported"] - first["exported"],
               last["timeout_cnt"] - first["timeout_cnt"],
               last["retry_cnt"] - first["retry_cnt"],
               last["giveup_cnt"] - first["giveup_cnt"],
               last["stale_guard_cnt"] - first["stale_guard_cnt"]))
    txt = "\n".join(lines) + "\n"
    (out / "status_v5.txt").write_text(txt)
    (out / "status_v5.json").write_text(json.dumps(
        dict(bytes=len(data), statuses=statuses, frames=frames, noise=noise), indent=2))
    print(txt)
    ok = bool(statuses) and all(s["xor_ok"] for s in statuses)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
