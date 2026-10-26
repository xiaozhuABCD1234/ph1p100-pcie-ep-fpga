# T10.a1-pipe-split r0 — **BLOCKED：Routed 零违例（0/4649）且 hold 通过，但 setup SWNS +0.047 ns < dispatch 门槛 +0.2 ns**

- task_id `T10.a1-pipe-split` | revision **r0** | 2026-10-22/23 | run `20261020-0209_singleA_aplus_closedloop`
- 授权：`dispatch-pipe-split.json`（用户 2026-10-22 原话“进行结构性分拍尝试”；同一 T10/同一 run；允许改 `a1_deflate_core.v` 与必要的 frame 纯流水适配；协议/端口/帧语义/CRC/长度/abort/Bayer/SDC 不变）
- 判定 **BLOCKED（Routed 门槛未达）**：
  - **G1 全绿**：P2 13/13、P3 20/20 全部逐位相同（0 差异）、0 mismatch、0 X、`vlog` 0/0；P2 comp **355,261 cycles 精确不变**（cycle-neutral）；1080p 81,707 B / 4,677,945 cycles；SDC `227dd39e` 与 frame `18d51b1b` 未改。
  - **G2 部分成立**：Routed 零违例 **0 / 4,649** 端点、hold +0.021/0、资源在器件内、静态单时钟与复位结构、报告直接 `-file`、bitgen not_run、无 `.bit`/下载；**但 setup SWNS +0.047 ns < +0.2 ns** → 按 dispatch 门槛未通过，交规划裁决是否接受（本包不宣称 PASS）。
- 无 bitgen、无 `.bit`、无下载、无 seed sweep、无降频/false path/multicycle；未派测试者（无 PASS 可验）。

## 1. 冻结输入（本包候选 = 工作树现值）

| 文件 | SHA256 | 结果 |
|---|---|---|
| core `a1_deflate_core.v`（候选，工作树） | `bf6af3903f123d753391358ab003cd6ae4ec4a6a281a09dfa6e33b67798b1080` | 相对基线仅分拍改动（`patch.diff`） |
| 基线 core（`baseline-core-35ea7364.v`） | `35ea736415c5fbfd28fabcf85b78e33275fb2507f8d30a070a95a17a41760942` | bm-addr 冻结值，未变 |
| frame `a1_frame_top.v` | `18d51b1b80002e3549b6afd74956cff9d323d0a0272a7a08d617365a01611cbe` | **未改** |
| SDC（TD 用副本） | `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311` | **未改** |
| bench `a1_eng_top.v` | `544cecfc2eb34a3ab5c03ebf3965730b4ce60b2ff73ac4c2ec2d87772faaf9aa` | 未改 |

候选存档：`candidate-pipe-split.a1_deflate_core.v`；差异：`patch.diff`（unified diff，仅本文件 6 处：声明/线网/寄存/两处复位/一处 CE 条件）。

## 2. RTL 改动（bounded：步骤 1-2 + 步骤 4 一处；步骤 3 未用）

1. **stage-1 范围测试寄存 `rng1_r`**（步骤 1）：在 stage-1 周期计算旧式 stage-1 谓词并随 `hb_r` 同拍寄存（`if (s1_en)`）。实现上用**预计算边界**避免 13-bit 减法/比较串在 ERAM clk2q 之后：
   - `s1_lo = s1_pos_r - 1`，`s1_hi = (s1_pos_r > MAX_DIST) ? s1_pos_r - MAX_DIST : 0`，`s1_nz = (s1_pos_r != 0)`；
   - `hent_pos <= s1_lo` ⇔ `hent_pos < s1_pos_r`；`hent_pos >= s1_hi` ⇔ `s1_pos_r - hent_pos <= MAX_DIST`（在第一条成立时）；
   - `rng1 = s1_nz && (hent_pos <= s1_lo) && (hent_pos >= s1_hi)`；**两条 hent 源并行比较、只对 1-bit 结果做 `htab_byp` 选择**，使 ERAM clk2q 锥只剩比较 + 1 级 LUT（无数据 mux）。
