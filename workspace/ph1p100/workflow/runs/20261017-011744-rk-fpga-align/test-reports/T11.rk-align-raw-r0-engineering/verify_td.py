# -*- coding: utf-8 -*-
"""T11.rk-align-raw round0 engineering (independent tester).
Read-only consolidation of G2 (TD) evidence + candidate tree coverage audit.
Writes only under test-reports/T11.rk-align-raw-r0-engineering/.
"""
import hashlib, json, os, re
from datetime import datetime

ROOT = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
RUN = os.path.join(ROOT, "workflow", "runs", "20261017-011744-rk-fpga-align")
OUT = os.path.join(RUN, "test-reports", "T11.rk-align-raw-r0-engineering")
MAN = os.path.join(RUN, "raw", "candidate-manifest.json")
T07MAN = os.path.join(RUN, "backend", "candidate-manifest.json")
PRJ = os.path.join(RUN, "raw", "candidate", "prj")
PHY = os.path.join(PRJ, "ph1p_pcie_integration_Runs", "phy_1")
SYN = os.path.join(PRJ, "ph1p_pcie_integration_Runs", "syn_1")
BEST = os.path.join(PRJ, "ph1p_pcie_integration_Runs", "best_result")

def sha256_file(p, bs=1 << 20):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        while True:
            b = f.read(bs)
            if not b:
                break
            h.update(b)
    return h.hexdigest()

def mt(p):
    return datetime.fromtimestamp(os.path.getmtime(p)).strftime("%Y-%m-%d %H:%M:%S")

L = []
def w(s=""):
    L.append(s)

def read_text(p):
    with open(p, encoding='utf-8', errors='replace') as f:
        return f.read()

man = json.load(open(MAN, encoding='utf-8'))
t07 = json.load(open(T07MAN, encoding='utf-8'))

# ---------- 1. coverage audit (candidate trees vs manifest) ----------
w("== 1. coverage audit ==")
prod_man = {e["path"] for e in man["production_inputs"]}
base = os.path.join(ROOT, "fpga", "csi2", "pcie_integration")
tree_prod = set()
for dp, dn, fn in os.walk(base):
    rel = os.path.relpath(dp, ROOT).replace(os.sep, '/')
    if '/sim' in rel.replace(base.replace(os.sep, '/'), '') or rel.endswith('/sim'):
        continue
    if 'peer-ref-2a4b253' in rel:
        continue
    for f in fn:
        r = (rel + '/' + f).replace(os.sep, '/')
        if r == 'fpga/csi2/pcie_integration/README.md':
            continue
        tree_prod.add(r)
w(f"production tree files (excl sim/, peer-ref-2a4b253/, README.md): {len(tree_prod)}; manifest: {len(prod_man)}")
w(f"  manifest-only (missing on disk): {sorted(prod_man - tree_prod)}")
w(f"  tree-only (uncovered files):    {sorted(tree_prod - prod_man)}")

sim_man = {e["path"] for e in man["test_inputs"]}
sim_base = os.path.join(ROOT, "fpga", "csi2", "pcie_integration", "sim")
volatile = {"commands.log", "abs.f", "run.do", "vsim_stdout.log"}
tree_sim = set()
for dp, dn, fn in os.walk(sim_base):
    for f in fn:
        if f in volatile or f.endswith('.log') or f.endswith('.logw'):
            continue
        tree_sim.add(os.path.relpath(os.path.join(dp, f), ROOT).replace(os.sep, '/'))
w(f"sim tree files (excl volatile logs): {len(tree_sim)}; manifest test_inputs under sim/: {len(sim_man)}")
w(f"  manifest-only: {sorted(sim_man - tree_sim)}")
w(f"  tree-only:     {sorted(tree_sim - sim_man)}")

tools_man = {e["path"] for e in man["build_scripts"]}
tools_base = os.path.join(ROOT, "tools", "pcie_integration")
tree_tools = set()
for dp, dn, fn in os.walk(tools_base):
    for f in fn:
        tree_tools.add(os.path.relpath(os.path.join(dp, f), ROOT).replace(os.sep, '/'))
w(f"tools tree files: {len(tree_tools)}; manifest build_scripts: {len(tools_man)}")
w(f"  manifest-only: {sorted(tools_man - tree_tools)}")
w(f"  tree-only:     {sorted(tree_tools - tools_man)}")

