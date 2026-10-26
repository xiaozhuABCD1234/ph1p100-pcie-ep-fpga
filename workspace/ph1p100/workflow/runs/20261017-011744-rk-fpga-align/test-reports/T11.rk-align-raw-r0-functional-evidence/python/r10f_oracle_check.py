#!/usr/bin/env python3
"""Independent R10F frame oracle (functional r0 evidence).

Written from scratch by the functional tester using only:
  - the frozen contract (contract/acceptance-vectors.json / registers.json semantics)
  - the RTL header layout documented in cam_r10f_writer.v (cross-read by the tester)
  - standard CRC-32 (IEEE, reflected poly 0xEDB88320, init/xorout 0xFFFFFFFF)

It does NOT import or call any developer tool (r10f_strict.py etc.).
Purpose: independently recompute the frozen constants used by the G1 testbenches and
the contract samples, and parse the RTL-produced frame dumps.
"""
import hashlib
import json
import os
import struct
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "..", ".."))
RUN = os.path.join(ROOT, "workflow", "runs", "20261017-011744-rk-fpga-align")

# ----------------------------------------------------------------------------
# CRC32 IEEE (reflected) — independent implementation
# ----------------------------------------------------------------------------
_TAB = []
def _mk_tab():
    for n in range(256):
        c = n
        for _ in range(8):
            c = (c >> 1) ^ 0xEDB88320 if (c & 1) else (c >> 1)
        _TAB.append(c)
_mk_tab()

def crc32(data: bytes) -> int:
    c = 0xFFFFFFFF
    for b in data:
        c = (c >> 8) ^ _TAB[(c ^ b) & 0xFF]
    return c ^ 0xFFFFFFFF


# ----------------------------------------------------------------------------
# Frame builders (mirror of the frozen contract semantics)
# ----------------------------------------------------------------------------
def pack_group(px):
    p0, p1, p2, p3 = px
    return bytes([
        (p0 >> 2) & 0xFF, (p1 >> 2) & 0xFF, (p2 >> 2) & 0xFF, (p3 >> 2) & 0xFF,
        ((p3 & 3) << 6) | ((p2 & 3) << 4) | ((p1 & 3) << 2) | (p0 & 3),
    ])

def build_header(w, h, x0, y0, phase, session, seq, flags, camera_id=0, mode_id=1,
                 stride=None, raw=None, payload=None, div=1):
    """div: if >1, payload stride is padded to make the header 128B exactly."""
    stride = stride if stride is not None else (w * 5) // 4
    raw = raw if raw is not None else (w * h * 5) // 4
    payload = payload if payload is not None else raw
    hdr = bytearray(128)
    hdr[0:4] = b"R10F"
    struct.pack_into("<HH", hdr, 4, 1, 0)           # version 1.0
    struct.pack_into("<H", hdr, 8, 128)             # header_bytes
    hdr[10] = camera_id
    hdr[11] = 0                                     # format_id
    struct.pack_into("<I", hdr, 12, 0)              # codec_id
    struct.pack_into("<III", hdr, 16, session, seq, mode_id)
    struct.pack_into("<HH", hdr, 28, w, h)
    struct.pack_into("<I", hdr, 32, stride)
    struct.pack_into("<HH", hdr, 36, x0, y0)
    hdr[40] = phase
    hdr[41] = 0                                     # bayer_dir
    hdr[42] = 10                                    # valid_bits
    hdr[43] = 0                                     # packing
    struct.pack_into("<I", hdr, 44, raw)
    struct.pack_into("<I", hdr, 48, payload)
    struct.pack_into("<I", hdr, 52, 1)              # block_count
    struct.pack_into("<I", hdr, 56, 0)              # exposure
    struct.pack_into("<I", hdr, 60, 0)              # gain
    struct.pack_into("<Q", hdr, 64, 0)              # sof_timestamp
    struct.pack_into("<I", hdr, 72, 0)              # timestamp_hz
    struct.pack_into("<I", hdr, 76, flags)
    struct.pack_into("<I", hdr, 80, 0)              # raw_crc32
    struct.pack_into("<I", hdr, 84, 0)              # payload_crc32
    struct.pack_into("<I", hdr, 88, 0)              # header_crc32
    return hdr

