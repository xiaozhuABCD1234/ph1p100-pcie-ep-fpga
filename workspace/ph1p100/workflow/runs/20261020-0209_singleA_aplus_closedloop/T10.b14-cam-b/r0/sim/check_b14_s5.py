#!/usr/bin/env python3
"""check_b14_s5.py -- S5 B-tap short-line / geometry-error negative test.

Expected: source frame 1 is aborted by a short ROI line (crop_geom_err=1), it is
never published or exported; source frame 2 is a good frame and must export
with the full four-CRC + strict-zlib + independent-reference contract.
"""
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import check_b13  # noqa: E402  (frozen frame/v5 parser and reference generator)


def main(case):
    case = pathlib.Path(case)
    errors = []

    def req(ok, why):
        if not ok:
            errors.append(why)

    stats = {}
    for tok in (case / "stats.txt").read_text().split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            try:
                stats[k] = int(v)
            except ValueError:
                pass
    data = bytes(map(int, (case / "capture.dec").read_text().split()))
    wire = bytes(map(int, (case / "wire.dec").read_text().split()))
    log = (case / "console.log").read_text(errors="replace")

    req("B14_CHAIN_DONE" in log, "missing normal completion marker")
    req("Fatal" not in log and "ASSERT_FAIL" not in log and "WATCHDOG" not in log,
        "sim assertion/fatal/watchdog")
    req(data == wire, "physical UART capture != debug bytes")
    req(stats.get("source_frames") == 2, "source_frames != 2")
    req(stats.get("cap") == 1, "bad frame was published: cap=%s" % stats.get("cap"))
    req(stats.get("raw_pub") == 1, "raw_pub != 1")
    req(stats.get("enc") == 1, "enc != 1")
    req(stats.get("exported") == 1, "exported != 1")
    # The bad frame opened a RAW writer on its first ROI line and was aborted by
    # the short line: exactly one partial frame must be dropped, and the good
    # frame must be the only complete (SOF+LAST) frame.
    req(stats.get("crop_sofs") == 2, "crop_sofs != 2 (expected abort after SOF)")
    req(stats.get("crop_lasts") == 1, "crop_lasts != 1")
    req(stats.get("raw_drop") == 1, "raw_drop != 1 (partial frame not dropped)")
    req(stats.get("cmp_drop") == 0, "cmp_drop != 0")
    req(stats.get("dup_words") == 0, "dup_words != 0")
    req(stats.get("fifo_reject") == 0, "fifo_reject != 0")

    decoded = {}
    try:
        decoded = check_b13.parse(data, stats["w"], stats["h"], stats["cam_w"],
                                  stats["roi_x"], stats["roi_y"])
        frames = decoded["frames"]
        req(len(frames) == 1, "decoded %d frames, expected 1" % len(frames))
        if frames:
            f = frames[0]
            raw, xf = f.pop("raw"), f.pop("xf")
            eraw, exf = check_b13.reference(222, stats["w"], stats["h"], stats["cam_w"],
                                            stats["roi_x"], stats["roi_y"])
            req(raw == eraw, "frame RAW does not match the second source seed")
            req(xf == exf, "frame transform does not match the second source seed")
            req(f["four_crcs_verified"] and f["strict_zlib_eof"],
                "frame did not pass four CRCs / strict zlib")
        req(len(decoded["statuses"]) >= 1, "no v5 status packet")
        if decoded["statuses"]:
            v = decoded["statuses"][-1]
            req(v["after_frame"] <= 1, "status placement invalid")
    except Exception as exc:  # noqa: BLE001
        errors.append("parse: %r" % (exc,))

    # raw selected-camera fields from the last 241 B status packet
    import struct
    sts = []
    off = 0
    while off + 241 <= len(data):
        if data[off:off + 2] == b"\xa5\x5a" and data[off + 2] == 241 and data[off + 3] == 5:
            p = data[off:off + 241]
            x = 0
            for b in p[:-1]:
                x ^= b
            if x == p[-1]:
                sts.append(struct.unpack("<59I", p[4:4 + 236]))
                off += 241
                continue
        off += 1
    if sts:
        v = sts[-1]
        req(v[16] == 1, "crop_roi_frames != 1")
        req(v[19] == 1, "crop_geom_err != 1 (got %d)" % v[19])
        req(v[18] == 0, "crop_short != 0 (got %d)" % v[18])
        req((v[21] >> 20) & 1 == 1, "cam_sysstat bit20 != 1")
    else:
        errors.append("no parseable 241 B status packet")

    res = dict(status="PASS" if not errors else "FAIL", errors=errors, stats=stats,
               decoded={k: (len(v) if isinstance(v, list) else v) for k, v in decoded.items()},
               limitations=["simulation only; small 96x12 B-geometry proxy for the "
                            "short-line abort path"])
    (case / "result.json").write_text(json.dumps(res, indent=2))
    print(json.dumps({"status": res["status"], "errors": res["errors"]}, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1]))
