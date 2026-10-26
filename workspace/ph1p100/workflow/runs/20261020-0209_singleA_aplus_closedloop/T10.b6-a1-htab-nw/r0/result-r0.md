# T10.b6-a1-htab-nw r0 — 结果（开发角色自测，非最终判定）

日期：2026-10-24。角色：开发（单会话）。状态：**ready_for_test**（离线候选已冻结；本轮不下载、不 Flash、不碰板）。
核心目标：去掉 r5 每个 match 的 1 拍 S_EXT 等待，保持字节完全不变，把 P2 comp 拉回 **355,261 cycles / 81.067 MB/s**，同时让 bm_b 读地址只由 fabric flop 驱动（时序闭合）。

## 1. 唯一 RTL 变更

- 文件：`r0/changed-src/a1_deflate_core.v`，SHA256 `6797db05…35bb`，80,196 B（r5 起点 `29b1e3e1…c9828`，79,788 B）。
- 补丁：`r0/rtl-diff-r0.patch`（vs r5）、`r0/rtl-diff-vs-r4.patch`（vs upstream r4，用于确认只多出 b3 字段与比较源）。
- 改法（为何不是 §4.1 的 p3v 影子表，见 §7 偏差说明）：
  1. **新增哈希表第 4 字节 `htab_b3[0:1023]`**：b3 = 条目位置 pos+3 处的字节，即 r4 命中拍从 bm_b 读到的 `bm[ref+3]`。写口与 `htab_b` 同 `htab_we/s1_ins_addr`，数据取 `bm_a_rd2`（在 S_SCAN/S_PRE/S_REPOS 三种 htab_pref 相位里它都正好是 x1_r 的下一个字节，槽内数据在编码期间稳定，故与匹配时读 bm 完全同值）；清除沿用 `htab_p3v[13]` valid 覆盖式清表（b3 残值永不参与比较）。
  2. **命中拍首字节比较恢复 r4 结构**：`ext_mis_r <= (ext_fw_byte != ext_rf_byte)`，`ext_rf_byte = (state==S_EXT) ? bm_b_rd : h4_r`，`h4_r` 与 `hf_r` 同拍从同一 hent（含写优先旁路 `htab_byp_b3`）寄存。
  3. **删除投机 bm_b 读**：`bm_raddr_b = bm_hit_a ? hf1_r : (state==S_EXT) ? ext_faddr : raddr`，三个来源全是 flop；`bm_b_spec_q` 与其装载逻辑删除。命中拍仍预取 `bm_a=p3_r+1`、`bm_b=hf1_r`，供 k=1 比较。
  4. **扩展循环回到 r4**：`ext_raddr <= p3_r+2`、`ext_faddr <= hf_r+2`，删除 S_EXT 的 `ext_first` 等待分支（`ext_first` 寄存器保留赋值，与 r4 一致且不参与数据通路）。
- 未改：端口/位宽/时钟/复位、htab 的 tag/p3v/pos/b0..b2 编码与比较语义、窗口链、match 阈值、候选打包、stored 回退、块/帧/块头/CRC/Adler32/长度、DDR 布局、UART 状态包、SDC/引脚；无 false path / multicycle / seed / 降频。

## 2. functional（ModelSim Intel FPGA 10.5b，独立 work 库）

运行器：`r0/run_sim.py`（命令/退出码/耗时全部记录在 `r0/sim/sim-run.json`、`r0/sim/logs/*`）。`vlog 0 errors / 0 warnings`。

| case | cycles | 吞吐 @187.5 MHz | 输出字节 | 流 SHA256 | TB | zlib | strict |
|---|---:|---:|---:|---|---|---|---|
| P2 comp（`+BP=0 +GAP=0`） | **355,261**（=r4，r5 为 374,461） | **81.067 MB/s** | 50,310 | `2601d57c…a7c05` | done=1/out_last=1/timeout=0 | ok，0 差异 | ok，0 差异 |
| P2 rand（stored 回退） | 161,479（=r4） | 178.351 | 153,766 | `54f262f2…496dd` | 同上 | ok，0 差异 | ok，0 差异 |

