#!/usr/bin/env python3
"""P4 T10.ss-4run-matrix content freeze / RAW10 packing preparation.

Inputs (read-only copies in r0/content/):
  raw_p1d1.bin   C1 full-frame packed RAW10 1920x1080 (grad, PREP/PRED=1)
  raw_rand.bin   C2 full-frame packed RAW10 (rand / incompressible)
  comp_raw.hex / comp_vec.hex   P3 comp proxy (R4 control)

Outputs:
  content/raw40_p1d1.hex, content/raw40_rand.hex   518400 lines of 40-bit
      {b4,b3,b2,b1,b0} groups, same byte order as the source raw.bin
  out/content-map.json   sources, geometry, packing, mapping, SHA, CRCs
"""
import hashlib
import json
import pathlib
import sys
import zlib

sys.dont_write_bytecode = True

HERE = pathlib.Path(__file__).resolve().parent
R0 = HERE.parent
CONTENT = R0 / "content"
OUT = R0 / "out"
sys.path.insert(0, str(HERE))
import ref_a1_ref as a1ref  # noqa: E402

W, H = 1920, 1080
STRIDE = W * 5 // 4
GROUPS = STRIDE * H // 5          # 518400
ROW_GROUPS = STRIDE // 5          # 480

FROZEN = {
    "raw_p1d1.bin": ("061b0dfce062d5cd9231e2f0eccee112c189f64487e9b928f99e1531ccf91f8d", 2592000),
    "raw_rand.bin": ("8fe204b715d08285b5918d7745e01195c1925b18ef0d19b9fcfb59ff06f0fad5", 2592000),
    "in.hex": ("edbfdeaedb06824ced20ad76b260979e95e1322d6f6e3bab5e7a951a268f9849", 614400),
    "in.meta": ("e98c9a1c3e0fe621c9aa65aaadbcacbef13c2437a0bbbafcde17d2ff471f80fe", 330),
    "in.xform": ("b836b51df0bc98045f3768cf497bb5a76f88fa301e0598c63514284e2fbfba7a", 153600),
    "comp_raw.hex": ("e3d9094643e3d7d3881ab527abfa0d7e296348895c71eca757cbf911a595eea1", 6220800),
    "comp_vec.hex": ("a91cd406585d54cb2ed9cc760eb88abfcfc6faf135265684f93a6c20a98595b8", 368640),
}
P3_PROXY = {
    "raw_sha256": "9498c16c73917291f17e466a1f6e63fb7d523b9070e403038779d068248f585b",
    "tiled_xform_sha256": "02bdf021e0aed452e53cecb0f6baf22c2dc0ccc7631802f9f67775beecaddafc",
    "raw_crc32": 3613527589,
    "xform_crc32": 3038348232,
}


def sha_bytes(b):
    return hashlib.sha256(b).hexdigest()


def read_hex40(path):
    vals = []
    for line in pathlib.Path(path).read_text(encoding="ascii").split():
        vals.append(int(line, 16))
    return vals


def group_bytes(v):
    return bytes(((v >> 0) & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF,
                  (v >> 24) & 0xFF, (v >> 32) & 0xFF))


def check_pack_identity(g):
    b0, b1, b2, b3, b4 = g
    p0 = (b0 << 2) | (b4 & 0x3)
    p1 = (b1 << 2) | ((b4 >> 2) & 0x3)
    p2 = (b2 << 2) | ((b4 >> 4) & 0x3)
    p3 = (b3 << 2) | ((b4 >> 6) & 0x3)
    rep = bytes((p0 >> 2, p1 >> 2, p2 >> 2, p3 >> 2,
                 ((p3 & 3) << 6) | ((p2 & 3) << 4) | ((p1 & 3) << 2) | (p0 & 3)))
    return rep


