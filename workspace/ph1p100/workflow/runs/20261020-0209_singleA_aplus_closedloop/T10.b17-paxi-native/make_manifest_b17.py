#!/usr/bin/env python3
"""make_manifest_b17.py -- freeze the T10.b17-paxi-native r0 candidate set.

Collects hashes for the 11 changed sources, the simulation inputs/results, the
single TD build (bit/CWC/BID/compiled + STA numbers) and the board evidence.
Writes CANDIDATE-MANIFEST-b17-paxi-native-r0.json and r0/artifact-hashes.txt.
"""
import hashlib
import json
import pathlib
import re
import subprocess

PKG = pathlib.Path(r"D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b17-paxi-native")
R0 = PKG / "r0"
TD = R0 / "td"
SIM = R0 / "sim"
BOARD = R0 / "board"

CHANGED = [
    ("p2_ddr_bridge.v", "functional: native AW/AR address, wstrb=0, single command, v6"),
    ("camera_a1_uart_top.v", "diagnostic: i_dbg_bridge 512, sts_ext 768, v6 #60..#67"),
    ("p2_a1_board_top.v", "diagnostic: dbg_bridge 512"),
    ("a1_uart_export.v", "diagnostic: status packet v6 273 B / 67 fields"),
    ("f9p_camera_display_core.v", "unchanged"),
    ("a1_ddr_slot_store.v", "unchanged"),
    ("a1_ddr_arb2.v", "unchanged"),
    ("a1_frame_top.v", "unchanged"),
    ("a1_deflate_core.v", "unchanged"),
    ("a1_raw_crop.v", "unchanged"),
    ("cam_diag_mailbox.v", "unchanged (instance W=512 only)"),
]


def sha(p):
    p = pathlib.Path(p)
    return hashlib.sha256(p.read_bytes()).hexdigest().upper() if p.exists() else "MISSING"


def text(p):
    p = pathlib.Path(p)
    return p.read_text(errors="replace") if p.exists() else ""


def sta_numbers():
    out = {}
    for name in ("routed_timing_status.rpt", "phy_pr_timing_flow.rpt", "routed_qor.rpt"):
        t = text(TD / name)
        if not t:
            continue
        for key in ("SWNS", "STNS", "HWNS", "HTNS", "Period Check WNS"):
            m = re.search(key + r":?\s*([-+0-9.]+)", t)
            if m:
                out[key] = float(m.group(1))
        m = re.search(r"([0-9]+)\s+Viol Endpoints", t)
        if m:
            out["viol_endpoints"] = int(m.group(1))
        m = re.search(r"([0-9]+)\s+Total Endpoints", t)
        if m:
            out["total_endpoints"] = int(m.group(1))
    area = text(TD / "routed_area.rpt")
    for key, pat in (("eram", r"#eram\s+([0-9]+)"), ("cwc", r"#cwc\s+([0-9]+)"),
                     ("slice", r"#slice\*\s+([0-9]+)"), ("reg", r"#reg\s+([0-9]+)")):
        m = re.search(pat, area)
        if m:
            out[key] = int(m.group(1))
    for name in ("routed_timing_status.rpt",):
        t = text(TD / name)
        m = re.search(r"([0-9]+)\s+Viol", t)
        if m:
            out.setdefault("viol_endpoints", int(m.group(1)))
    return out


