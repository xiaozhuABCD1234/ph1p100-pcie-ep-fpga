#!/usr/bin/env python3
"""make_ref_geom.py -- independent reference for tb_crop_geom_real.

Contract pattern (frame fr, full-frame line ln, group gg, pixel k):
   g4 = gg[3:0]
   b0 = {ln[5:0], g4}
   b1 = ~b0
   b2 = ln[9:0] ^ g4
   b3 = 0x2A5 ^ (ln[9:0] + g4)
   p  = (b + (0x155 if fr == 1 else 0)) & 0x3FF
Beat = {p3[1:0],p2[1:0],p1[1:0],p0[1:0],p3[9:2],p2[9:2],p1[9:2],p0[9:2]}
written as 5 little-endian bytes, raster order over
line in [556, 1635], group in [243, 722].
"""
import hashlib
import pathlib
import sys

CAM_W, CAM_H = 3864, 2192
ROI_X, ROI_Y = 972, 556
W, H = 1920, 1080


def pv(fr, ln, gg, k):
    if k == 0:
        b = ((ln & 0x3F) << 4) | (gg & 0xF)
    elif k == 1:
        b = (~(((ln & 0x3F) << 4) | (gg & 0xF))) & 0x3FF
    elif k == 2:
        b = ((ln & 0x3FF) ^ (gg & 0xF)) & 0x3FF
    else:
        b = (0x2A5 ^ ((ln + (gg & 0xF)) & 0x3FF)) & 0x3FF
    return (b + (0x155 if fr == 1 else 0)) & 0x3FF


def beat(fr, ln, gg):
    p = [pv(fr, ln, gg, k) for k in range(4)]
    return ((p[3] & 3) << 38 | (p[2] & 3) << 36 | (p[1] & 3) << 34 | (p[0] & 3) << 32 |
            (p[3] >> 2) << 24 | (p[2] >> 2) << 16 | (p[1] >> 2) << 8 | (p[0] >> 2))


def main():
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "roi_real.ref.bin")
    og = W // 4
    gx = ROI_X // 4
    n = 0
    with open(out, "wb") as f:
        for fr in range(2):
            for r in range(H):
                row = bytearray()
                for c in range(og):
                    row += beat(fr, ROI_Y + r, gx + c).to_bytes(5, "little")
                f.write(row)
                n += og
    data = out.read_bytes()
    print("REF bytes=%d beats=%d sha256=%s" % (len(data), n, hashlib.sha256(data).hexdigest()))


if __name__ == "__main__":
    main()