2. **stage-2 全 flop**（步骤 2）：`rng2` 线网删除；`hit2 = s1_vld_r && hb_r && rng1_r && s1_ok_r`（4 个 flop）。`hp_r`/`hdist2` 仅保留给 hit 分支数据（`cand_pos <= hp_r`、`dist_r <= hdist2`）不变。
3. **`s1_ok_r`**：`s1_ok_r <= s1_ok` 与 `hb_r` 同拍寄存；组合 `s1_ok` 仍供 `htab_we` 使用（语义不变）。
4. **步骤 4（一处谓词）**：`s1_last_r <= (s1_pos_r + 13'd1 >= blk_n)` 与 `hb_r` 同拍寄存；S_SCAN literal 分支的 `pos + 13'd1 >= blk_n` 改用 `s1_last_r`，把 13-bit 自增+比较移出 `pos`/`thresh_base` 的 CE 锥（依据上一包 routed 证据该类路径 −0.036）。
5. **步骤 3（`p3p1_r`）未实施**：三次综合的 top-10 均未显示 `p3_r+1 → bm_raddr → ERAM` 为关键（≥ +0.469），按 dispatch 条件不使用。
6. `rng1_r`/`s1_ok_r`/`s1_last_r` 在 `!rst_n` 与 `abort` 两个分支均清零（与 `hb_r` 一致）。

**等价性**（由 33 例逐位回归证明，非仅推理）：stage-2 消费周期的 `pos` 等于上一 stage-1 周期的 `s1_pos_r`（literal 锁步；S_PRE/S_REPOS rewind 时 `s1_pos_r` 装入 `pos` 且 `pos` 保持），`lim2`/`blk_n` 块内恒定，故 stage-1 寄存的三个谓词与旧 stage-2 组合谓词逐拍相同；`s1_last_r` 同理（`pos + 1 >= blk_n` ⇔ `s1_pos_r(prev) + 1 >= blk_n`）。**周期 +0**。

## 3. 综合迭代（同一 top/器件/187.5 MHz、同一 SDC、retiming on；共 3 次）

| # | RTL | synth SWNS / STNS | slice / ERAM / reg / DRAM LUT | 关键锥（synth） |
|---|---|---|---|---|
| 1 | 步骤 1-2 字面式（`hdist1`+比较） | **−0.055 / −0.055** | 3,071 / 26 / 1,742 / 32 | `htab ERAM clk2q → rng1_r`（5.324 ns，5 级：LUT3×2+ADDER×2+LUT6） |
| 2 | + 预计算边界 + `s1_ok_r` | **−0.007 / −0.007** | 3,101 / 26 / 1,691 / 32 | 同路径（5.276 ns） |
| 3 | 最终（+ 双源比较 + `s1_last_r`） | **+0.275 / 0.000** | 3,128 / 26 / 1,689 / 32 | 无违例；次关键为 `cand_bits`（+0.341）、`praddr`（+0.522） |

- 字面式在 synth 即 −0.055，证明 13-bit 减法/比较不能放在 ERAM clk2q 之后；改用等价预计算边界后归零，最终形式 synth 0 违例。
- retiming 实际生效：`SYN-3005` backward retimed（`adler_fold_b_reg[8..13]` 等）；`#reg 1,646→1,689`。

## 4. Routed 结果（第 3 个 TD 会话：synth #3 + **1 次布线**）

策略：`set_param -run syn_1 rtl retiming on`、`set_param -run phy_1 route post_route_opt ultra`（均 `PRJ-1105 … succeed`；param 表 `post_route_opt = ultra (*)`）。**证据偏差**：本次 phy 流程统计仅 place 40 s / route 29 s / fix_hold 1 s（总 1m10s），**未出现 post-route `phys_opt` 阶段**（上一包 718 s 的 phys_opt 本次未执行；不声称其生效）；+47 ps 来自 retiming + place/route + hold fix。

| 项 | 本包 | 门槛 | 结论 |
|---|---|---|---|
| **Routed SWNS / STNS** | **+0.047 / 0.000** | 零违例且 ≥ +0.2 | **FAIL（未达 +0.2）** |
| **违例端点 / 总数** | **0 / 4,649** | 0 | pass |
| hold HWNS / HTNS | +0.021 / 0.000 | ≥ 0 | pass |
| 报告 Fmax（R-Period） | **189.179 MHz**（5.286 ns） | 诊断项 | — |
| 资源 slice / lut6 / reg / ERAM / DSP / IO / DRAM LUT | **3,032**（4.23%）/ 2,945 / 1,712 / 26（8.67%）/ 0 / 121 / 32 | 器件内 | pass |
| Confidence / 角 / CRPR / coverage | Routed / Both / Yes / 96.40% | Routed | pass |
| 时钟 | 单 `clk` 187.512 MHz，fanout 1,322，Max-Level 6，CC-From/To = no/no | 单时钟 | pass |
| bitgen / `.bit` / 下载 | not_run / 0 / 0（`NO_BIT_FILE`，stop marker 于 opt_route 前落下） | not_run | pass |

