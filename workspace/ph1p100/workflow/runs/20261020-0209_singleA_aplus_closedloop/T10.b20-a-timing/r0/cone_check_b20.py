#!/usr/bin/env python3
"""cone_check_b20.py -- mechanical cone-break proof on a routed/gate netlist.

Walks the Anlogic netlist and asks: is there a purely combinational path from the
Q output of the `a1_abort_reg` flop(s) (u_a1/a1_abort_reg*) to any ERAM read
address input pin `addrb` of the `smem_syn_*` memories?

Only combinational cell outputs (LUT `of`/`ofb`, ...) are traversed; registered
outputs (`oqb`, `oq`, `q`, ERAM `dob`, ...) are treated as a hard boundary.  This
is independent of the timing report (which only lists critical paths) and can be
run on the b19 netlist as a positive control (it must find a path there).

Usage:  python cone_check_b20.py <netlist.v> [--expect-path|--expect-clean]
Exit:   0 = expectation met, 1 = violated, 2 = parse/usage problem
"""
import json
import re
import sys

COMB_OUT = {"of", "ofb", "ofa", "o", "ob", "cout", "s", "so"}
REG_OUT = {"oqa", "oqb", "oq", "q", "dob", "dob_extra"}
OUT_PINS = COMB_OUT | REG_OUT
CLK_PINS = {"clk", "clka", "clkb", "ck"}


def parse(path):
    inst_re = re.compile(r"^\s*\\(\S+)\s*\(\s*$")
    pin_re = re.compile(r"^\s*\.(\w+)\s*\((.*?)\)\s*[,;]?\s*$")
    type_re = re.compile(r"^\s*(PH1P_[A-Z0-9_]+|RAM[A-Z0-9_]*|LUT[0-9]+)\b")
    cells = {}
    order = []
    cur = None
    cur_type = "?"
    last_type = "?"
    # The A1 abort cone lives entirely inside camera_a1_uart_top (u_a1/...) plus
    # the a1_frame_top ERAM (u_a1/u_a1/smem_syn_*).  Restricting the graph to that
    # subtree keeps the parse small; anything outside it cannot be on an
    # a1_abort_reg -> smem.addrb combinational path.
    keep = "u_a1/"
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
                if name.startswith(keep):
                    cur = name
                    cur_type = last_type
                    cells[cur] = {"type": cur_type, "pins": {}}
                    order.append(cur)
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


def main():
    path = sys.argv[1]
    expect = sys.argv[2] if len(sys.argv) > 2 else "--expect-clean"
    cells = parse(path)
    consumers = {}
    for name, c in cells.items():
        for pin, expr in c["pins"].items():
            if pin in OUT_PINS:
                continue
            for n in nets_of(expr):
                consumers.setdefault(n, []).append((name, pin))

    starts = set()
    abort_cells = [n for n in cells if n.startswith("u_a1/a1_abort_reg")]
    for name in abort_cells:
        pins = cells[name]["pins"]
        for op in ("oqa", "oqb", "oq", "q"):
            if op in pins:
                for n in nets_of(pins[op]):
                    if not n.startswith("open_n"):
                        starts.add(n)
    # The abort flop's Q is the a1_frame_top `abort` port net.  Prefer exactly
    # that net so a second register sharing the same slice (e.g. an unrelated
    # oqb in the same LSLICE) cannot seed the walk.
    port_net = r"\u_a1/u_a1/abort"
    if port_net in starts:
        starts = {port_net}
    starts = sorted(starts)

    hit_nets = {}
    seen = set(starts)
    frontier = list(starts)
    while frontier:
        net = frontier.pop()
        for (name, pin) in consumers.get(net, ()):
            c = cells[name]
            if name.startswith("u_a1/u_a1/smem_syn_") and pin == "addrb":
                hit_nets.setdefault(name, []).append(net)
                continue
            if pin in CLK_PINS or pin in OUT_PINS:
                continue
            for op in COMB_OUT:
                if op in c["pins"]:
                    for nn in nets_of(c["pins"][op]):
                        if nn.startswith("open_n") or nn in seen:
                            continue
                        seen.add(nn)
                        frontier.append(nn)

    res = {
        "netlist": path,
        "cells_parsed": len(cells),
        "abort_flop_q_nets": starts,
        "cone_nets": len(seen),
        "smem_addrb_hits": {k: sorted(set(v))[:6] for k, v in hit_nets.items()},
        "hit_count": sum(len(v) for v in hit_nets.values()),
    }
    clean = res["hit_count"] == 0
    res["expectation"] = expect
    res["result"] = ("PASS_cone_clean" if (expect == "--expect-clean" and clean)
                     else "FAIL_path_exists" if expect == "--expect-clean"
                     else "PASS_positive_control" if not clean
                     else "FAIL_positive_control_no_path")
    print(json.dumps(res, indent=2))
    print("CONE_CHECK %s hits=%d cone_nets=%d starts=%s" %
          (res["result"], res["hit_count"], res["cone_nets"], starts[:4]))
    if expect == "--expect-clean":
        return 0 if clean else 1
    return 0 if not clean else 1


if __name__ == "__main__":
    sys.exit(main())