def prep_raw(tag, src_name):
    src = CONTENT / src_name
    raw = src.read_bytes()
    want_sha, want_len = FROZEN[src_name]
    got_sha = sha_bytes(raw)
    if len(raw) != want_len or got_sha != want_sha:
        raise SystemExit("%s frozen source mismatch bytes=%d sha=%s" % (src_name, len(raw), got_sha))
    if len(raw) != GROUPS * 5:
        raise SystemExit("%s is not %d x 5 B" % (src_name, GROUPS))

    hex_path = CONTENT / ("raw40_%s.hex" % tag)
    lines = []
    for i in range(GROUPS):
        g = raw[i * 5:(i + 1) * 5]
        lines.append("%02x%02x%02x%02x%02x" % (g[4], g[3], g[2], g[1], g[0]))
    text = "\n".join(lines) + "\n"
    hex_path.write_text(text, encoding="ascii")

    # decode the written hex back to bytes and compare with the source
    back = bytearray()
    bad = 0
    for ln in text.split():
        v = int(ln, 16)
        g = group_bytes(v)
        if check_pack_identity(g) != g:
            bad += 1
        back += g
    back = bytes(back)
    mismatch = sum(1 for a, b in zip(back, raw) if a != b) + abs(len(back) - len(raw))

    xform = a1ref.transform_frame(raw, W, H, 1, 1)
    if len(xform) != len(raw):
        raise SystemExit("transform length change")
    # forward/inverse round-trip on the same frozen model
    inv = a1ref.inverse_frame(xform, W, H, 1, 1)
    rt = sum(1 for a, b in zip(inv, raw) if a != b) + abs(len(inv) - len(raw))

    rec = {
        "source_path": str(src),
        "source_bytes": len(raw),
        "source_sha256": got_sha,
        "frozen_expected_sha256": want_sha,
        "source_match": got_sha == want_sha,
        "geometry": {"W": W, "H": H, "stride_bytes": STRIDE,
                     "row_groups": ROW_GROUPS, "groups": GROUPS,
                     "bytes_per_group": 5, "pixels_per_group": 4,
                     "packing": "packed RAW10: b0..b3 = p0..p3[9:2]; b4 = "
                                "{p3[1:0],p2[1:0],p1[1:0],p0[1:0]}; "
                                "40-bit group {b4,b3,b2,b1,b0}"},
        "raw40_hex": {"path": str(hex_path), "bytes": hex_path.stat().st_size,
                      "lines": len(lines), "sha256": sha_bytes(hex_path.read_bytes())},
        "roundtrip": {"decoded_bytes": len(back), "mismatch_bytes": mismatch,
                      "group_pack_identity_bad": bad},
        "model_roundtrip_mismatch_bytes": rt,
        "expected_header": {
            "raw_len": len(raw), "xform_len": len(xform),
            "raw_crc32": zlib.crc32(raw) & 0xFFFFFFFF,
            "xform_crc32": zlib.crc32(xform) & 0xFFFFFFFF,
        },
        "label": "full_frame_raw_synthetic",
        "proxy_labels": ["proxy_not_natural", "proxy_not_worst"],
    }
    return rec


