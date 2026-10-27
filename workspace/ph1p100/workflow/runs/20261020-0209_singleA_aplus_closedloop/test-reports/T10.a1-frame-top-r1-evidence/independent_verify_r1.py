#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Independent r1 verifier for T10.a1-frame-top.

No candidate tool is imported.  Uses stdlib zlib 1.2.13 as the third-party
decoder plus a from-scratch zlib/DEFLATE parser and a from-scratch RGGB
phase-0 Bayer inverse.  Handles all r1 modes: clean (0/5), recovery (1-4),
multi-frame (6), abort-final-word (7), illegal geometry (8), illegal config
then valid recovery (9).
"""
import binascii
import hashlib
import json
import sys
import zlib
from pathlib import Path

sys.dont_write_bytecode = True
RUN = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
OUTDIR = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else (RUN.parents[1] / "test-reports" / "T10.a1-frame-top-r1-evidence")


class BitReader:
    def __init__(self, data):
        self.d = data
        self.pos = 0
        self.bit = 0

    def bit1(self):
        if self.pos >= len(self.d):
            raise ValueError("E_TRUNCATED")
        v = (self.d[self.pos] >> self.bit) & 1
        self.bit += 1
        if self.bit == 8:
            self.bit = 0
            self.pos += 1
        return v

    def bits(self, n):
        v = 0
        for i in range(n):
            v |= self.bit1() << i
        return v

    def align_zero(self, where):
        if self.bit:
            if (self.d[self.pos] >> self.bit) != 0:
                raise ValueError("E_BAD_PADDING_" + where)
            self.bit = 0
            self.pos += 1

    def byte(self):
        if self.bit:
            raise ValueError("E_INTERNAL_UNALIGNED")
        if self.pos >= len(self.d):
            raise ValueError("E_TRUNCATED")
        v = self.d[self.pos]
        self.pos += 1
        return v


def canonical_table(lengths):
    maxlen = max(lengths)
    bl = [0] * (maxlen + 1)
    for L in lengths:
        bl[L] += 1
    code = 0
    nxt = [0] * (maxlen + 1)
    for bits in range(1, maxlen + 1):
        code = (code + bl[bits - 1]) << 1
        nxt[bits] = code
    tab = {}
    for sym, L in enumerate(lengths):
        tab[(L, nxt[L])] = sym
        nxt[L] += 1
    return tab, maxlen


FIX_TAB, FIX_MAX = canonical_table([8] * 144 + [9] * 112 + [7] * 24 + [8] * 8)
DIST_TAB, DIST_MAX = canonical_table([5] * 32)
LBASE = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43,
         51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
LEXT = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4,
        4, 4, 5, 5, 5, 5, 0]
DBASE = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257,
         385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289,
         16385, 24577]
DEXT = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9,
        10, 10, 11, 11, 12, 12, 13, 13]


def decode_sym(br, tab, maxlen):
    code = 0
    for L in range(1, maxlen + 1):
        code = (code << 1) | br.bit1()
        if (L, code) in tab:
            return tab[(L, code)]
    raise ValueError("E_INVALID_HUFFMAN_CODE")


def adler32_manual(data):
    a, b = 1, 0
    for x in data:
        a = (a + x) % 65521
        b = (b + a) % 65521
    return (b << 16) | a


def parse_stream(data, expected_len, expected_block_bytes):
    if len(data) < 2:
        raise ValueError("E_TRUNCATED")
    cmf, flg = data[0], data[1]
    if (cmf & 0x0F) != 8:
        raise ValueError("E_BAD_ZLIB_HEADER_CM")
    if ((cmf << 8) | flg) % 31 != 0:
        raise ValueError("E_BAD_ZLIB_HEADER_FCHECK")
    if flg & 0x20:
        raise ValueError("E_FDICT_SET")
    br = BitReader(data)
    br.pos = 2
    out = bytearray()
    blocks = []
    stored_blocks = fixed_blocks = 0
    literals = matches = 0
    max_dist = 0
    while True:
        bfinal = br.bits(1)
        btype = br.bits(2)
        start = len(out)
        if btype == 0:
            br.align_zero("STORED_HEADER")
            ln = br.bits(16)
            nln = br.bits(16)
            if (ln ^ 0xFFFF) != nln:
                raise ValueError("E_BAD_STORED_NLEN")
            if ln > 4800:
                raise ValueError("E_BAD_STORED_LEN")
            for _ in range(ln):
                out.append(br.byte())
            stored_blocks += 1
            blocks.append(("stored", start, len(out)))
        elif btype == 1:
            while True:
                sym = decode_sym(br, FIX_TAB, FIX_MAX)
                if sym < 256:
                    out.append(sym)
                    literals += 1
                elif sym == 256:
                    break
                elif 257 <= sym <= 285:
                    idx = sym - 257
                    length = LBASE[idx] + br.bits(LEXT[idx])
                    dsym = decode_sym(br, DIST_TAB, DIST_MAX)
                    if dsym > 29:
                        raise ValueError("E_BAD_DISTANCE_CODE")
                    dist = DBASE[dsym] + br.bits(DEXT[dsym])
                    if dist > len(out):
                        raise ValueError("E_BAD_DISTANCE")
                    if dist > 2048:
                        raise ValueError("E_DISTANCE_WINDOW")
                    max_dist = max(max_dist, dist)
                    for _ in range(length):
                        out.append(out[-dist])
                    matches += 1
                else:
                    raise ValueError("E_BAD_LENGTH_CODE")
            fixed_blocks += 1
            blocks.append(("fixed", start, len(out)))
        elif btype == 2:
            raise ValueError("E_BAD_BTYPE_DYNAMIC")
        else:
            raise ValueError("E_BAD_BTYPE_RESERVED")
        got = len(out) - start
        if len(blocks) - 1 < len(expected_block_bytes):
            exp = expected_block_bytes[len(blocks) - 1]
            if got != exp:
                raise ValueError("E_BLOCK_LEN got=%d want=%d block=%d" % (got, exp, len(blocks) - 1))
        if bfinal:
            break
        if len(blocks) > len(expected_block_bytes):
            raise ValueError("E_TOO_MANY_BLOCKS")
    if len(blocks) != len(expected_block_bytes):
        raise ValueError("E_BLOCK_COUNT got=%d want=%d" % (len(blocks), len(expected_block_bytes)))
    br.align_zero("FINAL")
    if br.pos + 4 != len(data):
        raise ValueError("E_STREAM_LEN_OR_TRAILING pos=%d len=%d" % (br.pos, len(data)))
    if int.from_bytes(data[br.pos:br.pos + 4], "big") != adler32_manual(bytes(out)):
        raise ValueError("E_BAD_ADLER")
    if len(out) != expected_len:
        raise ValueError("E_LENGTH_MISMATCH got=%d want=%d" % (len(out), expected_len))
    return bytes(out), {"blocks": len(blocks), "stored_blocks": stored_blocks,
                        "fixed_blocks": fixed_blocks, "literals": literals,
                        "matches": matches, "max_distance": max_dist,
                        "block_edges": blocks}


def unpack_samples(bs, n):
    if len(bs) * 4 != n * 5:
        raise ValueError("E_PACK_LEN")
    out = []
    for g in range(n // 4):
        b0, b1, b2, b3, b4 = bs[5 * g:5 * g + 5]
        out.extend([(b0 << 2) | (b4 & 3), (b1 << 2) | ((b4 >> 2) & 3),
                    (b2 << 2) | ((b4 >> 4) & 3), (b3 << 2) | ((b4 >> 6) & 3)])
    return out


def pack_samples(vals):
    if len(vals) % 4:
        raise ValueError("E_PACK_ALIGN")
    out = bytearray()
    for g in range(len(vals) // 4):
        p = vals[4 * g:4 * g + 4]
        out.extend([p[0] >> 2, p[1] >> 2, p[2] >> 2, p[3] >> 2,
                    ((p[0] & 3) | ((p[1] & 3) << 2) |
                     ((p[2] & 3) << 4) | ((p[3] & 3) << 6))])
    return bytes(out)


def bayer_inverse(xform, w, h, prep, pred):
    stride = w * 5 // 4
    nblk = (h + 1) // 2
    tail = h % 2
    half = w // 2
    samples = [[0] * w for _ in range(h)]
    off = 0
    block_sizes = []
    for b in range(nblk):
        one_row = bool(tail and b == nblk - 1)
        ns = w if one_row else 2 * w
        nb = ns * 5 // 4
        block_sizes.append(nb)
        blk = xform[off:off + nb]
        off += nb
        if prep:
            sv = unpack_samples(blk, ns)
            planes = ([sv[0:half], sv[half:2 * half]] if one_row else
                      [sv[i * half:(i + 1) * half] for i in range(4)])
            if pred:
                for pi in range(len(planes)):
                    acc = 0
                    for i in range(len(planes[pi])):
                        acc = (acc + planes[pi][i]) & 0x3FF
                        planes[pi][i] = acc
            y0 = 2 * b
            for x in range(w):
                if x % 2 == 0:
                    samples[y0][x] = planes[0][x // 2]
                    if not one_row:
                        samples[y0 + 1][x] = planes[2][x // 2]
                else:
                    samples[y0][x] = planes[1][x // 2]
                    if not one_row:
                        samples[y0 + 1][x] = planes[3][x // 2]
        else:
            for r in range(1 if one_row else 2):
                samples[2 * b + r] = unpack_samples(blk[r * stride:(r + 1) * stride], w)
    if off != len(xform):
        raise ValueError("E_XFORM_LEN")
    return b"".join(pack_samples(row) for row in samples), samples, block_sizes


def parse_stats(path):
    d = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        p = line.split()
        if len(p) != 2:
            continue
        k, v = p
        try:
            d[k] = int(v, 16) if (len(v) == 8 and all(c in "0123456789abcdefABCDEF" for c in v)) else int(v)
        except ValueError:
            d[k] = v
    return d


def verify_stream(name, data, raw, w, h, prep, pred, st, prefix, problems, check_crc=True, expect_fixed=None, expect_stored=None):
    stride = w * 5 // 4
    nblk = (h + 1) // 2
    expected_len = stride * h
    blk_bytes = [stride if (h % 2 and b == nblk - 1) else 2 * stride for b in range(nblk)]
    zout = None
    try:
        d = zlib.decompressobj()
        zout = d.decompress(data) + d.flush()
        if not d.eof or d.unused_data != b"" or d.unconsumed_tail != b"":
            problems.append("%s zlib_not_exact" % name)
    except Exception as e:
        problems.append("%s zlib_error:%s" % (name, e))
    try:
        xout, pst = parse_stream(data, expected_len, blk_bytes)
    except Exception as e:
        problems.append("%s independent_parse_error:%s" % (name, e))
        return None
    if zout is not None and zout != xout:
        problems.append("%s decoders_disagree" % name)
    back, samples, bsz = bayer_inverse(xout, w, h, prep, pred)
    ref_samples = [unpack_samples(raw[y * stride:(y + 1) * stride], w) for y in range(h)]
    smm = sum(1 for y in range(h) for x in range(w) if samples[y][x] != ref_samples[y][x])
    bmm = sum(1 for a, b in zip(back, raw) if a != b) + abs(len(back) - len(raw))
    if smm:
        problems.append("%s bayer_sample_mismatch=%d" % (name, smm))
    if bmm:
        problems.append("%s bayer_byte_mismatch=%d" % (name, bmm))
    if bsz != blk_bytes:
        problems.append("%s block_size_table" % name)
    if check_crc:
        want = {
            prefix + "_raw_len": expected_len,
            prefix + "_xform_len": expected_len,
            prefix + "_stream_len": len(data),
            prefix + "_raw_crc": binascii.crc32(raw) & 0xFFFFFFFF,
            prefix + "_xform_crc": binascii.crc32(xout) & 0xFFFFFFFF,
            prefix + "_stream_crc": binascii.crc32(data) & 0xFFFFFFFF,
            prefix + "_blocks": nblk,
            prefix + "_w": w, prefix + "_h": h,
        }
        for k, v in want.items():
            if st.get(k) != v:
                problems.append("%s %s got=%r want=%r" % (name, k, st.get(k), v))
    else:
        if st.get(prefix + "_stream_len") != len(data):
            problems.append("%s %s_stream_len got=%r want=%r" % (name, prefix, st.get(prefix + "_stream_len"), len(data)))
        if st.get(prefix + "_blocks") != nblk:
            problems.append("%s %s_blocks got=%r want=%r" % (name, prefix, st.get(prefix + "_blocks"), nblk))
    if expect_fixed is not None and pst["fixed_blocks"] != expect_fixed:
        problems.append("%s fixed_blocks=%d want=%d" % (name, pst["fixed_blocks"], expect_fixed))
    if expect_stored is not None and pst["stored_blocks"] != expect_stored:
        problems.append("%s stored_blocks=%d want=%d" % (name, pst["stored_blocks"], expect_stored))
    return {"stream_len": len(data), "blocks": pst["blocks"],
            "stored_blocks": pst["stored_blocks"], "fixed_blocks": pst["fixed_blocks"],
            "literals": pst["literals"], "matches": pst["matches"],
            "max_distance": pst["max_distance"], "sample_mismatch": smm,
            "byte_mismatch": bmm, "sha256_stream": hashlib.sha256(data).hexdigest(),
            "sha256_xform": hashlib.sha256(xout).hexdigest()}


def main():
    idx = json.loads((RUN / "cases/index.json").read_text(encoding="utf-8"))
    results, failures = [], []
    streams = {}
    for c in idx["cases"]:
        name, w, h, mode = c["name"], c["w"], c["h"], c["mode"]
        sd = RUN / "runs" / name
        st = parse_stats(sd / "stats.txt")
        prob = []
        info = {"name": name, "w": w, "h": h, "mode": mode,
                "prep": c["prep"], "pred": c["pred"]}
        if st.get("errs", 0) != 0:
            prob.append("tb_errs=%s" % st.get("errs"))
        for pref in ("p1", "p2", "p3"):
            if st.get(pref + "_xerr", 0) != 0:
                prob.append(pref + "_xerr")
            if st.get(pref + "_stab_err", 0) != 0:
                prob.append(pref + "_stab_err")
        raw = (RUN / c["raw"]).read_bytes()
        if hashlib.sha256(raw).hexdigest() != c["raw_sha256"]:
            prob.append("raw_sha256")
        if c["raw_len"] != len(raw):
            prob.append("raw_len")

        if mode in (0, 5):
            if st.get("p1_commit") != 1 or st.get("p1_last") != 1 or st.get("p1_abort") != 0:
                prob.append("p1_commit/last/abort=%r/%r/%r" % (st.get("p1_commit"), st.get("p1_last"), st.get("p1_abort")))
            data = bytes.fromhex((sd / "out.hex").read_text(encoding="ascii").strip())
            info["p1"] = verify_stream(name + ":p1", data, raw, w, h, c["prep"], c["pred"], st, "p1", prob,
                                       expect_fixed=(540 if name == "f1080p_p1d1" else None),
                                       expect_stored=(540 if name == "f1080p_rand" else None))
            if name == "mixed1920x16":
                p = info["p1"]
                if not p or p["fixed_blocks"] == 0 or p["stored_blocks"] == 0:
                    prob.append("mixed_fixed_stored_not_both")
            if name == "f1080p_rand":
                nblk = (h + 1) // 2
                if len(data) != len(raw) + 5 * nblk + 6:
                    prob.append("f1080p_rand_worst_bound_mismatch")
            info["cycles"] = st.get("p1_cycles")
            if st.get("p1_cycles"):
                info["mbps_187p5"] = (w * 5 // 4 * h) * 187_500_000.0 / st["p1_cycles"] / 1e6
            streams[name] = data

        elif mode in (1, 2, 3, 4):
            if st.get("p1_commit") != 0 or st.get("p1_last") != 0:
                prob.append("p1_commit/last=%r/%r" % (st.get("p1_commit"), st.get("p1_last")))
            if mode in (1, 3, 4) and st.get("p1_abort") != 1:
                prob.append("p1_abort=%r" % st.get("p1_abort"))
            if mode == 4:
                for k in ("p1_pending_after_abort", "p1_commit_after_release", "p1_last_after_release"):
                    if k == "p1_pending_after_abort" and st.get(k) != 1:
                        prob.append("%s=%r" % (k, st.get(k)))
                    if k != "p1_pending_after_abort" and st.get(k) != 0:
                        prob.append("%s=%r" % (k, st.get(k)))
            raw2 = (RUN / c["raw2"]).read_bytes()
            if hashlib.sha256(raw2).hexdigest() != c["raw2_sha256"]:
                prob.append("raw2_sha256")
            if st.get("p2_commit") != 1 or st.get("p2_last") != 1 or st.get("p2_abort") != 0:
                prob.append("p2_commit/last/abort=%r/%r/%r" % (st.get("p2_commit"), st.get("p2_last"), st.get("p2_abort")))
            data2 = bytes.fromhex((sd / "out2.hex").read_text(encoding="ascii").strip())
            info["p2"] = verify_stream(name + ":p2", data2, raw2, w, h, c["prep2"], c["pred2"], st, "p2", prob)

        elif mode == 6:
            n = st.get("multi_n", 0)
            if n != c.get("nframes", 2):
                prob.append("multi_n=%r" % n)
            data = bytes.fromhex((sd / "out.hex").read_text(encoding="ascii").strip())
            off = 0
            for i in range(1, n + 1):
                ln = st.get("m%d_stream_len" % i, 0)
                if ln <= 0 or off + ln > len(data):
                    prob.append("m%d_stream_len=%r" % (i, ln)); continue
                if st.get("m%d_commit" % i) != 1 or st.get("m%d_last" % i) != 1:
                    prob.append("m%d_commit/last=%r/%r" % (i, st.get("m%d_commit" % i), st.get("m%d_last" % i)))
                info["m%d" % i] = verify_stream("%s:m%d" % (name, i), data[off:off + ln], raw, w, h,
                                                c["prep"], c["pred"], st, "m%d" % i, prob,
                                                check_crc=False)
                off += ln
            if off != len(data):
                prob.append("multi_trailing_bytes off=%d len=%d" % (off, len(data)))
            tc, mb = st.get("multi_total_cycles", 0), st.get("multi_bytes", 0)
            if tc > 0 and mb > 0:
                info.update({"multi_n": n, "multi_total_cycles": tc, "multi_bytes": mb,
                             "mbps_187p5": mb * 187_500_000.0 / tc / 1e6,
                             "cycles_per_byte": tc / mb})
            else:
                prob.append("multi_cycles")

        elif mode == 7:
            if st.get("p1_commit") != 1 or st.get("p1_last") != 1:
                prob.append("p1_commit/last")
            data = bytes.fromhex((sd / "out.hex").read_text(encoding="ascii").strip())
            info["p1"] = verify_stream(name + ":p1", data, raw, w, h, c["prep"], c["pred"], st, "p1", prob)
            for k, want in (("p2_pending_last", 1), ("p2_last_after_abort", 0),
                            ("p2_abort_lvl", 1), ("p2_commit_after_abort", 0),
                            ("p2_last_after_release", 0), ("p2_commit_after_release", 0),
                            ("p2_valid_after_release", 0)):
                if st.get(k) != want:
                    prob.append("%s=%r want=%r" % (k, st.get(k), want))
            raw2 = (RUN / c["raw2"]).read_bytes()
            if hashlib.sha256(raw2).hexdigest() != c["raw2_sha256"]:
                prob.append("raw2_sha256")
            if st.get("p3_commit") != 1 or st.get("p3_last") != 1 or st.get("p3_abort") != 0:
                prob.append("p3_commit/last/abort=%r/%r/%r" % (st.get("p3_commit"), st.get("p3_last"), st.get("p3_abort")))
            data3 = bytes.fromhex((sd / "out2.hex").read_text(encoding="ascii").strip())
            info["p3"] = verify_stream(name + ":p3", data3, raw2, w, h, c["prep2"], c["pred2"], st, "p3", prob)

        elif mode == 8:
            for k, want in (("p1_abort_lvl", 1), ("p1_commit", 0), ("p1_busy", 0),
                            ("after_rst_abort", 0), ("p2_abort_lvl", 1), ("p2_commit", 0)):
                if st.get(k) != want:
                    prob.append("%s=%r want=%r" % (k, st.get(k), want))
            info["illegal"] = {k: st.get(k) for k in ("p1_abort_lvl", "p1_commit", "p1_busy", "after_rst_abort", "p2_abort_lvl", "p2_commit")}

        elif mode == 9:
            for k, want in (("p1_abort_lvl", 1), ("p1_commit", 0)):
                if st.get(k) != want:
                    prob.append("%s=%r want=%r" % (k, st.get(k), want))
            raw2 = (RUN / c["raw2"]).read_bytes()
            if hashlib.sha256(raw2).hexdigest() != c["raw2_sha256"]:
                prob.append("raw2_sha256")
            if st.get("p2_commit") != 1 or st.get("p2_last") != 1 or st.get("p2_abort") != 0:
                prob.append("p2_commit/last/abort=%r/%r/%r" % (st.get("p2_commit"), st.get("p2_last"), st.get("p2_abort")))
            data2 = bytes.fromhex((sd / "out2.hex").read_text(encoding="ascii").strip())
            info["p2"] = verify_stream(name + ":p2", data2, raw2, w, h, c["prep2"], c["pred2"], st, "p2", prob)

        info["problems"] = prob
        info["verdict"] = "PASS" if not prob else "FAIL"
        if prob:
            failures.append({"case": name, "problems": prob})
        results.append(info)

    bp_ok = streams.get("bp20x5") is not None and streams.get("bp20x5") == streams.get("odd20x5_p1d1")
    if not bp_ok:
        failures.append({"case": "bp20x5", "problems": ["bp_stream_differs"]})
    verdict = "PASS" if not failures else "FAIL"
    out = {"verifier": "independent r1 (stdlib only; no candidate tools imported)",
           "python": sys.version.split()[0], "zlib": zlib.ZLIB_RUNTIME_VERSION,
           "verdict": verdict, "bp_equivalence": bp_ok,
           "failures": failures, "cases": results}
    OUTDIR.mkdir(parents=True, exist_ok=True)
    (OUTDIR / "independent-result.json").write_text(json.dumps(out, indent=2), encoding="utf-8")
    print(json.dumps({"verdict": verdict, "failures": failures, "bp_equivalence": bp_ok}, indent=2))
    return 0 if verdict == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
