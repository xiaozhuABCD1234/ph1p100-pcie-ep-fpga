#!/usr/bin/env python3
"""T11.BRD.P1 r2 slot / A1U1 verifier (local, simulation only).

Judged criteria come from the INDEPENDENT model in `gen_expected_raw.py`
(contract only) plus the frozen header/transport contract.  The DUT's own
`pk_bytes.bin` is an ADDITIONAL self-consistency check and never a pass/fail
criterion (r1 FAIL: T11.BRD.P1:TB_CAM_STIMULUS_WIDTH).

  raw == expected_raw            PRIMARY byte criterion (bypass runs)
  zlib.decompress succeeds       standard library, no DUT helper
  len(raw) == xform_len          == 3840
  Adder-32 tail == adler32(raw)  == 392578F9
  header fields/CRC/payload      D6 host contract
  frame_bytes/mwr/doorbell       transport consistency
  stimulus probe                 lane/chain/520 checks from the frozen TB

Usage:
  python verify_slot_r2.py                 # scen0/scen3/scen4 + prep + logs
  python verify_slot_r2.py --only scen0
Exit code 0 iff every judged check passes.
"""
import argparse
import json
import struct
import sys
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
R2 = HERE.parent
SIM = R2 / "sim"
GOLD = json.loads((HERE / "golden-r2.json").read_text(encoding="utf-8"))
EXPECTED = (HERE / "expected_raw.bin").read_bytes()
EXP_CRAC = GOLD["independent_golden"]["expected_raw"]

BYPASS_SCENS = ["scen0", "scen3", "scen4"]

fails = []
checks = 0


def check(name, cond, detail=""):
    global checks
    checks += 1
    print(("PASS " if cond else "FAIL ") + name + (("  [" + detail + "]") if detail else ""))
    if not cond:
        fails.append(name)


def read_meta(d: Path) -> dict:
    meta = {}
    for line in read_text_any(d / "sim_meta.txt").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            meta[k.strip()] = v.strip()
    return meta


def read_text_any(p: Path) -> str:
    """Run logs are produced by PowerShell Tee-Object (UTF-16LE on PS 5.1)."""
    raw = p.read_bytes()
    for enc in ("utf-8-sig", "utf-16", "latin-1"):
        try:
            return raw.decode(enc)
        except (UnicodeDecodeError, UnicodeError):
            continue
    return raw.decode("latin-1", errors="replace")


def parse_header(frame: bytes) -> dict:
    magic = frame[0:4]
    version, flags = frame[4], frame[5]
    hlen = struct.unpack_from("<H", frame, 6)[0]
    frame_id, w, h = struct.unpack_from("<IHH", frame, 8)
    raw_len, x_len, s_len, raw_crc, xf_crc, st_crc, hcrc = struct.unpack_from("<IIIIIII", frame, 16)
    return dict(magic=magic, version=version, flags=flags, hlen=hlen, frame_id=frame_id,
                w=w, h=h, raw_len=raw_len, xform_len=x_len, stream_len=s_len,
                raw_crc=raw_crc, xform_crc=xf_crc, stream_crc=st_crc, hcrc=hcrc)


