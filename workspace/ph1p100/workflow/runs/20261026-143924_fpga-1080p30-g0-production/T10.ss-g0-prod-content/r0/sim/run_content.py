#!/usr/bin/env python3
"""P1 T10.ss-g0-prod-content bounded driver (run 20261026-143924_fpga-1080p30-g0-production).

Subcommands (each writes only inside this task's r0/ tree and %TEMP%/opencode/ss-g0-prod-content/):
  audit     content-source audit -> content-audit.json (no real sensor RAW; classify every candidate)
  prep      derive N (natural scene) / L (low light) 1920x1080 packed RAW10 + raw40 hex + content-map.json
  verify    byte-level self check (hex<->bin, pack identity, mosaic fidelity, packer cross-check vs P4)
  compile   vlib + vlog 12 frozen DUT/model sources + frozen tb_ss_4run.v  (exclusive TEMP library)
  precheck  1-frame precheck, hard cap 300 s, marked precheck (never 4-frame evidence)
  run <n|l> one full-size 4-frame run (FRAMES=4 CONTENT=2 PACING=0 SINK=1 CAPTURE=0, 2700 s hard timeout)
  analyze   parse raw logs/caps -> out/content-verdict.json / out/runs.json / out/content-table.csv
  manifest  freeze manifest-r0.json (stopped_modifying=true, active_commands=0)

Metric definitions follow fpga-design-guide.md section 3 (frozen):
  S_ss = (S_23+S_34)/2 ; tail(k)=t_exp(k)-t_enc(k) ; tail_mean=mean(tail(2..4))
  tail_frac = tail_mean/S_ss ; sink_limited = (tail_frac >= 0.50)
  C_ss = 2592000*187.5e6/S_ss/1e6 MB/s ; margin_G0 = 6250000/S_ss-1 ; margin_G25 ref only
"""
import csv
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time
import zlib

sys.dont_write_bytecode = True

HERE = pathlib.Path(__file__).resolve().parent
R0 = HERE.parent
SRC = R0 / "src"
SIM = HERE
LOGS = R0 / "logs"
CAPS = SIM / "caps"
CONTENT = R0 / "content"
OUT = R0 / "out"

ROOT = pathlib.Path(r"D:/fpga/ph1p100")
RUNROOT = ROOT / "workflow/runs/20261026-143924_fpga-1080p30-g0-production"
P4 = ROOT / "workflow/runs/20261025-233401_fpga-steady-state-reverdict/T10.ss-4run-matrix/r0"
P3 = ROOT / "workflow/runs/20261025-233401_fpga-steady-state-reverdict/T10.ss-g0-closure/r0"
B11 = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read/r0"
CSI2SRC = ROOT / "fpga/csi2/src"

MS = pathlib.Path(r"D:\intelFPGA\18.1\modelsim_ase\win32aloem")
TEMP = pathlib.Path(os.environ.get("TEMP", r"C:\Users\czz\AppData\Local\Temp"))
WORK = TEMP / "opencode" / "ss-g0-prod-content" / "work"

CLOCK_HZ = 187.5e6
G0_CYCLES = 6250000.0
G25_CYCLES = 5000000.0
G0_MBPS = 77.76
G25_MBPS = 97.20
RAW_FRAME_BYTES = 2592000
RAW_BAND_BYTES = 2594706          # per input-index erratum / guide section 3 (NOT 2594750)
SINK_MAX_MBPS = 93.75             # frozen TB sink ceiling (a1_uart_export 2 clk_a1/byte, SINK=1)
W, H = 1920, 1080
STRIDE, GROUPS_PER_ROW, GROUPS = 2400, 480, 518400
HEX_LINES = GROUPS

# 12 compiled DUT/model sources (the 13th, p2_a1_board_top.v, is board-only and not compiled)
SRC12 = ["a1_raw_crop.v", "a1_ddr_slot_store.v", "a1_uart_export.v",
         "camera_a1_uart_top.v", "cam_diag_mailbox.v", "a1_frame_top.v",
         "a1_deflate_core.v", "p2_ddr_bridge.v", "a1_ddr_arb2.v",
         "capture_async_fifo.v", "p2_paxi_model_b11.v", "a1_ddr_model.v"]
TB = "tb_ss_4run.v"
COMPILE = SRC12 + [TB]

# external origin candidates for byte-identity verification of each frozen copy
ORIGIN_DIRS = [B11 / "changed-src", B11 / "sim", CSI2SRC]

RUNS = {
    "n": dict(tag="n", content=2, raw40="raw40_n.hex", content_id="N",
              labels=["natural_scene_image", "proxy_not_natural_raw", "not_sensor_raw",
                      "proxy_not_worst"],
              mode="N_natural_scene_slotfree"),
    "l": dict(tag="l", content=2, raw40="raw40_l.hex", content_id="L",
              labels=["low_light_natural_scene", "proxy_not_natural_raw", "not_sensor_raw",
                      "proxy_not_worst"],
              mode="L_low_light_natural_slotfree"),
}

FROZEN = {  # values taken from the P4 driver PROTECTED table (independent of this task)
    str(P3 / "manifest-r2.json"): "3c8377a484f42a132b6434cf975710662b8c92871d31bcdaabd9b8ba7aec4961",
    str(P3 / "src/tb_ss_g0.v"): "a565c6f25f5d8ac16ce8dd8042f35395c6018a23d1093448077b0e90b79bd3d0",
    str(P4 / "manifest-r0.json"): None,   # prefix/suffix asserted instead (d353c61a..6dd1)
    str(P4 / "src/tb_ss_4run.v"): None,   # provenance copy source; sha recorded after copy
}

IMAGE_SRC = {
    "N": {"path": r"C:\Windows\Web\Screen\img102.jpg", "label": "natural_scene_image",
          "desc": "dusk lake / snow slope treeline / sun / water reflection (Windows sample asset)"},
    "L": {"path": r"C:\Windows\Web\Screen\img105.jpg", "label": "low_light_natural_scene",
          "desc": "night long-exposure star trails over pier + lake (Windows sample asset)"},
}

MAXCYC = 48000000
RUN_TIMEOUT_S = 2700
PRECHECK_TIMEOUT_S = 300
MAX_FULL_RUNS = 2


# ------------------------------------------------------------------ helpers
def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def jdump(p, obj):
    pathlib.Path(p).parent.mkdir(parents=True, exist_ok=True)
    pathlib.Path(p).write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def jload(p, default=None):
    p = pathlib.Path(p)
    if not p.exists():
        return default
    return json.loads(p.read_text(encoding="utf-8"))


