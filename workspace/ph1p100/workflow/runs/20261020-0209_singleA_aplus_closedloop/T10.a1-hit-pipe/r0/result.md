# T10.a1-hit-pipe r0（含 r0-route）— G1 功能逐位不变、r2 的 `bm_a ERAM clk2q→state CE` 锥已消除，但 route-only 实测 **Routed SWNS −0.577 / STNS −57.504 / 311 违例端点** → G2 FAIL（route 1/1 用尽，bitgen not_run）

- task_id `T10.a1-hit-pipe` | round **r0** | 同一 T10 / 同一 run `20261020-0209_singleA_aplus_closedloop`
- 日期 2026-10-22 | 离线合成帧 + 离线综合（TD Release_2026.2）+ **规划批准一次性 +0.5 预布线豁免后的 route-only** | **未 bitgen、无 .bit/CWC/下载/Flash**
- 路由结果（r0-route，见 §9）：Routed、**SWNS −0.577 / STNS −57.504 / 311 违例端点**、HWNS +0.020 / HTNS 0.000、slice 3008/71680、ERAM 26 → **G2 setup FAIL**
- CDC（同一 routed netlist）：`report_clock_utilization`/`check_timing`/`report_timing_summary` 实际执行，单时钟 `clk`、无跨域；TD 2026.2 无 `report_cdc`（见 `cdc-static.md`，非工具 CDC 签核）
- 候选（冻结）：`a1_deflate_core.v` SHA256 `587ef708967fbe2f3bb27b0bccdbc6af942b61639ad95d8d9ec9eca2b24a2f16`
- 锁定输入（未改）：frame `18d51b1b80002e3549b6afd74956cff9d323d0a0272a7a08d617365a01611cbe`、SDC `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311`
- 基线（回退点）：r2 `0b084317db0608a56865a77fd18e7312add3ddb87c2a465a48f60816d8545396`（`r0/base-0b084317.a1_deflate_core.v`，与 `T10.a1-htab-eram/r2/candidate-0b084317…v` 同源）
- **唯一判定：FAIL（G2 setup）。** G1（功能等价 + 零周期增加）PASS 且与基线逐位相同；`bm_a ERAM clk2q → state_reg.ce`（r2 唯一失败锥）已在网表结构上消除；但规划豁免 +0.5 预布线门槛后的一次 route-only 实测 **Routed `SWNS −0.577 ns / STNS −57.504 ns / 311 违例端点`**（hold PASS），最终门槛「Routed 零违例」未达 → G2 FAIL。route 1/1 用尽，不自动扩轮；r2 `0b084317` 仍是最佳（唯一有 routed 记录且只 −0.436 的候选），本候选 **不得**作为 G2 候选或生产输入。

## 1. 改动（两项纯流水移动，均不加周期）

只改 `rtl/ep_side/codec/a1_deflate_core.v`；htab/bm 存储映射、`thresh_lit8/9`、协议/端口/帧语义/CRC/长度/abort/Bayer/SDC、`a1_frame_top.v` 全部未动（哈希见上）。语义目标是**逐拍值不变**，用 P2/P3 逐位证据验收。

