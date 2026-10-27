# T10.a1-bm-prefetch r2-waive（route-only）— **BLOCKED：Routed setup 违约（SWNS −0.421 / STNS −23.367）**

- task_id `T10.a1-bm-prefetch` | revision **r2-waive** | 2026-10-22 | run `20261020-0209_singleA_aplus_closedloop`
- 对象（未改）：core `df6124d4aa48725e…14a9c`、frame `18d51b1b…1cbe`、SDC `227dd39e…6311`（开工逐个复算一致）
- 无综合（synth 0）、无 RTL 改动、route 1/1（phy 1m30s）、bitgen not_run、`.bit/.cwc` = 0、无下载
- **判定 FAIL**：Routed WNS/TNS < 0 → 按 dispatch 立即停止，保留 `r2 0b084317` 为最佳回退，不自动 r3

## 1. 执行（2 次 TD 调用，均为 read/route，无综合）

| # | 动作 | 结果 |
|---|---|---|
| 1 | `02_route_only.tcl`：`import_device` → `open_project` → `launch_runs phy_1` → 12 s 早失败检查（`SETTINGS_CHECK device=ph1_100p.db package=PH1P100SBG484`）→ `.opt_place.begin.f` 出现即通过（38 s）→ `.opt_route.begin.f` 出现后写 `.stop.f`（停于 bitgen 前）→ `wait_run` 完成 → `import_db a1_bp_r2_pr.db` | `PRJ-1406 Run phy_1 finished`，106 s；`route_flow.status`：place 36s / route / fix_hold 1s / phys_opt 1s，总 **1m30s** |
| 2 | `03_route_reports.tcl`：在**已布线 DB** 上 `import_db` → `update_timing -mode final` → 三份必需报告与定向报告直接 `-file` | 11 s，全部 `*_EXECUTED`（`report_cdc`/`report_clocks` 不存在，已记录） |

> 说明：第 1 次调用已把报告名写成 `../r2-waive/...`，TD 在该会话内无法打开该相对路径（`USR-8002`），因此追加了**只读报告**第 2 次调用（无综合/无布线/无 bitgen，11 s）。TD 墙钟共约 2 分钟，route 仍为 1/1、synth 0；属"会话数 1→2"的轻微会计偏差，如实记录。

## 2. Routed 结果（全门槛）

| 项 | 值 | 门槛 | 结论 |
|---|---|---|---|
| SWNS / STNS | **−0.421 ns / −23.367 ns** | ≥0 | **FAIL** |
| 违约端点 | 报告 20 条端点中 **10 条为负**（每组 10 端点 × 1 组 `clk -> clk`） | 0 | **FAIL** |
| HWNS / HTNS | **+0.020 ns / 0.000 ns** | ≥0 | pass |
| Path group | 仅 `clk -> clk`；`CC-From/CC-To` 无跨域 | 单组 | pass |
| 资源 | `#slice 3,016/71,680`、`#lut6 2,941`、`#reg 1,653`、`#eram 26/300`、`#dram lut 32`、`#io 121/286`、`#dsp 0` | 器件内 | pass |
| Confidence / 角 | `Routed` / `Both (Slow and Fast)` / `CRPR Yes` | — | pass |
| bitgen | not_run；`_pr.bit` 不存在；run 内 `.bit/.cwc`=0 | not_run | pass |
| CDC | 静态单时钟证据（`cdc-static.md`） | 证据 | 见该文件 |

### 2.1 违约锥（10 条，全部新增/转移，已不是本包目标锥）

```
-0.421  htab_p3v ERAM clk2q → bm_b_syn_41.addrb[11]
-0.407  pos_reg[1] → bm_b_syn_41.addrb[10]
-0.406  pos_reg[1] → bm_b_syn_41.addrb[12]
-0.362  htab_p3v ERAM clk2q → bm_b_syn_39.addrb[11]
-0.359  htab_p3v ERAM clk2q → bm_b_syn_37.addrb[11]
-0.347  pos_reg[1] → w0_reg[1].ceb
-0.332  pos_reg[1] → w1_reg[2].ceb / w0_reg[0].ceb
-0.329  pos_reg[1] → bm_b_syn_41.addrb[5]
-0.322  pos_reg[1] → bm_a_syn_41.addrb[9]
```

