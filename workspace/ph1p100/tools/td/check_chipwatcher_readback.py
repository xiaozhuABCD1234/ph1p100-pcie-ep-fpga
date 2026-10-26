"""Check CWC physical readback mapping against its native BID; no hardware access.

Default mode keeps the original strict single-section / full-depth geometry:
every physical ERAM piece must carry the whole logical width (single wide RAM).

--multipiece adds a fail-closed multi-piece coverage check for TD 2026.2
auto-created ChipWatcher instances (one logical ERAM tiled by several physical
ERAMs).  For every enabled instance it requires:
  * exactly one logic_eram; positive width (data bits) and depth;
  * every piece resolves to a unique BID entry (normalised rid + name), WID and
    BID logic_depth match, and per-piece fields (address_offset, data_offset,
    depth, width, num_section, section_size, width_per_section) match the BID;
  * address_offset == 0, num_section == 1, address_step == 1 (full depth,
    address mapping contiguous by construction), bytes_in_per_section matches;
  * working_mode_* fields match BID per piece, ECC maps consistently and
    super-wide mode is disabled;
  * all pieces share one BID logic_width, piece width <= that logic_width;
  * piece data ranges tile [0, ram_logic_width) contiguously - no gaps, no
    overlaps - and ram_logic_width == the tiled end;
  * data width W = logic_eram width; at most one extra tail bit beyond W
    (TD 2026.2 stores one status bit after the data bits): ram_width - W <= 1,
    and coverage of [0, W) must be exactly 288/288-style full.
--map-out writes a machine readable bit -> piece/offset coverage map.
Exit codes are unchanged: 0 = accepted, 1 = rejected.
"""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET


def number(value):
    value = str(value).strip()
    return int(value, 16 if value.lower().startswith("0x") else 10)


def _bid_entries(bid):
    entries = {}
    for entry in bid.iter():
        if entry.tag.startswith("INST_"):
            key = (number(entry.findtext("rid")), entry.findtext("name"))
            assert key not in entries, f"duplicate BID identity: {key}"
            entries[key] = entry
    return entries


def _check_common(piece, entry, depth, name):
    """Strict per-piece checks shared by the default and multipiece modes."""
    subs = entry.findall("sub_bid_info")
    assert len(subs) == 1, f"{name}: unsupported BID sections"
    sub = subs[0]
    for field in ("address_offset", "data_offset", "depth", "width", "num_section", "section_size", "width_per_section"):
        assert number(piece.get(field)) == number(sub.findtext(field)), f"{name}: {field} mismatch"
    assert number(piece.get("address_offset")) == 0, f"{name}: unsupported address offset"
    assert number(piece.get("num_section")) == 1, f"{name}: unsupported sections"
    assert number(piece.get("address_step")) == number(sub.findtext("working_mode/address_step")) == 1
    assert number(piece.get("bytes_in_per_section")) == number(sub.findtext("bytes_in_per_section"))
    for field in ("depth", "width", "num_byte"):
        assert number(piece.get("working_mode_" + field)) == number(sub.findtext("working_mode/" + field)), f"{name}: working {field} mismatch"
    ecc = "enable" if number(sub.findtext("working_mode/ecc")) else "disable"
    assert piece.get("working_mode_ecc") == ecc, f"{name}: working ECC mismatch"
    assert piece.get("working_mode_super_wide") == "disable", f"{name}: unsupported super-wide mode"
    assert number(piece.get("depth")) == depth, f"{name}: partial depth"
    return sub


def check(cwc, bid):
    """Default strict mode: single-section, full-depth geometry (unchanged)."""
    if not __debug__:
        raise ValueError("run this validator without Python -O")
    entries = _bid_entries(bid)
    instances = []
    for instance in cwc.findall("instance"):
        if instance.get("inst_enable") != "true":
            continue
        name = instance.get("name")
        logical = instance.findall("logic_eram")
        assert len(logical) == 1, f"{name}: missing/unsupported logical ERAM"
        ram = logical[0]
        width, depth = number(ram.get("width")), number(ram.get("depth"))
        assert width > 0 and depth > 0, f"{name}: invalid dimensions"
        pieces = ram.findall("phy_eram")
        assert pieces, f"{name}: missing physical ERAM readback mapping"
        coverage = [0] * width
        seen = set()
        for piece in pieces:
            key = (number(piece.get("rid")), piece.get("name"))
            assert key in entries and key not in seen, f"{name}: wrong/duplicate BID identity {key}"
            seen.add(key)
            entry = entries[key]
            assert number(entry.findtext("wid")) == number(piece.get("wid")), f"{name}: WID mismatch"
            assert number(entry.findtext("logic_width")) == width, f"{name}: BID width mismatch"
            assert number(entry.findtext("logic_depth")) == depth, f"{name}: BID depth mismatch"
            _check_common(piece, entry, depth, name)
            start, size = number(piece.get("data_offset")), number(piece.get("width"))
            assert size > 0 and 0 <= start < start + size <= width, f"{name}: invalid data range"
            for bit in range(start, start + size):
                coverage[bit] += 1
        assert all(count == 1 for count in coverage), f"{name}: data coverage has gaps/overlap"
        instances.append({"name": name, "width": width, "depth": depth, "physical_pieces": len(pieces)})
    assert instances, "no enabled instances"
    return instances


