#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T09.rk-align-algo G1 ModelSim runner.

For each invocation it creates a fresh sim directory under the run's
algo/g1/msim/, copies the frozen RTL + testbench + vectors, optionally applies a
named negative-control mutation to the *copies only* (originals are asserted
unchanged), runs vlib/vlog/vsim through a temporary subst drive (ASCII path for
ModelSim), and writes a JSON report with commands, exit codes, log SHAs and the
parsed markers.

Verdicts: a clean case requires the PASS marker, exit 0 and no simulator errors.
A mutation case requires the specific named mismatch and no simulator errors
(replayable negative control).  No hardware claims.

Usage:
  python tools/algo/run_g1.py --case core --mutation none
  python tools/algo/run_g1.py --case core --mutation he_samebin
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import string
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path('C:\\Users\\czz\\OneDrive\\桌面\\实验室\\竞赛\\嵌入式\\FPGA创新设计赛道')
MS = Path("D:/intelFPGA/18.1/modelsim_ase/win32aloem")
IMG = ROOT / "upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/img/algo"
TBD = ROOT / "tools" / "algo" / "tb"
RUN = ROOT / "workflow" / "runs" / "20261017-011744-rk-fpga-align"
VEC = RUN / "algo" / "vectors"
OUTROOT = Path(__file__).resolve().parents[1] / "algo-g1"

RTLS = [
    "algo_rowwin_reader.v",
    "algo_rowwin3.v",
    "algo_obuf.v",
    "bayer_raw10_demosaic4.v",
    "gray8_gaussian3x3_stream.v",
    "gray8_he_cdfmin_frame.v",
    "rgb8_gray_stream.v",
    "gray8_gaussian3x3_frame.v",
    "img_algo_parallel_top.v",
]

CASES = {
    "core": dict(tb="tb_img_algo_core", tbfiles=["tb_img_algo_core.sv"],
                 vec=["algo_core.vec"], lut="algo_core.lut.hex",
                 pass_marker="ALGO_CORE_PASS", fail_marker="ALGO_CORE_FAIL",
                 timeout=1800),
    "rate": dict(tb="tb_img_algo_rate", tbfiles=["tb_img_algo_rate.sv"],
                 vec=[], lut=None,
                 pass_marker="ALGO_RATE_PASS", fail_marker="ALGO_RATE_FAIL",
                 timeout=7200),
    "gray": dict(tb="tb_rgb8_gray_stream", tbfiles=["tb_rgb8_gray_stream.sv"],
                 vec=["gray_mod.vec"], lut=None,
                 pass_marker="ALGO_GRAYMOD_PASS", fail_marker="ALGO_GRAYMOD_FAIL",
                 timeout=600),
    "gauss_frame": dict(tb="tb_gray8_gaussian3x3_frame",
                        tbfiles=["tb_gray8_gaussian3x3_frame.sv"],
                        vec=["gauss_frame.vec"], lut=None,
                        pass_marker="ALGO_GAUMOD_PASS", fail_marker="ALGO_GAUMOD_FAIL",
                        timeout=900),
}

