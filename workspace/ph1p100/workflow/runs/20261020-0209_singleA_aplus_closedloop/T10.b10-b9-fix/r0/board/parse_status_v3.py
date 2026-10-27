#!/usr/bin/env python3
"""parse_status_v3.py -- T10.b9 r0 raw-store status packet v3 parser.

Wire format (little endian, 1 Hz while the A1 exporter is idle):

    off  len  field
    0    1    0xA5
    1    1    0x5A
    2    1    LEN = 0xB1 (177)
    3    1    VER = 0x03
    4    172  43 x u32, all latched on ONE clk_a1 edge:
              #1..#23  identical to v2 (8 legacy + 15 camera fields)
              #24..#43 raw-store / read-path fields (see FIELDS)
    176  1    XOR8 over bytes 0..175

Input is the raw .bin capture, the one-decimal-byte-per-line .dec text, or the
ModelSim byte dump.  Counter handling is identical to the v2 parser: wrapping
32-bit deltas plus the first/last/OR values for level fields.
"""

import argparse
import json
import pathlib
import sys

MAGIC = b"\xA5\x5A"
LEN = 177
VER = 3
PKT = 177

LEGACY = ["cap_frames", "raw_pub", "enc_frames", "exported",
          "raw_drop", "cmp_drop", "errors", "read_words"]

CAM = ["cam_clk_tgl_inc", "cam_pkt_tgl_inc", "cam_vs_tgl_inc", "cam_pix_beats",
       "cam_line_rises", "cam_frame_rises", "cam_frame_falls",
       "cam_last_frame_cycles", "crop_roi_frames", "crop_groups", "crop_short",
       "crop_geom_err", "cam_phystat", "cam_sysstat", "cam_nack_cnt"]

RAW = ["raw_begin_ok", "raw_begin_deny", "raw_wr_beats", "raw_wr_words",
       "raw_wr_ptr", "raw_wr_state", "raw_rd_state", "raw_slot_st",
       "raw_slot_len0", "raw_slot_len1", "raw_rd_idx", "raw_rd_words",
       "raw_ar_valid", "raw_ar_hs", "raw_rv_cnt", "raw_rd_open_ok",
       "raw_rd_close", "raw_abort_cnt", "raw_deny_nofree", "raw_deny_ddr"]

FIELDS = LEGACY + CAM + RAW
assert len(FIELDS) == 43

LEVEL = {"cam_phystat", "cam_sysstat", "cam_nack_cnt",
         "raw_wr_ptr", "raw_wr_state", "raw_rd_state", "raw_slot_st",
         "raw_slot_len0", "raw_slot_len1", "raw_rd_idx", "raw_rd_words"}

PHYS_BITS = [("delay_tap", 0, 5), ("delay_done", 6, 6), ("rst_out", 7, 7),
             ("sync_wait", 8, 8), ("in_frame_now", 9, 9), ("vsync_now", 10, 10)]

SYS_BITS = [("cfg_done", 0, 0), ("bus_err_lat", 1, 1), ("xclr_n", 2, 2),
            ("pll_locked", 3, 3), ("cfg_rst_n", 4, 4), ("lane_sticky", 8, 11)]

# raw_rd_state bit map (design guide section 5, field 30)
RD_BITS = [("rd_state", 0, 1), ("rd_armed", 2, 2), ("rd_sel", 3, 3),
           ("rd_valid", 4, 4), ("raw_rd_open", 5, 5),
           ("raw_rd_open_ready", 6, 6), ("skip_frame", 7, 7),
           ("skid_valid", 8, 8), ("fifo_valid", 9, 9), ("fifo_ready", 10, 10),
           ("raw_active", 11, 11), ("a1_busy", 12, 12),
           ("a1_out_valid", 13, 13), ("cmp_begin_ready", 14, 14),
           ("fstate", 15, 16), ("a1_in_valid", 17, 17),
           ("a1_in_ready", 18, 18), ("a1_out_last", 19, 19),
           ("cmp_begin", 20, 20), ("cmp_abort", 21, 21)]

RD_STATE_NAME = {0: "R_IDLE", 1: "R_AR", 2: "R_RW", 3: "R_HOLD"}
SLOT_ST_NAME = {0: "FREE", 1: "WRITE", 2: "READY", 3: "READING"}
FSTATE_NAME = {0: "F_IDLE", 1: "F_WAIT", 2: "F_FEED", 3: "F_END"}


def load_bytes(path):
    p = pathlib.Path(path)
    raw = p.read_bytes()
    if raw[:1] == b"\xa5" and len(raw) >= PKT:
        return raw
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
        for b in pkt[:176]:
            x ^= b
        if x != pkt[176]:
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


