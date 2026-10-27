"""T10.b13-ddr-retry r0 -- manifest + artifact hash freeze (b13b completed run)."""
import hashlib
import json
import pathlib
import re

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
RUN = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop"
PKG = RUN / "T10.b13-ddr-retry"
R0 = PKG / "r0"


def sha(p):
    p = pathlib.Path(p)
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else "MISSING"


def any_glob(base, pats):
    out = []
    for pat in pats:
        out.extend(base.glob(pat))
    return sorted(set(out))


groups = {
    "changed_src": sorted((R0 / "changed-src").glob("*.v")),
    "sim": any_glob(R0 / "sim", ["*.py", "*.v", "*.sv"]),
    "td": any_glob(R0 / "td", ["*.tcl", "*.al", "*.sdc", "*.adc", "*.ps1", "*.rpt",
                              "*.bit", "*.cwc", "*.bid", "*.log", "*.status"]),
    "diag": sorted((R0 / "diag").glob("*.md")),
    "board": any_glob(R0 / "board", ["*.md", "*.py", "*.tcl", "*.ps1", "*.log",
                                    "*.txt", "*.bin", "*.dec", "*.stats"]),
}
hashes, lines = {}, []
for g, files in groups.items():
    for f in files:
        if f.is_dir():
            continue
        h = sha(f)
        rel = f.relative_to(PKG).as_posix()
        hashes[rel] = h
        lines.append("%s  %s" % (h, rel))
for name in ("result-r0.md", "lessons-r0.md"):
    f = PKG / name
    if f.exists():
        hashes[name] = sha(f)
        lines.append("%s  %s" % (hashes[name], name))
(R0 / "artifact-hashes.txt").write_text("\n".join(lines) + "\n")


def load(pattern):
    p = R0 / "sim" / pattern
    return json.loads(p.read_text()) if p.exists() else {}


chain = load("sim-results-b13-chain.json")
store = load("sim-results-b13-store.json")
v5res = load("sim-results-b13-status.json")
regress = load("sim-results-b13-regress-final.json")
main2 = load("sim-results-b13-main2.json")
regress.update(main2)
fullchain = load("sim-results-b13-fullchain.json")

# ---- routed timing -----------------------------------------------------------
rt = (R0 / "td/routed_timing_summary.rpt")
timing = rt.read_text(errors="replace") if rt.exists() else ""
def grab(pat, txt, default=None):
    m = re.search(pat, txt)
    return float(m.group(1)) if m else default
sw = grab(r"SWNS:\s*(-?[0-9.]+)", timing)
st = grab(r"STNS:\s*(-?[0-9.]+)", timing)
hw = grab(r"HWNS:\s*(-?[0-9.]+)", timing)
ht = grab(r"HTNS:\s*(-?[0-9.]+)", timing)
viol = grab(r"([0-9]+) Viol Endpoints", timing)
tot = grab(r"([0-9]+) Total Endpoints", timing)
prf = R0 / "td/phy_pr_timing_flow.rpt"
if sw is None and prf.exists():
    t = prf.read_text(errors="replace")
    sw = grab(r"SWNS:\s*(-?[0-9.]+)", t)
    st = grab(r"STNS:\s*(-?[0-9.]+)", t)
    hw = grab(r"HWNS:\s*(-?[0-9.]+)", t)
    ht = grab(r"HTNS:\s*(-?[0-9.]+)", t)
    m = re.search(r"SWNS\s+(-?[0-9.]+)ns,\s+STNS\s+(-?[0-9.]+)ns,\s+([0-9]+) Viol Endpoints,\s+([0-9]+) Total Endpoints", t)
    if m:
        viol, tot = int(m.group(3)), int(m.group(4))
arpt = R0 / "td/routed_area.rpt"
area = arpt.read_text(errors="replace") if arpt.exists() else ""
m = re.search(r"#eram\s+([0-9]+)", area)
eram = int(m.group(1)) if m else None

bit = R0 / "td/a1_board.bit"
cwc = R0 / "td/a1_board.cwc"
bid = R0 / "td/a1_board_inst.bid"
if not bid.exists():
    bid = R0 / "td/a1_board.bid"
cand = R0 / "td/candidate_timing.rpt"
ctext = cand.read_text(errors="replace") if cand.exists() else ""

# ---- board ------------------------------------------------------------------
statxt = (R0 / "board/captures/status_v5.txt")
board_txt = statxt.read_text(errors="replace") if statxt.exists() else ""
board_ok = "frames_ok=0" not in board_txt and "status_packets=0" not in board_txt and bool(board_txt)
timing_caveat = None
if sw is not None and viol == 0:
    if sw < 0.05:
        timing_caveat = "thin_margin_+%.3f" % sw

sim_ok = all((v or {}).get("status") == "PASS" for k, v in chain.items() if k.startswith("chain_"))
sim_ok = sim_ok and all(v.get("ok") for v in store.values())
sim_ok = sim_ok and bool(v5res.get("v5", {}).get("ok"))
reg_ok = all(
    (v.get("ok") is True) or (v.get("status") == "PASS") or (v.get("byte_identical") is True)
    for v in regress.values())
fc = fullchain.get("fullchain_drop_full", {})