def main():
    man = {
        "task_id": "T10.b17-paxi-native",
        "run_id": "20261020-0209_singleA_aplus_closedloop",
        "package": PKG.as_posix(),
        "candidate": "r0",
        "stopped_modifying": True,
        "declared_scope": [
            "A path only", "single frame export path", "SRAM download only",
            "no Flash", "no PCIe/RK", "no dual-stream/G4",
            "native PAXI boundary: address x8, wstrb=0, ALLOW_CONCURRENT=0",
        ],
        "inputs": [],
        "changed_src": [],
        "sim": {},
        "td": {},
        "board": {},
        "tools": {},
        "commands": [],
    }
    for rel in ("dispatch.json", "dev-plan.md", "fpga-design-guide.md", "handoff.md"):
        man["inputs"].append(dict(path=(PKG / rel).as_posix(), sha256=sha(PKG / rel)))
    man["inputs"].append(dict(path=r"D:/fpga/ph1p100/docs/OpenCode_b15根因审计与定位建议_2026-10-26.md",
                              sha256=sha(r"D:/fpga/ph1p100/docs/OpenCode_b15根因审计与定位建议_2026-10-26.md")))
    for n, cls in CHANGED:
        man["changed_src"].append(dict(name=n, role=cls, sha256=sha(R0 / "changed-src" / n)))

    for p in sorted((R0 / "diag").glob("*")):
        man["sim"].setdefault("diag", []).append(dict(path=p.as_posix(), sha256=sha(p)))
    sim_files = ["p2_paxi_model_b17.v", "tb_b17_paxi_native.sv", "tb_b17_chain.sv",
                 "tb_status_v6.v", "run_b17.py", "check_b17.py", "check_b17_core.py",
                 "neg/p2_ddr_bridge_b15.v", "caps/micro8x2.dec", "caps/mid64x8.dec",
                 "caps/full_grad.dec"]
    man["sim"]["files"] = [dict(name=n, sha256=sha(SIM / n)) for n in sim_files]
    man["sim"]["results"] = []
    for p in sorted(SIM.glob("sim-results-b17-*.json")):
        man["sim"]["results"].append(dict(path=p.as_posix(), sha256=sha(p)))

    for n in ("a1_board.bit", "a1_board.cwc", "a1_board_inst.bid"):
        man["td"][n] = sha(TD / n) if (TD / n).exists() else "ABSENT_STOPPED_BEFORE_BITGEN"
    for p in sorted((TD / "cw").glob("compiled.*")):
        man["td"]["cw/" + p.name] = sha(p)
    man["td"]["sta"] = sta_numbers()
    man["td"]["build"] = dict(
        synth_runs=2, route_launches=2, route_completed=1,
        first_run_interrupted="PRJ-8806 syn_1 exited unexpectedly (license/resource event); "
                              "evidence r0/td/failed_r1/",
        bitgen=0, cwc=0, download=0,
        timing_gate="STOP_WNS_BELOW_+0.003",
        timing_gate_detail="Routed 0 violations, SWNS=+0.002 ns, HWNS=+0.020 ns, "
                           "Period Check WNS=+2.200 ns; worst path is in the frozen "
                           "a1_deflate_core (u_a1/u_a1/u_core/len_r[5] -> add9), not in "
                           "the v6 diagnostics, so the allowed v6-only timing fix does not apply.",
        eram=102, eram_plus_cwc_limit=300,
    )
    man["td"]["build_scripts"] = [dict(path=(TD / n).as_posix(), sha256=sha(TD / n))
                                  for n in ("01_build.tcl", "02_bitgen.tcl", "03_cwc.tcl",
                                            "run_build_b17.ps1", "a1_board.al", "p2_board.sdc",
                                            "board_p2.adc")]
    man["td"]["logs"] = [dict(path=(TD / n).as_posix(), sha256=sha(TD / n))
                         for n in ("build_driver_r0.log", "build_console_r0.log",
                                   "bitgen_console_r0.log", "cwc_console_r0.log")
                         if (TD / n).exists()]
    man["td"]["reports"] = [dict(path=(TD / n).as_posix(), sha256=sha(TD / n))
                            for n in ("routed_timing_status.rpt", "routed_qor.rpt",
                                      "routed_timing_summary.rpt", "routed_area.rpt",
                                      "phy_pr_timing_flow.rpt", "route_flow.status",
                                      "place_flow.status", "params_after.tcl")
                            if (TD / n).exists()]
    man["status"] = "blocked"
    man["blocked_reason"] = "ROUTED_WNS_+0.002_BELOW_+0.003_FLOOR_NO_BITGEN; FTDI_0403:6042_ABSENT"
    man["retest"] = dict(
        functional="not required for this source set: 16-word/S1/S2/S3/P1/v6/negatives PASS",
        engineering="only after planner authorises a permitted timing fix or a new build; "
                    "current routed result is 0 violations but SWNS +0.002 < +0.003",
        system="blocked: FTDI/COM8 absent and no bitstream exists; no board claim",
    )
    for n in ("result-r0.md", "lessons-r0.md"):
        man.setdefault("outputs", []).append(dict(path=(PKG / n).as_posix(), sha256=sha(PKG / n)))

    man["board"] = dict(
        state="blocked", reason="FTDI_0403:6042_absent",
        downloads=0, com8_opened=0, capture_seconds=0,
        preflight=(BOARD / "log/ftdi_preflight.txt").as_posix(),
        blocked_file=(BOARD / "log/board_blocked.txt").as_posix(),
        parser_selftest=(BOARD / "captures/parser_selftest.json").as_posix(),
        sha256=dict(
            preflight=sha(BOARD / "log/ftdi_preflight.txt"),
            blocked=sha(BOARD / "log/board_blocked.txt"),
            parser_selftest=sha(BOARD / "captures/parser_selftest.json"),
            dl_script=sha(BOARD / "dl_b17.tcl"),
            run_script=sha(BOARD / "run_board_b17.ps1"),
            parser=sha(BOARD / "parse_status_v6.py"),
            gate=sha(BOARD / "check_b17_board.py"),
        ),
    )
    try:
        pyver = subprocess.run(["python", "--version"], capture_output=True, text=True).stdout.strip()
    except Exception:  # noqa: BLE001
        pyver = "unknown"
    man["tools"] = dict(td="D:/anlogic/TD_Release_2026.2", modelsim="D:/intelFPGA/18.1/modelsim_ase/win32aloem",
                        python=pyver, vite="not used")
    man["commands"] = [
        dict(cmd="python r0/sim/run_b17.py native", log="r0/sim/logs/b17_native_*.log"),
        dict(cmd="python r0/sim/run_b17.py status", log="r0/sim/logs/b17_status_v6.log"),
        dict(cmd="python r0/sim/run_b17.py chain s3_drop1", log="r0/sim/logs/b17_chain_s3_drop1.log"),
        dict(cmd="vsim tb_b17_chain (S1/S2 full geometry)", log="r0/sim/logs/b17_chain_s1_full_clean.log / b17_chain_s2_full_two.log"),
        dict(cmd="python r0/sim/run_b17.py p1", log="r0/sim/logs/b17_p1_*.log"),
        dict(cmd="powershell r0/td/run_build_b17.ps1", log="r0/td/build_driver_r0.log"),
        dict(cmd="td_commands_prompt 02_bitgen.tcl", log="r0/td/bitgen_console_r0.log"),
        dict(cmd="td_commands_prompt 03_cwc.tcl", log="r0/td/cwc_console_r0.log"),
        dict(cmd="powershell r0/board/run_board_b17.ps1", log="r0/board/log/board_blocked.txt"),
    ]
    man["active_commands"] = 0
    (PKG / "CANDIDATE-MANIFEST-b17-paxi-native-r0.json").write_text(json.dumps(man, indent=2))

    lines = []
    for e in man["changed_src"]:
        lines.append("%s  r0/changed-src/%s" % (e["sha256"], e["name"]))
    for e in man["sim"]["files"]:
        lines.append("%s  r0/sim/%s" % (e["sha256"], e["name"]))
    for e in man["sim"]["results"]:
        lines.append("%s  %s" % (e["sha256"], e["path"].split("T10.b17-paxi-native/")[-1]))
    for e in man["td"].get("reports", []):
        lines.append("%s  %s" % (e["sha256"], e["path"].split("T10.b17-paxi-native/")[-1]))
    for k, v in man["td"].items():
        if isinstance(v, str) and len(v) == 64:
            lines.append("%s  r0/td/%s" % (v, k))
    for e in man.get("outputs", []):
        lines.append("%s  %s" % (e["sha256"], e["path"].split("T10.b17-paxi-native/")[-1]))
    (R0 / "artifact-hashes.txt").write_text("\n".join(lines) + "\n")
    print(json.dumps(man["td"].get("sta", {}), indent=2))
    print("manifest", (PKG / "CANDIDATE-MANIFEST-b17-paxi-native-r0.json").stat().st_size)


if __name__ == "__main__":
    main()