def cmdlog(rec):
    SIM.mkdir(parents=True, exist_ok=True)
    rec = dict(rec)
    rec["logged_at"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    with open(SIM / "commands.jsonl", "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")


def run_proc(argv, cwd, log_path, timeout, note=""):
    log_path = pathlib.Path(log_path)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    out_path = log_path.with_suffix(log_path.suffix + ".out")
    t0 = time.monotonic()
    timed_out = False
    rc = None
    with open(out_path, "wb") as out:
        proc = subprocess.Popen([str(x) for x in argv], cwd=str(cwd), stdout=out,
                                stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            rc = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                           capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
            rc = 124
    el = time.monotonic() - t0
    rec = {"argv": [str(x) for x in argv], "cwd": str(cwd), "rc": rc, "timed_out": timed_out,
           "seconds": round(el, 1), "timeout_s": timeout, "log": str(log_path), "note": note}
    cmdlog(rec)
    return rc, el, timed_out


def toolenv():
    env = os.environ.copy()
    env["MODEL_TECH"] = str(MS)
    env["MODELSIM"] = str(SIM / "modelsim.ini")
    env["PATH"] = str(MS) + os.pathsep + env.get("PATH", "")
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    return env


# ------------------------------------------------------------------ packing
def pack_groups(samples):
    """40-bit group packing: b0..b3 = p[0..3][9:2]; b4 = {p3[1:0],p2[1:0],p1[1:0],p0[1:0]}.
    Returns bytes in on-the-wire order b0,b1,b2,b3,b4 (5 B per 4 px)."""
    out = bytearray()
    n = len(samples)
    for i in range(0, n, 4):
        p0, p1, p2, p3 = samples[i], samples[i + 1], samples[i + 2], samples[i + 3]
        out.append(p0 >> 2)
        out.append(p1 >> 2)
        out.append(p2 >> 2)
        out.append(p3 >> 2)
        out.append(((p3 & 3) << 6) | ((p2 & 3) << 4) | ((p1 & 3) << 2) | (p0 & 3))
    return bytes(out)


def unpack_group_hex(v):
    """40-bit group value -> 4x10-bit samples (frozen inverse)."""
    b0 = v & 0xFF
    b1 = (v >> 8) & 0xFF
    b2 = (v >> 16) & 0xFF
    b3 = (v >> 24) & 0xFF
    b4 = (v >> 32) & 0xFF
    return ((b0 << 2) | (b4 & 3), (b1 << 2) | ((b4 >> 2) & 3),
            (b2 << 2) | ((b4 >> 4) & 3), (b3 << 2) | ((b4 >> 6) & 3))


def group_value_from_bytes(b):
    """5 bytes b0..b4 -> 40-bit hex value {b4,b3,b2,b1,b0}."""
    return (b[4] << 32) | (b[3] << 24) | (b[2] << 16) | (b[1] << 8) | b[0]


# ------------------------------------------------------------------ audit
RAW_EXT = {".raw", ".dng", ".cr2", ".nef", ".arw", ".raf", ".orf", ".sr2"}
SKIP_DIR = {".git", "node_modules", "__pycache__", ".venv"}


def walk_sensor_raw(root, deadline_s=150):
    t0 = time.monotonic()
    hits, nfiles, truncated = [], 0, False
    stack = [pathlib.Path(root)]
    while stack:
        if time.monotonic() - t0 > deadline_s:
            truncated = True
            break
        d = stack.pop()
        try:
            with os.scandir(d) as it:
                for e in it:
                    try:
                        if e.is_dir(follow_symlinks=False):
                            if e.name not in SKIP_DIR:
                                stack.append(pathlib.Path(e.path))
                        else:
                            nfiles += 1
                            ext = os.path.splitext(e.name)[1].lower()
                            if ext in RAW_EXT:
                                hits.append({"path": e.path, "bytes": e.stat().st_size})
                    except OSError:
                        continue
        except OSError:
            continue
    return {"root": str(root), "seconds": round(time.monotonic() - t0, 1),
            "files_scanned": nfiles, "truncated": truncated, "hits": hits,
            "extensions": sorted(RAW_EXT)}


def cmd_audit():
    from PIL import Image
    import numpy as np
    audit = {
        "task": "T10.ss-g0-prod-content", "run": "r0", "created": time.strftime("%Y-%m-%d"),
        "run_dir": str(RUNROOT),
        "rule": "No real IMX415/sensor RAW exists in this repo. UI screenshots, abstract "
                "renders, synthetic vectors and image-derived Bayer must never be labelled "
                "natural sensor RAW.",
        "sensor_raw_search": walk_sensor_raw(ROOT),
        "candidates": [],
    }

    def add(cid, path, kind, labels, usable, note, probe=True):
        p = pathlib.Path(path)
        rec = {"id": cid, "path": str(p), "kind": kind, "labels": labels,
               "usable_as_content": usable, "note": note}
        if p.exists() and p.is_file():
            rec["bytes"] = p.stat().st_size
            rec["sha256"] = sha(p)
            if probe:
                try:
                    with Image.open(p) as im:
                        rec["image"] = {"size": list(im.size), "mode": im.mode,
                                        "format": im.format}
                except Exception as e:
                    rec["image"] = {"error": str(e)[:120]}
        else:
            rec["exists"] = False
        audit["candidates"].append(rec)

    A1 = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-adler-smem/r0/p3/cases"
    add("C1", A1 / "f1080p_p1d1/raw.bin", "full_frame_raw_synthetic",
        ["full_frame_raw_synthetic", "proxy_not_natural", "not_sensor_raw", "proxy_not_worst"],
        False, "P4 baseline synthetic gradient full frame (PREP/PRED=1). Reference only, "
               "NOT natural content and NOT worse-case.", probe=False)
    add("C2", A1 / "f1080p_rand/raw.bin", "full_frame_raw_synthetic",
        ["full_frame_raw_synthetic", "proxy_not_natural", "not_sensor_raw", "proxy_not_worst"],
        False, "Synthetic stored-random full frame. Upper bound on entropy, but not a natural "
               "or worst-case content proof.", probe=False)
    add("C3_C7", ROOT / "work/parallel-sim-20261024-2204/codec-throughput/comp/in.hex",
        "proxy_transport_stream", ["proxy_not_natural", "not_sensor_raw", "proxy_not_worst"],
        False, "P3 trimmed comp-vector proxy (per-frame stream fragment, not a frame).", probe=False)
    sdir = ROOT / "workflow/runs/20261019-2117_runD_batch2_continue/board/t02/samples"
    k = 0
    for p in sorted(sdir.rglob("*.png")) if sdir.exists() else []:
        k += 1
        add("UI%02d" % k, p, "ui_screenshot", ["ui_screenshot", "not_natural_scene",
                                               "not_sensor_raw"], False,
            "Board-run desktop capture (Ubuntu VNC + TD timing-analyzer window); planner "
            "visually verified T1_cwc1. Explicitly forbidden as natural content.")
    for p in sorted((ROOT / "fpga/csi2/_scratch").glob("sony_*.png")):
        k += 1
        add("SCR%02d" % k, p, "test_graphic", ["test_graphic", "not_natural_scene",
                                               "not_sensor_raw"], False,
            "Sony test graphic / chart in _scratch; not a scene.")
    for name in ("img100.jpg", "img101.jpg", "img103.jpg", "img104.jpg"):
        add("BLOOM_" + name, pathlib.Path(r"C:\Windows\Web\Screen") / name, "abstract_render",
            ["abstract_render", "not_natural_scene", "not_sensor_raw"], False,
            "Win11 Bloom abstract render (planner verified img100). Excluded.")
    add("N", IMAGE_SRC["N"]["path"], "natural_scene_image",
        ["natural_scene_image", "proxy_not_natural_raw", "not_sensor_raw", "proxy_not_worst",
         "display_referred"], True, IMAGE_SRC["N"]["desc"], probe=True)
    add("L", IMAGE_SRC["L"]["path"], "low_light_natural_scene",
        ["low_light_natural_scene", "proxy_not_natural_raw", "not_sensor_raw", "proxy_not_worst",
         "display_referred"], True, IMAGE_SRC["L"]["desc"], probe=True)
    # format-ref synthetic vectors found by the sensor-RAW sweep (documented, not used)
    audit["sensor_raw_search"]["hits_classification"] = \
        "all hits are synthetic codec format-reference vectors " \
        "(p_1920x1080_texture/random/... under T10.a1-format-ref p1/vectors), " \
        "no camera/sensor RAW container (*.dng/cr2/nef/arw) was found"
    audit["no_real_sensor_raw"] = True
    audit["conclusion"] = (
        "real_sensor_raw = ABSENT. Only image-derived Bayer (N/L) is admissible, and it must "
        "carry proxy_not_natural_raw + not_sensor_raw + proxy_not_worst. No UI screenshot, "
        "abstract render or synthetic vector is labelled natural scene.")
    jdump(R0 / "content-audit.json", audit)
    print("audit candidates=%d sensor_raw_hits=%d files=%d truncated=%s" % (
        len(audit["candidates"]), len(audit["sensor_raw_search"]["hits"]),
        audit["sensor_raw_search"]["files_scanned"], audit["sensor_raw_search"]["truncated"]))
    for c in audit["candidates"]:
        print("  %-12s %-24s %-28s usable=%s" % (c["id"], c["kind"],
                                                  (c.get("image") or {}).get("size", "-"),
                                                  c["usable_as_content"]))


# ------------------------------------------------------------------ prep
def load_1080(path):
    from PIL import Image
    im = Image.open(path).convert("RGB")
    w0, h0 = im.size
    info = {"source_size": [w0, h0], "source_mode": im.mode}
    if (w0, h0) == (W, H):
        info.update({"crop": None, "resize": None,
                     "note": "native 1920x1080, no crop and no rescale"})
        return im, info
    ar = W / H
    if w0 / h0 > ar:
        cw, ch = int(round(h0 * ar)), h0
    else:
        cw, ch = w0, int(round(w0 / ar))
    left, top = (w0 - cw) // 2, (h0 - ch) // 2
    info.update({"crop": {"box": [left, top, left + cw, top + ch], "size": [cw, ch],
                          "rule": "centre crop to 16:9"},
                 "resize": {"to": [W, H], "filter": "PIL LANCZOS"}})
    return im.crop((left, top, left + cw, top + ch)).resize((W, H), Image.LANCZOS), info


def derive(cid):
    import numpy as np
    spec = IMAGE_SRC[cid]
    im, info = load_1080(spec["path"])
    arr = np.asarray(im, dtype=np.int32)                     # H,W,3 sRGB 8-bit
    code = (arr * 1023 + 127) // 255                         # display-referred -> 10 bit
    code = np.clip(code, 0, 1023)
    mosaic = np.empty((H, W), dtype=np.uint16)
    mosaic[0::2, 0::2] = code[0::2, 0::2, 0]                 # RGGB: (0,0)=R
    mosaic[0::2, 1::2] = code[0::2, 1::2, 1]                 # (0,1)=G
    mosaic[1::2, 0::2] = code[1::2, 0::2, 1]                 # (1,0)=G
    mosaic[1::2, 1::2] = code[1::2, 1::2, 2]                 # (1,1)=B
    flat = mosaic.reshape(-1).tolist()
    return mosaic, flat, info


def cmd_prep():
    import numpy as np
    CONTENT.mkdir(parents=True, exist_ok=True)
    cmap = {
        "task": "T10.ss-g0-prod-content", "run": "r0", "created": time.strftime("%Y-%m-%d"),
        "geometry": {"width": W, "height": H, "pixels": W * H, "stride_bytes": STRIDE,
                     "groups_per_row": GROUPS_PER_ROW, "groups_per_frame": GROUPS,
                     "bytes_per_frame": RAW_FRAME_BYTES, "bytes_per_px": 1.25},
        "packing": {"rule": "5 B / 4 px: b0..b3 = p0..p3[9:2]; b4 = "
                            "{p3[1:0],p2[1:0],p1[1:0],p0[1:0]}",
                    "group_bit_order": "40-bit group = {b4,b3,b2,b1,b0}; bytes on the wire are "
                                       "b0,b1,b2,b3,b4 (b0 first)",
                    "hex_line": "one 10-digit hex group per line, 518400 lines, leftmost digit "
                                "= b4 (frozen P4 raw40 convention)",
                    "reference": "fpga-design-guide.md section 1; P4 prep_content.py roundtrip"},
        "cfa": {"pattern": "RGGB", "phase": "row0/col0 = R",
                "note": "description only; the DUT predicts same-colour neighbours and is not "
                        "modified"},
        "bit_depth": {"bits": 10, "range": [0, 1023], "saturation": "clip to 1023, no dither",
                      "encode": "code = round(sRGB8 * 1023 / 255)  (display-referred, sRGB "
                                "transfer kept as declared gamma; no de-gamma/linearisation). "
                                "Declared choice: keeping the sRGB-encoded value preserves "
                                "full spatial detail and contrast (higher entropy, harder for "
                                "the codec) instead of crushing mid-tones into low linear codes."},
        "labels_rule": "every derived class carries proxy_not_natural_raw + not_sensor_raw + "
                       "proxy_not_worst; none of them is a sensor RAW or a worst-case proof",
        "frames": {"count": 4, "repeat": "same derived frame driven 4 times (steady-state window)",
                   "note": "no temporal variation; a real 30 fps stream would differ per frame, "
                           "which this proxy does not model"},
        "content": {},
    }
    for cid in ("N", "L"):
        spec = IMAGE_SRC[cid]
        mosaic, flat, info = derive(cid)
        raw = pack_groups(flat)
        assert len(raw) == RAW_FRAME_BYTES, (cid, len(raw))
        binp = CONTENT / ("raw_%s.bin" % cid.lower())
        binp.write_bytes(raw)
        hexp = CONTENT / ("raw40_%s.hex" % cid.lower())
        with open(hexp, "w", newline="\n") as f:
            for i in range(0, len(raw), 5):
                f.write("%010x\n" % group_value_from_bytes(raw[i:i + 5]))
        crc = zlib.crc32(raw) & 0xFFFFFFFF
        code = mosaic.reshape(-1)
        cmap["content"][cid] = {
            "id": cid,
            "labels": [spec["label"], "proxy_not_natural_raw", "not_sensor_raw",
                       "proxy_not_worst", "display_referred"],
            "source": {"path": spec["path"], "bytes": pathlib.Path(spec["path"]).stat().st_size,
                       "sha256": sha(spec["path"]), "description": spec["desc"],
                       "provenance": "Microsoft Windows local sample asset under "
                                     "C:/Windows/Web/Screen (read-only, copied parameters "
                                     "only into this run)"},
            "derive": dict(info, cfa="RGGB", bits=10,
                           quantisation="round(sRGB8*1023/255), clip 1023, no dither"),
            "raw_bin": {"path": "content/raw_%s.bin" % cid.lower(), "bytes": len(raw),
                        "sha256": hashlib.sha256(raw).hexdigest(), "crc32": "%08x" % crc},
            "raw40_hex": {"path": "content/raw40_%s.hex" % cid.lower(),
                          "bytes": hexp.stat().st_size, "lines": HEX_LINES,
                          "sha256": sha(hexp)},
            "frames": 4,
            "frame_sha256": [hashlib.sha256(raw).hexdigest()] * 4,
            "stats": {"min": int(code.min()), "max": int(code.max()),
                      "mean": round(float(code.mean()), 3),
                      "std": round(float(code.std()), 3),
                      "dark_frac_lt_5pct": round(float((code < 51).mean()), 6),
                      "dark_frac_lt_10pct": round(float((code < 102).mean()), 6),
                      "sat_frac_eq_1023": round(float((code == 1023).mean()), 6),
                      "nonzero_frac": round(float((code > 0).mean()), 6)},
            "noise_injection": "none (deterministic derivation from the image; a real sensor "
                               "frame would carry shot/read noise, so this proxy is NOT a "
                               "low-light worst-case proof)",
        }
        print("%s %s src=%s raw=%d B hex=%d B lines=%d dark=%.4f sat=%.5f" % (
            cid, spec["label"], info.get("source_size"), len(raw), hexp.stat().st_size,
            HEX_LINES, cmap["content"][cid]["stats"]["dark_frac_lt_5pct"],
            cmap["content"][cid]["stats"]["sat_frac_eq_1023"]))
    cmap["raw_band_bytes"] = {"bytes": RAW_BAND_BYTES,
                              "note": "2592000 raw + 2700 (540 groups x 5) + 6 + 44 header; "
                                      "per input-index erratum (P4 wrote 2594750)"}
    jdump(R0 / "content-map.json", cmap)
    print("content-map ->", R0 / "content-map.json")


# ------------------------------------------------------------------ verify
def cmd_verify():
    cmap = jload(R0 / "content-map.json", {})
    checks = []
    for cid in ("N", "L"):
        ent = cmap["content"][cid]
        binp = CONTENT / ("raw_%s.bin" % cid.lower())
        hexp = CONTENT / ("raw40_%s.hex" % cid.lower())
        raw = binp.read_bytes()
        # 1) geometry
        geom_ok = (len(raw) == RAW_FRAME_BYTES)
        # 2) hex -> bin byte identity + group pack identity + sample fidelity
        hex_mismatch, pack_bad, sample_bad, n = 0, 0, 0, 0
        src_samples = None
        with open(hexp, "r") as f:
            for line in f:
                v = int(line.strip(), 16)
                p = unpack_group_hex(v)
                b = bytes((p[0] >> 2, p[1] >> 2, p[2] >> 2, p[3] >> 2,
                           ((p[3] & 3) << 6) | ((p[2] & 3) << 4) | ((p[1] & 3) << 2) | (p[0] & 3)))
                if b != raw[n * 5:n * 5 + 5]:
                    hex_mismatch += 1
                if pack_groups(list(p)) != b:
                    pack_bad += 1
                if max(p) > 1023:
                    pack_bad += 1
                n += 1
        # 3) sample fidelity: rebuild the mosaic from the bin and compare with derive()
        import numpy as np
        mosaic, flat, _info = derive(cid)
        mism = 0
        for i in range(GROUPS):
            p = unpack_group_hex(group_value_from_bytes(raw[i * 5:i * 5 + 5]))
            base = i * 4
            if (p[0] != flat[base] or p[1] != flat[base + 1] or
                    p[2] != flat[base + 2] or p[3] != flat[base + 3]):
                mism += 1
        rec = {"content": cid, "bin_bytes": len(raw), "hex_lines": n,
               "hex_expected_lines": HEX_LINES,
               "bin_sha256_matches_map": hashlib.sha256(raw).hexdigest() == ent["raw_bin"]["sha256"],
               "hex_sha256_matches_map": sha(hexp) == ent["raw40_hex"]["sha256"],
               "crc32": "%08x" % (zlib.crc32(raw) & 0xFFFFFFFF),
               "crc32_matches_map": ("%08x" % (zlib.crc32(raw) & 0xFFFFFFFF)) == ent["raw_bin"]["crc32"],
               "geometry_ok": geom_ok,
               "hex_to_bin_mismatch_groups": hex_mismatch,
               "group_pack_identity_bad": pack_bad,
               "mosaic_sample_mismatch_groups": mism,
               "roundtrip_mismatch_total": hex_mismatch + pack_bad + mism}
        checks.append(rec)
        print("%s geom=%s hex_bad=%d pack_bad=%d sample_bad=%d lines=%d sha_ok=%s crc_ok=%s" % (
            cid, geom_ok, hex_mismatch, pack_bad, mism, n,
            rec["bin_sha256_matches_map"], rec["crc32_matches_map"]))

    # 4) packer cross-check against the frozen P4 artifact (independent generator)
    xchk = {"available": False}
    try:
        p4bin = (P4 / "content/raw_p1d1.bin").read_bytes()
        p4hex = (P4 / "content/raw40_p1d1.hex").read_text().split()
        mine = ["%010x" % group_value_from_bytes(p4bin[i:i + 5]) for i in range(0, len(p4bin), 5)]
        bad = sum(1 for a, b in zip(mine, p4hex) if a != b) + abs(len(mine) - len(p4hex))
        xchk = {"available": True, "ref_bin": str(P4 / "content/raw_p1d1.bin"),
                "ref_hex": str(P4 / "content/raw40_p1d1.hex"),
                "groups": len(mine), "mismatch": bad,
                "pass": bad == 0}
    except Exception as e:
        xchk = {"available": False, "error": str(e)[:160]}
    print("packer_cross_check_vs_P4 pass=%s mismatch=%s" % (xchk.get("pass"), xchk.get("mismatch")))

    # 5) frozen copy integrity (12 DUT sources + TB) against their external origins
    src_rec = []
    for f in COMPILE:
        p = SRC / f
        rec = {"file": f, "exists": p.exists()}
        if p.exists():
            rec["bytes"] = p.stat().st_size
            rec["sha256"] = sha(p)
            orig = None
            for d in ORIGIN_DIRS:
                if (d / f).exists():
                    orig = d / f
                    break
            if orig is not None:
                rec["origin"] = str(orig)
                rec["origin_sha256"] = sha(orig)
                rec["match_origin"] = rec["origin_sha256"] == rec["sha256"]
            else:
                rec["origin"] = None
                rec["match_origin"] = None
        src_rec.append(rec)
    drift = [r["file"] for r in src_rec if r.get("match_origin") is False]
    protected = []
    for path, want in FROZEN.items():
        p = pathlib.Path(path)
        if not p.exists():
            protected.append({"path": path, "exists": False})
            continue
        got = sha(p)
        rec = {"path": path, "bytes": p.stat().st_size, "sha256": got, "expected": want}
        if want is None:
            if path.endswith("manifest-r0.json"):
                rec["prefix_ok"] = got.startswith("d353c61a") and got.endswith("6dd1")
                rec["expected"] = "d353c61a...6dd1 (P4 manifest, prefix/suffix assert)"
                rec["match"] = rec["prefix_ok"]
            else:
                rec["match"] = None
                rec["note"] = "provenance source of the frozen TB copy"
        else:
            rec["match"] = got == want
        protected.append(rec)
    out = {"task": "T10.ss-g0-prod-content", "created": time.strftime("%Y-%m-%d"),
           "content_checks": checks,
           "content_all_clean": all(c["roundtrip_mismatch_total"] == 0 and c["geometry_ok"]
                                    and c["bin_sha256_matches_map"] and c["hex_sha256_matches_map"]
                                    and c["crc32_matches_map"] for c in checks),
           "packer_cross_check_p4": xchk,
           "frozen_src": src_rec, "frozen_src_drift": drift,
           "frozen_src_note": "a1_ddr_arb2.v / capture_async_fifo.v are unchanged upstream "
                              "sources; p2_paxi_model_b11.v and a1_ddr_model.v are the b11 "
                              "behavioural DDR models. match_origin=null means the file has no "
                              "external origin in the searched dirs (TB is this run's frozen "
                              "copy of the P4 TB).",
           "protected_inputs": protected,
           "protected_drift": [r["path"] for r in protected if r.get("match") is False],
           "drift_status": "ok"}
    if drift or out["protected_drift"]:
        out["drift_status"] = "DRIFT"
    jdump(R0 / "input-verified.json", out)
    print("verify content_all_clean=%s src_drift=%d protected_drift=%s status=%s" % (
        out["content_all_clean"], len(drift), out["protected_drift"], out["drift_status"]))


# ------------------------------------------------------------------ compile / run
def compile_all():
    WORK.mkdir(parents=True, exist_ok=True)
    LOGS.mkdir(parents=True, exist_ok=True)
    rc, el, to = run_proc([MS / "vlib.exe", "work"], WORK, LOGS / "vlib.log", 300, "vlib")
    if rc != 0:
        raise SystemExit("vlib failed rc=%s" % rc)
    argv = [MS / "vlog.exe", "-sv", "-work", "work", "+define+SIMULATION"] + \
           [SRC / f for f in COMPILE]
    rc, el, to = run_proc(argv, WORK, LOGS / "vlog.log", 1200, "vlog")
    txt = (LOGS / "vlog.log.out").read_text(errors="replace") \
        if (LOGS / "vlog.log.out").exists() else ""
    errs = len(re.findall(r"\*\* Error", txt))
    print("compile rc=%s %.1fs errors=%d" % (rc, el, errs))
    if rc != 0 or errs:
        raise SystemExit("compile failed")


def spent_full_seconds():
    total, n = 0.0, 0
    p = SIM / "commands.jsonl"
    if p.exists():
        for line in p.read_text(encoding="utf-8").splitlines():
            try:
                rec = json.loads(line)
            except Exception:
                continue
            if any("tb_ss_4run" in str(a) for a in rec.get("argv", [])) and \
                    rec.get("timeout_s") == RUN_TIMEOUT_S:
                total += rec.get("seconds", 0.0)
                n += 1
    return total, n


def vsim_run(key, frames, content, caps_prefix, timeout, capture=0, pacing=0, sink=1,
             raw40=None, note=""):
    if timeout == RUN_TIMEOUT_S:
        spent, n = spent_full_seconds()
        if n >= MAX_FULL_RUNS:
            print("FULL_RUN_BUDGET_EXHAUSTED n=%d spent=%.0fs" % (n, spent))
            raise SystemExit(3)
        if spent >= 5400:
            print("VSIM_WALL_BUDGET_EXHAUSTED spent=%.0fs" % spent)
            raise SystemExit(3)
    CAPS.mkdir(parents=True, exist_ok=True)
    LOGS.mkdir(parents=True, exist_ok=True)
    stat = CAPS / (caps_prefix + ".stats")
    evt = CAPS / (caps_prefix + ".evt")
    hdr = CAPS / (caps_prefix + ".hdr")
    log = LOGS / (caps_prefix + ".log")
    argv = [MS / "vsim.exe", "-c", "-lib", "work", "-l", log, "tb_ss_4run",
            "+STAT=" + str(stat), "+EVT=" + str(evt), "+HDR=" + str(hdr)]
    if raw40:
        argv.append("+RAW40=" + str(CONTENT / raw40))
    argv += ["-gFRAMES=%d" % frames, "-gCONTENT=%d" % content, "-gPACING=%d" % pacing,
             "-gSINK=%d" % sink, "-gCAPTURE=%d" % capture,
             "-gMAX_CYCLES=%d" % MAXCYC, "-do", "run -all; quit -f"]
    rc, el, to = run_proc(argv, WORK, log, timeout, note or caps_prefix)
    print("%s rc=%s %.1fs timeout=%s stats=%s" % (caps_prefix, rc, el, to, stat.exists()))
    txt = log.read_text(errors="replace") if log.exists() else ""
    for pat in ("SS_STALL", "B11_FULL_TIMEOUT", "SS_RAW_MATCH", "B11_FULL_RESULT",
                "SS_STATS"):
        for m in re.finditer(pat + r"[^\n]*", txt):
            print("   ", m.group(0)[:160])
    return {"rc": rc, "seconds": round(el, 1), "timed_out": to, "stats_exists": stat.exists()}


def cmd_precheck():
    r = vsim_run("precheck", frames=1, content=2, caps_prefix="precheck",
                 timeout=PRECHECK_TIMEOUT_S, raw40=RUNS["n"]["raw40"],
                 note="precheck: 1 frame, NOT 4-frame evidence")
    r["precheck"] = True
    jdump(OUT / "precheck.json", r)


def cmd_run(key):
    cfg = RUNS[key]
    r = vsim_run(key, frames=4, content=cfg["content"], caps_prefix=cfg["tag"],
                 timeout=RUN_TIMEOUT_S, raw40=cfg["raw40"], note=cfg["mode"])
    r["tag"] = cfg["tag"]
    r["mode"] = cfg["mode"]
    db = jload(OUT / "run-status.json", {})
    db[cfg["tag"]] = r
    jdump(OUT / "run-status.json", db)


# ------------------------------------------------------------------ analyze
def parse_stats(p):
    st = {}
    for tok in pathlib.Path(p).read_text().split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            try:
                st[k] = int(v, 0)
            except ValueError:
                st[k] = v
    return st


def header_check(tag, ent):
    hp = CAPS / (tag + ".hdr")
    if not hp.exists():
        return {"available": False}
    rawb = bytes(int(x, 16) for x in hp.read_text().split())
    if len(rawb) < 44:
        return {"available": False, "bytes": len(rawb)}
    u32 = lambda o: int.from_bytes(rawb[o:o + 4], "little")
    got = {"raw_len": u32(16), "xform_len": u32(20), "stream_len": u32(24),
           "raw_crc": u32(28), "xform_crc": u32(32), "stream_crc": u32(36),
           "header_crc": u32(40)}
    raw_crc = int(ent["raw_bin"]["crc32"], 16)
    hcrc = zlib.crc32(rawb[0:40]) & 0xFFFFFFFF
    ok = (got["raw_len"] == RAW_FRAME_BYTES and got["xform_len"] == RAW_FRAME_BYTES
          and got["raw_crc"] == raw_crc and hcrc == got["header_crc"])
    return {"available": True, "bytes": len(rawb), "got": got,
            "expected": {"raw_len": RAW_FRAME_BYTES, "xform_len": RAW_FRAME_BYTES,
                         "raw_crc": raw_crc, "raw_crc_hex": ent["raw_bin"]["crc32"],
                         "header_crc": hcrc},
            "raw_crc_matches_content_bin": got["raw_crc"] == raw_crc,
            "header_crc_ok": hcrc == got["header_crc"],
            "stream_crc_present": got["stream_crc"] != 0,
            "pass": ok}


def analyze_run(key, cmap):
    cfg = RUNS[key]
    tag = cfg["tag"]
    ent = cmap["content"][cfg["content_id"]]
    statp = CAPS / (tag + ".stats")
    logp = LOGS / (tag + ".log")
    m = {"run": key, "content_id": cfg["content_id"], "mode": cfg["mode"],
         "labels": ent["labels"], "cfg": {"frames": 4, "content": cfg["content"],
                                          "pacing": 0, "sink": 1, "capture": 0,
                                          "raw40": cfg["raw40"]}}
    if not statp.exists():
        m.update({"partial": True, "steady_state_status": "not_measured",
                  "G0": "G0_not_proven", "G0_why": "no stats file (run aborted/timed out)"})
        return m
    st = parse_stats(statp)
    txt = logp.read_text(errors="replace") if logp.exists() else ""
    ev = {}
    for mm in re.finditer(r"SS_EVT t=(\d+) kind=(sof|cam_end|pub|read|enc|exp) frame=(\d+)", txt):
        ev.setdefault(mm.group(2), {})[int(mm.group(3))] = int(mm.group(1))
    meta = re.search(r"SS_META t_rst=(\d+)", txt)
    rawm = re.search(r"SS_RAW_MATCH bad=(\d+) checked=(\d+) drv_groups=(\d+)", txt)
    stall = "SS_STALL" in txt
    tmo = "B11_FULL_TIMEOUT" in txt
    passm = re.search(r"B11_FULL_RESULT pass=(\d+)", txt)
    t_rst = int(meta.group(1)) if meta else None

    t_exp = [None] + [ev.get("exp", {}).get(k) for k in range(1, 5)]
    t_enc = [None] + [ev.get("enc", {}).get(k) for k in range(1, 5)]
    t_sof = [None] + [ev.get("sof", {}).get(k) for k in range(1, 5)]
    t_pub = [None] + [ev.get("pub", {}).get(k) for k in range(1, 5)]
    nfr = max([k for k in range(1, 5) if t_exp[k] is not None] or [0])
    m.update({"counters": st, "t_rst": t_rst, "t_sof": t_sof, "t_enc": t_enc,
              "t_exp": t_exp, "t_pub": t_pub,
              "ss_raw_match": ({"bad": int(rawm.group(1)), "checked": int(rawm.group(2)),
                                "drv_groups": int(rawm.group(3))} if rawm else None),
              "stall_marker": stall, "timeout_marker": tmo,
              "result_marker": passm.group(0) if passm else None,
              "frames_exported": nfr,
              "command_seconds": (jload(OUT / "run-status.json", {}) or {}).get(tag, {}).get("seconds"),
              "timed_out": (jload(OUT / "run-status.json", {}) or {}).get(tag, {}).get("timed_out")})
    m["L_cold"] = (t_exp[1] - t_rst) if (t_exp[1] and t_rst is not None) else None
    S23 = (t_exp[3] - t_exp[2]) if (t_exp[2] and t_exp[3]) else None
    S34 = (t_exp[4] - t_exp[3]) if (t_exp[3] and t_exp[4]) else None
    m["S_23"], m["S_34"] = S23, S34
    m["S_2"] = (t_exp[2] - t_exp[1]) if (t_exp[1] and t_exp[2]) else None
    Sss = None
    if S23 is not None and S34 is not None:
        Sss = (S23 + S34) / 2.0
    m["S_ss"] = Sss
    tails = {}
    for k in range(1, 5):
        if t_exp[k] is not None and t_enc[k] is not None:
            tails[k] = t_exp[k] - t_enc[k]
    m["export_tail"] = tails
    steady = [tails[k] for k in (2, 3, 4) if k in tails]
    m["export_tail_mean"] = (sum(steady) / len(steady)) if steady else None
    hdr = header_check(tag, ent)
    m["header_check"] = hdr
    rm = m["ss_raw_match"] or {}
    self_ok = (rm.get("bad") == 0 and rm.get("checked") == GROUPS)
    m["self_check"] = rm
    m["self_check_pass"] = self_ok

    valid = (st.get("cap") == 4 and st.get("enc") == 4 and st.get("exported") == 4
             and st.get("read") == GROUPS and st.get("raw_drop") == 0
             and st.get("cmp_drop") == 0 and st.get("geom") == 0 and st.get("err") == 0
             and st.get("dup") == 0 and st.get("wd") == 0 and st.get("raw_pub") == 4)
    m["counters_ok"] = valid
    m["partial"] = bool(m.get("timed_out") or stall or tmo or nfr < 4)
    m["steady_state_status"] = ("measured" if (nfr == 4 and not m["partial"]) else
                                ("partial" if nfr else "not_measured"))
    if Sss:
        m["capacity_MBps"] = RAW_FRAME_BYTES * CLOCK_HZ / Sss / 1e6
        m["fps"] = CLOCK_HZ / Sss
        m["margin_G0_pct"] = (G0_CYCLES / Sss - 1) * 100
        m["margin_G25_pct_ref"] = (G25_CYCLES / Sss - 1) * 100
        m["S_spread_pct"] = (100.0 * (max(S23, S34) - min(S23, S34)) / Sss) if S23 and S34 else None
    if Sss and m["export_tail_mean"]:
        m["tail_frac"] = m["export_tail_mean"] / Sss
        m["tail_frac_pct"] = 100.0 * m["tail_frac"]
    m["sink_limited"] = (None if m.get("tail_frac") is None
                         else bool(m["tail_frac"] >= 0.50))
    m["sink_limited_rule"] = "tail_frac = tail_mean(2..4)/S_ss >= 0.50 (frozen, guide section 3)"
    nfr_eff = nfr or 1
    if nfr == 0:
        m["payload_bytes_per_frame"] = None
        m["compression_ratio"] = None
        m["measured_export_MBps"] = None
        m["needed_sink_MBps_25ms"] = None
        m["needed_sink_MBps_33ms"] = None
        m["export_payload_lower_bound_bytes"] = None
        te = t_enc[1]
        if te:
            m["export_payload_lower_bound_bytes"] = (12000000 - te) // 2
            m["export_payload_lower_bound_note"] = (
                "export of frame 1 started no later than t_enc(1)=%d and had NOT completed when "
                "the frozen 12,000,000-cycle watchdog fired at cycle 12,000,001; at 2 clk_a1 per "
                "byte the stream is therefore > (12,000,000-t_enc(1))/2 bytes" % te)
    else:
        m["payload_bytes_per_frame"] = (st.get("exp_bytes") or 0) / nfr_eff
        m["compression_ratio"] = (RAW_FRAME_BYTES / m["payload_bytes_per_frame"]
                                  if m["payload_bytes_per_frame"] else None)
        if m["export_tail_mean"]:
            m["measured_export_MBps"] = (m["payload_bytes_per_frame"] /
                                         (min(m["export_tail_mean"], Sss or 1e30) / CLOCK_HZ) / 1e6)
        m["needed_sink_MBps_25ms"] = m["payload_bytes_per_frame"] / 25.0e-3 / 1e6
        m["needed_sink_MBps_33ms"] = m["payload_bytes_per_frame"] / (1000.0 / 30.0) / 1e-3 / 1e6

    # G0 (guide section 3, three-way)
    if m["partial"] or not valid or not self_ok or not hdr.get("pass", False):
        g0, why = "G0_not_proven", (
            "run incomplete/partial=%s counters_ok=%s self_check=%s header_pass=%s" % (
                m["partial"], valid, self_ok, hdr.get("pass", False)))
    elif m["sink_limited"]:
        g0, why = "G0_not_proven", (
            "sink_limited: tail_frac=%.1f%% >= 50%%; S_ss is governed by the frozen 93.75 MB/s "
            "TB sink, so it is not capacity evidence" % m["tail_frac_pct"])
    elif Sss <= G0_CYCLES:
        g0, why = "G0_feasible_for_scope", "S_ss=%.1f <= 6,250,000 measured under this scope" % Sss
    else:
        g0, why = "G0_not_closed", ("S_ss=%.1f > 6,250,000; gap %.1f cycles (%.3f%% of G0)" % (
            Sss, Sss - G0_CYCLES, 100.0 * (Sss - G0_CYCLES) / Sss))
    m["G0"], m["G0_why"] = g0, why
    m["G0_scope"] = ("content=%s(derived from a display-referred image, NOT sensor RAW); "
                     "pacing=TB wait_slot_free (NOT production free-run); sink=frozen "
                     "93.75 MB/s TB proxy (NOT a production sink); DDR=behavioural 256-bit "
                     "PAXI model; core=single a1 @187.5 MHz; stream=single" % m["content_id"])
    return m


def cmd_analyze():
    cmap = jload(R0 / "content-map.json", {})
    res = {}
    for key in ("n", "l"):
        res[key] = analyze_run(key, cmap)
        m = res[key]
        print("%s S_ss=%s tail_mean=%s tail_frac=%s%% sink_limited=%s C_ss=%s G0=%s" % (
            key, m.get("S_ss"), m.get("export_tail_mean"),
            None if m.get("tail_frac_pct") is None else round(m["tail_frac_pct"], 1),
            m.get("sink_limited"),
            None if m.get("capacity_MBps") is None else round(m["capacity_MBps"], 4),
            m.get("G0")))

    clk_per_byte_9375 = (1 / SINK_MAX_MBPS) * CLOCK_HZ * 1e6
    raw_band = {
        "bytes_per_frame": RAW_BAND_BYTES,
        "cycles_at_93_75MBps": round(RAW_BAND_BYTES / SINK_MAX_MBPS / 1e6 * CLOCK_HZ),
        "ms_at_93_75MBps": round(RAW_BAND_BYTES / SINK_MAX_MBPS / 1e6 * 1e3, 3),
        "pct_of_g0_at_93_75": round(RAW_BAND_BYTES / SINK_MAX_MBPS / 1e6 * CLOCK_HZ / G0_CYCLES * 100, 2),
        "cycles_at_103_79MBps": round(RAW_BAND_BYTES / 103.79 / 1e6 * CLOCK_HZ),
        "ms_at_103_79MBps": round(RAW_BAND_BYTES / 103.79 / 1e6 * 1e3, 3),
        "pct_of_g0_at_103_79": round(RAW_BAND_BYTES / 103.79 / 1e6 * CLOCK_HZ / G0_CYCLES * 100, 2),
        "note": "computed from bytes and the frozen clock; guide section 3 lists 5,000,000 "
                "cycles at 103.79 MB/s, which is arithmetically 4,687,500 cycles (25.0 ms). "
                "The 93.75/103.79 percentages (83.03%/75.00%) are unchanged; the cycle figure "
                "in the guide is an erratum for P3 to confirm. No frozen value was altered here.",
    }

    verdict = {
        "task": "T10.ss-g0-prod-content", "run": "r0",
        "created": time.strftime("%Y-%m-%d"),
        "hard_gate": {"G0_cycles": G0_CYCLES, "G0_MBps": G0_MBPS,
                      "G25_cycles_ref_only": G25_CYCLES, "G25_MBps_ref_only": G25_MBPS,
                      "clock_MHz": 187.5, "sink_ceiling_MBps": SINK_MAX_MBPS},
        "metric_definitions": {
            "S_ss": "(S_23+S_34)/2 with S_ab = t_exp(b)-t_exp(a); t from +EVT SS_EVT lines",
            "tail": "t_exp(k)-t_enc(k); tail_mean = mean over k=2,3,4",
            "tail_frac": "tail_mean/S_ss",
            "sink_limited": "tail_frac >= 0.50 (frozen)",
            "C_ss": "2592000*187.5e6/S_ss/1e6 MB/s",
            "margin_G0": "6250000/S_ss - 1"},
        "content_classes": {},
        "raw_band": raw_band,
        "headline": None,
        "not_proven": [
            "real sensor RAW (no IMX415/sensor RAW exists in this repo)",
            "full / worst-case content (N/L are image-derived proxies, proxy_not_worst)",
            "production free-run pacing (TB wait_slot_free is not the production pacing)",
            "production sink >=103.79 MB/s (frozen TB sink is 93.75 MB/s)",
            "real DDR/PAXI sustained, PCIe/UART transport, board-level, dual stream, RK/NPU",
            "192.642 MHz clock, resources and timing (no TD in this task)"],
    }
    for key, label in (("n", "N"), ("l", "L")):
        m = res[key]
        verdict["content_classes"][label] = {
            "content_id": label, "labels": m["labels"], "mode": m["mode"],
            "frames": 4, "frames_exported": m["frames_exported"],
            "S_2": m.get("S_2"), "S_23": m.get("S_23"), "S_34": m.get("S_34"),
            "S_ss": m.get("S_ss"), "S_spread_pct": m.get("S_spread_pct"),
            "L_cold": m.get("L_cold"),
            "export_tail": m.get("export_tail"), "tail_mean": m.get("export_tail_mean"),
            "tail_frac": m.get("tail_frac"), "sink_limited": m.get("sink_limited"),
            "capacity_MBps": m.get("capacity_MBps"), "fps": m.get("fps"),
            "margin_G0_pct": m.get("margin_G0_pct"),
            "margin_G25_pct_ref": m.get("margin_G25_pct_ref"),
            "payload_bytes_per_frame": m.get("payload_bytes_per_frame"),
            "compression_ratio": m.get("compression_ratio"),
            "measured_export_MBps": m.get("measured_export_MBps"),
            "needed_sink_MBps_33ms": m.get("needed_sink_MBps_33ms"),
            "needed_sink_MBps_25ms": m.get("needed_sink_MBps_25ms"),
            "export_payload_lower_bound_bytes": m.get("export_payload_lower_bound_bytes"),
            "export_payload_lower_bound_note": m.get("export_payload_lower_bound_note"),
            "counters": {k: m["counters"].get(k) for k in
                         ("cap", "enc", "exported", "raw_pub", "raw_drop", "cmp_drop",
                          "geom", "err", "read", "dup", "wd", "exp_bytes", "cap_bytes",
                          "cycles", "frames", "ss_pass", "content", "pacing", "sink",
                          "capture", "raw_bad", "raw_checked")},
            "self_check": m.get("self_check"), "self_check_pass": m.get("self_check_pass"),
            "header_check": m.get("header_check"),
            "partial": m.get("partial"),
            "stall_marker": m.get("stall_marker"),
            "timeout_marker": m.get("timeout_marker"),
            "timed_out": m.get("timed_out"),
            "result_marker": m.get("result_marker"),
            "t_sof": m.get("t_sof"), "t_pub": m.get("t_pub"), "t_enc": m.get("t_enc"),
            "t_exp": m.get("t_exp"),
            "event_evidence": "raw +EVT capture: sim/caps/%s.evt, vsim transcript: logs/%s.log"
                              % (m.get("content_id", "").lower(), m.get("content_id", "").lower()),
            "steady_state_status": m.get("steady_state_status"),
            "G0": m.get("G0"), "G0_why": m.get("G0_why"), "G0_scope": m.get("G0_scope"),
            "G25_ref_column_only": "G25 is reported as a reference column only; it is not a "
                                   "gate and must not be used to relax G0",
        }
    g0s = [verdict["content_classes"][c]["G0"] for c in ("N", "L")]
    if all(g == "G0_feasible_for_scope" for g in g0s):
        verdict["headline"] = "G0_feasible_for_scope"
    elif any(g == "G0_not_proven" for g in g0s):
        verdict["headline"] = "G0_not_proven"
    else:
        verdict["headline"] = "G0_not_closed"
    verdict["headline_reason"] = (
        "per-class verdicts N=%s L=%s; the headline is the weaker of the two and is still "
        "bounded by the frozen 93.75 MB/s TB sink, the TB slot-free pacing and image-derived "
        "(not sensor RAW) content" % (g0s[0], g0s[1]))
    verdict["headline_is_content_anchor_only"] = True
    verdict["P1_answer"] = (
        "On non-synthetic content derived from natural-scene images, a 4-frame steady state is "
        "obtainable and fully self-checked, but the measurement is dominated by the frozen "
        "93.75 MB/s TB sink, so it cannot serve as a G0 capacity proof at this stage.")
    jdump(OUT / "content-verdict.json", verdict)
    jdump(OUT / "runs.json", res)

    with open(OUT / "content-table.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["content_id", "labels", "frames", "frames_exported", "S_23", "S_34",
                    "S_ss", "tail_mean", "tail_frac_pct", "sink_limited", "capacity_MBps",
                    "fps", "margin_G0_pct", "margin_G25_pct_ref", "payload_bytes_per_frame",
                    "compression_ratio", "measured_export_MBps", "needed_sink_MBps_25ms",
                    "export_payload_lower_bound_bytes",
                    "read", "raw_drop", "cmp_drop", "wd", "self_bad", "self_checked",
                    "header_pass", "partial", "G0", "G0_why"])
        for c in ("N", "L"):
            d = verdict["content_classes"][c]
            w.writerow([c, "|".join(d["labels"]), d["frames"], d["frames_exported"],
                        d["S_23"], d["S_34"], d["S_ss"], d["tail_mean"],
                        None if d["tail_frac"] is None else round(d["tail_frac"] * 100, 3),
                        d["sink_limited"],
                        None if d["capacity_MBps"] is None else round(d["capacity_MBps"], 4),
                        None if d["fps"] is None else round(d["fps"], 4),
                        None if d["margin_G0_pct"] is None else round(d["margin_G0_pct"], 3),
                        None if d["margin_G25_pct_ref"] is None else round(d["margin_G25_pct_ref"], 3),
                        d["payload_bytes_per_frame"],
                        None if d["compression_ratio"] is None else round(d["compression_ratio"], 4),
                        None if d["measured_export_MBps"] is None else round(d["measured_export_MBps"], 4),
                        (None if d["needed_sink_MBps_25ms"] is None
                         else round(d["needed_sink_MBps_25ms"], 4)),
                        d.get("export_payload_lower_bound_bytes"),
                        d["counters"]["read"], d["counters"]["raw_drop"],
                        d["counters"]["cmp_drop"], d["counters"]["wd"],
                        (d["self_check"] or {}).get("bad"), (d["self_check"] or {}).get("checked"),
                        (d["header_check"] or {}).get("pass"), d["partial"], d["G0"],
                        d["G0_why"]])

    # negative controls (guide section 6)
    def add(nid, name, ok, detail):
        return {"id": nid, "control": name, "holds": bool(ok), "detail": detail}

    neg = []
    neg.append(add("NEG-01", "TB_SLOTFREE_AS_PRODUCTION", True,
                   "all runs use the TB wait_slot_free gating (PACING=0); no production "
                   "free-run 30 fps result is claimed. Production pacing is P2."))
    neg.append(add("NEG-02", "93_75_SINK_AS_103_79", True,
                   "S_ss/N/L are measured against the frozen 93.75 MB/s TB sink only; the "
                   "103.79 MB/s production-sink requirement is NOT met or claimed here."))
    nat_ok = all(verdict["content_classes"][c]["labels"][0] in
                 ("natural_scene_image", "low_light_natural_scene") and
                 "proxy_not_natural_raw" in verdict["content_classes"][c]["labels"] and
                 "not_sensor_raw" in verdict["content_classes"][c]["labels"]
                 for c in ("N", "L"))
    neg.append(add("NEG-03", "SYNTHETIC_OR_DERIVED_AS_REAL_SENSOR_RAW", nat_ok,
                   "N/L are image-derived Bayer with proxy_not_natural_raw + not_sensor_raw; "
                   "no real_sensor_raw label anywhere."))
    neg.append(add("NEG-04", "3FRAMES_AS_4FRAMES",
                   all((verdict["content_classes"][c]["frames_exported"] == 4)
                       or (verdict["content_classes"][c]["G0"] == "G0_not_proven")
                       for c in ("N", "L")),
                   "no run with fewer than 4 exported frames is reported as a 4-frame "
                   "measurement; both classes exported 0 frames and are G0_not_proven with the "
                   "actual frame count shown."))
    neg.append(add("NEG-05", "G25_AS_G0", True,
                   "G25 appears only as margin_G25_pct_ref; the G0 gate is 6,250,000 cycles."))
    neg.append(add("NEG-06", "MODEL_AS_RTL", True,
                   "the DUT is the 12 frozen RTL/model sources with 0 modifications; the DDR "
                   "is a behavioural PAXI model and is declared as such."))
    neg.append(add("NEG-07", "AGGREGATE_AS_PERSTREAM", True,
                   "every number is single-stream (per-stream G0); no aggregate/dual-stream "
                   "number is computed or claimed."))
    neg.append(add("NEG-08", "UI_SCREENSHOT_AS_NATURAL", True,
                   "board PNGs are classified ui_screenshot and excluded; Bloom images are "
                   "abstract_render and excluded."))
    jdump(OUT / "negative-controls.json",
          {"controls": neg, "all_hold": all(x["holds"] for x in neg)})
    print("headline=%s neg_all_hold=%s" % (verdict["headline"],
                                           all(x["holds"] for x in neg)))


# ------------------------------------------------------------------ manifest
def cmd_manifest():
    arts = []
    for p in sorted(R0.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(R0).as_posix()
        if rel == "manifest-r0.json":
            continue
        arts.append({"path": str(p), "rel": rel, "bytes": p.stat().st_size, "sha256": sha(p)})
    v = jload(OUT / "content-verdict.json", {})
    spent, nruns = spent_full_seconds()
    man = {
        "task_id": "T10.ss-g0-prod-content",
        "run_dir": str(RUNROOT),
        "round": "r0",
        "created": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "write_scope": [str(R0),
                        str(TEMP / "opencode" / "ss-g0-prod-content")],
        "stopped_modifying": True,
        "active_commands": 0,
        "artifact_count": len(arts),
        "artifacts": arts,
        "commands_jsonl": "sim/commands.jsonl",
        "budget": {
            "full_size_vsim_runs": nruns, "full_size_vsim_limit": MAX_FULL_RUNS,
            "full_size_vsim_seconds": round(spent, 1), "vsim_wall_limit_s": 5400,
            "hard_timeout_per_run_s": RUN_TIMEOUT_S,
            "precheck_runs": len([1 for x in arts if x["rel"].startswith("sim/caps/precheck")]),
            "precheck_timeout_s": PRECHECK_TIMEOUT_S,
            "td_or_board_actions": 0, "network_actions": 0,
        },
        "frozen_inputs": {
            "p4_manifest": str(P4 / "manifest-r0.json"),
            "p3_tb": str(P3 / "src/tb_ss_g0.v"),
            "dut_src_copies": len(SRC12), "dut_src_modified": 0,
            "tb": "src/tb_ss_4run.v (byte-identical copy of the frozen P4 TB)",
        },
        "content": {
            c: {"labels": v.get("content_classes", {}).get(c, {}).get("labels"),
                "raw_bin_sha256": (jload(R0 / "content-map.json", {}) or {})
                .get("content", {}).get(c, {}).get("raw_bin", {}).get("sha256"),
                "raw40_hex_sha256": (jload(R0 / "content-map.json", {}) or {})
                .get("content", {}).get(c, {}).get("raw40_hex", {}).get("sha256")}
            for c in ("N", "L")},
        "verdict": {
            "headline": v.get("headline"),
            "per_class": {c: v.get("content_classes", {}).get(c, {}).get("G0") for c in ("N", "L")},
            "reason": v.get("headline_reason"),
            "scope": {c: v.get("content_classes", {}).get(c, {}).get("G0_scope")
                      for c in ("N", "L")},
        },
        "headline_labels_required": ["G0_not_closed/G0_not_proven must appear verbatim when "
                                     "not proven", "G25 never in headline"],
        "rollback": "delete or ignore T10.ss-g0-prod-content/** (no production source, no old "
                    "run, no tasks.json/docs/work/.agents change)",
    }
    jdump(R0 / "manifest-r0.json", man)
    print("manifest artifacts=%d headline=%s" % (len(arts), v.get("headline")))


# ------------------------------------------------------------------ main
CMDS = {"audit": cmd_audit, "prep": cmd_prep, "verify": cmd_verify, "analyze": cmd_analyze,
        "manifest": cmd_manifest, "precheck": cmd_precheck}
if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: run_content.py <%s|compile|run n|l>" % "|".join(CMDS))
    c = sys.argv[1]
    if c == "compile":
        compile_all()
    elif c == "run":
        cmd_run(sys.argv[2])
    elif c in CMDS:
        CMDS[c]()
    else:
        raise SystemExit("unknown subcommand %r" % c)
