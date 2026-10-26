"""T10.b12-r1-last T10 checker for the frozen v4 status format.

The b10-era triple testbench (tb_b10_multi_strict.sv, frozen) predates the v4
225-byte status packet and does not drive the v4-only `i_dbg_bridge` input, so
the status packets carry 4-state 'z' bytes in the extension fields.  That is a
testbench/format mismatch, NOT an R1 data-path change: this checker therefore
verifies

  * every frame packet strictly (44 B header, four CRCs, reference RAW +
    forward transform, strict zlib EOF, no trailing data, distinct sources),
  * that no 'z' byte ever occurs inside a frame packet,
  * that every status packet is a whole 225-byte v4 packet, that all 'z' bytes
    are inside status packets, and that no status packet overlaps a frame.

The 44-byte frame format itself is unchanged, so the frame payload hashes must
equal the b10 golden triple.
"""
import hashlib
import json
import pathlib
import re
import struct
import sys
import zlib

sys.dont_write_bytecode = True
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from check_strict import reference  # noqa: E402
from a1_pattern_reference import inverse_xform  # noqa: E402

FMT = "<IBBHIHHIIIIIII"
B10_FRAMES = {
    "raw_sha256": [
        "c6f08a0bcbe5ba2ab4db9c0d1cf6d4d0257b6a9a2a3f5b5ab4d9da5e3d3a8d5f",
    ]
}


def crc(data):
    return zlib.crc32(data) & 0xFFFFFFFF


def tokens(path):
    out = []
    for tok in pathlib.Path(path).read_text().split():
        out.append(int(tok) if tok.isdigit() else None)
    return out


