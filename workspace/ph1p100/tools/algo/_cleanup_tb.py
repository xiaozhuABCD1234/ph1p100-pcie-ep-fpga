# -*- coding: utf-8 -*-
"""Remove the temporary T09 debug prints from tb_img_algo_core.sv (final)."""
from pathlib import Path

p = Path(r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\tools\algo\tb\tb_img_algo_core.sv")
t = p.read_text(encoding="utf-8")

i = t.find("    // temporary debug:")
j = t.find("    initial begin\n        #20000000;")
assert i >= 0 and j > i, (i, j)
t = t[:i] + t[j:]
p.write_text(t, encoding="utf-8")
print("cleaned ok, chars:", len(t))