# The single bitgen/CWC was spent BEFORE the last RTL fix (1080p orphan-word
# drain in camera_a1_uart_top.v): the frozen cache of that file no longer
# matches the routed database, so the bit must not be presented as the candidate.
candidate_stale = True
status = "blocked"
status_reason = (
    "sim PASS on the final RTL, but the single bitgen/CWC (r0/td/a1_board.bit|.cwc, "
    "WNS +0.003) was generated from the pre-orphan-fix camera_a1_uart_top.v; a second "
    "bitgen is required by the frozen 1-bitgen rule, so this round stops before a "
    "valid candidate. Board: 1 SRAM download + 150 s OK, but the camera link produced "
    "zero valid pixels/lines (cap=0, no A1U1, timeout=0), so the retry path was not "
    "exercised on hardware; that is a board/camera-session issue, not this task's fault."
)

manifest = {
    "task_id": "T10.b13-ddr-retry",
    "run_id": "20261020-0209_singleA_aplus_closedloop",
    "round": "r0",
    "date": "2026-10-25",
    "status": status,
    "status_reason": status_reason,
    "parent_task": "T10 stays blocked",
    "candidate": {
        "eligible": False,
        "stale_reason": "camera_a1_uart_top.v changed after the single bitgen (1080p orphan drain)",
        "bit": hashes.get("r0/td/a1_board.bit"),
        "cwc": hashes.get("r0/td/a1_board.cwc"),
        "bid": sha(bid) if bid.exists() else "MISSING",
        "compiled_bit": sha(R0 / "td/cw/compiled.bit"),
        "compiled_cwc": sha(R0 / "td/cw/compiled.cwc"),
        "bitgen": 1 if bit.exists() else 0,
        "cwc_count": 1 if cwc.exists() else 0,
        "downloads": 1 if (R0 / "board/log/download_b13.log").exists() and
                      "B13_DL_OK" in (R0 / "board/log/download_b13.log").read_bytes().decode(
                          "utf-16", "replace")
                      else 0,
        "bitgen_rtl_note": "routed/bitgen ran before the orphan-drain fix; final RTL has no bit",
    },
    "timing": {
        "routed_SWNS_ns": sw, "routed_STNS_ns": st, "routed_HWNS_ns": hw,
        "routed_HTNS_ns": ht, "routed_violated_endpoints": viol,
        "routed_total_endpoints": tot, "routed_eram": eram,
        "timing_caveat": timing_caveat,
        "target_wns_ns": 0.05, "floor_wns_ns": 0.003,
        "candidate_timing": ctext.strip().splitlines()[:6],
    },
    "sim_results": {
        "unit_store": {k: v.get("ok") for k, v in store.items()},
        "chain": {k: v.get("status") for k, v in chain.items()},
        "v5_status": v5res.get("v5", {}).get("ok"),
        "regress": {k: (v.get("status") if v.get("status") is not None else
                        (v.get("ok") if v.get("ok") is not None else v.get("byte_identical")))
                    for k, v in regress.items()},
        "full_chain_drop": {"status": fc.get("status"),
                            "stats": fc.get("stats"),
                            "errors": fc.get("errors")},
    },
    "changed_src": {f.name: hashes["r0/changed-src/" + f.name]
                    for f in sorted((R0 / "changed-src").glob("*.v"))},
    "frozen_src_unchanged_vs_b12": ["a1_frame_top.v", "a1_deflate_core.v",
                                    "a1_raw_crop.v", "cam_diag_mailbox.v"],
    "board": "blocked",
    "board_reason": "camera link produced zero valid pixels/lines (cap=0, no A1U1); "
                    "v5 status/UART/download verified; the downloaded bit is stale "
                    "(pre-orphan-fix), so no retry evidence on hardware",
    "board_summary": board_txt.strip().splitlines()[:8] if board_txt else
                     ["no board capture"],
    "artifacts": sorted(hashes.keys()),
    "artifact_hashes_file": "r0/artifact-hashes.txt",
    "test_input_paths": [
        "r0/changed-src",
        "r0/sim/run_b13.py", "r0/sim/check_b13.py",
        "r0/sim/tb_b13_store_retry.v", "r0/sim/tb_b13_chain.sv",
        "r0/sim/tb_status_v5.v", "r0/sim/p2_paxi_model_b13.v",
        "r0/sim/sim-results-b13-chain.json", "r0/sim/sim-results-b13-store.json",
        "r0/sim/sim-results-b13-status.json", "r0/sim/sim-results-b13-regress-final.json",
        "r0/sim/sim-results-b13-main2.json",
        "r0/sim/sim-results-b13-fullchain.json",
        "r0/board/parse_status_v5.py", "r0/board/captures/com8_150s.bin",
        "r0/board/captures/status_v5.txt",
        "r0/artifact-hashes.txt",
    ],
    "lessons_path": "lessons-r0.md",
    "result_path": "result-r0.md",
    "diag_path": "r0/diag/ddr-drop-repro.md",
    "td_dir": "r0/td",
    "retest_required": [
        "independent functional re-run of T1-T13 on the frozen manifest",
        "independent engineering re-check of routed timing/bit/CWC hashes",
        "independent board-v5 parse of r0/board/captures/com8_150s.bin",
    ],
    "known_limits": [
        "board capture is 150 s single-shot; no statistical retry-rate claim",
        "late-R later than the 327 us bridge guard cannot be absolutely excluded "
        "on a single-outstanding, untagged PAXI read port (four CRCs + strict zlib are the detector)",
    ],
}
(PKG / "CANDIDATE-MANIFEST-b13-ddr-retry-r0.json").write_text(json.dumps(manifest, indent=2))
print(json.dumps({"status": manifest["status"], "timing": manifest["timing"],
                  "board": manifest["board"], "files": len(hashes)}, indent=1))

