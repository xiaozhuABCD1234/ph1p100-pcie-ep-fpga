# -*- coding: utf-8 -*-
"""Apply/restore one of two deliberate semantic mutations in the isolated shadow DUT (negative controls).
Usage:
  python mutate_shadow.py extract           # show target statements
  python mutate_shadow.py m1                # CRC advance fixed to 4 bytes (re-introduces bug (1) of change-report 8.2)
  python mutate_shadow.py m2                # tail decode closes one beat early
  python mutate_shadow.py restore           # restore pristine copy from the frozen project file
Records sha256 before/after into mutation-log.json (evidence)."""
import os, sys, hashlib, json, re

ROOT = r'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道'
FROZEN_DUT = ROOT + '/fpga/csi2/pcie_integration/rtl/checked/csi_rx_packet_integrity.v'
SHADOW_DUT = ROOT + '/workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r2/neg-shadow/fpga/csi2/pcie_integration/rtl/checked/csi_rx_packet_integrity.v'
LOG = ROOT + '/workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r2/neg-shadow/mutation-log.json'

def sha(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()

def log(entry):
    data = []
    if os.path.isfile(LOG):
        data = json.load(open(LOG, encoding='utf-8'))
    data.append(entry)
    json.dump(data, open(LOG, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)

def read():
    return open(SHADOW_DUT, encoding='utf-8').read()

def write(t):
    open(SHADOW_DUT, 'w', encoding='utf-8', newline='').write(t)

cmd = sys.argv[1]
if cmd == 'extract':
    t = read()
    m = re.search(r'wire\[15:0\] crc_next = .*?;', t, re.S)
    print('CRC SELECTION:')
    print(m.group(0) if m else 'NOT FOUND')
    m2 = re.search(r'wire tail_le4\s*=.*?;', t)
    print('TAIL_LE4:')
    print(m2.group(0) if m2 else 'NOT FOUND')
elif cmd in ('m1', 'm2'):
    t = read()
    before = sha(SHADOW_DUT)
    if cmd == 'm1':
        m = re.search(r'wire\[15:0\] crc_next = .*?;', t, re.S)
        assert m and m.group(0).count('\n') >= 1, 'crc_next pattern not found'
        old = m.group(0)
        new = "wire[15:0] crc_next = crc_u4;  // NEGATIVE CONTROL M1: fixed 4-byte CRC feed"
    else:
        m = re.search(r'wire tail_le4\s*=.*?;', t)
        assert m, 'tail_le4 pattern not found'
        old = m.group(0)
        new = "wire tail_le4   = tail_small && (tail[2:0]<=3'd3);  // NEGATIVE CONTROL M2: close one beat early"
    assert t.count(old) == 1, 'pattern not unique'
    write(t.replace(old, new))
    log({'cmd': cmd, 'file': SHADOW_DUT, 'sha_before': before, 'sha_after': sha(SHADOW_DUT),
         'old': old, 'new': new})
    print(cmd, 'applied; sha_before=', before, 'sha_after=', sha(SHADOW_DUT))
elif cmd == 'restore':
    before = sha(SHADOW_DUT)
    t = open(FROZEN_DUT, encoding='utf-8').read()
    write(t)
    log({'cmd': 'restore', 'file': SHADOW_DUT, 'sha_before': before, 'sha_after': sha(SHADOW_DUT)})
    print('restored; sha=', sha(SHADOW_DUT), 'equals frozen:', sha(SHADOW_DUT) == sha(FROZEN_DUT))
else:
    print('unknown'); sys.exit(2)