### 1.1 S_EXT 扩展字节比较寄存化（r2 布线唯一失败锥）
- r2 的 138 个 setup 违例全部是 `bm_a ERAM clk2q → state_reg[*].ce`，根因是 `S_EXT` 里 `if (bm_a_rd != bm_b_rd) state <= S_MLEN;`：ERAM clk2q（含 0.686 ns 网）→ 8 bit 比较 → 27 态 CE 网络，4 级 5.245 ns。
- 改为**预取一拍 + 失配标志寄存**：
  - 命中拍 bm_a 口改发 `p3_r+1`（=pos+4）、bm_b 口改发 `hf_r+1`（=ref+4），S_EXT 中 `ext_raddr/ext_faddr` 初值相应 `+2`；于是第 k 个扩展字节的字节对在 k-1 拍就已在 `bm_a_rd/bm_b_rd`。
  - `ext_mis_r` 在 k-1 拍登记该字节对的比较结果，S_EXT 第 k 拍直接用它决定 `S_MLEN` —— 与原组合比较**同拍消费**，循环拍数完全不变。
  - 第一个扩展字节：前向字节 = `x1_r`（命中拍已寄存），参考字节由命中拍 bm_b 口读 `hent[49:37]`（=ref+3）得到。该读口在 `s1_en` 拍（S_SCAN 以及 S_PRE/S_REPOS 的 pre_cnt/rp_cnt==3 拍）本来就不被消费（S_SCAN 窗口靠 `w0..w2/x1_r` 移位链），因此改成投机预读不改变任何既有语义。S_PRE/S_REPOS 那一拍必须按 `s1_en` 选（只用 `state==S_SCAN` 会漏掉"重新起扫第一拍就命中"的情形，实测会得到错误的参考字节）。
  - 两个独立条件赋值（`if (state==S_EXT)` / `if (bm_hit_a)`）而不是一个 `hit2` 控制的输入 mux：否则 pos 派生的 hit2 会进入 `ext_mis_r.d` 数据锥（第 1 次综合实测 5.259 ns，见 §3）。

### 1.2 hit 距离/范围判定移到 stage 2
- r2 综合最差是 `htab_tag ERAM clk2q → hent_pos → 13 bit 减法 → range 比较 → hrg_r.d`（−0.017 ns，5 级）。该锥保持 stage 1 就必然继承 ERAM clk2q。
- 改法：stage 1 只登记 ERAM 读数据（`hp_r`、`hf_r`、`hb_r`、`s1_vld_r`）；距离/范围在 stage 2 用寄存器算：
  `hdist2 = pos - hp_r`；`rng2 = (hp_r < pos) && (hdist2 <= MAX_DIST) && (pos < lim2)`；`hit2 = s1_vld_r && hb_r && rng2`；`dist_r <= hdist2`。
  等价性：stage-1 结果被消费的那一拍恒有 `pos == 上一拍 s1_pos_r`（literal 路径两者同步 +1；S_PRE/S_REPOS 回卷拍 `s1_pos_r` 被装成 `pos` 且 `pos` 保持），故 `hdist2` 与旧 `s1_hdist`、`rng2` 与旧 `s1_ok && s1_rng` 逐值相同。`hd_r/hrg_r` 删除。
- 结果：none of the top synthesis paths starts at an ERAM clk2q any more（§3 top-4 全部 flop 发起）。

### 1.3 范围说明（供规划复核）
- dispatch 写域写的是「only bm_a read-data/state CE pipeline」，而 `technical_scope.five_steps` 第 2 条写「Precompute/register state_reg CE from hit/hdist/threshold control」。§1.2 属于「hit/hdist 控制」这一段：不加周期、不改存储/协议、目标是移出 ERAM clk2q。若规划认为 §1.2 越界，可用 §1.1 单独构成候选（S_EXT 锥照样消除），但综合 WNS 会回到约 −0.017（htab→hrg 仍在），门槛更远。

## 2. G1：功能等价 + 零周期增加（PASS，逐位同基线）

| 项 | 门槛 | 实测 | 结论 |
|---|---|---|---|
| P2 | 13/13、0 mismatch、0 X、0 illegal | **13/13 PASS**（`r0/p2/result.json`） | PASS |
| P3 | 20/20、0 mismatch、0 X | **20/20 PASS**（`r0/p3/result.json`，`failures=[]`） | PASS |
| 码流逐位 | 与 r2 基线同 sha/长度 | **13+20 例 stream/raw sha、stream_len、out_bytes 全同；P3 各例 cycles 全同（cycles-diff=0）** | PASS |
| P2 comp 周期 | ≤355,261（硬上限 370,370） | **355,261**（81.067159 MB/s） | PASS（零增加） |
| 1080p | ≤6,250,000 | p1d1 **4,677,945**、p1d0 **4,866,587**、p0 **4,744,596**、rand **4,678,533** | PASS |
| 解码 | 独立 zlib 1.2.13 + 自研 strict | 两套均 0 mismatch；负例（truncate/oversize/h1/wmod4/pred0prep0/abort/reset/proto）判定不变 | PASS |
| vlog | 0/0 | P2 `Errors: 0, Warnings: 0`；P3 `Errors: 0, Warnings: 0` | PASS |
| 存储上界 | 不增长 | 各例 `worst_stored_bytes`/`worst_expansion_pct` 与基线逐值相同 | PASS |