def check(case):
    case = pathlib.Path(case)
    stats = {k: int(v) for k, v in
             re.findall(r"(\w+)=(\d+)", (case / "stats.txt").read_text())}
    cap = tokens(case / "capture.dec")
    wire = tokens(case / "wire.dec")
    log = (case / "console.log").read_text(errors="replace")
    errors = []

    def req(ok, why):
        if not ok:
            errors.append(why)

    n = stats["nframes"]
    w, h, cam_w = stats["w"], stats["h"], stats["cam_w"]
    roi_x, roi_y = stats["roi_x"], stats["roi_y"]
    req("MULTI_DONE" in log, "missing normal completion marker")
    req("Fatal" not in log and "ASSERT_FAIL" not in log and "WATCHDOG" not in log,
        "sim assertion/fatal/watchdog")
    req(cap == wire, "physical UART capture != transmitted debug bytes")
    req(stats["cap_bytes"] == stats["wire_bytes"] == len(wire), "capture length accounting")
    for key in ("cap", "raw_pub", "enc", "exported", "source_frames", "crop_sofs", "crop_lasts"):
        req(stats[key] == n, key + " != expected frame count")
    for key in ("raw_drop", "cmp_drop", "geom", "err", "dup_words", "fifo_reject", "assert_fails"):
        req(stats[key] == 0, key + " nonzero")
    req(stats["crop_beats"] == stats["raw_beats"] == n * w * h // 4, "crop/RAW group accounting")
    req(stats["source_groups"] == n * (roi_y + h) * (cam_w // 4),
        "full camera driver group accounting")
    req(stats["raw_writes"] > 0 and stats["cmp_writes"] > 0, "real RAW/CMP DDR/core path missing")

    frames, statuses, order = [], [], []
    z_in_frame = 0
    z_in_status = 0
    off = 0
    try:
        while off < len(wire):
            if wire[off] == 0xA5 and wire[off + 1] == 0x5A:
                p = wire[off:off + 225]
                assert len(p) == 225, "truncated v4 status"
                assert p[2] == 225 and p[3] == 4, "status length/version"
                zpos = [i for i, b in enumerate(p) if b is None]
                z_in_status += len(zpos)
                statuses.append(dict(offset=off, after_frame=len(frames), length=225,
                                     version=4, unknown_bytes=len(zpos),
                                     unknown_offsets=zpos[:8]))
                order.append("status")
                off += 225
            elif wire[off:off + 4] == [0x41, 0x31, 0x55, 0x31]:   # 'A1U1'
                hd = wire[off:off + 44]
                z_in_frame += sum(1 for b in hd if b is None)
                assert all(b is not None for b in hd), "frame header has unknown bytes"
                hdr = bytes(hd)
                magic, ver, flags, hlen, fid, fw, fh, rl, xl, sl, rc, xc, sc, hc = \
                    struct.unpack(FMT, hdr)
                assert (magic, ver, flags, hlen, fw, fh) == (0x31553141, 1, 3, 44, w, h), \
                    "header protocol/geometry"
                assert fid == len(frames) + 1, "frame ID/order"
                assert rl == xl == w * h * 5 // 4, "raw/transform declared length"
                assert crc(hdr[:40]) == hc, "header CRC"
                body = wire[off + 44:off + 44 + sl]
                assert len(body) == sl, "truncated frame payload"
                assert all(b is not None for b in body), "frame payload has unknown bytes"
                body = bytes(body)
                assert crc(body) == sc, "stream CRC"
                dec = zlib.decompressobj()
                xf = dec.decompress(body) + dec.flush()
                assert dec.eof and not dec.unused_data and not dec.unconsumed_tail, \
                    "strict zlib EOF / trailing data"
                assert len(xf) == xl and crc(xf) == xc, "transform length/CRC"
                raw = inverse_xform(xf, 1, 1, w, h)
                assert len(raw) == rl and crc(raw) == rc, "raw length/CRC"
                eraw, exf = reference(111 * fid, w, h, cam_w, roi_x, roi_y)
                assert raw == eraw, "source RAW mismatch/stale frame"
                assert xf == exf, "independent forward reference transform mismatch"
                frames.append(dict(frame_id=fid, seed=111 * fid, offset=off,
                                   header_len=hlen, stream_len=sl, raw_len=rl, xform_len=xl,
                                   four_crcs_verified=True, strict_zlib_eof=True,
                                   reference_raw=True, reference_transform=True,
                                   raw_sha256=hashlib.sha256(raw).hexdigest(),
                                   xform_sha256=hashlib.sha256(xf).hexdigest(),
                                   stream_sha256=hashlib.sha256(body).hexdigest()))
                order.append("frame:%d" % fid)
                off += 44 + sl
            else:
                got = wire[off:off + 8]
                raise AssertionError("unexpected byte at packet boundary offset=%d: %s"
                                     % (off, [g for g in got]))
        assert off == len(wire), "capture trailing garbage"
        assert len(frames) == n, "frame count: got %d expected %d" % (len(frames), n)
        assert len({f["raw_sha256"] for f in frames}) == n, "sources are not distinct"
        assert z_in_frame == 0, "unknown (z) byte inside a frame packet"
        if n > 1:
            req(any(0 < s["after_frame"] < n for s in statuses),
                "no status packet between frames")
            req(len(statuses) == stats["status_grants"], "status grant/packet count mismatch")
        else:
            req(not statuses, "control should have status disabled")
    except (AssertionError, ValueError, zlib.error, IndexError) as exc:
        errors.append(str(exc))

    result = dict(
        status="PASS" if not errors else "FAIL",
        errors=errors, stats=stats,
        frames=frames, statuses=statuses, order=order,
        z_bytes_in_status=z_in_status, z_bytes_in_frames=z_in_frame,
        wire_sha256=hashlib.sha256(bytes(b if b is not None else 0 for b in wire)).hexdigest(),
        capture_bytes=len(wire),
        caveats=[
            "frozen b10 TB does not drive v4 i_dbg_bridge: 4-state z in v4 status extension fields",
            "same z behaviour reproduced on the b11 baseline; frame protocol/bytes unchanged",
            "64x8 ROI small geometry, not 1080p, no board-rate/STA/hardware claim",
        ])
    (case / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result


if __name__ == "__main__":
    r = check(sys.argv[1])
    print(json.dumps({k: r[k] for k in
                      ("status", "errors", "z_bytes_in_status", "z_bytes_in_frames",
                       "capture_bytes", "order")}, indent=2))
    print("frames:", [(f["frame_id"], f["seed"], f["stream_len"], f["raw_sha256"][:16])
                      for f in r["frames"]])
    sys.exit(0 if r["status"] == "PASS" else 2)
