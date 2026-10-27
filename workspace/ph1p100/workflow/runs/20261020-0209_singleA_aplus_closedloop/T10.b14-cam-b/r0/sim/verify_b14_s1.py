#!/usr/bin/env python3
"""verify_b14_s1.py -- S1 exact B-geometry counters and v5 selected-camera map.

Reads the S1 case directory produced by tb_b14_chain (b14 changed-src) and
asserts the exact B numbers frozen in the dev-plan:

  pix_beats=2,117,472  line_rises=2,192  frame_rises=1  frame_falls=1
  crop_roi_frames=1    crop_groups=518,400  raw_len=2,592,000
  v5 field #13 bit20 = 1 (cam_sel = B) and bits 19:0 as packed by the RTL

The frame itself (44 B header + four CRCs + strict zlib + independent
reference) is already asserted by check_b14.py; this script only adds the
selected-camera / geometry evidence that check_b14 does not decode.
"""
import json
import pathlib
import struct
import sys

ST_LEN, ST_VER, ST_FIELDS = 241, 5, 59
EXPECT = {
    "cam_pix_beats": 2117472,
    "cam_line_rises": 2192,
    "cam_frame_rises": 1,
    "cam_frame_falls": 1,
    "crop_roi_frames": 1,
    "crop_groups": 518400,
    "crop_short": 0,
    "crop_geom_err": 0,
    "cam_nack_cnt": 0,
    "cam_sysstat": 0x00100000,
}


def main(case):
    case = pathlib.Path(case)
    errors, checks = [], {}

    def req(name, got, want):
        checks[name] = got
        if got != want:
            errors.append("%s=%r expected %r" % (name, got, want))

    stats = {}
    for tok in (case / "stats.txt").read_text().split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            try:
                stats[k] = int(v)
            except ValueError:
                pass
    req("stats_crop_beats", stats.get("crop_beats"), 518400)
    req("stats_crop_sofs", stats.get("crop_sofs"), 1)
    req("stats_crop_lasts", stats.get("crop_lasts"), 1)
    req("stats_source_frames", stats.get("source_frames"), 1)
    req("stats_cap", stats.get("cap"), 1)
    req("stats_enc", stats.get("enc"), 1)
    req("stats_exported", stats.get("exported"), 1)
    req("stats_raw_drop", stats.get("raw_drop"), 0)
    req("stats_dup_words", stats.get("dup_words"), 0)
    req("stats_fifo_reject", stats.get("fifo_reject"), 0)

    txt = (case / "capture.dec").read_text().split()
    data = bytes(map(int, txt))
    statuses = []
    off = 0
    while off + ST_LEN <= len(data):
        if data[off:off + 2] == b"\xa5\x5a" and data[off + 2] == ST_LEN and data[off + 3] == ST_VER:
            p = data[off:off + ST_LEN]
            x = 0
            for b in p[:-1]:
                x ^= b
            if x == p[-1]:
                statuses.append(struct.unpack("<%dI" % ST_FIELDS, p[4:4 + 4 * ST_FIELDS]))
                off += ST_LEN
                continue
        off += 1
    req("v5_status_packets", len(statuses) >= 1, True)
    if statuses:
        v = statuses[-1]
        req("v5_pix_beats", v[11], EXPECT["cam_pix_beats"])
        req("v5_line_rises", v[12], EXPECT["cam_line_rises"])
        req("v5_frame_rises", v[13], EXPECT["cam_frame_rises"])
        req("v5_frame_falls", v[14], EXPECT["cam_frame_falls"])
        req("v5_crop_roi_frames", v[16], EXPECT["crop_roi_frames"])
        req("v5_crop_groups", v[17], EXPECT["crop_groups"])
        req("v5_crop_short", v[18], EXPECT["crop_short"])
        req("v5_crop_geom_err", v[19], EXPECT["crop_geom_err"])
        req("v5_cam_sysstat", v[21], EXPECT["cam_sysstat"])
        req("v5_cam_sysstat_bit20", (v[21] >> 20) & 1, 1)
        req("v5_cam_nack_cnt", v[22], EXPECT["cam_nack_cnt"])
        req("v5_last_frame_cycles_nonzero", v[15] > 0, True)
        req("v5_clk_tgl_sim_unused", v[8], 0)
        req("v5_pkt_tgl_sim_unused", v[9], 0)
        req("v5_vs_tgl_sim_unused", v[10], 0)

    res = dict(status="PASS" if not errors else "FAIL", errors=errors,
               checks=checks, limitations=[
                   "simulation only; no board/STA claim",
                   "i_dbg_clk_tgl/pkt_tgl/vs_tgl are constant 0 in this synthetic TB "
                   "(the B tap counters are exercised, not the PHY toggles)"])
    (case / "s1_verify.json").write_text(json.dumps(res, indent=2))
    print(json.dumps(res, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1]))
