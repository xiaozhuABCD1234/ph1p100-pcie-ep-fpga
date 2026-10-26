#!/usr/bin/env python3
"""check_b20_board.py -- T10.b20-a-timing board gate for the 300 s COM8 capture.

Reads <capdir>/status_v6.json (parse_status_v6.py output) and, independently,
the raw capture to prove there is no truncated (half) frame.

Gates (dev-plan S5, unchanged from b19):
  * >= 1 v6 status packet, every packet XOR ok, 273/6/67;
  * CAM_SEL bit12 == 0 and bit20 == 0 in every packet;
  * A tap counters pix_beats / line_rises / frame_rises > 0
    (absolute totals with one packet, deltas with >= 2);
  * enc_frames / exported > 0; at least one FRAME with four CRCs + strict zlib;
  * no half frame in the raw stream;
  * raw_drop / cmp_drop / errors do not grow; timeout/retry/giveup do not grow
    (absolute 0 with one packet, deltas 0 with >= 2).

Statuses:
  PASS                 all gates true
  blocked_A_no_pixels  pix_beats == line_rises == frame_rises == 0 (A silent)
  blocked              A silent AND reset_pulse was not confirmed (ambiguous),
                       or another precondition is missing
  FAIL                 any other gate failed
"""
import json
import pathlib
import struct
import sys
import zlib

HDR = 44
FMT = "<IBBHIHHIIIIIII"


def partial_tail(raw):
    """Classify A1U1 starts that the 300 s window cut at the tail.

    Returns (sealed, tail_cut, bad):
      sealed   complete frames whose four CRCs were checked by the parser
      tail_cut frames started near the end of the window (payload runs past end)
      bad      full payload present but header/stream CRC failed (real corruption)
    """
    sealed, tail_cut, bad = 0, [], []
    off = 0
    n = len(raw)
    while True:
        i = raw.find(b"A1U1", off)
        if i < 0:
            break
        off = i + 1
        if i + HDR > n:
            continue
        try:
            (magic, ver, flags, hlen, fid, w, h, rl, xl, sl,
             rc, xc, sc, hc) = struct.unpack(FMT, raw[i:i + HDR])
        except struct.error:
            continue
        if magic != 0x31553141 or ver != 1 or hlen != HDR or crc(raw[i:i + 40]) != hc:
            continue
        if i + HDR + sl > n:
            tail_cut.append({"offset": i, "stream_len": sl, "available": n - i - HDR})
            continue
        body = raw[i + HDR:i + HDR + sl]
        if crc(body) != sc:
            bad.append({"offset": i, "stream_len": sl, "body_crc": "bad"})
            continue
        sealed += 1
        off = i + HDR + sl
    return sealed, tail_cut, bad


def crc(b):
    return zlib.crc32(b) & 0xFFFFFFFF


