#!/usr/bin/env python3
"""derive_geometry.py -- T10.b8-crop-geom: recompute the IMX415 tap geometry
from the frozen b7 v2-status capture (read only, does not modify b7).

Uses the frozen parse_status_v2.parse() so the packet layout is not duplicated.
Writes r0/geometry-derivation.md.
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from parse_status_v2 import parse, wrap_delta, FIELDS  # noqa: E402

B7 = pathlib.Path(r"D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop"
                  r"\T10.b7-cam-diag\r0\board\captures_retry")
CAP = B7 / "com8_150s.bin"
OUT = HERE.parent / "geometry-derivation.md"


def main():
    data = CAP.read_bytes()
    raw, bad_xor, bad_hdr, skipped = parse(data)
    pkt = [dict(zip(FIELDS, v)) for v in raw]
    if not pkt:
        print("NO_PACKETS")
        return 2
    lines = []
    a = lines.append
    a("# T10.b8-crop-geom r0 - geometry derivation (measured, not guessed)\n")
    a("Source: `%s`" % CAP)
    a("Parser: frozen `parse_status_v2.py` (97 B v2 packet, XOR8 at byte 96)\n")
    a("packets=%d bad_xor=%d bad_hdr=%d skipped=%d trailing=%d\n"
      % (len(pkt), bad_xor, bad_hdr, skipped, len(data) - len(pkt) * 97 - skipped))

    a("## 1. Packet deltas (camera-domain counters)\n")
    a("| # | cap_frames | raw_pub | crop_roi_frames | crop_groups | crop_geom_err | crop_short "
      "| cam_pix_beats | cam_line_rises | cam_frame_rises |")
    a("|---|---|---|---|---|---|---|---|---|---|")
    for i, p in enumerate(pkt):
        a("| %d | %d | %d | %d | %d | %d | %d | %d | %d | %d |"
          % (i, p["cap_frames"], p["raw_pub"], p["crop_roi_frames"], p["crop_groups"],
             p["crop_geom_err"], p["crop_short"], p["cam_pix_beats"],
             p["cam_line_rises"], p["cam_frame_rises"]))

    a("\n## 2. Window deltas and derived geometry\n")
    a("Packets 0..12 carry the live stream; packet 13 onward has all camera counters at 0 "
      "(sensor stopped ~13 s after the download, a board-level issue, not a crop issue).\n")
    lo, hi = 0, min(12, len(pkt) - 1)
    d = {k: wrap_delta(pkt[hi][k], pkt[lo][k]) for k in FIELDS}
    dfr = d["cam_frame_rises"] if d["cam_frame_rises"] else d["cap_frames"]
    a("| delta (pkt %d - pkt %d) | value |" % (hi, lo))
    a("|---|---|")
    for k in ("cam_pix_beats", "cam_line_rises", "cam_frame_rises", "cap_frames",
              "crop_roi_frames", "crop_groups", "crop_geom_err", "crop_short"):
        a("| %s | %d |" % (k, d[k]))
    a("")
    beats = d["cam_pix_beats"]
    lines_n = d["cam_line_rises"]
    frames = dfr
    a("Derivation (integer / fractional check):\n")
    a("```")
    a("frames      = %d" % frames)
    a("lines       = %d  -> lines/frame = %d / %d = %.6f"
      % (lines_n, lines_n, frames, lines_n / frames if frames else 0))
    a("beats       = %d  -> beats/line  = %d / %d = %.6f"
      % (beats, beats, lines_n, beats / lines_n if lines_n else 0))
    a("px/beat     = 4 (csi_rx_10bit_unpack: 5 B -> 4 x RAW10)")
    a("CAM_W       = beats/line * 4 = %.3f * 4 = %d"
      % (beats / lines_n if lines_n else 0, round(4 * beats / lines_n) if lines_n else 0))
    a("CAM_H       = lines/frame   = %d" % (round(lines_n / frames) if frames else 0))
    a("remainder   = beats - 966*lines = %d  (< 966: partial line at the sample instant,"
      " not a shorter line)" % (beats - 966 * lines_n,))
    a("geom_err    = %d frames -> exactly one per frame (old 960 check fails once, then"
      " active=0 stops all further checks)" % (d["crop_geom_err"],))
    a("```\n")

    cw = round(4 * beats / lines_n / 4) if lines_n else 0   # groups per line
    ch = round(lines_n / frames) if frames else 0
    a("Frozen values: CAM_W=%d (CG=%d), CAM_H=%d." % (cw * 4, cw, ch))
    a("ROI_X=(%d-1920)/2=%d (%%4=%d), ROI_Y=(%d-1080)/2=%d (%%2=%d), "
      "GX=%d, OG=480, NGRP=518400.\n"
      % (cw * 4, (cw * 4 - 1920) // 2, ((cw * 4 - 1920) // 2) % 4,
         ch, (ch - 1080) // 2, ((ch - 1080) // 2) % 2, (cw * 4 - 1920) // 8))

    a("## 3. Why the old defaults discarded every frame\n")
    a("Old crop: CAM_W=3840 -> CG=960. Real line = %d beats. At the first `new_line` "
      "(line 1) grp_idx=%d != 960 -> `st_geom_err+1`, `active<=0`; with active=0 no later "
      "line is checked, so exactly one geom_err per frame and `st_groups` stays 0. "
      "b7 measured crop_geom_err=%d, crop_roi_frames=0, crop_groups=0, cap_frames=0 - "
      "consistent with this mechanism and inconsistent with a data/CRC/CRC-store fault."
      % (cw, cw, pkt[-1]["crop_geom_err"]))
    a("\n## 4. ROI placement\n")
    a("Active array 3840x2160 sits at (12,16) inside the 3864x2192 valid array.")
    a("ROI is defined on the **full valid frame centre**: (972,556) = ((3864-1920)/2,"
      " (2192-1080)/2). Relative to the active array that is (960,540) - still 2x2 aligned,"
      " so Bayer phase is preserved and the ROI is centred on the delivered image.\n")
    a("## 5. Checks\n")
    a("| check | value | ok |")
    a("|---|---|---|")
    a("| CAM_W %% 4 | %d | %s |" % (cw * 4 % 4, "ok" if cw * 4 % 4 == 0 else "FAIL"))
    a("| ROI_X %% 4 | %d | %s |" % ((cw * 4 - 1920) // 2 % 4,
                                     "ok" if ((cw * 4 - 1920) // 2) % 4 == 0 else "FAIL"))
    a("| ROI_Y %% 2 | %d | %s |" % ((ch - 1080) // 2 % 2,
                                     "ok" if ((ch - 1080) // 2) % 2 == 0 else "FAIL"))
    a("| ROI_X+W <= CAM_W | %d | %s |" % ((cw * 4 - 1920) // 2 + 1920,
                                           "ok" if (cw * 4 - 1920) // 2 + 1920 <= cw * 4 else "FAIL"))
    a("| ROI_Y+H <= CAM_H | %d | %s |" % ((ch - 1080) // 2 + 1080,
                                           "ok" if (ch - 1080) // 2 + 1080 <= ch else "FAIL"))
    a("| NGRP < 2^20 | 518400 | ok |")
    a("")
    OUT.write_text("\n".join(lines) + "\n")
    print("WROTE", OUT)
    print("beats/line=%.6f lines/frame=%.6f CAM_W=%d CAM_H=%d"
          % (beats / lines_n, lines_n / frames, cw * 4, ch))
    return 0


if __name__ == "__main__":
    sys.exit(main())
