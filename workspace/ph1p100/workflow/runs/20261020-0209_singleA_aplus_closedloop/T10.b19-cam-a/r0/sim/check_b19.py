#!/usr/bin/env python3
"""check_b19.py -- T10.b19-cam-a chain checker.

Wraps check_b17.py (native PAXI/v6 gates) and adds the b19 (same structural) gates:

  geometry (T1 only, --geom): pix_beats 2,117,472 / line_rises 2,192 /
      frame_rises 1 / one ROI frame (crop_sofs == crop_lasts == 1) /
      crop_groups 518,400 / raw_len 2,592,000
  every decoded frame: four CRCs verified, strict zlib EOF, no half frame
  enc == exported == nframes

Usage: python check_b19.py <case_dir> [--geom] [exported=1 ... b17_bit0=0]
"""
import json
import pathlib
import sys

sys.dont_write_bytecode = True
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import check_b17  # noqa: E402

T1_GEOM = {"source_groups": 2117472, "b15_line_rises": 2192,
           "b15_frame_rises": 1, "crop_beats": 518400,
           "b15_raw_len": 2592000}
# NOTE: the frozen TB writes b15_pix_beats = crop_beats (518,400 ROI groups)
# and b15_crop_groups = source_groups (2,117,472 driven groups) -- the two labels
# are swapped in tb_b17_chain.sv.  The gate therefore uses the unambiguous keys
# source_groups / crop_beats and records the TB label swap in the result.


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    geom = "--geom" in sys.argv
    case = pathlib.Path(args[0])
    exp, bexp = {}, {}
    for a in args[1:]:
        if "=" in a:
            k, v = a.split("=", 1)
            (bexp if k.startswith("b17_") else exp)[k] = int(v)
    res = check_b17.check(case, exp, bexp)
    st = res["stats"]
    errs = res["errors"]

    gate = {"mode": "t1_geometry" if geom else "retry_path"}
    if geom:
        for k, v in T1_GEOM.items():
            gate[k] = st.get(k)
            if st.get(k) != v:
                errs.append("%s=%s expected %s" % (k, st.get(k), v))
        # no frame_falls counter exists in the frozen TB: one ROI frame is
        # asserted through crop_sofs/crop_lasts and the single decoded frame.
        gate["crop_sofs"] = st.get("crop_sofs")
        gate["crop_lasts"] = st.get("crop_lasts")
        if not (st.get("crop_sofs") == 1 and st.get("crop_lasts") == 1):
            errs.append("ROI frame boundary count %s/%s != 1/1" %
                        (st.get("crop_sofs"), st.get("crop_lasts")))
        if not (st.get("enc") == 1 and st.get("exported") == 1):
            errs.append("enc/exported %s/%s != 1/1" %
                        (st.get("enc"), st.get("exported")))
    frames = res.get("decoded", {}).get("frames", [])
    gate["frames"] = len(frames)
    gate["four_crcs"] = [f.get("four_crcs_verified") for f in frames]
    gate["strict_zlib"] = [f.get("strict_zlib_eof") for f in frames]
    gate["raw_len"] = [f.get("raw_len") for f in frames]
    if not frames:
        errs.append("no decoded frame")
    for f in frames:
        if not f.get("four_crcs_verified"):
            errs.append("frame %s four CRCs not verified" % f.get("seed"))
        if not f.get("strict_zlib_eof"):
            errs.append("frame %s zlib not strictly decodable" % f.get("seed"))
    # no half frame: one decoded frame per exported frame
    if len(frames) != st.get("exported"):
        errs.append("decoded frames %d != exported %s" % (len(frames), st.get("exported")))
    res["geom_gate"] = gate
    res["status"] = "PASS" if not errs else "FAIL"
    (case / "result.json").write_text(json.dumps(res, indent=2))
    print(json.dumps({"status": res["status"], "errors": errs,
                      "geom_gate": gate}, indent=2))
    print("B19_CHECK_RESULT status=%s exported=%s timeout=%s retry=%s giveup=%s "
          "pix_beats=%s lines=%s frames=%s raw_len=%s crc=%s zlib=%s" %
          (res["status"], st.get("exported"), st.get("timeout_cnt"),
           st.get("retry_cnt"), st.get("giveup_cnt"), st.get("b15_pix_beats"),
           st.get("b15_line_rises"), st.get("b15_frame_rises"),
           st.get("b15_raw_len"), gate["four_crcs"], gate["strict_zlib"]))
    return 0 if res["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
