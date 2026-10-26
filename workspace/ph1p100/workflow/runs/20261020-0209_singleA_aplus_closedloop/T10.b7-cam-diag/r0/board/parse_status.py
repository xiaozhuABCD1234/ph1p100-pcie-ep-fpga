#!/usr/bin/env python3
"""T10.b5-a1-htab-pipe r1-diag -- A5 5A status packet parser.

Wire contract (frozen for this diagnostic candidate only):

  off  size  field
  0    1     0xA5
  1    1     0x5A
  2    4     cap_frames  u32 little-endian
  6    4     raw_pub     u32 little-endian
  10   4     enc_frames  u32 little-endian
  14   4     exported    u32 little-endian
  18   4     raw_drop    u32 little-endian
  22   4     cmp_drop    u32 little-endian
  26   4     errors      u32 little-endian
  30   4     read_words  u32 little-endian
  34   1     XOR of bytes 0..33

Everything else on the wire belongs to the frozen A1U1 frame format and is
skipped while scanning for the magic.

Usage:
  python parse_status.py --in com8_60s.bin                 # raw bytes
  python parse_status.py --in status_bytes.txt --format hex
"""
import argparse
import hashlib
import sys

FIELDS = ["cap_frames", "raw_pub", "enc_frames", "exported",
          "raw_drop", "cmp_drop", "errors", "read_words"]
MAGIC = b"\xA5\x5A"
PKT_LEN = 35


def load(path, fmt):
    if fmt == "bin":
        with open(path, "rb") as f:
            return f.read()
    out = bytearray()
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            out.append(int(line, 16))
    return bytes(out)


def scan(buf):
    """Return (packets, bad_magic_hits, skipped_bytes)."""
    pkts = []
    bad = 0
    i = 0
    n = len(buf)
    while i + PKT_LEN <= n:
        if buf[i:i + 2] != MAGIC:
            i += 1
            continue
        pkt = buf[i:i + PKT_LEN]
        x = 0
        for b in pkt[:34]:
            x ^= b
        if x != pkt[34]:
            bad += 1
            i += 1
            continue
        vals = [int.from_bytes(pkt[2 + 4 * k:6 + 4 * k], "little")
                for k in range(8)]
        pkts.append((i, vals))
        i += PKT_LEN
    return pkts, bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--format", choices=("bin", "hex"), default="bin")
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    buf = load(args.inp, args.format)
    pkts, bad = scan(buf)

    lines = []
    lines.append("input=%s format=%s bytes=%d sha256=%s"
                 % (args.inp, args.format, len(buf),
                    hashlib.sha256(buf).hexdigest()))
    lines.append("status_packets=%d bad_xor=%d" % (len(pkts), bad))
    lines.append("")
    lines.append("idx      off        cap_frames      raw_pub    enc_frames"
                 "     exported     raw_drop    cmp_drop      errors"
                 "   read_words")
    for n, (off, v) in enumerate(pkts):
        lines.append("%3d %6d  " % (n, off) +
                     "  ".join("0x%08X(%7d)" % (x, x) if x < 1000000
                               else "0x%08X(%d)" % (x, x) for x in v))

    if pkts:
        first, last = pkts[0][1], pkts[-1][1]
        lines.append("")
        lines.append("first packet:")
        for name, x in zip(FIELDS, first):
            lines.append("  %-11s = 0x%08X = %d" % (name, x, x))
        lines.append("last packet:")
        for name, x in zip(FIELDS, last):
            lines.append("  %-11s = 0x%08X = %d" % (name, x, x))
        if len(pkts) > 1:
            lines.append("delta first->last:")
            for name, a, b in zip(FIELDS, first, last):
                lines.append("  %-11s = %+d" % (name, b - a))

    text = "\n".join(lines) + "\n"
    sys.stdout.write(text)
    if args.out:
        with open(args.out, "w") as f:
            f.write(text)
    return 0 if pkts else 1


if __name__ == "__main__":
    sys.exit(main())
