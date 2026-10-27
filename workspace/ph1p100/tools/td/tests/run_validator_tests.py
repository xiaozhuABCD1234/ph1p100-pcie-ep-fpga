"""Regression harness for tools/td/check_chipwatcher_readback.py (T11.runB-debug-rtl P1-fix2).

Cases (all paths are arguments; no absolute paths are embedded):
  1 real_multipiece     real CWC+BID, --multipiece            -> accepted, map written, 288/288 data + 1 status
  2 real_strict         real CWC+BID, strict                  -> rejected (BID width mismatch; regression guard)
  3 single_strict       synthetic single-segment, strict      -> accepted
  4 single_multipiece   synthetic single-segment, multipiece  -> accepted
  5 neg_gap             real copy, piece data_offset 100->101 -> rejected
  6 neg_overlap         real copy, piece data_offset 120->110 -> rejected
  7 neg_width_overflow  real copy, piece width 20->300        -> rejected
  8 neg_mode_mismatch   real copy, piece working_mode_depth -> 512 (CWC only) -> rejected
  9 neg_wrong_rid       real copy, piece rid -> 0X0000FFFF    -> rejected

Usage:
  python tools/td/tests/run_validator_tests.py --checker tools/td/check_chipwatcher_readback.py \
      --real-cwc <compiled.cwc> --real-bid <inst.bid> --outdir <log dir> --map-out <map.json>
"""
import argparse
import copy
import json
import subprocess
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

SYNTH_CWC = """<chipwatcher>
  <instance name="single_cwc" id="0" ipgen="false" inst_enable="true">
    <logic_eram name="single_cwc/ram" width="32" depth="1024">
      <phy_eram name="single_cwc/ram/mem0" wid="0X00000010" rid="0X00000010" width="32" depth="1024"
                address_offset="0" data_offset="0" address_step="1" num_section="1"
                section_size="32" width_per_section="32" bytes_in_per_section="4"
                working_mode_depth="1024" working_mode_width="32" working_mode_ecc="disable"
                working_mode_num_byte="4" working_mode_super_wide="disable"/>
    </logic_eram>
  </instance>
</chipwatcher>
"""

SYNTH_BID = """<All_Bram_Infos>
  <INST_1>
    <rid>0X00000010</rid><wid>0X00000010</wid><name>single_cwc/ram/mem0</name>
    <logic_width>32</logic_width><logic_depth>1024</logic_depth>
    <sub_bid_info>
      <address_offset>0</address_offset><data_offset>0</data_offset>
      <depth>1024</depth><width>32</width><num_section>1</num_section>
      <section_size>32</section_size><width_per_section>32</width_per_section>
      <bytes_in_per_section>4</bytes_in_per_section>
      <working_mode><address_step>1</address_step><depth>1024</depth><width>32</width>
        <num_byte>4</num_byte><ecc>0</ecc></working_mode>
    </sub_bid_info>
  </INST_1>
</All_Bram_Infos>
"""


def number(value):
    value = str(value).strip()
    return int(value, 16 if value.lower().startswith("0x") else 10)


def load(path):
    return ET.parse(str(path)).getroot()


def first_active_instance(cwc_root):
    for inst in cwc_root.findall("instance"):
        if inst.get("inst_enable") == "true":
            return inst
    raise AssertionError("no enabled instance in fixture")


def bid_entry_for(bid_root, piece):
    key = (number(piece.get("rid")), piece.get("name"))
    for entry in bid_root.iter():
        if entry.tag.startswith("INST_"):
            if (number(entry.findtext("rid")), entry.findtext("name")) == key:
                return entry
    raise AssertionError(f"BID entry not found for {key}")


def set_fields(root, fields):
    for path, value in fields.items():
        node = root.find(path)
        if node is None:
            raise AssertionError(f"fixture node not found: {path}")
        node.text = str(value)


def mutate(real_cwc, real_bid, idx, cwc_attrs, bid_sub_fields):
    """Return (cwc_root, bid_root) with piece idx and its BID sub record mutated."""
    cwc_root = load(real_cwc)
    bid_root = load(real_bid)
    piece = first_active_instance(cwc_root).find("logic_eram").findall("phy_eram")[idx]
    entry = bid_entry_for(bid_root, piece)
    for attr, value in cwc_attrs.items():
        piece.set(attr, str(value))
    set_fields(entry.find("sub_bid_info"), bid_sub_fields)
    return ET.ElementTree(cwc_root), ET.ElementTree(bid_root)


