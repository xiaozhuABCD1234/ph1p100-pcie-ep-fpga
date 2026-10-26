# lessons — T10.dual-core-resource-baseline r0

只记可复用的根因/触发/修正/验证入口，不重复报告正文。

## 1. TD 报告解析

- **触发**：`syn_gate_area.rpt` 的 `#lut6` 缩进在 `#lut` 之下（`  #lut6 8528`），而 `routed_area.rpt` 的 `#lut6` 顶格。
- **根因**：只用 `^#lut6` 的解析器在 synth 报告上漏字段。
- **修正**：所有 `#` 资源行统一允许前导空白；`#lut` 规则显式排除 `#lut6`。
- **验证**：`check_tables.py::resource_table_matches_reports` 对 3 个 synth 顶层逐项重算。

## 2. b6 独立报告的哈希写法

- **触发**：`b6_report_carries_core_sha` 断言失败。
- **根因**：b6 独立报告只写 `6797db05…35bb` 短哈希，完整 SHA 只在 manifest 与输入文件里。
- **修正**：报告级交叉检查用“短哈希 + 80,196 B”；完整 SHA 用文件重算 + manifest 节点双断言。
- **验证**：`input-verified.json` 的 `hard_assertions`，`mismatch_count=0`。

## 3. synth 72 vs routed 102 的真实原因（可复用结论）

- **事实**：三源 synth ERAM 都是 72，routed 都是 102；差值恰为布线阶段自动插入的 `auto_created_cwc1/2` 各 15 ERAM（`U_cwc_ram`）。
- **用法**：解释 synth/routed 差异时先查 CWC/调试 RAM，不要用“工具映射差异”一句带过；但拟合仍只用 routed，不得用 72 替换 102。
- **验证**：`resource-table.csv` 的 synth 行 notes + `hierarchy_sums_close_to_top`。

## 4. 层次闭合的容差

- **触发**：`HIERARCHY_CLOSURE_FAIL b6 ripple residual 43`。
- **根因**：TD 的深度 1 层次行不含顶层直接粘合逻辑；b6 顶层 logic/ripple/seq 残留 91/43/60，b10 为 95/43/91。
- **修正**：ERAM/DRAM_LUT/PLL/DSP 要求精确相等（这些决定预算）；logic/ripple/seq 允许 <2% 顶层粘合残留并在报告中写明。不要用“全等”硬断言，也不要反过来放宽 ERAM。
- **验证**：三源 ERAM 均 102/102。

## 5. DRAMHARDCON 归属

- **事实**：area `#eram 102/300` 与 QoR `#RAMs 102`、`#DRAMHARDCON 85` 分列；b10 result-r1 §4.1 明确 102+85=187≤300；构建控制台同印两行。
- **用法**：`ERAM_total = ERAM_logic + DRAM_HARDCON`，共享单 DDR MC 时 85 只算一次。若第二路要独立 DDR 控制器，再 +85 → 316/374，均超 300。
- **验证**：`dual_core_budget_arithmetic` + `MISSING_DRAMHARDCON` 负对照。

## 6. 顶层识别

- 三份 routed 报告都是 `p2_a1_board_top`；b6 不是“仅 core 的小顶层”，只是功能集较小（LUT6 18,743 vs b10 19,695）。
- 后续引用 b6 资源时必须说明它是整机 top 的单链构建，不能把 102 说成“core 的资源”；`u_core` 只有 23 ERAM。

## 7. 负对照设计

- 负对照必须能拒绝**真实会犯的错**：synth 行混入拟合、漏 85、用 102×2 单栏。fixture 只放最小字段，检查器按规则抛固定错误码，测试者可直接复核期望码。
- 检查器与生成器分开实现（不 import），否则负对照会自证。

## 8. TD `#lut6` 恒等式（round1 F1）

- **根因**：把层次 `logic lut` 当成唯一 LUT6 增量，漏了 `ripple` 与 `dram lut`。
- **恒等式**（b6/b10/b11 三源顶层精确成立）：`#lut6 = #with luts + #with adder + #dram lut + #shifter lut`。
- **修正**：marginal `LUT6 = 19,695 + 3,793 + 2,077 + 144 = 25,709`；`LUT4 上界 = 2×25,709 = 51,418`。只算 logic 的 23,488 只能作下界，必须单列并注明“不作拟合值”。
- **验证**：`check_tables.py::lut6_identity_td` + budget 行的 `LUT6_total - LUT6_logic_only_lower == ripple_delta + dram_delta`。

## 9. manifest 与 freeze 日志的自绑定（round1 F2）

- **根因**：manifest 与 freeze 日志由不同运行/不同顺序产生；日志里的 SHA 不是最终 manifest 的 SHA，且最终 manifest 未被命令日志记录。
- **修正模式**（可复用）：
  1. 追加本次 freeze 到 `commands.jsonl`（在 manifest 哈希前，保证命令被 manifest 覆盖）；
  2. 哈希全部 artifacts（排除 manifest 自身与 freeze 日志）；
  3. 写 manifest；
  4. **读回 manifest SHA，再写 freeze 日志**（日志含 `sha256=<final>`，并从 artifacts 排除，避免自引用）；
  5. 之后不再写任何文件。
- **验证**：测试者比较 `logs/mk_manifest.out.txt` 的 `sha256=` 与磁盘 manifest；`commands.jsonl` 条数 = manifest `commands` 条数。

## 10. 源码例化 ≠ routed 资源（round1 F3）

- **触发**：报告写 `u_camera` 已含 A/B 两路 CSI RX，但 routed 层次只有 `u_csi_a`，没有 `u_csi_b`。
- **根因**：`u_csi_b` 在源码中例化，但数据输出未形成使用路径，综合/布线后无资源。
- **修正**：资源清单以 routed 层次为准；第二路完整 CSI 的 773 logic/340 ripple/1,474 seq/0 ERAM 要么计入边际，要么明确写“未实现/未计入”并给补算值。不得把源码例化当已实现/共享。
- **验证**：`resource-table.csv` 的 `u_camera` notes + `resource-baseline.md` §4.3 + 预算 marginal notes。

## 11. 时序域的写法（round1 F3 附）

- b11 全局 WNS `+0.015` 来自 `ddr_user` 200 MHz 域；`clk_a1` 187.5 MHz 域为 `+0.059`。
- 引用跨域 WNS 必须写“全局/某域”，不能把跨域值当 A+ 187.5 MHz 域结论；b6/b10 的 `+0.119/+0.103` 才是 `clk_a1` 域。

## 12. 测试脚本的硬编码期望（round1 复跑 T1）

- round0 的 `independent_verify.py` line 335 对 marginal 与 marginal_2ddr 硬编码 `LUT6_dev=23,488`，line 363 又要求 `25,709`，两者互斥；F1 修复后 T1 必然在 `budget_marginal`/`budget_marginal_2ddr` 报错。
- 这不是数据缺陷；r1 复测前测试者需把 T1 的期望 tuple 更新为 TD 值（25,709），并保留 line 363 作为恒等式检查。
- 开发不得修改 test-reports；只在 result-r0 记录该脚本缺陷与影响。