def check_multipiece(cwc, bid):
    """Fail-closed multi-piece coverage mode (see module docstring)."""
    if not __debug__:
        raise ValueError("run this validator without Python -O")
    entries = _bid_entries(bid)
    instances = []
    for instance in cwc.findall("instance"):
        if instance.get("inst_enable") != "true":
            continue
        name = instance.get("name")
        logical = instance.findall("logic_eram")
        assert len(logical) == 1, f"{name}: missing/unsupported logical ERAM"
        ram = logical[0]
        width, depth = number(ram.get("width")), number(ram.get("depth"))
        assert width > 0 and depth > 0, f"{name}: invalid dimensions"
        pieces = ram.findall("phy_eram")
        assert pieces, f"{name}: missing physical ERAM readback mapping"
        bid_widths = set()
        seen = set()
        recs = []
        for piece in pieces:
            key = (number(piece.get("rid")), piece.get("name"))
            assert key in entries and key not in seen, f"{name}: wrong/duplicate BID identity {key}"
            seen.add(key)
            entry = entries[key]
            assert number(entry.findtext("wid")) == number(piece.get("wid")), f"{name}: WID mismatch"
            lw = number(entry.findtext("logic_width"))
            assert lw >= number(piece.get("width")), f"{name}: piece width exceeds BID logic_width"
            bid_widths.add(lw)
            assert number(entry.findtext("logic_depth")) == depth, f"{name}: BID depth mismatch"
            _check_common(piece, entry, depth, name)
            start, size = number(piece.get("data_offset")), number(piece.get("width"))
            assert size > 0 and start >= 0, f"{name}: invalid data range"
            recs.append({"piece": piece, "start": start, "size": size,
                         "rid": piece.get("rid"), "name": piece.get("name"),
                         "bid_logic_width": lw})
        assert len(bid_widths) == 1, f"{name}: inconsistent BID logic_width across pieces {sorted(bid_widths)}"
        ram_width = bid_widths.pop()
        recs.sort(key=lambda r: r["start"])
        cursor = 0
        for index, r in enumerate(recs):
            assert r["start"] == cursor, f"{name}: data range gap/overlap at bit {cursor} (piece starts {r['start']})"
            cursor += r["size"]
        assert cursor == ram_width, f"{name}: tiled width {cursor} != BID logic_width {ram_width}"
        status_bits = ram_width - width
        assert 0 <= status_bits <= 1, f"{name}: unsupported extra bits beyond data width ({status_bits})"
        bits = []
        for index, r in enumerate(recs):
            for offset in range(r["size"]):
                bit = r["start"] + offset
                bits.append({"bit": bit, "piece": index, "piece_offset": offset,
                             "kind": "data" if bit < width else "status"})
        data_bits = sum(1 for b in bits if b["kind"] == "data")
        assert data_bits == width, f"{name}: data coverage {data_bits}/{width}"
        instances.append({
            "name": name,
            "width": width,
            "depth": depth,
            "ram_logic_width": ram_width,
            "status_bits": status_bits,
            "physical_pieces": len(recs),
            "data_coverage": f"{data_bits}/{width}",
            "pieces": [{"index": i, "rid": r["rid"], "name": r["name"],
                        "data_offset": r["start"], "width": r["size"],
                        "bid_logic_width": r["bid_logic_width"]} for i, r in enumerate(recs)],
            "bits": bits,
        })
    assert instances, "no enabled instances"
    return instances


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("cwc", type=Path)
    parser.add_argument("bid", type=Path)
    parser.add_argument("--multipiece", action="store_true",
                        help="enable the fail-closed multi-piece coverage mode (default: strict single-section)")
    parser.add_argument("--map-out", type=Path, default=None,
                        help="with --multipiece: write a machine readable bit -> piece/offset coverage map")
    args = parser.parse_args()
    if args.map_out is not None and not args.multipiece:
        parser.error("--map-out requires --multipiece")
    try:
        if args.multipiece:
            instances = check_multipiece(ET.parse(args.cwc).getroot(), ET.parse(args.bid).getroot())
            result = {"accepted": True, "mode": "multipiece", "instances": instances}
            if args.map_out is not None:
                Path(args.map_out).write_text(json.dumps(result, indent=2), encoding="utf-8")
                result = {"accepted": True, "mode": "multipiece",
                          "instances": [dict(inst, bits="see map-out") for inst in instances],
                          "map_out": str(args.map_out)}
        else:
            result = {"accepted": True, "mode": "strict",
                      "instances": check(ET.parse(args.cwc).getroot(), ET.parse(args.bid).getroot())}
    except (AssertionError, ValueError, TypeError, ET.ParseError) as error:
        result = {"accepted": False, "mode": "multipiece" if args.multipiece else "strict",
                  "reason": str(error)}
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["accepted"] else 1)
