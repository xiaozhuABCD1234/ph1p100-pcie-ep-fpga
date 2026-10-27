#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T09.rk-align-algo independent software oracle (no DUT helpers).

This module re-derives the three R2 preprocessing algorithms from the frozen
semantics and is deliberately structured differently from
`parallel/algorithms/image_algorithms_ref.py` (which is the semantic source and
is cross-checked by `--selftest`).  The ModelSim vector generator uses only this
module plus the cross-check; RTL internals are never consulted.

Frozen semantics (shared with the reference):
  * CFA phase 0=RGGB 1=BGGR 2=GRBG 3=GBRG by received pixel/row order.
  * bilinear demosaic with CFA-parity preserving replicate borders; averages
    round half-up ((a+b+1)>>1, (s+2)>>2); RAW10 -> RGB10 -> R8/G8/B8 by >>2.
  * Y8 = (77*R8 + 150*G8 + 29*B8 + 128) >> 8.
  * 3x3 Gaussian [1 2 1; 2 4 2; 1 2 1], replicate borders, (sum+8)>>4.
  * previous-frame CDF-min HE: first frame identity; LUT[v] =
    clamp(round((cdf[v]-cdf_min)*255/den)) with den = npix-cdf_min; den == 0 ->
    identity; bad frames never publish; 4 histogram banks (lane i -> bank i)
    count every pixel, then merge.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# CFA helpers
# ---------------------------------------------------------------------------

# top-left, top-right, bottom-left, bottom-right colour per phase (receive order)
_CFA4 = {
    0: ("R", "G", "G", "B"),   # RGGB
    1: ("B", "G", "G", "R"),   # BGGR
    2: ("G", "R", "B", "G"),   # GRBG
    3: ("G", "B", "R", "G"),   # GBRG
}


def cfa(y: int, x: int, phase: int) -> str:
    """Colour of the CFA site (y, x) for a phase in receive order."""
    tl, tr, bl, br = _CFA4[phase]
    return (tl, tr, bl, br)[(y & 1) * 2 + (x & 1)]


def nb_axis(x: int, dx: int, n: int) -> int:
    """Neighbour coordinate with preserved parity (demosaic replicate border).

    In range -> x+dx.  Out of range -> the same-parity coordinate inside the
    frame (x=-1 -> 1, x=n -> n-2), matching "clamp then restore parity, prefer
    +1".  A single-column/row frame degenerates to the centre coordinate.
    """
    t = x + dx
    if 0 <= t <= n - 1:
        return t
    if n == 1:
        return 0
    return 1 if t < 0 else n - 2


def nb_plain(x: int, dx: int, n: int) -> int:
    """Plain replicate clamp used by the Y8 3x3 Gaussian (no parity rule)."""
    t = x + dx
    return 0 if t < 0 else (n - 1 if t > n - 1 else t)


def avg2(a: int, b: int) -> int:
    return (a + b + 1) >> 1


def avg4(a: int, b: int, c: int, d: int) -> int:
    return (a + b + c + d + 2) >> 2


# ---------------------------------------------------------------------------
# demosaic / gray
# ---------------------------------------------------------------------------

def demosaic(raw: list, w: int, h: int, phase: int):
    """Return [(r10, g10, b10)] for a row-major RAW10 frame."""
    if len(raw) != w * h:
        raise ValueError("raw size mismatch")
    out = []
    for y in range(h):
        yu, yd = nb_axis(y, -1, h), nb_axis(y, 1, h)
        for x in range(w):
            xl, xr = nb_axis(x, -1, w), nb_axis(x, 1, w)
            own = raw[y * w + x]
            code = cfa(y, x, phase)
            if code == "G":
                hcol = cfa(y, x - 1, phase)          # ideal-parity column colour
                hl, hr = raw[y * w + xl], raw[y * w + xr]
                vu, vd = raw[yu * w + x], raw[yd * w + x]
                if hcol == "R":
                    r, b = avg2(hl, hr), avg2(vu, vd)
                else:
                    b, r = avg2(hl, hr), avg2(vu, vd)
                g = own
            else:
                hl, hr = raw[y * w + xl], raw[y * w + xr]
                vu, vd = raw[yu * w + x], raw[yd * w + x]
                g = avg4(hl, hr, vu, vd)
                diag = avg4(raw[yu * w + xl], raw[yu * w + xr],
                            raw[yd * w + xl], raw[yd * w + xr])
                if code == "R":
                    r, b = own, diag
                else:
                    b, r = own, diag
            out.append((r, g, b))
    return out


