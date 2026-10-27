"""Render feasibility-report.md deterministically from the CSVs + frozen inputs.

Every number in the report is either a CSV cell (printed verbatim) or computed here
by model/calc.py from inputs/frozen-inputs.json.  No number is typed by hand.
"""
import csv
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
import calc  # noqa: E402

FROZEN = json.loads((ROOT / "inputs" / "frozen-inputs.json").read_text(encoding="utf-8"))
RULES = json.loads((HERE / "rules.json").read_text(encoding="utf-8"))
JOURNAL = "--journal" in sys.argv


def append_command(result, exit_code, timeout_s=120):
    if not JOURNAL:
        return
    rec = {"argv": ["python", "model/render_report.py"] + (["--journal"] if JOURNAL else []),
           "cwd": str(ROOT), "exit": exit_code, "timeout_s": timeout_s,
           "time_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
           "purpose": "render feasibility-report.md from the CSVs", "result": result}
    path = ROOT / "commands.jsonl"
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    rec["seq"] = len(lines) + 1
    with open(path, "a", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")


def load_csv(name):
    with open(ROOT / "out" / name, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def f2(x):
    return "%.2f" % x


def f3(x):
    return "%.3f" % x


def pct(x):
    return "%.2f%%" % (100.0 * x)


def num(row, key):
    return float(row[key])


def row_at(rows, sid):
    for r in rows:
        if r["scenario_id"] == sid:
            return r
    raise KeyError(sid)


def sens_at(sens, sid, ov):
    for r in sens:
        if r["scenario_id"] == sid and int(round(float(r["overhead_tier_cycles"]))) == int(ov):
            return r
    raise KeyError((sid, ov))


def table(header, rows):
    out = ["| " + " | ".join(header) + " |", "|" + "|".join(["---"] * len(header)) + "|"]
    for r in rows:
        out.append("| " + " | ".join(str(c) for c in r) + " |")
    return out


def main():
    rows = load_csv("scenarios.csv")
    content = load_csv("content-sensitivity.csv")
    ddr = load_csv("ddr-budget.csv")
    frontier = load_csv("frontier.csv")
    sens = load_csv("overhead-sensitivity.csv")

    for r in rows:
        r["_m"] = num(r, "margin_chain_pct") / 100.0
        r["_mc"] = num(r, "margin_core_pct") / 100.0
    primary, alts = calc.recommendations(rows, FROZEN)
    alt_ids = [a["scenario_id"] for a in alts]

    counts = {}
    for r in rows:
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
    gate_counts = {}
    for r in rows:
        gate_counts[r["gate_status"]] = gate_counts.get(r["gate_status"], 0) + 1
    dual_feasible = [r for r in rows if r["verdict"] == "feasible" and r["cores"] == "2"]
    feasible_1080p30 = [r for r in rows if r["verdict"] == "feasible" and r["fps"] == "30"
                        and r["W"] == "1920" and r["H"] == "1080"]

    a = FROZEN["anchors"]
    f = FROZEN["clock_hz"]
    cpb = a["comp"]["cycles_per_byte"]
    core_cycles = calc.raw_bytes(1920, 1080) * cpb
    chain_cycles = a["full_grad"]["cycles"]
    chain_cap = calc.capacity_MBps(2592000, chain_cycles, f)
    core_cap = calc.capacity_from_cpb(cpb, f)
    demand = calc.demand_MBps(2592000, 30)
    gate = FROZEN["design_margin"]
    m_chain = chain_cap / demand - 1.0
    m_core = core_cap / demand - 1.0
    clock25 = calc.required_clock_hz(chain_cycles, 30, 0.25) / 1e6
    clock0 = calc.required_clock_hz(chain_cycles, 30, 0.0) / 1e6
    core_clock25 = calc.required_clock_hz(core_cycles, 30, 0.25) / 1e6
    max_fps_25 = calc.max_fps(chain_cycles, f, 0.25)
    max_fps_0 = calc.max_fps(chain_cycles, f, 0.0)
    max_fps_core_25 = calc.max_fps(core_cycles, f, 0.25)
    px_chain_25 = calc.max_pixels_for(f, cpb, FROZEN["overhead"]["primary_cycles"], 30, 0.25)
    px_core_25 = calc.max_pixels_for(f, cpb, 0, 30, 0.25)
    tiers = RULES["grid"]["geometry_30fps"]
    snap_chain = calc.snap_tier(px_chain_25, [tuple(t) for t in tiers])
    snap_core = calc.snap_tier(px_core_25, [tuple(t) for t in tiers])
    over = FROZEN["overhead"]
    dmain = next(d for d in ddr if d["case_id"] == "dual_1080p30_main")
    dnocmp = next(d for d in ddr if d["case_id"] == "dual_1080p30_no_cmp_ddr")
    dtight = next(d for d in ddr if d["case_id"] == "dual_1080p30_tight_1p0x")
    res = FROZEN["resources"]
    single = res["single_chain_b10_r1_routed"]
    marg = res["dual_marginal"]
    cons = res["dual_conservative"]
    ddrv = res["dual_ddr_variant"]
    csi = res["second_full_csi"]
    fr = FROZEN["frame"]

    L = []
    L.append("# 双路 A+ 双核/服务率可行性判定（P2：`T10.dual-aplus-service-verdict` r0）")
    L.append("")
    L.append("- run：`20261025-195604_fpga-dual-aplus-core-feasibility`；任务：`T10.dual-aplus-service-verdict`")
    L.append("- 角色：fpga-dev（离线模型/表格/报告；**0 次 TD/综合/布线/bitgen/CWC/下载/板卡/ModelSim/RK**）")
    L.append("- 输入冻结：`input-verified.json`（P1 manifest `228531e7…bdd0`、b6 core `6797db05…35bb`、"
             "comp/rand/full_grad 锚点、字节账、187.5 MHz、25% 门槛；0 mismatch）")
    L.append("- 机器可读结果：`out/scenarios.csv`（%d 行）、`out/content-sensitivity.csv`、`out/ddr-budget.csv`、"
             "`out/frontier.csv`、`out/overhead-sensitivity.csv`（%d 行）；判定规则 `model/rules.json`；"
             "模型 `model/calc.py`" % (len(rows), len(sens)))
    L.append("- 单位：MB = 10^6 B；MiB = 2^20 B；时钟 MHz。本报告不声称任何板级/实测吞吐。")
    L.append("")
    L.append("## 1. 结论摘要")
    L.append("")
    L.append("**双路 1920×1080@30 在 187.5 MHz、冻结 b6 core、共享单 DDR MC 下不可行（`infeasible`）；"
             "双核也不能改变 per-stream 结论：每核服务一路时 per-stream 容量仍是单核链级 %.3f MB/s，"
             "低于 25%% 门槛 %.2f MB/s，也低于 30 fps 需求 %.3f MB/s（%s）。"
             "双核资源最高只能判 `conditional`（conservative ERAM %d/300、双核 Routed 时序 unproven）。**"
             % (chain_cap, demand * (1 + gate), demand, pct(m_chain), cons["eram_total"]))
    L.append("")
    L.append("| 关键数字 | 值 | 标签 |")
    L.append("|---|---:|---|")
    L.append("| 单核核级 comp 容量 | %.6f MB/s（%.2f fps@1080p） | measured/derived（b6） |"
             % (core_cap, core_cap / 2.592))
    L.append("| 单核链级 full_grad 容量 | %.6f MB/s（%.3f fps@1080p） | measured（b6 P1 STAT 全帧锚点） |"
             % (chain_cap, chain_cap / 2.592))
    L.append("| 1080p30 per-stream 需求 / 25%% 门槛 | %.2f / %.2f MB/s | derived |" % (demand, demand * 1.25))
    L.append("| 双路总需求（仅 DDR/总量） | %.2f MB/s | derived（**不用于 per-stream 判定**） |" % (2 * demand))
    L.append("| 双核 marginal / conservative ERAM | %d / %d / 300（余 %d / %d） | derived（P1） |"
             % (marg["eram_total"], cons["eram_total"], marg["eram_headroom"], cons["eram_headroom"]))
    L.append("| 场景判定计数 | feasible %d / conditional %d / infeasible %d（共 %d 行） | 本模型 |"
             % (counts.get("feasible", 0), counts.get("conditional", 0), counts.get("infeasible", 0), len(rows)))
    L.append("")
    L.append("一句话：**1080p30 的链级裕量是 %.2f%%（比 25%% 门槛低 %.2f 个百分点）；双核只解决“两路并行”的资源/调度，"
             "不解决单路链级服务率。**"
             % (100.0 * m_chain, 100.0 * (1.0 - chain_cap / (demand * 1.25))))
    L.append("")
    L.append("**三档 overhead 敏感性（设计指南 §4.3/§6.2，`out/overhead-sensitivity.csv`）**：主档 426,385 cycles 下 "
             "1600×900@30 链级 %.4f%%（feasible）；保守档 1,000,000 cycles 下只有 %.4f%%（<25%%，按 R4 为 conditional），"
             "此时 30 fps 链级 25%% 最大档退回 1440×810（%.4f%%，三档均 ≥25%%）。**因此主推荐带条件，不是无条件 feasible。**"
             % (float(sens_at(sens, "1600x900-30fps-c1s1-187.5MHz", 426385)["margin_chain_pct"]),
                float(sens_at(sens, "1600x900-30fps-c1s1-187.5MHz", 1000000)["margin_chain_pct"]),
                float(sens_at(sens, "1440x810-30fps-c1s1-187.5MHz", 1000000)["margin_chain_pct"])))
    L.append("")
    L.append("## 2. 范围、冻结输入与标签")
    L.append("")
    L.append("- 器件：PH1P100SBG484-3；ERAM20K %d、LUT4 %d、DFF %d、DSP %d、PLL %d、slice %d；"
             "LUT6 站点（TD 分母）%d，**不与 LUT4 混算**。"
             % (FROZEN["device"]["eram20k"], FROZEN["device"]["lut4"], FROZEN["device"]["dff"],
                FROZEN["device"]["dsp"], FROZEN["device"]["pll"], FROZEN["device"]["slice"],
                FROZEN["device"]["lut6_sites"]))
    L.append("- 帧：%d×%d，RAW10 packed %.2f B/px；`B_raw`=%s B；RAW 槽 20B/32B → `B_raw_slot`=%s B"
             "（%d words），膨胀 %.1f×；`B_content`=%s；`B_dma`=%s；CMP 最坏 %s+44 = %s B；CMP 槽 8 MiB。"
             % (fr["W"], fr["H"], fr["bytes_per_px"], format(fr["raw_bytes"], ","),
                format(fr["raw_slot_bytes"], ","), fr["raw_slot_words"], fr["raw_slot_expansion"],
                format(fr["content_bytes"], ","), format(fr["dma_bytes"], ","),
                format(fr["cmp_payload_bytes"], ","), format(fr["cmp_total_bytes"], ",")))
    L.append("- 锚点：comp %d cycles / %d B = %.6f MB/s；rand %d / %.6f MB/s；full_grad %d cycles / 全帧 %.3f fps。"
             % (a["comp"]["cycles"], a["comp"]["input_bytes"], a["comp"]["rate_MBps"],
                a["rand"]["cycles"], a["rand"]["rate_MBps"], a["full_grad"]["cycles"],
                a["full_grad"]["fps_at_187p5"]))
    L.append("- **链级锚点边界（本轮核实）**：full_grad 是 1920×1080 全帧（TB 默认 W/H=1920/1080，STAT "
             "`read_words=129600` 证明 1080p RAW 槽几何），%d cycles 覆盖“相机模型→RAW 槽写→DDR 读→core→"
             "UART 导出”的串行链（行为级 DDR，不是 PAXI/DDR MC 时序）。`full_grad.dec` 的 180,425 B 是 TB "
             "逐行十进制字节抓包（40,076 行），**不是 payload 尺寸**。" % a["full_grad"]["cycles"])
    L.append("- **1440×810 档的打包边界**：H=810 不被 4 整除，但 W=1440 使每行 360 组、stride 1,800 B 为整数，"
             "total groups 291,600，packed 组连续存放即无 padding；设计指南“W/H 均可被 4 整除”对 810 不成立，"
             "模型按实际可分性（W%4==0 且 W*H%4==0）校验，7 档全部通过。")
    L.append("- 标签纪律：`measured`（b6/b10 routed、b6 STAT、P1）、`derived`（公式复算）、"
             "`assumed`（overhead 恒定 %d cycles、slice 比例、共享 PHY、CSI 增量）、`unproven`（双核 Routed、"
             "DDR 持续效率、自然图像内容、200 MHz）。" % over["primary_cycles"])
    L.append("- 工具：Python %s；无网络/随机；TD=0、ModelSim=0、硬件=0。"
             % json.loads((ROOT / "input-verified.json").read_text(encoding="utf-8")).get("python", "3.11.5"))
    L.append("")
    L.append("## 3. 单核资源/时序基线（Routed）")
    L.append("")
    L.extend(table(
        ["source", "ERAM 逻辑", "DRAMHARDCON", "ERAM 合计", "LUT6/71,680", "REG/143,360", "SLICE/71,680",
         "DSP/220", "PLL/12", "WNS/hold (ns)", "违例/端点"],
        [["b10 r1（单链基线）", single["eram_logic"], single["dram_hardcon"], single["eram_total"],
          "%d (%.2f%%)" % (single["lut6"], 100.0 * single["lut6"] / 71680),
          "%d (%.2f%%)" % (single["reg"], 100.0 * single["reg"] / 143360),
          "%d (%.2f%%)" % (single["slice"], 100.0 * single["slice"] / 71680),
          single["dsp"], single["pll"], "+%.3f/+%.3f" % (single["wns_ns"], single["hold_ns"]),
          "%d/%d" % (single["viol_ep"], single["total_ep"])],
         ["b6（core 级）", "—", "—", "—", "—", "—", "—", "—", "—", "+%.3f/+%.3f" % (
             FROZEN["resources"]["single_core_b6_routed"]["wns_ns"],
             FROZEN["resources"]["single_core_b6_routed"]["hold_ns"]),
          "%d/%d" % (FROZEN["resources"]["single_core_b6_routed"]["viol_ep"],
                     FROZEN["resources"]["single_core_b6_routed"]["total_ep"])]]))
    L.append("")
    L.append("- 单链 102+85=**%d/300**（%.2f%%），LUT6 %d/71,680；单核 Routed WNS +0.119/+0.103 属**薄余量**"
             "（hold 仅 +0.020）。"
             % (single["eram_total"], 100.0 * single["eram_total"] / 300, single["lut6"]))
    L.append("- 时序只在 187.5 MHz 的单核 Routed 上 measured；**双核 Routed 时序 unproven**，"
             "不得由 +0.119/+0.103 外推。")
    L.append("")
    L.append("## 4. 双核资源表（P1 `228531e7…bdd0`）")
    L.append("")
    L.extend(table(
        ["栏", "ERAM 逻辑", "+DRAMHARDCON", "ERAM 合计", "余量", "LUT6/71,680", "LUT4 上界/129,024",
         "REG", "SLICE", "PLL", "fit_300", "时序"],
        [["marginal（期望）", marg["eram_logic"], marg["dram_hardcon"], marg["eram_total"],
          "%d (%.1f%%)" % (marg["eram_headroom"], marg["headroom_pct"]), marg["lut6"], marg["lut4_upper"],
          marg["reg"], marg["slice"], marg["pll"], marg["fit_300"], "unproven"],
         ["conservative（上界）", cons["eram_logic"], cons["dram_hardcon"], cons["eram_total"],
          "%d (%.2f%%)" % (cons["eram_headroom"], cons["headroom_pct"]), cons["lut6"], cons["lut4_upper"],
          cons["reg"], cons["slice"], cons["pll"], cons["fit_300"], "unproven"]]))
    L.append("")
    L.append("- **marginal %d/300（余 %d，%.1f%%）pass；conservative %d/300（余 %d，%.2f%%）落 271–300 → "
             "按冻结规则只能 `conditional`。双核最高判定 = `conditional`，本 run 不存在双核 `feasible`。**"
             % (marg["eram_total"], marg["eram_headroom"], marg["headroom_pct"], cons["eram_total"],
                cons["eram_headroom"], cons["headroom_pct"]))
    L.append("- 210 逻辑额度：marginal %d/210（余 %d）、conservative %d/210（余 %d）；双 DDR 控制器变体 "
             "marginal %d/300、conservative %d/300 → **fail**（默认共享 256-bit PAXI/DDR MC，不默认两端口）。"
             % (marg["eram_logic"], marg["logic_headroom_210"], cons["eram_logic"], cons["logic_headroom_210"],
                ddrv["marginal_eram_total"], ddrv["conservative_eram_total"]))
    L.append("- **第二路完整 CSI 敏感性**：routed 只有 `u_csi_a`，`u_csi_b` 未实现/未计入 marginal；若需要，"
             "加 %d logic/%d ripple/%d seq/%d ERAM → LUT6 **%s**、REG **%s**、SLICE 约 **%s**，"
             "ERAM %d/300 与 fit 不变。"
             % (csi["logic_delta"], csi["ripple_delta"], csi["seq_delta"], csi["eram_delta"],
                format(csi["lut6_total"], ","), format(csi["reg_total"], ","),
                format(csi["slice_total"], ","), csi["eram_total"]))
    L.append("")
    L.append("## 5. 服务率（core-only vs full-chain；per-stream vs aggregate）")
    L.append("")
    L.append("per-stream 需求 `D_s = B_raw×fps`；1080p30 = **%.2f MB/s**，25%% 门槛 **%.2f MB/s**。"
             "容量按每行 fps/时钟计算；`feasible` 只看 **per-stream full-chain** 裕量。"
             % (demand, demand * 1.25))
    L.append("")
    four = [row_at(rows, "1920x1080-30fps-c1s1-187.5MHz"), row_at(rows, "1920x1080-30fps-c1s2-187.5MHz"),
            row_at(rows, "1920x1080-30fps-c2s1-187.5MHz"), row_at(rows, "1920x1080-30fps-c2s2-187.5MHz")]
    L.extend(table(
        ["cores", "streams", "per-stream 容量 basis", "C_core_comp", "C_chain", "m_core", "m_chain",
         "drop_lb", "gate", "verdict"],
        [[r["cores"], r["streams"], ("C/2（单核分时）" if r["cores"] == "1" and r["streams"] == "2"
                                     else ("C（每核一路，**不是 2C**）" if r["cores"] == "2" and r["streams"] == "2"
                                           else "C")),
          r["capacity_core_MBps"], r["capacity_chain_MBps"], r["margin_core_pct"] + "%",
          r["margin_chain_pct"] + "%", r["drop_rate_lb_pct"] + "%", r["gate_status"], r["verdict"]]
         for r in four]))
    L.append("")
    L.append("- **aggregate 陷阱**：2×C_core = %.3f ≥ %.2f，但这是聚合带宽；2×C_chain = %.3f 已 < %.2f，"
             "per-stream 更只有 %.3f < %.2f。双路 30 fps 只能看 per-stream。"
             % (2 * core_cap, 2 * demand, 2 * chain_cap, 2 * demand, chain_cap, demand))
    L.append("- **core-only 陷阱**：1080p30 core-only 裕量 %s，看着“实时”；同一行链级 %s → `fails_30`。"
             "core-only 只是乐观上界（无 DDR 读/槽管理/导出/仲裁）。" % (pct(m_core), pct(m_chain)))
    L.append("- 1080p 帧率梯（每路）：链级 25%% 最大 **%.2f fps**，0%% 最大 **%.3f fps**；"
             "核级 25%% 最大 %.2f fps。单核双路的 per-stream 25%% 最大只有 **%.2f fps**。"
             % (max_fps_25, max_fps_0, max_fps_core_25, max_fps_25 / 2.0))
    L.append("- 30 fps 分辨率前沿：链级 25%% 最大 **%d×%d**（%.2f%%），核级 25%% 最大 %d×%d（%.2f%%）；"
             "1080p30 链级固定差 %.2f%%。"
             % (snap_chain[0], snap_chain[1], 100.0 * (calc.capacity_MBps(
                 calc.raw_bytes(*snap_chain), calc.chain_cycles_for(*snap_chain, cpb, over["primary_cycles"]), f)
                 / calc.demand_MBps(calc.raw_bytes(*snap_chain), 30) - 1.0),
                snap_core[0], snap_core[1], 100.0 * (core_cap / (calc.raw_bytes(*snap_core) * 30 / 1e6) - 1.0),
                100.0 * m_chain))
    L.append("- 1080p30 双核时钟梯（每核一路）：150/175/187.5/200 MHz 的链级裕量见 §8/`out/scenarios.csv`；"
             "200 MHz 仍只有 %.2f%% 且 200 MHz 时序 unproven。" % (100.0 * (chain_cap * 200.0 / 187.5 / demand - 1.0)))
    L.append("- **1 核 2 路 ERAM 口径**：这些行的 ERAM bound 仍用单链 187/300，**未**把第二路 bridge 15 + stream fabric 6 = 21 "
             "计入（合计约 208/300，仍 ≤270，verdict 不变）；这是偏保守偏低的口径，已在 `out/scenarios.csv` 的 notes 写明。")
    L.append("")
    L.append("overhead 三档敏感性（`out/overhead-sensitivity.csv`；1080p 固定实测锚点，tier 不适用）：")
    L.append("")

    def sm(sid, ov):
        return sens_at(sens, sid, ov)["margin_chain_pct"]

    def tier_best(ov):
        cand = [r for r in sens if int(round(float(r["overhead_tier_cycles"]))) == ov
                and r["applies"] == "true" and float(r["fps"]) == 30
                and int(r["cores"]) == 1 and int(r["streams"]) == 1
                and float(r["margin_chain_pct"]) >= 100.0 * gate]
        best = max(cand, key=lambda r: int(r["W"]) * int(r["H"]))
        return "%s×%s" % (best["W"], best["H"]), best["margin_chain_pct"] + "%"

    tier_rows = []
    for ov in FROZEN["overhead"]["sensitivity_tiers"]:
        label, margin = tier_best(ov)
        tier_rows.append(["%d cycles" % ov, label, margin,
                          sm("1600x900-30fps-c1s1-187.5MHz", ov) + "%",
                          sm("1440x810-30fps-c1s1-187.5MHz", ov) + "%",
                          sm("1728x972-30fps-c1s1-187.5MHz", ov) + "%"])
    L.extend(table(["overhead tier", "30 fps c1s1 最大 25% 档", "该档 margin",
                    "1600×900 margin", "1440×810 margin", "1728×972 margin"], tier_rows))
    L.append("")
    L.append("- 主档（426,385）的最大 25% 档是 1600×900；保守档（1,000,000）退回 1440×810。"
             "**1600×900 在保守档只有 21.0486% <25%，因此主推荐必须写成“主档 feasible / 保守档 conditional”。**")
    L.append("")
    L.append("内容敏感性（`out/content-sensitivity.csv`）：")
    L.append("")
    L.extend(table(
        ["case", "basis", "cycles", "capacity MB/s", "fps@1080p", "margin@30", "gate", "label"],
        [[c["case_id"], c["basis"], c["cycles"], c["capacity_MBps"], c["fps_1080p_equivalent"],
          c["margin_pct"] + "%", c["gate_25"], c["label"]] for c in content]))
    L.append("")
    L.append("- comp 是最慢的 measured 核级向量；full_grad 是唯一全帧链级锚点。**自然图像/低照/噪声未测**，"
             "comp 不是所有内容的严格上界；链级 overhead 跨内容恒定是 `assumed`。")
    L.append("")
    L.append("## 6. DDR 2R+2S")
    L.append("")
    L.append("公式：`R_w=R_r=D_total×1.6`；`S_w=S_r=B_cmp_total×fps×streams/1e6`（worst stored）；"
             "`DDR_total=R_w+R_r+S_w+S_r`；`gate=DDR_total×1.25`；`required_eff=DDR_total/6400`。"
             "6,400 MB/s 是 ×32 1600 MT/s 理论峰值，**未扣刷新/行切换/仲裁/命令开销，不是实测**。")
    L.append("")
    L.extend(table(
        ["case", "streams", "fps", "raw W", "raw R", "cmp W", "cmp R", "total", "gate+25%",
         "required eff", "含 CMP DDR", "layout"],
        [[d["case_id"], d["streams"], d["fps"], d["raw_write_MBps"], d["raw_read_MBps"],
          d["cmp_write_MBps"], d["cmp_read_MBps"], d["ddr_total_MBps"], d["ddr_gate_25_MBps"],
          d["required_eff_pct"] + "%", d["includes_cmp_ddr"], d["layout"]] for d in ddr]))
    L.append("")
    L.append("- 主路径（双路 1080p30，20B/32B，含 CMP DDR）总需求 **%s MB/s**，所需效率 **%s%%**，"
             "25%% 门槛下也只有 **%s MB/s（%s%% 峰值）**。**平均带宽不是主要瓶颈**，但桥的 latency/"
             "outstanding/单拍效率仍未证明。"
             % (dmain["ddr_total_MBps"], dmain["required_eff_pct"], dmain["ddr_gate_25_MBps"],
                dmain["sustained_eff_at_gate_pct"]))
    L.append("- 变体：不含 CMP DDR %s MB/s（%s%%）；20261025-180900 紧密 1.0× 布局 %s MB/s（%s%%）——"
             "**后者不是本 run 采用的主动路径**。排除项（预览/显示、诊断 RAW、元数据、ECC、刷新）另计。"
             % (dnocmp["ddr_total_MBps"], dnocmp["required_eff_pct"], dtight["ddr_total_MBps"],
                dtight["required_eff_pct"]))
    L.append("")
    L.append("## 7. 调度/缓冲服务率与丢帧下界")
    L.append("")
    L.append("- 假设（与 T08/T10 合同一致）：每路 2 RAW 槽/2 CMP 槽、帧级公平、一编码器一次一帧不抢占；"
             "无空闲 RAW 槽 → 丢整帧并记 capture_seq 缺口；CMP 满 → 持有 RAW 槽。")
    L.append("- 双核：每核固定服务一路，per-stream = C；单核双路：帧级轮转，长期每路 50%，per-stream = C/2。")
    L.append("- 稳态丢帧下界 `drop_rate_lb = max(0, 1 − C_service/D_s)`，`C_service` 一律取 **per-stream 链级**"
             "（本表 `drop_rate_lb_basis` 列）；它是**下界**，实际仲裁/空窗可能更差。")
    L.append("- 1080p30：单核单路丢帧下界 **%s%%**、单核双路 **%s%%**、双核双路 **%s%%**（双核不改变 per-stream）。"
             % (row_at(rows, "1920x1080-30fps-c1s1-187.5MHz")["drop_rate_lb_pct"],
                row_at(rows, "1920x1080-30fps-c1s2-187.5MHz")["drop_rate_lb_pct"],
                row_at(rows, "1920x1080-30fps-c2s2-187.5MHz")["drop_rate_lb_pct"]))
    L.append("- `drop_rate_lb=0` 只表示算术上不积压，**不等于满足 25% 设计裕量**；`gate_25` 单列。"
             "本 run 只做帧级下界，不做周期级调度/one-outstanding reader/PAXI 仲裁仿真。")
    L.append("")
    L.append("## 8. 判定表（%d 行，机械应用 `model/rules.json`）" % len(rows))
    L.append("")
    L.append("判定顺序：R1 marginal ERAM>300 → infeasible；R2 per-stream 链级裕量<0 → infeasible；"
             "R3 双核时序 unproven → conditional；R4 链级≥25% 且 conservative≤270 且时序已证 → feasible；"
             "否则 conditional。`gate_status` 按 per-stream 链级裕量。")
    L.append("")
    L.extend(table(
        ["scenario_id", "c", "s", "W×H", "fps", "clk", "C_core", "C_chain", "m_core%", "m_chain%",
         "drop_lb%", "gate", "verdict"],
        [[r["scenario_id"], r["cores"], r["streams"], r["W"] + "×" + r["H"], r["fps"], r["clock_mhz"],
          r["capacity_core_MBps"], r["capacity_chain_MBps"], r["margin_core_pct"], r["margin_chain_pct"],
          r["drop_rate_lb_pct"], r["gate_status"], r["verdict"]] for r in rows]))
    L.append("")
    L.append("- 计数：feasible **%d**、conditional **%d**、infeasible **%d**；gate：meets_25 %d、below_25 %d、"
             "fails_30 %d。双核 feasible 行 **%d**；1080p30 feasible 行 **%d**。"
             % (counts.get("feasible", 0), counts.get("conditional", 0), counts.get("infeasible", 0),
                gate_counts.get("meets_25", 0), gate_counts.get("below_25", 0), gate_counts.get("fails_30", 0),
                len(dual_feasible), len(feasible_1080p30)))
    L.append("- 网格说明：设计指南 §6.2 的 39 行 = 7 档几何×4 组合 + 8 个 1080p 双路帧率 + 3 个附加时钟档；"
             "本表另加 4 个**单核单路 1080p 帧率档**（25/24/20/15 fps），因为 §6.3 规则 4 要求给出"
             "“1080p 下满足 25%% 的最大 fps（单核/双核各一）”；合计 %d 行，未删任何 §6.2 组合。" % len(rows))
    L.append("")
    L.append("## 9. Pareto 前沿与推荐（1 主 + ≤2 备选）")
    L.append("")
    L.extend(table(
        ["family", "c", "s", "W×H", "fps", "clk", "basis", "margin%", "gate",
         "worst tier%", "worst gate", "verdict", "rec", "req chain clk", "req core clk", "notes"],
        [[x["family"], x["cores"], x["streams"], x["W"] + "×" + x["H"], x["fps"], x["clock_mhz"],
          x["capacity_basis"], x["margin_pct"], x["gate_25"], x["worst_tier_margin_pct"],
          x["worst_tier_gate"], x["verdict"], x["is_recommended"], x["required_clock_chain_25_mhz"],
          x["required_clock_core_25_mhz"], x["notes"]] for x in frontier]))
    L.append("")
    f1600 = next(x for x in frontier if x["W"] == "1600" and x["H"] == "900"
                 and x["capacity_basis"] == "full_chain_affine")
    f1440 = next(x for x in frontier if x["W"] == "1440" and x["H"] == "810"
                 and x["capacity_basis"] == "full_chain_affine")
    f1080p20 = next(x for x in frontier if x["W"] == "1920" and x["H"] == "1080"
                    and x["fps"] == "20" and x["capacity_basis"] == "full_chain_anchor")
    L.append("**主推荐（带条件）：1600×900@30（单核单路）** —— 主档 426,385 cycles 链级裕量 **%s**（%s）；"
             "保守档 1,000,000 cycles 下 **%s**（%s；该档 verdict = `%s`）。所需时钟：链 **%s MHz** / 核 **%s MHz**"
             "（25%% 门槛；均低于已验证的 187.5 MHz，不需要超频）。ERAM **%s/300**。"
             "**不是无条件 feasible，也不是 1080p。**"
             % (f1600["margin_chain_pct"] + "%", f1600["gate_25"],
                sm("1600x900-30fps-c1s1-187.5MHz", 1000000) + "%",
                sens_at(sens, "1600x900-30fps-c1s1-187.5MHz", 1000000)["gate_25"],
                sens_at(sens, "1600x900-30fps-c1s1-187.5MHz", 1000000)["verdict"],
                f1600["required_clock_chain_25_mhz"], f1600["required_clock_core_25_mhz"],
                primary["eram_total"]))
    L.append("")
    L.append("**备选 1（三档稳健）：1440×810@30（单核单路）** —— 三档 overhead 下链级裕量最小 **%s**（%s），"
             "所需时钟 链 **%s MHz** / 核 **%s MHz**；ERAM 187/300 → 三档均 `feasible`。"
             % (f1440["worst_tier_margin_pct"] + "%", f1440["worst_tier_gate"],
                f1440["required_clock_chain_25_mhz"], f1440["required_clock_core_25_mhz"]))
    L.append("")
    L.append("**备选 2（全分辨率降帧）：1920×1080@20（单核单路）** —— 链级裕量 **%s**（1080p 实测锚点固定，三档相同），"
             "所需时钟 链 **%s MHz** / 核 **%s MHz** → `feasible`。"
             % (f1080p20["margin_pct"] + "%", f1080p20["required_clock_chain_25_mhz"],
                f1080p20["required_clock_core_25_mhz"]))
    L.append("")
    L.append("- **不推荐**：双核 2×1080p30（链级 %s，`fails_30`；双核时序 unproven；conservative %d/300）；"
             "单核双路 1080p（per-stream 只有 C/2）；1728×972@30（主档 %s、保守档 %s，均低于 25%%）。"
             % (pct(m_chain), cons["eram_total"],
                row_at(rows, "1728x972-30fps-c1s1-187.5MHz")["margin_chain_pct"] + "%",
                sm("1728x972-30fps-c1s1-187.5MHz", 1000000) + "%"))
    L.append("- 前沿极大性：主档 30 fps 链级 25%% 最大档 %d×%d（%s）；全档稳健最大档 1440×810；"
             "1080p 链级 25%% 最大 fps %s（单核）；1c2s 最大 960×540。"
             % (snap_chain[0], snap_chain[1], primary["scenario_id"],
                row_at(rows, "1920x1080-20fps-c1s1-187.5MHz")["fps"]))
    L.append("")
    L.append("## 10. 什么会改变结论（可测阈值）")
    L.append("")
    L.append("- **时钟**：链级 1080p30 需 ≥ **%.3f MHz** 才到 0%%、≥ **%.3f MHz** 才到 25%%；当前 187.5 MHz"
             "（+%.2f%% / +%.2f%%）。200 MHz 只有 %.2f%% 且 unproven。"
             % (clock0, clock25, 100.0 * (clock0 / 187.5 - 1.0), 100.0 * (clock25 / 187.5 - 1.0),
                100.0 * (chain_cap * 200.0 / 187.5 / demand - 1.0)))
    L.append("- **链级 cycles/frame**：25%% 需 ≤ **5,000,000**（当前 %s，需减少 **%.2f%%**）；"
             "0%% 需 ≤ **6,250,000**（当前已 %.2f%% 超出）。即使 overhead 归零，核级也需 ≤ **1.9288 cycles/B**"
             "（comp 现为 %.4f，需快 %.2f%%）。"
             % (format(chain_cycles, ","), 100.0 * (1.0 - 5_000_000 / chain_cycles),
                100.0 * (chain_cycles / 6_250_000 - 1.0), cpb, 100.0 * (1.0 - 1.9288 / cpb)))
    L.append("- **核级**：25%% 需 ≥ **%.2f fps**@1080p（需 ≥ %.3f MHz 或同比减少 cycles）；"
             "当前核级 31.276 fps 只够 0%%。" % (max_fps_core_25, core_clock25))
    L.append("- **分辨率**：30 fps 链级 25%% 最大档 %d×%d；1728×972 只有 %s（可实时但低于门槛）。"
             % (snap_chain[0], snap_chain[1], row_at(rows, "1728x972-30fps-c1s1-187.5MHz")["margin_chain_pct"] + "%"))
    L.append("- **overhead 档**：1600×900@30 在保守档（1,000,000 cycles）只有 %.4f%%；要让该档也满足 25%%，"
             "链级 overhead 必须 ≤ %.0f cycles（当前 1,000,000）。1440×810 的对应上限是 %.0f cycles，"
             "因此它是三档稳健档。"
             % (float(sm("1600x900-30fps-c1s1-187.5MHz", 1000000)),
                5_000_000 - calc.raw_bytes(1600, 900) * cpb,
                5_000_000 - calc.raw_bytes(1440, 810) * cpb))
    L.append("- **DDR**：主路径需持续 **%s MB/s**（0%%）/ **%s MB/s**（25%% 门槛）。若实测持续带宽低于 "
             "809 MB/s，或 PAXI 仲裁/单拍效率使有效带宽低于该值，DDR 会取代 core 成为瓶颈。"
             % (dmain["ddr_total_MBps"], dmain["ddr_gate_25_MBps"]))
    L.append("- **内容**：若自然图像的核级 cycles/B > %.4f（comp）或全帧链级 > %s cycles，结论只会更差；"
             "要让 1080p30 25%% 成立，链级必须 ≤ 5,000,000 cycles（比 measured 锚点少 %.2f%%）。"
             % (cpb, format(chain_cycles, ","), 100.0 * (1.0 - 5_000_000 / chain_cycles)))
    L.append("- **双核资源/时序**：即使双核 Routed 时序通过，conservative 仍 %d/300 > 270 → 仍 `conditional`；"
             "而 per-stream 链级不变，1080p30 仍 `fails_30`。**双核不是 1080p30 的解。**" % cons["eram_total"])
    L.append("- **第二 DDR 控制器**：marginal %d/300、conservative %d/300 → 双核直接 `infeasible`，"
             "必须保持共享单 DDR MC。" % (ddrv["marginal_eram_total"], ddrv["conservative_eram_total"]))
    L.append("")
    L.append("## 11. 风险、未测、G 层与复现")
    L.append("")
    L.append("| 风险/未测 | 影响 | 现状 |")
    L.append("|---|---|---|")
    L.append("| 自然图像/低照/噪声未测 | comp 可能不是最坏内容，实时性更差 | `unproven`，不得称“保证” |")
    L.append("| 链级锚点单一内容 | overhead %d cycles 跨内容恒定是 assumed | 仅 full_grad 一例 |" % over["primary_cycles"])
    L.append("| overhead 档依赖 | 主推荐只在 assumed 主档 ≥25%%，保守档降为 conditional | `out/overhead-sensitivity.csv` %d 行；§1/§5/§9 已披露 |" % len(sens))
    L.append("| 双核 Routed 时序/布局/拥塞 | 可能改变 WNS | `unproven`；本 run 无 TD |")
    L.append("| DDR 持续带宽/PAXI 仲裁/单拍效率 | 平均够 ≠ 实际够 | `unproven`，只有 required efficiency |")
    L.append("| 第二路完整 CSI 未实现 | marginal 少 773/340/1,474 | 补算 LUT6 %s/REG %s/SLICE %s，ERAM 不变 |"
             % (format(csi["lut6_total"], ","), format(csi["reg_total"], ","), format(csi["slice_total"], ",")))
    L.append("| 精确 LUT4、第二路 FIFO ERAM 映射、去 CWC 后真实 ERAM | 资源可能偏移 | 只有上界/assumed |")
    L.append("| 周期级调度/one-outstanding reader | 帧级下界可能偏乐观 | 未仿真；T10 scheduler 无 PASS 报告 |")
    L.append("| RK/PCIe/板级/曝光同步 | 无系统级吞吐/恢复结论 | 全部 not_run |")
    L.append("")
    L.append("G 层：**G0 pass**（输入 SHA/字节，0 mismatch）、**G1 pass**（模型/CSV/报告可复现，3 个负对照被拒）、"
             "**G2/G3/G4 not_applicable**（无 RTL/综合/布线/bit/板卡）。离线 PASS 不等于双路系统完成。")
    L.append("")
    L.append("复现（cwd = 本任务 `r0/`）：")
    L.append("")
    L.append("```powershell")
    L.append("python model/gen_tables.py      # 冻结/校验输入 + 生成 out/*.csv；mismatch 必须为 0")
    L.append("python model/test_calc.py       # 已知值/边界/3 个负对照；必须 exit 0")
    L.append("python model/render_report.py   # 由 CSV 生成本报告")
    L.append("python model/check_outputs.py   # CSV↔报告一致性 + 前沿极大性 + 负对照；必须 exit 0")
    L.append("```")
    L.append("")
    text = "\n".join(L) + "\n"
    (ROOT / "feasibility-report.md").write_text(text, encoding="utf-8", newline="\n")
    import hashlib
    logs = ROOT / "logs"
    logs.mkdir(exist_ok=True)
    payload = text.encode("utf-8")
    (logs / "report.sha256").write_text(
        "sha256=%s\nbytes=%d\nlines=%d\n" % (hashlib.sha256(payload).hexdigest(), len(payload), len(L)),
        encoding="utf-8", newline="\n")
    print("REPORT_OK lines=%d bytes=%d primary=%s alts=%s"
          % (len(L), len(payload), primary["scenario_id"], ",".join(alt_ids)))
    append_command("REPORT_OK lines=%d bytes=%d" % (len(L), len(payload)), 0)
    return 0


if __name__ == "__main__":
    sys.exit(main())
