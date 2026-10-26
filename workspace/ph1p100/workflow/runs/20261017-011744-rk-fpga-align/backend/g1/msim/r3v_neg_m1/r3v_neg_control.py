# -*- coding: utf-8 -*-
"""T07 round3 oracle negative control re-run (r3v, new repair instance).

Method: copy frozen rtl/ + sim/ into an isolated tree OUTSIDE the project
(%TEMP%/opencode/r3negv, created fresh; the old r3neg tree is left untouched),
inject M1 (crc_next fixed 4-byte advance; ref change-report 8.2 defect-1),
then run the FROZEN documented entry (run_sim.ps1, now UTF-8 BOM) with -Root
pointed at the isolated tree, running the differential TB. Expected: FAIL
(oracle rejects the bad implementation).

Reads project frozen files only; writes only into %TEMP% isolated tree and
workflow/runs/20261017-011744-rk-fpga-align/backend/g1/msim/r3v_neg_m1/.
"""
import hashlib
import json
import os
import shutil
import subprocess

ROOT = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
TEMP = os.path.join(os.environ["TEMP"], "opencode")
SHADOW = os.path.join(TEMP, "r3negv")
EVID = os.path.join(ROOT, "workflow", "runs", "20261017-011744-rk-fpga-align",
                    "backend", "g1", "msim", "r3v_neg_m1")
REL_OUT = "workflow/runs/20261017-011744-rk-fpga-align/backend/g1/msim/r3v_neg_m1"

EXPECT_FROZEN_SHA = "50b4c77be684f078bdf6dca93848e9298e3cbd8010e45eab4b0ecfb2debdc6c0"


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


assert not os.path.exists(SHADOW), "refusing: shadow tree already exists: " + SHADOW

src = os.path.join(ROOT, "fpga", "csi2", "pcie_integration")
dst = os.path.join(SHADOW, "fpga", "csi2", "pcie_integration")
os.makedirs(dst)
for sub in ("rtl", "sim"):
    shutil.copytree(os.path.join(src, sub), os.path.join(dst, sub))

frozen = os.path.join(src, "rtl", "checked", "csi_rx_packet_integrity.v")
tgt = os.path.join(dst, "rtl", "checked", "csi_rx_packet_integrity.v")
frozen_sha = sha(frozen)
assert frozen_sha == EXPECT_FROZEN_SHA, "frozen RTL drift: " + frozen_sha

needle = (" wire[15:0] crc_next = (keep_d==4'b1111)?crc_u4:\n"
          "                       (keep_d==4'b0111)?crc_u3:\n"
          "                       (keep_d==4'b0011)?crc_u2:\n"
          "                       (keep_d==4'b0001)?crc_u1:crc;\n")
with open(tgt, "r", encoding="utf-8", newline="") as f:
    old = f.read()
assert needle in old, "mutation anchor not found"
new = old.replace(needle, " wire[15:0] crc_next = crc_u4;  // M1: fixed 4-byte advance\n")
with open(tgt, "w", encoding="utf-8", newline="") as f:
    f.write(new)
shadow_sha = sha(tgt)

os.makedirs(EVID, exist_ok=True)
cmd = ["powershell", "-ExecutionPolicy", "Bypass", "-File",
       os.path.join("tools", "pcie_integration", "run_sim.ps1"),
       "-Root", SHADOW, "-Tb", "tb_csi_integrity_diff",
       "-OutDir", REL_OUT, "-TbFiles", "tb/tb_csi_integrity_diff.v"]
proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, timeout=1800)
with open(os.path.join(EVID, "console_stdout.txt"), "wb") as f:
    f.write(proc.stdout)
with open(os.path.join(EVID, "console_stderr.txt"), "wb") as f:
    f.write(proc.stderr)

shadow_out = os.path.join(SHADOW, REL_OUT.replace("/", os.sep))
for fn in ("vlog.log", "vsim.log", "vsim_stdout.log", "run.do", "abs.f", "commands.log"):
    p = os.path.join(shadow_out, fn)
    if os.path.exists(p):
        shutil.copy2(p, os.path.join(EVID, fn))

mut = {
    "task": "T07.rk-align-backend round3 oracle negative control re-run (r3v; new repair instance)",
    "method": "copy frozen rtl/+sim/ to isolated tree outside project; inject M1; run frozen documented run_sim.ps1 (-Root shadow); differential TB expected FAIL",
    "frozen_file": "fpga/csi2/pcie_integration/rtl/checked/csi_rx_packet_integrity.v",
    "frozen_sha256": frozen_sha,
    "shadow_sha256_after_mutation": shadow_sha,
    "mutation": "crc_next = crc_u4 (fixed 4-byte advance; ref change-report 8.2 defect-1)",
    "shadow_tree": SHADOW,
    "frozen_untouched": sha(frozen) == frozen_sha,
}
with open(os.path.join(EVID, "mutation.json"), "w", encoding="utf-8") as f:
    json.dump(mut, f, ensure_ascii=False, indent=2)

shutil.copy2(__file__, os.path.join(EVID, "r3v_neg_control.py"))

vs = os.path.join(EVID, "vsim.log")
txt = ""
if os.path.exists(vs):
    raw = open(vs, "rb").read()
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        txt = raw.decode("utf-16", "replace")
    else:
        txt = raw.decode("utf-8", "replace")
verdict = [l.strip() for l in txt.splitlines()
           if ("FAIL" in l or "mismatch" in l or "ALL PASS" in l)]
ok = any("FAIL: 507 mismatches" in l for l in verdict)
print("frozen_sha    = " + frozen_sha[:16])
print("shadow_sha    = " + shadow_sha[:16])
print("child_exit    = %s" % proc.returncode)
print("artifacts     = vlog=%s vsim=%s run.do=%s" % (
    os.path.exists(os.path.join(EVID, "vlog.log")),
    os.path.exists(os.path.join(EVID, "vsim.log")),
    os.path.exists(os.path.join(EVID, "run.do"))))
for h in verdict[:4]:
    print("verdict       : " + h[:120])
print("M1_VERDICT_OK = %s" % ok)