- 主锥是 **`htab_p3v` ERAM clk2q（hent 有效位/pos 字段）→ `bm_b` 读地址（S_SCAN 的 `hent[49:37]` 投机读）→ bm_b ERAM 地址**，以及 **`pos_reg[1] → bm 读地址 / w0/w1 装载 CE**（位置计数到两条 bm 端口地址与窗口装载使能）。
- **本包目标的 `bm_a ERAM clk2q → hash3 → htab 地址 → CE` 锥已在布线后消失**：`bm_a` 在本轮 routed 报告中只作为**终点**（`bm_a_syn_41.addrb`）出现，不再作为起点。上一轮（hit-pipe r1）该锥为 −0.577 主导全部 10 条端点。
- 数值上也有改善：SWNS 由 −0.577 → **−0.421**，STNS −57.504 → **−23.367**，违约端点 311 → 10。

## 3. 定向 ERAM clk2q 端点枚举（覆盖范围与限制）

- 尝试 `report_timing -from [get_pins -hierarchical {*bm_a*}]`、`{*bm_b*}`、`{*htab*}`、`-from [get_cells -hierarchical ...]`、`-max_paths 3000`。前四条**命令执行成功**，但产出的 142,283 B 文件与无过滤的 `report_timing` **逐字节相同**（`45A4D658BD5B5528` / `B18C7771236E05D2` 同长度同内容）→ **TD 2026.2 忽略了 `-from <pin/cell 列表>` 过滤**；`-max_paths` 不可用。
- 因此"全部 ERAM clk2q 起点端点 ≥ +0.9"的**穷举证明不可得**，本轮覆盖 = routed `report_timing_summary` 中出现的 20 条端点（`Report Scheme: 10 end point(s) per path group`，1 组）。在该集合内，ERAM clk2q 起点仅 `htab_p3v_syn_13.clkb`（−0.421/−0.362/−0.359）与 `blk_tag_reg / s1_pos_r_reg`（+0.020，作为起点走 htab_tag 写口）；**无** `bm_a`/`bm_b` ERAM clk2q 起点。
- 结论：不能声称"穷举通过"；但可声称"报告集合内不存在 slack<+0.9 的 bm_a/bm_b ERAM clk2q 起点"，且**整体 Routed 已违约**，故该子项不再是走向 G2 PASS 的可行路径。

## 4. 已做 / 未做

已做：route-only 1 次（无综合）；布线后三份必需报告直接 `-file`；定向端点尝试与覆盖边界；静态单时钟 CDC 证据；资源/bitgen/route 流程状态核对。
未做（因 FAIL 立即停止）：不重布线、不改 RTL/SDC、不综合、不 bitgen、不下载、不做门级仿真。

## 5. 最小下一步（交规划，不在本包执行）

1. 新失败锥与 bm 预取无关：`hent[49:37] → bm_b.addrb` 是 S_SCAN 的投机 bm_b 读；可考虑（新包）把该投机读的地址提前一拍寄存，或取消投机读改为命中拍后再取——都会动到 S_EXT 首字节时序，需像本包一样做完整 G1+P2/P3 逐位回归。
2. `pos_reg[1] → bm_a/bm_b.addrb + w0/w1.ceb`（−0.407/−0.347）属位置计数到地址/装载的短锥，可用预计算 `pos±k` 或寄存地址解决，同属新包。
3. 保留 `r2 0b084317` 为最佳回退；本候选 `df6124d4` 的 G1 全绿证据仍有效，可用于后续结构包的功能基线。

## 6. 恢复入口

`T10.a1-bm-prefetch/r2-waive/`（`result-r2-waive.md`、`cdc-static.md`、`lessons-r2-waive.md`、`routed_*.rpt`、`directed_*.rpt`、`phy_pr_timing_flow.rpt`、`route_flow.status`、`phy_area_raw.rpt`、`route_console.log`、`reports_console.log`、`phy_run.log`）与 `r2/td/`（`02_route_only.tcl`、`03_route_reports.tcl`、`a1_bp_r2_Runs/phy_1/a1_bp_r2_pr.db`）。
