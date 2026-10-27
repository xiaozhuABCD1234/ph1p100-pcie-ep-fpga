# -*- coding: utf-8 -*-
"""Rewrite neg-replay/before-fix-run_sim.ps1 as the VERBATIM no-BOM bytes of the frozen r3 run_sim.ps1
(sha must equal 33399210... = the r2/pre-fix frozen bytes). Root will be supplied via the entry's -Root param."""
import hashlib

ROOT = r'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道'
SRC = ROOT + '/tools/pcie_integration/run_sim.ps1'
DST = ROOT + '/workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r3/neg-replay/before-fix-run_sim.ps1'

raw = open(SRC, 'rb').read()
assert raw[:3] == b'\xef\xbb\xbf'
body = raw[3:]
open(DST, 'wb').write(body)
sha = hashlib.sha256(open(DST, 'rb').read()).hexdigest()
print('written', DST, len(body), 'bytes')
print('sha256 =', sha)
print('equals r2/pre-fix 33399210...:', sha == '33399210c389818a8601b2710ff08fc1b46312976b35d6fb9a0de1b50674229e')
