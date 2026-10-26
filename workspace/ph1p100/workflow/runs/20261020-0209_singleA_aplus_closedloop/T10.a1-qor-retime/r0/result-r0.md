# T10.a1-qor-retime r0 — **BLOCKED：两组固定 QoR/retiming 策略均未达 Routed 门槛（setup ≥ +0.2 ns）**

- task_id `T10.a1-qor-retime` | revision **r0** | 2026-10-22 | run `20261020-0209_singleA_aplus_closedloop`
- 授权：`dispatch-qor-retime.json`（用户 2026-10-22 批准 QoR/retime 边界：RTL/SDC 冻结、≤2 组固定策略、不随机 seed、失败即收尾）
- 判定 **BLOCKED**：两组各完成 1 综合 + 1 布线；**均未 Routed 零违例且 setup ≥ +0.2 ns**（组 1 最佳 −0.039 / 45 端点；组 2 −0.747 / 188 端点）；按 dispatch 无第 3 组、无 seed sweep，T10 保持 **3/4 PASS + 1 ⚠**
- 未改 RTL/SDC、未 bitgen、无 `.bit/.cwc`、无下载；未派测试者（无 PASS 可验）

## 1. 冻结输入（每次策略运行前复算，一致）

| 文件 | SHA256 | 结果 |
|---|---|---|
| core `a1_deflate_core.v` | `35ea736415c5fbfd28fabcf85b78e33275fb2507f8d30a070a95a17a41760942` | 与基线一致（g1/g2 运行前均复核，见 `r0/hash-checks.txt`） |
| frame `a1_frame_top.v` | `18d51b1b80002e3549b6afd74956cff9d323d0a0272a7a08d617365a01611cbe` | 一致 |
| SDC `a1_small_top.sdc` | `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311` | 一致（g1/g2 各一份逐字节副本） |
| bench `a1_eng_top.v` | `544cecfc2eb34a3ab5c03ebf3965730b4ce60b2ff73ac4c2ec2d87772faaf9aa` | 未改 |

工作树在两次运行前均持有上述冻结版本；本包**未修改工作树 RTL**。

## 2. 固定策略与实际执行（不随机 seed）

### 组 1 `retiming + phys_opt`（`r0/td/g1`，1 综合 + 1 布线）

写入 tcl 并在运行日志中确认：

```tcl
set_param -run syn_1 rtl retiming on            ;# PRJ-1105 Update param syn_1 rtl::retiming::on succeed
set_param -run phy_1 route post_route_opt ultra ;# PRJ-1105 ... route::post_route_opt::ultra succeed
set_param -run phy_1 route postrt_opt_loc 20
set_param -run phy_1 route postrt_opt_extra_round 4
```

- **retiming 实际生效**：syn run.log 有 `SYN-3005 ... backward retimed`（如 `adler_fold_b_reg[8..18]` → `*_bret_*` 复制寄存器）；综合 `#reg 1646 → 1685`（+39），slice 3,085→3,089。
- **phys_opt 实际命令**：route 步骤内执行 `phys_opt -post_route -effort high`（**717.98 s** wall）；`route post_route_opt ultra` 在 run.log 参数表中为 `ultra (*)`。
- **证据偏差（如实登记）**：`postrt_opt_loc 20`、`postrt_opt_extra_round 4` 经 `set_param` 无报错，但**没有** `PRJ-1105 Update param` 确认行（`set_param_update_lines.g1` 只含前两条）；不声称它们生效。

### 组 2 `performance mapping / placement QoR`（`r0/td/g2`，1 综合 + 1 布线）

```tcl
set_param -run syn_1 gate map_mode logic_level_prior ;# PRJ-1105 succeed
set_param -run syn_1 gate map_strategy 2             ;# PRJ-1105 succeed
set_param -run phy_1 place logic_level_opt on        ;# PRJ-1105 succeed
set_param -run phy_1 place effort high               ;# PRJ-1105 succeed
set_param -run phy_1 place opt_timing ultra          ;# PRJ-1105 succeed
```

route 保持默认（`post_route_opt auto`→`phys_opt -post_route -effort low`，1 s）。

## 3. 结果（同一 top/器件/187.5 MHz、同一 SDC、报告工具直接 `-file`）

| 项 | 基线 bm-addr `35ea7364` | **组 1** | **组 2** | 门槛 | 结论 |
|---|---|---|---|---|---|
| synth SWNS/STNS | +0.113 / 0 | +0.113 / 0 | +0.109 / 0 | — | 均完成 |
| synth slice / ERAM / reg / DRAM LUT | 3,085 / 26 / 1,646 / 32 | 3,089 / 26 / **1,685** / 32 | 3,189 / 26 / 1,646 / 32 | ≤71,680 | pass |
| **Routed SWNS / STNS** | −0.087 / −1.109 | **−0.039 / −0.645** | −0.747 / −51.133 | ≥ 0 且 ≥ +0.2 | **FAIL** |
| **违例端点（setup）** | 27 / 4,555 | **45 / 4,635** | 188 / 4,556 | 0 | **FAIL** |
| hold HWNS/HTNS | +0.023 / 0 | +0.024 / 0.000 | +0.020 / 0.000 | ≥ 0 | pass |
| Routed 资源 slice / lut6 / reg / ERAM / IO / DSP | 2,993 / … / 1,664 / 26 / 121 / 0 | 3,023 / 2,925 / 1,703 / 26 / 121 / 0 | 3,208 / 3,048 / 1,668 / 26 / 121 / 0 | 器件内 | pass |
| 报告 Fmax（min period） | 184.502 MHz (5.420) | **186.150 MHz (5.372)** | 164.474 MHz (6.080) | — | 诊断项 |
| Confidence / 角 / CRPR / coverage | Routed / Both / Yes / 96.41% | Routed / Both / Yes / 96.36% | Routed / Both / Yes / 96.20% | Routed | pass |
| bitgen / `.bit` / 下载 | not_run / 0 / 0 | not_run / 0 / 0 | not_run / 0 / 0 | not_run | pass |

