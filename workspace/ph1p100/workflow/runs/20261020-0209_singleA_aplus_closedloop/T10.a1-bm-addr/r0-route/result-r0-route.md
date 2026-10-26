# T10.a1-bm-addr r0-route（最后一次 route-only）— **FAIL：Routed setup 违约（SWNS −0.087 / STNS −1.109，27 个违约端点）**

- task_id `T10.a1-bm-addr` | revision **r0-route** | 2026-10-22 | run `20261020-0209_singleA_aplus_closedloop`
- 对象（**开工复算一致，未改**）：core **`35ea7364…0942`**（75,877 B）、frame `18d51b1b…1cbe`、SDC `227dd39e…6311`
- **无综合（synth 0）**、无 RTL 改动、**route 1/1**（phy 2m5s）、bitgen not_run、`.bit/.cwc` = 0、无下载
- 判定 **FAIL**：Routed WNS/TNS < 0 → 按 dispatch 立即停止，交规划收尾 T10 为 **3/4 PASS + 1 ⚠**，保留 r2 `0b084317`，无 r1

## 1. 执行（1 会话 / 2m21s，route-only）

| 项 | 结果 |
|---|---|
| 会话 | `T:/`=`r0/td`、`Y:`=项目根（`td_env.ps1 -Force`）；1/1 会话，TD 墙钟 **2m21s** |
| harness | `import_device ph1_100p.db -package PH1P100SBG484 -speed 3` → `open_project a1_bm_addr.al`（`Path="T:/"`，syn_1 checkpoint 已在）→ `reset_run`/`launch_runs phy_1` |
| 早失败检查 | `syn_1/settings.cfg`：device=`ph1_100p.db`、package=`PH1P100SBG484`；`phy_1/settings.cfg` 非空；12 s 内 `OPT_PLACE_STARTED`；run.log 无 `PRJ-8001` |
| 停比特流 | `.opt_route.begin.f` 出现（40 s）即写 `.stop.f` → `PHY_STOP_MARKER_SET`；run 结束 `NO_BIT_FILE` |
| 流程时间 | place 38 s / route 59 s / phys_opt 27 s / fix_hold 1 s，总 **2m5s**；`PRJ-1406 Run phy_1 finished` |
| 报告 | `import_db a1_bm_addr_pr.db` → `update_timing -mode final` → 全部报告 **工具直接 `-file`** 写入 `r0/td/`（`*_EXECUTED`） |

## 2. Routed 结果（全门槛）

| 项 | 值 | 门槛 | 结论 |
|---|---|---|---|
| **SWNS / STNS** | **−0.087 ns / −1.109 ns** | ≥ 0 | **FAIL** |
| **违约端点** | **27** setup（`NUM_FEPS 27`，共 4,555 端点；报告集 20 条中 10 条为负） | 0 | **FAIL** |
| HWNS / HTNS | **+0.023 ns / 0.000 ns** | ≥ 0 | pass（0 hold 违约） |
| Path group | 仅 `clk -> clk`；`CC-From/CC-To` = `no/no` | 单域 | pass |
| Confidence / 角 | `Routed` / Both (Slow and Fast) / CRPR Yes；STA coverage 96.41% | — | pass |
| 资源 | `#slice 2,993/71,680`、`#lut6 2,912`、`#reg 1,664`、`#eram 26/300`（`#eram20k 26`）、`#dram lut 32`、`#io 121/286`、`#dsp 0` | 器件内 | pass |
| bitgen | not_run；`.bit/.cwc`=0 | not_run | pass |
| CDC | 静态单时钟证据见 `cdc-static.md`；`report_cdc`/`report_clocks`/`report_exceptions` 在 TD 2026.2 **不存在**（`invalid command name`，已按原文留证，不作 signoff） | 证据 | 见该文件 |

### 2.1 报告集 10 条违约端点（全部为**无 ERAM 起点**的 flop→flop/框架锥）

