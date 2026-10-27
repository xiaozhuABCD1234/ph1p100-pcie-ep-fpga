#!/usr/bin/env python3
"""T11.BRD.P1 r1 independent slot / A1U1 verifier (local, sim only).

Checks, from the files a G1 run leaves in r1/sim:
  * slot_dump.bin is an RFC1950 zlib member accepted by the standard zlib
  * decompressed length == xform_len from sim_meta.txt
  * decompressed bytes == the packed RAW10 A+ input byte stream (bypass run)
  * the last 4 bytes are the correct big-endian Adler-32
  * the 44B A1U1 header built by the TB host model has correct magic/fields/
    header CRC and its payload equals slot_dump.bin
  * the MWr / doorbell / exported counters agree with frame_bytes
"""
import struct
import sys
import zlib
from pathlib import Path

sim = Path(__file__).resolve().parent.parent / "sim"
meta = {}
for line in (sim / "sim_meta.txt").read_text().splitlines():
    k, v = line.split("=", 1)
    meta[k.strip()] = v.strip()

def i(k):
    return int(meta[k], 0)

slot = (sim / "slot_dump.bin").read_bytes()
pk = (sim / "pk_bytes.bin").read_bytes()
a1u1 = (sim / "a1u1_frame.bin").read_bytes()

fails = []

def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + ((" " + detail) if detail else ""))
    if not cond:
        fails.append(name)

stream_len = i("stream_len")
xform_len = i("xform_len")
frame_bytes = i("frame_bytes")
check("slot_len_matches_meta", len(slot) == stream_len, f"{len(slot)} vs {stream_len}")

try:
    raw = zlib.decompress(slot)
    check("standard_zlib_decompress", True, f"{len(raw)} bytes")
except Exception as e:  # noqa: BLE001
    raw = b""
    check("standard_zlib_decompress", False, repr(e))

check("uncompressed_len_equals_xform_len", len(raw) == xform_len, f"{len(raw)} vs {xform_len}")
check("raw_bytes_equal_aplus_input", raw == pk, f"{len(raw)} vs {len(pk)}")

adler = zlib.adler32(raw) & 0xFFFFFFFF
tail = int.from_bytes(slot[-4:], "big")
check("adler32_tail", adler == tail, f"computed={adler:08x} tail={tail:08x}")

# A1U1 44B header (D6: host/offline tool owns the header; the DUT stores only zlib)
magic = a1u1[0:4]
version = a1u1[4]
flags = a1u1[5]
hlen = struct.unpack_from("<H", a1u1, 6)[0]
frame_id, width, height = struct.unpack_from("<IHH", a1u1, 8)
raw_len, x_len, s_len, raw_crc, xf_crc, st_crc, hcrc = struct.unpack_from("<IIIIIII", a1u1, 16)
check("header_magic", magic == b"A1U1", magic.hex())
check("header_version_len", version == 1 and hlen == 44, f"v={version} len={hlen}")
check("header_len_fields", len(a1u1) == 44 + stream_len, f"{len(a1u1)} vs {44 + stream_len}")
check("header_geometry", (width, height) == (64, 48), f"{width}x{height}")
check("header_lengths", raw_len == 3840 and x_len == xform_len and s_len == stream_len,
      f"raw={raw_len} xform={x_len} stream={s_len}")
check("header_crc", (zlib.crc32(a1u1[0:40]) & 0xFFFFFFFF) == hcrc, f"{hcrc:08x}")
check("header_payload_equals_slot", a1u1[44:] == slot)

# transport counters
check("mwr_count", i("tlp_cnt") == frame_bytes // 128, f"{i('tlp_cnt')} vs {frame_bytes // 128}")
check("mwr_bytes", i("mwr_bytes") == frame_bytes, f"{i('mwr_bytes')} vs {frame_bytes}")
check("frame_bytes_alignment", frame_bytes == (stream_len + 4095) // 4096 * 4096,
      f"{frame_bytes} vs {stream_len}")
check("doorbell", i("db_cnt") == 1 and i("db_payload") == i("held_seq"), meta.get("db_payload"))
check("exported_once", i("exported") == 1)
check("zero_mismatch", i("mism") == 0 and i("err_tlp") == 0)
check("no_x", i("x_hits") == 0)
check("stream_crc", (zlib.crc32(slot) & 0xFFFFFFFF) == int(meta["stream_crc"], 16))

print("VERIFY=" + ("PASS" if not fails else "FAIL " + ",".join(fails)))
sys.exit(0 if not fails else 1)