复跑脚本：`upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p2_hitpipe_r0.ps1`、`run_p3_hitpipe_r0.ps1`（由 r2 harness 仅替换 run 目录，仿真仍 P:/W:）。

## 3. 综合（2/3 次）

顶层 `a1_eng_top`、`PH1P100SBG484 -3`、clk 187.5 MHz / 5.333 ns、SDC 未改。

| 次 | 变化 | SWNS | STNS | slice* | ERAM / core | reg | DRAM LUT |
|---|---|---|---|---|---|---|---|
| s1 | §1.1 用 hit2 输入 mux | **+0.010** | 0.000 | 3054 | 26 / 22 | 1626 | 32 |
| s2 | 冻结候选（§1.1 改双条件赋值 + §1.2） | **+0.021** | **0.000** | **3083** | **26 / 22** | 1625 | 32 |

- s2 最差路径（`syn_gate_timing_s2.rpt`）：
  1. `+0.021` `grp_in_row_reg[3]` → `smem_waddr_r_reg[15].d`，5.248 ns / 7 级 —— **a1_frame_top（锁定）**；
  2. `+0.063` 同源 `smem_waddr_r_reg[14].d`；
  3. `+0.150` `p3_r_reg[0]` → `ext_zero_r_reg.d`（core，7 级；r2 已有的扩展停止标志预计算）；
  4. `+0.271` `len_r_reg[0]` → `cand_bits_reg[31].d`（core，r2 已有）。
- **关键证据：top-4 没有任何一条起于 `bm_a`/`htab` ERAM clk2q**；r2 的两条 ERAM clk2q 锥（`bm_a→state.ce`、`htab_tag→hrg_r`）都已从网表结构上消失。
- s1 教训：第 1 次综合的 5.259 ns 是我自己引入的 `pos→hit2→mux→ext_mis_r.d` 锥（hit2 含 stage-2 距离算术），用两次独立条件赋值把 hit2 只留在 CE 上后消失。
- 两次综合都出现 `PRJ-8806 Run syn_1 has exited unexpectedly`，但 `gate.timing/area/db` 完整，按 r2-b lessons 的判定继续解析（不是综合失败）。

## 4. 门槛判定与停止依据

- dispatch g2_synth：`wns_ns_min = 0.5`、`tns>=0`、`slice<=71680`、`ERAM 26 与实例相符`。
- 实测：WNS **+0.021**（< +0.5）→ 按 stop_conditions「Synth WNS < +0.5 或 TNS<0 → 不布线」**未布线**：route **0/1**，无 routed DB，故 routed WNS/TNS/HWNS/HTNS、0 违例、routed 资源**均未评估**。
- slice 3083/71680、ERAM 26（core 22 = 18 基线 + 4 htab）、DRAM LUT 32 与 r2 一致 → 资源门槛本身不阻塞。
- 未做：QoR 策略、降频、false path/multicycle、seed sweep、更大器件、bitgen/下载。
- 结论：+0.5 的预布线门槛**在本包允许写域内不可达**——现实最差路径是锁定的 `a1_frame_top` smem 写地址锥（+0.021/+0.063）；core 侧最差 +0.150。touched 的 `a1_frame_top.v` 属 `must_not_modify`。

## 5. CDC：证据缺口（无 routed netlist）

- 按 dispatch，CDC 接受「同一 routed netlist/clock structure 的静态单时钟证据」。本包**没有布线**，因此该证据**不可得**；`report_clock_utilization`/`check_timing` 是 route 模式命令，未执行。
- TD Release_2026.2 **没有 `report_cdc`** 命令（r2-waive2 实测 `invalid command name`）；本包 tcl 保留该尝试并如实记录 `RPT_CDC_UNAVAILABLE`，**未**产生 cdc.rpt。
- 预布线层面只记录到：SDC 只有 `create_clock clk 187.5`（单时钟、无生成时钟），s2 综合报告只有 `clk -> clk` 一个 path group，无跨域路径组。**这不构成 CDC 签核**，也**不得**把 `check_timing` 当 CDC。
- 详见 `r0/cdc-static.md`。

