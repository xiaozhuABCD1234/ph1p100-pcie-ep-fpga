"""Fault controls for the observed direct-AND/pixel-reset reference mapping.

Writes only isolated validation copies; the actual candidate is never changed.
This checks the bounded structural checker chain, not all possible CDC faults.
"""
from pathlib import Path
import argparse, datetime, hashlib, json, re, subprocess, sys

parser = argparse.ArgumentParser()
parser.add_argument('project', type=Path)
a = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
source = a.project.resolve()
raw = (source / 'capture_routed.v').read_bytes()
# Match the checkers' universal-newline parsing; retain raw source identity.
net = raw.decode().replace('\r\n', '\n')
out = Path('D:/TD/work/csi2/_validation') / ('reference_cdc_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
out.mkdir()
scripts = ['audit_display_cdc.py', 'review_display_cdc_functions.py', 'review_display_cdc_origins.py']
for name in scripts:
    (out / name).write_bytes((repo / 'tools/td' / name).read_bytes())
blocks = list(re.finditer(r'(?m)^  PH1P_PHY_[LM]SLICE #\(\n.*?\);', net, re.S))

def choose(token):
    found = [m for m in blocks if token in m[0]]
    assert len(found) == 1, (token, len(found))
    return found[0]

gate = choose('\\u_ddrmc_test_top/u_capture/u_display_fifo/rq1_wgray_reg[0]_syn_2  (')
truth = ".INIT_LUT5A(32'b10100000101000001010000010100000)"
bit = '.ic(\\u_ddrmc_test_top/u_capture/u_display_fifo/wgray [0])'
assert truth in gate[0] and bit in gate[0]
assert '.ia(\\u_ddrmc_test_top/u_capture/pixel_reset [1])' in gate[0]
reset_cells = [choose('.oqa(\\u_ddrmc_test_top/u_capture/pixel_reset [' + str(i) + '])') for i in range(2)]
capture_clock = json.loads((source / 'u_fifo_cdc_audit.json').read_bytes())['rows']['wgray[0]']['pins']['clk']

def splice(changes):
    data = net
    for m, changed in sorted(changes, key=lambda x: x[0].start(), reverse=True):
        assert changed != m[0]
        data = data[:m.start()] + changed + data[m.end():]
    return data

cases = [
    ('valid', net, None),
    ('wrong_truth', splice([(gate, gate[0].replace(truth, truth[:-2] + '1)'))]), 'Not a two-input AND'),
    ('wrong_bit', splice([(gate, gate[0].replace(bit, bit.replace('[0]', '[2]')))]), 'Missing same-bit input'),
    ('wrong_reset_domain', splice([(m, re.sub(r'(?m)^    \.clk\([^\n]+',
        lambda _: '    .clk(\\' + capture_clock + ' ),', m[0])) for m in reset_cells]), 'Reset domain mismatch')]
results = []
for label, data, expected in cases:
    root = out / label
    root.mkdir()
    (root / 'capture_routed.v').write_bytes(data.encode())
    commands = [('audit_display_cdc.py', ['--fifo', 'u_fifo']),
                ('audit_display_cdc.py', ['--fifo', 'u_display_fifo']),
                ('review_display_cdc_functions.py', []), ('review_display_cdc_origins.py', [])]
    runs = []
    for index, (name, args) in enumerate(commands):
        command = [sys.executable, '-X', 'utf8', str(out / name), str(root), *args]
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
        (root / f'{index}.txt').write_bytes(result.stdout)
        runs.append({'command': command, 'exit_code': result.returncode, 'log': f'{label}/{index}.txt'})
        if result.returncode:
            break
    if expected:
        assert runs[-1]['exit_code'] != 0 and expected.encode() in result.stdout, (label, result.stdout.decode())
    else:
        assert len(runs) == 4 and all(x['exit_code'] == 0 for x in runs), (label, result.stdout.decode())
    results.append({'case': label, 'expected': 'pass' if expected is None else 'rejection', 'accepted': True,
                    'netlist_sha256': hashlib.sha256(data.encode()).hexdigest(), 'runs': runs})
assert (source / 'capture_routed.v').read_bytes() == raw
obj = {'source': str(source), 'source_netlist_sha256': hashlib.sha256(raw).hexdigest(),
       'checker_hashes': {name: hashlib.sha256((out / name).read_bytes()).hexdigest() for name in scripts},
       'cases': results, 'boundary': 'Observed direct A*C AND and pixel_reset mapping. Invalid copies only; fail-fast chain, not separate coverage of each checker by every mutation.'}
(out / 'result.json').write_bytes((json.dumps(obj, indent=2) + '\n').encode())
print('REFERENCE_CDC_CONTROLS_PASS valid=1 rejected=3', out)
