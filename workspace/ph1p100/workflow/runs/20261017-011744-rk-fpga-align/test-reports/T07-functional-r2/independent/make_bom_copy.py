# -*- coding: utf-8 -*-
"""Build run_sim_bom.ps1 = frozen bytes + UTF-8 BOM + root-depth patch (no other change); validate fix via -File.
Root patch only adjusts $PSScriptRoot "..\.." to the depth of this evidence copy (script location differs);
this is independent of the BOM fix under test."""
import os

ROOT = r'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道'
SRC = ROOT + '/tools/pcie_integration/run_sim.ps1'
DST = ROOT + '/workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r2/independent/run_sim_bom.ps1'

raw = open(SRC, 'rb').read()
needle = b'(Join-Path $PSScriptRoot "..\\..")'
assert raw.count(needle) == 1
raw = raw.replace(needle, b'(Join-Path $PSScriptRoot "..\\..\\..\\..\\..\\..")')
assert raw[:3] != b'\xef\xbb\xbf'
out = b'\xef\xbb\xbf' + raw
open(DST, 'wb').write(out)
print('wrote', DST, len(out), 'bytes (BOM + frozen bytes + root-depth patch)')
