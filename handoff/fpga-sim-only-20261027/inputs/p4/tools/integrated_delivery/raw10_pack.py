#!/usr/bin/env python3
"""INT.P1 RAW10 packing helpers and independent oracle."""

from __future__ import annotations


def pack_samples(p0, p1, p2, p3):
    """Pack four 10-bit samples into one 40-bit RAW10 word (byte0 LSB)."""
    for p in (p0, p1, p2, p3):
        if not (0 <= p <= 0x3FF):
            raise ValueError("sample out of 10-bit range")
    b0 = (p0 >> 2) & 0xFF
    b1 = (p1 >> 2) & 0xFF
    b2 = (p2 >> 2) & 0xFF
    b3 = (p3 >> 2) & 0xFF
    b4 = (p0 & 0x3) | ((p1 & 0x3) << 2) | ((p2 & 0x3) << 4) | ((p3 & 0x3) << 6)
    return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24) | (b4 << 32)


def unpack_packed(word):
    """Independent oracle: unpack a 40-bit RAW10 word into four 10-bit samples."""
    b0 = word & 0xFF
    b1 = (word >> 8) & 0xFF
    b2 = (word >> 16) & 0xFF
    b3 = (word >> 24) & 0xFF
    b4 = (word >> 32) & 0xFF
    p0 = (b0 << 2) | (b4 & 0x3)
    p1 = (b1 << 2) | ((b4 >> 2) & 0x3)
    p2 = (b2 << 2) | ((b4 >> 4) & 0x3)
    p3 = (b3 << 2) | ((b4 >> 6) & 0x3)
    return [p0, p1, p2, p3]


def pack_samples_vector(samples):
    if len(samples) != 4:
        raise ValueError("need 4 samples")
    return pack_samples(*samples)


def samples_to_packed_bytes(samples_flat):
    """Pack a flat list of 10-bit samples (multiple of 4) into packed words."""
    if len(samples_flat) % 4:
        raise ValueError("sample count must be multiple of 4")
    return [pack_samples(samples_flat[i], samples_flat[i + 1],
                        samples_flat[i + 2], samples_flat[i + 3])
            for i in range(0, len(samples_flat), 4)]


def verify_roundtrip(samples):
    word = pack_samples(*samples)
    got = unpack_packed(word)
    return got == list(samples), word, got


if __name__ == "__main__":
    import random
    rng = random.Random(12345)
    bad = 0
    for _ in range(10000):
        s = [rng.randrange(1024) for _ in range(4)]
        ok, w, got = verify_roundtrip(s)
        if not ok:
            bad += 1
            if bad < 5:
                print("MISMATCH", s, w, got)
    # negative: direct 4x10 vector (same bits) is not equal to packed for non-trivial lows
    direct = 0
    for i, v in enumerate([1, 2, 3, 4]):
        direct |= (v & 0x3FF) << (i * 10)
    packed = pack_samples(1, 2, 3, 4)
    print("roundtrip_bad=", bad)
    print("direct_vector=", hex(direct))
    print("packed_word=", hex(packed))
    print("RAW10_PACK", "PASS" if bad == 0 and direct != packed else "FAIL")