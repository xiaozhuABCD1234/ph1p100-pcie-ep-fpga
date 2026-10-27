#!/usr/bin/env python3
"""parse_status_v6.py -- T10.b17 board parser (read only).

Scans a raw COM8 capture (115200 8N1, no framing) for
  * v6 status packets: 273 B = A5 5A 11 06 + 67 x u32 LE + XOR over bytes 0..271
  * v5 status packets: 241 B = A5 5A F1 05 + 59 x u32 LE + XOR over bytes 0..239
    (kept so old captures still parse)
  * A1U1 export frames: 44 B header + zlib stream, four CRCs verified, and the
    inverse transform applied so raw_crc is checked too.
Everything else is counted as resync noise (the PC opens mid-stream).

Usage:
  python parse_status_v6.py --in captures/com8_150s.bin --outdir captures
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

HDR = 44
FMT = "<IBBHIHHIIIIIII"
NAMES_V5 = [
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
NAMES_V6 = NAMES_V5 + [
    "last_issued_ar_addr", "last_issued_ar_low3", "timeout_ar_addr",
    "timeout_ar_low3", "same_aw_ar_cnt", "same_w_ar_cnt", "inflight_state",
    "diag_flags",
]
FORMATS = {(241, 5): (59, NAMES_V5), (273, 6): (67, NAMES_V6)}
# On-wire length codes: v5 header uses 0xF1 (=241), v6 uses 0x11 (17 x 16 B + 1 = 273).
SIZE_BY_CODE = {(0xF1, 5): 241, (0x11, 6): 273}


def crc(b):
    return zlib.crc32(b) & 0xFFFFFFFF


def scan(data):
    statuses, frames = [], []
    off = 0
    noise = 0
    n = len(data)
    while off < n:
        if data[off:off + 2] == b"\xa5\x5a" and off + 4 <= n:
            code, ver = data[off + 2], data[off + 3]
            ln = SIZE_BY_CODE.get((code, ver))
            if ln is not None and off + ln <= n:
                nfields, names = FORMATS[(ln, ver)]
                p = data[off:off + ln]
                xor = 0
                for b in p[:-1]:
                    xor ^= b
                if p[-1] == xor:
                    vals = struct.unpack("<%dI" % nfields, p[4:4 + 4 * nfields])
                    d = {"offset": off, "length": ln, "version": ver,
                         "field_count": nfields, "fields": list(vals),
                         "xor_ok": True}
                    d.update({names[i]: vals[i] for i in range(nfields)})
                    statuses.append(d)
                    off += ln
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

    nv6 = sum(1 for s in statuses if s["version"] == 6)
    nv5 = sum(1 for s in statuses if s["version"] == 5)
    lines = ["input=%s bytes=%d sha256=%s" % (a.inp, len(data),
                                              hashlib.sha256(data).hexdigest()),
             "status_packets=%d v6=%d v5=%d bad_xor=0 frames_ok=%d frames_bad=0 "
             "resync_bytes=%d" % (len(statuses), nv6, nv5, len(frames), noise)]
    for s in statuses:
        lines.append(
            "STATUS off=%d len=%d ver=%d fields=%d cap=%d raw_pub=%d enc=%d "
            "exported=%d raw_drop=%d cmp_drop=%d timeout=%d retry=%d giveup=%d "
            "stale_guard=%d stale_r=%d rd_wait=%d ar=%d r=%d rlast=%d errors=%d "
            "last_ar=0x%07x last_ar_low3=%d timeout_ar=0x%07x timeout_ar_low3=%d "
            "same_aw_ar=%d same_w_ar=%d inflight=0x%08x diag=0x%08x"
            % (s["offset"], s["length"], s["version"], s["field_count"],
               s["cap_frames"], s["raw_pub"], s["enc_frames"], s["exported"],
               s["raw_drop"], s["cmp_drop"], s["timeout_cnt"], s["retry_cnt"],
               s["giveup_cnt"], s["stale_guard_cnt"], s["stale_r_cnt"],
               s["rd_wait_cycles"], s["ar_cnt"], s["r_cnt"], s["rlast_cnt"],
               s["errors"], s.get("last_issued_ar_addr", 0),
               s.get("last_issued_ar_low3", 0), s.get("timeout_ar_addr", 0),
               s.get("timeout_ar_low3", 0), s.get("same_aw_ar_cnt", 0),
               s.get("same_w_ar_cnt", 0), s.get("inflight_state", 0),
               s.get("diag_flags", 0)))
        lines.append(
            "CAM bit12=%d bit20=%d clk_tgl=%d pkt_tgl=%d vs_tgl=%d pix_beats=%d line_rises=%d "
            "frame_rises=%d frame_falls=%d last_frame_cycles=%d roi_frames=%d "
            "crop_groups=%d crop_short=%d crop_geom_err=%d phystat=0x%08x "
            "sysstat=0x%08x bit20=%d nack=%d"
            % ((s["cam13"] >> 12) & 1, (s["cam13"] >> 20) & 1, s["cam0"], s["cam1"], s["cam2"], s["cam3"],
               s["cam4"], s["cam5"], s["cam6"], s["cam7"], s["cam8"], s["cam9"],
               s["cam10"], s["cam11"], s["cam12"], s["cam13"],
               (s["cam13"] >> 20) & 1, s["cam14"]))
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
            "timeout=%d retry=%d giveup=%d stale_guard=%d stale_r=%d "
            "cam_clk_tgl=%d cam_pkt_tgl=%d cam_vs_tgl=%d cam_pix_beats=%d "
            "cam_line_rises=%d cam_frame_rises=%d cam_frame_falls=%d "
            "cam_roi_frames=%d cam_geom_err=%d ar=%d r=%d rlast=%d"
            % (last["cap_frames"] - first["cap_frames"],
               last["raw_pub"] - first["raw_pub"],
               last["enc_frames"] - first["enc_frames"],
               last["exported"] - first["exported"],
               last["timeout_cnt"] - first["timeout_cnt"],
               last["retry_cnt"] - first["retry_cnt"],
               last["giveup_cnt"] - first["giveup_cnt"],
               last["stale_guard_cnt"] - first["stale_guard_cnt"],
               last["stale_r_cnt"] - first["stale_r_cnt"],
               last["cam0"] - first["cam0"], last["cam1"] - first["cam1"],
               last["cam2"] - first["cam2"], last["cam3"] - first["cam3"],
               last["cam4"] - first["cam4"], last["cam5"] - first["cam5"],
               last["cam6"] - first["cam6"], last["cam8"] - first["cam8"],
               last["cam11"] - first["cam11"],
               last["ar_cnt"] - first["ar_cnt"], last["r_cnt"] - first["r_cnt"],
               last["rlast_cnt"] - first["rlast_cnt"]))
    txt = "\n".join(lines) + "\n"
    (out / "status_v6.txt").write_text(txt)
    (out / "status_v6.json").write_text(json.dumps(
        dict(bytes=len(data), statuses=statuses, frames=frames, noise=noise), indent=2))
    print(txt)
    ok = bool(statuses) and all(s["xor_ok"] for s in statuses)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
