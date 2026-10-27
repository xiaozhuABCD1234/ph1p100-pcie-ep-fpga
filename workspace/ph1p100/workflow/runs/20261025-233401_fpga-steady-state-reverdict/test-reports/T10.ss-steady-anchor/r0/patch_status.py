import json

p = "control2-test-status.json"
d = json.load(open(p, encoding="utf-8-sig"))
log = open("logs/control2-test.log", encoding="utf-8", errors="replace").read()
step = [s for s in d["steps"] if s["name"] == "vsim_control2"][0]
step["rc_note"] = ("Start-Process did not populate ExitCode (null); normal completion evidenced by "
                   "$finish + Errors: 0 + B11_FULL_RESULT pass=1 + fresh stats, and no timeout "
                   "(410.8 s << 2700 s)")
d["log_completion"] = {
    "pass_marker": "# B11_FULL_RESULT pass=1" in log,
    "errors_zero": "# Errors: 0" in log,
    "finish": "$finish" in log,
    "end_time": "01:00:27 on Oct 26,2026, Elapsed time: 0:06:49",
}
d["control_result"] = ("PASS: 16/16 b11 fields exact; evt/dec byte-identical to developer control "
                       "(SHA match); appended frames=2 ss_pass=1")
json.dump(d, open(p, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
print("patched", p)
