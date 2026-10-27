"""Independent verifier for T10.ss-g0-prod-content r0 (tester-owned, does not modify candidates).

Checks, using only third-party/independent reconstruction:
  1. raw40 hex -> packed RAW10 bin round trip (5B/4px), per-group mismatch count.
  2. bin geometry/stride, crc32 vs content-map and vs DUT export header raw_crc.
  3. Independent re-derivation of the mosaic straight from the source JPEG
     (crop -> LANCZOS -> RGGB mosaic -> round(s*1023/255)), several
     channel hypotheses; exact pixel match count decides which one the
     candidate actually used.
  4. DUT export header struct: locate raw_crc little-endian, verify
     header CRC over the prefix, verify raw_len/xform_len/stream_len.
  5. content-map / content-audit label + SHA spot checks.
  6. DUT 12 source copies + TB vs every same-named .v in the project.
"""
import hashlib, json, os, struct, sys, zlib
import numpy as np
from PIL import Image

RUN = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\T10.ss-g0-prod-content\r0"
OUT = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\test-reports\T10.ss-g0-prod-content"
ROOT = r"D:\fpga\ph1p100"
G = 518400
res = {}

def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

def unpack_groups(bin_path):
    buf = np.fromfile(bin_path, dtype=np.uint8)
    assert buf.size == G * 5, buf.size
    g = buf.reshape(G, 5)
    b0, b1, b2, b3, b4 = (g[:, i].astype(np.uint32) for i in range(5))
    p = np.empty((G, 4), dtype=np.uint32)
    p[:, 0] = (b0 << 2) | (b4 & 3)
    p[:, 1] = (b1 << 2) | ((b4 >> 2) & 3)
    p[:, 2] = (b2 << 2) | ((b4 >> 4) & 3)
    p[:, 3] = (b3 << 2) | ((b4 >> 6) & 3)
    return g, p

def pack_groups(p):
    p = p.astype(np.uint32)
    assert p.max() <= 1023, p.max()
    out = np.empty((p.shape[0], 5), dtype=np.uint8)
    out[:, 0] = (p[:, 0] >> 2) & 0xFF
    out[:, 1] = (p[:, 1] >> 2) & 0xFF
    out[:, 2] = (p[:, 2] >> 2) & 0xFF
    out[:, 3] = (p[:, 3] >> 2) & 0xFF
    out[:, 4] = (((p[:, 3] & 3) << 6) | ((p[:, 2] & 3) << 4) | ((p[:, 1] & 3) << 2) | (p[:, 0] & 3)).astype(np.uint8)
    return out.reshape(-1)

def hex_to_groups(hex_path):
    vals = np.empty(G, dtype=np.uint64)
    with open(hex_path, "r") as f:
        for i, line in enumerate(f):
            assert i < G, "too many lines"
            vals[i] = int(line.strip(), 16)
    assert len(vals) == G, "line count"
    g = np.empty((G, 5), dtype=np.uint8)
    for i in range(5):
        g[:, i] = ((vals >> np.uint64(8 * i)) & np.uint64(0xFF)).astype(np.uint8)
    return vals, g


def mosaic_from(img, mode):
    a = np.asarray(img, dtype=np.uint32)          # H,W,3 sRGB8
    H, W, _ = a.shape
    yy, xx = np.mgrid[0:H, 0:W]
    r = a[:, :, 0]; gg = a[:, :, 1]; b = a[:, :, 2]
    if mode == "native_rggb_channels":
        m = np.where(((yy + xx) % 2 == 0),
                     np.where(yy % 2 == 0, r, b), gg)
    elif mode == "luma601_all":
        m = (299 * r + 587 * gg + 114 * b) // 1000
    elif mode == "mean_all":
        m = (r + gg + b) // 3
    elif mode == "native_rggb_luma_in_cfa":
        # CFA-selected channel replaced by 601 luma of that pixel
        lum = (299 * r + 587 * gg + 114 * b) // 1000
        m = lum
    else:
        raise ValueError(mode)
    q = np.rint(m.astype(np.float64) * 1023.0 / 255.0).astype(np.uint32)
    np.clip(q, 0, 1023, out=q)
    return q

# ---------- 1/2. hex<->bin ----------
hexb = {}
for cls, hexn, binn in (("N", "raw40_n.hex", "raw_n.bin"), ("L", "raw40_l.hex", "raw_l.bin")):
    hp = os.path.join(RUN, "content", hexn)
    bp = os.path.join(RUN, "content", binn)
    vals, gh = hex_to_groups(hp)
    buf = np.fromfile(bp, dtype=np.uint8)
    gb, p = unpack_groups(bp)
    re = pack_groups(p)
    mismatch = int(np.count_nonzero(re != buf))
    hex_mismatch = int(np.count_nonzero(gh != gb))
    # also re-pack from reconstructed pixels and re-serialize to hex text
    repack_vals = np.zeros(G, dtype=np.uint64)
    for i in range(5):
        repack_vals |= gb[:, i].astype(np.uint64) << np.uint64(8 * i)
    hex_text_mismatch = int(np.count_nonzero(repack_vals != vals))
    hexb[cls] = dict(
        bin_sha256=sha(bp), hex_sha256=sha(hp),
        bin_bytes=int(buf.size), hex_lines=int(vals.size),
        unpack_repack_mismatch=mismatch,
        hexgroup_vs_bin_mismatch=hex_mismatch,
        repack_hex_vs_source_hex_mismatch=hex_text_mismatch,
        bin_crc32="%08x" % (zlib.crc32(buf.tobytes()) & 0xFFFFFFFF),
        px_min=int(p.min()), px_max=int(p.max()), px_mean=round(float(p.mean()), 3),
        px_std=round(float(p.std()), 3),
    )
