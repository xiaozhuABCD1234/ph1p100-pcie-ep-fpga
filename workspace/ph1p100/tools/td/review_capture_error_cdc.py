"""Check the routed sticky capture-error synchronizer; bounded, not formal CDC."""
from pathlib import Path
import argparse
import hashlib
import json
import re

p = argparse.ArgumentParser()
p.add_argument('project', type=Path)
a = p.parse_args()
netlist = a.project / 'capture_routed.v'
s = netlist.read_text()

def pins(text):
    return {k: v.replace('\\', '').replace(' ', '')
            for k, v in re.findall(r'\.(\w+)\(([^)]+)\)', text)}

blocks = list(re.finditer(
    r'(?m)^  (PH1P_PHY_[LM]SLICE) #\(\n(.*?)\)\n    (\\\S+)  \(\n(.*?)\);',
    s, re.S))
qs = {}
for m in blocks:
    for q in ('oqa', 'oqb'):
        z = pins(m[4])
        if q in z:
            assert z[q] not in qs, z[q]
            qs[z[q]] = (m, q)
roots = {}
for m in re.finditer(r'(?m)^  PH1P_PHY_SCLK\b[\s\S]*?(?=^  \w|\Z)', s):
    z = pins(m[0])
    if 'clkout' in z:
        roots[z['clkout']] = z['clkin']

prefix = 'u_ddrmc_test_top/'
names = [prefix + n for n in ('cap_error_seen', 'cap_error_sync[0]', 'cap_error_sync[1]')]
rows = []
for name in names:
    m, q = qs[name]
    z = pins(m[4])
    v = dict(re.findall(r'(?m)^    \.(\w+)\("([^"\n]+)"\)', m[2]))
    letter = 'A' if q == 'oqa' else 'B'
    assert v['LATCHMODE'] == 'DFF' and v['ASRMUX'] == 'INV'
    assert v['SSRMUX'] == '0' and v['CLKMUX'] == 'SIG'
    assert v['CE' + letter + 'MUX'] == '1'
    assert v['REG' + letter + '_REGSET_ASYNC'] == 'RESET'
    rows.append({'net': name, 'cell': m[3], 'q': q, 'clock': roots[z['clk']],
                 'reset_n': z['asr'], 'select': v['REG' + letter + '_SD'],
                 'pins': z})
assert rows[1]['select'] in ('IMA', 'IMB')
assert rows[2]['select'] in ('IMA', 'IMB')
assert rows[1]['pins'][rows[1]['select'].lower()] == names[0]
assert rows[2]['pins'][rows[2]['select'].lower()] == names[1]
fifo = json.loads((a.project / 'u_fifo_cdc_audit.json').read_text())
def fifo_clock(name):
    return roots[fifo['rows'][name]['pins']['clk']]
assert rows[0]['clock'] == fifo_clock('wgray[0]')
assert rows[1]['clock'] == rows[2]['clock'] == fifo_clock('rgray[0]')
assert len({r['reset_n'] for r in rows}) == 1
result = {'netlist_sha256': hashlib.sha256(netlist.read_bytes()).hexdigest(),
          'rows': rows, 'result': 'Registered source, direct stage0/stage1, expected clocks and common active-low async reset.',
          'limits': 'Does not prove MTBF, reset recovery/removal, analog behavior or whole-design CDC.'}
(a.project / 'cap_error_cdc_review.json').write_text(json.dumps(result, indent=2) + '\n')
print('CAP_ERROR_CDC_PASS source_registered direct_links=2 expected_clocks common_reset')
