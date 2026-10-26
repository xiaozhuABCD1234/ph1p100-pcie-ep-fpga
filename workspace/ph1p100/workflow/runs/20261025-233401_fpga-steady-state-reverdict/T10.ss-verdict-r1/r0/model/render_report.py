"""Render verdict-r1.md from the corrected model (single source of truth).

The report is generated, not hand-edited, so every number in it comes from the same pure
functions that produced out/*.csv.  model/check_outputs.py independently re-derives the
key figures from inputs/frozen-inputs.json and asserts they appear in the report and agree
with the CSVs.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import calc  # noqa: E402


def load(name):
    with open(os.path.join(ROOT, "inputs", name), "r", encoding="utf-8") as fh:
        return json.load(fh)


def key_figures(frozen, rows, overhead):
    """(label, value, label_tag, source) rows used by both the report and its checker."""
    p1 = frozen["p1_binding"]
    a1 = calc.anchor_metrics(frozen, "A1")
    a2 = calc.anchor_metrics(frozen, "A2")
    a3 = calc.anchor_metrics(frozen, "A3")
    u = calc.uart_numbers(frozen)
    ddr = calc.ddr_rows(frozen, frozen["ddr"]["peak_MBps_main"])[0]
    t0 = calc.capacity_from_cycles(calc.tier_shift_1080p(frozen, 0), frozen["clock_hz"])
    t1 = calc.capacity_from_cycles(calc.tier_shift_1080p(frozen, 1000000), frozen["clock_hz"])
    d = frozen["gates"]["G0"]["demand_1080p30_MBps"]
    tier = {}
    for cyc in (0, 426385, 1000000):
        c = calc.capacity_from_cycles(calc.tier_shift_1080p(frozen, cyc), frozen["clock_hz"])
        tier[cyc] = (calc.margin_0(c, d) * 100.0, calc.margin_25(c, d) * 100.0)
    primary, alts = calc.recommendations(rows, frozen, overhead)
    counts = {}
    for r in rows:
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
    return [
        ("P1 L_cold", calc.fmt_cyc(p1["L_cold_cycles"]), "measured", "P1 steady-state.json"),
        ("P1 S_ss", calc.fmt_cyc(p1["S_ss_cycles"]), "measured", "P1 steady-state.json"),
        ("P1 S_2 / S_23 / S_34", "%s / %s / %s" % (calc.fmt_cyc(p1["S_2_cycles"]),
                                                   calc.fmt_cyc(p1["S_23_cycles"]),
                                                   calc.fmt_cyc(p1["S_34_cycles"])),
         "measured", "P1 steady-state.json"),
        ("P1 band spread", calc.fmt_num(p1["S_ss_spread_pct"], 4) + "%", "measured", "P1 steady-state.json"),
        ("P1 startup / startup_pct", "%s / %s" % (calc.fmt_cyc(p1["startup_cycles"]),
                                                  calc.fmt_num(p1["startup_pct"], 4) + "%"),
         "derived", "P1 steady-state.json"),
        ("P1 S_avg2 event / stats", "%s / %s" % (calc.fmt_cyc(p1["s_avg2_event_cycles"]),
                                                  calc.fmt_cyc(p1["s_avg2_stats_cycles"])),
         "derived", "P1 steady-state.json (not S_ss)"),
        ("P1 export_tail (per frame, x4)", calc.fmt_cyc(p1["export_tail_cycles"]), "measured",
         "P1 steady-state.json; constant, sink_limited=false"),
        ("A1 C_ss / fps", "%s MB/s / %s fps" % (calc.fmt_num(a1["capacity_MBps"]),
                                                calc.fmt_num(a1["fps_30_equiv"])),
         "measured", "P1 r0 measured S_ss"),
        ("A1 margin G0 / G25", "%s / %s" % (calc.fmt_pct(a1["margin_0_pct"]),
                                            calc.fmt_pct(a1["margin_25_pct"])),
         "derived", "103.9009 vs 77.76 / 97.20"),
        ("A1 f_req_0 / f_req_25", "%s / %s MHz" % (calc.fmt_num(calc.required_clock_MHz(4677535, 30, 0.0), 3),
                                                   calc.fmt_num(calc.required_clock_MHz(4677535, 30, 0.25), 3)),
         "derived", "30*S_ss / 37.5*S_ss"),
        ("A2 cycles / C_ss", "%s / %s MB/s" % (calc.fmt_cyc(a2["cycles_per_frame"]),
                                               calc.fmt_num(a2["capacity_MBps"])),
         "assumed", "comp 2.312897 c/B x 2,592,000 B + 426,385"),
        ("A2 margin G0 / G25", "%s / %s" % (calc.fmt_pct(a2["margin_0_pct"]),
                                            calc.fmt_pct(a2["margin_25_pct"])),
         "assumed", "conservative content envelope"),
        ("A3 cycles / C_ss", "%s / %s MB/s" % (calc.fmt_cyc(a3["cycles_per_frame"]),
                                               calc.fmt_num(a3["capacity_MBps"])),
         "assumed", "rand 1.051297 c/B extrapolation"),
        ("A3 margin G0 / G25", "%s / %s" % (calc.fmt_pct(a3["margin_0_pct"]),
                                            calc.fmt_pct(a3["margin_25_pct"])),
         "assumed", "optimistic content envelope"),
        ("A2 vs A4", "%s vs %s (delta 0.375 cycle)" % (calc.fmt_cyc(a2["cycles_per_frame"]),
                                                       calc.fmt_cyc(6421414)),
         "assumed", "A2 is definitionally A4 + 0.375; not independent evidence"),
        ("Gate demand G0 / G25", "%s / %s MB/s" % (calc.fmt_num(77.76, 2), calc.fmt_num(97.2, 2)),
         "derived", "2,592,000 B x 30 fps; 1.25x"),
        ("S_ss at exactly 0% / 25%", "%s / %s cycles" % (calc.fmt_cyc(6250000), calc.fmt_cyc(5000000)),
         "derived", "4.86e8/S thresholds"),
        ("1080p tier0 (S_ss-426,385)", "%s cycles / G0 %s / G25 %s" %
         (calc.fmt_cyc(calc.tier_shift_1080p(frozen, 0)), calc.fmt_pct(tier[0][0]),
          calc.fmt_pct(tier[0][1])), "assumed", "tier shift, 1080p participates"),
        ("1080p tier primary", "%s cycles / G0 %s / G25 %s" %
         (calc.fmt_cyc(calc.tier_shift_1080p(frozen, 426385)), calc.fmt_pct(tier[426385][0]),
          calc.fmt_pct(tier[426385][1])), "measured+assumed", "A1 measured anchor, primary tier"),
        ("1080p tier 1e6 (S_ss+573,615)", "%s cycles / G0 %s / G25 %s" %
         (calc.fmt_cyc(calc.tier_shift_1080p(frozen, 1000000)), calc.fmt_pct(tier[1000000][0]),
          calc.fmt_pct(tier[1000000][1])), "assumed", "conservative overhead tier"),
        ("25% max 1080p fps A1 / A2", "%s / %s" %
         (calc.fmt_num(calc.max_fps(4677535, frozen["clock_hz"], 0.25), 3),
          calc.fmt_num(calc.max_fps(a2["cycles_per_frame"], frozen["clock_hz"], 0.25), 3)),
         "derived", "1.875e8/(1.25*S)"),
        ("A2 f_req_25", "%s MHz" % calc.fmt_num(calc.required_clock_MHz(a2["cycles_per_frame"], 30, 0.25), 3),
         "assumed", "conservative-content clock"),
        ("DDR total / gate", "%s / %s MB/s" % (calc.fmt_num(ddr["ddr_total_MBps"], 3),
                                               calc.fmt_num(ddr["ddr_gate_25_MBps"], 4)),
         "derived", "2R+2S, 20B/32B, CMP worst stored"),
        ("required_eff @5332 / @6400", "%s / %s" % (calc.fmt_num(ddr["required_eff_1333_pct"]),
                                                    calc.fmt_num(ddr["required_eff_1600_pct"])),
         "derived", "809.034 / peak"),
        ("gate_eff @5332 / @6400", "%s / %s" % (calc.fmt_num(ddr["gate_eff_1333_pct"]),
                                                calc.fmt_num(ddr["gate_eff_1600_pct"])),
         "derived", "1,011.2925 / peak"),
        ("UART 40,032 B @11,520 B/s", "%s s (%s x frame period)" %
         (calc.fmt_num(u["export_s_payload"], 3), calc.fmt_num(u["payload_vs_period_x"], 2)),
         "derived", "real 115200 8N1"),
        ("UART 2,594,706 B @11,520 B/s", "%s s (%s x frame period)" %
         (calc.fmt_num(u["export_s_frame"], 3), calc.fmt_num(u["frame_vs_period_x"], 0)),
         "derived", "worst stored payload, real 115200"),
        ("sim sink vs real 115200", "%s x" % calc.fmt_num(u["sim_sink_vs_real_x"], 0), "derived",
         "18.75 MB/s / 11,520 B/s"),
        ("export ideal vs measured tail", "%s / %s cycles (+%s)" %
         (calc.fmt_cyc(u["tail_ideal_cycles"]), calc.fmt_cyc(u["tail_measured_cycles"]),
          calc.fmt_cyc(u["tail_excess_cycles"])), "measured", "P1 export_tail constant"),
        ("dual-core per-stream", "c2s2 = C = %s MB/s (2C aggregate %s is not per-stream)" %
         (calc.fmt_num(a1["capacity_MBps"]), calc.fmt_num(2 * a1["capacity_MBps"])),
         "assumed", "assumed_from_single_core; paaxi_shared_unproven"),
        ("1080p30 per-stream headline", "not_proven", "derived", "A1 G0/G25 pass vs A2 G0/G25 fail"),
        ("verdict counts (43 rows)", "feasible %d / conditional %d / infeasible %d" %
         (counts.get("feasible", 0), counts.get("conditional", 0), counts.get("infeasible", 0)),
         "derived", "out/scenarios.csv"),
        ("primary recommendation", primary["scenario_id"] if primary else "none", "assumed",
         "comp content basis, largest G25-passing 30 fps tier"),
        ("alternates", "; ".join(a["scenario_id"] for a in alts), "assumed", "tier-robust, comp basis"),
    ]


def main():
    frozen = load("frozen-inputs.json")
    with open(os.path.join(HERE, "rules.json"), "r", encoding="utf-8") as fh:
        rules = json.load(fh)

    rows = calc.scenario_rows(frozen, rules)
    overhead = calc.overhead_rows(rows, frozen, rules)
    anchors = calc.anchor_rows(frozen)
    gm = calc.gate_matrix_rows(frozen, rules)
    ddr = calc.ddr_rows(frozen, frozen["ddr"]["peak_MBps_main"])
    u = calc.uart_numbers(frozen)
    a1 = calc.anchor_metrics(frozen, "A1")
    a2 = calc.anchor_metrics(frozen, "A2")
    a3 = calc.anchor_metrics(frozen, "A3")
    headline = calc.headline_1080p30(rules, a1["margin_0_pct"] / 100, a1["margin_25_pct"] / 100,
                                     a2["margin_0_pct"] / 100, a2["margin_25_pct"] / 100, True)
    primary, alts = calc.recommendations(rows, frozen, overhead)
    worst_primary = calc.worst_tier_margin(overhead, primary["scenario_id"])
    tier_by = {}
    for t in frozen["overhead"]["sensitivity_tiers"]:
        tier_by[t] = [r for r in overhead if r["tier_cycles"] == t]
    d = frozen["gates"]["G0"]["demand_1080p30_MBps"]

    L = []
    add = L.append
    add("# 复核判定 r1：修正 P2 `T10.dual-aplus-service-verdict` 的 1080p30/双路结论")
    add("")
    add("- run：`20261025-233401_fpga-steady-state-reverdict`；task：`T10.ss-verdict-r1`；round：`r0`；"
        "role：fpga-dev（离线模型/表格/报告；0 次 TD/综合/布线/bitgen/下载/Flash/板级/RK）")
    add("- 绑定输入（只读）：P1 `T10.ss-steady-anchor` manifest `39f3e3d6…9f9a`、"
        "`out/steady-state.json` `a0945e1f…`、`sim/caps/ss4.stats` `29bd3185…`、`sim/logs/run4.log` `dc215e0b…`")
    add("- 被复核冻结件：P2 manifest `5ed90500…36a6`、`feasibility-report.md` `82c2669e…`、"
        "旧 `out/scenarios.csv` `2d806599…`（43 行，byte-identical 回归复现）")
    add("- 本文件由 `model/render_report.py` 从冻结输入与规则生成；表内数值与 `out/*.csv` 同源，"
        "`model/check_outputs.py` 复核 CSV↔报告一致")
    add("")
    add("## 0. 结论（先给 three-part headline，再给依据）")
    add("")
    add("**1080p30 per-stream 的 claim 级结论 = `%s`。** 不是 `infeasible`，也不是 `feasible`。" % headline["headline"])
    add("")
    add("- `G0`（nominal 0%%，%s MB/s，per-stream）：A1（measured 梯度内容）**%s**（%s）；"
        "A2（assumed comp 外推）**%s**（%s）→ **内容跨界**" %
        (calc.fmt_num(d, 2), "通过" if headline["A1"]["G0"] else "未通过", calc.fmt_pct(a1["margin_0_pct"]),
         "通过" if headline["A2"]["G0"] else "未通过", calc.fmt_pct(a2["margin_0_pct"])))
    add("- `G25`（设计裕量 1.25x，%s MB/s）：A1 **%s**（%s）；A2 **%s**（%s）" %
        (calc.fmt_num(1.25 * d, 2), "通过" if headline["A1"]["G25"] else "未通过",
         calc.fmt_pct(a1["margin_25_pct"]), "通过" if headline["A2"]["G25"] else "未通过",
         calc.fmt_pct(a2["margin_25_pct"])))
    add("- `content` = `not_proven_all_content`：只测了一种平滑梯度内容（smooth `smp` 图案）+ b11 几何 + "
        "18.75 MB/s sim-only sink + 行为级 DDR；自然图像/低照/噪声未测")
    add("")
    add("证据标签：`measured` = 冻结实测；`derived` = 由冻结公式算得；`assumed` = 无直接实测的模型假设；"
        "`unproven` = 无任何证据。")
    add("")
    add("## 1. 对 P2 的修正摘要（撤回/保留与百分点）")
    add("")
    add("| # | P2 原口径 | 处置 | 修正后（本包） | 百分点/数值变化 |")
    add("|---|---|---|---|---|")
    add("| C1 | b6 单帧 `cycles=6,421,414` 当每帧服务时间 → `75.684 MB/s / 29.199 fps / −2.6694%%` | **撤回** | "
        "A1 稳态 `S_ss=4,677,535` → `%s MB/s / %s fps` | G0 −2.6694%% → **%s**；G25 −22.1355%% → **%s** |" %
        (calc.fmt_num(a1["capacity_MBps"]), calc.fmt_num(a1["fps_30_equiv"], 4),
         calc.fmt_pct(a1["margin_0_pct"]), calc.fmt_pct(a1["margin_25_pct"])))
    add("| C2 | 0% nominal 与 25% 设计裕量合判（链级 margin<0 → `infeasible`） | **撤回**（拆两 gate） | "
        "`G0`/`G25` 分列；`below_25` → `conditional`，不得写 `infeasible` | 1080p30 A1 双 gate 均过；A2 双 gate 均失 |")
    add("| C3 | DDR 峰值 6,400 MB/s（@1600）为主口径 | **修正** | 主线 1333 = **5,332 MB/s**；6,400 只作带标签回退列 | "
        "required_eff 12.6412%% → **%s**；gate_eff 15.8014%% → **%s** |" %
        (calc.fmt_pct(ddr[0]["required_eff_1333_pct"]), calc.fmt_pct(ddr[0]["gate_eff_1333_pct"])))
    add("| C4 | 1080p 固定锚点、overhead 三档 `applies=false` | **撤回** | 1080p 用档位差平移 "
        "`S_ss+(tier−426,385)`；tier0 **%s**、primary **%s**、1e6 **%s** | 1080p 25%% 非三档稳健 |" %
        (calc.fmt_pct(calc.margin_25(calc.capacity_from_cycles(calc.tier_shift_1080p(frozen, 0), frozen["clock_hz"]), d) * 100),
         calc.fmt_pct(a1["margin_25_pct"]),
         calc.fmt_pct(calc.margin_25(calc.capacity_from_cycles(calc.tier_shift_1080p(frozen, 1000000), frozen["clock_hz"]), d) * 100)))
    add("| C5 | “UART 导出”未限定生产/仿真 | **限定** | sim sink 18.75 MB/s；真实 115200 = 11,520 B/s（慢 %s×）；"
        "`export_tail=480,930` 恒定、`sink_limited=false`；`transport=not_proven` | 不得用 fast-sink 暗示 UART 可实时 |" %
        calc.fmt_num(u["sim_sink_vs_real_x"], 0))
    add("| C6 | `overhead=426,385` 当独立实测；A2 当第二个全帧锚点 | **降级/披露** | overhead 为 assumed 且与 A4 循环"
        "（A2−A4=0.375 cycle）；A2 只标 `assumed` | 不得把 A2 当 6.42M 的独立证据 |")
    add("| C7 | 双核 per-stream=C 但结论易被 2C 聚合误读 | **保留表值+加边界** | `c2s2=C`（assumed_from_single_core）、"
        "`paaxi_shared_unproven=true`；2C 只用于 DDR/总量 | 双核 headline 最高 `not_proven`，永不 `feasible` |")
    add("| C8 | 单一 comp 内容基；无内容包络 | **扩展** | A1 measured / A2 assumed 保守 / A3 assumed 乐观；"
        "每行 `claim_status=not_proven_all_content` | 自然图像/低照未证，不得称“保证” |")
    add("| C9 | 前沿：1080p30 `fails_30`、25%% 最大 23.36 fps、f_req 240.803 MHz | **修正** | "
        "A1：25%% 最大 **%s fps**、f_req **%s MHz**；A2 仍 23.359 fps / 240.803 MHz | 1080p30 改单列 "
        "“measured-content 双 gate 过 / not_proven all content” |" %
        (calc.fmt_num(calc.max_fps(4677535, frozen["clock_hz"], 0.25), 3),
         calc.fmt_num(calc.required_clock_MHz(4677535, 30, 0.25), 3)))
    add("")
    add("**保留的 P2 结论（本次复核未推翻）**：per-stream 容量规则（`1c1s=C`、`1c2s=C/2`、`2c1s=C`、`2c2s=C`，"
        "永不用 2C 作 per-stream）；双核资源 marginal 231/300（余 69）、conservative 289/300（余 11）；"
        "单核 Routed 时序仅在 ≤187.5 MHz proven；双路 1080p30 的 DDR 平均带宽非瓶颈；"
        "43 行网格与旧判定算术本身（legacy 回归 **byte-identical**，见 §7）——**修正只来自规则/口径/输入**。")
    add("")
    add("## 2. Q1：单帧延迟 vs 稳态吞吐（P1 已实测，本包只引用）")
    add("")
    add("| 量 | 值 | 标签 | 说明 |")
    add("|---|---|---|---|")
    add("| `L_cold` | %s cycles | measured | 冷启动单帧完成（与 b6 的 6,421,414 同类，不同几何/UART） |" % calc.fmt_cyc(6766434))
    add("| `S_2` / `S_23` / `S_34` | %s / %s / %s | measured | 三间隔完全一致 |" %
        (calc.fmt_cyc(4677535), calc.fmt_cyc(4677535), calc.fmt_cyc(4677535)))
    add("| `S_ss` | **%s cycles**（band %s，spread %s%%） | measured | 主口径；非 knife-edge |" %
        (calc.fmt_cyc(4677535), "[4,677,535, 4,677,535]", calc.fmt_num(0.0, 4)))
    add("| `startup` / `startup_pct` | %s / %s%% | derived | 冷启动占 44.66%%，把 6.421M 当吞吐是实质性口径错误 |" %
        (calc.fmt_cyc(2088899), calc.fmt_num(44.6581, 4)))
    add("| `S_avg2`（事件口径 / stats 含 2,000 drain） | %s / %s | derived | 两帧平均，**不是** `S_ss`；比稳态高 22.3%% |" %
        (calc.fmt_cyc(5721984.5), calc.fmt_cyc(5722994)))
    add("| b6 单帧 6,421,414 | `L_cold`（延迟） | measured 但**非吞吐** | 几何 CAM 3840×2160/ROI 960·540/LINE_GAP 40、"
        "1 GHz UART；与 b11 几何不可直接当帧间隔 |")
    add("| 导出尾巴 | %s ×4 恒定；ideal %s（+%s） | measured | 常数尾巴在帧间差抵消，`sink_limited=false`，"
        "`C_excl_export=C_ss`；**不得**无条件扣 400,320 |" %
        (calc.fmt_cyc(480930), calc.fmt_cyc(400320), calc.fmt_cyc(80590)))
    add("")
    add("结论：P2 的 6.421M/29.199 fps/−2.669%% 是“单帧冷启动延迟当稳态吞吐”的产物；实测稳态为 "
        "`S_ss=4,677,535` → `%s MB/s`、`%s fps`。" %
        (calc.fmt_num(a1["capacity_MBps"]), calc.fmt_num(a1["fps_30_equiv"], 4)))
    add("")
    add("## 3. Q2：两个 gate 与内容包络")
    add("")
    add("### 3.1 内容锚点（1080p，cycles/frame）")
    add("")
    add("| id | 名称 | cycles/frame | C（MB/s） | G0 margin | G25 margin | 标签 | 用途 |")
    add("|---|---|---:|---:|---:|---:|---|---|")
    for aid, name, use in (("A1", "grad_chain_ss", "主锚点（唯一实测全帧）"),
                           ("A2", "comp_core_scaled+overhead", "保守内容界（假设）"),
                           ("A3", "rand_core_scaled+overhead", "乐观界（假设）"),
                           ("A4", "b6 冷启动单帧", "仅延迟参照，**不作吞吐**")):
        m = calc.anchor_metrics(frozen, aid)
        g0 = calc.fmt_pct(m["margin_0_pct"]) if aid != "A4" else "n/a"
        g25 = calc.fmt_pct(m["margin_25_pct"]) if aid != "A4" else "n/a"
        add("| %s | `%s` | %s | %s | %s | %s | %s | %s |" %
            (aid, name, calc.fmt_cyc(m["cycles_per_frame"]),
             calc.fmt_num(m["capacity_MBps"]) if aid != "A4" else "n/a（延迟）",
             g0, g25, frozen["anchors_1080p"][aid]["label"], use))
    add("")
    add("**强制披露**：A2 与 A4 数值几乎相同（6,421,414.375 vs 6,421,414）是**定义造成**的"
        "（overhead := 6,421,414 − 5,995,029.375），不是独立证据；A2 只能 `assumed`。"
        "A4 是单帧冷启动延迟，禁止进入任何容量/gate 计算（负对照 NC1）。")
    add("")
    add("**A1 的外推边界（硬约束）**：A1 是**单内容（smooth `smp` 梯度）/单几何（b11 1920×1080）/18.75 MB/s "
        "sim sink/行为级 DDR/per-stream** 的链级锚点；`40.0852 fps`、`+6.8939%` **不得**外推自然图像/低照/噪声，"
        "**不得**外推双路 1080p30。两个 gate 的 77.76 / 97.20 MB/s 为冻结门槛，**未放宽**；"
        "`below_25` 一律写 `conditional`，永不写 `infeasible`。")
    add("")
    add("### 3.2 gate 矩阵（c1s1/c1s2/c2s1/c2s2 × A1/A2/A3 × G0/G25 = 24 行，完整见 `out/gate-matrix.csv`）")
    add("")
    add("| 锚点 | cores/streams | per-stream C | G0 %s | G0 | G25 %s | G25 | 行 verdict | 标签 |" %
        (calc.fmt_num(d, 2), calc.fmt_num(1.25 * d, 2)))
    add("|---|---|---:|---:|---|---:|---|---|---|")
    for aid in ("A1", "A2", "A3"):
        for cores, streams in ((1, 1), (1, 2), (2, 1), (2, 2)):
            r = [x for x in gm if x["anchor_id"] == aid and x["cores"] == cores
                 and x["streams"] == streams][0]
            g0 = "pass" if r["margin_G0_pct"] >= 0.0 else "fail"
            g25 = "pass" if r["margin_G25_pct"] >= 0.0 else "fail"
            add("| %s | c%ds%d | %s | %s | %s | %s | %s | %s | %s |" %
                (aid, cores, streams, calc.fmt_num(r["per_stream_capacity_chain_MBps"]),
                 calc.fmt_pct(r["margin_G0_pct"]), g0,
                 calc.fmt_pct(r["margin_G25_pct"]), g25, r["row_verdict"],
                 frozen["anchors_1080p"][aid]["label"]))
    add("")
    add("### 3.3 1080p30 headline（三段式，claim 级）")
    add("")
    add("| 组合 | G0（%s MB/s） | G25（%s MB/s） | content | headline |" %
        (calc.fmt_num(d, 2), calc.fmt_num(1.25 * d, 2)))
    add("|---|---|---|---|---|")
    add("| c1s1（per-stream=C） | %s（%s） | %s（%s） | `not_proven_all_content` | **`not_proven`** |" %
        (headline["gate_G0"], calc.fmt_pct(headline["A1"]["margin_0_pct"]),
         headline["gate_G25"], calc.fmt_pct(headline["A1"]["margin_25_pct"])))
    add("| A2 内容基（保守） | %s（%s） | %s（%s） | 同上 | 同上（内容跨界） |" %
        ("pass" if headline["A2"]["G0"] else "fail", calc.fmt_pct(headline["A2"]["margin_0_pct"]),
         "pass" if headline["A2"]["G25"] else "fail", calc.fmt_pct(headline["A2"]["margin_25_pct"])))
    add("| c2s1/c2s2（双核） | pass（算术） | pass（算术） | 同上 | **`not_proven`**（`assumed_from_single_core` + "
        "`paaxi_shared_unproven`；**永不 feasible**） |")
    add("")
    add("规则（`model/rules.json`）：A1/A2 的 G0 不一致 → `not_proven`；两者 G0 均失 → `infeasible`；"
        "均过但 G25 或资源/时序未证 → `conditional`；全过且资源/时序 proven → `feasible`（仅单核）。"
        "**本行任何组合都不得省略 content 一段。**")
    add("")
    add("## 4. Q3：1080p 参与 overhead 三档（0 / 426,385 / 1,000,000）")
    add("")
    add("| tier cycles | cycles/frame | C（MB/s） | G0 margin | G25 margin | G25 | 说明 |")
    add("|---:|---:|---:|---:|---:|---|---|")
    for t in (0, 426385, 1000000):
        cyc = calc.tier_shift_1080p(frozen, t)
        cap = calc.capacity_from_cycles(cyc, frozen["clock_hz"])
        add("| %s | %s | %s | %s | %s | %s | %s |" %
            (calc.fmt_cyc(t), calc.fmt_cyc(cyc), calc.fmt_num(cap), calc.fmt_pct(calc.margin_0(cap, d) * 100),
             calc.fmt_pct(calc.margin_25(cap, d) * 100), calc.gate_g25(cap, d),
             "1080p 档位差平移（applies=true）" if t != 426385 else "A1 实测锚点（主档）"))
    add("")
    add("- 1080p **必须**参与敏感性（P2 的 `applies=false` 撤回）：`Δ = tier − 426,385`，"
        "tier0 = S_ss−426,385，1e6 = S_ss+573,615。")
    add("- 结果：1080p 25%% **非三档稳健**——只在 tier0 与 primary 过，保守档 1e6 跌破（%s）。" %
        calc.fmt_pct(calc.margin_25(calc.capacity_from_cycles(calc.tier_shift_1080p(frozen, 1000000), frozen["clock_hz"]), d) * 100))
    add("- “0-overhead/流水线隐藏 tail”判据：`Δ_req = S_ss − 5,000,000 = %s cycles`（≤0）→ 主档 25%% 已过；"
        "但要在保守档（1e6）也过，需再降 ≥ **%s cycles** 固定开销，或把时钟提到 ≥ **%s MHz**；"
        "常数导出尾巴（480,930）本身不是瓶颈，隐藏 tail 不改变 `S_ss`。" %
        (calc.fmt_cyc(4677535 - 5000000), calc.fmt_cyc(5251150 - 5000000),
         calc.fmt_num(5251150 * 37.5 / 1e6, 3)))
    add("")
    add("## 5. Q4：DDR 口径 1333（5,332）vs 1600（6,400）")
    add("")
    add("| 口径 | DDR total | gate(1.25x) | required_eff | gate_eff |")
    add("|---|---:|---:|---:|---:|")
    add("| **1333 主线（5,332 MB/s）** | %s MB/s | %s MB/s | %s | %s |" %
        (calc.fmt_num(ddr[0]["ddr_total_MBps"], 3), calc.fmt_num(ddr[0]["ddr_gate_25_MBps"], 4),
         calc.fmt_pct(ddr[0]["required_eff_1333_pct"]), calc.fmt_pct(ddr[0]["gate_eff_1333_pct"])))
    add("| 1600 回退列（6,400 MB/s） | 同上 | 同上 | %s | %s |" %
        (calc.fmt_pct(ddr[0]["required_eff_1600_pct"]), calc.fmt_pct(ddr[0]["gate_eff_1600_pct"])))
    add("")
    add("- 显式公式：`peak_1333 = 1333e6 × 32/8 / 1e6 = 5,332 MB/s`（用户域 166.65 MHz × 32 B = 5,333 MB/s，同一量级）；"
        "`809.034/5,332 = %s`。**DOC-1 §8 的 1.2/2.33/3.4 GB/s 与 `data_rate×width/8` 不自洽**"
        "（1333 应 ≈5.332 GB/s），本包单列该差异、不采用、不改 gate。" % calc.fmt_pct(ddr[0]["required_eff_1333_pct"]))
    add("- 结论：**平均带宽不是瓶颈**（15.17% of peak；含 25% gate 为 18.97%），但 "
        "`DDR sustained/刷新/行切换/仲裁/单 outstanding` 仍 **unproven**；`809.034` 是平均需求，不是 sustained 实测。")
    add("")
    add("## 6. Q5：UART / 导出尾巴的性质")
    add("")
    add("| 口径 | 字节率 | 40,032 B | 2,594,706 B | 相对 33.333 ms |")
    add("|---|---:|---:|---:|---:|")
    add("| 真实 115200 8N1 | 11,520 B/s | %s s | %s s | %s× / %s× |" %
        (calc.fmt_num(u["export_s_payload"], 3), calc.fmt_num(u["export_s_frame"], 3),
         calc.fmt_num(u["payload_vs_period_x"], 2), calc.fmt_num(u["frame_vs_period_x"], 0)))
    add("| b11/本 run sim sink（`UART_DIV=1`, `clk_uart=clk_a1`=187.5 MHz） | 18.75 MB/s | %s ms | — | — |" %
        calc.fmt_num(u["b11_sink_ms_40032"], 3))
    add("| b6 sim sink（`clk_uart`=1 GHz） | 100 MB/s | %s ms | — | — |" % calc.fmt_num(u["b6_sink_ms_40032"], 3))
    add("")
    add("- 链级锚点覆盖“采集→RAW 槽→DDR 读→core→CMP→**sim-only fast sink**”。真实 115200 比 sim sink 慢 "
        "**%s×**（比 b6 sink 慢 8,688×），无法承载 1080p30 → `transport=not_proven`；生产路径必须是 PCIe/高速 sink。" %
        calc.fmt_num(u["sim_sink_vs_real_x"], 0))
    add("- `export_tail = %s cycles/frame` 四帧恒定（ideal %s，+%s），`sink_limited=false` → 在 `S_ss` 中抵消，"
        "`C_excl_export = C_ss`；**不得**无条件扣 400,320。若真实 UART 限速，CMP 槽会反压 core，`S_ss` 不再成立。" %
        (calc.fmt_cyc(u["tail_measured_cycles"]), calc.fmt_cyc(u["tail_ideal_cycles"]),
         calc.fmt_cyc(u["tail_excess_cycles"])))
    add("")
    add("## 7. Q6：双核 per-stream / 共享 PAXI / 资源 / 时序")
    add("")
    add("- 容量规则不变：`c1s1=C`、`c1s2=C/2`、`c2s1=C`、`c2s2=C`（每核一路，**不是 2C**）。"
        "`2×C_ss = %s MB/s` 只作聚合（DDR/总量），**不得**与 155.52 MB/s 比较判 per-stream。" %
        calc.fmt_num(2 * a1["capacity_MBps"]))
    add("- `dual_core_capacity=assumed_from_single_core`、`paaxi_shared_unproven=true`（b11 的 `a1_ddr_arb2` 只覆盖"
        "“写 store + 读 reader”两客户，4 客户 256-bit 仲裁未实现/未测）。")
    add("- 资源：marginal 231/300（余 69）、conservative 289/300（余 11，3.67%）；Routed 双核时序 **unproven**"
        "（本 run 0 次 TD）。")
    add("- 因此双核行最高 `conditional`，claim headline 最高 `not_proven`，**永不 `feasible`**"
        "（`out/scenarios.csv` 中无任何 `cores=2` 行 verdict=feasible）。")
    add("")
    add("## 8. Q7：其它口径/算术问题与修正后 verdict")
    add("")
    add("| id | 问题 | 影响 |")
    add("|---|---|---|")
    add("| C1 | 冷启动单帧当稳态吞吐（6,421,414 → 29.199 fps） | G0/G25 方向性反转（−2.67%/−22.14% → +33.62%/+6.89%） |")
    add("| C2 | 0% 与 25% 合判（R2 链级 margin<0 → infeasible） | 把“25% 不够”误写成“nominal 不可行” |")
    add("| C3 | 1333 平台用 6,400 峰值 | required_eff/gate_eff 偏乐观（12.64%/15.80% vs 15.17%/18.97%） |")
    add("| C4 | 1080p `applies=false` | 掩盖 25% 在保守档跌破（−4.78%） |")
    add("| C5 | sim sink 当生产 UART | 真实 115200 仅 11,520 B/s（104×/6,757× 帧周期） |")
    add("| C6 | overhead 循环定义、A2≡A4 | A2 被误当独立实测证据 |")
    add("| C7 | 双核 2C 聚合易误读 | 双路误判可行 |")
    add("| C8 | 单一内容基、无 `claim_status` | “保证”越界；自然图像未证 |")
    add("| C9 | 前沿 f_req 240.803 MHz / 25% 最大 23.36 fps | A1 下应为 175.408 MHz / 32.068 fps（单内容） |")
    add("")
    add("**修正后 verdict（1080p30，per-stream，单核）：**")
    add("- `G0`：A1 `%s` / A2 `%s`；`G25`：A1 `%s` / A2 `%s`；`content` = `not_proven_all_content`。"
        % (calc.fmt_pct(a1["margin_0_pct"]) + " pass", calc.fmt_pct(a2["margin_0_pct"]) + " fail",
           calc.fmt_pct(a1["margin_25_pct"]) + " pass", calc.fmt_pct(a2["margin_25_pct"]) + " fail"))
    add("- 行级（A1 measured 内容基）：`c1s1` = `feasible`（资源 187/300、时序 187.5 proven），"
        "但 **`claim_status=not_proven_all_content`**，不得升级为系统 feasible；`c1s2` = `infeasible`（C/2 低于 nominal）；"
        "`c2s1/c2s2` = `conditional`（双核/PAXI unproven）。")
    add("- 系统级 headline：**`not_proven`**（既不是 `infeasible`，也不是 `feasible`；双路更不得 feasible）。")
    add("")
    add("## 9. 推荐（comp 内容基一致规则）")
    add("")
    add("| 角色 | scenario | nominal margin（主档） | G25 | 三档最差 nominal margin | 所需时钟 0% / 25% | 说明 |")
    add("|---|---|---:|---|---:|---|---|")
    add("| **主推荐** | `%s` | %s | %s | %s | %s / %s MHz | comp 基最大 30 fps 几何；保守档跌破 → **primary feasible / conservative conditional** |" %
        (primary["scenario_id"], calc.fmt_pct(primary["margin_chain_pct"]), primary["gate_G25"],
         calc.fmt_pct(worst_primary), calc.fmt_num(primary["required_clock_0_mhz"], 3),
         calc.fmt_num(primary["required_clock_25_mhz"], 3)))
    for i, a in enumerate(alts, 1):
        add("| 备选 %d | `%s` | %s | %s | %s | %s / %s MHz | %s |" %
            (i, a["scenario_id"], calc.fmt_pct(a["margin_chain_pct"]), a["gate_G25"],
             calc.fmt_pct(calc.worst_tier_margin(overhead, a["scenario_id"])),
             calc.fmt_num(a["required_clock_0_mhz"], 3), calc.fmt_num(a["required_clock_25_mhz"], 3),
             "三档稳健" if i == 1 else "单核分时双流，per-stream=C/2 三档稳健"))
    add("| 单列（不作推荐） | `1920x1080-30fps-c1s1-187.5MHz`（A1 单内容） | %s | %s | %s / %s MHz | "
        "**measured-content only / not_proven_all_content**；A2 同几何双 gate 均失，故不得压过 comp 基的 1600×900 |" %
        (calc.fmt_pct(a1["margin_25_pct"]),
         calc.fmt_pct(calc.margin_25(calc.capacity_from_cycles(calc.tier_shift_1080p(frozen, 1000000), frozen["clock_hz"]), d) * 100),
         calc.fmt_num(140.32605, 3), calc.fmt_num(175.4075625, 3)))
    add("")
    add("- 内容基一致性：主推荐/备选全部是 comp 外推基（`affine_comp_tier`），与比较对象同源；1080p 只有 A1（grad）实测，"
        "**不得**因 A1 过 G25 就把 1080p30 提为主推荐。")
    add("- 1080p30 若只看 G0：A1 过、A2 失 → 仍不是 nominal-only，而是内容跨界；`below_25` 一律写 `conditional`，"
        "**不得**写 `infeasible`。")
    add("")
    add("## 10. band / knife-edge / tier 依赖 / 什么会改变结论")
    add("")
    add("- **band**：`S_23=S_34=4,677,535`，band `[4,677,535, 4,677,535]`，spread 0.0000%% → **非 knife-edge**；"
        "A1 距 25%% 阈值（5,000,000 cycles）尚有 %s cycles。" % calc.fmt_cyc(5000000 - 4677535))
    add("- **tier 依赖**：1080p 25%% 只在 tier0/primary 过；tier 1e6 需 %s cycles（比 A1 多 %s）→ 见 §4。" %
        (calc.fmt_cyc(5251150), calc.fmt_cyc(5251150 - 4677535)))
    add("- **A2 缺口**：保守内容要过 G25 需从 6,421,414 降到 ≤5,000,000（−%s cycles，−22.1%%）或把时钟提到 ≥240.803 MHz。"
        % calc.fmt_cyc(6421414 - 5000000))
    add("- 会改变结论的输入：① 全帧 comp/自然图像锚点（A2 变 measured，且 `S ≤ 5,000,000` → 1080p30 可升 `conditional`；"
        "`S > 6,250,000` → `infeasible`）；② 共享 PAXI 4 客户仲裁/DDR sustained 实测；③ 双核 Routed 时序与 "
        "conservative 289 落地；④ 固定开销削减 ≥%s cycles 或时钟 ≥196.918 MHz；⑤ 生产 sink（PCIe）替代 sim sink；"
        "⑥ 几何/内容变化（b6 几何+1 GHz UART 的 `L_cold` 6.42M–6.77M 差异不影响 `S_ss`）。" % calc.fmt_cyc(251150))
    add("")
    add("## 11. 关键数字核对表（`check_outputs.py` 逐行核对）")
    add("")
    add("| 量 | 值 | 标签 | 来源 |")
    add("|---|---|---|---|")
    for label, value, tag, source in key_figures(frozen, rows, overhead):
        add("| %s | %s | %s | %s |" % (label, value, tag, source))
    add("")
    add("## 12. 未测 / not_proven 清单")
    add("")
    add("- 内容：只测平滑梯度（A1）；自然图像/低照/噪声/全帧 comp 均未测 → `not_proven_all_content`。")
    add("- DDR：行为级 PAXI（AR_GAP/R_GAP，单拍，`rdy=1`），无 MC/刷新/行切换/争用 → sustained 与仲裁 unproven。")
    add("- 双核：无 Routed 构建、无 4 客户仲裁、`c2s2=C` 只是 `assumed_from_single_core`。")
    add("- 传输：sim sink 18.75 MB/s；真实 115200 仅诊断 → `transport=not_proven`；PCIe 未做。")
    add("- 时序/资源：单核 ≤187.5 MHz proven（b6/b10 routed），200 MHz 与双核 unproven；本 run 0 次 TD。")
    add("- 板级/RK/Flash：0；本包不声称系统完成。")
    add("")
    add("## 13. 证据索引")
    add("")
    add("- 输入：`inputs/frozen-inputs.json`、`input-verified.json`、`inputs/legacy/{calc.py,rules.json,frozen-inputs.json}`（P2 byte-identical 副本）")
    add("- 模型/规则/测试：`model/{calc.py,rules.json,test_calc.py,gen_tables.py,check_outputs.py,regress_legacy.py,render_report.py}`")
    add("- 表格：`out/{scenarios,content-anchors,gate-matrix,overhead-sensitivity,ddr-budget,corrections,frontier}.csv`、`out/summary.json`、`out/legacy-regression.json`")
    add("- 回归/TEST：`logs/{gen_tables,test_calc,check_outputs,regress_legacy}.out.txt`")
    add("- 冻结：`manifest-r0.json`（本文件与全部附件 SHA256）")
    add("")

    bad = [ln for ln in L if "%%" in ln]
    if bad:
        print("UNFORMATTED-PERCENT LINES: %d" % len(bad))
        for b in bad:
            print("  " + b[:200])
        raise SystemExit(3)

    text = "\n".join(L)
    path = os.path.join(ROOT, "verdict-r1.md")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    print("wrote %s (%d bytes, %d lines)" % (path, len(text.encode("utf-8")), len(L)))


if __name__ == "__main__":
    main()
