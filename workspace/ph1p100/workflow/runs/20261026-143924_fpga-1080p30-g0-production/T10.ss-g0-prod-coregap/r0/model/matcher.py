"""Offline LZ77 stage matcher for the b11 a1_deflate_core scan engine.

Purpose: (1) cross-check the 1-frame stage-probe counters that are read-only
tapped from a1_deflate_core, (2) quantify parameter variants (hash size, match
window) that are *not* implementable without RTL changes, from the frozen
content bytes only.

Fidelity notes (all read from r0/src/a1_deflate_core.v, b11 frozen copy):
  * hash3(a,b,c) = {a,b[1:0]} ^ {b[5:0],c[3:0]} ^ {c[7:0],a[1:0]}   (10 bits, 1024 entries)
  * one candidate per entry, entry carries blk_tag -> the table is block-scoped
  * hit requires: tag match, the 3 bytes equal, 0 < dist <= MAX_DIST, pos <= blk_n-3
  * extension compares bm[pos+3+k] vs bm[ref+3+k], both inside the current block,
    capped at MAX_MATCH = 258
  * the FSM inserts the current position into the table on every scanned
    position (literal or match start) -- positions covered by a match are skipped
  * block size MAX_BLOCK = 4800, block = stored vs fixed chosen by bit cost

Not modelled: the RTL's early candidate abort and the exact ERAM/pipeline
micro-cycles; the cycle model in coregap_model.py absorbs those terms with a
fitted per-block constant.  This script only produces symbol statistics.
"""

import json
import sys
from pathlib import Path

MAX_BLOCK = 4800
MAX_MATCH = 258

LEN_BASE = {  # len -> (code-257, extra bits)
    3: (0, 0), 4: (1, 0), 5: (2, 0), 6: (3, 0), 7: (4, 0), 8: (5, 0), 9: (6, 0), 10: (7, 0),
}


def len_cost(n):
    """fixed-Huffman length code cost in bits: 7 base + extra bits."""
    if n <= 10:
        extra = 0
    elif n <= 18:
        extra = 1
    elif n <= 34:
        extra = 2
    elif n <= 66:
        extra = 3
    elif n <= 130:
        extra = 4
    elif n <= 257:
        extra = 5
    else:
        extra = 0  # 258 -> code 285
    return 7 + extra


def lit_cost(v):
    return 8 if v < 144 else 9


def dist_cost(d):
    """fixed-Huffman distance code: 5 bits + extra (dist <= 8192 -> extra 0..7)."""
    if d <= 4:
        extra = 0
    elif d <= 8:
        extra = 1
    elif d <= 16:
        extra = 2
    elif d <= 32:
        extra = 3
    elif d <= 64:
        extra = 4
    elif d <= 128:
        extra = 5
    elif d <= 256:
        extra = 6
    else:
        extra = 7
    return 5 + extra


def hash3(a, b, c, hbits=10):
    h = ((a << 2) | (b & 3)) ^ (((b & 0x3F) << 4) | (c & 0x0F)) ^ ((c << 2) | (a & 3))
    return h & ((1 << hbits) - 1)


def scan_block(bm, hbits=10, max_dist=2048, max_match=MAX_MATCH):
    """Return (literals, matches, sum_len, max_match_seen, fixed_bits)."""
    n = len(bm)
    table = {}
    literals = 0
    matches = 0
    sum_len = 0
    mx = 0
    bits = 0
    pos = 0
    while pos < n:
        hit = None
        if pos <= n - 3:
            h = hash3(bm[pos], bm[pos + 1], bm[pos + 2], hbits)
            e = table.get(h)
            table[h] = pos  # insert current position (read-before-write, as in RTL)
            if e is not None:
                d = pos - e
                if 0 < d <= max_dist and bm[e] == bm[pos] and bm[e + 1] == bm[pos + 1] \
                        and bm[e + 2] == bm[pos + 2]:
                    hit = (e, d)
        if hit is None:
            literals += 1
            bits += lit_cost(bm[pos])
            pos += 1
            continue
        e, d = hit
        ln = 3
        # extension: both sides stay inside the block
        while ln < max_match and pos + ln < n and e + ln < n and bm[pos + ln] == bm[e + ln]:
            ln += 1
        matches += 1
        sum_len += ln
        mx = max(mx, ln)
        bits += len_cost(ln) + dist_cost(d)
        pos += ln
    return dict(literals=literals, matches=matches, sum_len=sum_len, max_match=mx, fixed_bits=bits)


def frame_stats(path, frame_bytes=2592000, hbits=10, max_dist=2048):
    data = Path(path).read_bytes()
    blocks = [data[i:i + MAX_BLOCK] for i in range(0, len(data), MAX_BLOCK)]
    tot = dict(literals=0, matches=0, sum_len=0, max_match=0, blocks=len(blocks),
               fixed_blocks=0, stored_blocks=0, stored_bytes=0, fixed_stream_bytes=0)
    for b in blocks:
        st = scan_block(b, hbits=hbits, max_dist=max_dist)
        fixed_cost = st["fixed_bits"]
        stored_cost = 8 * len(b) + 40  # stored header/len + byte alignment (approx)
        tot["literals"] += st["literals"]
        tot["matches"] += st["matches"]
        tot["sum_len"] += st["sum_len"]
        tot["max_match"] = max(tot["max_match"], st["max_match"])
        if fixed_cost + 8 < stored_cost:
            tot["fixed_blocks"] += 1
            tot["fixed_stream_bytes"] += (fixed_cost + 7) // 8
        else:
            tot["stored_blocks"] += 1
            tot["stored_bytes"] += len(b)
            tot["fixed_stream_bytes"] += 5  # stored header + len
    tot["bytes"] = len(data)
    tot["stream_bytes"] = tot["fixed_stream_bytes"] + tot["stored_bytes"]
    return tot


if __name__ == "__main__":
    out = {}
    args = sys.argv[1:]
    for spec in args:
        name, path = spec.split("=", 1)
        out[name] = frame_stats(path)
        s = out[name]
        print(name, json.dumps(s))
    if "--json" in args:
        pass