def run_checker(checker, cwc_path, bid_path, multipiece, map_out=None):
    cmd = [sys.executable, str(checker), str(cwc_path), str(bid_path)]
    if multipiece:
        cmd.append("--multipiece")
    if map_out is not None:
        cmd += ["--map-out", str(map_out)]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError:
        payload = {"raw_stdout": proc.stdout, "raw_stderr": proc.stderr}
    return proc.returncode, payload, cmd


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--checker", type=Path, required=True)
    parser.add_argument("--real-cwc", type=Path, required=True)
    parser.add_argument("--real-bid", type=Path, required=True)
    parser.add_argument("--outdir", type=Path, required=True)
    parser.add_argument("--map-out", type=Path, required=True)
    args = parser.parse_args()
    args.outdir.mkdir(parents=True, exist_ok=True)
    results = []

    def record(name, expect_accept, rc, payload, cmd, extra=None):
        ok = (rc == 0) == expect_accept
        if ok and not expect_accept and extra and "reason_contains" in extra:
            ok = extra["reason_contains"] in payload.get("reason", "")
        row = {"case": name, "expect_accept": expect_accept, "exit": rc,
               "accepted": payload.get("accepted"), "reason": payload.get("reason"),
               "mode": payload.get("mode"), "pass": ok}
        if extra:
            row.update({k: v for k, v in extra.items() if k != "reason_contains"})
        results.append(row)
        (args.outdir / f"{name}.json").write_text(json.dumps({"cmd": cmd, "exit": rc, "result": payload}, indent=2), encoding="utf-8")
        print(f"[{'PASS' if ok else 'FAIL'}] {name}: exit={rc} accepted={payload.get('accepted')} reason={payload.get('reason')}")

    # 1) real multipiece accept + map
    rc, payload, cmd = run_checker(args.checker, args.real_cwc, args.real_bid, True, args.map_out)
    extra = {}
    if rc == 0:
        inst = payload["instances"][0]
        mapping = json.loads(Path(args.map_out).read_text(encoding="utf-8"))["instances"][0]
        bits = mapping["bits"]
        data_bits = sum(1 for b in bits if b["kind"] == "data")
        status_bits = sum(1 for b in bits if b["kind"] == "status")
        extra = {"pieces": inst["physical_pieces"], "data_coverage": inst["data_coverage"],
                 "map_bits": len(bits), "map_data_bits": data_bits, "map_status_bits": status_bits,
                 "map_ok": data_bits == 288 and status_bits == 1 and len(bits) == 289}
        if not extra["map_ok"]:
            rc = 99
    record("real_multipiece", True, rc, payload, cmd, extra)

    # 2) real strict rejected (default-mode regression guard)
    rc, payload, cmd = run_checker(args.checker, args.real_cwc, args.real_bid, False)
    record("real_strict", False, rc, payload, cmd, {"reason_contains": "BID width mismatch"})

    # 3/4) synthetic single-segment accepted by both modes
    syn_cwc = args.outdir / "synthetic_single.cwc"
    syn_bid = args.outdir / "synthetic_single.bid"
    syn_cwc.write_text(SYNTH_CWC, encoding="utf-8")
    syn_bid.write_text(SYNTH_BID, encoding="utf-8")
    for name, multi in (("single_strict", False), ("single_multipiece", True)):
        rc, payload, cmd = run_checker(args.checker, syn_cwc, syn_bid, multi)
        record(name, True, rc, payload, cmd)

    # 5) gap: piece at data_offset 100 -> 101 (CWC + BID)
    cwc_root, bid_root = mutate(args.real_cwc, args.real_bid, 4, {"data_offset": "101"}, {"data_offset": "101"})
    gap_cwc, gap_bid = args.outdir / "neg_gap.cwc", args.outdir / "neg_gap.bid"
    cwc_root.write(gap_cwc)
    bid_root.write(gap_bid)
    rc, payload, cmd = run_checker(args.checker, gap_cwc, gap_bid, True)
    record("neg_gap", False, rc, payload, cmd, {"reason_contains": "gap/overlap"})

    # 6) overlap: piece at data_offset 120 -> 110
    cwc_root, bid_root = mutate(args.real_cwc, args.real_bid, 5, {"data_offset": "110"}, {"data_offset": "110"})
    ov_cwc, ov_bid = args.outdir / "neg_overlap.cwc", args.outdir / "neg_overlap.bid"
    cwc_root.write(ov_cwc)
    bid_root.write(ov_bid)
    rc, payload, cmd = run_checker(args.checker, ov_cwc, ov_bid, True)
    record("neg_overlap", False, rc, payload, cmd, {"reason_contains": "gap/overlap"})

    # 7) width overflow: piece width 20 -> 300 (CWC + BID sub/section/wm width)
    cwc_root, bid_root = mutate(args.real_cwc, args.real_bid, 9,
                                {"width": "300", "width_per_section": "300", "working_mode_width": "300"},
                                {"width": "300", "width_per_section": "300", "working_mode/width": "300"})
    wo_cwc, wo_bid = args.outdir / "neg_width_overflow.cwc", args.outdir / "neg_width_overflow.bid"
    cwc_root.write(wo_cwc)
    bid_root.write(wo_bid)
    rc, payload, cmd = run_checker(args.checker, wo_cwc, wo_bid, True)
    record("neg_width_overflow", False, rc, payload, cmd, {"reason_contains": "exceeds BID logic_width"})

    # 8) working mode mismatch: piece wm depth 1024 -> 512 (CWC only)
    cwc_root, bid_root = mutate(args.real_cwc, args.real_bid, 9, {"working_mode_depth": "512"}, {})
    mm_cwc, mm_bid = args.outdir / "neg_mode_mismatch.cwc", args.outdir / "neg_mode_mismatch.bid"
    cwc_root.write(mm_cwc)
    bid_root.write(mm_bid)
    rc, payload, cmd = run_checker(args.checker, mm_cwc, mm_bid, True)
    record("neg_mode_mismatch", False, rc, payload, cmd, {"reason_contains": "working depth mismatch"})

    # 9) wrong rid (CWC only)
    cwc_root, bid_root = mutate(args.real_cwc, args.real_bid, 0, {"rid": "0X0000FFFF"}, {})
    wr_cwc, wr_bid = args.outdir / "neg_wrong_rid.cwc", args.outdir / "neg_wrong_rid.bid"
    cwc_root.write(wr_cwc)
    bid_root.write(wr_bid)
    rc, payload, cmd = run_checker(args.checker, wr_cwc, wr_bid, True)
    record("neg_wrong_rid", False, rc, payload, cmd, {"reason_contains": "BID identity"})

    summary = {"cases": results, "failed": sum(1 for r in results if not r["pass"]), "total": len(results)}
    (args.outdir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"SUMMARY: {summary['total'] - summary['failed']}/{summary['total']} passed")
    return 0 if summary["failed"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
