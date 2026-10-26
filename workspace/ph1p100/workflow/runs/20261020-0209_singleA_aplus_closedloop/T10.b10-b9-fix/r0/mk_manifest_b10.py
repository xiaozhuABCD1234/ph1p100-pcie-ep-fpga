#!/usr/bin/env python3
"""mk_manifest_b10.py -- freeze the T10.b10-b9-fix r0 candidate.

Hashes every input that can change behaviour (RTL copies, td sources, build
scripts, TBs, board scripts), then binds the bit / CWC / BID and the collected
evidence (sim results, board parse, captures) into one manifest and a flat
artifact-hashes.txt.
"""
import hashlib
import json
import pathlib
import sys

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
PKG = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b10-b9-fix"
R0 = PKG / "r0"


def sha(p):
    p = pathlib.Path(p)
    if not p.exists():
        return "MISSING"
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def group(paths, base):
    out = {}
    for p in paths:
        p = pathlib.Path(p)
        out[str(p.relative_to(base)).replace("\\", "/")] = sha(p)
    return out


def main():
    src = group(sorted((R0 / "changed-src").glob("*.v")), R0)
    td_src = group(sorted((R0 / "td").glob("*.tcl")) +
                   sorted((R0 / "td/src").glob("*.v")) +
                   [R0 / "td/p2_board.sdc", R0 / "td/board_p2.adc"],
                   R0)
    sim = group(sorted((R0 / "sim").glob("*.v")) + sorted((R0 / "sim").glob("*.sv")) +
                sorted((R0 / "sim").glob("*.py")), R0)
    board = group(sorted((R0 / "board").glob("*.py")) +
                  [R0 / "board/download_sram_b10.tcl", R0 / "board/run_board_b10.ps1"], R0)

    bit = R0 / "td/a1_board.bit"
    cwc = R0 / "td/a1_board.cwc"
    bid = R0 / "td/a1_board_inst.bid"
    man = {
        "task_id": "T10.b10-b9-fix",
        "run_id": "20261020-0209_singleA_aplus_closedloop",
        "parent_task": "T10 (NOT marked done by this package)",
        "date": "2026-10-25",
        "candidate_root": str(R0),
        "baseline": {
            "root": "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b9-rawstore/r0",
            "exporter_sha256_b9": sha(ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b9-rawstore/r0/changed-src/a1_uart_export.v"),
            "bit_sha256_b9": "950b6e4a867cf1aa87d11c4f084607f4254a82d335f5ed10891dcf74b66a5a06",
            "cwc_sha256_b9": "b9515f79" + "*",
            "bid_sha256_b9": "67c289a8" + "*",
        },
        "changes": {
            "a1_uart_export.v": "B9-01 frame-boundary status/frame arbitration (status_due = sts_tick||sts_want, single grant, last-byte guard); B9-02 1-bit wrap pointers + single-point dq_cnt + full/same-cycle policy + sim asserts",
            "camera_a1_uart_top.v": "B9-03 CMP_BASE 131072 -> 262144 + four-slot capacity/layout assertions; R1 loss-abort on a dropped CDC beat, raw_active released only when the LAST really reaches the store, and a data beat with no active frame is discarded (no FIFO head deadlock)",
            "p2_ddr_bridge.v": "R2 guard against re-issuing the same FIFO word after a registered pop; R3 discard an R that arrives with no outstanding AR (post-reset stale response)",
            "p2_a1_board_top.v": "no functional change (hierarchical CWC probes removed: TD rejects hierarchical references -> cwc_hier_not_available)",
            "a1_ddr_slot_store.v": "unchanged (hash frozen)",
            "a1_raw_crop.v / cam_diag_mailbox.v / a1_deflate_core.v": "unchanged (hash frozen)",
        },
        "sources": {"changed_src": src, "td": td_src},
        "tests": {"sim": sim, "board": board},
        "artifacts": {
            "bit": {"path": str(bit), "sha256": sha(bit)},
            "cwc": {"path": str(cwc), "sha256": sha(cwc)},
            "bid": {"path": str(bid), "sha256": sha(bid)},
        },
        "evidence": {
            "sim_results": "r0/sim/sim-results-b10.json",
            "sim_logs": "r0/sim/logs/",
            "board_status": "r0/board/captures_pwr/status_v3.json",
            "board_capture": "r0/board/captures_pwr/com8_180s.bin",
            "result": "result-r0.md",
            "lessons": "lessons-r0.md",
        },
        "board": {
            "download_count": None,
            "order": "download (COM8 closed) -> open COM8 180 s capture",
        },
    }
    fp = PKG / "CANDIDATE-MANIFEST-b10-b9-fix-r0.json"
    fp.write_text(json.dumps(man, indent=2))

    lines = []
    for sec in ("changed_src", "td"):
        for k, v in man["sources"][sec].items():
            lines.append("%s  %s" % (v, k))
    for sec in ("sim", "board"):
        for k, v in man["tests"][sec].items():
            lines.append("%s  %s" % (v, k))
    for k in ("bit", "cwc", "bid"):
        lines.append("%s  %s" % (man["artifacts"][k]["sha256"], man["artifacts"][k]["path"]))
    (R0 / "artifact-hashes.txt").write_text("\n".join(lines) + "\n")
    print("manifest", fp)
    print("bit", man["artifacts"]["bit"]["sha256"])
    print("cwc", man["artifacts"]["cwc"]["sha256"])
    print("bid", man["artifacts"]["bid"]["sha256"])
    for k, v in man["sources"]["changed_src"].items():
        print("src", v, k)
    return 0


if __name__ == "__main__":
    sys.exit(main())
