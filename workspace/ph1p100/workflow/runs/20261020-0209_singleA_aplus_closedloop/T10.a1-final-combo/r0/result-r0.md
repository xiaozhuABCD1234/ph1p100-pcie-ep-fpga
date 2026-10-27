# T10.a1-final-combo r0 — **BLOCKED：单点 cycle-neutral 微修 + 组 1 策略仍未达 Routed 门槛（SWNS −0.091 / 12 端点）**

- task_id `T10.a1-final-combo` | revision **r0** | 2026-10-22 | run `20261020-0209_singleA_aplus_closedloop`
- 授权：`dispatch-final-combo.json`（用户 2026-10-22 批准“最后一次组合尝试”：单个微 RTL 修改 + 沿用组 1 retiming+phys_opt，1 综合 + 1 布线，失败即收尾）
- 判定 **BLOCKED / FAIL**：Routed gate 要求零违例且 setup ≥ **+0.2 ns**；实测 **SWNS −0.091 ns / STNS −0.308 ns / 12 违例端点（共 4,651）**。按 dispatch 停止条件**不做第二处 RTL 修改、不加综合/布线**；T10 保持 **3/4 PASS + 1 ⚠**，最佳 routed 保持 qor-retime 组 1（−0.039 / 45）
- 无 bitgen、无 `.bit`、无下载；未派测试者（无 PASS 可验）

## 1. 冻结输入（运行前/后复核）

| 文件 | SHA256 | 结果 |
|---|---|---|
| core `a1_deflate_core.v`（本包候选） | `c676ba0bf6e0c1d855a04faab68d4d6edfc3b2d39ef6e931bcbabbc938766b9f` | 相对 bm-addr `35ea7364…0942` 仅含单点微修（见 `patch.diff`） |
| frame `a1_frame_top.v` | `18d51b1b80002e3549b6afd74956cff9d323d0a0272a7a08d617365a01611cbe` | **未改**（运行前复核一致） |
| SDC `a1_small_top.sdc` | `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311` | **未改**（TD 用逐字节副本） |
| bench `a1_eng_top.v` | `544cecfc2eb34a3ab5c03ebf3965730b4ce60b2ff73ac4c2ec2d87772faaf9aa` | 未改 |

- 候选存档：`candidate-final-combo.a1_deflate_core.v`（c676ba0b）；差异 `patch.diff`（unified diff，仅 3 处：声明 `reg s1_ok_r;`、stage-1 寄存 `s1_ok_r <= s1_ok;`、`rng2` 用 `s1_ok_r` 替换 `(pos < lim2)`；逐行比对无其它改动）。
- 失败后工作树已回退到 bm-addr `35ea7364…0942`（回退后哈希已复核），与 qor-retime 收尾时的“工作树=最佳 routed 候选”口径一致。

## 2. 单点微修与等价性

- `s1_ok_r` 与 `s1_vld_r <= s1_en` 同拍无条件寄存；`rng2 = (hp_r < pos) && (hdist2 <= MAX_DIST) && s1_ok_r`；`(hp_r < pos)`、`hdist2`、`s1_ok` 本身及其它消费者（`htab_we` 等）不变。
- 依据 RTL 自身注释（stage-2 消费周期的 `pos` = 上一拍 `s1_pos_r`，`lim2` 块内恒定）等价；**由 33 例全量回归证明**（见 §3），未加流水周期。
- 复位说明（如实登记）：`s1_ok_r` **未加复位**（保持“仅此一处”边界）。安全性依据：`lim2`/`s1_pos_r` 复位为 0 → 第一个有效沿即写入确定值；`hit2` 由复位为 0 的 `s1_vld_r` 门控，复位期间不会因 X 传播产生误判。仿真 33 例 0 X 支持该结论。

## 3. 功能回归（RTL 已改，33 例全部重跑）

| 项 | 结果 | 门槛 | 结论 |
|---|---|---|---|
| P2 | **13/13 PASS**；`result.json` verdict PASS | 13/13 | pass |
| P3 | **20/20 PASS** | 20/20 | pass |
| mismatch / X | 0 mismatch；全部 stats `xerr/stab_err=0`（逐文件扫描） | 0 / 0 | pass |
| `vlog` | P2 `Errors: 0, Warnings: 0`；P3（含 lint）`Errors: 0, Warnings: 0` | 0/0 | pass |
| P2 comp cycles | **355,261**（精确） | =355,261 | pass |
| P2 comp 吞吐 | 81.067 MB/s | ≥77.76 | pass |
| f1080p_p1d1 | **81,707 B** / `b769cc66…08ff` / 4,677,945 cycles（103.892 MB/s） | 81,707 B | pass |
| 逐位等价 | **13/13 P2 + 20/20 P3 的 stream SHA/len/run_cycles 与 stats 与 bm-addr 基线全部逐位相同**（脚本比对，0 差异） | 逐位相同 | pass |