**Routed 最差路径（诊断）**：`u_core/bm_a` ERAM clk2q（1.846 ns）→ `bm_a_rd[4]` → `ext_mis_r` 比较网络（LUT6/LUT4/LUT6，3 级）→ `add41` 输入，**5.003 ns，slack +0.047**；第二条同锥经 `bm_b`（+0.047）；随后 `mux280 → praddr`（+0.140）、`len_r[8] → add9`（+0.170）、`fifo_rptr → str_crc`（+0.173）。**旧最差锥 `pos_reg[3] → bm_a.addrb`（qor-retime −0.039）已消失**，hit2 已为纯 flop 驱动；当前限制项是扩展字节比较（`ext_mis_r`）的 ERAM clk2q 锥，不在本包授权改动范围。

## 5. 功能回归（最终 RTL，33 例全量重跑）

| 项 | 结果 | 门槛 | 结论 |
|---|---|---|---|
| P2 | **13/13 PASS**，`result.json` verdict PASS | 13/13 | pass |
| P3 | **20/20 PASS**（干净单次重跑，491 s） | 20/20 | pass |
| 逐位等价 | P2 13 例与 P3 20 例的 stream SHA/len/cycles/stats 与 final-combo（= bm-addr）基线**全部逐位相同**（脚本比对 0 差异） | 逐位相同 | pass |
| mismatch / X | 0 mismatch；P3 全部 `xerr/stab_err=0`、`errs=0`；P2 `timeout_hit=0` | 0 / 0 | pass |
| `vlog` | P2 0/0；P3 0/0；frame lint 0/0 | 0/0 | pass |
| P2 comp | **355,261 cycles**（81.067 MB/s） | ≤370,370（目标 355,261） | pass（cycle-neutral） |
| f1080p_p1d1 | **81,707 B** / `b769cc66…08ff` / **4,677,945 cycles**（103.892 MB/s） | 81,707 B / ≤6.25M | pass |

证据：`p2/result.json`、`p2/logs/{vlog.log,exitcodes.txt}`、`p3/result.json`、`p3/logs/{vlog.log,vlog-lint.log,exitcodes.txt}`（退出码全 0，无超时）。

## 6. 静态 CDC + 复位结构

- `report_cdc` 在 TD Release_2026.2 不存在（console `RPT_CDC_UNAVAILABLE`，原文留证）；采用静态单时钟证据，不冒充 CDC 报告。
- Routed timing summary：唯一 `clk` 187.512 MHz，CC-From/CC-To = no/no；`report_clock_utilization`：GCLK 1 / SCLK 4（gclk_0 fanout 1,290）。
- `check_timing -verbose`：组合环 **0**、dummy node **1**（PH1P_PHY_LSLICE）、无未连接生成时钟。
- **gate 网表静态扫描**（`analysis/scan_netlists.py` → `analysis/netlist_scan.txt`）：**1,689 个 `AL_MAP_SEQ`，clk 引脚 100% 在 `clk_dup_1`**（单时钟）；sr 网络 `rst_n_dup_1567`（756）、`fifo_mem_i1_syn_2`（443）、未连接（245）等，与上一包同类；retiming 仅同域搬移/复制（SYN-3005 清单），未跨时钟/复位域。routed 网表把触发器打包进 LSLICE/MSLICE，无 `AL_MAP_SEQ`（如实说明，以 STA/clock 报告佐证）。

## 7. 预算账

| 项 | 值 |
|---|---|
| TD 会话 | **3/3**（50 s / 131 s / 147 s，合计 ≈5.5 min；≤150 min） |
| 综合 / 布线 | **3/3** / **1/1** |
| 开发 wall / calls | ≈105 min（≤120）/ ≈55（≤60） |
| seed sweep / bitgen / 下载 / Flash | 0 / 0 / 0 / 0 |
| `.bit/.cwc` | 0 |

## 8. 停止、回退与收尾

