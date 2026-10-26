#!/usr/bin/env python3
"""cone_firsthop_b20.py -- decisive first-hop dependency check for the abort cone.

The routed netlist walk in cone_check_b20.py is LUT-agnostic (it follows every
combinational output of a reached cell), so it is a conservative upper bound.
This script settles the structural question exactly at the first hop: for every
cell that consumes the abort flop Q net, decode the LSLICE LUT INIT + SD pin map
and ask whether the LUT output actually *depends* on that pin.  If no first-hop
cell depends on the abort net, no combinational path from the abort flop to any
downstream net can exist.

Validation: on the b19 netlist the same code must report at least one dependent
first hop (that design really had abort -> smem.addrb timing paths).

Usage: python cone_firsthop_b20.py <netlist.v>
"""
import json
import re
import sys

ABORT_NET = r"\u_a1/u_a1/abort"


def parse(path):
    inst_re = re.compile(r"^\s*\\(\S+)\s*\(\s*$")
    pin_re = re.compile(r"^\s*\.(\w+)\s*\((.*?)\)\s*[,;]?\s*$")
    type_re = re.compile(r"^\s*(PH1P_[A-Z0-9_]+|RAM[A-Z0-9_]*|LUT[0-9]+)\b")
    cells = {}
    cur = None
    last_type = "?"
    cur_type = "?"
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line.lstrip().startswith("//"):
                continue
            m = type_re.match(line)
            if m:
                last_type = m.group(1)
                continue
            m = inst_re.match(line)
            if m:
                name = m.group(1)
                if name.startswith("u_a1/"):
                    cur = name
                    cur_type = last_type
                    cells[cur] = {"type": cur_type, "pins": {}}
                else:
                    cur = None
                continue
            if cur is None:
                continue
            m = pin_re.match(line)
            if m:
                cells[cur]["pins"][m.group(1)] = m.group(2)
                continue
            if line.strip().startswith(");"):
                cur = None
    return cells


def nets_of(expr):
    return re.findall(r"\\[^\s,(){}]+", expr)


def const_int(s):
    m = re.search(r"'([bdh])([0-9a-fA-F_xzXZ]+)", s)
    if not m:
        return None
    base = {"b": 2, "d": 10, "h": 16}[m.group(1)]
    digits = m.group(2).replace("_", "")
    try:
        return int(digits, base)
    except ValueError:
        return None


def lut_depends(init, letter, nvars):
    if init is None or letter is None:
        return None
    for i in range(1 << nvars):
        if (init >> i) & 1 != (init >> (i | (1 << letter))) & 1:
            return True
    return False


def analyse(path, net=ABORT_NET):
    cells = parse(path)
    out = []
    seen_cons = set()
    for name, c in cells.items():
        for pin, expr in c["pins"].items():
            if pin in ("oqa", "oqb", "oq", "q", "of", "ofb", "dob", "dob_extra"):
                continue
            for n in nets_of(expr):
                if n != net:
                    continue
                key = (name, pin)
                if key in seen_cons:
                    continue
                seen_cons.add(key)
                p = c["pins"]
                row = {"cell": name, "type": c["type"], "pin": pin,
                       "lutmode": p.get("LUTMODE", "").strip('"'), "depends": None}
                for half in ("A", "B"):
                    init = const_int(p.get("INIT_LUT5" + half, ""))
                    mode = p.get("LUTMODE", "").strip('"')
                    nv = 5
                    letter = None
                    for k in range(5):
                        sd = p.get("LUT5%s_SD%d" % (half, k), "").strip('"')
                        if sd.upper() == pin.upper():
                            letter = k
                    if letter is None:
                        continue
                    d = lut_depends(init, letter, nv)
                    row["half_%s" % half] = {"init": init, "letter": letter,
                                             "depends": d, "mode": mode}
                    if d:
                        row["depends"] = True
                if row["depends"] is None:
                    # pure register / non-LUT first hop: a D pin of a flop is a
                    # boundary, not a combinational continuation.
                    row["depends"] = False if ("oqa" in p or "oqb" in p) else None
                out.append(row)
    dep = [r for r in out if r["depends"] is True]
    return {"netlist": path, "start_net": net, "first_hop_consumers": out,
            "dependent_first_hops": dep, "verdict":
            "PASS_cone_empty" if not dep else "FAIL_first_hop_depends"}


if __name__ == "__main__":
    res = analyse(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else ABORT_NET)
    print(json.dumps(res, indent=2))
    print("FIRSTHOP %s consumers=%d dependent=%d" %
          (res["verdict"], len(res["first_hop_consumers"]),
           len(res["dependent_first_hops"])))
    sys.exit(0 if res["verdict"] == "PASS_cone_empty" else 1)