证据：`p2/result.json`、`p2/logs/vlog.log`、`p2/logs/exitcodes.txt`、`p3/result.json`、`p3/logs/vlog.log`、`p3/logs/vlog-lint.log`、`p3/logs/exitcodes.txt`（退出码均 0，无超时）。

## 4. TD 结果（同一 top/器件/187.5 MHz、同一 SDC、报告工具直接 `-file`）

### 4.1 策略（沿用组 1，1 综合 + 1 布线）

- `set_param -run syn_1 rtl retiming on` → `PRJ-1105 … retiming::on succeed`；syn run.log 有 `SYN-3005` backward retimed（`dval_r_reg[7..13]`、`ext_zero_r_reg`、`adler_fold_b_reg[8..10]` 等）；`#reg 1,646 → 1,692`。
- `set_param -run phy_1 route post_route_opt ultra` → `PRJ-1105 succeed`；route 步骤实际执行 `phys_opt -post_route -effort high`（**261.8 s** wall）。
- `postrt_opt_loc 20`、`postrt_opt_extra_round 4`：`set_param` 接受但**无 PRJ-1105 确认行**（与组 1 相同；不声称生效）。
- 无 seed sweep、无第 2 组、无 RTL/SDC 二次修改。

### 4.2 数值

| 项 | 基线 bm-addr `35ea7364` | 组 1（qor-retime） | **本包** | 门槛 | 结论 |
|---|---|---|---|---|---|
| synth SWNS/STNS | +0.113 / 0 | +0.113 / 0 | **+0.021 / 0.000** | — | 完成 |
| synth slice / ERAM / reg / DRAM LUT | 3,085 / 26 / 1,646 / 32 | 3,089 / 26 / 1,685 / 32 | 3,084 / 26 / 1,692 / 32 | 器件内 | pass |
| **Routed SWNS / STNS** | −0.087 / −1.109 | −0.039 / −0.645 | **−0.091 / −0.308** | ≥0 且 ≥+0.2 | **FAIL** |
| 违例端点 / 总数 | 27 / 4,555 | 45 / 4,635 | **12 / 4,651** | 0 | **FAIL** |
| hold HWNS / HTNS | +0.023 / 0 | +0.024 / 0 | **+0.021 / 0.000** | ≥0 | pass |
| Routed 资源 slice / lut6 / reg / ERAM / DSP / IO | 2,993 / … / 1,664 / 26 / 0 / 121 | 3,023 / 2,925 / 1,703 / 26 / 0 / 121 | 3,028 / 2,936 / 1,717 / 26 / 0 / 121 | 器件内 | pass |
| Confidence / 角 / CRPR / coverage | Routed | Routed | Routed / Both / Yes / 96.17% | Routed | pass |
| 报告 Fmax | 184.502 MHz | 186.150 MHz | 184.366 MHz (5.424) | — | 诊断项 |
| bitgen / `.bit` / 下载 | not_run / 0 / 0 | not_run / 0 / 0 | not_run / 0 / 0（递归计数 0） | not_run | pass |

### 4.3 违例锥（诊断）

- 最差：`u_core/hp_r_reg[4]_syn_2` → `u_core/bm_a_syn_37.addrb[3]`（ERAM 地址），**−0.091 ns**，数据路径 4.730 ns（cell 2.210 / net 2.520），6 级（ADDER×2、LUT6/LUT5/LUT3、ERAM），fanout 18。
- 前 4 条全部为 `hp_r_reg[4] → bm_a.addrb[*]`（−0.091/−0.060/−0.034/−0.029）；随后 4 条 `add8_syn_190 → pos_reg[*].ce`（−0.019/−0.016×3）；1 条 `bm_b ERAM clkb → ext_mis_r`（−0.009）。
- 路径链：`hp_r[4] → lt60 比较链（(hp_r < pos)） → rng2_n2（fo=6） → hit2 门控 mux409 → bm_raddr_a LUT6/LUT5 → bm_raddr_a[3] net（1.293 ns） → ERAM addrb[3]`（`a1_deflate_core.v:289/513/720`）。
- **微修确实生效**：原 `(pos < lim2)` 13-bit 比较器已不在 hit2 锥中（旧最差发射点 `pos_reg[3]` 消失，新发射点为 `hp_r_reg[4]`）；gate 网表含 `u_dut/u_core/s1_ok_r_reg`（DFF）。但残余的 `(hp_r < pos)` 比较链 + hit2→地址 mux→ERAM 地址仍 4.730 ns，且 `bm_raddr_a[3]` 长线 1.293 ns 占主导。

