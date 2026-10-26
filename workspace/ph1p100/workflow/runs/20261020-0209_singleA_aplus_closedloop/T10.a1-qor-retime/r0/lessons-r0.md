# T10.a1-qor-retime r0 lessons（可复用根因/触发/修正/验证入口）

## 1. 结论速览（本轮实测）
- 两组固定策略各 1 综合 + 1 布线：**组 1（retiming + phys_opt）routed −0.039 / 45 端点**；**组 2（performance map/place QoR）routed −0.747 / 188 端点**；基线 bm-addr `35ea7364` 为 −0.087 / 27 端点。**均未达零违例且 ≥ +0.2 ns**。
- 组 1 是二者中最佳：Routed Fmax 184.502 → **186.150 MHz**，最差违例 −0.087 → −0.039；但端点 27→45（更多 −0.03…−0.04 小锥暴露）。
- 组 2 的 `map_mode logic_level_prior + map_strategy 2 + place effort high/opt_timing ultra` 在本设计上**布线后回退**（综合 +0.109 与基线持平，route 后 −0.747）——该组合不宜再用；若再用 place QoR，应单变量、小步验证。

## 2. 可复用事实（TD Release_2026.2 实测）
1. **全局 retiming 开关可用且无 RTL 改动**：`set_param -run syn_1 rtl retiming on` → `PRJ-1105 ... rtl::retiming::on succeed`；syn run.log 出现 `SYN-3005 ... backward retimed`，`#reg +39`。这是“RTL 冻结下做 retiming”的正确入口。
2. **phys_opt 由 route 步骤内部调用**：`set_param -run phy_1 route post_route_opt ultra` 使 route 步骤执行 `phys_opt -post_route -effort high`（本设计 717.98 s wall；默认 auto 时是 `-effort low`，27 s）。注意 **ultra 在日志中的命令仍是 `-effort high`**——不要把“ultra”写成 `-effort ultra` 的证据。
3. `postrt_opt_loc` / `postrt_opt_extra_round`：`set_param` 不报错但**无 PRJ-1105 确认行**；不要把“无报错”当生效证据（本包按未确认处理）。
4. **`report_cdc` 在 TD 2026.2 不存在**（`invalid command name`）；静态单时钟证据 = routed timing summary（CC-From/To=no）+ `report_clock_utilization` + `check_timing`。`report_timing -max_paths 1000` 也不支持（`USR-8011 invalid option -max_paths`）。
5. **write_verilog 的层级差异**：syn gate db → `AL_MAP_SEQ` 原语（可扫 clk/sr/ce 引脚）；routed pr db → 触发器已打包进 `LSLICE/MSLICE`，无 `AL_MAP_SEQ`。跨域静态检查应在 **gate 级**做（retiming 发生在该级），布线级用 STA/clock 报告佐证。
6. **参数/证据落点**：`report_param -file params_*_after.tcl`（非默认参数）、run.log 的 `Print * Property` 表（Settings vs Default）、console 的 `PRJ-1105` 行，三者互补；`report_param -file` 在项目早期（未 open design）不产出文件（本包 g1/g2 的 `params_*_before.tcl` 未生成）。
7. **耗时参考**：综合 ~50 s；默认 phy ~2m19s；`post_route_opt ultra` 的 phy ~13m23s（其中 phys_opt 11m57s）。会话预算按 ≥20 min 准备更稳。

## 3. 触发/根因（为什么仍差 ~0.24 ns）
- 组 1 的 45 个违例仍是 **core 内 flop→flop 小锥**（`pos_reg[3]`、`lim2_reg[6]`、`dtot_r_reg[0]`、`pos_reg[1]` 等，−0.03…−0.04），与 bm-addr 的剩余类别相同；retiming 只搬动了 `adler_fold_b_reg` 等少量寄存器，对这批小锥作用有限。
- 纯策略手段（retiming + phys_opt / map/place QoR）**不足以**把 −0.087 推到 +0.2（需 +0.287 ns）；局部 RTL 流水已在前序 r1–r10 用尽，说明剩余缺口需要**新微架构或更大器件**，而不是继续换实现策略。

## 4. 验证入口（下次直接复用）
- 组 1 策略脚本：`r0/td/g1/01_syn_route_g1.tcl`（`T:`=g1、`Y:`=项目根、`td_commands_prompt.exe T:/01_syn_route_g1.tcl`、`*>` 落 console 日志；stop marker 在 `.opt_route.begin.f` 出现后落 `.stop.f` 停在 bitgen 前）。
- 组 2：`r0/td/g2/01_syn_route_g2.tcl`。
- 哈希复核：`r0/hash-checks.txt`（运行前逐次记录）；策略生效证据：`console_g*.log` 的 `PRJ-1105`、`a1_qor_g*_Runs/{syn_1,phy_1}/run.log`。
- 静态跨域扫描：`analysis/scan_netlists.py <out> <netlist...>` → `analysis/netlist_scan.txt`（对 gate/routed netlist 逐文件统计 SEQ、clk/sr/ce 网络集合与两两对比）。
- 判定口径：Routed 零违例 + setup ≥ +0.2 ns + hold ≥0；本包两组均 FAIL，不得以“更接近”或综合 +0.113 代替。

## 5. 边界与未测
- 未改 RTL/SDC、未 bitgen/`.bit`/下载/Flash；未跑门级仿真/形式等价（预算内无已建立流程），以 gate 级 netlist 静态扫描替代并写明。
- 组 1 的 `postrt_opt_loc/extra_round` 未确认生效；`phys_opt -register_opt/-force_replication_on_nets` 等显式子选项**未单独调用**（不是 run 参数，未建立 hook），本包只用了 route 内建 `phys_opt`。
- 后续若要继续：需用户明确新授权（更大器件 / 新微架构包）；不得用新 ID/改名/新 run 绕“失败即收尾”。
