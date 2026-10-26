#!/usr/bin/env python3
"""parse_status_v2.py -- T10.b7 r0-diag status packet v2 parser.

Wire format (little endian, 1 Hz while the A1 exporter is idle):

    off  len  field
    0    1    0xA5
    1    1    0x5A
    2    1    LEN = 0x61 (97)
    3    1    VER = 0x02
    4    32   8 x u32 legacy counters (v1 order):
              cap_frames, raw_pub, enc_frames, exported,
              raw_drop, cmp_drop, errors, read_words
    36   60   15 x u32 camera front-end counters:
              cam_clk_tgl_inc, cam_pkt_tgl_inc, cam_vs_tgl_inc, cam_pix_beats,
              cam_line_rises, cam_frame_rises, cam_frame_falls,
              cam_last_frame_cycles, crop_roi_frames, crop_groups, crop_short,
              crop_geom_err, cam_phystat, cam_sysstat, cam_nack_cnt
    96   1    XOR8 over bytes 0..95

Input is either the raw .bin capture or the one-decimal-byte-per-line .dec
text produced by the ModelSim testbenches.

Counter handling: every field is treated as a 32-bit wrapping counter; the
delta between consecutive packets adds 2**32 when the new value is lower.
Level/status fields (cam_phystat, cam_sysstat, cam_nack_cnt) additionally get
an OR over all packets and their first/last raw values.
"""

import argparse
import pathlib
import sys

MAGIC = b"\xA5\x5A"
LEN = 0x61
VER = 0x02
PKT = 97

LEGACY = ["cap_frames", "raw_pub", "enc_frames", "exported",
          "raw_drop", "cmp_drop", "errors", "read_words"]

CAM = ["cam_clk_tgl_inc", "cam_pkt_tgl_inc", "cam_vs_tgl_inc", "cam_pix_beats",
       "cam_line_rises", "cam_frame_rises", "cam_frame_falls",
       "cam_last_frame_cycles", "crop_roi_frames", "crop_groups", "crop_short",
       "crop_geom_err", "cam_phystat", "cam_sysstat", "cam_nack_cnt"]

FIELDS = LEGACY + CAM
LEVEL = {"cam_phystat", "cam_sysstat", "cam_nack_cnt"}

PHYS_BITS = [("delay_tap", 0, 5), ("delay_done", 6, 6), ("rst_out", 7, 7),
             ("sync_wait", 8, 8), ("in_frame_now", 9, 9), ("vsync_now", 10, 10)]

SYS_BITS = [("cfg_done", 0, 0), ("bus_err_lat", 1, 1), ("xclr_n", 2, 2),
            ("pll_locked", 3, 3), ("cfg_rst_n", 4, 4),
            ("lane_sticky", 8, 11)]


def load_bytes(path):
    p = pathlib.Path(path)
    raw = p.read_bytes()
    if raw[:1] == b"\xa5" and len(raw) > PKT:
        return raw
    # one decimal byte per line?
    if raw[:1].isdigit():
        vals = [int(x) for x in raw.split() if x.strip()]
        return bytes(v & 0xFF for v in vals)
    return raw


def parse(buf):
    packets, bad_xor, bad_hdr, skipped = [], 0, 0, 0
    i = 0
    while i + PKT <= len(buf):
        if buf[i:i + 2] != MAGIC:
            i += 1
            skipped += 1
            continue
        pkt = buf[i:i + PKT]
        if pkt[2] != LEN or pkt[3] != VER:
            bad_hdr += 1
            i += 1
            continue
        x = 0
        for b in pkt[:96]:
            x ^= b
        if x != pkt[96]:
            bad_xor += 1
            i += 1
            continue
        vals = [int.from_bytes(pkt[4 + 4 * k:8 + 4 * k], "little")
                for k in range(len(FIELDS))]
        packets.append(vals)
        i += PKT
    return packets, bad_xor, bad_hdr, skipped


