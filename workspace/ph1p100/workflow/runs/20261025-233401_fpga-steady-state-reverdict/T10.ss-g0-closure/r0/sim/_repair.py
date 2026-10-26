import pathlib
p = pathlib.Path(__file__).with_name("run_g0.py")
b = p.read_bytes()
lines = b.split(b"\n")
start = None
end = None
for i, l in enumerate(lines):
    if l.startswith(b"    # ------------------------------------------------ content proxy doc"):
        start = i
    if start is not None and b'(OUT / "content-proxy.md").write_text' in l:
        end = i
        break
print("start", start, "end", end)
new = '''    # ------------------------------------------------ content proxy doc
    lines = ["# P3 content proxy (comp-like full-frame)", "",
             "- label: **proxy_not_worst** (proxy content; not a worst/all-content proof).",
             "- input: frozen comp vector 32x4800 B (SHA `%s`), tiled over 1920x1080 by 2-ROI-row block b mod 32 (540 blocks)."
             % proxy.get("inputs", {}).get("in.hex", {}).get("sha256", "?"),
             "- domain: in.hex is transform-domain; the chain has PREP/PRED=1, so the TB inverts with a1_ref.inverse_frame to packed RAW10 and the DUT re-applies the transform; the core consumes the vector byte for byte.",
             "- Python check: forward(inverse(tiled)) == tiled, mismatch=%d." % proxy.get("transform", {}).get("mismatch_bytes"),
             "- fixed-TB check (v1, 1 frame): SS_VEC_MATCH bad=%s checked=%s; t_exp(1) equals R3 (9,234,096)."
             % (v1_vec.get("bad"), v1_vec.get("checked")),
             "- R3 pre-fix TB counter printed bad=691132: a TB-only grouping off-by-one (compared every 3rd sample); it does not touch DUT inputs.",
             "- DUT end-to-end: R3 exported frame header raw_crc/xform_crc/lengths equal the Python expectation; header_crc self-consistent; pass=%s." % hdr_ok,
             "- cross-band: identical blocks are 153,600 B apart, far beyond the core 13-bit (8,192 B) match window; adjacent blocks differ.",
             "- limits: synthetic ramp, single content class; no natural/low-light/noise corpus; real images remain not_proven.",
             "- local codec-throughput rerun (different core.v 79,788 B) gives 374,461 cycles/153,600 B = 2.438 c/B vs frozen 355,261 (2.313 c/B), +5.1%; A2 stays assumed and R3 is the direct measurement."]
    (OUT / "content-proxy.md").write_text("\\n".join(lines) + "\\n", encoding="utf-8")
'''
out = lines[:start] + new.encode("ascii").split(b"\n") + lines[end + 1:]
p.write_bytes(b"\n".join(out))
print("rewritten lines", len(out))
