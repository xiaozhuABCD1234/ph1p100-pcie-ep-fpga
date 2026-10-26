"""r1 doc-refreeze finalisation (0 sim): R3/R4 text, R1 md, R7, R8.

Runs after patch_r1.py.  It
  1) removes the withdrawn r0 C1 numbers from coregap_model.py and regenerates
     out/coregap-model.json (reporting layer only; arithmetic re-derives identically),
  2) re-patches out/coregap-verdict.json (C1 statement, LOO wording, audit block),
  3) rewrites model/assumptions.json (R3: c_ab + label taxonomy + constructive zero),
  4) corrects src/DIFF-probe.md (R1: 54 lines / 3 hunks / +32-0 + SHA + tester copy note),
  5) corrects result-r0.md section 3 C1 bullet (R4, marked as an r1 correction),
  6) writes result-r1.md (R1-R8 + OBS-5 process deviation),
  7) writes manifest-r1.json (repair_round=1, previous_manifest=manifest-r0.json 97d7b195..,
     every artefact re-hashed, stopped_modifying=true, active_commands=0, 0 sim).

It never touches the probe TB, the DUT sources, the content, r/k/c_ab values, matrix numbers,
the 45.034% envelope, `conditional`, or the G0 headline.
"""

import hashlib
import importlib
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]      # .../r0
MODEL = ROOT / "model"
OUT = ROOT / "out"
PREV_MANIFEST_SHA = "97d7b1955b1df0bde45e9305d80a8aa703ea1365009d407f0d5d71d58dc6cc15"