def finish_header(hdr: bytearray, payload_crc: int):
    hdr = bytearray(hdr)
    struct.pack_into("<I", hdr, 80, payload_crc)
    struct.pack_into("<I", hdr, 84, payload_crc)
    struct.pack_into("<I", hdr, 88, 0)
    hcrc = crc32(bytes(hdr))
    struct.pack_into("<I", hdr, 88, hcrc)
    return bytes(hdr), hcrc


def main():
    results = []
    def note(name, ok, detail=""):
        results.append((name, ok, detail))
        print(f"[{'OK ' if ok else 'BAD'}] {name} {detail}")

    # ---------------- 1. writer TB constant: 8x4 frozen small vector ----------------
    PAY1 = 40
    pay1 = bytearray()
    for g in range(PAY1 // 5):
        pay1 += pack_group((0, 1, 1022, 1023))
    c_pay1 = crc32(bytes(pay1))
    note("tb_p1_payload_crc==0x97E69DE2", c_pay1 == 0x97E69DE2, hex(c_pay1))
    hdr1 = build_header(8, 4, 0, 0, 3, 0x20261017, 1, 0)
    hdr1b, c_hdr1 = finish_header(hdr1, c_pay1)
    note("tb_p1_header_crc==0x6E5C61EE", c_hdr1 == 0x6E5C61EE, hex(c_hdr1))

    # full 4096-byte expected content for the small vector
    exp1 = bytearray(4096)
    exp1[0:128] = hdr1b
    exp1[128:168] = bytes(pay1)

    # ---------------- 2. contract small sample ----------------
    with open(os.path.join(RUN, "artifacts", "r10f-small-synthetic.dma"), "rb") as f:
        s = f.read()
    note("contract small sample size 4096", len(s) == 4096, str(len(s)))
    note("contract small == tb expected content", s == bytes(exp1),
         "first diff " + str(next((i for i in range(4096) if s[i] != exp1[i]), None)))
    note("contract small tail zero", all(b == 0 for b in s[168:]))

    # ---------------- 3. writer TB constant: 1080p (x*3+y*5 model) ----------------
    W3, H3 = 1920, 1080
    PAY3 = (W3 * H3 * 5) // 4
    buf = bytearray(PAY3)
    for row in range(H3):
        y = 577 + row
        base = row * 2400
        for i in range(480):
            x0 = 960 + i * 4
            px = [(x * 3 + y * 5) & 0x3FF for x in (x0, x0 + 1, x0 + 2, x0 + 3)]
            buf[base + i * 5: base + i * 5 + 5] = pack_group(px)
    c_pay3 = crc32(bytes(buf))
    note("tb_p10_payload_crc==0xAC1B6FE1", c_pay3 == 0xAC1B6FE1, hex(c_pay3))
    hdr3 = build_header(W3, H3, 960, 540, 3, 0x20261017, 1, 2)
    hdr3b, c_hdr3 = finish_header(hdr3, c_pay3)
    note("tb_p10_header_crc==0x56BA381A", c_hdr3 == 0x56BA381A, hex(c_hdr3))

    # ---------------- 4. contract 1080p sample (own parse) ----------------
    with open(os.path.join(RUN, "artifacts", "r10f-1080p-synthetic.dma"), "rb") as f:
        d = f.read()
    note("contract 1080p size 2592768", len(d) == 2592768, str(len(d)))
    hdr = d[0:128]
    note("magic R10F", hdr[0:4] == b"R10F")
    wcrc = struct.unpack_from("<I", hdr, 80)[0]
    pcrc = struct.unpack_from("<I", hdr, 84)[0]
    hcrc = struct.unpack_from("<I", hdr, 88)[0]
    note("1080p raw==payload crc field", wcrc == pcrc, f"{wcrc:#x}")
    note("1080p payload crc field == recompute",
         pcrc == crc32(d[128:128 + 2592000]), f"{pcrc:#x}")
    hdr_nc = bytearray(hdr); struct.pack_into("<I", hdr_nc, 88, 0)
    note("1080p header crc field == recompute(0x58 cleared)",
         hcrc == crc32(bytes(hdr_nc)), f"{hcrc:#x}")
    note("1080p tail 640B zero", all(b == 0 for b in d[128 + 2592000:]))
    note("1080p flags field == 2", struct.unpack_from("<I", hdr, 76)[0] == 2)
    note("1080p header_bytes==128", struct.unpack_from("<H", hdr, 8)[0] == 128)

    # ---------------- 5. RTL dump from the e2e G1 evidence (dev artifact, re-parsed) ----------------
    dump = os.path.join(RUN, "raw", "g1", "msim", "p2_e2e_v6", "t11_e2e_e4_host.bin")
    if os.path.exists(dump):
        with open(dump, "rb") as f:
            h = f.read()
        note("e2e dump size 4096", len(h) == 4096, str(len(h)))
        note("e2e dump magic", h[0:4] == b"R10F")
        sess = struct.unpack_from("<I", h, 16)[0]
        seq = struct.unpack_from("<I", h, 20)[0]
        note("e2e dump session==0x20261018 (new session)", sess == 0x20261018, hex(sess))
        note("e2e dump seq==2", seq == 2, str(seq))
        pc = struct.unpack_from("<I", h, 84)[0]
        note("e2e dump payload crc field == recompute", pc == crc32(h[128:168]), f"{pc:#x}")
        hc = struct.unpack_from("<I", h, 88)[0]
        hnc = bytearray(h[0:128]); struct.pack_into("<I", hnc, 88, 0)
        note("e2e dump header crc field == recompute", hc == crc32(bytes(hnc)), f"{hc:#x}")
        note("e2e dump payload == frozen small vector payload",
             h[128:168] == bytes(pay1))
        note("e2e dump tail zero", all(b == 0 for b in h[168:]))
        # header without session/seq must equal the frozen small header
        diffs = [i for i in range(128) if h[i] != hdr1b[i]]
        note("e2e dump header differs from frozen small only at session/seq/crcs",
             set(diffs) <= set(range(16, 24)) | {80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91},
             f"diffs={diffs}")
        # recompute the header CRC using the *rebuilt* model with dump's session/seq
        hdr_e = build_header(8, 4, 0, 0, 3, sess, seq, 0)
        rc = crc32(h[128:168])
        hdr_e, c_e = finish_header(hdr_e, rc)
        note("e2e dump header == independent rebuild(session,seq)", bytes(hdr_e) == h[0:128])

    # ---------------- 6. mutated file hash from neg_m1 mutation.json ----------------
    mut = os.path.join(RUN, "raw", "g1", "msim", "neg_m1_pack_order", "mutation.json")
    if os.path.exists(mut):
        with open(mut, "r", encoding="utf-8") as f:
            mj = json.load(f)
        src = os.path.join(ROOT, "fpga", "csi2", "pcie_integration", "rtl",
                           "ep_side", "ddr", "cam_r10f_writer.v")
        with open(src, "rb") as f:
            frozen = f.read()
        note("mutation.json frozen_file_sha256 == current RTL file",
             hashlib.sha256(frozen).hexdigest() == mj["frozen_file_sha256"],
             hashlib.sha256(frozen).hexdigest())

    print("\nSUMMARY: %d checks, %d failed" % (len(results), sum(1 for _, ok, _ in results if not ok)))
    for name, ok, detail in results:
        if not ok:
            print("  FAILED:", name, detail)
    print("MARKER:", "ORACLE_OK" if all(ok for _, ok, _ in results) else "ORACLE_MISMATCH")
    return 0 if all(ok for _, ok, _ in results) else 1


if __name__ == "__main__":
    sys.exit(main())