## 6. 预算与账目（如实）

| 项 | 用/上限 | 说明 |
|---|---|---|
| 开发 | **约 105 min / 约 60 calls** | **超 90 min / 50 calls**：主因是 §1.1 的错拍对齐做了 3 轮 A1_DEBUG 定位（参考字节读口在 S_PRE/S_REPOS 拍被窗口占用）。已披露，未擅自扩范围/扩权限。 |
| TD 会话 | 2/3（单会话 ~3 min、总计 ~6 min） | 综合 2/3；布线 0/1 |
| bitgen / .bit / 下载 / Flash | 0 / 0 / 0 / 0 | phy 从未 launch；包内无 `.bit/.cwc` |
| 3 轮修复 | 未进入 | 本轮 r0 首次验收前即按综合门槛停止 |

## 7. 回退

- 工作树 `a1_deflate_core.v` = 冻结候选 `587ef708…2f16`。
- 回退 r2：`Copy-Item r0\base-0b084317.a1_deflate_core.v` → `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v`（= `T10.a1-htab-eram/r2/candidate-0b084317.a1_deflate_core.v`）。frame/SDC 从未改动，无需回退。

## 8. 交给规划的最小下一步（二选一）

1. **建议**：对本候选**豁免一次预布线 +0.5 门槛**，用掉 1 次布线（≤60 min）取 routed 结果。证据：r2-waive2 的同一 routed 运行里，`smem_waddr` 这类路径落在 **+0.020**（通过），而 r2 唯一失败锥 `bm_a ERAM clk2q → state.ce`（138/4514 端点、−0.436/−26.919）在本候选的网表里已不存在（top-4 无 ERAM clk2q 发起路径）；本候选功能与 0b084317 逐位相同、零周期增加。若 routed 达标，CDC 静态单时钟证据可在同一 routed DB 上补做。
2. 或：新开一个针对 `a1_frame_top` smem 写地址锥（`grp_in_row → smem_waddr_r`）的包——它在综合 +0.021、r2 布线 +0.020，是当前真正的时序前哨；该文件在本包锁定，不能由本包改动。

---

## 9. r0-route：route-only 实测结果（规划批准豁免后，1 次布线，无综合、无 RTL 改动）

- 触发：规划 `dispatch-hit-pipe-verify.json` 批准**一次性 +0.5 预布线豁免**，最终仍以「Routed 零违例」为准；对象 `587ef708`、frame/SDC 锁定。
- harness：`r0/td/04_route_only.tcl`（r2-waive2 修正版：先 `import_device ph1_100p.db -package PH1P100SBG484 -speed 3` 再 open、12 s 早失败检查 `SETTINGS_CHECK device=ph1_100p.db package=PH1P100SBG484` / `OPT_PLACE_STARTED`、`.opt_route.begin.f` 出现即写 `.stop.f` 停 bitgen；无综合、无 bitgen、无 .bit）。
- 时序：place→route 完成（`PHY_STOP_MARKER_SET waited=48s`，全 session 约 3 min，远低于 45 min）。

| 项 | 门槛 | 实测 | 结论 |
|---|---|---|---|
| 状态 | Routed | **Routed**（`phy_pr_timing.rpt`/`phy_timing_status.rpt`） | PASS |
| Routed S WNS | ≥0 | **−0.577 ns** | **FAIL** |
| Routed S TNS | ≥0 | **−57.504 ns** | **FAIL** |
| setup 违例端点 | 0 | **311 / 4514** | **FAIL** |
| Routed H WNS / TNS | ≥0 | **+0.020 / 0.000 ns** | PASS |
| 资源 | 在器件内 | slice **3008**/71680、LUT6 2923、reg 1644、ERAM **26**、DRAM LUT 32、IO 121/286、DSP 0 | PASS |
| Fmax | — | 169.205 MHz（`phy_pr_timing.rpt`） | 诊断 |
| CDC 命令 | 实际执行 | `report_clock_utilization`/`check_timing -verbose`/`report_timing_summary` **实际执行**；`report_cdc` = `invalid command name`（无 cdc.rpt） | 见 `cdc-static.md` |
| bitgen / .bit | not_run | `NO_BIT_FILE`、`.stop.f` 在位、包内 `.bit/.cwc` = 0 | PASS |

