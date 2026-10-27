#!/usr/bin/env python3
"""check_b17.py -- T10.b17 chain checker.

Wraps check_b17_core.py (the b13 frame/four-CRC/strict-zlib/reference decoder,
retargeted to the 273 B / 67 field v6 status packet) and adds the native PAXI
contract gates:

  b17_aw_low3_bad / b17_ar_low3_bad == 0   every PAXI address has addr[2:0]=0
  b17_mask_bad == 0                        every W handshake drives wstrb=0
  b17_same_req / b17_same_hs == 0          no same-cycle AW/W+AR in the candidate
  b17_model_bad_low3 / b17_model_oob == 0  model-side address contract
  b17_model_mask == 0                      model-side mask contract
  b17_model_sreq / b17_model_shs == 0      model-side concurrency contract
  b17_model_commit == b17_aw_hs == b17_w_hs (one commit per write command)
  v6: every status packet has last_ar_low3=0, diag_flags bits 1..5 = 0,
      same_aw_ar = same_w_ar = 0; bit0 (timeout_ar_valid) is only allowed in a
      run that expects a timeout (S3).

Usage: python check_b17.py <case_dir> [exported=1 timeout=0 ... b17_bit0=1]
"""
import json
import pathlib
import sys

sys.dont_write_bytecode = True
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import check_b17_core  # noqa: E402


def check(case, expect=None, bexp=None):
    bexp = dict(bexp or {})
    res = check_b17_core.check(case, expect)
    st = res["stats"]
    errors = res["errors"]

    def req(ok, why):
        if not ok:
            errors.append(why)

    req(st.get("b17_aw_low3_bad", -1) == 0, "AW address low3 nonzero")
    req(st.get("b17_ar_low3_bad", -1) == 0, "AR address low3 nonzero")
    req(st.get("b17_mask_bad", -1) == 0, "paxi_wstrb nonzero on a write handshake")
    req(st.get("b17_same_req", -1) == 0, "AW/W+AR requested in the same cycle")
    req(st.get("b17_same_hs", -1) == 0, "AW/W+AR handshook in the same cycle")
    for k in ("b17_model_bad_low3", "b17_model_oob", "b17_model_mask",
              "b17_model_sreq", "b17_model_shs"):
        req(st.get(k, -1) == 0, k + " nonzero")
    req(st.get("b17_model_commit", -1) == st.get("b17_aw_hs", -2) ==
        st.get("b17_w_hs", -3), "write command/commit accounting")
    req(st.get("b17_model_ar", 0) - st.get("b17_model_r", 0) <= 1,
        "more than one AR outstanding at rest")

    statuses = res.get("decoded", {}).get("statuses", [])
    req(len(statuses) > 0, "no v6 status packet")
    for s in statuses:
        req(s.get("last_ar_low3", -1) == 0, "status last_ar_low3 nonzero")
        req((s.get("diag_flags", 0xFFFFFFFF) & 0x3E) == 0,
            "diag_flags bits1..5 nonzero: 0x%08x" % s.get("diag_flags", 0))
        req(s.get("same_aw_ar", -1) == 0, "status same_aw_ar nonzero")
        req(s.get("same_w_ar", -1) == 0, "status same_w_ar nonzero")
        if not int(bexp.get("b17_bit0", 0)):
            req((s.get("diag_flags", 1) & 1) == 0, "timeout_ar_valid set in a clean run")

    res["b17"] = {k: v for k, v in st.items() if k.startswith("b17_")}
    res["b17_status"] = [{k: s.get(k) for k in
                          ("last_ar_addr", "last_ar_low3", "timeout_ar_addr",
                           "timeout_ar_low3", "same_aw_ar", "same_w_ar",
                           "inflight", "diag_flags")} for s in statuses]
    res["status"] = "PASS" if not errors else "FAIL"
    return res


if __name__ == "__main__":
    case = pathlib.Path(sys.argv[1])
    exp, bexp = {}, {}
    for a in sys.argv[2:]:
        if "=" in a:
            k, v = a.split("=", 1)
            (bexp if k.startswith("b17_") else exp)[k] = int(v)
    result = check(case, exp, bexp)
    (case / "result.json").write_text(json.dumps(result, indent=2))
    print(json.dumps({"status": result["status"], "errors": result["errors"],
                      "b17": result["b17"],
                      "stats_subset":
                      {k: result["stats"].get(k) for k in
                       ("exported", "enc", "timeout_cnt", "retry_cnt", "giveup_cnt",
                        "stale_guard_cnt", "cap", "raw_pub", "raw_drop", "cmp_drop",
                        "dup_words", "geom", "err", "cycles")}}, indent=2))
    print("B17_CHECK_RESULT status=%s exported=%s timeout=%s retry=%s giveup=%s "
          "stale=%s low3=%s/%s mask=%s same=%s/%s commit=%s ar=%s r=%s"
          % (result["status"], result["stats"].get("exported"),
             result["stats"].get("timeout_cnt"), result["stats"].get("retry_cnt"),
             result["stats"].get("giveup_cnt"), result["stats"].get("stale_guard_cnt"),
             result["stats"].get("b17_aw_low3_bad"),
             result["stats"].get("b17_ar_low3_bad"),
             result["stats"].get("b17_mask_bad"),
             result["stats"].get("b17_same_req"),
             result["stats"].get("b17_same_hs"),
             result["stats"].get("b17_model_commit"),
             result["stats"].get("b17_model_ar"),
             result["stats"].get("b17_model_r")))
    sys.exit(result["status"] != "PASS")
