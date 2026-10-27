#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""New-instance engineering re-verification: RTL interface/ref-copy/dead-code checks."""
import re, sys, difflib, os

ROOT = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
ORIG = os.path.join(ROOT, r"fpga\csi2\src\csi\csi_rx_packet_integrity.v")
CAND = os.path.join(ROOT, r"fpga\csi2\pcie_integration\rtl\checked\csi_rx_packet_integrity.v")
REF  = os.path.join(ROOT, r"fpga\csi2\pcie_integration\sim\tb\csi_rx_packet_integrity_ref.v")

def lines(p):
    return open(p, encoding="utf-8", errors="replace").read().splitlines()

o, c, r = lines(ORIG), lines(CAND), lines(REF)

print("== 1. candidate checked file: END_PACKET / END_PEND occurrences ==")
for i, ln in enumerate(c, 1):
    if "END_PACKET" in ln or "END_PEND" in ln:
        print("  L%d: %s" % (i, ln.rstrip()))

print("\n== 2. candidate file header comment (first 24 lines) ==")
for i, ln in enumerate(c[:24], 1):
    print("  L%d: %s" % (i, ln))

print("\n== 3. port/param block compare (candidate vs original, whitespace-normalized) ==")
def header_block(text_lines, name):
    # from 'module <name>' up to first line that is exactly ');'
    started = False
    buf = []
    for ln in text_lines:
        if not started:
            if re.match(r"\s*module\s+%s" % re.escape(name), ln):
                started = True
                buf.append(ln)
            continue
        buf.append(ln)
        if ln.strip() == ");":
            break
    return "\n".join(buf)

def norm(s):
    return re.sub(r"\s+", " ", s).strip()

hb_o = header_block(o, "csi_rx_packet_integrity")
hb_c = header_block(c, "csi_rx_packet_integrity")
hb_r = header_block(r, "csi_rx_packet_integrity_ref")
print("  original header len=%d chars, candidate len=%d chars" % (len(norm(hb_o)), len(norm(hb_c))))
print("  candidate header == original header  : %s" % (norm(hb_o) == norm(hb_c)))
print("  ref header == original header        : %s" % (norm(hb_o) == norm(hb_r)))

print("\n== 4. ref copy vs original: unified diff summary ==")
diff = list(difflib.unified_diff(o, r, fromfile="orig", tofile="ref", lineterm=""))
print("  diff lines = %d" % len(diff))
for ln in diff[:60]:
    print("  " + ln)

print("\n== 5. candidate vs original: changed-line count (context) ==")
sm = difflib.SequenceMatcher(None, o, c)
changed = sum((i2 - i1) + (j2 - j1) for tag, i1, i2, j1, j2 in sm.get_opcodes() if tag != "equal")
print("  total changed/inserted/deleted lines = %d of %d (orig %d lines, cand %d lines)" %
      (changed, len(o), len(o), len(c)))

print("\n== 6. crc16 dead-code note: 'crc_bad_q' in final_timing.rpt ==")
ft = os.path.join(ROOT, r"workflow\runs\20261017-011744-rk-fpga-align\backend\candidate\prj\ph1p_pcie_integration_Runs\phy_1\final_timing.rpt")
txt = open(ft, encoding="utf-8", errors="replace").read()
print("  crc_bad_q occurrences in final_timing.rpt = %d" % txt.count("crc_bad_q"))
for ln in txt.splitlines():
    if "crc_bad_q" in ln:
        print("   sample: " + ln.strip()[:160])
        break

print("\n== 7. 187.5MHz premise: cam byte clock in SDC (context lines) ==")
sdc = os.path.join(ROOT, r"fpga\csi2\pcie_integration\constraints\ph1p_pcie_case_ep.sdc")
sl = open(sdc, encoding="gbk", errors="replace").read().splitlines()
for i, ln in enumerate(sl, 1):
    if "1.333" in ln or "divide_by 4" in ln or "asynchronous" in ln:
        print("  L%d: %s" % (i, ln.rstrip()))