def verify_scenario(name: str, mode: str) -> None:
    d = SIM / name
    print(f"\n=== {name} (mode={mode}) ===")
    if not (d / "sim_meta.txt").exists():
        check(f"{name}_dumps_present", False, f"no dumps in {d}")
        return
    meta = read_meta(d)
    slot = (d / "slot_dump.bin").read_bytes()
    base0 = (d / "slotbase0_dump.bin").read_bytes()
    a1u1 = (d / "a1u1_frame.bin").read_bytes()
    pk = (d / "pk_bytes.bin").read_bytes() if (d / "pk_bytes.bin").exists() else b""

    def i(k):
        return int(meta[k], 0)

    stream_len, xform_len, frame_bytes = i("stream_len"), i("xform_len"), i("frame_bytes")

    check(f"{name}_slot_len_matches_meta", len(slot) == stream_len, f"{len(slot)} vs {stream_len}")
    try:
        raw = zlib.decompress(slot)
        check(f"{name}_standard_zlib_decompress", True, f"{len(raw)} B")
    except Exception as e:  # noqa: BLE001
        raw = b""
        check(f"{name}_standard_zlib_decompress", False, repr(e))

    check(f"{name}_decompressed_len_equals_xform_len",
          len(raw) == xform_len == GOLD["independent_golden"]["raw_len"], f"{len(raw)} / {xform_len}")

    if mode == "bypass":
        check(f"{name}_raw_equals_expected_raw", raw == EXPECTED,
              "expected sha " + EXP_CRAC["sha256"][:16])
        # ADDITIONAL: self-consistency with the DUT's own packer output
        print(("ADDITIONAL PASS " if raw == pk else "ADDITIONAL FAIL ") +
              f"{name}_raw_equals_pk_bytes (self-consistency only, not a criterion)")
    else:
        # PREP=1/PRED=1: the transform domain is not the packed raw domain.
        check(f"{name}_transform_domain_nonempty", len(raw) == xform_len and any(raw), f"{len(raw)} B")
        differs = raw != EXPECTED
        print(("ADDITIONAL PASS " if differs else "ADDITIONAL FAIL ") +
              f"{name}_transform_differs_from_raw_domain")

    adler = zlib.adler32(raw) & 0xFFFFFFFF
    tail = int.from_bytes(slot[-4:], "big")
    cb = GOLD["candidate_bound"] if mode == "bypass" else GOLD["candidate_bound_prep"]
    gold_adler = int(EXP_CRAC["adler32"], 16) if mode == "bypass" else int(cb["adler32_of_decoded"], 16)
    check(f"{name}_adler32_tail", adler == tail == gold_adler,
          f"calc={adler:08x} tail={tail:08x} golden={gold_adler:08X}")

    hdr = parse_header(a1u1)
    expect_flags = 0 if mode == "bypass" else 3
    check(f"{name}_header_magic", hdr["magic"] == b"A1U1", hdr["magic"].hex())
    check(f"{name}_header_version_len", hdr["version"] == 1 and hdr["hlen"] == 44,
          f"v={hdr['version']} len={hdr['hlen']}")
    check(f"{name}_header_flags", hdr["flags"] == expect_flags, f"{hdr['flags']} vs {expect_flags}")
    check(f"{name}_header_geometry", (hdr["w"], hdr["h"]) == (64, 48), f"{hdr['w']}x{hdr['h']}")
    check(f"{name}_header_raw_len", hdr["raw_len"] == 3840, str(hdr["raw_len"]))
    check(f"{name}_header_xform_len", hdr["xform_len"] == xform_len, str(hdr["xform_len"]))
    check(f"{name}_header_stream_len", hdr["stream_len"] == stream_len, str(hdr["stream_len"]))
    check(f"{name}_header_raw_crc_matches_dut", hdr["raw_crc"] == int(meta["raw_crc"], 16),
          f"{hdr['raw_crc']:08x}")
    check(f"{name}_header_xform_crc_matches_dut", hdr["xform_crc"] == int(meta["xform_crc"], 16),
          f"{hdr['xform_crc']:08x}")
    if mode == "bypass":
        check(f"{name}_xform_crc_equals_expected_crc",
              hdr["xform_crc"] == int(EXP_CRAC["crc32"], 16), f"{hdr['xform_crc']:08x}")
        check(f"{name}_raw_crc_equals_expected_crc",
              hdr["raw_crc"] == int(EXP_CRAC["crc32"], 16), f"{hdr['raw_crc']:08x}")
    else:
        # PREP/PRED: the raw domain is still the packed RAW10 input, so its CRC
        # must equal the independent expected-raw CRC even though the transform
        # domain (and therefore xform_crc/stream) is different.
        check(f"{name}_raw_crc_equals_expected_crc",
              hdr["raw_crc"] == int(EXP_CRAC["crc32"], 16), f"{hdr['raw_crc']:08x}")
        check(f"{name}_xform_crc_differs_from_raw_crc", hdr["xform_crc"] != hdr["raw_crc"],
              f"{hdr['xform_crc']:08x}")
    check(f"{name}_header_crc_self_consistent",
          (zlib.crc32(a1u1[0:40]) & 0xFFFFFFFF) == hdr["hcrc"], f"{hdr['hcrc']:08x}")
    check(f"{name}_header_payload_equals_slot", a1u1[44:] == slot, f"{len(a1u1)} B")
    check(f"{name}_stream_crc_matches_slot",
          (zlib.crc32(slot) & 0xFFFFFFFF) == int(meta["stream_crc"], 16), meta["stream_crc"])

    check(f"{name}_slot_base_0x10000_starts_789c", slot[0:2] == b"\x78\x9c", slot[0:2].hex())
    check(f"{name}_legacy_base0_unused", len(base0) == 4096 and not any(base0), f"{len(base0)} B")

    check(f"{name}_frame_bytes_alignment",
          frame_bytes == (stream_len + 4095) // 4096 * 4096 == GOLD["independent_golden"]["frame_bytes"],
          f"{frame_bytes} vs stream_len {stream_len}")
    check(f"{name}_mwr_count", i("tlp_cnt") == frame_bytes // 128 == 32, str(i("tlp_cnt")))
    check(f"{name}_mwr_bytes", i("mwr_bytes") == frame_bytes == 4096, str(i("mwr_bytes")))
    check(f"{name}_doorbell", i("db_cnt") == 1 and i("db_payload") == i("held_seq"), meta.get("db_payload"))
    check(f"{name}_exported_once", i("exported") == 1, str(i("exported")))
    check(f"{name}_zero_tlp_mismatch", i("mism") == 0 and i("err_tlp") == 0,
          f"mism={i('mism')} err={i('err_tlp')}")
    check(f"{name}_no_x", i("x_hits") == 0, str(i("x_hits")))

    check(f"{name}_stim_lane_equal", i("stim_lane_bad") == 0, str(i("stim_lane_bad")))
    check(f"{name}_stim_chain_equal", i("stim_chain_bad") == 0, str(i("stim_chain_bad")))
    check(f"{name}_stim_first_v_520", i("stim_first_v") == 520, str(i("stim_first_v")))
    check(f"{name}_stim_pk_first", meta.get("pk_first", "").lower() == "0082828282", meta.get("pk_first"))
    check(f"{name}_stim_pk_len", i("pk_bytes_len") == 3840, str(i("pk_bytes_len")))

    check(f"{name}_stream_len_repeatable", stream_len == cb["stream_len"], f"{stream_len} vs {cb['stream_len']}")
    check(f"{name}_hcrc_repeatable", f"{hdr['hcrc']:08X}" == cb["hcrc"], f"{hdr['hcrc']:08X}")
    check(f"{name}_stream_crc_repeatable",
          f"{int(meta['stream_crc'], 16):08X}" == cb["stream_crc"], meta["stream_crc"])
    if mode != "bypass":
        check(f"{name}_xform_crc_repeatable",
              f"{hdr['xform_crc']:08X}" == cb["xform_crc"], f"{hdr['xform_crc']:08X}")


def verify_cross_run() -> None:
    print("\n=== cross-scenario stability (same frozen stimulus, same DUT) ===")
    slots = {s: (SIM / s / "slot_dump.bin").read_bytes() for s in BYPASS_SCENS}
    pks = {s: (SIM / s / "pk_bytes.bin").read_bytes() for s in BYPASS_SCENS}
    ref = slots[BYPASS_SCENS[0]]
    check("cross_scen_same_slot_stream", all(v == ref for v in slots.values()),
          ", ".join(f"{k}={len(v)}" for k, v in slots.items()))
    check("cross_scen_same_pk_bytes", all(v == pks[BYPASS_SCENS[0]] for v in pks.values()),
          ", ".join(f"{k}={len(v)}" for k, v in pks.items()))


def verify_negatives() -> None:
    print("\n=== negative / arbiter logs ===")
    needed = {
        "run_scen1_r2.log": ["NEG1_RESULT=PASS"],
        "run_scen2_r2.log": ["NEG2_RESULT=PASS", "PASS neg2"],
        "run_arb_r2.log": ["PASS arb: no grant changed owner inside a burst",
                           "PASS arb: bridge got exactly its single beat",
                           "PASS arb: one bridge transaction completed",
                           "PASS arb: o_switch_err=0",
                           "PASS arb: orphan/late beat counted once (o_late_cnt=1)",
                           "PASS arb: orphan beat was NOT re-routed to any owner",
                           "ARB_RESULT=PASS"],
    }
    for fn, tokens in needed.items():
        p = SIM / fn
        if not p.exists():
            check(f"log_{fn}_present", False, str(p))
            continue
        txt = read_text_any(p)
        missing = [t for t in tokens if t not in txt]
        check(f"log_{fn}", not missing, "missing: " + "; ".join(missing) if missing else "ok")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    args = ap.parse_args()

    if args.only:
        mode = "prep" if args.only == "prep" else "bypass"
        verify_scenario(args.only, mode)
    else:
        for s in BYPASS_SCENS:
            verify_scenario(s, "bypass")
        verify_scenario("prep", "prep")
        verify_cross_run()
        verify_negatives()

    print(f"\nCHECKS={checks} FAILS={len(fails)}")
    print("VERIFY_R2=" + ("PASS" if not fails else "FAIL " + ",".join(fails)))
    return 0 if not fails else 1


if __name__ == "__main__":
    raise SystemExit(main())
