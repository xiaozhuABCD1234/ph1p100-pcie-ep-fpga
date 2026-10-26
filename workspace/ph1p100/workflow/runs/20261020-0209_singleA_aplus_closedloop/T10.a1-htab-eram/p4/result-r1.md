# T10.a1-htab-eram r1 — 字面量阈值比较改造成功（违例端点 40→3、TNS -4.909→-0.465），但 WNS -0.245 仍 <0；综合 2/2 用尽 → blocked（未布线）

- task_id `T10.a1-htab-eram` | round **r1**（r0 的修复轮，同一包）
- 日期 2026-10-22 | 离线 synthetic；TD **2/2 会话**（约 3 min）、综合 **2/2**、布线 **0/1**、bitgen 0、无 .bit/CWC/下载/Flash
- 基准/复用候选：`b374f6fc…7b6d`（r0）；frame `18d51b1b…1cbe`、SDC `227dd39e…6311` 未改
- 冻结候选：`3326a1fae89cd35d86acc44701937970cdc6edece4abb91996325c896c82e532`
- **唯一判定：blocked。** 只改字面量阈值比较，功能逐位不变；综合 s2 **SWNS -0.245 / STNS -0.465 / 3 个违例端点**（r0 为 -0.146 / -4.909 / 40 个），仍低于 **WNS ≥ 0** 的布线门槛。

## 1. 本轮改动（只动 `cand_bits + litlen` vs `thresh_lit`）

### 1.1 尝试 1（`06d59a9d`，已作废）：17 位低半和
把 `(cand_bits + {28'd0,litlen}) >= thresh_lit` 改成
`{1'b0,cand_bits[15:0]} + litlen >= {1'b0,thresh_lit[15:0]}`（17 位和，进位精确；`MAX_BLOCK=4800 → stored_cost ≤ 38,442、thresh_lit ≤ 38,450、cand_bits < thresh_lit`，故 16 位足够）。
- 综合 s1：SWNS **-0.722**、STNS -18.177、slice 2876、ERAM 26、reg 1546。字面量路径下降了，但 bm_a_rd→state.ce 被综合重新排成 5.988 ns / 6 级 → 反而更差，作废。

### 1.2 尝试 2（`3326a1fa`，冻结）：预计算 thresh_lit−8 / thresh_lit−9
- 字面量是字节，`litlen` 只可能是 8（w0<144）或 9；`cand_bits + litlen >= thresh_lit ⟺ cand_bits >= thresh_lit − litlen`。
- 新增寄存器 `thresh_lit8 = thresh_lit − 8`、`thresh_lit9 = thresh_lit − 9`，在 `thresh_lit` 的三个赋值点同步更新（S_WAIT、S_SCAN 字面量通过、S_MCHK），复位/abort 清 0。
- 比较改为 `lit_ge = (litlen==4'd9) ? (cand_bits >= thresh_lit9) : (cand_bits >= thresh_lit8)`。
- 精确性：`thresh_lit ≥ 43 > 9` 无下溢；`thresh_lit8/9` 与 `thresh_lit` 同拍更新，比较使用的就是当前阈值。`litlen` 的 8/9 由 `lit_len({1'b0,w0})` 唯一决定。
- 效果：字面量路径从关键路径消失；综合 s2 **SWNS -0.245、STNS -0.465、仅 3/4640 个违例端点**，slice 3030、ERAM 26、reg 1626、DRAM LUT 32。

## 2. 功能等价（全绿，且与 r0/基准逐位一致）

| 项 | 结果 | 证据 |
|---|---|---|
| P2 | **13/13 PASS**、0 mismatch、`vlog 0/0`、bp/gapbp/abort/reset 全过 | `r1/p2/result.json`、`r1/p2/logs/vlog.log` |
| P2 等价 | **13/13 stream_sha256、stream_len、run_cycles 与 r0 完全相同** | 逐例比较 |
| P2 comp | **355,261 cycles / 81.067 MB/s**（红线 370,370） | `r1/p2/result.json` |
| P3 | **20/20 PASS**、`failures=[]`、0 mismatch、0 X、`vlog 0/0` | `r1/p3/result.json`、`r1/p3/logs/vlog.log` |
| 1080p | 4,677,945 / 4,866,587 / 4,744,596 / 4,678,533，**与 r0 逐周期相同**（门槛 6.25M） | `r1/p3/result.json` |
| stored | 各例 `worst_stored_bytes` 与 r0 相同（1080p 2,594,706），未增大 | 同上 |

结论：阈值改写是**精确等价**的，无周期/码流/上界变化；P2/P3 各复跑一次均通过。

## 3. G2 综合（2/2 次用尽）

| tag | 候选 | SWNS | STNS | 违例端点 | slice | ERAM | reg | DRAM LUT | 最差路径 |
|---|---|---|---|---|---|---|---|---|
| s1 | `06d59a9d`（17 位和） | -0.722 | -18.177 | 39 | 2876 | 26 | 1546 | 32 | bm_a ERAM clk2q→bm_a_rd→S_EXT 决策→state.ce 5.988 ns / 6 级 |
| s2 | `3326a1fa`（冻结） | **-0.245** | **-0.465** | **3/4640** | 3030 | 26 | 1626 | 32 | **bm_b ERAM clk2q→S_EXT 字节比较→ext_zero_r_reg.d 5.514 ns（cell 3.089/net 2.425）/ 5 级** |