def deltas(packets):
    d, first = {}, packets[0]
    for k, name in enumerate(FIELDS):
        tot, prev = 0, first[k]
        for p in packets[1:]:
            tot += wrap_delta(p[k], prev)
            prev = p[k]
        d[name] = tot
    return d


def bitfield(val, lo, hi):
    return (val >> lo) & ((1 << (hi - lo + 1)) - 1)


def verdict(d, packets, last):
    """Four-way board verdict (design guide section 4)."""
    rd_state_or = 0
    for p in packets:
        rd_state_or |= p[FIELDS.index("raw_rd_state")] & 3
    ar_valid = d["raw_ar_valid"]
    ar_hs = d["raw_ar_hs"]
    rv = d["raw_rv_cnt"]
    open_ok = d["raw_rd_open_ok"]
    wr_begin_ok = d["raw_begin_ok"]
    wr_beats = d["raw_wr_beats"]
    pub = d["raw_pub"]

    if pub > 0 and rv > 0:
        tag = "PASS-READ"
        text = ("raw store writes, publishes and the A+ read path returns data "
                "(raw_pub=%d, rv_cnt=%d)" % (pub, rv))
    elif open_ok > 0 and ar_valid > 0 and rv == 0 and ar_hs == 0:
        tag = "B"
        text = ("read opened and the AR was offered but never handshaked "
                "(open_ok=%d, ar_valid=%d, ar_hs=0) -> rd_state=%s"
                % (open_ok, ar_valid, RD_STATE_NAME.get(last[FIELDS.index("raw_rd_state")] & 3, "?")))
    elif open_ok > 0 and ar_valid > 0 and rv == 0:
        tag = "A"
        text = ("read opened and AR handshaked but no read data came back "
                "(open_ok=%d, ar_valid=%d, ar_hs=%d, rv_cnt=0) -> rd_state=%s"
                % (open_ok, ar_valid, ar_hs,
                   RD_STATE_NAME.get(last[FIELDS.index("raw_rd_state")] & 3, "?")))
    elif open_ok == 0:
        tag = "C"
        text = ("read never opened (rd_open_ok=0, rd_state=%s); write side: "
                "begin_ok=%d, wr_beats=%d, raw_pub=%d"
                % (RD_STATE_NAME.get(last[FIELDS.index("raw_rd_state")] & 3, "?"),
                   wr_begin_ok, wr_beats, pub))
    elif wr_begin_ok == 0 or wr_beats == 0:
        tag = "D"
        text = ("write side never started (begin_ok=%d, deny=%d, wr_beats=%d)"
                % (wr_begin_ok, d["raw_begin_deny"], wr_beats))
    else:
        tag = "UNRESOLVED"
        text = ("no rule matched: pub=%d open_ok=%d ar_valid=%d ar_hs=%d rv=%d "
                "begin_ok=%d wr_beats=%d" % (pub, open_ok, ar_valid, ar_hs, rv,
                                             wr_begin_ok, wr_beats))
    return tag, text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--out", dest="out", default="")
    ap.add_argument("--json", dest="js", default="")
    ap.add_argument("--min-packets", type=int, default=0)
    args = ap.parse_args()

    data = load_bytes(args.inp)
    packets, bad_xor, bad_hdr, skipped = parse(data)

    lines = []
    add = lines.append
    add("T10.b9 status packet v3 parse")
    add("input            : %s" % args.inp)
    add("bytes            : %d" % len(data))
    add("packet size      : %d" % PKT)
    add("packets          : %d" % len(packets))
    add("bad_xor          : %d" % bad_xor)
    add("bad_len_ver      : %d" % bad_hdr)
    add("skipped_bytes    : %d" % skipped)
    add("")

    if not packets:
        add("NO_PACKETS")
        txt = "\n".join(lines) + "\n"
        if args.out:
            pathlib.Path(args.out).write_text(txt)
        print(txt)
        return 2

    first, last = packets[0], packets[-1]
    d = deltas(packets)
    add("%-20s %14s %14s %14s" % ("field", "first", "last", "delta_wrap"))
    for k, name in enumerate(FIELDS):
        add("%-20s %14d %14d %14d" % (name, first[k], last[k], d[name]))

    add("")
    add("raw_wr_state last : 0x%08X" % last[FIELDS.index("raw_wr_state")])
    wrs = last[FIELDS.index("raw_wr_state")]
    add("  wr_active=%d wr_slot=%d wcnt=%d nbytes=%d"
        % (bitfield(wrs, 31, 31), bitfield(wrs, 30, 30), bitfield(wrs, 27, 29),
           bitfield(wrs, 0, 26)))
    add("raw_rd_state last : 0x%08X" % last[FIELDS.index("raw_rd_state")])
    for name, lo, hi in RD_BITS:
        v = bitfield(last[FIELDS.index("raw_rd_state")], lo, hi)
        if name == "rd_state":
            add("  %-18s = %d (%s)" % (name, v, RD_STATE_NAME.get(v, "?")))
        elif name == "fstate":
            add("  %-18s = %d (%s)" % (name, v, FSTATE_NAME.get(v, "?")))
        else:
            add("  %-18s = %d" % (name, v))
    ss = last[FIELDS.index("raw_slot_st")]
    add("raw_slot_st last  : 0x%08X" % ss)
    add("  slot0=%s slot1=%s seq0=%d seq1=%d"
        % (SLOT_ST_NAME.get(bitfield(ss, 0, 1), "?"),
           SLOT_ST_NAME.get(bitfield(ss, 2, 3), "?"),
           bitfield(ss, 4, 4), bitfield(ss, 5, 5)))
    add("slot bytes        : slot0=%d slot1=%d"
        % (last[FIELDS.index("raw_slot_len0")], last[FIELDS.index("raw_slot_len1")]))
    add("raw store write   : begin_ok_delta=%d deny_delta=%d (nofree=%d ddr=%d)"
        % (d["raw_begin_ok"], d["raw_begin_deny"], d["raw_deny_nofree"],
           d["raw_deny_ddr"]))
    add("raw store words   : wr_beats_delta=%d wr_words_delta=%d read_words_delta=%d"
        % (d["raw_wr_beats"], d["raw_wr_words"], d["read_words"]))
    add("raw read path     : open_ok=%d close=%d ar_valid=%d ar_hs=%d rv_cnt=%d dup?=%d"
        % (d["raw_rd_open_ok"], d["raw_rd_close"], d["raw_ar_valid"],
           d["raw_ar_hs"], d["raw_rv_cnt"], d["read_words"] - d["raw_rd_open_ok"]))
    add("abort / drop      : abort_cnt=%d raw_drop_delta=%d cmp_drop_delta=%d"
        % (d["raw_abort_cnt"], d["raw_drop"], d["cmp_drop"]))
    add("targets           : raw_pub=%d enc_frames=%d exported=%d"
        % (d["raw_pub"], d["enc_frames"], d["exported"]))

    tag, text = verdict(d, packets, last)
    add("")
    add("=== raw store verdict ===")
    add("verdict          : %s" % tag)
    add("answer           : " + text)
    add("where it stops   : rd_state=%s / fstate=%s / raw_active=%d / a1_busy=%d / "
        "a1_out_valid=%d / raw_rd_open_ready=%d / cmp_begin_ready=%d / fifo_valid=%d"
        % (RD_STATE_NAME.get(bitfield(last[FIELDS.index("raw_rd_state")], 0, 1), "?"),
           FSTATE_NAME.get(bitfield(last[FIELDS.index("raw_rd_state")], 15, 16), "?"),
           bitfield(last[FIELDS.index("raw_rd_state")], 11, 11),
           bitfield(last[FIELDS.index("raw_rd_state")], 12, 12),
           bitfield(last[FIELDS.index("raw_rd_state")], 13, 13),
           bitfield(last[FIELDS.index("raw_rd_state")], 6, 6),
           bitfield(last[FIELDS.index("raw_rd_state")], 14, 14),
           bitfield(last[FIELDS.index("raw_rd_state")], 9, 9)))

    add("")
    add("=== v2-compatible fields (regression check) ===")
    add("cap_frames=%d crop_roi_frames=%d crop_groups=%d crop_short=%d crop_geom_err=%d"
        % (d["cap_frames"], d["crop_roi_frames"], d["crop_groups"],
           d["crop_short"], d["crop_geom_err"]))
    add("cam_pix_beats=%d cam_line_rises=%d cam_frame_rises=%d cam_frame_falls=%d"
        % (d["cam_pix_beats"], d["cam_line_rises"], d["cam_frame_rises"],
           d["cam_frame_falls"]))

    txt = "\n".join(lines) + "\n"
    if args.out:
        pathlib.Path(args.out).write_text(txt)
    print(txt)

    if args.js:
        js = {"packets": len(packets), "bad_xor": bad_xor, "bad_hdr": bad_hdr,
              "skipped": skipped, "delta": d, "first": first, "last": last,
              "fields": FIELDS, "verdict": tag, "answer": text}
        pathlib.Path(args.js).write_text(json.dumps(js, indent=2))

    if bad_xor or bad_hdr:
        return 3
    if len(packets) < args.min_packets:
        print("FAIL: packets %d < min %d" % (len(packets), args.min_packets))
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