P1 三例（`tb_camera_a1_uart_top`，`+MODE=0`，`-gUART_DIV=1`；金标取 b5 r0 captures）：

| case | .dec 字节 | SHA256(.dec) | 与 r4 金标逐字节 | cycles | r4 上限 | r5 cycles |
|---|---:|---|---|---:|---:|---:|
| micro8x2 | 249 | `fa513a2b…edef` | ✔ | 3,809 | 3,809 | 3,809 |
| mid64x8 | 625 | `ee61e620…789` | ✔ | 5,172 | 5,172 | 5,178 |
| full_grad | 180,425 | `b992a8ad…ada9` | ✔ | 6,421,414 | 6,421,414 | 6,421,438 |

`full_grad` stat：`exported=1 exp_bytes=40032 cap_bytes=40076 raw_pub=1 raw_drop=0 cmp_drop=0 geom=0 err=0 dup_words=0`。三例无 X/半帧。vsim 3 条 TFMPC 警告为既有 clip 端口连接（b5 同），0 error。

边界（`r0/run_boundaries.py` → `r0/sim/boundaries/`，同一 P1 链路 + 本包 core）：

| case | 结果 | cycles | 关键项 |
|---|---|---:|---|
| odd8x3（8×3 奇数尾块） | PASS | 3,875（r5 3,878） | 单帧、无半帧、header/stream/xform/raw CRC、zlib、raw/xform 逐字节、read_words |
| random64x8（随机 stored 64×8） | PASS | 6,935（=r5） | 同上 + `stored_fallback_observed`（first BTYPE=00） |

双路同步/负对照 RTL 未改，按计划复用 b5 r0 结论，本包未重跑。

## 3. engineering（TD Release_2026.2 / PH1P100SBG484 -3，冻结策略组）

- `01_build.tcl`：唯一改动 = core 路径重定向到本包 `r0/changed-src`（其余与 b5 r0 逐字节同）。
- **综合（syn_1，第 1 次）**：SWNS **+0.280 ns** / STNS 0.000 / 0 违例端点（15,102）；slice\* 16,767；**ERAM 72**（b5 71，+1 = htab_b3）；reg 16,030。
- **布线（phy_1，第 1 次）**：Slow **SWNS +0.119 / STNS 0.000 / 0 违例端点 / 19,779**；Fast corner 0；Hold **+0.020 / 0**；Period Check WNS +2.200；`RUN-0008` timing check 0 issue、routing resource check 0 issue；STA coverage 96.87%。
- **资源（Routed）**：slice 22,608/71,680（31.54%）、lut6 18,743、reg 25,135、**ERAM 102/300**、DSP 0、PLL 4/12。
- **结构证明**：`routed_timing.rpt` 中 `htab_p3v*` 端点组 **完全消失**（r4 的 23 个 `htab_p3v_syn_23.clkb → u_core/bm_b_syn_29.addrb[*]` 违例组不再存在），`bm_b` 的 addrb 也不再出现在最差端点组；`bm_raddr_b` 三个来源 `hf1_r / ext_faddr / raddr` 均为寄存器。S_EXT 状态使能只由 `ext_mis_r`（flop）驱动。
- 门槛：Routed 0 违例 ✔、WNS +0.119 ≥ +0.05 ✔（**caveat：+0.05…+0.20 区间，与 b5 +0.100 同类薄余量**）、TNS 0 ✔、hold ≥0 ✔、period 0 ✔。综合 +0.280 < +0.3（**caveat**，b5 为 +0.222 仍 0 违例）。

## 4. system

- 端口/协议/帧/CRC/DDR/UART 状态包未改（RTL diff 只落在 htab 条目与 bm_b 读地址/扩展比较）；SDC、引脚、时钟、复位逐字节未改（`p2_board.sdc`/`a1_small_top.sdc`/`board_p2.adc`，见 manifest）。
- **板级/下载：not_run**（用户明确本轮不下载；0 次 SRAM 下载、0 次 Flash、未连板/未采集 COM8）。