def prep_comp():
    hex_text = (CONTENT / "in.hex").read_bytes()
    vec = bytes(int(x, 16) for x in hex_text.split())
    xform = (CONTENT / "in.xform").read_bytes()
    if vec != xform:
        raise SystemExit("in.hex != in.xform")
    raw = b"".join(group_bytes(v) for v in read_hex40(CONTENT / "comp_raw.hex"))
    vecg = b"".join(group_bytes(v) for v in read_hex40(CONTENT / "comp_vec.hex"))
    if len(vecg) != len(vec):
        raise SystemExit("comp_vec.hex != frozen vector length")
    BLOCK = STRIDE * 2
    tiled = b"".join(vec[(b % 32) * BLOCK:(b % 32) * BLOCK + BLOCK]
                     for b in range(H // 2))
    fwd = a1ref.transform_frame(raw, W, H, 1, 1)
    fwd_mismatch = sum(1 for a, b in zip(fwd, tiled) if a != b) + abs(len(fwd) - len(tiled))
    rec = {
        "source_paths": {k: str(CONTENT / k) for k in
                         ("in.hex", "in.meta", "in.xform", "comp_raw.hex", "comp_vec.hex")},
        "in_hex_equals_in_xform": True,
        "vector_bytes": len(vecg), "vector_sha256": sha_bytes(vecg),
        "tiling": "block b (2 ROI rows, 4800 B) -> vector block b mod 32 over 540 blocks",
        "raw_bytes": len(raw), "raw_sha256": sha_bytes(raw),
        "tiled_xform_bytes": len(tiled), "tiled_xform_sha256": sha_bytes(tiled),
        "raw_crc32": zlib.crc32(raw) & 0xFFFFFFFF,
        "xform_crc32": zlib.crc32(tiled) & 0xFFFFFFFF,
        "forward_transform_mismatch_bytes": fwd_mismatch,
        "p3_proxy_expected": P3_PROXY,
        "matches_p3_proxy": (sha_bytes(raw) == P3_PROXY["raw_sha256"]
                             and sha_bytes(tiled) == P3_PROXY["tiled_xform_sha256"]
                             and (zlib.crc32(raw) & 0xFFFFFFFF) == P3_PROXY["raw_crc32"]
                             and (zlib.crc32(tiled) & 0xFFFFFFFF) == P3_PROXY["xform_crc32"]),
        "expected_header": {"raw_len": len(raw), "xform_len": len(tiled),
                            "raw_crc32": zlib.crc32(raw) & 0xFFFFFFFF,
                            "xform_crc32": zlib.crc32(tiled) & 0xFFFFFFFF},
        "label": "proxy_not_worst",
        "proxy_labels": ["proxy_not_natural", "proxy_not_worst"],
    }
    return rec


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    srcs = {}
    for name, (want, nbytes) in FROZEN.items():
        p = CONTENT / name
        b = p.read_bytes()
        ok = len(b) == nbytes and sha_bytes(b) == want
        srcs[name] = {"path": str(p), "bytes": len(b), "sha256": sha_bytes(b),
                      "frozen_expected": want, "match": ok}
        if not ok:
            raise SystemExit("content source mismatch: %s" % name)

    c1 = prep_raw("p1d1", "raw_p1d1.bin")
    c2 = prep_raw("rand", "raw_rand.bin")
    comp = prep_comp()
    c1["id"] = "C1"; c2["id"] = "C2"; comp["id"] = "C3-C7"

    out = {
        "created": "2026-10-26",
        "task": "T10.ss-4run-matrix",
        "run": "r0",
        "geometry": {"CAM_W": 3864, "CAM_H": 2192, "ROI_X": 972, "ROI_Y": 556,
                     "W": W, "H": H, "LINE_GAP": 16, "FRAME_GAP": 400,
                     "raw_bytes_per_frame": W * H * 5 // 4},
        "mapping": {
            "tb_rule": "ROI group (roi_row=y-ROI_Y, roi_g=g-GX) -> raw_mem[roi_row*480+roi_g]",
            "raw40_line": "line i -> group i of the row-major packed RAW10 frame",
            "out_of_roi": "tap_pix=0 on the 966-4 non-ROI groups of each camera row",
            "bit_order": "tap_pix = {b4,b3,b2,b1,b0}; matches a1_ref.pack_samples and the "
                         "P1 TB smp() packing",
            "c1_choice": "C1 uses f1080p_p1d1 only; f1080p_p1d0/f1080p_p0 share the same "
                         "raw.bin SHA and differ only in PREP/PRED config (fixed 1/1 in the DUT)",
        },
        "sources": srcs,
        "content": {"C1": c1, "C2": c2, "C3_C7": comp},
        "self_check": {
            "c1_roundtrip_mismatch": c1["roundtrip"]["mismatch_bytes"],
            "c2_roundtrip_mismatch": c2["roundtrip"]["mismatch_bytes"],
            "c1_group_pack_bad": c1["roundtrip"]["group_pack_identity_bad"],
            "c2_group_pack_bad": c2["roundtrip"]["group_pack_identity_bad"],
            "comp_matches_p3": comp["matches_p3_proxy"],
            "tb_expects": {
                "C1": "SS_RAW_MATCH bad=0 checked=518400",
                "C2": "SS_RAW_MATCH bad=0 checked=518400",
                "C3_C7": "SS_VEC_MATCH bad=0 checked=518400",
            },
        },
        "labels": {
            "C1": ["full_frame_raw_synthetic", "proxy_not_natural", "proxy_not_worst"],
            "C2": ["full_frame_raw_synthetic", "proxy_not_natural", "proxy_not_worst"],
            "C3_C7": ["proxy_not_natural", "proxy_not_worst"],
            "note": "no natural-image corpus in this run; C1/C2 are full-frame synthetic "
                    "packed RAW10 images, C3-C7 is the P3 transform-domain comp proxy",
        },
    }
    (OUT / "content-map.json").write_text(json.dumps(out, indent=2) + "\n")
    print(json.dumps({
        "c1_hex_sha": c1["raw40_hex"]["sha256"], "c1_rt": c1["roundtrip"]["mismatch_bytes"],
        "c2_hex_sha": c2["raw40_hex"]["sha256"], "c2_rt": c2["roundtrip"]["mismatch_bytes"],
        "c1_crc": c1["expected_header"], "c2_crc": c2["expected_header"],
        "comp_ok": comp["matches_p3_proxy"],
    }, indent=2))


if __name__ == "__main__":
    main()
