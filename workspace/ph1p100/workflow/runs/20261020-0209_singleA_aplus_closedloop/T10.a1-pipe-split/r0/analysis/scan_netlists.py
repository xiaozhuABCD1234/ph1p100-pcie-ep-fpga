#!/usr/bin/env python3
# T10.a1-qor-retime r0 -- static clock/reset structure scan for TD write_verilog netlists.
# Linear-time scan (statement split on ';'), no nested-quantifier regex.
# Purpose: verify (a) every sequential cell (AL_MAP_SEQ*) is clocked by the single design
# clock net and (b) the reset/control structure is comparable between the pre-optimization
# (elaborate) netlist and the post-retiming/post-route netlists.
# Usage: python scan_netlists.py <out.txt> <netlist1> [netlist2 ...]
import re, sys, json, collections, os

SEQ_RE = re.compile(r'\bAL_MAP_SEQ(?:_GSR)?\b')
PIN_RE = re.compile(r'\.([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*([^)]*?)\s*\)')
CNT_RE = {name: re.compile(r'\b%s\b' % name) for name in
          ('AL_MAP_SEQ', 'AL_MAP_LUT', 'AL_MAP_ADDER', 'AL_MAP_MUX', 'ERAM', 'DRAM', 'GCLK', 'SCLK', 'PAD', 'IOBUF')}

def scan(path):
    txt = open(path, 'r', encoding='utf-8', errors='replace').read()
    txt = re.sub(r'//[^\n]*', '', txt)
    seq = []
    for m in SEQ_RE.finditer(txt):
        pre = txt[max(0, m.start() - 16):m.start()]
        if 'module' in pre:
            continue
        semi = txt.find(';', m.end())
        if semi < 0:
            continue
        stmt = txt[m.start():semi]
        pm = dict(PIN_RE.findall(stmt))
        seq.append(dict(clk=pm.get('clk', ''), sr=pm.get('sr', ''), ce=pm.get('ce', ''),
                        name=(re.search(r'\)\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(', stmt) or [None, '?'])[1]))
    counts = {k: len(v.findall(txt)) for k, v in CNT_RE.items()}
    return seq, counts

def summarize(path):
    seq, counts = scan(path)
    clk = collections.Counter(s['clk'] for s in seq)
    sr = collections.Counter(s['sr'] for s in seq)
    ce = collections.Counter(s['ce'] for s in seq)
    susp = [s for s in seq if not re.search(r'clk', s['clk'])]
    return dict(path=os.path.abspath(path), seq=len(seq), clk=clk, sr=sr, ce=ce, susp=susp, counts=counts)

def main():
    out = sys.argv[1]
    files = sys.argv[2:]
    lines = []
    res = {}
    for f in files:
        if not os.path.isfile(f):
            lines.append('MISSING %s' % f)
            continue
        r = summarize(f)
        res[f] = r
        lines.append('===== %s' % os.path.basename(f))
        lines.append('  bytes            : %d' % os.path.getsize(f))
        lines.append('  raw token counts : %s' % ', '.join('%s=%d' % (k, v) for k, v in r['counts'].items()))
        lines.append('  AL_MAP_SEQ insts : %d' % r['seq'])
        lines.append('  clk nets         : %s' % ', '.join('%s:%d' % (k, v) for k, v in r['clk'].most_common(20)))
        lines.append('  sr  nets         : %s' % ', '.join('%s:%d' % (k, v) for k, v in r['sr'].most_common(20)))
        lines.append('  ce  nets distinct: %d' % len(r['ce']))
        lines.append('  ce  top          : %s' % ', '.join('%s:%d' % (k, v) for k, v in r['ce'].most_common(8)))
        if r['susp']:
            lines.append('  SUSPICIOUS clk (no "clk" in net name): %d' % len(r['susp']))
            for s in r['susp'][:10]:
                lines.append('    %s' % s)
        else:
            lines.append('  SUSPICIOUS clk (no "clk" in net name): 0')
        lines.append('')
    names = list(res.keys())
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            a, b = res[names[i]], res[names[j]]
            sa, sb = set(a['clk']), set(b['clk'])
            ra, rb = set(a['sr']), set(b['sr'])
            lines.append('PAIR %s VS %s' % (os.path.basename(names[i]), os.path.basename(names[j])))
            lines.append('  clk net sets equal: %s  (only-in-A=%s only-in-B=%s)' % (sa == sb, sorted(sa - sb), sorted(sb - sa)))
            lines.append('  sr  net sets equal: %s  (only-in-A=%s only-in-B=%s)' % (ra == rb, sorted(ra - rb), sorted(rb - ra)))
            lines.append('  SEQ counts: %d vs %d (delta %+d)' % (a['seq'], b['seq'], b['seq'] - a['seq']))
            lines.append('')
    text = '\n'.join(lines)
    print(text)
    with open(out, 'w', encoding='utf-8') as fh:
        fh.write(text + '\n')

if __name__ == '__main__':
    main()
