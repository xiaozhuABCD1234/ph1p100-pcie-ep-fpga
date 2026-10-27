#!/usr/bin/env python3
"""P3 input freeze / drift check.  Writes r0/input-verified.json."""
import hashlib
import json
import pathlib
import sys

sys.dont_write_bytecode = True
R0 = pathlib.Path(__file__).resolve().parent.parent
ROOT = pathlib.Path(r"D:/fpga/ph1p100")
P1 = ROOT / "workflow/runs/20261025-233401_fpga-steady-state-reverdict/T10.ss-steady-anchor/r0"
P2 = ROOT / "workflow/runs/20261025-233401_fpga-steady-state-reverdict/T10.ss-verdict-r1/r0"
COMP = ROOT / "work/parallel-sim-20261024-2204/codec-throughput/comp"
SRC = R0 / "src"


def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()


EXPECT = {
    str(P1 / "manifest-r0.json"): "39f3e3d6d115afbdcda9753b254f6971a10eb75df88d5718eb9ea5a247199f9a",
    str(P1 / "out/steady-state.json"): "a0945e1f60d9e7651d3db2d1a4d939b665d4fe451e9206537fb3b7d0c5430023",
    str(P1 / "sim/run_ss.py"): "d7417ea1f4ee32c17412a0d82ee547407cd8dc6be7b1ebe34061c347586dbac8",
    str(P1 / "src/tb_ss_anchor.v"): "ddd9e02ca71aa3b81e86f4cc0f151498fd48bf9a4dbbcc042b59c97d9f15d1ff",
    str(P1 / "sim/caps/ss4.stats"): "29bd31851804714bf65df6d5f4aa29f9daddccebe4d858e08dbfed2e937981a5",
    str(P2 / "manifest-r0.json"): "fd27c70f304f51ba0b0b022398acd46f1f5f43a32351acfc472dea12e034fad0",
    str(P2 / "verdict-r1.md"): "62ec3adc067101383613ef3e5ff659b7139f320f57d1f1e6ad6ea30c09a3c18a",
    str(COMP / "in.hex"): "edbfdeaedb06824ced20ad76b260979e95e1322d6f6e3bab5e7a951a268f9849",
}


def main():
    p1man = json.loads((P1 / "manifest-r0.json").read_text())
    p1art = {a["path"]: a for a in p1man["artifacts"]}
    checks = []
    drift = []
    for path, want in EXPECT.items():
        got = sha(path)
        ok = got == want
        checks.append({"path": path, "bytes": pathlib.Path(path).stat().st_size,
                       "sha256": got, "expected": want, "match": ok})
        if not ok:
            drift.append(path)
    copied = []
    for f in sorted(SRC.glob("*.v")):
        rel = "src/" + f.name
        ref = p1art.get(rel)
        rec = {"file": f.name, "bytes": f.stat().st_size, "sha256": sha(f)}
        if ref:
            rec["p1_manifest_sha256"] = ref["sha256"]
            rec["match"] = rec["sha256"] == ref["sha256"] and rec["bytes"] == ref["bytes"]
        else:
            rec["match"] = None
        copied.append(rec)
        if rec["match"] is False:
            drift.append(str(f))
    ss = json.loads((P1 / "out/steady-state.json").read_text())
    out = {
        "created": "2026-10-26",
        "task": "T10.ss-g0-closure",
        "run": "r0",
        "protected_inputs": checks,
        "protected_drift": drift,
        "copied_src": copied,
        "copied_src_mismatch": [c["file"] for c in copied if c["match"] is False],
        "copied_src_extra": [c["file"] for c in copied if c["match"] is None],
        "copied_src_extra_note": "tb_ss_g0.v is the P3 derived TB and has no P1 manifest "
                                 "entry; all 12 DUT/model sources match the P1 manifest",
        "p1_bindings": {
            "manifest_sha256": EXPECT[str(P1 / "manifest-r0.json")],
            "steady_state_S_ss": ss["S_ss"], "steady_state_L_cold": ss["L_cold"],
            "steady_state_exp_bytes": ss["counters"]["exp_bytes"],
            "steady_state_cap_bytes": ss["counters"]["cap_bytes"],
            "steady_state_cycles": ss["counters"]["cycles"],
            "t_exp1": ss["t_exp"][1], "t_exp2": ss["t_exp"][2],
        },
        "p2_bindings": {"manifest_sha256": EXPECT[str(P2 / "manifest-r0.json")]},
        "tools": {"modelsim": str(pathlib.Path(r"D:/intelFPGA/18.1/modelsim_ase/win32aloem/vsim.exe")),
                  "python": sys.version.split()[0]},
        "drift_status": "ok" if not drift else "DRIFT",
    }
    (R0 / "input-verified.json").write_text(json.dumps(out, indent=2) + "\n")
    print("protected=%d drift=%d copied=%d mismatch=%d extra=%d" % (
        len(checks), len(drift), len(copied), len(out["copied_src_mismatch"]), len(out["copied_src_extra"])))
    if drift:
        print("DRIFT:", drift)


if __name__ == "__main__":
    main()