## 5. G 层

| G | 判定 | 依据 |
|---|---|---|
| G0/G1 | pass（自测） | §2 全部字节/CRC/长度/边界 |
| G2 | pass（离线工程） | Routed 0 违例、WNS +0.119、TNS 0、hold +0.020、period +2.200、ERAM 102/300 |
| G3 | pass（1 bitgen + 1 CWC） | `a1_board.bit` `a2757d40…ffa2` 5,224,022 B；`a1_board.cwc` `dc477c8f…dc57` 110,168 B；`a1_board_inst.bid` `2bf011c5…d730` 96,813 B；`cw/compiled.bit`=`a1_board.bit`、`cw/compiled.cwc`=`a1_board.cwc`（SHA 相同） |
| G4 | not_run | 下载/板级未授权 |

bitgen 放行 STA（`02_bitgen.tcl` 内部 fail-closed 复检）：`setup 0.119/0.000 hold 0.020/0.000 period 2.200`，`candidate_abnormal.rpt` 0 端点。

## 6. 预算消耗

| 项 | 上限 | 实际 |
|---|---|---|
| 开发会话 | 90 min / 50 calls | 单会话（含 P2/P1/边界复跑与 TD 等待），见 §8 |
| TD sessions | 3 | **3**（build / bitgen / cwc） |
| 综合 | ≤3 | **1** |
| 布线 | ≤2 | **1** |
| bitgen / CWC | 1 / 1 | **1 / 1** |
| 下载 | 0 | **0** |

## 7. 与冻结设计指南的偏差（必须由规划/测试者裁决，未隐藏）

- 指南 §4.1「首选 A：提前一拍的 htab p3v 影子读（必要时加一级 bm_a 预取）」**未采用**。
  原因（实测推演）：要满足 `shadow_addr(C) = main_addr(C+1)`，S_SCAN 稳态可用 `hash3(x1_r, bm_a_rd3, bm_a_rd2)`（需 bm_a 加一级并把 praddr 全部重播种），但 S_PRE/S_REPOS 重播种相位（每块 1 次 + 每 match 1 次，P2 comp 约 19,328 次）里同一窗口字节还没进入 bm_a 链（bm[0]/bm[pos] 当拍只在 bm_b 的 ERAM clk2q 上），影子读地址要么取不到、要么把 ERAM→ERAM 搬回影子表地址；而每次重播种相位都补 1 拍等待正好抵消本包要省的 19,200 拍。故改用等价、更小且可判定的结构：把 `bm[ref+3]` 作为条目第 4 字节随插入写入（写口/清表/旁路与主表逐项对齐），命中拍比较源从 bm_b 读数据换成该字段。
- 结果上等价性更强：字节与周期都与 r4 **逐位相同**（P2 comp 355,261、rand 161,479、P1 3,809/5,172/6,421,414），且 bm_b 地址锥只由 flop 驱动、r4 的 htab→bm_b 违例组消失；资源只多 1 个 ERAM（72→102 布线口径，仍在 300 内）。
- 若规划要求严格照 §4.1 实现，本包需退回并重开一个新包（不建议在本轮追加，会超出 1 包/5 步边界）。

## 8. 实际命令 / 退出码 / 超时（摘要，完整见各 json/log）

| 步骤 | 命令（cwd） | exit | 耗时 |
|---|---|---|---|
| P2/P1 编译+仿真 | `python r0\run_sim.py`（r0） | 0 | P2 7.1/5.6 s，P1 2.5/2.3/210.8 s |
| 边界回归 | `python r0\run_boundaries.py`（r0） | 0 | odd8x3/random64x8 各 <4 s |
| TD 环境 | `tools\td\td_env.ps1 -TdDir …\r0\td -Force`（项目根） | 0 | T: 旧映射到 b5 r1-diag，已按脚本提示 -Force 重映射 |
| 综合+布线 | `td_commands_prompt.exe ./01_build.tcl`（r0\td） | 0 | syn 232.7 s，route wait 172.5 s（`P2_PHY_STOP_MARKER_SET` 停 bitgen 前） |
| bitgen | `td_commands_prompt.exe ./02_bitgen.tcl` | 0 | ~90 s CPU |
| CWC | `td_commands_prompt.exe ./03_cwc.tcl` | 0 | 一次导出，`compiled.*` 与父 bit/cwc 逐字节同 |

