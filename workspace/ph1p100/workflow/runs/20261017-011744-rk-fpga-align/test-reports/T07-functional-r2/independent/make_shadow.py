# -*- coding: utf-8 -*-
"""Build an isolated shadow copy of rtl/ + sim/ (skip work dirs) under the evidence dir for negative controls.
The frozen project tree is only READ. Usage: python make_shadow.py"""
import os, shutil, hashlib

ROOT = r'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道'
SRC = ROOT + '/fpga/csi2/pcie_integration'
DST = ROOT + '/workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r2/neg-shadow'

def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for c in iter(lambda: f.read(1 << 20), b''):
            h.update(c)
    return h.hexdigest()

count = 0
PREFIX = 'fpga/csi2/pcie_integration'
for sub in ('rtl', 'sim'):
    for dp, dns, fns in os.walk(os.path.join(SRC, sub)):
        dns[:] = [d for d in dns if d != 'work']
        rel = os.path.relpath(dp, SRC)
        tgt = os.path.join(DST, PREFIX, rel)
        os.makedirs(tgt, exist_ok=True)
        for fn in fns:
            s = os.path.join(dp, fn)
            t = os.path.join(tgt, fn)
            shutil.copy2(s, t)
            count += 1
print('shadow files copied:', count)
dut = os.path.join(DST, PREFIX, 'rtl/checked/csi_rx_packet_integrity.v')
print('shadow DUT sha:', sha(dut))
print('shadow DUT sha (origin):', sha(SRC + '/rtl/checked/csi_rx_packet_integrity.v'))
print('equal:', sha(dut) == sha(SRC + '/rtl/checked/csi_rx_packet_integrity.v'))
