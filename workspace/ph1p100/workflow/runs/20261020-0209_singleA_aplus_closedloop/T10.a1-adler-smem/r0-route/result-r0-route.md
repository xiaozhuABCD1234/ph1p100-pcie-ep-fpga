# T10.a1-adler-smem r0-route（最后一次 route-only）— **FAIL：Routed setup 违约（SWNS −0.541 / STNS −52.866，299 端点）**

- task_id `T10.a1-adler-smem` | revision **r0-route** | 2026-10-22 | run `20261020-0209_singleA_aplus_closedloop`
- 对象（**开工复算一致，未改**）：core **`611ad704…90d7`**（76,366 B）、frame `cc330814…c594`（24,301 B）、SDC `227dd39e…6311`、`a1_eng_top.v 544cecfc…f9aa`
- **无综合（synth 0）**、无 RTL 改动、**route 1/1**（place 41 s / route 54 s / phys_opt 1 s / fix_hold 1 s，1 会话约 1m38s 流程）
- 判定 **FAIL**：Routed WNS/TNS < 0 → 按 dispatch 立即停止，交规划收尾 T10 为 **3/4 PASS + 1 ⚠**，保留 r2 `0b084317`、bm-addr `35ea7364`、adler-smem `611ad704` 证据；无 r1

## 1. 执行（1 会话，route-only）

| 项 | 结果 |
|---|---|
| 会话 | `T:/`=`r0/td`、`Y:`=项目根（`td_env.ps1 -Force`）；1/1 会话 |
| harness | `import_device ph1_100p.db -package PH1P100SBG484 -speed 3` → `open_project a1_adler_smem.al`（`Path="T:/"`）→ `launch_runs phy_1 -jobs 4` |
| 综合检查点 | `syn_1/a1_adler_smem_gate.db` 存在（`95724bc4…9f8b`），syn 0 |
| 早失败检查 | syn `settings.cfg`：device=`ph1_100p.db`、package=`PH1P100SBG484`；phy `settings.cfg` 2 s 内非空且同 device/package；2 s 见 `.opt_place.begin.f`；run.log 无 `PRJ-8001` |
| 停比特流 | `.opt_route.begin.f` 出现（44 s）即写 `.stop.f` → `PHY_STOP_MARKER_SET`；流程在 fix_hold 后结束，`NO_BIT_FILE` |
| 报告 | `import_db a1_adler_smem_pr.db` → `update_timing -mode final` → `report_timing_summary`/`timing_status`/`area`/`check_timing`/`clock_utilization`/`timing`/`qor` 全部**工具直接 `-file`** 写入 `r0/td/`，`r0-route/` 为逐字节副本 |

## 2. Routed 结果（全门槛）

| 项 | 值 | 门槛 | 结论 |
|---|---|---|---|
| **SWNS / STNS** | **−0.541 ns / −52.866 ns** | ≥ 0 | **FAIL** |
| **违约端点** | **299 setup**（`NUM_FEPS 299`，共 4,572 端点） | 0 | **FAIL** |
| HWNS / HTNS | **+0.024 ns / 0.000 ns** | ≥ 0 | pass（0 hold 违约） |
| Path group | 仅 `clk -> clk`；`CC-From/CC-To` = `no/no` | 单域 | pass |
| Confidence / 角 | `Routed` / Both (Slow and Fast) / CRPR Yes；STA coverage 96.30% | — | pass |
| 资源 | `#slice 3,005/71,680`、`#lut6 2,923`、`#reg 1,679`、`#eram 26/300`（`#eram20k 26`）、`#dram lut 32`、`#io 121/286`、`#dsp 0` | 器件内 | pass |
| bitgen | not_run；`.bit/.cwc`=0 | not_run | pass |
| CDC | 静态单时钟证据见 `cdc-static.md`；`report_cdc`/`report_clocks`/`report_exceptions` 在 TD 2026.2 **不存在**（`invalid command name`，已按原文留证，不作 signoff） | 证据 | 见该文件 |

### 2.1 违约端点类别（报告集 10 条，全部为**冻结 core 锥**）

```
-0.541  u_core/ld_ptr_reg[10] -> smem.addrb[4]            (6 级；ld_ptr→in_ready→smem 读地址 mux)
-0.530  u_core/pos_reg[7]     -> u_core/bm_b.addrb[12]    (7 级；2 ADDER)
-0.514  u_core/pos_reg[1]     -> u_core/bm_b.addrb[12]    (7 级)
-0.481  u_core/add8_*         -> u_core/raddr_reg[3/4/5/7].ceb (6 级；4 ADDER)
-0.473  u_core/ld_ptr_reg[10] -> smem_syn_25.addrb[3]     (6 级)
```
- 与 r0 目标锥对比：`byte_k → smem_waddr_r`（r0 综合最差 +0.113）与 `adler_red_st → smem.addrb`（bm-addr routed −0.087）**均不在本报告集**；两处目标锥在本候选上已清除。
- 但本次布线把**冻结的 core bm 读地址 / raddr CE / ld_ptr→in_ready 锥**暴露成 −0.47…−0.54（bm-addr 同族路径当时为 −0.057…−0.058），退化来自本候选 netlist 的 place/route 结果（同一 harness、同一 `settings.cfg`、`-jobs 4`、无 QoR/seed 变更），单次 route 无法再调。

## 3. 完整性

- 输入哈希开工复算：core `611ad704…`、frame `cc330814…`、SDC `227dd39e…`；syn checkpoint `95724bc4…`、routed DB `16bbf6b9…`、place DB `15f04992…`（SHA 见 manifest）。
- 报告为工具 `-file` 直接写入 `r0/td/`；`r0-route/` 内为**逐字节副本**（SHA256 见 manifest，权威路径仍是 `r0/td/`）。
- 无 `.bit/.cwc`、无下载、无 Flash、无 QoR/seed/时钟/exception 变更、无 RTL/SDC 编辑。
- 工作树未改（本 revision 未改 RTL；route-only 不读 RTL，冻结候选在 `r0/td/*.v`）。

## 4. 收尾（交规划，不在本包执行）

1. T10 按 `dev-plan.md §39.4` 收口：**3/4 PASS + 1 ⚠**（G1/功能/吞吐全绿；G2 时序未闭，Routed −0.541/299 端点）。
2. 最佳回退：r2 `0b084317`（routed −0.436）与 bm-addr `35ea7364`（routed −0.087）；本轮最佳“接近”是 bm-addr 的 −0.087（27 端点）。
3. 剩余违例全部属于冻结 core 逻辑（bm 读地址、`raddr` CE、`ld_ptr→in_ready`），**不属于** adler/smem 写地址授权；若继续需用户明确新授权（core 地址锥或更大器件/QoR），本轮不再扩轮。

## 5. 恢复入口

`T10.a1-adler-smem/r0-route/`（本文件、`CANDIDATE-MANIFEST-adler-smem-r0-route.json`、`cdc-static.md`、`lessons-r0-route.md`、`routed_*.rpt`、`route_flow.status`、`02_route_only.tcl`）与 `T10.a1-adler-smem/r0/td/`（`a1_adler_smem_Runs/phy_1/a1_adler_smem_pr.db`、`syn_1/a1_adler_smem_gate.db`、`td_20261022_153905.log`、`phy_1/run.log`）。