### 9.1 违例锥（新的布线最差，不是被移除的那条）

`phy_pr_timing.rpt` 最差 10 条端点的 Begin Point **全部**是 `u_dut/u_core/bm_a_syn_13.clkb`（bm_a ERAM clk2q），4 级 5.499 ns，slack −0.577/−0.524/−0.452，End Point 为**同一 CE 组**：

```
bm_a ERAM clk2q -> 4 levels -> htab_byp_data_reg[30].ce / htab_byp_n.ce / ext_mis_r_reg.ce / add74.ce
```

- 该锥在综合（s2）里对应第 6 条端点 `bm_a_syn_41.clkb -> htab_byp_reg.d`，**+0.339 ns 通过**；布线后同类端点退化到 **−0.577**（约 0.9 ns 的 synth→route 退化），成为 311 个违例端点的主锥。
- 结构解释：`htab_rd_addr = hash3(w2, x1_r, bm_a_rd)`（bm_a ERAM clk2q）→ 10 bit 地址 → 与 `s1_ins_addr` 比较 → `htab_byp/byp_data` 的写使能；本次 `ext_mis_r` 的 CE（`state==S_EXT || bm_hit_a`，含 pos 派生的 hit2）被 TD **并进同一 CE 组**，因此该组同时覆盖 `ext_mis_r.ce` 与 `add74.ce`。r2 里没有 `ext_mis_r`，这一组不存在（或未合并），所以 r2 的 138 端点里没有它。
- 结论：r0 的两项改动把 r2 的 `bm_a→state CE` 比较锥消灭了，但**没有**处理 `bm_a_rd → hash3 → htab 地址 → 写使能/CE` 这条 ERAM clk2q 锥（r0 计划阶段判定它"综合 +0.339、r2 布线 ≥+0.020"而未动）；布线后它成为唯一主锥，且比 r2 的更差。**本候选不是改进闭环，不能作为 G2 候选。**

### 9.2 预算

| 项 | 用/上限 |
|---|---|
| TD 会话 | 1/1（约 3 min，≤45 min） |
| 综合 | **0**（未综合） |
| 布线 | **1/1**（完成，Routed） |
| bitgen / .bit / 下载 / Flash | 0 / 0 / 0 / 0 |
| 本阶段开发 | 约 10 min / 约 10 calls |

## 10. 下一轮修复方向（交规划，本阶段不实施）

1. **把 `bm_a_rd` 移出 htab 读地址/写使能锥**（这是现在唯一的主锥）：给 bm 读数据加一级寄存器并把扫描预取整体前移一拍（`praddr` 由 `raddr+3` → `raddr+5`，x1_r/w2 也随之对齐），使 `hash3` 的第三字节来自 flop 而不是 ERAM clk2q；同时把 `ext_mis_r` 改成**无 CE 的无条件赋值**（`state==S_EXT ? (bm_a_rd!=bm_b_rd) : (x1_r!=bm_b_rd)`），避免其 CE 与 htab_byp 组合并。二者都不改变周期数，但会改动扫描预取对齐 → 必须重跑 P2/P3 逐位对比。
2. 若上一条仍不足，再考虑 `a1_frame_top` 的 `grp_in_row → smem_waddr_r`（综合 +0.021，r2 布线 +0.020）——该文件在本包锁定。
3. 门槛建议：这类"综合 5.2 ns 级、布线退化 ~0.9 ns"的 ERAM clk2q 锥，用综合 WNS 做闸门不可靠（s2 +0.339 的路径布线后 −0.577）；应把**同一候选的 synth top-N 端点**全部列出并逐条给出要求（例如综合端点上 ERAM clk2q 锥必须 ≥ +0.9），或直接允许一次布线作为判定。
