#!/usr/bin/env python3
"""Adversarial tool check: mutate copies of the frozen samples and confirm r10f_strict.py
fails closed (exit code 1) for each mutation class. Evidence-only copies under this dir."""
import os
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "..", ".."))
RUN = os.path.join(ROOT, "workflow", "runs", "20261017-011744-rk-fpga-align")
EV = os.path.dirname(__file__)
TOOL = os.path.join(ROOT, "tools", "pcie_integration", "r10f_strict.py")
SRC = os.path.join(RUN, "artifacts", "r10f-small-synthetic.dma")

cases = {
    "payload_flip": (200, None),          # byte inside payload (128..167)
    "tail_nonzero": (2000, None),         # inside 4KiB tail pad
    "header_reserved": (0x60, None),      # reserved area
    "magic_broken": (1, ord('X')),        # corrupt magic
}

results = []
for name, (off, val) in cases.items():
    p = os.path.join(EV, f"mut_{name}.dma")
    shutil.copyfile(SRC, p)
    with open(p, "r+b") as f:
        f.seek(off)
        b = f.read(1)[0]
        f.seek(off)
        f.write(bytes([val if val is not None else (b ^ 0x01)]))
    r = subprocess.run([sys.executable, TOOL, "check", p], capture_output=True, text=True)
    ok_reject = r.returncode == 1
    results.append((name, ok_reject, r.returncode, r.stdout.strip()[:200]))
    print(f"[{'OK ' if ok_reject else 'BAD'}] {name}: exit={r.returncode} {r.stdout.strip()[:160]}")

# session mismatch on the unmutated sample must also be rejected
r = subprocess.run([sys.executable, TOOL, "check", SRC, "--session", "0xdeadbeef"],
                   capture_output=True, text=True)
ok = r.returncode == 1
results.append(("session_mismatch", ok, r.returncode, r.stdout.strip()[:200]))
print(f"[{'OK ' if ok else 'BAD'}] session_mismatch: exit={r.returncode} {r.stdout.strip()[:160]}")

print("SUMMARY:", sum(1 for _, o, _, _ in results if o), "/", len(results), "rejections confirmed")
print("MARKER:", "FAIL_CLOSED_OK" if all(o for _, o, _, _ in results) else "FAIL_CLOSED_PROBLEM")
sys.exit(0 if all(o for _, o, _, _ in results) else 1)
