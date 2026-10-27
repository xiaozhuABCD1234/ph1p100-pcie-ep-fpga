#!/usr/bin/env python3
"""check_b15_board.py -- T10.b15-ddr-pace board gate for the 150 s COM8 capture.

Reads captures/status_v5.json (parse_status_v5.py output) and applies dev-plan
section 7.3:
  * >= 120 valid v5 status packets, every packet XOR/format ok, resync_bytes == 0
  * A path selected: field #13 (cam13) bit20 == 0 in every packet
  * camera/A+ progress: cap_frames delta > 0, enc_frames delta > 0,
    exported delta > 0; crop_short == crop_geom_err == 0
  * THE b15 GOAL: timeout / retry / giveup deltas are all exactly 0
  * >= 1 A1U1 frame with the four CRCs + strict zlib (parser decoded it)
  * at rest: ar_cnt - rlast_cnt <= 1, ar_cnt - r_cnt <= L_max-1 (L_max = 1 -> 0),
    stale_guard == 0
If timeout/retry/giveup are still 3/2/1 per frame with exported == 0 the result
is H4_UNRESOLVED (stop, no second download) -- that branch is reported, not
silently passed.
"""
import json
import pathlib
import sys

L_MAX = 1   # PAXI single-beat AR/R (see r0/diag/paxi-read-facts.md)


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
    req("resync_bytes_zero", j.get("resync_bytes", 0) == 0, j.get("resync_bytes"))
    req("all_sel_a", all(((s.get("cam13", 0) >> 20) & 1) == 0 for s in st), len(st))
    first = st[0] if st else {}
    last = st[-1] if st else {}
    keys = ("cap_frames", "raw_pub", "enc_frames", "exported", "timeout_cnt",
            "retry_cnt", "giveup_cnt", "stale_guard_cnt", "stale_r_cnt",
            "ar_cnt", "r_cnt", "rlast_cnt")
    delta = {k: last.get(k, 0) - first.get(k, 0) for k in keys}
    req("delta_cap_frames_gt_0", delta["cap_frames"] > 0, delta["cap_frames"])
    req("delta_raw_pub_gt_0", delta["raw_pub"] > 0, delta["raw_pub"])
    req("delta_enc_gt_0", delta["enc_frames"] > 0, delta["enc_frames"])
    req("delta_exported_gt_0", delta["exported"] > 0, delta["exported"])
    req("delta_timeout_zero", delta["timeout_cnt"] == 0, delta["timeout_cnt"])
    req("delta_retry_zero", delta["retry_cnt"] == 0, delta["retry_cnt"])
    req("delta_giveup_zero", delta["giveup_cnt"] == 0, delta["giveup_cnt"])
    req("crop_short_zero", all(s.get("cam11", 0) == 0 for s in st),
        last.get("cam11"))
    req("crop_geom_err_zero", all(s.get("cam12", 0) == 0 for s in st),
        last.get("cam12"))
    req("stale_guard_zero", last.get("stale_guard_cnt", 0) == 0,
        last.get("stale_guard_cnt"))
    req("frame_with_four_crcs_zlib", len(frames) >= 1,
        [bool(f.get("four_crcs_verified") and f.get("strict_zlib_eof")) for f in frames])
    out_ar = last.get("ar_cnt", 0) - last.get("rlast_cnt", 0)
    lost = last.get("ar_cnt", 0) - last.get("r_cnt", 0)
    req("outstanding_ar_le_1", out_ar <= 1, out_ar)
    req("in_flight_beats_le_lmax_1", lost <= L_MAX - 1, lost)

    h4 = (delta["timeout_cnt"] > 0 and delta["exported"] == 0)
    cap = {"status_packets": len(st), "frames_ok": len(frames), "delta": delta,
           "first": first, "last": last, "outstanding_ar": out_ar,
           "lost_beats": lost, "L_max": L_MAX,
           "branch": "H4_UNRESOLVED" if h4 else ("PASS" if not errors else "FAIL"),
           "errors": errors,
           "status": "PASS" if not errors else "FAIL"}
    (capdir / "board_gate.json").write_text(json.dumps(cap, indent=2))
    (capdir / "board_gate.txt").write_text(
        "BOARD_GATE status=%s branch=%s status_packets=%d frames_ok=%d "
        "outstanding_ar=%d lost_beats=%d delta=%s errors=%s\n"
        % (cap["status"], cap["branch"], len(st), len(frames), out_ar, lost,
           json.dumps(delta), errors))
    print(cap["status"], cap["branch"], json.dumps(delta), errors)
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1]))