- 门槛：WNS ≥ **0**（目标 +0.3）、TNS ≥ 0、slice ≤71,680、ERAM 与实例相符。实测 WNS -0.245 <0 → **不布线**。
- 与 r0 对比：违例端点 40→3、TNS -4.909→-0.465（改善）；WNS 数值 -0.146→-0.245（因为字面量路径修掉后，暴露出更窄但更深的一条 bm_b→flag 路径）。**剩余 3 个端点全部是 S_EXT 的 `ext_zero_r/len_cap_r` 更新**：这两个 flag 只在“字节匹配且继续扩展”的 else 分支里更新，使能依赖 bm_b_rd 比较，于是继承了 ERAM clk2q 1.5 ns。
- ERAM 26 = bm 8+8 + cmem 4 + smem 4 + htab 4；core ERAM 22；DRAM LUT 32；资源一致。

### TD 异常（诚实记录）
s2 综合的父 tcl 在 `wait_run syn_1` 处打印 `PRJ-8806 ERROR: Run syn_1 has exited unexpectedly`，tcl 在复制/解析/门控段之前退出。但 `a1_ht_r1_Runs/syn_1/{run.log, flow.status, a1_ht_r1_gate.timing, a1_ht_r1_gate.area, a1_ht_r1_gate.db}` 显示 opt_gate 已完整跑完（37 s、4 条命令、峰值 581 MB），报告已生成。已手工把 timing/area/flow.status/run.log 复制为 `syn_gate_*_s2.rpt`、`syn_flow_status_s2.rpt`、`syn_run_s2.log`。这是 TD run 状态检测异常，不是综合缺结果；原始报告完整可复核。未启动布线或 bitgen。

另：`00_syn_then_route.tcl` 的 `#dram` regexp 已在 r0 修复并沿用——所有解析变量先初始化（`set syn_dram -1`），`#dram lut` 用 `if {[regexp ...]}` 保护；本轮 s1/s2 均未触发该错误（s2 的中断是 `wait_run` 的 PRJ-8806，不是 regexp）。

## 4. 预算与停止依据

| 项 | 用/上限 |
|---|---|
| TD 会话 | **2/2**（s1 42 s、s2 40 s 综合；总墙钟约 3 min） |
| 综合 / 布线 | **2/2** / **0/1** |
| bitgen / .bit / 下载 / Flash | 0 / 0 / 0 / 0 |
| 开发 | 约 35 min / 20 calls（低于 75 min / 40 calls） |

停止依据：dispatch `Synth WNS <0 -> do not route`、`2 sessions/75 min 或 2 synth attempts exhausted -> stop`、`Any needed change outside the 32-bit literal threshold path -> stop`。剩余 3 个端点的修法（把 S_EXT flag 更新移出比较相关的 else 分支/提前一拍）属于 r0-step-2 的扩展逻辑，不在 r1 授权的字面量路径内；且会话/综合均已用尽 → blocked。

## 5. 最小下一步（交规划）

- 只差 3 个端点、0.245 ns。唯一有证据的修法：`S_EXT` 里 `ext_zero_r <= (ext_rem==13'd1)`、`len_cap_r <= (len_r==9'd256)` 目前只在“字节匹配且未停止”的 else 分支更新，使能带 bm_b_rd 比较。由于这两个 flag 在每次命中时都会重装、离开 S_EXT 后是 don't-care，可把它们的更新改为 **S_EXT 内无条件**（或提前一拍由 ext_rem/len_r 寄存器直接算），从而把 bm_b ERAM clk2q 从 flag D 路径移除；预计释放 1.1~1.5 ns，足以过 WNS ≥0。该改动在 r1 授权范围之外，需规划/用户明确。
- 保持本轮字面量改写（`thresh_lit8/9`）不变；它的 16 位范围证明继续有效。
- 需要新的综合/布线预算（本轮 2/2 会话、2/2 综合已用尽）。综合后 WNS≥0 再 route 1 次，布线后单独 report_cdc/check_timing。

## 6. 回退

- 工作树 = `3326a1fa`。回 r0 候选：把 `r0/candidate-b374f6fc.a1_deflate_core.v` 覆盖上游 core；回基准：`r0/base-1dca732b…v`。frame/SDC 未改。
- 只回退本轮：按 `r1/candidate.diff` 反向（r1b → r0 b374f6fc）；或用两个 patch 脚本的逆替换。

## 7. 复现

```powershell
# 仿真（P:=项目根，W:=包 r1）
powershell -NoProfile -ExecutionPolicy Bypass -File upstream\ph1p100-pcie-ep-fpga\tools\codec\run_p2_htab_eram_r1.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File upstream\ph1p100-pcie-ep-fpga\tools\codec\run_p3_htab_eram_r1.ps1
# TD（T:=包 r1\td，Y:=项目根；先 tools\td\td_env.ps1）
powershell -NoProfile -ExecutionPolicy Bypass -File tools\td\td_env.ps1 -Force -TdDir "workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-htab-eram\r1\td"
cd T:\; $env:A1_TD_TAG="s2"; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe T:/00_syn_then_route.tcl
```