def wrap_delta(new, old):
    d = new - old
    if d < 0:
        d += 1 << 32
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--out", dest="out", required=True)
    ap.add_argument("--min-packets", type=int, default=0)
    args = ap.parse_args()

    data = load_bytes(args.inp)
    packets, bad_xor, bad_hdr, skipped = parse(data)

    lines = []
    add = lines.append
    add("T10.b7 status packet v2 parse")
    add("input            : %s" % args.inp)
    add("bytes            : %d" % len(data))
    add("packet size      : %d" % PKT)
    add("packets          : %d" % len(packets))
    add("bad_xor          : %d" % bad_xor)
    add("bad_len_ver      : %d" % bad_hdr)
    add("skipped_bytes    : %d" % skipped)
    add("trailing_bytes   : %d" % (len(data) - len(packets) * PKT - skipped))
    add("")

    if not packets:
        add("NO_PACKETS")
        txt = "\n".join(lines) + "\n"
        pathlib.Path(args.out).write_text(txt)
        print(txt)
        return 2

    first, last = packets[0], packets[-1]
    add("%-22s %12s %12s %12s %12s" % ("field", "first", "last", "delta_wrap", "or_all"))
    for k, name in enumerate(FIELDS):
        tot = 0
        prev = first[k]
        orv = first[k]
        for p in packets[1:]:
            tot += wrap_delta(p[k], prev)
            prev = p[k]
            orv |= p[k]
        add("%-22s %12d %12d %12d 0x%08X" % (name, first[k], last[k], tot, orv))

    add("")
    add("level fields (first / last / OR):")
    for k, name in enumerate(FIELDS):
        if name in LEVEL:
            add("  %-14s 0x%08X / 0x%08X / 0x%08X" %
                (name, first[k], last[k],
                 (lambda v: v)(first[k]) | last[k]))

    add("")
    add("cam_phystat decode (last packet): 0x%08X" % last[12])
    for name, lo, hi in PHYS_BITS:
        add("  %-12s = %d" % (name, (last[12] >> lo) & ((1 << (hi - lo + 1)) - 1)))
    add("cam_sysstat decode (last packet): 0x%08X" % last[13])
    for name, lo, hi in SYS_BITS:
        add("  %-12s = %d" % (name, (last[13] >> lo) & ((1 << (hi - lo + 1)) - 1)))

    # ---------------------------------------------------------------- answers
    d = {}
    for k, name in enumerate(FIELDS):
        tot, prev = 0, first[k]
        for p in packets[1:]:
            tot += wrap_delta(p[k], prev)
            prev = p[k]
        d[name] = tot
    clk_tgl, pkt_tgl, vs_tgl = d["cam_clk_tgl_inc"], d["cam_pkt_tgl_inc"], d["cam_vs_tgl_inc"]
    beats, line_r = d["cam_pix_beats"], d["cam_line_rises"]
    roi, groups = d["crop_roi_frames"], d["crop_groups"]
    short, geom = d["crop_short"], d["crop_geom_err"]
    sys_or = 0
    phys_or = 0
    for p in packets:
        sys_or |= p[13]
        phys_or |= p[12]
    cfg_done = (sys_or >> 0) & 1
    bus_err = (sys_or >> 1) & 1
    xclr_n = (sys_or >> 2) & 1
    pll_lock = (sys_or >> 3) & 1
    cfg_rst_n = (sys_or >> 4) & 1
    lane = (sys_or >> 8) & 0xF
    nack_inc = d["cam_nack_cnt"]
    tap = (last[12] >> 0) & 0x3F
    delay_done = (last[12] >> 6) & 1
    rst_out = (last[12] >> 7) & 1
    sync_wait = (last[12] >> 8) & 1
    in_frame_last = (last[12] >> 9) & 1
    vsync_last = (last[12] >> 10) & 1

    add("")
    add("=== Q1 MIPI: is there data? ===")
    if clk_tgl == 0 and beats == 0 and pkt_tgl == 0:
        q1 = "NO - MIPI byte clock is dead (cam_clk_tgl_inc delta = 0)"
    elif clk_tgl > 0 and pkt_tgl == 0 and beats == 0:
        q1 = "NO CSI packets - byte clock alive but no packet/pixel (lane align / sync / sensor not streaming)"
    elif beats > 0 and groups == 0:
        q1 = "PIXELS PRESENT but crop never accepted a group (tap/line/frame semantics)"
    elif groups > 0 and roi == 0:
        q1 = "PIXELS + crop groups present but no complete ROI frame (short/geom)"
    elif roi > 0:
        q1 = "YES - complete ROI frames reached the crop"
    else:
        q1 = "UNRESOLVED"
    add("answer           : " + q1)
    add("evidence         : cam_clk_tgl_inc=%d cam_pkt_tgl_inc=%d cam_pix_beats=%d "
        "cam_line_rises=%d cam_frame_rises=%d cam_frame_falls=%d cam_vs_tgl_inc=%d"
        % (clk_tgl, pkt_tgl, beats, line_r, d["cam_frame_rises"],
           d["cam_frame_falls"], vs_tgl))
    add("supporting state : lane_sticky=0x%X rst_out=%d sync_wait=%d delay_done=%d "
        "tap=%d in_frame_now=%d vsync_now=%d"
        % (lane, rst_out, sync_wait, delay_done, tap, in_frame_last, vsync_last))

    add("")
    add("=== Q2 I2C: did configuration succeed? ===")
    if cfg_done and nack_inc == 0 and xclr_n:
        q2 = "YES - cfg_done seen, no NACK growth, sensor out of reset"
    elif not cfg_done:
        q2 = "NO - cfg_done never asserted (table/timing/address/power)"
    elif nack_inc > 0:
        q2 = "PARTIAL/NO - cfg_done seen but NACK count grew"
    elif not xclr_n:
        q2 = "NO - sensor held in reset (xclr_n = 0)"
    else:
        q2 = "UNRESOLVED"
    add("answer           : " + q2)
    add("evidence         : cfg_done=%d bus_err_lat=%d xclr_n=%d pll_locked=%d "
        "cfg_rst_n=%d lane_sticky=0x%X cam_nack_cnt_delta=%d cam_nack_cnt_last=%d"
        % (cfg_done, bus_err, xclr_n, pll_lock, cfg_rst_n, lane, nack_inc, last[14]))

    add("")
    add("=== Q3 crop: did it receive a frame? ===")
    if roi > 0:
        q3 = "YES - complete ROI frames captured (crop_roi_frames delta > 0)"
    elif short > 0:
        q3 = "PARTIAL - frames ended before the ROI completed (crop_short)"
    elif geom > 0:
        q3 = "PARTIAL - line group count mismatched (crop_geom_err)"
    elif groups == 0:
        q3 = "NO - crop never saw a valid beat (crop_groups = 0)"
    else:
        q3 = "UNRESOLVED"
    add("answer           : " + q3)
    add("evidence         : crop_roi_frames=%d crop_groups=%d crop_short=%d "
        "crop_geom_err=%d cam_last_frame_cycles=%d"
        % (roi, groups, short, geom, d["cam_last_frame_cycles"]))
    add("legacy cross-chk : cap_frames=%d raw_pub=%d enc_frames=%d exported=%d "
        "raw_drop=%d cmp_drop=%d errors=%d read_words=%d"
        % tuple(d[n] for n in LEGACY))

    txt = "\n".join(lines) + "\n"
    pathlib.Path(args.out).write_text(txt)
    print(txt)

    if bad_xor or bad_hdr:
        return 3
    if len(packets) < args.min_packets:
        print("FAIL: packets %d < min %d" % (len(packets), args.min_packets))
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