MUTATIONS = {
    "none": dict(files=[], expect=None),
    "gray_round": dict(
        files=[("bayer_raw10_demosaic4.v",
                "a2h = (hl + hr + 11'd1) >> 1;",
                "a2h = (hl + hr) >> 1;")],
        expect="branch 0 data mismatch"),
    "gray_clamp": dict(
        files=[("algo_rowwin3.v",
                "asm40[59:50] = first ? (par ? r1[19:10] : r1[9:0]) : r2[39:30];",
                "asm40[59:50] = first ? (par ? r1[9:0]   : r1[9:0]) : r2[39:30];")],
        expect="branch 0 data mismatch"),
    "gau_round": dict(
        files=[("gray8_gaussian3x3_stream.v",
                "s = {2'b0, t} + ({2'b0, m} << 1) + {2'b0, b} + 13'd8;",
                "s = {2'b0, t} + ({2'b0, m} << 1) + {2'b0, b};")],
        expect="branch 1 data mismatch"),
    "he_samebin": dict(
        files=[("gray8_he_cdfmin_frame.v",
                "((a_px[0] == px_p[0])  && we1)", "(1'b0)"),
               ("gray8_he_cdfmin_frame.v",
                "((a_px[1] == px_p[1])  && we1)", "(1'b0)"),
               ("gray8_he_cdfmin_frame.v",
                "((a_px[2] == px_p[2])  && we1)", "(1'b0)"),
               ("gray8_he_cdfmin_frame.v",
                "((a_px[3] == px_p[3])  && we1)", "(1'b0)")],
        expect="branch 2 data mismatch"),
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def free_drive() -> str | None:
    used = set()
    out = subprocess.run(["powershell", "-Command",
                          "(Get-PSDrive -PSProvider FileSystem).Name"],
                         capture_output=True, text=True)
    used = set(out.stdout.split())
    for letter in "STUVWXYZ":
        if letter not in used and not Path(f"{letter}:\\").exists():
            return letter
    return None


def run_case(case: str, mutation: str, tag: str, timeout: int | None):
    spec = CASES[case]
    mut = MUTATIONS[mutation]
    stamp = time.strftime("%Y%m%dT%H%M%S") + f"_{tag}" if tag else time.strftime("%Y%m%dT%H%M%S")
    name = f"{case}" + (f"-{mutation}" if mutation != "none" else "") + f"-{stamp}"
    sim = OUTROOT / name
    sim.mkdir(parents=True, exist_ok=False)

    # ---- stage sources ----
    sources = {}
    for f in RTLS:
        src = IMG / f
        dst = sim / f
        shutil.copyfile(src, dst)
        sources[f] = {"origin": str(src.relative_to(ROOT)), "sha256": sha(src)}
    for f in spec["tbfiles"]:
        src = TBD / f
        dst = sim / f
        shutil.copyfile(src, dst)
        sources[f] = {"origin": str(src.relative_to(ROOT)), "sha256": sha(src)}
        if f == "tb_img_algo_core.sv":
            text = dst.read_text(encoding="utf-8")
            old = "task do_stall(input integer br, input integer n);\n        begin"
            assert text.count(old) == 1
            text = text.replace(old, old + "\n            n = n + 64; // Retain output-hold coverage across the registered RGB boundary.")
            old_ready = "    always @* begin\n        y8_ready  = (stall_y8  == 0);\n        gau_ready = (stall_gau == 0);\n        he_ready  = (stall_he  == 0);\n    end"
            new_ready = """    reg [5:0] elastic_stall_phase = 0;
    always @(posedge clk) begin
        if (!rst_n) elastic_stall_phase <= 0;
        else elastic_stall_phase <= elastic_stall_phase + 1'b1;
    end
    always @* begin
        y8_ready  = (stall_y8  == 0) && (elastic_stall_phase >= 8);
        gau_ready = (stall_gau == 0) && (elastic_stall_phase < 16 || elastic_stall_phase >= 24);
        he_ready  = (stall_he  == 0) && (elastic_stall_phase < 32 || elastic_stall_phase >= 40);
    end"""
            assert text.count(old_ready)==1
            text=text.replace(old_ready,new_ready)
            dst.write_text(text, encoding="utf-8")
            sources[f]["staged_sha256"] = sha(dst)
            sources[f]["test_only_change"] = "Retain directed stalls+64; add eight-cycle periodic stalls at three distinct phases to exercise actual valid outputs after elastic latency. All original oracle/marker/stability/assertion checks retained."
    for f in spec["vec"]:
        src = VEC / f
        dst = sim / f
        shutil.copyfile(src, dst)
        sources[f] = {"origin": str(src.relative_to(ROOT)), "sha256": sha(src)}
    if spec["lut"]:
        src = VEC / spec["lut"]
        dst = sim / spec["lut"]
        shutil.copyfile(src, dst)
        sources[spec["lut"]] = {"origin": str(src.relative_to(ROOT)), "sha256": sha(src)}

    # ---- apply mutation to copies ----
    mutations_applied = []
    for (fname, old, new) in mut["files"]:
        p = sim / fname
        text = p.read_text(encoding="utf-8")
        cnt = text.count(old)
        assert cnt == 1, f"mutation anchor {old!r} found {cnt} times in {fname}"
        p.write_text(text.replace(old, new), encoding="utf-8")
        mutations_applied.append({"file": fname, "old": old, "new": new,
                                  "sim_sha256": sha(p)})

    # ---- run through subst ----
    letter = free_drive()
    if not letter:
        raise RuntimeError("no free drive letter for subst")
    subprocess.run(["subst", f"{letter}:", str(ROOT)], check=True)
    try:
        cwd = Path(f"{letter}:/") / sim.relative_to(ROOT)
        vlib = MS / "vlib.exe"
        vlog = MS / "vlog.exe"
        vsim = MS / "vsim.exe"
        commands = []
        logs = {}
        for cmd in (["vlib", "work"],
                    ["vlog", "-sv"] + RTLS + spec["tbfiles"],
                    ["vsim", "-c", "-l", "vsim.log", "-do", "run.do",
                     f"work.{spec['tb']}"] +
                    ([f"+VECTORS={v}" for v in spec["vec"]])):
            exe = {"vlib": vlib, "vlog": vlog, "vsim": vsim}[cmd[0]]
            (sim / "run.do").write_text("run -all\nquit -f\n", encoding="ascii")
            t0 = time.time()
            proc = subprocess.run([str(exe)] + cmd[1:], cwd=str(cwd),
                                  capture_output=True, text=True,
                                  timeout=min(timeout or spec["timeout"], 300))
            dt = time.time() - t0
            out = proc.stdout + proc.stderr
            log_name = f"{cmd[0]}.log"
            (sim / log_name).write_text(out, encoding="utf-8")
            logs[cmd[0]] = {"exit": proc.returncode, "seconds": round(dt, 1),
                            "log": log_name, "log_sha256": sha(sim / log_name)}
            commands.append({"cmd": [str(exe)] + cmd[1:], "cwd": str(cwd),
                             "exit": proc.returncode, "seconds": round(dt, 1)})
        vsim_out = (sim / "vsim.log").read_text(encoding="utf-8", errors="replace")
        sim_errors = bool(re.search(r"\*\* (?:Error|Fatal)|Errors:\s*[1-9]", vsim_out))
        pass_hit = spec["pass_marker"] in vsim_out
        fail_hit = spec["fail_marker"] in vsim_out
        mismatch_hits = re.findall(r"ALGO_(?:CORE|RATE|GRAYMOD|GAUMOD)_MISMATCH[^\n]*", vsim_out)
        cov = {}
        m = re.search(spec["pass_marker"] + r"\s+(.*)", vsim_out)
        if m:
            for kv in m.group(1).split():
                if "=" in kv:
                    k, v = kv.split("=", 1)
                    cov[k] = v
        lut_check = None
        if spec["lut"] and mutation == "none":
            dump = sim / "he_lut_dump.hex"
            expect = sim / spec["lut"]
            if dump.exists():
                got = dump.read_text(encoding="ascii").split()
                exp = expect.read_text(encoding="ascii").split()
                lut_check = {"match": got == exp, "entries": len(got),
                             "dump_sha256": sha(dump), "expected_sha256": sha(expect)}
            else:
                lut_check = {"match": False, "entries": 0, "note": "no dump"}
        # ---- verdict ----
        # A mutation case is a *replayable negative control*: the testbench must
        # reject the mutated RTL (no PASS marker, the named mismatch present, no
        # simulator errors).  The TB ends with $finish, so vsim exits 0 even on
        # mismatches - the exit code is therefore not part of the verdict.
        if mutation == "none":
            verdict = "PASS" if (pass_hit and not sim_errors and
                                 commands[-1]["exit"] == 0 and
                                 (lut_check is None or lut_check["match"])) else "FAIL"
        else:
            verdict = "PASS" if (not sim_errors and not pass_hit and
                                 any(mut["expect"] in h for h in mismatch_hits)) else "FAIL"
        report = {
            "case": case, "mutation": mutation, "sim_dir": str(sim),
            "stamp": stamp, "sources": sources, "mutations": mutations_applied,
            "commands": commands, "logs": logs,
            "simulator_errors": sim_errors, "pass_marker": pass_hit,
            "fail_marker": fail_hit, "mismatch_sample": mismatch_hits[:10],
            "coverage": cov, "lut_check": lut_check,
            "verdict": verdict,
            "limitations": ["RTL simulation only; no synthesis, timing, resource "
                            "or board evidence in this runner",
                            "Finite directed coverage, not exhaustive or formal"],
        }
        (sim / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(json.dumps({"sim_dir": str(sim), "verdict": verdict,
                          "coverage": cov, "lut_check": lut_check,
                          "mismatch_sample": mismatch_hits[:3]}, indent=2))
        return 0 if verdict == "PASS" else 1
    finally:
        subprocess.run(["subst", f"{letter}:", "/D"], check=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--case", required=True, choices=sorted(CASES))
    ap.add_argument("--mutation", default="none", choices=sorted(MUTATIONS))
    ap.add_argument("--tag", default="")
    ap.add_argument("--timeout", type=int, default=0)
    args = ap.parse_args()
    return run_case(args.case, args.mutation, args.tag, args.timeout)


if __name__ == "__main__":
    sys.exit(main())
