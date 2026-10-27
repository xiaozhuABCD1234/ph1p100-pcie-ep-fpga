# -*- coding: utf-8 -*-
"""Byte-level injection probe: copy frozen run_sim.ps1 (no BOM, LF) + insert ASCII debug line before WriteAllLines.
Also patch root resolution to work from the evidence dir. Writes ONLY to the evidence dir."""
import os

ROOT = r'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道'
SRC = ROOT + '/tools/pcie_integration/run_sim.ps1'
DST = ROOT + '/workflow/runs/20261017-011744-rk-fpga-align/test-reports/T07-functional-r2/msim-entry-repro/run_sim_inject.ps1'

raw = open(SRC, 'rb').read()

# 1) patch root resolution: "..\.." -> "..\..\..\..\..\.." (depth from msim-entry-repro to project root)
needle = b'(Join-Path $PSScriptRoot "..\\..")'
assert raw.count(needle) == 1, 'root needle count %d' % raw.count(needle)
raw = raw.replace(needle, b'(Join-Path $PSScriptRoot "..\\..\\..\\..\\..\\..")')

# 2) insert ASCII debug line before the WriteAllLines line
wal = b'    [System.IO.File]::WriteAllLines($doPath, @("run -all", "quit -f"))\n'
assert raw.count(wal) == 1, 'WAL needle count %d' % raw.count(wal)
dbg = (b'"DBG doPathNull=$($null -eq $doPath) doPath=[$doPath]" | Out-File -Encoding utf8 -Append $cmdLog\n'
       b'"DBG outDirF=[$outDirF] outMapped=[$outMapped] cmdLog=[$cmdLog]" | Out-File -Encoding utf8 -Append $cmdLog\n'
       b'if ($null -ne $doPath) { "DBG codes=" + (($doPath.ToCharArray() | ForEach-Object {[int]$_}) -join ",") | Out-File -Encoding utf8 -Append $cmdLog }\n')
raw = raw.replace(wal, dbg + wal)

open(DST, 'wb').write(raw)
print('wrote', DST, len(raw), 'bytes')
