#!/usr/bin/env python3
"""cone_trace_b20.py -- shortest LUT-only route abort -> smem.addrb, with hops."""
import re
import sys
import collections

sys.path.insert(0, r"D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b20-a-timing\r0")
import cone_check_b20 as cc

path = sys.argv[1]
cells = cc.parse(path)
consumers = {}
for name, c in cells.items():
    for pin, expr in c["pins"].items():
        if pin in cc.OUT_PINS:
            continue
        for n in cc.nets_of(expr):
            consumers.setdefault(n, []).append((name, pin))

start = r"\u_a1/u_a1/abort"
prev = {start: None}
q = collections.deque([start])
hit = None
while q and hit is None:
    net = q.popleft()
    for (name, pin) in consumers.get(net, ()):
        c = cells[name]
        if name.startswith("u_a1/u_a1/smem_syn_") and pin == "addrb":
            hit = (net, name, pin)
            break
        if pin in cc.CLK_PINS or pin in cc.OUT_PINS:
            continue
        for op in cc.COMB_OUT:
            if op in c["pins"]:
                for nn in cc.nets_of(c["pins"][op]):
                    if nn.startswith("open_n") or nn in prev:
                        continue
                    prev[nn] = (net, name, pin, op)
                    q.append(nn)

if not hit:
    print("NO_PATH")
    sys.exit(0)
net, name, pin = hit
hops = [(net, name, pin)]
cur = net
while prev.get(cur):
    pnet, cname, cpin, op = prev[cur]
    hops.append((pnet, cname, cpin, op))
    cur = pnet
hops.reverse()
print("HOPS=%d" % (len(hops) - 1))
for h in hops:
    print("  " + " | ".join(str(x) for x in h))
