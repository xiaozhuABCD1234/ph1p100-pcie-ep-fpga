"""T02 owned bounded launcher for the frozen SRAM entry; no retries."""
from pathlib import Path
import datetime as dt
import hashlib
import json
import os
import subprocess
import sys
import threading
import time

sys.stdout.reconfigure(encoding="utf-8")
OUT = Path(__file__).resolve().parent
RUN = OUT.parents[1]
ROOT = RUN.parents[2]
REC = RUN / "recovery01/B01/timing-continuation01/remaining-attempts01"

def sha(p):
    h = hashlib.sha256()
    with p.open("rb") as f:
        for b in iter(lambda: f.read(8388608), b""):
            h.update(b)
    return h.hexdigest()

def safe(p):
    assert p.resolve().is_relative_to(OUT.resolve()), str(p)
    for a in [p, *p.parents]:
        if a.exists():
            assert not a.lstat().st_file_attributes & 1024, str(a)
    return p

def write(name, data):
    safe(OUT / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

def now():
    return dt.datetime.now().astimezone().isoformat()

def main():
    timer = threading.Timer(60, lambda: os._exit(124))
    timer.daemon = True
    timer.start()
    assert ROOT == Path.cwd().resolve()
    assert not (OUT / "sram-execution.json").exists(), "one-shot ledger already exists"
    budget = json.loads((OUT / "execution-budget.json").read_text(encoding="utf-8"))
    assert budget["sram_executions_used"] == 0 and budget["sample_groups_used"] == 0
    assert dt.datetime.now().astimezone() + dt.timedelta(seconds=240) < dt.datetime.fromisoformat(budget["deadline"])
    reply_path = RUN / "request-followup-05.md"
    reply = reply_path.read_text(encoding="utf-8-sig")
    assert "在场，单A已上电，JTAG空闲" in reply
    mf = REC / "candidate/manifest.json"
    expected = "c7a40897166467f2beafb096701dba9cf836e1007d77ae03d90009d06f80d757"
    assert sha(mf) == expected
    m = json.loads(mf.read_text(encoding="utf-8"))
    for e in m["entries"]:
        p = Path(e["path"])
        assert p.stat().st_size == e["size"] and sha(p) == e["sha256"], str(p)
    for name in ["development-result.json", "execution-budget.json", "preflight-manifest.json"]:
        safe(OUT / ("pre-sram-" + name)).write_bytes((OUT / name).read_bytes())
    before = {p.resolve() for p in (RUN / "board").glob("sram-b01-*")}
    command = [sys.executable, "-B", str(REC / "scripts/run_sram.py"), "--execute"]
    record = {"task_id": "T02.codex-singleA-board", "started_at": now(),
        "command": command, "cwd": str(ROOT), "operator_reply_path": str(reply_path),
        "operator_reply_sha256": sha(reply_path), "operator_reply_verbatim": reply,
        "manifest_path": str(mf), "manifest_sha256_before": expected,
        "entries_verified_before": 699, "native_SRAM_deadline_seconds": 120,
        "outer_wrapper_deadline_seconds": 180, "execution_attempt": 1,
        "native_SRAM_attempts_max": 1, "automatic_retry": False, "status": "starting"}
    budget["sram_executions_used"] = 1
    budget["tool_calls_used_through_SRAM_launch"] = 15
    budget["resumed_at_with_actual_reply"] = now()
    write("execution-budget.json", budget)
    write("sram-execution.json", record)
    timer.cancel()
    started = time.monotonic()
    with safe(OUT / "sram-entry.stdout.log").open("w", encoding="utf-8") as log:
        proc = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        record["owned_wrapper_PID"] = proc.pid
        write("sram-execution.json", record)
        try:
            code = proc.wait(timeout=180)
            timeout = False
        except subprocess.TimeoutExpired:
            subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                stdout=log, stderr=log, timeout=20)
            code = proc.wait(timeout=20)
            timeout = True
    timer = threading.Timer(60, lambda: os._exit(124))
    timer.daemon = True
    timer.start()
    after = {p.resolve() for p in (RUN / "board").glob("sram-b01-*")}
    created = sorted(after - before)
    record.update({"completed_at": now(), "elapsed_seconds": time.monotonic() - started,
        "wrapper_exit": code, "outer_timeout": timeout, "stdout_path": str(OUT / "sram-entry.stdout.log"),
        "created_native_log_dirs": [str(p) for p in created], "owned_wrapper_activity_stopped": True})
    if len(created) == 1:
        native = created[0]
        assert native.parent == (RUN / "board").resolve() and native.name.startswith("sram-b01-")
        for a in [native, *native.parents]:
            assert not a.lstat().st_file_attributes & 1024, str(a)
        rp = native / "result.json"
        lp = native / "download.log"
        if rp.is_file():
            record["native_result"] = json.loads(rp.read_text(encoding="utf-8"))
        if lp.is_file():
            text = lp.read_text(encoding="utf-8", errors="replace")
            record["download_log_path"] = str(lp)
            record["download_log_sha256"] = sha(lp)
            record["download_log_size"] = lp.stat().st_size
            record["device_lines"] = [line for line in text.splitlines() if "B01_SRAM_DEVICE" in line]
            record["native_PID_lines"] = [line for line in text.splitlines() if "OWN_PID=" in line]
            record["success_marker_present"] = "B01_SRAM_PASS" in text
    for e in m["entries"]:
        p = Path(e["path"])
        assert p.stat().st_size == e["size"] and sha(p) == e["sha256"], str(p)
    record.update({"manifest_sha256_after": sha(mf), "entries_verified_after": 699,
        "input_drift": 0, "status": "completed"})
    native_result = record.get("native_result", {})
    record["download_success"] = (code == 0 and not timeout and native_result.get("pass") is True
        and native_result.get("timeout") is False and record.get("success_marker_present") is True
        and any("PH1P100" in line for line in record.get("device_lines", [])))
    write("sram-execution.json", record)
    print(json.dumps(record, ensure_ascii=False))
    sys.exit(0 if record["download_success"] else 1)

if __name__ == "__main__":
    main()
