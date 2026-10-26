#!/usr/bin/env python3
"""T10.b2-a1-uart-impl r4 -- COM8 115200 8N1 capture (read only).

Captures the A+ UART export stream for a fixed window and stores:
  <outdir>/com8_<secs>s.bin   raw bytes exactly as received
  <outdir>/com8_<secs>s.dec   one decimal byte per line (pc_decode input)
  <outdir>/com8_<secs>s.stats key=value summary

No write to the board, no control characters sent.
"""
import argparse
import hashlib
import sys
import time

import serial


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM8")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--secs", type=float, default=120.0)
    ap.add_argument("--outdir", required=True)
    a = ap.parse_args()

    tag = "com8_%ds" % int(a.secs)
    binp = "%s/%s.bin" % (a.outdir, tag)
    decp = "%s/%s.dec" % (a.outdir, tag)
    statp = "%s/%s.stats" % (a.outdir, tag)

    buf = bytearray()
    t0 = time.time()
    with serial.Serial(a.port, a.baud, bytesize=8, parity="N", stopbits=1,
                       timeout=0.2) as sp:
        sp.reset_input_buffer()
        deadline = t0 + a.secs
        while time.time() < deadline:
            chunk = sp.read(4096)
            if chunk:
                buf += chunk
    t1 = time.time()

    with open(binp, "wb") as f:
        f.write(buf)
    with open(decp, "w") as f:
        f.write("".join("%d\n" % b for b in buf))

    magic = b"A1U1"
    n_magic = 0
    off = 0
    while True:
        i = buf.find(magic, off)
        if i < 0:
            break
        n_magic += 1
        off = i + 1
    n55 = buf.count(0x55)

    with open(statp, "w") as f:
        f.write("port=%s baud=%d secs=%.1f\n" % (a.port, a.baud, a.secs))
        f.write("wall_start=%.3f wall_end=%.3f wall_elapsed=%.3f\n"
                % (t0, t1, t1 - t0))
        f.write("bytes=%d magic_a1u1=%d byte_0x55=%d\n" % (len(buf), n_magic, n55))
        f.write("sha256=%s\n" % hashlib.sha256(bytes(buf)).hexdigest())
        f.write("first32=%s\n" % bytes(buf[:32]).hex())
        f.write("last32=%s\n" % bytes(buf[-32:]).hex())

    print("CAPTURE bytes=%d magic=%d b55=%d elapsed=%.1fs"
          % (len(buf), n_magic, n55, t1 - t0))
    return 0 if len(buf) else 1


if __name__ == "__main__":
    sys.exit(main())
