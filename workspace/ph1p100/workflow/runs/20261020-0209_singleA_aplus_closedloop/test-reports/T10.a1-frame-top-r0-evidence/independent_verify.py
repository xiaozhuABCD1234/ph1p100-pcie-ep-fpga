#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Independent P3 verifier for T10.a1-frame-top.

Written by the independent integrated tester.  Deliberately does NOT import
a1_ref.py, a1_inflate_strict.py, or any candidate verification helper.  It uses
only the Python stdlib (zlib 1.2.13 as the third-party decoder) plus a
from-scratch zlib/DEFLATE parser and a from-scratch Bayer inverse transform
implemented directly from format-v1.md.

Checks per case:
  * DUT-produced stream decoded by zlib (eof, no unused/unconsumed data)
  * DUT-produced stream decoded by this independent parser (stored + fixed only,
    exact stream_len, zero padding, Adler, block sizes, BFINAL, distance<=2048)
  * Bayer inverse transform back to raw, sample-by-sample and byte-for-byte
  * DUT stats (len/CRC/block count/commit/abort/stability) vs recomputed values
"""
import binascii
import hashlib
import json
import sys
import zlib
from pathlib import Path

sys.dont_write_bytecode = True

RUN = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()

# ---------------------------------------------------------------- bit reader
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
            rest = self.d[self.pos] >> self.bit
            if rest != 0:
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


FIX_LEN = [8] * 144 + [9] * 112 + [7] * 24 + [8] * 8
FIX_TAB, FIX_MAX = canonical_table(FIX_LEN)
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
    a = 1
    b = 0
    for x in data:
        a = (a + x) % 65521
        b = (b + a) % 65521
    return (b << 16) | a


def parse_stream(data, expected_len, expected_block_bytes):
    """Return (xform_bytes, stats).  Strict subset: stored + fixed, no dynamic."""
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
        exp = expected_block_bytes[len(blocks) - 1] if len(blocks) <= len(expected_block_bytes) else None
        if exp is not None and got != exp:
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
    adler = int.from_bytes(data[br.pos:br.pos + 4], "big")
    if adler != adler32_manual(bytes(out)):
        raise ValueError("E_BAD_ADLER")
    if len(out) != expected_len:
        raise ValueError("E_LENGTH_MISMATCH got=%d want=%d" % (len(out), expected_len))
    return bytes(out), {
        "blocks": len(blocks),
        "stored_blocks": stored_blocks,
        "fixed_blocks": fixed_blocks,
        "literals": literals,
        "matches": matches,
        "max_distance": max_dist,
        "block_edges": [(t, s, e) for (t, s, e) in blocks],
    }


# ------------------------------------------------------------ RAW10 / Bayer
def unpack_samples(bs, n):
    if len(bs) * 4 != n * 5:
        raise ValueError("E_PACK_LEN bytes=%d samples=%d" % (len(bs), n))
    out = []
    for g in range(n // 4):
        b0, b1, b2, b3, b4 = bs[5 * g:5 * g + 5]
        out.extend([(b0 << 2) | (b4 & 3),
                    (b1 << 2) | ((b4 >> 2) & 3),
                    (b2 << 2) | ((b4 >> 4) & 3),
                    (b3 << 2) | ((b4 >> 6) & 3)])
    return out


def pack_samples(vals):
    if len(vals) % 4 != 0:
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
            if one_row:
                planes = [sv[0:half], sv[half:2 * half]]
            else:
                planes = [sv[i * half:(i + 1) * half] for i in range(4)]
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
            if len(blk) != nb:
                raise ValueError("E_BYPASS_BLOCK_LEN")
            for r in range(1 if one_row else 2):
                row = unpack_samples(blk[r * stride:(r + 1) * stride], w)
                samples[2 * b + r] = row
    if off != len(xform):
        raise ValueError("E_XFORM_LEN off=%d len=%d" % (off, len(xform)))
    raw = b"".join(pack_samples(row) for row in samples)
    return raw, samples, block_sizes


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


def check_stats(st, name, prefix, raw, xform, data, w, h, problems):
    stride = w * 5 // 4
    want = {
        prefix + "_raw_len": stride * h,
        prefix + "_xform_len": stride * h,
        prefix + "_stream_len": len(data),
        prefix + "_raw_crc": binascii.crc32(raw) & 0xFFFFFFFF,
        prefix + "_xform_crc": binascii.crc32(xform) & 0xFFFFFFFF,
        prefix + "_stream_crc": binascii.crc32(data) & 0xFFFFFFFF,
        prefix + "_blocks": (h + 1) // 2,
        prefix + "_w": w,
        prefix + "_h": h,
    }
    for k, v in want.items():
        if st.get(k) != v:
            problems.append("%s %s got=%r want=%r" % (name, k, st.get(k), v))


def check_stream(name, hex_path, raw, w, h, prep, pred, st, prefix, problems):
    txt = Path(hex_path).read_text(encoding="ascii").strip()
    data = bytes.fromhex(txt) if txt else b""
    expected_len = w * 5 // 4 * h
    stride = w * 5 // 4
    nblk = (h + 1) // 2
    blk_bytes = [stride if (h % 2 and b == nblk - 1) else 2 * stride for b in range(nblk)]

    # third-party decoder
    try:
        d = zlib.decompressobj()
        zout = d.decompress(data) + d.flush()
        if not d.eof or d.unused_data != b"" or d.unconsumed_tail != b"":
            problems.append("%s zlib_not_exact" % name)
    except Exception as e:
        zout = None
        problems.append("%s zlib_error:%s" % (name, e))

    # from-scratch parser
    try:
        xout, pst = parse_stream(data, expected_len, blk_bytes)
    except Exception as e:
        problems.append("%s independent_parse_error:%s" % (name, e))
        xout, pst = None, {}

    if zout is not None and xout is not None and zout != xout:
        problems.append("%s decoders_disagree" % name)
    if xout is None:
        return None

    # inverse Bayer, sample-by-sample and byte-for-byte
    try:
        raw_back, samples_back, bsz = bayer_inverse(xout, w, h, prep, pred)
    except Exception as e:
        problems.append("%s bayer_error:%s" % (name, e))
        return None
    raw_ref_samples = [unpack_samples(raw[y * stride:(y + 1) * stride], w) for y in range(h)]
    sample_mismatch = sum(1 for y in range(h) for x in range(w)
                          if samples_back[y][x] != raw_ref_samples[y][x])
    byte_mismatch = sum(1 for a, b in zip(raw_back, raw) if a != b) + abs(len(raw_back) - len(raw))
    if sample_mismatch:
        problems.append("%s bayer_sample_mismatch=%d" % (name, sample_mismatch))
    if byte_mismatch:
        problems.append("%s bayer_byte_mismatch=%d" % (name, byte_mismatch))
    if bsz != blk_bytes:
        problems.append("%s block_size_table" % name)

    check_stats(st, name, prefix, raw, xout, data, w, h, problems)
    return {
        "stream_len": len(data),
        "xform_len": len(xout),
        "blocks": pst.get("blocks"),
        "stored_blocks": pst.get("stored_blocks"),
        "fixed_blocks": pst.get("fixed_blocks"),
        "literals": pst.get("literals"),
        "matches": pst.get("matches"),
        "max_distance": pst.get("max_distance"),
        "sample_mismatch": sample_mismatch,
        "byte_mismatch": byte_mismatch,
        "sha256_stream": hashlib.sha256(data).hexdigest(),
        "sha256_xform": hashlib.sha256(xout).hexdigest(),
        "sha256_raw_back": hashlib.sha256(raw_back).hexdigest(),
        "block_edges_ok": True,
    }


def main():
    idx = json.loads((RUN / "cases/index.json").read_text(encoding="utf-8"))
    results = []
    failures = []
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
        for pref in ("p1", "p2"):
            if st.get(pref + "_xerr", 0) != 0:
                prob.append(pref + "_xerr")
            if st.get(pref + "_stab_err", 0) != 0:
                prob.append(pref + "_stab_err")

        raw = (RUN / c["raw"]).read_bytes()
        if hashlib.sha256(raw).hexdigest() != c["raw_sha256"]:
            prob.append("raw_sha256")

        if mode in (0, 5):
            if st.get("p1_commit") != 1:
                prob.append("p1_commit=%r" % st.get("p1_commit"))
            if st.get("p1_last") != 1:
                prob.append("p1_last=%r" % st.get("p1_last"))
            if st.get("p1_abort") != 0:
                prob.append("p1_abort=%r" % st.get("p1_abort"))
            info["p1"] = check_stream(name + ":p1", sd / "out.hex", raw, w, h,
                                      c["prep"], c["pred"], st, "p1", prob)
        else:
            if st.get("p1_commit") != 0:
                prob.append("p1_commit=%r" % st.get("p1_commit"))
            if st.get("p1_last") != 0:
                prob.append("p1_last=%r" % st.get("p1_last"))
            if mode in (1, 3, 4) and st.get("p1_abort") != 1:
                prob.append("p1_abort=%r" % st.get("p1_abort"))
            if mode == 2 and st.get("p1_abort") != 0:
                # synchronous reset clears frame_abort_r; it must not fake a commit
                prob.append("p1_abort_after_reset=%r" % st.get("p1_abort"))
            info["p1_partial_outbytes"] = st.get("p1_outbytes")
            if mode == 4:
                if st.get("p1_pending_after_abort") != 1:
                    prob.append("p1_pending_after_abort=%r" % st.get("p1_pending_after_abort"))
                if st.get("p1_commit_after_release") != 0:
                    prob.append("p1_commit_after_release=%r" % st.get("p1_commit_after_release"))
                if st.get("p1_last_after_release") != 0:
                    prob.append("p1_last_after_release=%r" % st.get("p1_last_after_release"))
            raw2 = (RUN / c["raw2"]).read_bytes()
            if hashlib.sha256(raw2).hexdigest() != c["raw2_sha256"]:
                prob.append("raw2_sha256")
            if st.get("p2_commit") != 1 or st.get("p2_last") != 1:
                prob.append("p2_commit/last=%r/%r" % (st.get("p2_commit"), st.get("p2_last")))
            if st.get("p2_abort") != 0:
                prob.append("p2_abort=%r" % st.get("p2_abort"))
            info["p2"] = check_stream(name + ":p2", sd / "out2.hex", raw2, w, h,
                                      c["prep2"], c["pred2"], st, "p2", prob)

        if mode in (0, 5):
            info["cycles"] = st.get("p1_cycles")
            info["stall_cycles"] = st.get("p1_stall")
            if st.get("p1_cycles"):
                info["mbps_187p5"] = (w * 5 // 4 * h) * 187_500_000.0 / st["p1_cycles"] / 1e6
        if mode in (0, 5) and "p1" in info and info["p1"]:
            streams[name] = (sd / "out.hex").read_text(encoding="ascii").strip()

        info["problems"] = prob
        info["verdict"] = "PASS" if not prob else "FAIL"
        if prob:
            failures.append({"case": name, "problems": prob})
        results.append(info)

    bp_ok = streams.get("bp20x5") is not None and streams.get("bp20x5") == streams.get("odd20x5_p1d1")
    if not bp_ok:
        failures.append({"case": "bp20x5", "problems": ["bp_stream_differs"]})

    verdict = "PASS" if not failures else "FAIL"
    out = {
        "verifier": "independent_verify.py (stdlib only, no candidate tools imported)",
        "python": sys.version.split()[0],
        "zlib": zlib.ZLIB_RUNTIME_VERSION,
        "verdict": verdict,
        "bp_equivalence": bp_ok,
        "failures": failures,
        "cases": results,
    }
    (RUN.parents[1] / "test-reports" / "T10.a1-frame-top-r0-evidence" / "independent-result.json").write_text(
        json.dumps(out, indent=2), encoding="utf-8")
    print(json.dumps({"verdict": verdict, "failures": failures, "bp_equivalence": bp_ok}, indent=2))
    return 0 if verdict == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
