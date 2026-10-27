#!/usr/bin/env python3
"""parse_status_v4.py -- T10.b11 status packet v4 parser.

Wire format (little endian):
    0      A5
    1      5A
    2      E1     LEN = 225
    3      04     VER = 4
    4..223 55 x u32 little-endian, field 1 at byte 4
    224    XOR8 of bytes 0..223

Fields 1..43 are bit-identical to the v3 packet (same sources, same order), so
a v3 capture can be compared field by field with this parser as well.  Fields
44..55 are new in v4.

Usage:
    python parse_status_v4.py <capture.bin> [--json out.json] [--dump]

The script never edits the capture; it only reads.
"""
import json
import sys

PKT_LEN = 225
MAGIC = b"\xA5\x5A\xE1\x04"

NAMES = [
    # 1..8 legacy
    "cap_frames", "raw_pub", "enc_frames", "exported",
    "raw_drop", "cmp_drop", "errors", "read_words",
    # 9..23 camera front end
    "cam_clk_tgl_inc", "cam_pkt_tgl_inc", "cam_vs_tgl_inc", "cam_pix_beats",
    "cam_line_rises", "cam_frame_rises", "cam_frame_falls",
    "cam_last_frame_cycles", "crop_roi_frames", "crop_groups",
    "crop_short", "crop_geom_err", "cam_phystat", "cam_sysstat",
    "cam_nack_cnt",
    # 24..43 raw store / read path
    "raw_begin_ok", "raw_begin_deny", "raw_wr_beats", "raw_wr_words",
    "raw_wr_ptr", "raw_wr_state", "raw_rd_state", "raw_slot_st",
    "raw_slot_len0", "raw_slot_len1", "raw_rd_idx", "raw_rd_words",
    "raw_ar_valid", "raw_ar_hs", "raw_rv_cnt", "raw_rd_open_ok",
    "raw_rd_close", "raw_abort_cnt", "raw_deny_nofree", "raw_deny_ddr",
    # 44..55 v4 read-path / A+ observability
    "br0", "ar_cnt", "ar_block_cnt", "r_cnt", "rlast_cnt", "stale_r_cnt",
    "rd_wait_cycles", "core0", "frame0", "src0", "exp0", "fwait_cycles",
]

RD_STATE = ["R_IDLE", "R_AR", "R_RW", "R_HOLD"]
ISTATE = ["I_IDLE", "I_EXP", "I_DONE", "I_ABORT", "I_DEAD"]
DSTATE = ["D_IDLE", "D_GATH", "D_EMIT", "D_FIN"]
ESTATE = ["E_IDLE", "E_OPEN", "E_HDR", "E_PAY"]
PSTATE = ["P_HDR", "P_PAY", "P_DONE"]
SLOT = ["FREE", "WRITE", "READY", "READING"]


def parse(path):
    data = open(path, "rb").read()
    pkts, skipped = [], 0
    i = 0
    while i + PKT_LEN <= len(data):
        if data[i:i + 4] != MAGIC:
            i += 1
            skipped += 1
            continue
        p = data[i:i + PKT_LEN]
        xor = 0
        for b in p[:224]:
            xor ^= b
        ok = (xor == p[224])
        f = [int.from_bytes(p[4 + 4 * k:8 + 4 * k], "little") for k in range(55)]
        pkts.append({"off": i, "xor_ok": ok, "xor": xor, "xor_wire": p[224], "f": f})
        i += PKT_LEN
    return data, pkts, skipped


def bits(v, hi, lo):
    return (v >> lo) & ((1 << (hi - lo + 1)) - 1)