res["hex_bin"] = hexb
res["N_L_bin_differ_bytes"] = int(np.count_nonzero(
    np.fromfile(os.path.join(RUN, "content", "raw_n.bin"), dtype=np.uint8) !=
    np.fromfile(os.path.join(RUN, "content", "raw_l.bin"), dtype=np.uint8)))

# ---------- 3. independent image re-derivation ----------
cm = json.load(open(os.path.join(RUN, "content-map.json")))
res["content_map_frames"] = {k: {"frame_sha_unique": len(set(v["frame_sha256"])),
                                 "frames_declared": v["frames"],
                                 "bin_sha": v["raw_bin"]["sha256"]} for k, v in cm["content"].items()}
img_res = {}
for cls, name, mode in (("N", "img102.jpg", "rgb"), ("L", "img105.jpg", "rgb")):
    src = os.path.join("C:\\Windows\\Web\\Screen", name)
    im = Image.open(src)
    info = dict(path=src, size=list(im.size), pil_mode=im.mode, file_bytes=os.path.getsize(src),
                file_sha256=sha(src))
    if cls == "N":
        im2 = im.crop((0, 200, 6400, 3800)).resize((1920, 1080), Image.LANCZOS)
    else:
        im2 = im.convert("RGB")
    im2 = im2.convert("RGB")
    ref = unpack_groups(os.path.join(RUN, "content", "raw_n.bin" if cls == "N" else "raw_l.bin"))[1]
    ref_flat = ref.reshape(-1)
    hyps = {}
    for hname in ("native_rggb_channels", "luma601_all", "mean_all"):
        q = mosaic_from(im2, hname).reshape(-1)
        mm = int(np.count_nonzero(q != ref_flat))
        hyps[hname] = dict(mismatch=mm, total=int(ref_flat.size),
                           max_abs_diff=int(np.max(np.abs(q.astype(np.int64) - ref_flat.astype(np.int64)))))
    info["hypotheses"] = hyps
    img_res[cls] = info
res["image_rederive"] = img_res
res["content_audit_sha"] = sha(os.path.join(RUN, "content-audit.json"))

# ---------- 4. DUT export header ----------
hdr = {}
for cls, fn, stlen in (("N", "n.hdr", 1677912), ("L", "l.hdr", 2156868)):
    raw = open(os.path.join(RUN, "sim", "caps", fn), "rb").read()
    assert raw and b"\n" in raw, len(raw)
    by = bytes(int(x, 16) for x in raw.decode().split())
    idx = by.find(struct.pack("<I", zlib.crc32(
        np.fromfile(os.path.join(RUN, "content", "raw_n.bin" if cls == "N" else "raw_l.bin"),
                    dtype=np.uint8).tobytes()) & 0xFFFFFFFF))
    # header crc: find a 4-byte little-endian word at the end of the 88-byte header
    cand = {}
    for n in (40, 44, 84, 88):
        if n + 4 <= len(by):
            cand[n] = zlib.crc32(by[:n]) & 0xFFFFFFFF
    hdr[cls] = dict(bytes_captured=len(by), raw_crc_offset=idx,
                    first40=by[:40].hex(), hdr_crc_over_prefix=cand,
                    raw_len_le=struct.unpack_from("<I", by, 40)[0] if len(by) >= 44 else None,
                    u32_at_44=struct.unpack_from("<I", by, 44)[0] if len(by) >= 48 else None,
                    u32_at_48=struct.unpack_from("<I", by, 48)[0] if len(by) >= 52 else None)
res["header"] = hdr

# ---------- 6. DUT/TB provenance ----------
same = {}
names = {}
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in (".git", "__pycache__")]
    for fn in filenames:
        if fn.endswith(".v"):
            names.setdefault(fn, []).append(os.path.join(dirpath, fn))
src = os.path.join(RUN, "src")
for fn in sorted(os.listdir(src)):
    if not fn.endswith(".v"):
        continue
    p = os.path.join(src, fn)
    h = sha(p)
    matches = [q for q in names.get(fn, []) if sha(q) == h]
    same[fn] = dict(sha256=h, n_same_named_in_repo=len(names.get(fn, [])),
                    byte_identical_to=matches[:4])
res["src_provenance"] = same

json.dump(res, open(os.path.join(OUT, "evidence-content-verify.json"), "w"), indent=2)
print(json.dumps({k: res[k] for k in ("hex_bin", "N_L_bin_differ_bytes", "content_map_frames",
                                      "image_rederive", "header")}, indent=2))
print("--- provenance ---")
for k, v in res["src_provenance"].items():
    print(k, v["n_same_named_in_repo"], [os.path.relpath(m, ROOT) for m in v["byte_identical_to"]])