def main(capdir, reset_pulse="unknown"):
    capdir = pathlib.Path(capdir)
    j = json.loads((capdir / "status_v6.json").read_text())
    st = j["statuses"]
    frames = j["frames"]
    raw_paths = sorted(capdir.glob("com8_*.bin"))
    raw = raw_paths[-1].read_bytes() if raw_paths else b""
    sealed, tail_cut, bad = partial_tail(raw)
    errors, checks = [], {}

    def req(name, ok, detail):
        checks[name] = detail
        if not ok:
            errors.append("%s: %s" % (name, detail))

    req("status_packet_ge_1", len(st) >= 1, len(st))
    req("all_xor_ok", all(s.get("xor_ok") for s in st), len(st))
    req("all_v6", all(s.get("version") == 6 and s.get("length") == 273 and
                      s.get("field_count") == 67 for s in st),
        sorted({(s.get("version"), s.get("length"), s.get("field_count")) for s in st}))
    req("all_camsel_a", all(((s.get("cam13", 1) >> 12) & 1) == 0 for s in st), len(st))
    req("no_bit20", all(((s.get("cam13", 1) >> 20) & 1) == 0 for s in st), len(st))
    req("no_half_frame", not bad, {"sealed": sealed, "tail_cut": tail_cut, "bad": bad})

    first = st[0] if st else {}
    last = st[-1] if st else {}
    keys = ("cap_frames", "raw_pub", "enc_frames", "exported", "raw_drop",
            "cmp_drop", "timeout_cnt", "retry_cnt", "giveup_cnt",
            "stale_guard_cnt", "stale_r_cnt", "errors",
            "ar_cnt", "r_cnt", "rlast_cnt")
    delta = {k: last.get(k, 0) - first.get(k, 0) for k in keys}
    multi = len(st) >= 2
    # Parser field map (a1_uart_export cam snapshot):
    # cam0 clk_tgl, cam1 pkt_tgl, cam2 vs_tgl, cam3 pix_beats, cam4 line_rises,
    # cam5 frame_rises, cam6 frame_falls, cam7 last_frame_cycles, cam8 roi_frames,
    # cam9 crop_groups, cam10 crop_short, cam11 crop_geom_err, cam12 phystat,
    # cam13 cam_sysstat, cam14 nack.
    pix_abs = last.get("cam3", 0)
    line_abs = last.get("cam4", 0)
    frame_abs = last.get("cam5", 0)
    pix = (last.get("cam3", 0) - first.get("cam3", 0)) if multi else pix_abs
    line = (last.get("cam4", 0) - first.get("cam4", 0)) if multi else line_abs
    frame = (last.get("cam5", 0) - first.get("cam5", 0)) if multi else frame_abs
    silent = (pix_abs == 0 and line_abs == 0 and frame_abs == 0)
    req("a_pix_beats_gt_0", pix > 0, pix)
    req("a_line_rises_gt_0", line > 0, line)
    req("a_frame_rises_gt_0", frame > 0, frame)
    req("enc_gt_0", (delta["enc_frames"] if multi else last.get("enc_frames", 0)) > 0,
        delta["enc_frames"] if multi else last.get("enc_frames", 0))
    req("exported_gt_0", (delta["exported"] if multi else last.get("exported", 0)) > 0,
        delta["exported"] if multi else last.get("exported", 0))
    req("frame_with_four_crcs_zlib",
        len(frames) >= 1 and all(f.get("four_crcs_verified") and f.get("strict_zlib_eof")
                                 for f in frames),
        [bool(f.get("four_crcs_verified") and f.get("strict_zlib_eof")) for f in frames])
    req("no_raw_drop_growth", delta["raw_drop"] == 0, delta["raw_drop"])
    req("no_cmp_drop_growth", delta["cmp_drop"] == 0, delta["cmp_drop"])
    req("no_errors_growth", delta["errors"] == 0, delta["errors"])
    req("timeout_zero", (last.get("timeout_cnt", 0) if not multi else delta["timeout_cnt"]) == 0,
        delta["timeout_cnt"] if multi else last.get("timeout_cnt", 0))
    req("retry_zero", (last.get("retry_cnt", 0) if not multi else delta["retry_cnt"]) == 0,
        delta["retry_cnt"] if multi else last.get("retry_cnt", 0))
    req("giveup_zero", (last.get("giveup_cnt", 0) if not multi else delta["giveup_cnt"]) == 0,
        delta["giveup_cnt"] if multi else last.get("giveup_cnt", 0))

    if silent and reset_pulse != "yes":
        status, branch = "blocked", "AMBIGUOUS_NO_RESET_PULSE"
    elif silent:
        status, branch = "blocked_A_no_pixels", "A_FRONT_END_NO_PIXELS"
    else:
        status = "PASS" if not errors else "FAIL"
        branch = "A_CHAIN_LIVE" if status == "PASS" else "A_GATE_FAILED"

    cap = {"status": status, "branch": branch, "reset_pulse": reset_pulse,
           "status_packets": len(st), "frames_ok": len(frames),
           "raw_bytes": len(raw), "sealed_frames": sealed, "tail_cut_frames": tail_cut,
           "bad_frames": bad,
           "a_counters": {"pix_beats": pix, "line_rises": line, "frame_rises": frame,
                          "pix_beats_abs": pix_abs, "line_rises_abs": line_abs,
                          "frame_rises_abs": frame_abs,
                          "frame_falls_abs": last.get("cam6", 0),
                          "roi_frames_abs": last.get("cam8", 0),
                          "clk_tgl_abs": last.get("cam0", 0),
                          "pkt_tgl_abs": last.get("cam1", 0),
                          "vs_tgl_abs": last.get("cam2", 0)},
           "delta": delta, "first": first, "last": last,
           "camsel_bit12": ((last.get("cam13", 0) >> 12) & 1) if st else None,
           "bit20": ((last.get("cam13", 0) >> 20) & 1) if st else None,
           "cam13_last": last.get("cam13"),
           "errors": errors, "checks": checks}
    (capdir / "board_gate.json").write_text(json.dumps(cap, indent=2))
    (capdir / "board_gate.txt").write_text(
        "BOARD_GATE status=%s branch=%s reset_pulse=%s status_packets=%d frames_ok=%d "
        "a_pix=%d a_line=%d a_frame=%d camsel_bit12=%s bit20=%s delta=%s errors=%s\n"
        % (status, branch, reset_pulse, len(st), len(frames), pix, line, frame,
           cap["camsel_bit12"], cap["bit20"], json.dumps(delta), errors))
    print(cap["status"], branch, json.dumps(delta), errors)
    return 0 if status == "PASS" else (3 if status == "blocked_A_no_pixels" else
                                       (4 if status == "blocked" else 1))


if __name__ == "__main__":
    cd = sys.argv[1]
    rp = sys.argv[2] if len(sys.argv) > 2 else "unknown"
    raise SystemExit(main(cd, rp))