def decode(idx, f):
    """Human readable decode of the v4-only structural fields."""
    out = []
    if idx == 44:
        v = f[43]
        out.append("  br0        : ddr_rdy=%d ar_pending=%d af_rvalid=%d af_wready=%d "
                   "rf_rvalid=%d rf_wready=%d s_rvalid=%d s_rready=%d wstate=%d "
                   "aw_seen=%d w_seen=%d wf_rvalid=%d wf_pop=%d"
                   % tuple(bits(v, b, b) for b in range(13)))
    elif idx == 50:
        out.append("  rd_wait    : %d clk_a1 cycles (saturated = dead read response)"
                   % f[49])
    elif idx == 51:
        v = f[50]
        out.append("  core0      : state=%d in_ready=%d in_valid=%d out_valid=%d "
                   "out_ready=%d busy=%d done=%d"
                   % (bits(v, 4, 0), bits(v, 5, 5), bits(v, 6, 6), bits(v, 7, 7),
                      bits(v, 8, 8), bits(v, 9, 9), bits(v, 10, 10)))
    elif idx == 52:
        v = f[51]
        ist = bits(v, 4, 2)
        dst = bits(v, 1, 0)
        out.append("  frame0     : dstate=%s istate=%s frame_active=%d wr_bank=%d "
                   "rd_bank=%d cooldown=%d core_in_ready=%d eidx=%d first_byte=%d"
                   % (DSTATE[dst] if dst < 4 else str(dst),
                      ISTATE[ist] if ist < 5 else str(ist),
                      bits(v, 5, 5), bits(v, 6, 6), bits(v, 7, 7), bits(v, 8, 8),
                      bits(v, 9, 9), bits(v, 12, 10), bits(v, 13, 13)))
    elif idx == 53:
        v = f[52]
        out.append("  src0       : src_ready=%d din_valid=%d bank_busy0=%d bank_busy1=%d"
                   % (bits(v, 0, 0), bits(v, 1, 1), bits(v, 2, 2), bits(v, 3, 3)))
    elif idx == 54:
        v = f[53]
        es = bits(v, 1, 0)
        ps = bits(v, 3, 2)
        out.append("  exp0       : estate=%s pstate=%s dq_cnt=%d wbuf_valid=%d "
                   "cmp_open_ready=%d cmp_rd_valid=%d cmp_rd_take=%d status_due=%d "
                   "sstate=%d cmp_open=%d"
                   % (ESTATE[es] if es < 4 else str(es),
                      PSTATE[ps] if ps < 3 else str(ps),
                      bits(v, 5, 4), bits(v, 6, 6), bits(v, 7, 7), bits(v, 8, 8),
                      bits(v, 9, 9), bits(v, 10, 10), bits(v, 11, 11),
                      bits(v, 12, 12)))
    return out


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    as_json = None
    dump = "--dump" in sys.argv
    if "--json" in sys.argv:
        as_json = sys.argv[sys.argv.index("--json") + 1]

    data, pkts, skipped = parse(path)
    print("T10.b11 status packet v4 parse")
    print("input            :", path)
    print("bytes            :", len(data))
    print("packet size      :", PKT_LEN)
    print("packets          :", len(pkts))
    print("bad_xor          :", sum(0 if p["xor_ok"] else 1 for p in pkts))
    print("skipped_bytes    :", skipped)
    if not pkts:
        print("VERDICT          : NO_V4_PACKET")
        return 1

    f0, fl = pkts[0]["f"], pkts[-1]["f"]
    print()
    print("%-3s %-20s %12s %12s %12s" % ("#", "field", "first", "last", "delta"))
    for k in range(55):
        d = (fl[k] - f0[k]) & 0xFFFFFFFF
        print("%-3d %-20s %12d %12d %12d" % (k + 1, NAMES[k], f0[k], fl[k], d))

    print()
    print("last packet, v3-compatible decodes")
    v = fl[29]
    print("  raw_rd_state: rd_state=%s rd_armed=%d rd_sel=%d rd_valid=%d skip=%d "
          "skid=%d fifo=%d/%d raw_active=%d a1_busy=%d out_valid=%d "
          "cmp_begin_ready=%d fstate=%d in_valid=%d in_ready=%d out_last=%d "
          "cmp_begin=%d cmp_abort=%d"
          % (RD_STATE[bits(v, 1, 0)], bits(v, 2, 2), bits(v, 3, 3), bits(v, 4, 4),
             bits(v, 7, 7), bits(v, 8, 8), bits(v, 9, 9), bits(v, 10, 10),
             bits(v, 11, 11), bits(v, 12, 12), bits(v, 13, 13), bits(v, 14, 14),
             bits(v, 16, 15), bits(v, 17, 17), bits(v, 18, 18), bits(v, 19, 19),
             bits(v, 20, 20), bits(v, 21, 21)))
    sv = fl[30]
    print("  raw_slot_st : slot0=%s slot1=%s seq0=%d seq1=%d"
          % (SLOT[bits(sv, 1, 0)], SLOT[bits(sv, 3, 2)],
             bits(sv, 4, 4), bits(sv, 5, 5)))
    print()
    print("last packet, v4 fields")
    for k in range(44, 56):
        print("  #%d %-14s = 0x%08X (%d)" % (k, NAMES[k - 1], fl[k - 1], fl[k - 1]))
        for line in decode(k, fl):
            print(line)

    # ---------------------------------------------------------- verdict chain
    print()
    print("=== 1176/1177 read-path verdict chain (last packet) ===")
    ar_hs = fl[36]
    paxi_ar = fl[44]
    block = fl[45]
    r_cnt = fl[46]
    rlast = fl[47]
    stale = fl[48]
    rd_wait = fl[49]
    br0 = fl[43]
    af_rv = bits(br0, 2, 2)
    ar_pend = bits(br0, 1, 1)
    ddr_rdy = bits(br0, 0, 0)
    rf_rv = bits(br0, 4, 4)
    s_rv = bits(br0, 6, 6)

    print("1 store AR handshakes (address into AF)      : %d" % ar_hs)
    print("2 PAXI AR handshakes (address to DDR)        : %d" % paxi_ar)
    print("3 PAXI R handshakes / rlast / stale          : %d / %d / %d"
          % (r_cnt, rlast, stale))
    print("4 leftovers: af_rvalid=%d ar_pending=%d ddr_rdy=%d rf_rvalid=%d s_rvalid=%d"
          % (af_rv, ar_pend, ddr_rdy, rf_rv, s_rv))
    print("5 store rd_wait_cycles (saturated = armed)   : %d" % rd_wait)
    exit_code = 0
    block_delta = (fl[45] - f0[45]) & 0xFFFFFFFF
    if af_rv and (not ar_pend) and (paxi_ar < ar_hs) and (block_delta > 0):
        print("VERDICT: AR_STUCK_IN_AF -- the %dth address never reached the PAXI "
              "(ddr_rdy=%d, ar_block_cnt=%d, delta=%d)"
              % (paxi_ar + 1, ddr_rdy, block, block_delta))
        exit_code = 3
    elif paxi_ar >= ar_hs and (r_cnt < paxi_ar):
        print("VERDICT: NO_R_FROM_DDR -- the DDR accepted the AR but never returned "
              "the beat (H4: DDR/PAXI side, outside the A1 RTL)")
        exit_code = 4
    elif stale > 0 and r_cnt == paxi_ar:
        print("VERDICT: STALE_R_SEEN -- %d unsolicited beats were swallowed "
              "(harmless if ar_cnt == r_cnt)" % stale)
    elif paxi_ar == r_cnt == rlast == ar_hs:
        print("VERDICT: READ_PATH_BALANCED -- every AR was answered 1:1")
    else:
        print("VERDICT: INCONCLUSIVE -- inspect fields 44..50 above")
        exit_code = 5
    print("(note: fields 44..49 are a clk_a1 snapshot refreshed every 256 clk_ddr "
          "cycles, so they can lag the newest %d-AR state)" % 256)

    if as_json:
        out = {
            "input": path, "bytes": len(data), "packets": len(pkts),
            "bad_xor": sum(0 if p["xor_ok"] else 1 for p in pkts),
            "skipped": skipped,
            "names": NAMES,
            "first": f0, "last": fl,
            "delta": [(fl[k] - f0[k]) & 0xFFFFFFFF for k in range(55)],
            "verdict_chain": {
                "ar_hs_store": ar_hs, "ar_hs_paxi": paxi_ar,
                "ar_block_cnt": block, "r_cnt": r_cnt, "rlast_cnt": rlast,
                "stale_r_cnt": stale, "rd_wait_cycles": rd_wait,
                "br0": br0, "ddr_rdy": ddr_rdy, "ar_pending": ar_pend,
                "af_rvalid": af_rv,
            },
            "verdict_exit": exit_code,
        }
        with open(as_json, "w", encoding="utf-8") as fh:
            json.dump(out, fh, indent=2)
        print("json             :", as_json)
    if dump:
        for p in pkts:
            print(p["off"], "xor_ok=%d" % p["xor_ok"], " ".join("%08X" % x for x in p["f"]))
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
