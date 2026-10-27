#!/usr/bin/env python3
"""check_b18_board.py -- T10.b18-b17-b board gate for the 150 s COM8 capture.

Reads captures/status_v6.json (parse_status_v6.py output) and applies the
package gates:
  * >= 120 status packets (150 s run), every packet XOR/format ok, noise == 0
  * len=273 / ver=6 / fields=67 in every packet
  * B selected: field #13 (cam13) bit12 == 1 in every packet and bit20 == 0
    (CAM_SEL is bit 12; the b14 "bit20" comment was stale)
  * cap_frames / raw_pub / enc_frames / exported deltas > 0
  * crop_short == crop_geom_err == 0
  * timeout / retry / giveup deltas all exactly 0
  * >= 1 A1U1 frame with four CRCs + strict zlib, no half frame
  * stale_guard delta == 0, raw_drop delta == 0, ar-rlast <= 1, ar-r <= 1
  * v6: every last_issued_ar_low3 == 0, diag_flags bits1..5 == 0,
        same_aw_ar_cnt == same_w_ar_cnt == 0
If timeout/retry/giveup still grow: branch PAXI_B18_STILL_UNRESOLVED, keep the
v6 failure-AR evidence and stop (no second download, no re-capture).
"""
import json
import pathlib
import sys

L_MAX = 1


def main(capdir):
    capdir = pathlib.Path(capdir)
    j = json.loads((capdir / "status_v6.json").read_text())
    st = j["statuses"]
    frames = j["frames"]
    errors, checks = [], {}

    def req(name, ok, detail):
        checks[name] = detail
        if not ok:
            errors.append("%s: %s" % (name, detail))

    req("status_packets_ge_120", len(st) >= 120, len(st))
    req("all_xor_ok", all(s.get("xor_ok") for s in st), len(st))
    req("all_v6", all(s.get("version") == 6 and s.get("length") == 273 and
                      s.get("field_count") == 67 for s in st),
        sorted({(s.get("version"), s.get("length"), s.get("field_count")) for s in st}))
    req("resync_bytes_zero", j.get("noise", 1) == 0, j.get("noise"))
    req("all_sel_b", all(((s.get("cam13", 0) >> 12) & 1) == 1 for s in st), len(st))
    req("no_stale_bit20", all(((s.get("cam13", 0) >> 20) & 1) == 0 for s in st), len(st))

    first = st[0] if st else {}
    last = st[-1] if st else {}
    keys = ("cap_frames", "raw_pub", "enc_frames", "exported", "raw_drop",
            "timeout_cnt", "retry_cnt", "giveup_cnt", "stale_guard_cnt",
            "stale_r_cnt", "ar_cnt", "r_cnt", "rlast_cnt")
    delta = {k: last.get(k, 0) - first.get(k, 0) for k in keys}
    req("delta_cap_frames_gt_0", delta["cap_frames"] > 0, delta["cap_frames"])
    req("delta_raw_pub_gt_0", delta["raw_pub"] > 0, delta["raw_pub"])
    req("delta_enc_gt_0", delta["enc_frames"] > 0, delta["enc_frames"])
    req("delta_exported_gt_0", delta["exported"] > 0, delta["exported"])
    req("delta_timeout_zero", delta["timeout_cnt"] == 0, delta["timeout_cnt"])
    req("delta_retry_zero", delta["retry_cnt"] == 0, delta["retry_cnt"])
    req("delta_giveup_zero", delta["giveup_cnt"] == 0, delta["giveup_cnt"])
    req("delta_raw_drop_zero", delta["raw_drop"] == 0, delta["raw_drop"])
    req("crop_short_zero", all(s.get("cam11", 0) == 0 for s in st), last.get("cam11"))
    req("crop_geom_err_zero", all(s.get("cam12", 0) == 0 for s in st), last.get("cam12"))
    req("stale_guard_zero", last.get("stale_guard_cnt", 0) == 0,
        last.get("stale_guard_cnt"))
    req("frame_with_four_crcs_zlib",
        len(frames) >= 1 and all(f.get("four_crcs_verified") and f.get("strict_zlib_eof")
                                 for f in frames),
        [bool(f.get("four_crcs_verified") and f.get("strict_zlib_eof")) for f in frames])
    out_ar = last.get("ar_cnt", 0) - last.get("rlast_cnt", 0)
    lost = last.get("ar_cnt", 0) - last.get("r_cnt", 0)
    req("outstanding_ar_le_1", out_ar <= 1, out_ar)
    req("in_flight_beats_le_lmax_1", lost <= L_MAX - 1, lost)

    req("all_last_ar_low3_zero",
        all(s.get("last_issued_ar_low3", 1) == 0 for s in st), len(st))
    req("all_same_aw_ar_zero",
        all(s.get("same_aw_ar_cnt", 1) == 0 for s in st), len(st))
    req("all_same_w_ar_zero",
        all(s.get("same_w_ar_cnt", 1) == 0 for s in st), len(st))
    req("all_diag_bits1_5_zero",
        all((s.get("diag_flags", 0xFFFFFFFF) & 0x3E) == 0 for s in st),
        sorted({s.get("diag_flags", 0) & 0x3E for s in st}))

    h4 = (delta["giveup_cnt"] > 0 or
          (delta["timeout_cnt"] > 0 and delta["exported"] == 0))
    branch = "PAXI_B18_STILL_UNRESOLVED" if h4 else ("PASS" if not errors else "FAIL")
    cap = {"status_packets": len(st), "frames_ok": len(frames), "delta": delta,
           "first": first, "last": last, "outstanding_ar": out_ar,
           "lost_beats": lost, "L_max": L_MAX, "branch": branch,
           "errors": errors, "checks": checks,
           "status": "PASS" if branch == "PASS" else
                     ("PAXI_B18_STILL_UNRESOLVED" if h4 else "FAIL")}
    if h4:
        cap["failure_ar_evidence"] = {
            "last_issued_ar_addr_first": first.get("last_issued_ar_addr"),
            "last_issued_ar_addr_last": last.get("last_issued_ar_addr"),
            "last_issued_ar_low3_all": sorted({s.get("last_issued_ar_low3")
                                               for s in st}),
            "timeout_ar_addr_last": last.get("timeout_ar_addr"),
            "timeout_ar_low3_last": last.get("timeout_ar_low3"),
            "timeout_ar_valid_last": (last.get("diag_flags", 0) & 1),
            "same_aw_ar_cnt_last": last.get("same_aw_ar_cnt"),
            "same_w_ar_cnt_last": last.get("same_w_ar_cnt"),
            "inflight_state_last": last.get("inflight_state"),
            "diag_flags_last": last.get("diag_flags"),
            "diag_flags_all": sorted({s.get("diag_flags") for s in st}),
            "ar_delta": delta["ar_cnt"], "r_delta": delta["r_cnt"],
            "rlast_delta": delta["rlast_cnt"],
            "stale_guard_delta": delta["stale_guard_cnt"],
            "stale_r_delta": delta["stale_r_cnt"],
            "cam13_last": last.get("cam13"),
        }
    (capdir / "board_gate.json").write_text(json.dumps(cap, indent=2))
    (capdir / "board_gate.txt").write_text(
        "BOARD_GATE status=%s branch=%s status_packets=%d frames_ok=%d "
        "outstanding_ar=%d lost_beats=%d cam13_last=0x%08x delta=%s errors=%s\n"
        % (cap["status"], cap["branch"], len(st), len(frames), out_ar, lost,
           last.get("cam13", 0), json.dumps(delta), errors))
    print(cap["status"], cap["branch"], json.dumps(delta), errors)
    return 0 if branch == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1]))
