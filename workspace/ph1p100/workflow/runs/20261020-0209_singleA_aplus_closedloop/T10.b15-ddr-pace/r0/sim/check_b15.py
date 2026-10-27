#!/usr/bin/env python3
"""check_b15.py -- T10.b15 checker.

Wraps the frozen b13 frame/v5 checker (unchanged PASS conditions: 44 B header,
four CRCs, strict zlib EOF, independent RAW/xform reference, v5 241 B / 59
fields / XOR) and adds the b15 read-path gates:

  b15_rready_low   == 0     paxi_rready never lowered (R3)
  b15_ar_busy_hs   == 0     no AR presented while a burst is owned (R2)
  b15_max_os       == 1     MAX_OS = 1 (R2 / S8)
  b15_rf_ovf       == 0     every pushed beat was taken by the RF (no overflow)
  b15_max_rf_level <= 16    RF occupancy never exceeded its depth
  b15_short_burst  == 0     no burst closed without rlast (except the expected
                            purge/guard closure after an injected loss)
  b15_ar_minus_rlast <= 1   at most one AR outstanding at rest

Usage: python check_b15.py <case_dir> [exported=1 timeout=0 ... b15_*=...]
"""
import json
import pathlib
import sys

sys.dont_write_bytecode = True
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import check_b13  # noqa: E402


def check(case, expect=None, bexp=None):
    bexp = dict(bexp or {})
    res = check_b13.check(case, expect)
    st = res["stats"]
    errors = res["errors"]

    def req(ok, why):
        if not ok:
            errors.append(why)

    req(st.get("b15_rready_low", -1) == 0, "paxi_rready was lowered (%s)" % st.get("b15_rready_low"))
    req(st.get("b15_ar_busy_hs", -1) == 0, "AR issued while a burst was owned (%s)" % st.get("b15_ar_busy_hs"))
    req(st.get("b15_rf_ovf", -1) == 0, "read FIFO overflow: a beat was dropped (%s)" % st.get("b15_rf_ovf"))
    req(st.get("b15_max_rf_level", 99) <= 16, "rf_level above RF depth (%s)" % st.get("b15_max_rf_level"))
    req(st.get("b15_max_os", 0) == int(bexp.get("b15_max_os", 1)),
        "MAX_OS=%s expected %s" % (st.get("b15_max_os"), bexp.get("b15_max_os", 1)))
    req(st.get("b15_short_burst", -1) == int(bexp.get("b15_short_burst", 0)),
        "short_burst=%s expected %s" % (st.get("b15_short_burst"), bexp.get("b15_short_burst", 0)))
    if "b15_purge_close_min" in bexp:
        req(st.get("b15_purge_close", -1) >= int(bexp["b15_purge_close_min"]),
            "purge_close=%s < %s" % (st.get("b15_purge_close"), bexp["b15_purge_close_min"]))
    if "b15_stale_r_min" in bexp:
        req(st.get("b15_stale_r", -1) >= int(bexp["b15_stale_r_min"]),
            "stale_r=%s < %s" % (st.get("b15_stale_r"), bexp["b15_stale_r_min"]))
    if "b15_stale_r" in bexp:
        req(st.get("b15_stale_r", -1) == int(bexp["b15_stale_r"]),
            "stale_r=%s expected %s" % (st.get("b15_stale_r"), bexp["b15_stale_r"]))
    req(st.get("b15_ar", 0) - st.get("b15_rlast", 0) <= int(bexp.get("b15_ar_minus_rlast_max", 1)),
        "outstanding AR at rest = %d" % (st.get("b15_ar", 0) - st.get("b15_rlast", 0)))
    # Geometry / byte accounting for the full board frame (dev-plan section 5).
    # NOTE on the two stat names: the TB prints b15_pix_beats = crop_valid beats
    # (post-crop groups) and b15_crop_groups = tap/source groups (pre-crop), i.e.
    # the board v5 names are crossed relative to these two keys.  Asserted here
    # against the frozen board numbers (pix_beats 2,117,472 / crop_groups
    # 518,400) with the mapping written out explicitly.
    if int(bexp.get("b15_full_frame", 0)):
        req(st.get("b15_crop_groups") == 2117472, "tap/source beats=%s (board pix_beats)" % st.get("b15_crop_groups"))
        req(st.get("b15_pix_beats") == 518400, "crop groups=%s (board crop_groups)" % st.get("b15_pix_beats"))
        req(st.get("b15_line_rises") == 2192, "line_rises=%s" % st.get("b15_line_rises"))
        req(st.get("b15_frame_rises") == 1, "frame_rises=%s" % st.get("b15_frame_rises"))
        req(st.get("b15_raw_len") == 2592000, "raw_len=%s" % st.get("b15_raw_len"))
    # Loss recovery must not resurrect a duplicate beat.
    req(st.get("dup_words", 0) == 0, "dup_words nonzero")
    res["b15"] = {k: v for k, v in st.items() if k.startswith("b15_")}
    res["status"] = "PASS" if not errors else "FAIL"
    return res


if __name__ == "__main__":
    case = pathlib.Path(sys.argv[1])
    exp, bexp = {}, {}
    for a in sys.argv[2:]:
        if "=" in a:
            k, v = a.split("=", 1)
            (bexp if k.startswith("b15_") else exp)[k] = int(v)
    result = check(case, exp, bexp)
    (case / "result.json").write_text(json.dumps(result, indent=2))
    print(json.dumps({"status": result["status"], "errors": result["errors"],
                      "b15": result["b15"], "stats_subset":
                      {k: result["stats"].get(k) for k in
                       ("exported", "enc", "timeout_cnt", "retry_cnt", "giveup_cnt",
                        "stale_guard_cnt", "cap", "raw_pub", "raw_drop", "cmp_drop",
                        "dup_words", "geom", "err", "cycles")}}, indent=2))
    print("B15_CHECK_RESULT status=%s exported=%s timeout=%s retry=%s giveup=%s "
          "stale=%s max_os=%s rf_ovf=%s rready_low=%s short_burst=%s ar=%s r=%s rlast=%s"
          % (result["status"], result["stats"].get("exported"),
             result["stats"].get("timeout_cnt"), result["stats"].get("retry_cnt"),
             result["stats"].get("giveup_cnt"), result["stats"].get("stale_guard_cnt"),
             result["stats"].get("b15_max_os"), result["stats"].get("b15_rf_ovf"),
             result["stats"].get("b15_rready_low"), result["stats"].get("b15_short_burst"),
             result["stats"].get("b15_ar"), result["stats"].get("b15_r"),
             result["stats"].get("b15_rlast")))
    sys.exit(result["status"] != "PASS")