- 停止依据：dispatch `stop_conditions`“Routed not zero-violation **or setup margin < +0.2 ns** → FAIL；无第二次布线、无额外 RTL 修复轮”。本包实测零违例但 **+0.047 < +0.2**，故判 **BLOCKED**，不自行放宽门槛。
- **工作树未回退**（按本轮指令“不要改 RTL”）：`a1_deflate_core.v` = 候选 `bf6af390`；回退入口为 `baseline-core-35ea7364.v` 或 `T10.a1-bm-addr/r0/td/a1_deflate_core.v`（逐字节恢复后复核哈希）。
- T10 口径：保持 **3/4 PASS + 1 ⚠**；不自动扩轮、不开新包。**规划需裁决**：(a) 接受 +47 ps/零违例（需用户刷新 +0.2 ns 验收口径）；(b) 保持 ⚠ 收尾。
- 与既有最佳对比：本包 **+0.047 / 0 违例**（WNS 与违例数均优于 qor-retime 组 1 的 −0.039 / 45、final-combo 的 −0.091 / 12），但**仍未达 +0.2 ns**；既有“最佳 routed”记录口径按 WNS 应更新，是否更新由规划决定。

## 9. 证据偏差 / 事故（如实登记）

1. **步骤 1 实现偏离字面式**：dispatch 给的是 `hdist1`+比较表达式；字面式 synth −0.055（ERAM clk2q 后 13-bit 减法/比较不可行），改用**等价预计算边界 + 双源比较**（同一谓词、同一流水位置、cycle-neutral），由 33 例逐位回归证明等价。已记录于 `patch.diff`。
2. **步骤 4 提前使用**：synth #2 未把 `pos/blk_n` CE 类列入 top-10，但上一包 routed 证据该类为 −0.036（下一瓶颈），且本包只有 1 次布线，故按 dispatch“至多一个额外谓词”实施 `s1_last_r`。
3. **P3 并发事故（本角色操作失误）**：23:40（阈值形式）与 23:46（最终形式）两次 P3 在**同一 `p3` 目录/work 库**上重叠运行，导致首次 verifier 读到半写文件（`got=None`、`f1080p_p1d0` 流被截断）。**单次干净重跑（03:01，491 s）PASS 20/20 且逐位相同**，本报告以该次为准；事故证据保留：`p3/logs/verify_first_run_FAIL.log`、`p3/logs/f1080p_p1d0_first_run_stats.txt`、`p3/logs/f1080p_p1d0_first_run_sim.log`。`f1080p_p1d0` 基线 stream_len = 2,566,969 / 4,866,587 cycles，与本次输出一致。
4. synth #2 出现 `PRJ-8806 Run syn_1 has exited unexpectedly`（`wait_run` 竞态）；run.log 显示流程完整、`gate.timing` 正常生成（23:42:07，Confidence=Synthesized），其数值仅用于中间迭代判断，最终以 synth #3 为准。
5. 未跑门级仿真/形式等价（本包预算内无已建立流程）；以 RTL 级逐位回归 + gate 网表静态扫描替代，不声称门级/板上功能已验证。
6. `post_route_opt ultra` 参数已确认写入，但本次流程未执行 post-route phys_opt 阶段（见 §4），不声称其生效。

## 10. 恢复入口与复测清单

- 恢复入口：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-pipe-split/r0/`（本文件、`CANDIDATE-MANIFEST-pipe-split-r0.json`、`artifact-hashes.txt`、`patch.diff`、`candidate-pipe-split.a1_deflate_core.v`、`baseline-core-35ea7364.v`、`p2/**`、`p3/**`、`td/**`、`analysis/netlist_scan.txt`）。
- 复测清单（独立测试者）：①独立解析 `td/routed_timing_summary.rpt` / `routed_timing_status.rpt`（SWNS +0.047、STNS 0、HWNS +0.021、0/4,649）与 `td/a1_ps_Runs/phy_1/route.qor`（Setup 47 ps、0 violated S-EP、3,032 slices/26 RAM/0 DSP）；②在 core `bf6af390` 上独立重跑 P2/P3（期望与 bm-addr 基线逐位相同：comp 355,261；1080p 81,707 B/`b769cc66`）；③核 frame/SDC/bench 哈希与“无 bitgen/.bit/下载”；④复核 `analysis/netlist_scan.txt` 的单时钟/复位结论；⑤**门槛判定不得放宽**：+47 ps < +200 ps，是否接受由规划/用户裁决。