```
-0.087  u_core/adler_red_st_reg[2]  -> u_dut/smem.addrb[12]          (frame_top smem 读地址, 6 级)
-0.084  u_core/pos_reg[4]           -> u_core/raddr_reg[12].d        (5 级)
-0.084  u_core/sdata_ptr_reg[1]     -> u_core/state_reg[3].ceb       (7 级)
-0.080  u_dut/eidx_reg[0]           -> u_core/bm_b.dia[0]            (3 级)
-0.067  u_core/dtot_r_reg[1]        -> u_core/praddr_reg[10/12/9].d  (6 级，3 条)
-0.061  u_core/blk_final1_reg       -> u_core/raddr_reg[0].ceb       (5 级)
-0.058  u_core/hp_r_reg[10]         -> u_core/bm_a.addrb[12]         (6 级)
-0.057  u_core/pos_reg[1]           -> u_core/bm_a.addrb[10]         (5 级)
```

### 2.2 与本包目标锥的对比（同一工具、同一报告口径）

| 指标 | r2-waive（`df6124d4`） | **r0-route（`35ea7364`）** |
|---|---|---|
| SWNS / STNS | −0.421 / −23.367 | **−0.087 / −1.109** |
| 违约端点（组统计） | 178 | **27** |
| 报告内 `ERAM (clk2q)` 起点端点 | 3 条（`htab_p3v → bm_b.addrb[11]`） | **0 条（`ERAM (clk2q)` 全文 0 次）** |
| `htab_p3v → bm_b.addrb` / `pos → w0/w1.ceb` | −0.421 / −0.347 / −0.332 | **已消失** |
| 报告内 `pos_reg[1] → bm_b.addrb` | −0.407 / −0.406 | **已消失**（改为 `bm_a.addrb[10]` −0.057） |
| slice / reg / ERAM | 3,016 / 1,653 / 26 | 2,993 / 1,664 / 26 |

- 结论：**本包目标（地址/写使能锥，尤其 ERAM clk2q 起点类）已从 routed 关键集消失**；剩余 27 条违约端点是另一类小锥（`adler_red_st→smem.addrb`、`sdata_ptr→state.ceb`、`dtot_r→praddr`、`pos/hp_r→bm_a.addrb` 等），单条 −0.057…−0.087。
- 但派发闸门是 **Routed 零违约**，且未获豁免（仅豁免了 +0.5 预布线 synth 门槛）→ 判定 FAIL，route 1/1 用尽，不重布线、不重综合、不改 RTL。

## 3. 完整性

- 输入哈希开工复算：core `35ea7364…`、frame `18d51b1b…`、SDC `227dd39e…`；`a1_eng_top.v 544cecfc…`；syn_1 checkpoint 沿用 r0 综合。
- 报告均为工具 `-file` 直接写入 `r0/td/`（`routed_timing_summary.rpt`、`routed_timing_status.rpt`、`routed_area.rpt`、`routed_check_timing.rpt`、`routed_clock_utilization.rpt`、`routed_qor.rpt`、`routed_timing.rpt`、`route_flow.status`、`phy_pr_timing_flow.rpt`、`route_console.log`）；`r0-route/` 内为**逐字节副本**（SHA256 见 manifest，权威路径仍是 `r0/td/`）。
- 无 `.bit/.cwc`、无下载、无 Flash、无 QoR/seed/时钟/exception 变更、无 frame/SDC 编辑。

## 4. 收尾（交规划，不在本包执行）

1. T10 按 `dev-plan.md §36.5` 收口：**3/4 PASS + 1 ⚠**（G1/功能/吞吐全绿；G2 时序未闭，Routed −0.087/27 端点）。
2. 最佳回退：r2 `0b084317`（routed −0.436）与 bm-prefetch/bm-addr 全部证据保留；工作树 core 保持 `35ea7364`（本包 G1 全绿候选）。
3. 剩余 −0.087 类别**不属于**地址/CE 锥，若继续需新授权（`adler_red_st → smem.addrb[12]` 跨 frame/core 边界、`state.ceb` 使能锥、`praddr` 更新锥）；本包不再扩轮。

## 5. 恢复入口

`T10.a1-bm-addr/r0-route/`（本文件、`CANDIDATE-MANIFEST-bm-addr-r0-route.json`、`cdc-static.md`、`lessons-r0-route.md`、`routed_*.rpt`、`route_flow.status`、`route_console.log`）与 `T10.a1-bm-addr/r0/td/`（`02_route_only.tcl`、`a1_bm_addr_Runs/phy_1/a1_bm_addr_pr.db`）。