### 4.4 静态 CDC + 复位结构

- `report_cdc` 在 TD Release_2026.2 **不存在**（console：`RPT_CDC_UNAVAILABLE invalid command name "report_cdc"`，未生成文件；不冒充 CDC 报告）。
- 静态单时钟证据：Routed timing summary 唯一时钟 `clk` 187.512 MHz，`CC-From/CC-To = no/no`；`report_clock_utilization` 实际执行（GCLK 1、SCLK 4、fanout 1,308）；`check_timing` 实际执行（组合环 0、dummy node 1 = PH1P_PHY_LSLICE、无未连接生成时钟）。
- retiming 只搬移/复制同域寄存器（SYN-3005 清单）；`s1_ok_r` 未被 retiming 移动；未跨时钟/复位域。

## 5. 预算账

| 项 | 值 |
|---|---|
| TD 会话 | **1/2**（wall **7.77 min** ≤75 min；总 ≤90 min） |
| 综合 / 布线 | **1/1** / **1/1** |
| dev wall（本会话） | ≈35 min（≤60 min），工具调用 ≤40 |
| seed sweep / bitgen / 下载 / Flash | 0 / 0 / 0 / 0 |
| `.bit/.cwc` | 0（递归统计） |

## 6. 停止、回退与收尾

- 停止依据：dispatch `stop_conditions`“Routed not zero-violation or setup margin < +0.2 ns → FAIL；无第二处 RTL 修改、无额外综合/布线”。
- 回退：工作树 core 已回 `35ea7364…0942`（bm-addr 冻结副本逐字节恢复，哈希复核）；候选存档 `candidate-final-combo.a1_deflate_core.v`（c676ba0b）+ `patch.diff`；r0–r10 及各包 manifest 只读保留。
- 收尾口径：**T10 保持 3/4 PASS + 1 ⚠，不称完成**；最佳 routed 仍为 qor-retime 组 1（−0.039/45）；不自动扩轮、不开新包。

## 7. 恢复入口与测试说明

- 恢复入口：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-final-combo/r0/`（本文件、`CANDIDATE-MANIFEST-final-combo-r0.json`、`artifact-hashes.txt`、`patch.diff`、`candidate-final-combo.a1_deflate_core.v`、`p2/**`、`p3/**`、`td/**`）。
- 复测清单：**本包 Routed 门槛未过，不派测试者、不声称 PASS**。若规划仍要独立核验 FAIL 证据，测试者可：①独立解析 `td/routed_timing_summary.rpt`/`routed_timing_status.rpt` 复算 SWNS −0.091 / 12 端点 / hold +0.021；②核 `td/routed_area.rpt` 资源与 `console_fc.log` 的 retiming/phys_opt 证据；③核冻结输入哈希与 frame/SDC 未改、无 bitgen/.bit/下载；④在新 manifest 上独立重跑 P2/P3（期望与 bm-addr 基线逐位相同）。判定必须保持 FAIL。

## 8. 证据偏差（如实登记）

1. `postrt_opt_loc 20` / `postrt_opt_extra_round 4` 无 PRJ-1105 确认行（与组 1 相同），不声称生效。
2. TD 2026.2 无 `report_cdc`；静态单时钟证据替代，未做工具级 CDC 签核。
3. 未跑门级仿真/形式等价（本包预算内无已建立流程）；等价性由 RTL 级 33 例逐位回归证明，并注明不含门级时序仿真。
4. 本包 phys_opt wall 261.8 s，明显短于组 1 的 718 s（网表不同、收敛点不同）；两个运行的策略参数一致，均以 console `PRJ-1105` 与 run.log `phys_opt -post_route -effort high` 为证据。