失败/返工记录：本包 RTL 一次成型（无返工）；唯一阻塞是 TD 盘符旧映射（已 `-Force` 重映射）与 ModelSim `vlib` 不接受 `-modelsimini`、`-modelsimini` 需正斜杠路径（均已在运行器中修正）。

## 9. 交综合测试的复测清单

```json
{
  "required_dimensions": ["integrated", "functional", "engineering", "system"],
  "required_checks": [
    "core SHA = 6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb（80,196 B），核对 rtl-diff-r0.patch / rtl-diff-vs-r4.patch，确认只多 b3 字段、ext 比较源与 bm_b 地址 mux",
    "P2 comp：355,261 cycles、50,310 B、SHA 2601d57cd98d1fe69b2e46fe8423779a5d44bd14c00e1fe2d5faab6ff15a7c05、zlib/strict 0 差异、bp=gap=0 done=1 out_last=1 timeout_hit=0",
    "P2 rand：161,479 cycles、153,766 B、SHA 54f262f2a600a3e2f12129f2937a390737d1ec8018d8f0236979e604760496dd",
    "P1 三例 .dec SHA = fa513a2b…edef / ee61e620…789 / b992a8ad…ada9，cycles = 3809 / 5172 / 6421414",
    "边界 odd8x3 / random64x8：run_boundaries.py 的 checks 全 pass，random64x8 首块 BTYPE=00",
    "工程：syn_gate_timing SWNS +0.280（<+0.3 caveat）、routed_timing SWNS +0.119 / STNS 0 / 0 违例 / 19,779、hold +0.020/0、period +2.200、ERAM 102/300、组合环 0（routed_check_timing.rpt；该 TD 版本无 report_cdc，无时钟网项不在该报告内，与 b5 相同）、STA coverage 96.87%",
    "结构：routed_timing.rpt 无 htab_p3v 端点组；bm_raddr_b = hf1_r/ext_faddr/raddr 全 flop",
    "候选：a1_board.bit a2757d40…ffa2（5,224,022 B）、a1_board.cwc dc477c8f…dc57（110,168 B）、a1_board_inst.bid 2bf011c5…d730（96,813 B）、compiled.bit/cwc 与父文件同 SHA；bitgen/CWC 各 1 次",
    "system：接口/协议/帧/CRC/DDR/SDC/UART 未变；板级/下载 not_run（本轮不授权）"
  ],
  "report_paths": {
    "manifest": "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw/CANDIDATE-MANIFEST-b6-a1-htab-nw-r0.json",
    "hashes": "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw/artifact-hashes.txt",
    "result": "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw/r0/result-r0.md",
    "lessons": "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw/r0/lessons-r0.md",
    "p2": "r0/sim/p2-regression.json", "p1": "r0/sim/p1-regression.json",
    "boundaries": "r0/sim/boundaries/result.json", "sim_commands": "r0/sim/sim-run.json"
  },
  "input_status": "changed（唯一 RTL：r0/changed-src/a1_deflate_core.v；向量/TB/SDC/引脚与 b5 r0 相同，SHA 见 manifest）",
  "reuse_decision_paths": ["r0/sim/boundaries/result.json", "T10.b5-a1-htab-pipe/r0/result-r0.md（双路同步未改，复用理由）"]
}
```

## 10. 明确未做

- 未下载、未 Flash、未连板、未采集 COM8；未做 P3；未碰相机 `cap_frames=0`。
- 未改 `upstream/**`、b5 r0/b1/b2 证据、`workflow/tasks.json`、`D:\TD\work\csi2`。