# SDC/ADC/checked vs T07 hashes
w("")
w("== 1b. constraint/checked zero-change vs T07 ==")
t07prod = {e["path"]: e["sha256"] for e in t07["production_inputs"]}
for p in ["fpga/csi2/pcie_integration/constraints/ph1p_pcie_case_ep.sdc",
          "fpga/csi2/pcie_integration/constraints/ph1p_pcie_case_ep.adc",
          "fpga/csi2/pcie_integration/rtl/checked/crc16_upd4.v",
          "fpga/csi2/pcie_integration/rtl/checked/csi_rx_10bit_unpack_checked.v",
          "fpga/csi2/pcie_integration/rtl/checked/csi_rx_packet_integrity.v"]:
    cur = {e["path"]: e["sha256"] for e in man["production_inputs"]}.get(p)
    old = t07prod.get(p)
    w(f"{'SAME' if cur == old else 'DIFF'} {p}\n    T07={old}\n    T11={cur}")
# tool .ps1 vs T07
t07bs = {e["path"]: e["sha256"] for e in t07["build_scripts"]}
cur_bs = {e["path"]: e["sha256"] for e in man["build_scripts"]}
for p in ["tools/pcie_integration/run_sim.ps1", "tools/pcie_integration/run_td.ps1"]:
    w(f"{'SAME' if cur_bs.get(p) == t07bs.get(p) else 'DIFF'} {p}\n    T07={t07bs.get(p)}\n    T11={cur_bs.get(p)}")

# ---------- 2. build_artifacts mtime/binding ----------
w("")
w("== 2. build_artifacts (35) mtime / binding ==")
arts = []
for e in man["build_artifacts"]:
    p = os.path.join(RUN, e["path"].replace("/", os.sep))
    arts.append((e["path"], os.path.getsize(p), mt(p), e["sha256"][:12]))
for rel, sz, m, h in sorted(arts, key=lambda x: x[2]):
    w(f"{m}  {sz:>9}  {h}  {rel}")
mtimes = [a[2] for a in arts]
w(f"mtime range: {min(mtimes)} .. {max(mtimes)}")
w(f"bit entry count in manifest: {sum(1 for a in arts if a[0].endswith('.bit'))}")

# ---------- 3. final_timing.rpt ----------
w("")
w("== 3. final_timing.rpt ==")
ftr = os.path.join(PHY, "ph1p_pcie_integration.bit") and os.path.join(PHY, "final_timing.rpt")
txt = read_text(ftr)
for pat in [r"Generated\s+:.*", r"Top Model\s+:.*", r"Device\s+:.*", r"STA coverage\s+:.*",
            r"Constraint File\s+:.*", r"Confidence\s+:.*", r"Check Corner\s+:.*", r"CRPR Enabled\s+:.*"]:
    m = re.search(pat, txt)
    w("  " + (m.group(0) if m else f"NOT FOUND: {pat}"))
for pat in [r"SWNS:\s*[-\d.]+ns,\s*STNS:\s*[-\d.]+ns", r"HWNS:\s*[-\d.]+ns,\s*HTNS:\s*[-\d.]+ns", r"Period Check WNS:.*"]:
    for m in re.finditer(pat, txt):
        w("  " + m.group(0))
w("  -- clock summary rows clk0..clk4 (name/type/C-Freq/R-Freq/SWNS/STNS/HWNS/HTNS) --")
in_tbl = False
for line in txt.splitlines():
    if line.strip().startswith("clk0") and "User GCLK" in line:
        in_tbl = True
    if in_tbl and re.match(r"\s*(clk[0-9]+)", line):
        w("  " + " ".join(line.split()))
    if in_tbl and line.strip().startswith("Notes"):
        break
w("  -- cam_a / cam_b path group max path --")
for grp in ["cam_a_byte_clk", "cam_b_byte_clk"]:
    idx = txt.find(f"Path Group     :     {grp} -> {grp}")
    seg = txt[idx:idx + 6000]
    mm = re.search(r"Min Period\s+:.*", seg)
    st = re.search(r"Max\s+: SWNS.*", seg)
    sl = re.search(r"Slack\s+:\s+([-\d.]+)ns", seg)
    bp = re.search(r"Begin Point\s+: (.*)", seg)
    ep = re.search(r"End Point\s+: (.*)", seg)
    dp = re.search(r"Data Path Delay\s+: (.*)", seg)
    ll = re.search(r"Logic Level\s+: (.*)", seg)
    bd = re.search(r"Budget\s+: (.*)", seg)
    for tag, m in [("MinPeriod", mm), ("Stats", st), ("Slack", sl), ("Begin", bp), ("End", ep), ("DataPath", dp), ("Logic", ll), ("Budget", bd)]:
        w(f"  [{grp}] {tag}: " + (m.group(1) if m and m.lastindex else (m.group(0) if m else "NOT FOUND")))
