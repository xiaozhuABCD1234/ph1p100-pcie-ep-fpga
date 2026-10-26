"""Read-only B01 identity gate. Writes T02 evidence only; never operates JTAG."""
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time

sys.stdout.reconfigure(encoding="utf-8")
OUT = Path(__file__).resolve().parent
RUN = OUT.parents[1]
ROOT = RUN.parents[2]
REC = RUN / "recovery01/B01/timing-continuation01/remaining-attempts01"
MF = REC / "candidate/manifest.json"
EXPECTED = "c7a40897166467f2beafb096701dba9cf836e1007d77ae03d90009d06f80d757"

def now():
    return dt.datetime.now().astimezone().isoformat()

def safe_out(name):
    p = OUT / name
    assert p.resolve().is_relative_to(OUT.resolve()), str(p)
    for a in [p, *p.parents]:
        if a.exists():
            assert not (a.lstat().st_file_attributes & 1024), "reparse point: " + str(a)
    return p

def write(name, value):
    safe_out(name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

def sha(p):
    h = hashlib.sha256()
    with p.open("rb") as f:
        for b in iter(lambda: f.read(8 * 1024 * 1024), b""):
            h.update(b)
    return h.hexdigest()

def main():
    timer = threading.Timer(300, lambda: os._exit(124))
    timer.daemon = True
    timer.start()
    started = now()
    write("execution-budget.json", {
        "task_id": "T02.codex-singleA-board", "developer_id": "/root/fpga_dev_singlea_board",
        "started_at_conservative_lower_bound": "2026-10-19T20:48:00+08:00",
        "first_observed_clock": "2026-10-19T20:50:08.4529041+08:00",
        "deadline": "2026-10-19T21:33:00+08:00",
        "max_tool_calls": 30, "tool_calls_used_through_preflight_launch": 8,
        "static_native_timeout_seconds": 300, "read_search_native_timeout_seconds": 60,
        "sram_native_timeout_seconds": 120, "sram_executions_used": 0, "sram_executions_max": 1,
        "sample_groups_used": 0, "sample_groups_max": 3, "sample_group_seconds_max": 300,
        "production_used": 6, "production_max": 6, "repair_rounds_used": 0,
        "waiting_policy": "Stop and return blocked at operator dependency; no background waiting."
    })
    assert ROOT == Path.cwd().resolve(), (ROOT, Path.cwd())
    m = json.loads(MF.read_text(encoding="utf-8"))
    assert sha(MF) == EXPECTED
    assert len(m["entries"]) == 699 and m["frozen"] and m["ready_for_test"]
    assert m["production_attempts_used"] == 6 and m["production_attempts_max"] == 6
    reports = []
    for task in ["T06.codex-ddr-readback-int", "T09.codex-production-int"]:
        p = RUN / "test-reports" / (task + "-r0-integrated.md")
        text = p.read_text(encoding="utf-8-sig")
        assert text.splitlines()[0] == "### 判定：PASS"
        assert EXPECTED in text and task in text and "integrated" in text
        reports.append({"task_id": task, "path": str(p), "sha256": sha(p), "verdict": "PASS", "scope": "B01 G0-G2 only"})
    audit = []
    for e in m["entries"]:
        p = Path(e["path"])
        digest = sha(p)
        assert digest == e["sha256"], str(p)
        assert p.stat().st_size == e["size"], str(p)
        audit.append({"path": str(p), "resolved_path": str(p.resolve()), "size": e["size"], "sha256": digest, "match": True})
    assert sha(MF) == EXPECTED
    write("b01-input-audit.json", {"started_at": started, "completed_at": now(), "manifest": str(MF), "manifest_sha256": EXPECTED, "entries_count": len(audit), "mismatches": 0, "entries": audit})
    pm = json.loads((REC / "candidate/probe-map.json").read_text(encoding="utf-8"))
    probes = [{k: v for k, v in p.items() if k != "nets"} for p in pm["probes"]]
    assert len(probes) == 40 and all(p["width"] == 32 for p in probes)
    safe_out("probe-reference.md").write_text(
        "# T02 exact probe reference\n\nSource: " + str(REC / "candidate/probe-map.json") +
        "\n\n| Instance | Clock | Exact 32-bit probe |\n|---|---|---|\n" +
        "".join("| " + p["instance"] + " | " + p["clock"] + " | `" + p["name"] + "` |\n" for p in probes) +
        "\n" + pm["snapshot_rule"] + "\n\n" + pm["recovery_rule"] + "\n", encoding="utf-8")
    tcl = (REC / "board/download_sram.tcl").read_text(encoding="utf-8")
    assert "PH1P100" in tcl and "-mode jtag -spd 7 -cable 0" in tcl
    assert "127.0.0.1:5555" in tcl and "B01_SRAM_PASS" in tcl
    wrapper = REC / "scripts/run_sram.py"
    cmd = [sys.executable, "-B", str(wrapper)]
    t = time.monotonic()
    p = subprocess.run(cmd, cwd=ROOT, text=True, encoding="utf-8", errors="replace", capture_output=True, timeout=60)
    write("dry-validation.json", {"command": cmd, "cwd": str(ROOT), "started_at": started,
        "elapsed_seconds": time.monotonic()-t, "timeout_seconds": 60, "exit": p.returncode,
        "stdout": p.stdout, "stderr": p.stderr, "hardware_executed": False})
    assert p.returncode == 0 and "Validated reports and candidate" in p.stdout
    git = subprocess.run(["git", "-c", "core.quotepath=false", "status", "--short"], cwd=ROOT,
        capture_output=True, timeout=60, text=True, encoding="utf-8", errors="replace")
    write("workspace-baseline.json", {"time": now(), "command": ["git", "-c", "core.quotepath=false", "status", "--short"],
        "exit": git.returncode, "stdout": git.stdout, "stderr": git.stderr,
        "ownership": "Pre-existing dirty files and all B01 files are read-only; this role owns only newly created T02 evidence."})
    lessons_path = REC / "lessons-learned.md"
    lessons = lessons_path.read_text(encoding="utf-8")
    write("preflight.json", {"task_id": "T02.codex-singleA-board", "status": "ready_for_operator",
        "completed_at": now(), "manifest_path": str(MF), "manifest_sha256": EXPECTED,
        "entries_verified": 699, "mismatches": 0, "reports": reports,
        "bit": {"path": str(REC / "candidate/current.bit"), "sha256": sha(REC / "candidate/current.bit")},
        "cwc": {"path": str(REC / "candidate/current.cwc"), "sha256": sha(REC / "candidate/current.cwc")},
        "bid": {"path": str(REC / "candidate/current.bid"), "sha256": sha(REC / "candidate/current.bid")},
        "probe_map_sha256": sha(REC / "candidate/probe-map.json"), "probe_count": len(probes),
        "reviewed_script_sha256": sha(wrapper), "reviewed_tcl_sha256": sha(REC / "board/download_sram.tcl"),
        "reviewed_lessons_path": str(lessons_path), "reviewed_lessons_sha256": sha(lessons_path), "reviewed_lessons_characters": len(lessons),
        "native_downloader_exists": Path("D:/anlogic/TD_Release_2026.2/bin/bw.exe").is_file(),
        "parameters": m["parameters"], "device": m["device"], "tool_versions": m["tool_versions"],
        "current_operator_reply_path": None, "hardware_executed": False,
        "G3": "blocked pending current on-site facts then GUI captures; geometry/phase and exact recovery remain unproven",
        "G4": "not_run_deferred_by_user", "ready_for_test": False})
    print(json.dumps({"status": "ready_for_operator", "entries_verified": 699, "mismatches": 0,
        "dry_validation_exit": p.returncode, "hardware_executed": False, "preflight_path": str(OUT / "preflight.json")}, ensure_ascii=False))

if __name__ == "__main__":
    main()
