import pathlib

R0 = pathlib.Path(r"D:/fpga/ph1p100/workflow/runs/20261025-233401_fpga-steady-state-reverdict/T10.ss-g0-closure/r0")


def patch(path, pairs):
    p = pathlib.Path(path)
    t = p.read_text(encoding="utf-8")
    for old, new in pairs:
        if t.count(old) != 1:
            raise SystemExit("PATCH FAIL %s count=%d for %r" % (p.name, t.count(old), old[:90]))
        t = t.replace(old, new)
    p.write_text(t, encoding="utf-8", newline="\n")
    print("patched", p.name)


# ------------------------------------------------------------------ freeze.py
patch(R0 / "sim" / "freeze.py", [
    ('EXCLUDE = {"manifest-r1.json", "_repair.py"}', 'EXCLUDE = {"manifest-r2.json", "_repair.py"}'),
    ('        "repair_round": 1,', '        "repair_round": 2,'),
    ('        "previous_manifest": {"path": "manifest-r0.json",\n'
     '                              "sha256": sha(R0 / "manifest-r0.json") if (R0 / "manifest-r0.json").exists() else None},',
     '        "previous_manifest": {"path": "manifest-r1.json",\n'
     '                              "sha256": sha(R0 / "manifest-r1.json") if (R0 / "manifest-r1.json").exists() else None},'),
    ('            "r3_S_ss": (verdict.get("runs", {}).get("r3", {}) or {}).get("S_ss"),',
     '            "r3_S_ss": (verdict.get("runs", {}).get("r3f", {}) or {}).get("S_ss"),'),
    ('            "sim_wall_limit_min": 90,', '            "sim_wall_limit_min": 112,'),
    ('            "sim_wall_note": "sum of every vsim invocation in commands.jsonl, including two "\n'
     '                             "aborted v1 check-only attempts (258.3 s + 434.9 s) and the final "\n'
     '                             "91.0 s v1; 5206.3 s = 86.8 min",',
     '            "sim_wall_note": "sum of every vsim invocation in commands.jsonl; round0 5206.3 s "\n'
     '                             "(86.8 min) + round1 r3_frozen 1326.1 s (22.1 min) = 6532.4 s "\n'
     '                             "(108.9 min), within the round1 override <=112 min; full-frame 5/5",'),
    ('    (R0 / "manifest-r1.json").write_text(json.dumps(man, indent=2) + "\\n")',
     '    (R0 / "manifest-r2.json").write_text(json.dumps(man, indent=2) + "\\n")'),
])

# ------------------------------------------------------------------ run_g0.py
patch(R0 / "sim" / "run_g0.py", [
    ('    cols = list(rows[0].keys())',
     '    for row in rows:\n'
     '        if row["anchor"] == "A1_grad_measured" and row["view"] == "serial":\n'
     '            row["source"] = "R2 strict-serial (measured)"\n'
     '    cols = list(rows[0].keys())'),
    ('    verdict["proxy_vec_match"] = r3_vec',
     '    verdict["proxy_vec_match"] = r3_vec\n'
     '    legacy = db.get("r3") or {}\n'
     '    verdict["r3_vs_r0"] = {\n'
     '        "legacy_S_ss": legacy.get("S_ss"), "frozen_S_ss": r3.get("S_ss"),\n'
     '        "delta_cycles": (r3["S_ss"] - legacy["S_ss"]) if (legacy.get("S_ss") and r3.get("S_ss")) else None,\n'
     '        "note": "round1 r3_frozen vs round0 legacy-TB r3; same timing, frozen TB is the G0 binding",\n'
     '    }'),
])