def y8_from_rgb(rgb):
    out = []
    for r, g, b in rgb:
        out.append((77 * (r >> 2) + 150 * (g >> 2) + 29 * (b >> 2) + 128) >> 8)
    return out


def grayscale(raw: list, w: int, h: int, phase: int):
    return y8_from_rgb(demosaic(raw, w, h, phase))


# ---------------------------------------------------------------------------
# Gaussian
# ---------------------------------------------------------------------------

def gaussian(img: list, w: int, h: int):
    """Separable 3x3 [1 2 1]^2 with plain replicate borders, one rounding."""
    hsum = []
    for y in range(h):
        row = img[y * w:(y + 1) * w]
        for x in range(w):
            l, m, r = row[nb_plain(x, -1, w)], row[x], row[nb_plain(x, 1, w)]
            hsum.append(l + 2 * m + r)
    out = []
    for y in range(h):
        yu, yd = nb_plain(y, -1, h), nb_plain(y, 1, h)
        for x in range(w):
            s = hsum[yu * w + x] + 2 * hsum[y * w + x] + hsum[yd * w + x]
            out.append((s + 8) >> 4)
    return out


# ---------------------------------------------------------------------------
# HE (CDF-min) with previous-frame LUT state
# ---------------------------------------------------------------------------

def hist4(img: list):
    """Four independent banks (lane i -> bank i), merged afterwards."""
    banks = [[0] * 256 for _ in range(4)]
    for i, v in enumerate(img):
        banks[i & 3][v & 0xFF] += 1
    merged = [0] * 256
    for b in banks:
        for v in range(256):
            merged[v] += b[v]
    return merged


def cdf_min_lut(counts: list, npix: int):
    cdf = []
    acc = 0
    for v in range(256):
        acc += counts[v]
        cdf.append(acc)
    first = None
    for v in range(256):
        if counts[v]:
            first = cdf[v]
            break
    if first is None:
        return list(range(256))
    den = npix - first
    if den <= 0:
        return list(range(256))
    lut = []
    for v in range(256):
        num = 255 * max(cdf[v] - first, 0)
        val = (num + (den >> 1)) // den
        lut.append(0 if val < 0 else (255 if val > 255 else val))
    return lut


class HeSeq:
    """Previous-frame HE state over a frame sequence (mirrors HeLut semantics)."""

    def __init__(self):
        self.lut = list(range(256))
        self.published = 0
        self.rejected = 0
        self.trace = []          # (frame index, published?, lut_source_index)

    def frame(self, img: list, good: bool):
        """Expected output for this frame + publish decision."""
        out = [self.lut[v] for v in img]
        src = self.published
        if good:
            self.lut = cdf_min_lut(hist4(img), len(img))
            self.published += 1
        else:
            self.rejected += 1
        self.trace.append((src, good, self.published))
        return out


# ---------------------------------------------------------------------------
# Frame-sequence simulator used by the vector generator
# ---------------------------------------------------------------------------

