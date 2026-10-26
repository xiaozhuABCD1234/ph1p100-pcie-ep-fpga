#!/usr/bin/env python3
"""make_manifest_b17_r1.py -- freeze the T10.b17-paxi-native r1 candidate set.

r1 = one bitgen + one CWC from the frozen r0 routed DB, plus one blocked board
attempt.  This script only reads existing evidence and writes the r1 manifest
and r1/artifact-hashes.txt.  It does not run TD, open COM8 or touch hardware.
"""
import hashlib
import json
import pathlib
import re
import subprocess

PKG = pathlib.Path(r"D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b17-paxi-native")
R0 = PKG / "r0"
R1 = PKG / "r1"
TD0 = R0 / "td"
TD1 = R1 / "td"
BRD = R1 / "board"

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


def parse_sta():
    t = text(TD1 / "candidate_timing.rpt")
    out = {}
    for key in ("SWNS", "STNS", "HWNS", "HTNS", "Period Check WNS"):
        m = re.search(key + r":?\s*([-+0-9.]+)", t)
        if m:
            out[key] = float(m.group(1))
    m = re.search(r"([0-9]+)\s+Viol Endpoints,\s+([0-9]+)\s+Total Endpoints", t)
    if m:
        out["viol_endpoints"] = int(m.group(1))
        out["total_endpoints"] = int(m.group(2))
    m = re.search(r"Top Model\s*:\s*(\S+)", t)
    if m:
        out["top"] = m.group(1)
    m = re.search(r"Device\s*:\s*(\S+)", t)
    if m:
        out["device"] = m.group(1)
    m = re.search(r"STA coverage\s*:\s*([0-9.]+%)", t)
    if m:
        out["sta_coverage"] = m.group(1)
    m = re.search(r"Constraint File\s*:\s*(\S+);", t)
    if m:
        out["constraint_file"] = m.group(1)
    return out


def parse_area():
    t = text(TD0 / "routed_area.rpt")
    out = {}
    for key, pat in (("eram", r"#eram\s+([0-9]+)\s+out of\s+([0-9]+)"),
                     ("slice", r"#slice\s+([0-9]+)\s+out of\s+([0-9]+)"),
                     ("reg", r"#reg\s+([0-9]+)")):
        m = re.search(pat, t)
        if m:
            out[key] = int(m.group(1))
            if len(m.groups()) > 1:
                out[key + "_limit"] = int(m.group(2))
    return out