neg = re.findall(r"Slack\s+:\s+(-\d+\.\d+)ns", txt)
w(f"  negative-slack occurrences in whole report: {len(neg)} {neg[:10]}")
w(f"  'Viol Endpoints' occurrences: {len(re.findall(r'Viol Endpoints', txt))}; total endpoints on stats line: "
  + (re.search(r"0 Viol Endpoints,\s+(\d+) Total Endpoints", txt).group(1) if re.search(r"0 Viol Endpoints,\s+(\d+) Total Endpoints", txt) else "n/a"))

# ---------- 4. route/place flow status ----------
w("")
w("== 4. flow.status / qor ==")
for name in ["route_flow.status", "place_flow.status"]:
    t = read_text(os.path.join(PHY, name))
    for pat in [r"Timing Mode\s+:.*", r"Setup\s+:.*", r"Hold\s+:.*"]:
        m = re.search(pat, t)
        w(f"  [{name}] " + (m.group(0) if m else "?"))
for name in ["route.qor", "place.qor"]:
    t = read_text(os.path.join(PHY, name))
    for pat in [r"Setup\s*:.*", r"Hold\s*:.*", r"Route.*:.*", r"Total.*wire.*"]:
        for m in re.finditer(pat, t):
            w(f"  [{name}] " + " ".join(m.group(0).split()))

# ---------- 5. run.log / td logs ----------
w("")
w("== 5. run.log / td logs ==")
rl = os.path.join(PHY, "run.log")
for pat in [r"PRJ-1406.*", r"PRJ-1424.*", r"TMST-7700.*", r"PHY-5060.*", r"DRC CLKST.*"]:
    for m in re.finditer(pat, read_text(rl)):
        w("  run.log: " + " ".join(m.group(0).split())[:200])
w(f"  run.log 'ERROR' lines: {len(re.findall(r'ERROR', read_text(rl)))}")
for name in ["td_00_all.log", "td_20261017_093208.log"]:
    t = read_text(os.path.join(PRJ, name))
    for pat in [r"PRJ-1406.*", r"PRJ-1424.*", r"T07_ALL_DONE", r"USR-8001.*", r"USR-8122.*"]:
        hits = re.findall(pat, t)
        w(f"  [{name}] {pat} -> {len(hits)}" + (f" last: {' '.join(hits[-1].split())[:160]}" if hits else ""))
    w(f"  [{name}] download/flash/sram mentions: {len(re.findall(r'download|flash|sram', t, re.I))}")
w(f"  td log files in prj/: {sorted(f for f in os.listdir(PRJ) if f.startswith('td_'))}")

# ---------- 6. area/exception/chk ----------
w("")
w("== 6. area / exception / chk.timing ==")
ar = read_text(os.path.join(PHY, "ph1p_pcie_integration_phy.area"))
for line in ar.splitlines():
    if re.match(r"^#", line.strip()) or line.strip().startswith("#"):
        w("  " + " ".join(line.split()))
ex = read_text(os.path.join(PHY, "ph1p_pcie_integration_exception.timing"))
ex_gen = re.search(r"Generated\s+:.*", ex)
w("  exception.timing generated: " + (ex_gen.group(0) if ex_gen else "n/a"))
mcp = ex.split("MCP/SMD Details")[1].split("Details on timing exceptions")[0] if "MCP/SMD Details" in ex else ""
w(f"  exception.timing MCP/SMD details body empty: {mcp.strip() == ''}")
chk = read_text(os.path.join(PHY, "ph1p_pcie_integration_chk.timing"))
for line in chk.splitlines()[:16]:
    if line.strip():
        w("  chk: " + " ".join(line.split()))

# ---------- 7. BOM of .ps1 entries (first bytes) ----------
w("")
w("== 7. tools entry .ps1 BOM + bytes ==")
BOM = b"\xef\xbb\xbf"
for rel in ["tools/pcie_integration/run_sim.ps1", "tools/pcie_integration/run_td.ps1"]:
    p = os.path.join(ROOT, rel.replace("/", os.sep))
    with open(p, 'rb') as f:
        head = f.read(3)
    w(f"  {rel}: bytes={os.path.getsize(p)} first3={head.hex(' ')} bom={head == BOM} sha256={sha256_file(p)[:16]}")

with open(os.path.join(OUT, "verify_td.out.txt"), "w", encoding='utf-8') as f:
    f.write("\n".join(L) + "\n")
print("\n".join(L))