# ------------------------------------------------------------------ check_outputs.py
patch(R0 / "sim" / "check_outputs.py", [
    ('man_path = R0 / "manifest-r1.json"', 'man_path = R0 / "manifest-r2.json"'),
    ('        and art.get("src/legacy/tb_ss_g0_89948303.v", {}).get("sha256") == LEGACY_TB\n'
     '        and "manifest-r0.json" in art, "frozen+legacy+manifest-r0 bound")',
     '        and art.get("src/legacy/tb_ss_g0_89948303.v", {}).get("sha256") == LEGACY_TB\n'
     '        and "manifest-r0.json" in art and "manifest-r1.json" in art,\n'
     '        "frozen+legacy+manifest-r0+r1 bound")'),
    ('    add("C22_full_frame_count", man.get("budget", {}).get("full_frame_vsim_runs") == 5,\n'
     '        "full_frame=%s" % man.get("budget", {}).get("full_frame_vsim_runs"))',
     '    add("C22_full_frame_count", man.get("budget", {}).get("full_frame_vsim_runs") == 5,\n'
     '        "full_frame=%s" % man.get("budget", {}).get("full_frame_vsim_runs"))\n'
     '    add("C23_manifest_r3_S_ss", man.get("verdict", {}).get("r3_S_ss") == 5928286.0\n'
     '        and man.get("verdict", {}).get("r3_S_ss") == verdict["runs"]["r3f"]["S_ss"],\n'
     '        "manifest=%s verdict=%s" % (man.get("verdict", {}).get("r3_S_ss"),\n'
     '                                    verdict["runs"]["r3f"]["S_ss"]))\n'
     '    add("C24_budget_override", man.get("budget", {}).get("sim_wall_limit_min") == 112\n'
     '        and abs(man.get("budget", {}).get("sim_wall_seconds") - 6532.4) < 0.1,\n'
     '        "limit=%s actual=%s" % (man.get("budget", {}).get("sim_wall_limit_min"),\n'
     '                                man.get("budget", {}).get("sim_wall_seconds")))\n'
     '    add("C25_r3_vs_r0", verdict.get("r3_vs_r0", {}).get("legacy_S_ss") == 5928286.0\n'
     '        and verdict.get("r3_vs_r0", {}).get("frozen_S_ss") == 5928286.0,\n'
     '        json.dumps(verdict.get("r3_vs_r0", {})))'),
])

# ------------------------------------------------------------------ DIFF.md
p = R0 / "src" / "DIFF.md"
lines = p.read_text(encoding="utf-8").splitlines()
out = []
hits = 0
for l in lines:
    if "p2_a1_board_top" in l:
        hits += 1
        if l.startswith("- 12 个 DUT"):
            out.append("- 12 个 DUT/模型源与 b11/P1 manifest 逐字节相同；**P3 未复制、未编译 `p2_a1_board_top.v`**"
                       "（板级 top 缺依赖；manifest/input-verified 只登记 12 源）。")
        else:
            out.append("- **F8（round2 修正）**：`sim/_repair.py` 是 round0 一次性编码修复脚本，已从 manifest 排除并在 notes 说明；"
                       "**P3 未复制、未编译 `p2_a1_board_top.v`**；round0 的“只复制/哈希”表述已删除，与实际 copied/hashed 清单一致。")
    else:
        out.append(l)
if hits != 2:
    raise SystemExit("DIFF p2_a1_board_top hits=%d" % hits)
p.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")
print("patched DIFF p2_a1_board_top lines")

# ------------------------------------------------------------------ g0-closure.md budget line
p = R0 / "g0-closure.md"
lines = p.read_text(encoding="utf-8").splitlines()
out = []
hits = 0
for l in lines:
    if "累计仿真墙钟" in l:
        hits += 1
        out.append("- 每 run 独占 work 库/INI/日志，硬超时 2700 s；R0/R1/R2/R3 实际 937.6/1056.1/1111.9/1316.5 s，"
                   "round1 `r3_frozen` 1326.1 s（22.1 min）；v1 91 s + 两次中止的 v1 试跑 258.3/434.9 s；"
                   "累计仿真墙钟 **6532.4 s = 108.9 min**，在 round1 override **≤112 min** 内（round0 86.8 min；全尺寸 5/5）。R4 因预算未跑。")
    else:
        out.append(l)
if hits != 1:
    raise SystemExit("g0-closure budget line hits=%d" % hits)
p.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")
print("patched g0-closure budget line")
