#!/usr/bin/env python3
"""r3 T03 oracle verifier (task A + address part of task B).

Reads the files written by tb_t03_pusher_map and the frozen T03 oracle
(evidence/t03/rtl-slot-read.bin) and prints the required markers:

  PRODUCED_LEN / FROZEN_LEN / BYTE_DIFF / FIRST8_PRODUCED / FIRST8_FROZEN

Judged parts
  * store read-back == frozen 70 B            (T03 oracle, store side)
  * pusher payload, documented host model == frozen 70 B
                                               (task A, pusher side)
  * store AW word == 2048 and pusher AR == 0x10000, 0x40000 never seen
                                               (task B, direct pair)
Diagnostic (not judged): MAP_B (no bswap) and MAP_C (DW-order only), so the
mapping choice is evidence, not a guess.
"""
import sys
from pathlib import Path

RUN = Path(__file__).resolve().parents[1]
T03 = RUN / "evidence" / "t03" / "rtl-slot-read.bin"
SIM = RUN / "sim" / "t03map"

fails = []
checks = 0


def check(name, cond, detail=""):
    global checks
    checks += 1
    print(("PASS " if cond else "FAIL ") + name + (f"  [{detail}]" if detail else ""))
    if not cond:
        fails.append(name)


def first8(d):
    return " ".join(f"{b:02X}" for b in d[:8])


def compare(tag, path, ref):
    d = path.read_bytes() if path.exists() else b""
    n = min(len(d), len(ref))
    diff = sum(1 for a, b in zip(d[:n], ref[:n]) if a != b) + abs(len(d) - n)
    return d, diff


def main():
    if not T03.exists():
        print(f"FAIL missing frozen oracle {T03}")
        return 1
    ref = T03.read_bytes()
    check("frozen_oracle_len_70", len(ref) == 70, str(len(ref)))
    check("frozen_oracle_first8_789c", ref[:2] == b"\x78\x9c", first8(ref))

    store, store_diff = compare("store", SIM / "t03_store_read.bin", ref)
    hostA, diffA = compare("A", SIM / "t03_host_A.bin", ref)
    hostB, diffB = compare("B", SIM / "t03_host_B.bin", ref)
    hostC, diffC = compare("C", SIM / "t03_host_C.bin", ref)

    print(f"PRODUCED_LEN={len(store)} FROZEN_LEN={len(ref)} BYTE_DIFF={store_diff}")
    print(f"FIRST8_PRODUCED={first8(store)}")
    print(f"FIRST8_FROZEN  ={first8(ref)}")
    check("store_read_equals_oracle", store_diff == 0 and len(store) >= 70,
          f"diff={store_diff} len={len(store)}")

    print(f"PUSHER_HOST_MODEL=documented(lane7_first,msb_first_dw)")
    print(f"PUSHER_LEN={len(hostA)} PUSHER_BYTE_DIFF={diffA} PUSHER_FIRST8={first8(hostA)}")
    check("pusher_host_equals_oracle", diffA == 0 and len(hostA) >= 70,
          f"diff={diffA} len={len(hostA)}")

    # diagnostic only: these are the two alternatives the round was asked to try
    print(f"MAP_B_no_bswap   FIRST8={first8(hostB)} BYTE_DIFF={diffB}")
    print(f"MAP_C_dw_order   FIRST8={first8(hostC)} BYTE_DIFF={diffC}")
    check("map_A_is_the_only_candidate_that_matches",
          diffA == 0 and diffB != 0 and diffC != 0,
          f"A={diffA} B={diffB} C={diffC}")

    txt = (SIM / "t03_map.txt").read_text() if (SIM / "t03_map.txt").exists() else ""
    kv = {}
    for line in txt.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            kv[k.strip()] = v.strip()

    def get(k):
        return kv.get(k, "")

    print("ADDR " + " ".join(f"{k}={get(k)}" for k in
          ("store_aw_word", "store_aw_byte", "push_ar_first", "saw_40000",
           "tlp", "done", "err", "data_beats")))
    check("store_aw_word_2048", get("store_aw_word") == "2048", get("store_aw_word"))
    check("store_aw_byte_0x10000", get("store_aw_byte").lower().endswith("10000"),
          get("store_aw_byte"))
    check("pusher_ar_0x10000", get("push_ar_first").lower().endswith("10000"),
          get("push_ar_first"))
    check("no_0x40000", get("saw_40000") == "0", get("saw_40000"))
    check("pusher_32_mwr_1_done", get("tlp") == "32" and get("done") == "1")
    check("pusher_no_error", get("err") == "0", get("err"))

    print(f"CHECKS={checks} FAILS={len(fails)}")
    print("T03_ORACLE=" + ("PASS" if not fails else "FAIL"))
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main())
