"""Bounded offline audit; compile b9 in place, never modify its files."""
from pathlib import Path
import hashlib
import json
import os
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = Path(r"D:\fpga\ph1p100")
MS = Path(r"D:\intelFPGA\18.1\modelsim_ase\win32aloem")
DUT = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b9-rawstore/r0/changed-src/a1_uart_export.v"
INI = HERE / "modelsim.ini"
if not INI.exists():
    INI.write_text("[Library]\nwork = work\nothers = " + (MS / "modelsim.ini").as_posix() + "\n", encoding="ascii")
env = os.environ.copy()
env["MODEL_TECH"] = str(MS)
env["MODELSIM"] = str(INI)
original = hashlib.sha256(DUT.read_bytes()).hexdigest()
results = {"dut": str(DUT), "sha256": original, "cases": []}

def run(exe, args, name):
    proc = subprocess.run([str(MS / exe)] + args, cwd=HERE, env=env,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True, errors="replace", timeout=60)
    (HERE / (name + ".log")).write_text(proc.stdout, encoding="utf-8")
    if proc.returncode:
        raise RuntimeError(name + " failed:\n" + proc.stdout[-6000:])
    return proc.stdout

if not (HERE / "work" / "_info").exists():
    run("vlib.exe", ["work"], "vlib")
run("vlog.exe", ["-sv", "-modelsimini", INI.as_posix(), "-work", "work",
                 DUT.as_posix(), (HERE / "tb_b9_arb_repro.sv").as_posix()], "compile")
for div, marker in [(64, "REPRO_CONFIRMED"), (0, "CONTROL_CONFIRMED")]:
    output = run("vsim.exe", ["-c", "-modelsimini", INI.as_posix(), "-lib", "work",
        "tb_b9_arb_repro", "-gSTATUS_DIV=" + str(div),
        "-do", "run -all; quit -f"], "sim_sts_" + str(div))
    if marker not in output or "** Fatal:" in output:
        raise RuntimeError(output[-6000:])
    evidence = [line for line in output.splitlines() if "OBS " in line or marker in line]
    results["cases"].append({"status_div": div, "evidence": evidence})
    print("\n".join(evidence))
results["dut_unchanged"] = original == hashlib.sha256(DUT.read_bytes()).hexdigest()
assert results["dut_unchanged"]
(HERE / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
print("DUT_UNCHANGED", original)
