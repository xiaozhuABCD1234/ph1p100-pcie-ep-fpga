#!/usr/bin/env python3
"""Oracle for the tester's own x-geometry / ownership / seq-gap probe.

Independently rebuilds the expected 4096-byte frame (header incl. flags/phase/session/seq,
packed payload, zero tail, both CRC layers) for W=4,H=2 (payload 10 bytes, not %4) and
compares byte-for-byte against the DDR dumps produced by tb_x_writer_geom:
  x_geom_frame.bin        f1  (BASE0, capture_seq=1)
  x_geom_after_skip.bin   BASE0 content after the locked-block frame was skipped
                          -> must be byte-identical to f1 (no overwrite)
  x_geom_frame4.bin       f4  (BASE1, capture_seq=4 -> gap after unpublished ordinal 2/3)
Only this file's own CRC/packing code is used.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

_TAB = []
for n in range(256):
    c = n
    for _ in range(8):
        c = (c >> 1) ^ 0xEDB88320 if (c & 1) else (c >> 1)
    _TAB.append(c)

def crc32(data: bytes) -> int:
    c = 0xFFFFFFFF
    for b in data:
        c = (c >> 8) ^ _TAB[(c ^ b) & 0xFF]
    return c ^ 0xFFFFFFFF

W, H = 4, 2
X0 = Y0 = 0
SKIP = 0
PHASE = 1
SES = 0xABCD0001
MODE = 7
STRIDE = W * 5 // 4          # 5
PAY = W * H * 5 // 4         # 10
DMA = ((PAY + 128 + 4095) // 4096) * 4096   # 4096
Y_PHYS = SKIP + Y0
phase_derived = PHASE ^ (2 if (X0 & 1) else 0) ^ (3 if (Y_PHYS & 1) else 0)
flags = 2 if (X0 != 0 or Y0 != 0) else 0

def p(x, y):
    return (x * 7 + y * 13 + 5) & 0x3FF

def pack_group(px):
    p0, p1, p2, p3 = px
    return bytes([(p0 >> 2) & 0xFF, (p1 >> 2) & 0xFF, (p2 >> 2) & 0xFF, (p3 >> 2) & 0xFF,
                  ((p3 & 3) << 6) | ((p2 & 3) << 4) | ((p1 & 3) << 2) | (p0 & 3)])

payload = bytearray()
for y in range(H):
    payload += pack_group([p(x, y) for x in range(4)])

def build(seq):
    hdr = bytearray(128)
    hdr[0:4] = b"R10F"
    struct.pack_into("<HH", hdr, 4, 1, 0)
    struct.pack_into("<H", hdr, 8, 128)
    hdr[10] = 0
    struct.pack_into("<III", hdr, 16, SES, seq, MODE)
    struct.pack_into("<HH", hdr, 28, W, H)
    struct.pack_into("<I", hdr, 32, STRIDE)
    struct.pack_into("<HH", hdr, 36, X0, Y0)
    hdr[40] = phase_derived
    hdr[42] = 10
    struct.pack_into("<I", hdr, 44, PAY)
    struct.pack_into("<I", hdr, 48, PAY)
    struct.pack_into("<I", hdr, 52, 1)
    struct.pack_into("<I", hdr, 76, flags)
    pc = crc32(bytes(payload))
    struct.pack_into("<I", hdr, 80, pc)
    struct.pack_into("<I", hdr, 84, pc)
    struct.pack_into("<I", hdr, 88, 0)
    hc = crc32(bytes(hdr))
    struct.pack_into("<I", hdr, 88, hc)
    exp = bytearray(DMA)
    exp[0:128] = hdr
    exp[128:128 + PAY] = payload
    return bytes(exp), pc, hc

exp1, pc, hc = build(1)
exp4, _, _ = build(4)

results = []
def check(name, cond, detail=""):
    results.append((name, cond, detail))
    print(f"[{'OK ' if cond else 'BAD'}] {name} {detail}")

print(f"payload={PAY} bytes (not %4), phase_derived={phase_derived}, flags={flags}, "
      f"payload_crc={pc:#010x}, header_crc(f1)={hc:#010x}")

def load(name):
    p = os.path.join(HERE, name)
    return open(p, "rb").read() if os.path.exists(p) else None

f1 = load("x_geom_frame.bin")
sk = load("x_geom_after_skip.bin")
f4 = load("x_geom_frame4.bin")

if f1 is None or f4 is None or sk is None:
    print("MISSING dumps:", [n for n, v in (("f1", f1), ("skip", sk), ("f4", f4)) if v is None])
    print("MARKER: XGEOM_ORACLE_FAIL")
    sys.exit(1)

d1 = [i for i in range(DMA) if f1[i] != exp1[i]]
check("f1 (seq=1) byte-exact vs independent model", not d1, f"mismatches={len(d1)}")
for i in d1[:8]:
    print(f"   f1 off {i:#06x} got {f1[i]:#04x} exp {exp1[i]:#04x}")
# re-parse f1 independently
check("f1 payload crc field == recompute", struct.unpack_from("<I", f1, 84)[0] == crc32(f1[128:128 + PAY]))
tmp = bytearray(f1[0:128]); struct.pack_into("<I", tmp, 88, 0)
check("f1 header crc field == recompute", struct.unpack_from("<I", f1, 88)[0] == crc32(bytes(tmp)))
check("f1 tail zero", all(b == 0 for b in f1[128 + PAY:]))
check("f1 capture_seq == 1", struct.unpack_from("<I", f1, 20)[0] == 1)

check("block0 unchanged after locked-block frame was skipped", sk == f1,
      "byte-identical" if sk == f1 else f"diffs={sum(1 for a, b in zip(sk, f1) if a != b)}")

d4 = [i for i in range(DMA) if f4[i] != exp4[i]]
check("f4 (capture_seq=4) byte-exact vs independent model", not d4, f"mismatches={len(d4)}")
for i in d4[:8]:
    print(f"   f4 off {i:#06x} got {f4[i]:#04x} exp {exp4[i]:#04x}")
check("f4 capture_seq == 4 (gap 1 -> 4 recorded)", struct.unpack_from("<I", f4, 20)[0] == 4,
      f"seq={struct.unpack_from('<I', f4, 20)[0]}")
check("f4 payload crc field == recompute", struct.unpack_from("<I", f4, 84)[0] == crc32(f4[128:128 + PAY]))
tmp = bytearray(f4[0:128]); struct.pack_into("<I", tmp, 88, 0)
check("f4 header crc field == recompute", struct.unpack_from("<I", f4, 88)[0] == crc32(bytes(tmp)))
check("f4 tail zero", all(b == 0 for b in f4[128 + PAY:]))

ok = all(c for _, c, _ in results)
print(f"SUMMARY: {len(results)} checks, {sum(1 for _, c, _ in results if not c)} failed")
print("MARKER:", "XGEOM_ORACLE_OK" if ok else "XGEOM_ORACLE_FAIL")
sys.exit(0 if ok else 1)
