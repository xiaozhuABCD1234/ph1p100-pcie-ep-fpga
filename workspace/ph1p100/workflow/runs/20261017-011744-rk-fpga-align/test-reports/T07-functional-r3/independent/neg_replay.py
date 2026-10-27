# -*- coding: utf-8 -*-
"""r3 independent replay helpers:
  make-shadow   : copy frozen rtl/+sim/ (excluding work/) into neg-replay/shadow; verify DUT hash
  mutate-m1     : apply M1 (crc_next = crc_u4) to the shadow DUT; record mutation.json
  make-beforefix: no-BOM copy of frozen run_sim.ps1 (root-depth patched) = pre-fix bytes; verify sha
"""
import os, sys, shutil, re, hashlib, json

ROOT = r'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道'
EV = ROOT + '/workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r3/neg-replay'
SRC = ROOT + '/fpga/csi2/pcie_integration'
SHADOW = EV + '/shadow'
SHADOW_DUT = SHADOW + '/fpga/csi2/pcie_integration/rtl/checked/csi_rx_packet_integrity.v'
FROZEN_DUT = SRC + '/rtl/checked/csi_rx_packet_integrity.v'


def sha(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()


cmd = sys.argv[1]
if cmd == 'make-shadow':
    PREFIX = 'fpga/csi2/pcie_integration'
    n = 0
    for sub in ('rtl', 'sim'):
        for dp, dns, fns in os.walk(os.path.join(SRC, sub)):
            dns[:] = [d for d in dns if d != 'work']
            rel = os.path.relpath(dp, SRC)
            tgt = os.path.join(SHADOW, PREFIX, rel)
            os.makedirs(tgt, exist_ok=True)
            for fn in fns:
                shutil.copy2(os.path.join(dp, fn), os.path.join(tgt, fn))
                n += 1
    print('copied', n, 'files; shadow DUT sha =', sha(SHADOW_DUT), '; equals frozen:', sha(SHADOW_DUT) == sha(FROZEN_DUT))
elif cmd == 'mutate-m1':
    t = open(SHADOW_DUT, encoding='utf-8').read()
    before = sha(SHADOW_DUT)
    m = re.search(r'wire\[15:0\] crc_next = .*?;', t, re.S)
    assert m, 'pattern not found'
    old = m.group(0)
    new = 'wire[15:0] crc_next = crc_u4;  // NEGATIVE CONTROL M1 (r3 independent replay): fixed 4-byte CRC feed'
    assert t.count(old) == 1
    open(SHADOW_DUT, 'w', encoding='utf-8', newline='').write(t.replace(old, new))
    rec = {'task': 'T07.rk-align-backend r3 functional independent negative-control replay',
           'method': 'copy frozen rtl/+sim/ to isolated tree under test-reports; inject M1; run frozen documented run_sim.ps1 with -Root shadow; differential TB expected FAIL',
           'frozen_file': 'fpga/csi2/pcie_integration/rtl/checked/csi_rx_packet_integrity.v',
           'frozen_sha256': sha(FROZEN_DUT), 'shadow_sha_before': before, 'shadow_sha_after': sha(SHADOW_DUT),
           'mutation': 'crc_next = crc_u4 (fixed 4-byte advance; re-introduces change-report 8.2 defect-1)',
           'shadow_tree': SHADOW, 'frozen_untouched': True}
    json.dump(rec, open(EV + '/mutation_m1.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    print('M1 applied: shadow sha', before, '->', sha(SHADOW_DUT))
elif cmd == 'make-beforefix':
    raw = open(SRC.replace('/fpga/csi2/pcie_integration', '') + '/tools/pcie_integration/run_sim.ps1', 'rb').read()
    assert raw[:3] == b'\xef\xbb\xbf', 'BOM missing in frozen script'
    body = raw[3:]
    needle = b'(Join-Path $PSScriptRoot "..\\..")'
    assert body.count(needle) == 1
    body = body.replace(needle, b'(Join-Path $PSScriptRoot "..\\..\\..\\..\\..\\..")')
    p = EV + '/before-fix-run_sim.ps1'
    open(p, 'wb').write(body)
    print('before-fix copy written:', p, len(body), 'bytes')
    print('sha256 =', sha(p), ' (expect 33399210c389818a8601b2710ff08fc1b46312976b35d6fb9a0de1b50674229e)')
else:
    print('unknown'); sys.exit(2)