def frame_beats(raw: list, w: int):
    """Pack a row-major RAW10 frame into 4-sample words (little-endian lanes)."""
    m = w // 4
    words = []
    for r in range(len(raw) // w):
        for j in range(m):
            word = 0
            for lane in range(4):
                word |= (raw[r * w + j * 4 + lane] & 0x3FF) << (10 * lane)
            words.append(word)
    return words


def pack_y8(px: list):
    """Pack four Y8 samples into a 32-bit word (lane 0 = bits 7:0)."""
    word = 0
    for lane in range(4):
        word |= (px[lane] & 0xFF) << (8 * lane)
    return word


# ---------------------------------------------------------------------------
# self-test / cross-check against the frozen parallel reference
# ---------------------------------------------------------------------------

def _load_reference():
    ref_path = Path(__file__).resolve().parents[2] / "parallel" / "algorithms" / "image_algorithms_ref.py"
    import importlib.util
    spec = importlib.util.spec_from_file_location("t09_parallel_ref", ref_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def selftest(verbose=True):
    ref = _load_reference()
    res = []
    rng = __import__("random").Random(0x20261017)

    # 1) colour-only CFA frames: exact reconstruction on every site/phase
    ok = True
    for phase in range(4):
        w, h = 8, 6
        raw = []
        for y in range(h):
            for x in range(w):
                raw.append({"R": 200, "G": 400, "B": 700}[cfa(y, x, phase)])
        got = demosaic(raw, w, h, phase)
        if any(px != (200, 400, 700) for px in got):
            ok = False
        # cross-check with the frozen reference
        if ref.demosaic_bilinear(raw, w, h, phase) != got:
            ok = False
    res.append(("demosaic_coloronly_and_ref", ok))

    # 2) random frames across phases/sizes: demosaic + y8 + gaussian vs reference
    ok = True
    for (w, h, phase) in ((8, 2, 0), (8, 3, 1), (12, 4, 2), (16, 5, 3), (20, 7, 0)):
        raw = [rng.randrange(1024) for _ in range(w * h)]
        if demosaic(raw, w, h, phase) != ref.demosaic_bilinear(raw, w, h, phase):
            ok = False
        gy = grayscale(raw, w, h, phase)
        if gy != ref.grayscale(raw, w, h, phase):
            ok = False
        ga = gaussian(gy, w, h)
        if ga != ref.gaussian3x3(gy, w, h):
            ok = False
    res.append(("gray_gauss_random_vs_ref", ok))

    # 3) gaussian literals (rounding, borders)
    res.append(("gauss_constant", gaussian([128] * 25, 5, 5) == [128] * 25))
    imp = [0] * 81
    imp[4 * 9 + 4] = 16
    gi = gaussian(imp, 9, 9)
    res.append(("gauss_impulse", gi[4 * 9 + 4] == 4 and gi[3 * 9 + 4] == 2 and
                gi[3 * 9 + 3] == 1 and sum(gi) == 16))
    res.append(("gauss_rounding", gaussian([0, 0, 0, 0, 2, 0, 0, 0, 0], 3, 3)[4] == 1))

    # 4) histogram banks + cdf-min LUT vs reference
    img = [7] * 64
    res.append(("hist4_no_lost_counts", hist4(img) == ref.histogram(img)))
    img2 = [(i * 37) & 0xFF for i in range(257)]
    ok = True
    for cand in (img, img2, list(range(256)), [0, 255] * 128):
        if hist4(cand) != ref.banks4_histogram(cand, 0):
            ok = False
        if cdf_min_lut(hist4(cand), len(cand)) != ref.cdf_min_lut(ref.histogram(cand), len(cand)):
            ok = False
    res.append(("he_vs_ref", ok))
    res.append(("he_den0_identity", cdf_min_lut(hist4([9] * 100), 100) == list(range(256))))

    # 5) sequence semantics vs reference HeLut
    frames = [[(i * 4) & 0xFF for i in range(64)],
              [0] * 64,
              [(i * 3 + 1) & 0xFF for i in range(64)]]
    he_ref = ref.HeLut()
    he_or = HeSeq()
    ok = True
    for i, f in enumerate(frames):
        good = (i != 1)
        exp_ref = ref.apply_lut(f, he_ref.begin_frame())
        he_ref.end_frame(f, valid=good)
        if he_or.frame(f, good) != exp_ref:
            ok = False
    res.append(("he_sequence_vs_ref", ok))
    res.append(("he_sequence_state", he_or.published == 2 and he_or.rejected == 1))

    if verbose:
        for name, passed in res:
            print("T09_ORACLE_SELFTEST", name, "PASS" if passed else "FAIL")
    return res


def main():
    ap = argparse.ArgumentParser(description="T09 independent oracle")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        res = selftest()
        ok = all(p for _, p in res)
        print("T09_ORACLE", "PASS" if ok else "FAIL")
        return 0 if ok else 1
    ap.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