- 组 1 把最差违例从 −0.087 推到 **−0.039**（Routed Fmax 184.5→186.2 MHz），但**端点 27→45**：更多小锥进入 −0.03…−0.04 区间，未过“零违例且 ≥ +0.2 ns”。
- 组 2 反而回退（−0.747 / 188 端点）：`map_mode logic_level_prior + map_strategy 2 + place effort high/opt_timing ultra` 在本设计上不利于布线后时序（综合 +0.109 与基线持平，但 place/route 结果变差）。
- 组 1 报告内最差起点：`u_core/pos_reg[3]`（−0.039）、`lim2_reg[6]`、`dtot_r_reg[0]`、`pos_reg[1]`×3；与 bm-addr 的剩余小锥同类（core 内 flop→flop，非 ERAM clk2q）。

## 4. 静态 CDC + 复位结构（retiming 不跨时钟/复位域）

- `report_cdc` 在 TD Release_2026.2 **不存在**（`invalid command name`，原文留证）；采用静态单时钟证据，不冒充 report_cdc。
- Routed 时序报告：唯一时钟 `clk` 187.512 MHz，`CC-From/CC-To = no/no`；`report_clock_utilization`、`check_timing` 实际执行（组合环 0，dummy node 1 = PH1P_PHY_LSLICE）。
- **netlist 静态扫描**（`analysis/scan_netlists.py` → `analysis/netlist_scan.txt`）：
  - gate 级（retiming 后）：组 1 **1,685 个 `AL_MAP_SEQ`，clk 引脚 100% 在 `clk_dup_1`**；组 2 1,646 个，同样 100% `clk_dup_1`。
  - **组 1（retimed）与组 2（未 retiming）的 clk 网络集合与 sr（复位/置位）网络集合完全相同**；SEQ 差 +39 即 retiming 复制/移动的寄存器，**未引入任何新时钟或新复位网络**。
  - sr 网络：`rst_n_dup_1567`（755/747）、`fifo_mem_i1_syn_2`（440）、未连接（245/214）及相同的常量/mux sr 网络。
  - routed 级 netlist 把触发器打包进 `LSLICE`（2,991）/`MSLICE`（32）宏，无 `AL_MAP_SEQ` 原语 → 布线级时钟结构以时序报告 + clock utilization 为准（如实说明，不夸大为原语级扫描）。
- 结论：retiming 只移动/复制同域寄存器；**未跨时钟域、未跨复位域**。

## 5. 功能证据（RTL 未变 → 复用并绑定哈希）

- core/frame/SDC 与 `T10.a1-bm-addr` r0 候选 `35ea7364` **逐字节相同** → 复用其 33 例证据：P2 13/13、P3 20/20、0 mismatch、0 X、`vlog 0/0`；P2 comp 355,261 cycles；f1080p_p1d1 81,707 B / `b769cc66…08ff`（证据：`T10.a1-bm-addr/r0/p2/result.json`、`r0/p3/result.json`、`r0-route/result-r0-route.md`）。
- **门级仿真/等价性检查未跑**（冻结预算内无已建立的 TD 门级仿真/形式等价流程；ModelSim 门级设置不在本包范围）→ 按 dispatch 以 §4 的静态跨域检查替代并写明。
- 不声称门级/板上功能已验证。

## 6. 预算账

| 项 | 值 |
|---|---|
| TD 会话 | **2/2**（g1 wall ≈14.5 min，其中 phy 13m23s：place 42 s / route 43 s / phys_opt 11m57s / fix_hold 1 s；g2 wall ≈4.5 min，phy 2m19s） |
| 总 wall | ≈19 min（≤90 min 上限） |
| 综合 / 布线 | **2/2** / **2/2** |
| seed sweep / bitgen / 下载 / Flash | 0 / 0 / 0 / 0 |
| `.bit/.cwc` 计数 | 0（全包递归统计） |

## 7. 停止、回退与收尾

- 停止依据：dispatch `stop_conditions`（组 2 仍 < +0.2 ns → 停；无第 3 组；无随机 seed）；`blocked.reason_code = LIMIT_REACHED`。
- 回退：本包**只改策略、未改 RTL**，无需回退工作树；最佳 G1 绿候选仍为 `35ea7364`（工作树现状），历史最佳回退 `r2 0b084317` 保留；r0–r10 及各包 manifest 只读保留。
- 规划收尾口径：T10 保持 **3/4 PASS + 1 ⚠**，不称完成；不自动扩轮、不开新包。

## 8. 恢复入口与测试说明

- 恢复入口：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-qor-retime/r0/`（本文件、`CANDIDATE-MANIFEST-qor-retime-r0.json`、`artifact-hashes.txt`、`hash-checks.txt`、`analysis/netlist_scan.txt`、`td/g1/**`、`td/g2/**`）。
- 复测清单：**本包 Routed 门槛未过，不派测试者、不声称 PASS**。若规划仍要独立核验 FAIL 证据，测试者可：①独立解析两组 `routed_timing_summary.rpt/-status.rpt`（SWNS −0.039/−0.747、hold ≥0、端点数）；②核 `routed_area.rpt` 资源与 `run.log` 的 `phys_opt`/retiming 证据；③核冻结输入哈希与“无 RTL/SDC 修改、无 bitgen/.bit/下载”；④复核 `analysis/netlist_scan.txt` 的静态跨域结论；判定必须保持 FAIL。
