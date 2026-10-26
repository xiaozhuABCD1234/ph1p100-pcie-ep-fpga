#!/usr/bin/env python3
"""check_b14_board.py -- T10.b14-cam-b board gate for the 150 s COM8 capture.

Reads captures/status_v5.json (parse_status_v5.py output) and asserts:
  * >= 120 valid v5 status packets, every packet XOR/format ok (parser gate)
  * B (selected camera) front-end deltas: clk_tgl, pkt_tgl, pix_beats,
    line_rises, frame_rises, cap_frames all > 0
  * A+ deltas: enc_frames and exported > 0
  * >= 1 A1U1 frame with the four CRCs + strict zlib (parser decoded it)
  * every packet: cam_sysstat (field #13) shows CAM_SEL=1 at bit 12
    (p2_a1_board_top.v: {19'd0,CAM_SEL,...}), and the invariant b13 low bits
    (cfg_done/xclr_n/pll_locked/cfg_rst_n = 0x1D) are intact.
    NOTE: r0's manifest/checker said "bit20", but the RTL concatenation puts
    CAM_SEL at bit 12; bit20 is always 0 in the real bit (r0 board capture
    sysstat=0x00001F1D vs the b13 baseline 0x00000F1D).
  * no half frame: every decoded frame is complete by construction; the parser
    only accepts a frame when all four CRCs + strict zlib pass.
"""
import json
import pathlib
import sys


def main(capdir):
    capdir = pathlib.Path(capdir)
    j = json.loads((capdir / "status_v5.json").read_text())
    st = j["statuses"]
    frames = j["frames"]
    errors, checks = [], {}

    def req(name, ok, detail):
        checks[name] = detail
        if not ok:
            errors.append("%s: %s" % (name, detail))

    req("status_packets_ge_120", len(st) >= 120, len(st))
    req("all_xor_ok", all(s.get("xor_ok") for s in st), len(st))
    req("all_sel_b_bit12", all((s.get("cam13", 0) >> 12) & 1 == 1 for s in st), len(st))
    req("all_sysstat_core_ok", all((s.get("cam13", 0) & 0x1D) == 0x1D for s in st),
        sorted({hex(s.get("cam13", 0)) for s in st})[:4])
    req("note_bit20_is_not_camsel", True, "bit20=%d (informational)"
        % (st[0].get("cam13", 0) >> 20 & 1 if st else -1))
    first = st[0] if st else {}
    last = st[-1] if st else {}
    delta = {k: last.get(k, 0) - first.get(k, 0) for k in
             ("cap_frames", "raw_pub", "enc_frames", "exported", "cam0", "cam1",
              "cam2", "cam3", "cam4", "cam5", "cam6", "cam8", "cam11")}
    for name, key in (("clk_tgl", "cam0"), ("pkt_tgl", "cam1"), ("pix_beats", "cam3"),
                      ("line_rises", "cam4"), ("frame_rises", "cam5"),
                      ("cap_frames", "cap_frames"), ("enc", "enc_frames"),
                      ("exported", "exported")):
        req("delta_" + name + "_gt_0", delta[key] > 0, delta[key])
    req("delta_roi_frames_gt_0", delta["cam8"] > 0, delta["cam8"])
    req("frame_with_four_crcs_zlib", len(frames) >= 1,
        [f.get("four_crcs_verified") and f.get("strict_zlib_eof") for f in frames])
    cap = {"status_packets": len(st), "frames_ok": len(frames), "delta": delta,
           "first": first, "last": last, "errors": errors,
           "status": "PASS" if not errors else "FAIL"}
    (capdir / "board_gate.json").write_text(json.dumps(cap, indent=2))
    (capdir / "board_gate.txt").write_text(
        "BOARD_GATE status=%s status_packets=%d frames_ok=%d delta=%s errors=%s\n"
        % (cap["status"], len(st), len(frames), json.dumps(delta), errors))
    print(cap["status"], json.dumps(delta), errors)
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1]))
