#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate T10 A+ v1 P1 vectors (synthetic only).

Outputs (under the run task dir):
  vectors/pos/*.raw|.xform|.z1|.rec
  vectors/neg/*.bin
  vectors/vectors.json   (paths, SHA256, expected verdicts, metadata)

No real RAW, no board, no production tree writes. Run:
  python tools/codec/a1_vectors.py --out <task>/p1/vectors
"""
import argparse
import datetime
import json
import struct
import sys
from pathlib import Path

sys.dont_write_bytecode = True

import a1_ref

SEED = 20261020


def lcg_bytes(n, seed):
    x = seed & 0xFFFFFFFF
    out = bytearray(n)
    for i in range(n):
        x = (1103515245 * x + 12345) & 0xFFFFFFFF
        out[i] = (x >> 16) & 0xFF
    return bytes(out)


def samples_flat(w, h, value=512):
    return [value] * (w * h)


def samples_grad(w, h):
    return [((x * 7 + y * 13) & 0x3FF) for y in range(h) for x in range(w)]


def samples_repeat(w, h):
    pat = [100, 200, 300, 400, 500, 600, 700, 800,
           900, 1000, 110, 220, 330, 440, 550, 660]
    return [pat[x % len(pat)] for y in range(h) for x in range(w)]


def samples_texture(w, h):
    tile = [((i * 37 + ((i * i) >> 3)) & 0x3FF) for i in range(64)]
    out = []
    for y in range(h):
        base = (y >> 1) * 13
        odd = 5 if (y & 1) else 0
        for x in range(w):
            v = (tile[(x + base) % 64] + odd) & 0x3FF
            if ((x * 131 + y * 17) % 997) == 0:
                v = (v + ((x + y) & 63)) & 0x3FF
            out.append(v)
    return out


def raw_from_samples(samples, w, h):
    return a1_ref.pack_samples(samples)


def write_file(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def pos_meta(enc, name, files):
    st = enc["stats"]
    return {
        "name": name,
        "kind": "frame",
        "w": enc["w"],
        "h": enc["h"],
        "prep_en": enc["prep_en"],
        "pred_en": enc["pred_en"],
        "stride": enc["stride"],
        "raw_len": enc["raw_len"],
        "xform_len": enc["xform_len"],
        "stream_len": enc["stream_len"],
        "block_count": st["block_count"],
        "expected_block_count": (enc["h"] + 1) // 2,
        "fixed_blocks": st["fixed_blocks"],
        "stored_blocks": st["stored_blocks"],
        "literal_count": st["literal_count"],
        "match_count": st["match_count"],
        "max_match_len": st["max_match_len"],
        "max_match_dist": st["max_match_dist"],
        "tail_bit_offset": st["tail_bit_offset"],
        "tail_pad_bits": st["tail_pad_bits"],
        "ratio_raw_over_stream": enc["ratio_raw_over_stream"],
        "expansion_pct": enc["expansion_pct"],
        "zlib_adler32": enc["zlib_adler32"],
        "raw_crc32": enc["raw_crc32"],
        "xform_crc32": enc["xform_crc32"],
        "stream_crc32": enc["stream_crc32"],
        "files": files,
        "sha256": enc["sha256"],
    }


def make_boundary(pos_dir):
    base = lcg_bytes(2048, SEED ^ 0x5A5A)
    out = bytearray(base)
    w = a1_ref.BitWriter()
    w.bits(1, 1)
    w.bits(1, 2)
    for b in base:
        _emit_lit(w, b)
    _emit_match(w, 10, 2048)
    out += base[:10]
    _emit_match(w, 3, 1)
    out += bytes([out[-1]]) * 3
    _emit_match(w, 258, 1)
    out += bytes([out[-1]]) * 258
    _emit_lit(w, 256)
    tail = w.n
    w.align()
    stream = bytes([a1_ref.ZLIB_CMF, a1_ref.ZLIB_FLG]) + bytes(w.out) + \
        a1_ref.adler32(out).to_bytes(4, "big")
    files = {"stream": "pos/p_tokens_boundary.z1", "out": "pos/p_tokens_boundary.out"}
    write_file(pos_dir / "p_tokens_boundary.z1", stream)
    write_file(pos_dir / "p_tokens_boundary.out", bytes(out))
    return {
        "name": "p_tokens_boundary",
        "kind": "stream_only",
        "purpose": "fixed-Huffman token boundary coverage: literal run, match len 3/258, distance 1/2048, non-byte-aligned tail",
        "out_len": len(out),
        "tail_bit_offset": tail,
        "tail_pad_bits": (8 - tail) % 8,
        "files": files,
        "sha256": {
            "stream": a1_ref.sha256(stream),
            "out": a1_ref.sha256(bytes(out)),
        },
    }


def _emit_lit(w, sym):
    code, nbits = a1_ref.FIXED_LIT[sym]
    w.bits(code, nbits)


def _emit_match(w, length, dist):
    ls, lev, leb = a1_ref.LEN_MAP[length]
    code, nbits = a1_ref.FIXED_LIT[ls]
    w.bits(code, nbits)
    if leb:
        w.bits(lev, leb)
    ds, dev, deb = a1_ref.DIST_MAP[dist]
    code, nbits = a1_ref.FIXED_DIST[ds]
    w.bits(code, nbits)
    if deb:
        w.bits(dev, deb)


def _wrap_raw(body, adler=None, trailer=b"\x00\x00\x00\x00"):
    ad = trailer if adler is None else adler.to_bytes(4, "big")
    return bytes([a1_ref.ZLIB_CMF, a1_ref.ZLIB_FLG]) + body + ad


def make_negatives(neg_dir, base_stream, base_record, base_meta):
    neg = []

    def add_stream(name, data, reason, zlib_expect, mutation):
        rel = "neg/%s.bin" % name
        write_file(neg_dir / (name + ".bin"), data)
        neg.append({
            "name": name,
            "kind": "stream",
            "file": rel,
            "expected_reason": reason,
            "zlib_expectation": zlib_expect,
            "mutation": mutation,
            "sha256": a1_ref.sha256(data),
        })

    def add_record(name, data, reason, mutation):
        rel = "neg/%s.bin" % name
        write_file(neg_dir / (name + ".bin"), data)
        neg.append({
            "name": name,
            "kind": "record",
            "file": rel,
            "expected_reason": reason,
            "zlib_expectation": "n/a",
            "mutation": mutation,
            "base": "p_8x4_grad_prep1_pred1",
            "w": base_meta["w"],
            "h": base_meta["h"],
            "prep_en": base_meta["prep_en"],
            "pred_en": base_meta["pred_en"],
            "sha256": a1_ref.sha256(data),
        })

    add_stream("n_trunc_last_byte", base_stream[:-1], "E_TRUNCATED", "must_fail",
               "drop final Adler byte")
    add_stream("n_trunc_mid", base_stream[:len(base_stream) // 2], "E_TRUNCATED", "must_fail",
               "cut stream in the middle")
    bad_adler = bytearray(base_stream)
    bad_adler[-1] ^= 0xFF
    add_stream("n_bad_adler", bytes(bad_adler), "E_BAD_ADLER", "must_fail",
               "flip final Adler byte")
    add_stream("n_trailing_byte", base_stream + b"\x00", "E_TRAILING_BYTES", "unused_data",
               "append one byte after the single zlib member")

    payload = b"\xAA" * 16
    w = a1_ref.BitWriter()
    w.bits(1, 1)
    w.bits(0, 2)
    w.align()
    body = bytes(w.out) + struct.pack("<HH", len(payload), ((~len(payload)) & 0xFFFF) ^ 1) + payload
    add_stream("n_bad_stored_nlen", _wrap_raw(body), "E_BAD_STORED_NLEN", "must_fail",
               "stored NLEN does not equal ~LEN")

    w = a1_ref.BitWriter()
    w.bits(1, 1)
    w.bits(2, 2)
    w.bits(0, 8)
    w.align()
    add_stream("n_btype_dynamic", _wrap_raw(bytes(w.out)), "E_BAD_BTYPE_DYNAMIC", "must_fail",
               "BTYPE=10 (dynamic Huffman is outside the v1 subset)")

    w = a1_ref.BitWriter()
    w.bits(1, 1)
    w.bits(1, 2)
    _emit_lit(w, 0x41)
    _emit_match(w, 3, 2)
    _emit_lit(w, 256)
    w.align()
    add_stream("n_bad_distance", _wrap_raw(bytes(w.out)), "E_BAD_DISTANCE", "must_fail",
               "match distance 2 with only 1 byte of output")

    w = a1_ref.BitWriter()
    w.bits(1, 1)
    w.bits(1, 2)
    _emit_lit(w, 286)
    _emit_lit(w, 256)
    w.align()
    add_stream("n_bad_length_code", _wrap_raw(bytes(w.out)), "E_BAD_LENGTH_CODE", "must_fail",
               "fixed literal/length symbol 286")

    w = a1_ref.BitWriter()
    w.bits(1, 1)
    w.bits(1, 2)
    _emit_lit(w, 0x41)
    ls, lev, leb = a1_ref.LEN_MAP[3]
    code, nbits = a1_ref.FIXED_LIT[ls]
    w.bits(code, nbits)
    code, nbits = a1_ref.FIXED_DIST[30]
    w.bits(code, nbits)
    _emit_lit(w, 256)
    w.align()
    add_stream("n_bad_distance_code", _wrap_raw(bytes(w.out)), "E_BAD_DISTANCE_CODE", "must_fail",
               "fixed distance symbol 30")

    add_record("n_record_truncated", base_record[:31], "E_RECORD_TRUNCATED",
               "record shorter than 32 B")
    rec = bytearray(base_record)
    rec[0:4] = b"XXXX"
    add_record("n_bad_magic", bytes(rec), "E_BAD_MAGIC", "magic changed")
    rec = bytearray(base_record)
    struct.pack_into("<H", rec, 0x04, 2)
    add_record("n_bad_version", bytes(rec), "E_BAD_VERSION", "version changed to 2")
    rec = bytearray(base_record)
    struct.pack_into("<H", rec, 0x06, 0x8000)
    add_record("n_bad_flags", bytes(rec), "E_BAD_FLAGS", "reserved flag bit 15 set")
    rec = bytearray(base_record)
    rec[0x1C] ^= 0xFF
    add_record("n_bad_header_crc", bytes(rec), "E_BAD_HEADER_CRC", "header CRC flipped")
    rec = bytearray(base_record)
    declared = struct.unpack_from("<I", rec, 0x10)[0]
    struct.pack_into("<I", rec, 0x10, declared - 1)
    add_record("n_bad_stream_len", a1_ref.fix_record_crc(rec), "E_STREAM_LEN_MISMATCH",
               "stream_len decremented by 1 and header CRC repaired")
    rec = bytearray(base_record)
    raw_crc = struct.unpack_from("<I", rec, 0x14)[0]
    struct.pack_into("<I", rec, 0x14, raw_crc ^ 1)
    add_record("n_bad_raw_crc", a1_ref.fix_record_crc(rec), "E_BAD_RAW_CRC",
               "raw_crc32 XOR 1 and header CRC repaired")
    rec = bytearray(base_record)
    xform_crc = struct.unpack_from("<I", rec, 0x18)[0]
    struct.pack_into("<I", rec, 0x18, xform_crc ^ 1)
    add_record("n_bad_xform_crc", a1_ref.fix_record_crc(rec), "E_BAD_XFORM_CRC",
               "xform_crc32 XOR 1 and header CRC repaired")
    return neg


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    outdir = Path(args.out)
    pos = outdir / "pos"
    neg = outdir / "neg"
    pos.mkdir(parents=True, exist_ok=True)
    neg.mkdir(parents=True, exist_ok=True)

    cases = [
        ("p_8x4_flat_prep0_pred0", 8, 4, 0, 0, "flat"),
        ("p_8x4_grad_prep1_pred0", 8, 4, 1, 0, "grad"),
        ("p_8x4_grad_prep1_pred1", 8, 4, 1, 1, "grad"),
        ("p_1920x4_repeat_prep0_pred0", 1920, 4, 0, 0, "repeat"),
        ("p_1920x4_repeat_prep1_pred1", 1920, 4, 1, 1, "repeat"),
        ("p_32x5_tail_prep1_pred1", 32, 5, 1, 1, "grad"),
        ("p_1920x1080_texture_prep1_pred1", 1920, 1080, 1, 1, "texture"),
        ("p_1920x1080_random_prep0_pred0", 1920, 1080, 0, 0, "random"),
    ]

    positives = []
    for name, w, h, prep, pred, kind in cases:
        print("GEN %s %dx%d prep=%d pred=%d kind=%s" % (name, w, h, prep, pred, kind), flush=True)
        stride = w * 5 // 4
        if kind == "random":
            raw = lcg_bytes(stride * h, SEED + w * 7 + h * 13)
        else:
            if kind == "flat":
                s = samples_flat(w, h)
            elif kind == "grad":
                s = samples_grad(w, h)
            elif kind == "repeat":
                s = samples_repeat(w, h)
            elif kind == "texture":
                s = samples_texture(w, h)
            else:
                raise ValueError(kind)
            raw = raw_from_samples(s, w, h)
        enc = a1_ref.encode_frame(raw, w, h, prep, pred)
        files = {
            "raw": "pos/%s.raw" % name,
            "xform": "pos/%s.xform" % name,
            "stream": "pos/%s.z1" % name,
            "record": "pos/%s.rec" % name,
        }
        write_file(outdir / files["raw"], enc["raw"])
        write_file(outdir / files["xform"], enc["xform"])
        write_file(outdir / files["stream"], enc["stream"])
        write_file(outdir / files["record"], enc["record"])
        m = pos_meta(enc, name, files)
        if m["block_count"] != m["expected_block_count"]:
            raise AssertionError("block_count mismatch")
        positives.append(m)
        print("  raw=%d xform=%d stream=%d blocks=%d fixed=%d stored=%d ratio=%.4f maxlen=%d maxdist=%d tail=%d"
              % (m["raw_len"], m["xform_len"], m["stream_len"], m["block_count"],
                 m["fixed_blocks"], m["stored_blocks"], m["ratio_raw_over_stream"],
                 m["max_match_len"], m["max_match_dist"], m["tail_bit_offset"]), flush=True)

    boundary = make_boundary(pos)
    positives.append(boundary)
    print("GEN p_tokens_boundary out=%d tail=%d" % (boundary["out_len"], boundary["tail_bit_offset"]), flush=True)

    base = [p for p in positives if p["name"] == "p_8x4_grad_prep1_pred1"][0]
    base_stream = (outdir / base["files"]["stream"]).read_bytes()
    base_record = (outdir / base["files"]["record"]).read_bytes()
    negatives = make_negatives(neg, base_stream, base_record, base)
    print("GEN negatives=%d" % len(negatives), flush=True)

    doc = {
        "schema": "a1t1-vectors-v1",
        "task_id": "T10.a1-format-ref",
        "generated_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "seed": SEED,
        "marker": "synthetic",
        "note": "All raw frames are synthetic. Declared RGGB phase=0; physical Bayer phase and real RAW remain unknown. Format: p1/format-v1.md.",
        "positives": positives,
        "negatives": negatives,
    }
    write_file(outdir / "vectors.json", json.dumps(doc, indent=2, ensure_ascii=False).encode("utf-8"))
    total = sum(p.get("raw_len", p.get("out_len", 0)) for p in positives)
    print("VECTORS_OK positives=%d negatives=%d total_payload_bytes=%d out=%s"
          % (len(positives), len(negatives), total, outdir), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