def sha(p):
    h = hashlib.sha256()
    with p.open("rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def rep(text, old, new, tag):
    assert old in text, f"anchor missing: {tag}"
    return text.replace(old, new, 1)


# ---------------------------------------------------------------- 1. model text
mp = MODEL / "coregap_model.py"
s = mp.read_text(encoding="utf-8")
s = rep(s,
        '        "withdrawn": {"r0_values": "1,441,559..1,577,737 (33.7%)", "why": "computed with the "\n'
        '                      "non-physical k = -2418 cycles/block from the 2-parameter {N,L} fold, which "\n'
        '                      "the model itself rejects"},',
        '        "withdrawn": {"what": "the r0 C1 figure and its percentage are withdrawn",\n'
        '                      "why": "computed with the non-physical k from the 2-parameter {N,L} fold, "\n'
        '                      "which the model itself rejects; coefficient taxonomy in assumptions.json"},',
        "model withdrawn text")
mp.write_text(s, encoding="utf-8")
importlib.invalidate_caches()
sys.path.insert(0, str(MODEL))
import coregap_model  # noqa: E402
importlib.reload(coregap_model)
coregap_model.main()

m = json.loads((OUT / "coregap-model.json").read_text(encoding="utf-8"))
c1 = m["residuals"]["C1"]
blob = json.dumps(m, ensure_ascii=False)
for forbidden in ("1,441,559", "1,577,737", "33.7%", "6.63M", "6.2% short"):
    assert forbidden not in blob, f"forbidden string still present: {forbidden}"
cal = m["calibration"]["fit_N_L_comp_3param"]
assert abs(cal["r_replay_cycles_per_stream_byte"] - 1.9007) < 5e-4
assert abs(cal["k_block_cycles"] - 293.63) < 0.05
assert abs(cal["c_abort_credit_cycles_per_aborted_block"] - 1109.0) < 0.5
assert [r["cycles_per_frame_est"] for r in m["matrix"] if r["id"] == "A"][0] == 7223675
assert [r["cycles_per_frame_est"] for r in m["matrix"] if r["id"] == "H"][0] == 6260648
assert [c["cycles_per_frame_est"] for c in m["combinations"] if c["combo"] == "A+H"][0] == 6008078
assert m["scheme_envelope"]["envelope_uncertainty_pct"] == 45.0
assert m["verdict"]["closable_at_187_5"] == "conditional"
assert m["anchors"]["N"]["probe_vs_p1_pct"] == 0.0 and m["anchors"]["L"]["probe_vs_p1_pct"] == 0.0
assert c1["core_predicted_min_cycles_M0"] == 2905862 and c1["core_estimate_over_chain_pct"] == 63.19
print("[1] model regenerated, invariants OK, C1 =", c1["core_predicted_min_cycles_M0"],
      "..", c1["core_predicted_max_cycles_with_symbol_bound"], "est", c1["core_predicted_estimate_cycles"])

# ---------------------------------------------------------------- 2. verdict
vp = OUT / "coregap-verdict.json"
v = json.loads(vp.read_text(encoding="utf-8"))
v["repair_round"] = 1
v["r1_doc_refreeze"] = {
    "sim_runs": 0, "td": 0, "board": 0, "network": 0,
    "scope": "documentation / labels / references only; the model arithmetic, matrix numbers, "
             "45.034% envelope, closable_at_187_5 = conditional and the G0 headline are unchanged",
    "changes": [
        "R1 src/DIFF-probe.raw regenerated from the final probe TB (git diff --no-index --unified=2; "
        "54 lines, 3 hunks, +32/-0) and src/DIFF-probe.md corrected",
        "R2 coregap-model.json row H note -> 6,260,648 cycles / -0.17% (stale 6.63M / 6.2% removed)",
        "R3 model/assumptions.json: c_ab = 1,109 added, assumed(fitted) label taxonomy, in-sample = 0 declared constructive",
        "R4 C1 restated with the physical coefficients: 2,905,862..3,042,041, estimate 2,956,095 = 63.19% of the chain; "
        "the r0 figure and its non-physical-k basis are withdrawn",
        "R5 rows B/C: the -0.02*scan credit labelled assumed; matcher-unvalidated + <0.1% evidence kept",
        "R6 anchors.{N,L}.probe_vs_p1_pct now reference the P1 r1 frame-1 core_interval (0.000%); the 4-frame S_ss "
        "comparison is kept separately as probe_vs_p1_ss_pct",
        "R7 OBS-5 (dev calls ~49 > 40) registered as a process deviation in result-r1.md and manifest-r1 notes",
        "R8 manifest-r1.json (repair_round = 1, previous_manifest = manifest-r0.json 97d7b195..)",
    ],
    "tester_r0_obs": {
        "OBS-1": "closed by R1", "OBS-2": "closed by R2", "OBS-3": "closed by R3", "OBS-4": "closed by R4",
        "OBS-5": "registered (R7), not reworked", "OBS-6": "closed by R5", "OBS-7": "closed by R6",
    },
}
v["model"]["residuals"]["C1"] = (
    "not_applicable_core_level: with the physical fitted coefficients (r = 1.900712, k = 293.6313) the C1 "
    "core-level bound is 2,905,862 (M = 0) .. 3,042,041 (M <= stream/3), estimate 2,956,095 = 63.19% of the "
    "4,677,970-cycle chain interval, so the chain interval contains capture/feed/export work and cannot be a "
    "core anchor. The r0 statement computed with the non-physical k from the 2-parameter {N,L} fold is withdrawn.")
v["model"]["c1_physical_bounds"] = {
    "cycles_M0_floor": 2905862, "cycles_symbol_bound": 3042041, "cycles_estimate": 2956095,
    "pct_of_chain_interval": 63.19, "chain_interval_cycles": 4677970,
    "coefficients": {"r": 1.900712, "k": 293.6313},
    "label": "derived (physical coefficients); C1 stays excluded from the fit",
}
v["model"]["leave_one_out"]["fit_N_L_k0_predict_comp"]["note"] = (
    "the unconstrained 2-parameter {N,L} fold returns k = -2418 cycles/block, which is unphysical; it is "
    "quoted only to justify the third parameter (per-abort credit) and is NOT used for any C1 or matrix statement")
vp.write_text(json.dumps(v, indent=2, ensure_ascii=False), encoding="utf-8")
print("[2] verdict patched: repair_round=1, closable =", v["closable_at_187_5"], ", headline =", v["headline"])

# ---------------------------------------------------------------- 3. assumptions.json (R3)
assump = {
    "task": "T10.ss-g0-prod-coregap",
    "repair_round": 1,
    "model": "model/coregap_model.py",
    "parser": "model/parse_probe.py",
    "units": "cycles are clk_a1 cycles at 187.5 MHz (period 5.333 ns); MB = 1e6 B",
    "label_taxonomy": {
        "measured": "read from a frozen artefact (1-frame stage probe log, b6 comp bench, P1 r1 evt)",
        "derived": "computed from the b11 RTL structure or from arithmetic on measured values",
        "assumed": "a stated assumption that is not measured; the fitted sub-label below belongs here",
        "assumed(fitted)": "a coefficient obtained by solving the cycle-accounting system on measured anchors; "
                           "it is an ASSUMPTION about mechanism costs, never a measurement, and the frozen "
                           "measured/derived/assumed vocabulary has no separate 'fitted' class (r1 mapping "
                           "requested by OBS-3)",
        "not_applicable": "the quantity has no meaning for this task",
    },
    "constructive_zero_note": "N/L/comp in-sample residuals are 0 BY CONSTRUCTION (three anchors, three "
                              "unknowns); they are not validation. Validation is the leave-one-out block in "
                              "out/coregap-model.json (all three folds within 5%).",
    "frozen_boundaries": {
        "clock_MHz": 187.5, "cores": 1, "device": "PH1P100SBG484-3", "ERAM_limit": 300,
        "LUT6_limit": 71680, "G0_cycles_per_frame": 6250000,
        "G0_cycles_per_byte": 2.4112654320987654, "bytes_per_frame": 2592000,
        "block_bytes": 4800, "blocks_per_frame": 540,
        "source": "dev-plan section 2 + fpga-design-guide sections 1-5 + P1 r1b report",
    },
    "quantities": {
        "cycles_per_byte": {"definition": "frame-1 core_interval / 2,592,000 B",
                            "labels": {"N": "measured", "L": "measured", "comp": "measured",
                                       "C1": "measured but CHAIN level, not core level"}},
        "symbols_per_byte": {"definition": "(literals + matches) / 2,592,000 from the stage probe",
                             "labels": {"N": "measured", "L": "measured"}},
        "extension_share": {"definition": "(bytes - literals - 3*matches) / bytes",
                            "labels": {"N": "measured", "L": "measured"}},
        "per_symbol_overhead": {"definition": "5 cycles per match (match costs len+5 for len bytes); "
                                              "a literal costs 1 cycle = the 1 cycle/position baseline",
                                "labels": {"match": "derived", "literal": "derived"}},
    },
    "coefficients": [
        {"name": "c_scan_per_position", "value": 1.0, "unit": "cycles/position", "label": "derived",
         "evidence": "a1_deflate_core.v S_SCAN (1446-1509): one emitted symbol start per cycle"},
        {"name": "c_match_fixed", "value": 5.0, "unit": "cycles/match", "label": "derived",
         "evidence": "S_SCAN 1 + S_EXT (len-2) + S_MLEN 1 + S_MCHK 1 + S_REPOS 4 = len+5 per match (1511-1612)"},
        {"name": "c_stored_per_block_byte", "value": 1.0, "unit": "cycles/block byte", "label": "derived",
         "evidence": "S_SDATA_R (1727-1742) emits one bm byte per cycle"},
        {"name": "r_replay_per_stream_byte", "value": 1.9007, "unit": "cycles/stream byte", "label": "assumed(fitted)",
         "evidence": "S_REPLAY_R + S_REPLAY_RD + 2x S_REPLAY_E (1657-1689) = 4 cycles per 2 bytes; out_space "
                     "backpressure and the last-word tail pull the fitted value below 2.0",
         "fitted_from": "N probe counters + L probe counters + comp b6 anchor"},
        {"name": "k_block_overhead", "value": 293.63, "unit": "cycles/block", "label": "assumed(fitted)",
         "evidence": "S_WAIT/S_BHDR/S_PRE(4)/S_EOB/S_EODONE/S_DECIDE + stored header + TRAIL/TADLER + loader wait",
         "fitted_from": "N + L + comp"},
        {"name": "c_abort_credit", "value": 1109.0, "unit": "cycles per aborted block", "label": "assumed(fitted)",
         "evidence": "a block whose candidate aborts (cand_abort -> S_DECIDE -> stored) stops scanning early, so a "
                     "full scan (B + 5M) overstates it; the credit is not observable from the 9 counters",
         "why_it_exists": "with only (r,k) the two-content solve returns k = -2418 cycles/block (unphysical) because "
                          "the aborted-block count differs strongly by content (N 83 / L 210 / comp 0). Adding c_ab "
                          "makes all three coefficients positive; the r1 assumptions file labels it assumed(fitted)",
         "joint_solve_note": "the three coefficients are solved simultaneously from three equations: "
                             "N: 1,279,097 r + 540 k - 83 c_ab = 2,497,710; "
                             "L: 1,147,818 r + 540 k - 210 c_ab = 2,107,346; "
                             "comp: 50,310 r + 32 k = 105,021",
         "fitted_from": "N + L + comp"},
    ],
    "superseded": [
        {"name": "aborted_scan_credit = 0.0 (r0 file, label assumed, 'absorbed into k')",
         "why": "superseded by the explicit c_ab term (OBS-3); keeping it as 0 contradicted the model"}
    ],
    "measured_inputs": {
        "N_probe": "sim/logs/n-probe.log -> out/stage-probe.json (frame 1 of the P1 frozen raw40_n.hex)",
        "L_probe": "sim/logs/l-probe.log -> out/stage-probe.json (frame 1 of the P1 frozen raw40_l.hex)",
        "comp_anchor": "b6 r0 result-r0.md sections 2/7: 355,261 cycles, 153,600 B in, 50,310 B out, 19,328 matches",
        "P1_r1": "content-verdict-r1.json: S_ss N 7,475,240 / L 6,986,952; frame-1 core_interval N 7,476,245 / L 6,979,811",
        "b11_routed": "WNS +0.015 ns @187.5 MHz (single core, frozen input)",
        "C1_chain": "P4 R1 S_ss 4,677,970 cycles, payload 81,707 B/frame (CHAIN level, excluded from the fit)",
    },
    "assumptions": [
        {"id": "A1", "text": "the b11 FSM cycle costs above are content-independent, so one (r,k,c_ab) set transfers "
                             "between N, L and comp", "label": "assumed(fitted)", "risk": "medium",
         "test": "L and N are each held out of the fit and predicted; comp is predicted with k >= 0"},
        {"id": "A2", "text": "C1's P4 S_ss is a chain interval, not a core interval", "label": "derived",
         "risk": "medium", "test": "the physical-coefficient core bound is 2,905,862..3,042,041 = 63.19% of the "
                                   "chain, so the chain contains capture/feed/export work"},
        {"id": "A3", "text": "scheme matrix resource deltas are engineering estimates, not synthesis results",
         "label": "assumed", "risk": "high", "test": "prototype + TD (next evidence)"},
        {"id": "A4", "text": "the 224.3 MHz closure arithmetic assumes the current cycles/frame are unchanged",
         "label": "derived", "risk": "high", "test": "STA on a re-pipelined core"},
        {"id": "A5", "text": "rows B/C carry an assumed 2% scan credit (-0.02*scan) that is NOT a matcher result; "
                             "the matcher itself is not probe-validated", "label": "assumed", "risk": "high",
         "test": "not used for any closure claim; both rows stay 'no'"},
    ],
    "not_measured": [
        "any modified-core cycle count (no RTL change is allowed in this task)",
        "synthesis / place & route / STA for any scheme", "resource deltas for any scheme",
        "board, DDR sustained, production sink, dual stream",
    ],
}
(MODEL / "assumptions.json").write_text(json.dumps(assump, indent=2, ensure_ascii=False), encoding="utf-8")
print("[3] assumptions.json rewritten:", len(assump["coefficients"]), "coefficients")

# ---------------------------------------------------------------- 4. DIFF-probe.md (R1)
dp = ROOT / "src" / "DIFF-probe.md"
d = dp.read_text(encoding="utf-8")
d = rep(d,
        "- 生成：`git diff --no-index --unified=2 <P1 TB> <probe TB>` → `DIFF-probe.raw`（43 行，4 个 hunk）",
        "- 生成（**r1 重生成，R1**）：`git diff --no-index --unified=2 <P1 TB> <probe TB>` → `DIFF-probe.raw`\n"
        "  = **54 行 / 3 个 hunk / +32 −0**（SHA256 见 `manifest-r1.json`；TB 本体未改，SHA256 "
        "`d2aa6cc09b8c091a3581dee02f2d556c2384f67d1ee2ee2a705c250933f86c31`）。\n"
        "  r0 冻结的 43 行 `.raw` 是**旧版**（`CORE_STAGE` 当时仍在 `SS_STATS` 之后，即 N#1 的 harness 版本），"
        "已由本次重生成取代（OBS-1）。\n"
        "  说明：测试者独立副本 `test-reports/T10.ss-g0-prod-coregap/tester-real-diff.txt` 用的是 `--unified=3`，"
        "为 60 行 / 3 hunk；**hunk 内容与本文件逐行相同**，行数差异只来自 context 行数。",
        "DIFF-probe.md generation line")
d = rep(d, "| 4 | 同步块内、enc 分支之后 |", "| 4 | 同步块内、enc 分支之后（8 拍事件式 dump） |", "DIFF row 4")
dp.write_text(d, encoding="utf-8")
print("[4] DIFF-probe.md corrected")

# ---------------------------------------------------------------- 5. result-r0.md C1 bullet (R4)
rp = ROOT / "result-r0.md"
r = rp.read_text(encoding="utf-8")
old_bullet = ("- **C1 不进入拟合**：C1 的 4,677,970 是 P4 的**链级 `S_ss`**；模型给出的 C1 核级上界仅 1.44M–1.58M 拍（链级的 33.7%），")
assert old_bullet in r, "anchor missing: result-r0 C1 bullet"
r = r.replace(
    old_bullet,
    "- **C1 不进入拟合**（r1 修正，物理系数口径，见 `result-r1.md` R4）：C1 的 4,677,970 是 P4 的**链级 `S_ss`**；"
    "用拟合系数 r=1.900712、k=293.6313 得到的 C1 核级界为 **2,905,862～3,042,041 拍（估计 2,956,095 = 链级 63.19%）**，",
    1)
rp.write_text(r, encoding="utf-8")
print("[5] result-r0.md C1 bullet corrected (physical coefficients)")

# ---------------------------------------------------------------- 6. result-r1.md (R7)
diff_sha = sha(ROOT / "src" / "DIFF-probe.raw")
r1 = f"""# T10.ss-g0-prod-coregap r1 — 文档重冻（同一开发会话；0 sim）

- run `20261026-143924_fpga-1080p30-g0-production`；task `T10.ss-g0-prod-coregap`；round **r1（repair_round=1，文档级重冻）**
- 依据：P2 r0 综合报告（PASS，7 条非阻断 OBS）+ `p2-obs-ruling.md` §2 重冻清单
- **不改**：模型算术（r/k/c_ab）、8 行矩阵、A+H = 6,008,078 / 2.3179 c/B、包络 45.034%、`closable_at_187_5=conditional`、G0 headline
- **0 sim**：无探针重跑、无 vsim、无 TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK/网络、无批量删除

## 1. R1–R8 执行

| # | 对象 | 实际改动 | 结果 |
|---|---|---|---|
| R1 | `src/DIFF-probe.raw`、`src/DIFF-probe.md` | 用**最终** `tb_ss_4run_wd_probe.v`（SHA `d2aa6cc0…`，未改）重跑 `git diff --no-index --unified=2` → **54 行 / 3 hunk / +32 −0**，SHA256 `{diff_sha}`；`.md` 的行数/hunk/生成说明与白名单第 4 项（8 拍事件式 dump）已对齐；并注明测试者 `--unified=3` 副本为 60 行 / 3 hunk、hunk 内容逐行相同 | 关闭 OBS-1 |
| R2 | `out/coregap-model.json` 行 H `note` | 改为 “→ 6,260,648 cycles (2.4154 cycles/B), i.e. −0.17% against the 6,250,000 gate … still short”；全文件已无 “6.63M / 6.2%” | 关闭 OBS-2 |
| R3 | `model/assumptions.json` | 增列 `c_ab = 1109.0`（`assumed(fitted)`，附三点联立方程：N/L/comp 三式）；新增 `label_taxonomy` 把 `fitted` 映射为 `assumed(fitted)`（冻结词汇仍 measured/derived/assumed）；写明 **in-sample=0 是构造性、不是验证**；把 r0 的 `aborted_scan_credit=0.0` 列入 `superseded` | 关闭 OBS-3 |
| R4 | `out/coregap-model.json → residuals.C1`、`out/coregap-verdict.json`、`result-r0.md §3` | C1 改用**物理系数**：2,905,862（M=0）～3,042,041（M ≤ stream/3），估计 2,956,095 = **链级 63.19%**；删除 r0 的核级界与非物理 `k=−2418` 依据（该 k 只保留在 LOO 里用于解释第三参数存在，并注明**不用于 C1/矩阵**）；结论句保留 `not_applicable_core_level` | 关闭 OBS-4 |
| R5 | `out/coregap-model.json` 行 B/C | `delta_scan=-0.02×scan` 标注 `assumed`（**不是** matcher 结果）；保留 matcher 未探针验证、hbits 10→12/13 <0.1%、窗口 2048→4800 仅 0.54%(N)/0.20%(L) literals 的证据；B/C 仍为“否” | 关闭 OBS-6 |
| R6 | `out/coregap-model.json → anchors.{{N,L}}.probe_vs_p1_pct` | 参照物统一为 **P1 r1 帧 1 `core_interval`**（N 0.000% / L 0.000%）；4 帧稳态 `S_ss` 对照改列 `probe_vs_p1_ss_pct`（N 0.0134% / L −0.1022%）并注明口径不同、仅参考 | 关闭 OBS-7 |
| R7 | 本文件 + `manifest-r1.json` notes | 登记 **OBS-5 过程偏差**：r0 开发工具调用 ≈49 > 40，无仿真增量（全尺寸 1 帧仍 3/3、vsim 34.93 min）、无门禁影响、不追溯改判 | 已登记 |
| R8 | `manifest-r1.json` | `repair_round=1`、`previous_manifest=manifest-r0.json`（`{PREV_MANIFEST_SHA}`）、全 artifact 重哈希、`stopped_modifying=true`、`active_commands=0`、`evidence_rounds` 全 0 sim | 已冻结 |

## 2. 未变项（逐值复核）

| 项 | 值 |
|---|---|
| r / k / c_ab | 1.9007 / 293.63 / 1109.0 |
| 探针 | N 7,476,245、L 6,979,811（r0 实测，未重跑） |
| 矩阵 | A 7,223,675、B/C 7,384,642、D/E/F/G 7,476,245、H 6,260,648 |
| 组合 | A+H **6,008,078（2.3179 c/B，+4.03%）**、A+B+H 5,916,475、A_full+H 3,970,580（乐观上界） |
| 包络 | 7,223,675 / 3,970,580 → **45.0%** |
| 判定 | `closable_at_187_5 = conditional`；headline `G0_not_closed` |

## 3. 边界

本重冻**不新增任何证据**，不改变任何结论；不证明 G0 闭合，不做 TD/板卡。改造后核的实测周期、任何方案时序/资源、生产 sink/DDR/板级/双路/传感器 RAW 仍未测。

## 4. 复现（0 sim）

```powershell
python model/patch_r1.py              # r0 -> r1 报告层补丁（锚点缺失会 assert 失败）
python model/finalize_r1.py           # 重生成 coregap-model.json + 校验不变量 + 重写 verdict/assumptions/DIFF/本文件 + manifest-r1
```

## 5. 预算

| 项 | 上限 | 实际 |
|---|---|---|
| 工具调用（r1） | 15 | 见主会话记账（≤15） |
| 墙钟 | 30 min | ≤30 min |
| 仿真 / TD / 板卡 / 网络 | 0 / 0 / 0 / 0 | **0 / 0 / 0 / 0** |
| 探针（P2 累计） | ≤3 | 3（r0，未新增） |
"""
(ROOT / "result-r1.md").write_text(r1, encoding="utf-8")
print("[6] result-r1.md written")

# ---------------------------------------------------------------- 7. manifest-r1 (R8)
files = []
for p in sorted(ROOT.rglob("*")):
    if p.is_dir() or p.name in ("manifest-r0.json", "manifest-r1.json"):
        continue
    files.append({"path": p.relative_to(ROOT).as_posix(), "sha256": sha(p), "bytes": p.stat().st_size})
inputs = []
for rel in ("content/raw40_n.hex", "content/raw40_l.hex", "content/raw_n.bin", "content/raw_l.bin",
            "src/a1_deflate_core.v", "src/a1_frame_top.v", "src/tb_ss_4run_wd.v", "manifest-r1.json"):
    p = ROOT.parents[1] / "T10.ss-g0-prod-content" / "r0" / rel
    if p.exists():
        inputs.append({"path": f"T10.ss-g0-prod-content/r0/{rel}", "sha256": sha(p), "bytes": p.stat().st_size})
prev = ROOT / "manifest-r0.json"
man = {
    "task": "T10.ss-g0-prod-coregap",
    "run": ROOT.parents[1].name,
    "round": 1,
    "repair_round": 1,
    "previous_manifest": {"path": "manifest-r0.json", "sha256": PREV_MANIFEST_SHA,
                          "recorded_sha256_matches": sha(prev) == PREV_MANIFEST_SHA},
    "role": "fpga-dev",
    "created": time.strftime("%Y-%m-%dT%H:%M:%S"),
    "write_scope": [f"workflow/runs/{ROOT.parents[1].name}/T10.ss-g0-prod-coregap/**",
                    "%TEMP%/opencode/ss-g0-prod-coregap/**"],
    "stopped_modifying": True,
    "active_commands": 0,
    "verdict": {"closable_at_187_5": "conditional", "headline": "G0_not_closed"},
    "evidence_rounds": {"stage_probe_frames": 0, "vsim_full_size_runs": 0, "vsim_seconds": 0.0,
                        "td": 0, "board": 0, "network": 0,
                        "note": "r1 is a 0-sim documentation refreeze; the 3 x 1-frame probes (695.4 + 612.0 + 788.4 s "
                                "= 2,095.8 s) belong to r0 and are quoted, not re-run"},
    "notes": {
        "OBS-5_process_deviation": "r0 used ~49 developer tool calls against a 40-call budget; no extra simulation "
                                   "(3/3 full-size 1-frame probes, 34.93 min), no gate input or conclusion changed; "
                                   "registered here and in result-r1.md, no rework and no retroactive verdict change",
        "r1_scope": "documentation / labels / references only: model arithmetic, matrix, 45.034% envelope, "
                    "closable_at_187_5 = conditional and the G0 headline are unchanged",
        "diff_probe_sha256": diff_sha,
        "tester_r0_report_artifact_count_note": "the r0 tester report section 0 wrote P1 manifest-r1 as 40 artifacts; "
                                                "the correct value is 70 artifacts (report typo, to be corrected in the "
                                                "tester r1 report, P1 manifest untouched)",
    },
    "readonly_inputs": inputs,
    "commands": json.loads((ROOT / "sim" / "commands.jsonl").read_text(encoding="utf-8").splitlines()[0]) and [],
    "commands_note": "r0 sim/commands.jsonl is unchanged and still holds the 4 r0 commands; r1 added 0 commands",
    "artifacts": files,
}
man["commands"] = [json.loads(l) for l in (ROOT / "sim" / "commands.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
(ROOT / "manifest-r1.json").write_text(json.dumps(man, indent=2, ensure_ascii=False), encoding="utf-8")
mjson = ROOT / "manifest-r1.json"
print("[7] manifest-r1.json:", len(files), "artifacts,", len(inputs), "inputs,",
      len(man["commands"]), "r0 commands, previous_manifest_match =", man["previous_manifest"]["recorded_sha256_matches"])
print("    manifest-r1 sha256 =", sha(mjson))
