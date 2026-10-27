#!/usr/bin/env python3
"""Deep-dive: which byte sequence produces the DUT's CRC fields for the x-geometry frame?"""
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
DUMP = os.path.join(HERE, "x_geom_frame.bin")

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

got = open(DUMP, "rb").read()
print("diffs:", [hex(i) for i in range(4096) if got[i] != (open(DUMP,'rb').read())[i]] or "none")
# find all mismatching offsets vs the *model without CRCs*:
# rebuild expected payload only (we know payload region matches per previous run)
pay = got[128:138]
print("payload bytes:", pay.hex())
dut_raw = struct.unpack_from("<I", got, 80)[0]
dut_pay = struct.unpack_from("<I", got, 84)[0]
dut_hdr = struct.unpack_from("<I", got, 88)[0]
print(f"DUT raw_crc={dut_raw:#010x} payload_crc={dut_pay:#010x} header_crc={dut_hdr:#010x}")

cands = {
    "pay[0:10]": pay,
    "pay[0:12] (pay + 2 zero tail bytes)": pay + b"\x00\x00",
    "pay[0:8]": pay[:8],
    "pay[0:12] + 4 zeros": pay + b"\x00" * 6,
    "full word bytes 128..139 (8 pay? )": got[128:140],
    "got[136:140]": got[136:140],
    "16 bytes from 128": got[128:144],
    "pay[0:10] with bytes swapped in pairs": bytes([pay[1],pay[0],pay[3],pay[2],pay[5],pay[4],pay[7],pay[6],pay[9],pay[8]]),
}
for name, data in cands.items():
    print(f"  crc({name}) = {crc32(data):#010x}  match={crc32(data)==dut_raw}")

# header crc check with the DUT's own field values
tmp = bytearray(got[0:128]); struct.pack_into("<I", tmp, 88, 0)
print(f"header recompute with DUT fields: {crc32(bytes(tmp)):#010x} vs DUT {dut_hdr:#010x} match={crc32(bytes(tmp))==dut_hdr}")

# print all 20 mismatch offsets vs a model with CRCs zeroed (find non-CRC diffs)
exp = bytearray(got[0:128])
struct.pack_into("<I", exp, 80, 0); struct.pack_into("<I", exp, 84, 0); struct.pack_into("<I", exp, 88, 0)
g0 = bytearray(got[0:128]); struct.pack_into("<I", g0, 80, 0); struct.pack_into("<I", g0, 84, 0); struct.pack_into("<I", g0, 88, 0)
print("header diffs excluding CRC fields:", [hex(i) for i in range(128) if exp[i] != g0[i]])
print("tail region nonzero bytes:", [hex(i) for i in range(138, 4096) if got[i] != 0][:20])
