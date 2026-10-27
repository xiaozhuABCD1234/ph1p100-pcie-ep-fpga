#!/usr/bin/env python3
"""A1 P1 deterministic test patterns and expected RAW / transform vectors.

The Verilog testbench (tb_camera_a1_uart_top.v) generates exactly the same
sample values; this module is the independent (non-RTL) reference used by the
verification scripts.

Patterns
  pat 0 : smooth gradient  s = (3x + 5y + 17*((x^y)&7)) & 1023
  pat 1 : xorshift32 advanced once per 4-pixel group (raster order of the
          driven camera lines); samples = st[9:0], st[19:10], st[29:20], st[31:22]

Geometry: 4K RAW10 tap CAM_W x CAM_H, ROI at (ROI_X,ROI_Y) of size W x H.
The testbench stops after ROI_Y+H lines (trailing lines cannot change ROI data).
"""

GEOM_DEFAULT = dict(cam_w=3840, cam_h=2160, roi_x=960, roi_y=540, w=1920, h=1080)


def sample_grad(x, y):
    return (x * 3 + y * 5 + ((x ^ y) & 7) * 17) & 1023


def pack_group(s0, s1, s2, s3):
    """4 x 10-bit samples -> the 5-byte packed RAW10 group of a1_frame_top."""
    return bytes((
        s0 >> 2, s1 >> 2, s2 >> 2, s3 >> 2,
        (s0 & 3) | ((s1 & 3) << 2) | ((s2 & 3) << 4) | ((s3 & 3) << 6),
    ))


def unpack_group(g):
    """5-byte packed group -> 4 x 10-bit samples."""
    b0, b1, b2, b3, b4 = g[0], g[1], g[2], g[3], g[4]
    return ((b0 << 2) | (b4 & 3),
            (b1 << 2) | ((b4 >> 2) & 3),
            (b2 << 2) | ((b4 >> 4) & 3),
            (b3 << 2) | ((b4 >> 6) & 3))


def roi_samples(pat, geom=None):
    """Return rows[y - roi_y][x - roi_x] of the ROI (list of lists, 10-bit)."""
    g = dict(GEOM_DEFAULT)
    if geom:
        g.update(geom)
    cam_w, roi_x, roi_y = g["cam_w"], g["roi_x"], g["roi_y"]
    w, h = g["w"], g["h"]
    nlines = roi_y + h
    cg = cam_w // 4
    rows = [[0] * w for _ in range(h)]
    st = 0x12345678
    for y in range(nlines):
        in_row = roi_y <= y < roi_y + h
        row = rows[y - roi_y] if in_row else None
        for gi in range(cg):
            if pat == 1:
                st ^= (st << 13) & 0xFFFFFFFF
                st ^= st >> 17
                st ^= (st << 5) & 0xFFFFFFFF
                st &= 0xFFFFFFFF
                vals = (st & 1023, (st >> 10) & 1023, (st >> 20) & 1023, (st >> 22) & 1023)
            else:
                x0 = gi * 4
                vals = (sample_grad(x0, y), sample_grad(x0 + 1, y),
                        sample_grad(x0 + 2, y), sample_grad(x0 + 3, y))
            if row is not None:
                x0 = gi * 4
                if roi_x <= x0 < roi_x + w:
                    k = x0 - roi_x
                    row[k:k + 4] = list(vals)
    return rows


def expected_raw(pat, geom=None):
    """Packed RAW10 byte stream of the ROI in raster order (W*H*10/8 bytes)."""
    g = dict(GEOM_DEFAULT)
    if geom:
        g.update(geom)
    rows = roi_samples(pat, g)
    out = bytearray()
    w = g["w"]
    for row in rows:
        for x in range(0, w, 4):
            out += pack_group(row[x], row[x + 1], row[x + 2], row[x + 3])
    return bytes(out)


def expected_xform(pat, prep=1, pred=1, geom=None):
    """Transform-domain byte stream fed to the A+ core (profile prep/pred)."""
    g = dict(GEOM_DEFAULT)
    if geom:
        g.update(geom)
    w, h = g["w"], g["h"]
    rows = roi_samples(pat, g)
    out = bytearray()
    halfw = w // 2
    for b in range((h + 1) // 2):
        y0 = 2 * b
        two = (y0 + 1) < h
        if prep:
            planes = []
            for p in range(4):
                y = y0 + (p >> 1)
                if y >= h:
                    planes.append([])
                    continue
                acc = []
                prev = 0
                for k in range(halfw):
                    s = rows[y][2 * k + (p & 1)]
                    d = s if (k == 0 or not pred) else ((s - prev) & 1023)
                    prev = s
                    acc.append(d)
                planes.append(acc)
            seq = planes[0] + planes[1] + planes[2] + planes[3]
        else:
            n = (2 * w) if two else w
            seq = [rows[y0][x] for x in range(w)]
            if two:
                seq += [rows[y0 + 1][x] for x in range(w)]
            seq = seq[:n]
        for i in range(0, len(seq), 4):
            q = seq[i:i + 4]
            out += pack_group(q[0], q[1], q[2], q[3])
    return bytes(out)


def inverse_xform(xform, prep=1, pred=1, w=1920, h=1080):
    """Inverse of the A+ frame transform: transform bytes -> packed raster RAW."""
    halfw = w // 2
    rows = [[0] * w for _ in range(h)]
    pos = 0
    for b in range((h + 1) // 2):
        y0 = 2 * b
        two = (y0 + 1) < h
        if prep:
            for p in range(4):
                y = y0 + (p >> 1)
                if y >= h:
                    continue
                prev = 0
                for k in range(halfw // 4):
                    s0, s1, s2, s3 = unpack_group(xform[pos:pos + 5])
                    pos += 5
                    for j, d in enumerate((s0, s1, s2, s3)):
                        idx = k * 4 + j
                        v = d if (idx == 0 or not pred) else ((prev + d) & 1023)
                        prev = v
                        if y < h:
                            rows[y][2 * idx + (p & 1)] = v
        else:
            n = (2 * w) if two else w
            gi = 0
            while gi * 4 < n:
                q = unpack_group(xform[pos:pos + 5])
                pos += 5
                for j, v in enumerate(q):
                    idx = gi * 4 + j
                    if idx >= n:
                        break
                    if idx < w:
                        rows[y0][idx] = v
                    else:
                        rows[y0 + 1][idx - w] = v
                gi += 1
    out = bytearray()
    for y in range(h):
        for x in range(0, w, 4):
            out += pack_group(rows[y][x], rows[y][x + 1], rows[y][x + 2], rows[y][x + 3])
    return bytes(out)


if __name__ == "__main__":
    import sys
    g = dict(GEOM_DEFAULT)
    pat = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    raw = expected_raw(pat, g)
    print("pat", pat, "raw_len", len(raw), "expect", g["w"] * g["h"] * 10 // 8)