def main():
    r0_hashes = {}
    for line in text(R0 / "artifact-hashes.txt").splitlines():
        parts = line.split()
        if len(parts) == 2 and "/changed-src/" in parts[1]:
            r0_hashes[parts[1].split("/changed-src/")[-1]] = parts[0]

    src = []
    for name, role in CHANGED:
        h = sha(R0 / "changed-src" / name)
        src.append(dict(name=name, role=role, sha256=h,
                        matches_r0_manifest=(h == r0_hashes.get(name))))

    bit = sha(TD1 / "a1_board.bit")
    cwc = sha(TD1 / "a1_board.cwc")
    bid = sha(TD1 / "a1_board_inst.bid")
    cbit = sha(TD1 / "cw/compiled.bit")
    ccwc = sha(TD1 / "cw/compiled.cwc")

    same = lambda a, b: (a != "MISSING" and a == b)
    man = {
        "task_id": "T10.b17-paxi-native",
        "run_id": "20261020-0209_singleA_aplus_closedloop",
        "package": PKG.as_posix(),
        "candidate": "r1",
        "phase": "single_bitgen_single_cwc_from_frozen_r0_route",
        "stopped_modifying": True,
        "declared_scope": [
            "A path only", "single frame export path", "SRAM download only",
            "no Flash", "no PCIe/RK", "no dual-stream/G4",
            "native PAXI boundary: address x8, wstrb=0, ALLOW_CONCURRENT=0",
            "diagnostic bitstream only: not production timing sign-off",
        ],
        "timing_caveat": "thin_margin_+0.002",
        "planner_decision": dict(
            decision="ACCEPT_+0.002_0_VIOLATIONS_AS_DIAGNOSTIC_CANDIDATE",
            round="r1",
            source="planner r1 instruction (user message), explicit waiver of dev-plan §6 +0.003 floor",
            constraints=["no re-synthesis", "no re-route", "no SDC/seed/clock change",
                         "no source change", "one bitgen + one CWC"],
            production_signoff=False,
        ),
        "status": "blocked",
        "dimension_results": {
            "functional": "pass_inherited_r0_unchanged_sources",
            "engineering": "pass_diagnostic_candidate_thin_margin_+0.002",
            "system": "blocked_ftdi_absent",
            "G0": "pass_input_hashes_match",
            "G1": "pass_inherited_r0_simulation_replayable",
            "G2": "pass_same_routed_db_bit_cwc",
            "G3": "blocked_no_hardware_no_download",
            "G4": "not_run_no_flash_long_term",
        },
        "blocked": [
            dict(category="hardware", status="blocked", reason="FTDI_0403:6042_absent",
                 resume="connect the board FTDI (JTAG A / UART B = COM8) and run one SRAM download + 150 s capture"),
            dict(category="signoff", status="not_production", reason="timing_caveat=thin_margin_+0.002",
                 resume="new build must clear +0.003 ns for production sign-off"),
        ],
        "inputs": [
            dict(path=(PKG / "dev-plan.md").as_posix(), sha256=sha(PKG / "dev-plan.md")),
            dict(path=(PKG / "CANDIDATE-MANIFEST-b17-paxi-native-r0.json").as_posix(),
                 sha256=sha(PKG / "CANDIDATE-MANIFEST-b17-paxi-native-r0.json")),
            dict(path=(TD0 / "a1_board_Runs/phy_1/a1_board_pr.db").as_posix(),
                 sha256=sha(TD0 / "a1_board_Runs/phy_1/a1_board_pr.db")),
            dict(path=(TD0 / "routed_timing_status.rpt").as_posix(),
                 sha256=sha(TD0 / "routed_timing_status.rpt")),
            dict(path=(TD0 / "routed_qor.rpt").as_posix(), sha256=sha(TD0 / "routed_qor.rpt")),
            dict(path=(TD0 / "routed_area.rpt").as_posix(), sha256=sha(TD0 / "routed_area.rpt")),
            dict(path=(TD0 / "route_flow.status").as_posix(), sha256=sha(TD0 / "route_flow.status")),
            dict(path=(TD0 / "a1_board.al").as_posix(), sha256=sha(TD0 / "a1_board.al"),
                 note="r0 input project file; r1 copy was normalised by open_project"),
        ],
        "source_set": {
            "root": (R0 / "changed-src").as_posix(),
            "unchanged_from_r0": True,
            "all_match_r0_manifest": all(e["matches_r0_manifest"] for e in src),
            "files": src,
        },
        "td": {
            "input_db": dict(path=(TD1 / "a1_board_Runs/phy_1/a1_board_pr.db").as_posix(),
                             sha256=sha(TD1 / "a1_board_Runs/phy_1/a1_board_pr.db"),
                             size=(TD1 / "a1_board_Runs/phy_1/a1_board_pr.db").stat().st_size,
                             identical_to_r0=(sha(TD1 / "a1_board_Runs/phy_1/a1_board_pr.db")
                                              == sha(TD0 / "a1_board_Runs/phy_1/a1_board_pr.db"))),
            "bit": dict(path=(TD1 / "a1_board.bit").as_posix(), sha256=bit,
                        size=(TD1 / "a1_board.bit").stat().st_size),
            "cwc": dict(path=(TD1 / "a1_board.cwc").as_posix(), sha256=cwc,
                        size=(TD1 / "a1_board.cwc").stat().st_size),
            "bid": dict(path=(TD1 / "a1_board_inst.bid").as_posix(), sha256=bid,
                        size=(TD1 / "a1_board_inst.bid").stat().st_size),
            "cw_compiled_bit": dict(path=(TD1 / "cw/compiled.bit").as_posix(), sha256=cbit,
                                    equals_parent=same(cbit, bit)),
            "cw_compiled_cwc": dict(path=(TD1 / "cw/compiled.cwc").as_posix(), sha256=ccwc,
                                    equals_parent=same(ccwc, cwc)),
            "contrast_b15_r0": dict(
                bit="C9292CA1C00A0E8DFDDABBE1D1D04EF262327F603F43E50B984223B9D7BBC40F",
                cwc="A5036B6D906E99224EDCD4A9BAF0BA276FD13BCC3579A25C58329E41BE764626",
                bid="3DF29D6C45D949DBA19E277F9B78856A5B552203A022E3DA1AFD1782D027CDD5",
                differs=True),
            "sta": parse_sta(),
            "area": parse_area(),
            "build": dict(
                synthesis_runs=0, route_runs=0, bitgen=1, cwc=1, download=0, flash=0,
                timing_gate="ACCEPTED_BY_PLANNER_R1_WAIVER_THIN_MARGIN_+0.002",
                timing_gate_detail="0 violations / 26,705 endpoints; SWNS +0.002 < dev-plan +0.003 floor; "
                                   "critical path remains in the frozen a1_deflate_core; diagnostic candidate only.",
                eram_plus_cwc=102, eram_plus_cwc_limit=300,
                device="PH1P100SBG484 speed 3",
            ),
            "scripts": [dict(path=(TD1 / n).as_posix(), sha256=sha(TD1 / n),
                             identical_to_r0=(sha(TD1 / n) == sha(TD0 / n)))
                        for n in ("02_bitgen.tcl", "03_cwc.tcl", "run_bitgen_cwc_b17_r1.ps1",
                                  "p2_board.sdc", "board_p2.adc", "a1_eng_top.v", "a1_small_top.sdc")],
            "project_file": dict(path=(TD1 / "a1_board.al").as_posix(),
                                 sha256=sha(TD1 / "a1_board.al"),
                                 input_r0_sha256=sha(TD0 / "a1_board.al"),
                                 source_entries=59,
                                 source_list_identical_after_normalisation=True,
                                 metadata_only_rewrite="Path T:/ -> T:/., added UCode, ./src -> src"),
            "logs": [dict(path=(TD1 / n).as_posix(), sha256=sha(TD1 / n))
                     for n in ("bitgen_console_r1.log", "cwc_console_r1.log",
                               "run_bitgen_cwc_driver_r1.log", "candidate_timing.rpt",
                               "candidate_abnormal.rpt", "candidate_hashes_r1.txt")],
        },
        "board": dict(
            state="blocked", reason="FTDI_0403:6042_absent",
            ftdi_present=False, com8_present=False, serial_ports=["COM3", "COM4"],
            downloads=0, com8_opened=0, capture_seconds=0,
            v6_decoded=False, v6_packets=0, enc_frames=None, exported=None,
            preflight=(BRD / "log/ftdi_preflight.txt").as_posix(),
            serial_ports_file=(BRD / "log/serial_ports_r1.txt").as_posix(),
            blocked_file=(BRD / "log/board_blocked.txt").as_posix(),
            driver_log=(BRD / "log/board_driver_r1.log").as_posix(),
            download_log_absent=not (BRD / "log/download_b17.log").exists(),
            hwserver_processes=0,
            sha256=dict(
                preflight=sha(BRD / "log/ftdi_preflight.txt"),
                serial_ports=sha(BRD / "log/serial_ports_r1.txt"),
                blocked=sha(BRD / "log/board_blocked.txt"),
                driver_log=sha(BRD / "log/board_driver_r1.log"),
                dl_script=sha(BRD / "dl_b17_r1.tcl"),
                run_script=sha(BRD / "run_board_b17_r1.ps1"),
                parser=sha(BRD / "parse_status_v6.py"),
                gate=sha(BRD / "check_b17_board.py"),
                capture=sha(BRD / "capture_com8.py"),
                parser_selftest_r0=sha(R0 / "board/captures/parser_selftest.json"),
            ),
        ),
        "commands": [
            dict(cmd="powershell -NoProfile -ExecutionPolicy Bypass -File r1/td/run_bitgen_cwc_b17_r1.ps1",
                 cwd="D:/fpga/ph1p100", exit=0, marker="B17_R1_BITGEN_CWC_DONE",
                 log="r1/td/run_bitgen_cwc_driver_r1.log"),
            dict(cmd="td_commands_prompt.exe 02_bitgen.tcl", cwd="T:/", exit=0,
                 marker="P2_CANDIDATE_BIT_GENERATED_NO_DOWNLOAD",
                 log="r1/td/bitgen_console_r1.log",
                 sta="P2_BITGEN_STA_SETUP=0.002/0.000 HOLD=0.020/0.000 PERIOD=2.200"),
            dict(cmd="td_commands_prompt.exe 03_cwc.tcl", cwd="T:/", exit=0,
                 marker="P2_MATCHING_CWC_EXPORTED_NO_DOWNLOAD",
                 log="r1/td/cwc_console_r1.log"),
            dict(cmd="powershell -NoProfile -ExecutionPolicy Bypass -File r1/board/run_board_b17_r1.ps1",
                 cwd="D:/fpga/ph1p100", exit=4,
                 marker="BOARD_BLOCKED_FTDI_ABSENT", log="r1/board/log/board_driver_r1.log",
                 note="script exit 4 is the intended board_blocked branch; download path not entered"),
        ],
        "tools": dict(td="D:/anlogic/TD_Release_2026.2 (Tang Dynasty Release_2026.2)",
                      device="PH1P100SBG484 -3", python=subprocess.run(
                          ["python", "--version"], capture_output=True, text=True).stdout.strip()),
        "active_commands": 0,
        "retest": dict(
            required_dimensions=["functional", "engineering", "system"],
            required_checks=[
                "functional: reuse r0 16-word/S1/S2/S3/P1/v6/negative evidence only if bound to the r0 manifest hash",
                "engineering: bit/CWC/BID hashes and cw/compiled.* byte-identity against this frozen manifest",
                "engineering: record timing_caveat=thin_margin_+0.002; 0 violations; no production sign-off",
                "system: requires a hardware window; FTDI present, 1 SRAM download, then 150 s COM8 v6 parse",
            ],
            report_paths=[(PKG / "CANDIDATE-MANIFEST-b17-paxi-native-r1.json").as_posix(),
                          (R1 / "result-r1.md").as_posix(),
                          (TD1 / "candidate_timing.rpt").as_posix(),
                          (TD1 / "candidate_hashes_r1.txt").as_posix(),
                          (BRD / "log/board_blocked.txt").as_posix()],
            input_status="source same as r0 (11/11 hashes); new derivative bit/CWC from byte-identical r0 routed DB",
            reuse_decision_paths=[(PKG / "CANDIDATE-MANIFEST-b17-paxi-native-r0.json").as_posix(),
                                  (R0 / "sim").as_posix(),
                                  (R0 / "artifact-hashes.txt").as_posix()],
        ),
    }
    man["outputs"] = [dict(path=(R1 / n).as_posix(), sha256=sha(R1 / n))
                      for n in ("result-r1.md", "lessons-r1.md", "make_manifest_b17_r1.py")]

    mp = PKG / "CANDIDATE-MANIFEST-b17-paxi-native-r1.json"
    mp.write_text(json.dumps(man, indent=2))

    lines = []
    for e in man["inputs"]:
        lines.append("%s  %s" % (e["sha256"], e["path"].split("T10.b17-paxi-native/")[-1]))
    for e in man["source_set"]["files"]:
        lines.append("%s  r0/changed-src/%s" % (e["sha256"], e["name"]))
    for k in ("bit", "cwc", "bid"):
        lines.append("%s  r1/td/%s" % (man["td"][k]["sha256"], man["td"][k]["path"].split("/")[-1]))
    for k in ("cw_compiled_bit", "cw_compiled_cwc"):
        lines.append("%s  r1/td/cw/%s" % (man["td"][k]["sha256"], man["td"][k]["path"].split("/")[-1]))
    for e in man["td"]["scripts"] + man["td"]["logs"]:
        lines.append("%s  %s" % (e["sha256"], e["path"].split("T10.b17-paxi-native/")[-1]))
    lines.append("%s  r1/td/a1_board.al" % man["td"]["project_file"]["sha256"])
    for k, v in man["board"]["sha256"].items():
        lines.append("%s  board_%s" % (v, k))
    for e in man["outputs"]:
        if e["sha256"].startswith("SELF"):
            continue
        lines.append("%s  %s" % (e["sha256"], e["path"].split("T10.b17-paxi-native/")[-1]))
    (R1 / "artifact-hashes.txt").write_text("\n".join(lines) + "\n")
    print(json.dumps({"sta": man["td"]["sta"], "area": man["td"]["area"],
                      "src_ok": man["source_set"]["all_match_r0_manifest"],
                      "bit": bit, "cwc": cwc, "bid": bid,
                      "compiled_ok": [man["td"]["cw_compiled_bit"]["equals_parent"],
                                      man["td"]["cw_compiled_cwc"]["equals_parent"]]}, indent=2))


if __name__ == "__main__":
    main()
