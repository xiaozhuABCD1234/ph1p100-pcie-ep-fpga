"""T10.b12-r1-last T7 checker: SOF-reject drain case (tb_r1_sof).

Re-uses the independent R1 reference model (RAW10 source / Bayer transform /
zlib) from check_r1.py -- only the case-specific pass conditions are new.
"""
import hashlib
import json
import pathlib
import struct
import sys
import zlib

sys.dont_write_bytecode = True
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "indep"))
sys.path.insert(0, str(HERE / "indep" / "indep"))
import check_r1  # noqa: E402  (frozen independent reference model)

# The T7 stimulus sources are 200 (fault), 201 (SOF rejected) and 300 (recovery).
SEEDS = [200, 201, 300]


def packets(data, seeds=None):
    """Same parser/acceptance rules as check_r1.packets, local source list."""
    seeds = seeds or SEEDS
    off = 0
    frames = []
    while off < len(data):
        assert len(data) - off >= 44, 'partial header'
        hdr = data[off:off + 44]
        (magic, ver, flags, hlen, fid, w, h, rawlen, xlen, slen,
         rawcrc, xfcrc, scrc, hcrc) = struct.unpack('<IBBHIHHIIIIIII', hdr)
        assert (magic, ver, flags, hlen, w, h) == (0x31553141, 1, 3, 44, 32, 2), 'header protocol/geometry'
        assert rawlen == xlen == 80 and 0 < slen < 200, 'lengths'
        pay = data[off + 44:off + 44 + slen]
        assert len(pay) == slen, 'partial payload'
        assert zlib.crc32(hdr[:40]) & 0xffffffff == hcrc, 'header CRC'
        assert zlib.crc32(pay) & 0xffffffff == scrc, 'stream CRC'
        dec = zlib.decompressobj()
        xf = dec.decompress(pay) + dec.flush()
        assert dec.eof and not dec.unused_data and not dec.unconsumed_tail, 'zlib EOF/tail'
        assert len(xf) == xlen and zlib.crc32(xf) & 0xffffffff == xfcrc, 'transform length/CRC'
        matches = []
        for seed in seeds:
            raw, expectxf = check_r1.expected(seed)
            if xf == expectxf and zlib.crc32(raw) & 0xffffffff == rawcrc:
                matches.append(seed)
        assert len(matches) == 1, 'RAW source CRC / reference transform mismatch'
        frames.append(dict(frame_id=fid, seed=matches[0], offset=off, bytes=44 + slen,
                           stream_len=slen, four_crcs=True, reference_raw_and_xform=True,
                           strict_zlib=True))
        off += 44 + slen
    return frames


def main(case_dir):
    case_dir = pathlib.Path(case_dir)
    errors = []
    text = (case_dir / "stats.txt").read_text() if (case_dir / "stats.txt").exists() else ""
    stats = {}
    for tok in text.split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            stats[k] = int(v) if v.lstrip("-").isdigit() else v
    needed = ["rawpub", "enc", "exp", "bytes", "uart_bytes", "sof_accept", "sof_reject",
              "last_reject", "rejects", "crop_aborts", "raw_abort_cnt", "rawdrop",
              "begin_deny", "writer_final", "slot0", "slot1", "geom", "err",
              "post_release_writer", "drain_cycles"]
    if not all(k in stats for k in needed):
        result = dict(status="INVALID", errors=["missing stats: %s" % [k for k in needed if k not in stats]],
                      stats=stats)
        (case_dir / "result.json").write_text(json.dumps(result, indent=2))
        print(json.dumps(result, indent=2))
        return 2

    def require(ok, why):
        if not ok:
            errors.append(why)

    log = (case_dir / "console.log").read_text(errors="replace")
    debug = bytes(map(int, (case_dir / "capture.dec").read_text().split()))
    wire = bytes(map(int, (case_dir / "uart.dec").read_text().split()))
    trace = (case_dir / "trace.txt").read_text()

    require("CASE_RESULT case=t7" in log, "TB did not complete")
    require(debug == wire and len(wire) == stats["bytes"] == stats["uart_bytes"],
            "debug/UART accounting")
    # fault preconditions (independent of the fix)
    require(stats["sof_reject"] >= 1, "no SOF was rejected (T7 precondition)")
    require(stats["last_reject"] >= 1, "no LAST was rejected (T7 precondition)")
    require(stats["crop_aborts"] == 0, "crop aborted: not a loss-abort stimulus")
    require("LAST_REJECTED" in trace and "RELEASED_DRAINED" in trace, "trace preconditions")
    # recovery conditions
    require(stats["geom"] == 0 and stats["err"] == 0, "geometry/error counters")
    require(stats["exp"] == 1 and stats["rawpub"] == 1 and stats["enc"] == 1,
            "damaged frames published or good frame lost")
    require(stats["writer_final"] == 0, "orphan writer after drain")
    require(stats["post_release_writer"] == 0, "writer not released after backpressure release")
    require(stats["raw_abort_cnt"] >= 1, "store abort never fired")
    require(stats["rawdrop"] >= 1, "raw_drop not incremented")
    require(stats["slot0"] == 0 and stats["slot1"] == 0, "slot leaked")

    decoded = []
    try:
        decoded = packets(wire)
    except (AssertionError, zlib.error, ValueError) as exc:
        errors.append("packet decode: %s" % exc)
    require(len(decoded) == stats["exp"], "packet/export count")
    require([p["seed"] for p in decoded] == [300], "exact recovered source sequence")
    if decoded:
        require(len({p["frame_id"] for p in decoded}) == len(decoded), "duplicate frame id")
        require(all(p["four_crcs"] and p["strict_zlib"] for p in decoded), "CRC/zlib")

    errors = [e for e in errors if e]
    status = "PASS" if not errors else "FAIL"
    result = dict(status=status, errors=errors, stats=stats, decoded=decoded,
                  wire_bytes=len(wire), uart_sha256=hashlib.sha256(wire).hexdigest())
    (case_dir / "result.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
    return 0 if status == "PASS" else 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))

