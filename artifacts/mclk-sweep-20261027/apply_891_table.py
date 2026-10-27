#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 IMX415 的 4K 分支（MODE==1）从当前的 24MHz/~1440Mbps 表
改成 27MHz/891Mbps 组（HMAX=1100, VMAX=2250, SYS_MODE=0x05, INCKSEL3/4=C6/E7 ...）。
只改 4K 分支；MODE=0 (1080p binning) 的寄存器值不动。
用法：python3 apply_891_table.py [ui_imx415_reg.v 路径]
默认路径：rtl/ep_side/cam/ui_imx415_reg.v
文件是 GB18030 编码，脚本按 GB18030 读回，避免中文注释乱码。
"""
import sys

p = sys.argv[1] if len(sys.argv) > 1 else "rtl/ep_side/cam/ui_imx415_reg.v"
s = open(p, "r", encoding="gb18030").read()

repls = [
    ("(MODE==2'd1) ? {16'h3008, 8'h54} : {16'h3008, 8'h5D}", "{16'h3008, 8'h5D}"),
    ("(MODE==2'd1) ? {16'h300A, 8'h3B} : {16'h300A, 8'h42}", "{16'h300A, 8'h42}"),
    ("{16'h3024, 8'h97}", "{16'h3024, 8'hCA}"),
    ("(MODE==2'd1) ? {16'h3025, 8'h11} : {16'h3025, 8'h08}", "{16'h3025, 8'h08}"),
    ("{16'h3028, 8'h15}", "{16'h3028, 8'h4C}"),
    ("18:  REG_DATA = {16'h3029, 8'h02};",
     "18:  REG_DATA = (MODE==2'd1) ? {16'h3029, 8'h04} : {16'h3029, 8'h02};"),
    ("(MODE==2'd1) ? {16'h3033, 8'h08} : {16'h3033, 8'h05}", "{16'h3033, 8'h05}"),
    ("(MODE==2'd1) ? {16'h3118, 8'hB4} : {16'h3118, 8'hC6}", "{16'h3118, 8'hC6}"),
    ("(MODE==2'd1) ? {16'h311A, 8'hFC} : {16'h311A, 8'hE7}", "{16'h311A, 8'hE7}"),
    ("(MODE==2'd1) ? {16'h4004, 8'h00} : {16'h4004, 8'hC0}", "{16'h4004, 8'hC0}"),
    ("(MODE==2'd1) ? {16'h400C, 8'h01} : {16'h400C, 8'h00}", "{16'h400C, 8'h00}"),
    ("(MODE==2'd1) ? {16'h4018, 8'h9F} : {16'h4018, 8'h7F}", "{16'h4018, 8'h7F}"),
    ("(MODE==2'd1) ? {16'h401A, 8'h57} : {16'h401A, 8'h37}", "{16'h401A, 8'h37}"),
    ("(MODE==2'd1) ? {16'h401C, 8'h57} : {16'h401C, 8'h37}", "{16'h401C, 8'h37}"),
    ("(MODE==2'd1) ? {16'h401E, 8'h87} : {16'h401E, 8'hF7}", "{16'h401E, 8'hF7}"),
    ("(MODE==2'd1) ? {16'h401F, 8'h01} : {16'h401F, 8'h00}", "{16'h401F, 8'h00}"),
    ("(MODE==2'd1) ? {16'h4020, 8'h5F} : {16'h4020, 8'h3F}", "{16'h4020, 8'h3F}"),
    ("(MODE==2'd1) ? {16'h4022, 8'hA7} : {16'h4022, 8'h6F}", "{16'h4022, 8'h6F}"),
    ("(MODE==2'd1) ? {16'h4024, 8'h5F} : {16'h4024, 8'h3F}", "{16'h4024, 8'h3F}"),
    ("(MODE==2'd1) ? {16'h4026, 8'h97} : {16'h4026, 8'h5F}", "{16'h4026, 8'h5F}"),
    ("(MODE==2'd1) ? {16'h4028, 8'h4F} : {16'h4028, 8'h2F}", "{16'h4028, 8'h2F}"),
    ("(MODE==2'd1) ? {16'h4074, 8'h00} : {16'h4074, 8'h01}", "{16'h4074, 8'h01}"),
]
for old, new in repls:
    if old not in s:
        raise SystemExit("MISSING: " + old)
    s = s.replace(old, new, 1)

open(p, "w", encoding="gb18030").write(s)
print("applied", len(repls), "replacements to", p)
