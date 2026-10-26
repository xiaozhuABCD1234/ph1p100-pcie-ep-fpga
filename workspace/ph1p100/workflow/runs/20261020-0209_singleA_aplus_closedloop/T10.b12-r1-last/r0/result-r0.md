# T10.b12-r1-last r0 — 开发结果（R1 丢 LAST / 孤儿 writer 修复）

- run：`20261020-0209_singleA_aplus_closedloop`；任务 **T10.b12-r1-last**（批大小 1）；父任务 T10 **保持 blocked**
- 状态：**blocked（R1 功能修复 + 全部仿真回归通过；构建时序门槛未过：Routed SWNS +0.003 < +0.015，两次布线运行一致 → 未 bitgen、未 CWC、未下载；板级 `blocked`：FTDI 不在位）**
- 结论先行：R1 反例在本轮被亲自复现并修复，T1–T10 + P1/v4/full/read 九例全过；**唯一未过的是 dev-plan §6 的布线时序硬门槛**，需规划决定后续（换实现方式/放宽门槛/交由后续任务）。
- 唯一源改动：`camera_a1_uart_top.v`、`a1_ddr_slot_store.v`（其余 7 个 changed-src 与 b11 r0 逐字节相同，见 `rtl-diff-r0.patch`）
- 冻结项：v4 225 B/55 字段、reader FSM、bridge、arbiter、crop、44 B 帧头与 CRC、引脚/SDC/时钟全部未动
- 新开发会话：**未继承上一轮尝试的任何 PASS**。本包 r0 目录里已有的旧产物（15:36–16:12）已整体移入 `r0/prior-attempt/`、`r0/td/prior-attempt/`，只作历史，不作证据（见 §10）

## 1. 交付物

| 项 | 路径 |
|---|---|
| 根因 / 前后对照 | `r0/diag/r1-root-cause.md` |
| 唯一 diff | `r0/rtl-diff-r0.patch`（2 个文件有 hunk，7 个无差异） |
| 候选源 | `r0/changed-src/**`（9 文件） |
| 仿真入口 | `r0/sim/run_b12.py`（组：`r1b11`/`r1`/`t7`/`store`/`b9`/`main`/`multi`） |
| 仿真证据 | `r0/sim/cases/**`、`r0/sim/logs/**`、`r0/sim/sim-results-b12-<group>.json` |
| 构建 | `r0/td/**`（见 §6） |
| 板级 | `r0/board/ftdi-preflight.log` |
| Manifest / 哈希 | `CANDIDATE-MANIFEST-b12-r1-last-r0.json`、`r0/artifact-hashes.txt`（仅在 bitgen/CWC 之后生成） |
| 经验 | `r0/lessons-r0.md` |

## 2. W1 — R1 复现（b11 r0 冻结源，本轮亲自运行）

冻结独立 TB/检查器逐字节复制到 `r0/sim/indep/`（`tb_r1_loss.sv`、`check_r1.py`、`ddr_recovery_model.sv`），
对 **b11 r0 changed-src** 编译运行（`python run_b12.py r1b11`，参数同独立补充验证：
CAM 40x8、ROI(4,2) 32x2、`FIFO_AW=2`、相机 25 MHz、A1/UART 187.5 MHz、`UART_DIV=4`、STS_DIV=0，
唯一故障注入 = 外部 DDR AW/W ready 背压）：

- clean 控制 **PASS**（135 B 物理 UART，四 CRC + 严格 zlib）
- loss 例 **DUT_FAIL_VALID**：外层 clean 前导 PASS；故障窗口 **拒收 7 组（含 1 个 LAST）**；
  释放背压后 `writer_final=1`、`post_release_writer=1`、`slot0=WRITE(1)`、`raw_abort_cnt=0`、`rawdrop=0`；
  两个后续好帧 `begin_deny=2`、恢复包 0、源序列仅 `[11]`；终态 `rawpub=enc=exp=1`，观察 151,559 周期。
- checker 失败项：`recovery criterion failed`、`RAW-slot release / good-frame recovery`、
  `exact recovery source sequence`、`fault RAW slot not FREE`。
- 证据：`r0/sim/cases/r1b11/{clean,loss}/result.json`、`.../loss/trace.txt`、`r0/sim/logs/sim_r1b11_*.log`。

与冻结独立反例（`work/b10-gap-sim-20261025-132023/r1-loss/result.md`：7 拒收含 LAST、`nbytes=45/80`、
`slot0=WRITE`、`raw_abort_cnt=0`、`begin_deny=2`、151559 周期）逐项一致。

## 3. W2 — R1 修复（只改 2 文件）

1. `camera_a1_uart_top.v` clk_cam：`fifo_wvalid && !fifo_wready`（SOF/中间/LAST 任一拍）→ `abort_hold<=1`，
   sticky 直到 abort beat 被 FIFO 接收；`fifo_ovf_cnt` 保留，只统计 `crop_valid && !fifo_wready`。
2. `camera_a1_uart_top.v` A1：`fifo_ready` 末尾 `else fifo_ready = 1'b1;`（无主 stray data beat 只消费、不写、不发布）。
3. `a1_ddr_slot_store.v`：`abort_now`/`begin_now`；`accept` 加 `!wr_abort`（同拍 LAST 不写、不 flush、不发布）；
   `wr_begin_ready` 加 `(!wr_active || abort_now)`；写侧优先级 `abort+begin > abort > begin > 数据`。

不变式（全部有用例支撑）：坏帧不发布、槽不泄漏、好帧字节不变、v4 225 B 不变、无新增 CDC。

## 4. W3 — 定向用例与回归（全部实跑）

| 用例 | 结果 | 关键数字 / 证据 |
|---|---|---|
| **T1** clean 控制（独立 TB） | **PASS** | 135 B、四 CRC+zlib：`cases/r1/clean/result.json` |
| **T2** 7 组拒收含 LAST → 两好帧恢复 | **PASS** | `rejects=7`、`last_reject=1`、`rawdrop=1`、`raw_abort_cnt=1`、`begin_deny=0`、`post_release_writer=0`、`slot0=0`、`rawpub=enc=exp=3`、源序列 `[11,1000,1001]`（ID 1/2/3）、405 B 四 CRC+严格 zlib、31,559 周期：`cases/r1/loss/result.json` |
| **T3** 同拍 LAST+abort（store 单元） | **PASS** | `pub=0 drop=1 abort=1`、abort 拍 `wr_ready=0`、当拍无 DDR 写、槽 FREE、下一帧发布并读回 10 字：`sim-results-b12-store.json` |
| **T4** 同拍 begin+abort | **PASS** | 有 FREE 槽：`begin_ready=1`、旧槽 FREE、新槽 WRITE、`wr_slot=1`、无两个 WRITE、新帧发布；无 FREE 槽：`begin_ready=0`、仅 abort、随后 begin 成功；3 次读回逐字节（30 字） |
| **T5** 中写复位 | **PASS** | `wr_active=0`、两槽 FREE、计数清零、`rd_open_ready=0`（无 ghost READY）、下一帧发布/读回 |
| **T6** 满槽并发 | **PASS** | slot0 READY 保持、只释放 slot1、slot0 读回逐字节、`dup=0`、下一帧复用 slot1（20 字） |
| **T7** SOF 拒收变体（顶层） | **PASS** | `sof_reject=1`、`last_reject=2`、释放后 **32 周期**排空（`post_release_writer=0`、`raw_abort_cnt=1`、`rawdrop=1`、两槽 FREE）、seed300 单帧 135 B 四 CRC+严格 zlib、`exp=1`：`cases/t7/result.json` |
| **T8** b9 `CASE=abort` | **PASS** | `words=129600 beats=558401 cyc=2550292`，与 b9 基线逐项相同 |
| **T9** b9 `nofree`/`rdy` | **PASS** | `nofree: words=388800 cyc=7531072`、`rdy: words=129600 cyc=3628508`，与 b9 基线逐项相同 |
| **T10** 三帧小几何 | **PASS** | control + triple；帧源 111/222/333、帧字节 sha256 `7ffbaf09…/e346461c…/6393a9f4…` **与 b10 黄金三帧完全相同**；22 个 v4 状态包全部严格在帧间（`status_grants=22`、`boundary_due_queued=22`、`ticks_in_frame=9`、`assert_fails=0`）、物理 UART 7080 B（225 B/包）、四 CRC+严格 zlib+独立参考全过 |
| P1 三黄金 | **逐字节一致** | micro8x2 `fa513a2b…`、mid64x8 `ee61e620…`、full_grad `b992a8ad…`（与 b5/b10/b11 冻结 goldens 同哈希） |
| v4 状态包 | **PASS** | `packets=3 bad=0 len=225 ver=4 fields=55` |
| 集成两帧（真核 1920×1080） | **PASS** | `enc=2 exported=2 read=259200 dup=0 err=0 wd=0`；bridge `ar=261704 r=261704 rlast=261704 stale=0 block=0`（750 s） |
| b11 read 九例 | **全 PASS** | one/multi/bp/late/stray/dup/reset/full 全 `pass=1 bad=0`；`read_full` 129600/129600 |
| 计数 | 正常路径干净 | P1、v4、read 九例、T10、full 的 `raw_drop/raw_abort_cnt` 均为 0；仅故障用例 T2/T3/T4/T6/T7 非零 |

**T10 的 TB 说明（唯一 TB 侧改动，不影响判据）**：冻结 b10 三帧 TB 早于 v4，未连接纯观测输入 `i_dbg_bridge`，
导致 v4 扩展字段为 4 态 `z`（22 包 × 24 B），解析器无法逐包校验。本包在 `r0/sim/tb_b10_multi_b12.sv` 的副本里
仅新增 `.i_dbg_bridge(192'd0)`（消除 4 态），stimulus 与全部判据一字未改；帧字节 sha256 与 b10 黄金三帧完全相同，
证明数据通路未变。此前“3015 B / 5 个状态包”是 b10 的 177 B 包口径，本包是 v4 225 B 口径，故总字节/包数按 v4 计。

## 5. 复测清单（交综合测试者）

- required_dimensions：`functional`、`engineering`、`system`
- required_checks：
  1. `python -B r0/sim/run_b12.py r1` → `r1_clean PASS`、`r1_loss PASS`（T1/T2）
  2. `python -B r0/sim/run_b12.py r1b11` → `r1b11_clean PASS`、`r1b11_loss DUT_FAIL_VALID`（负对照）
  3. `python -B r0/sim/run_b12.py store` → t3/t4/t5/t6 `pass=1`
  4. `python -B r0/sim/run_b12.py t7` → `status=PASS`
  5. `python -B r0/sim/run_b12.py b9` → abort/nofree/rdy `pass=1`
  6. `python -B r0/sim/run_b12.py multi` → control/triple `status=PASS`
  7. `python -B r0/sim/run_b12.py main v4 p1 read full` → 13 项 `ok=True`
  8. 构建：**本包未 bitgen**（见 §6）；如需继续，按 `r0/td/{01_build.tcl,02_bitgen.tcl,03_cwc.tcl}` 复跑
  9. 板级：只核对 `r0/board/ftdi-preflight.log`（`FTDI_PRESENT=0`，0 下载 / 0 COM8）
- report_paths：`r0/diag/r1-root-cause.md`、`r0/result-r0.md`、`r0/sim/sim-results-b12-*.json`、`r0/td/routed_qor.rpt`、`r0/td/routed_timing_status.rpt`
- input_status：**changed**（相对 b11 r0：2 个 changed-src 文件 + 构建/TB 输入路径）
- reuse_decision_paths：`r0/sim/indep/**`（冻结反例 TB/检查器，只读复制）

## 6. W4 — 重建与时序裁决

| 项 | 布线 run 1 | 布线 run 2（同一脚本、同一参数） |
|---|---|---|
| Routed SWNS / STNS | **+0.003 / 0.000** | **+0.003 / 0.000** |
| Routed HWNS / HTNS | +0.020 / 0.000 | +0.020 / 0.000 |
| 违例端点 / 总端点 | **0 / 25697** | **0 / 25697** |
| Period Check WNS | +2.200 ns | +2.200 ns |
| 综合 SWNS | +0.121 | +0.121 |
| 资源 | slice 18370、reg 19539、**ERAM 72**（+CWC ≤ 300 满足） | 同 |
| bitgen / CWC | **未执行** | **未执行** |

- 命令：`tools/td/td_env.ps1 -TdDir ... -Force` + `td_commands_prompt.exe 01_build.tcl`（cwd=`T:`），脚本与 b11 相同，仅 9 条 `add_files`/`a1_board.al` 的 `<File Path>` 指向 b12 changed-src（未改任何参数/seed/约束）。
- **最差 setup 路径**：`u_a1/u_a1/u_core/len_r_reg[6]_syn_2.clk → u_a1/u_a1/u_core/add9_syn_221.fci`
  （A+ 核心内部进位加法链，Path Group clk_a1，Data Path 4.796 ns = cell 2.550 + net 2.246，skew 0.259，uncertainty 0.211，logic level 6）。
  **不在** vendor DDR PHY、**不在**本轮改动的 `camera_a1_uart_top`/`a1_ddr_slot_store`/v4 观测路径，
  因此 dev-plan §6 的“只减观测”精简不适用（删 #50/#55 或邮箱宽度不会缩短该核心加法链），未做任何精简、也未改 SDC。
- 裁决（按 dev-plan §6/§8，不自行放宽）：**Routed SWNS +0.003 ns < 硬门槛 +0.015 ns，两次布线运行结果逐位一致（确定性），
  且最差路径落在冻结的 A+ 核心而非 vendor PHY 或本轮逻辑 → 停止：不 bitgen、不 CWC、不下载，交规划决定后续。**
  本包因此**没有** bit/CWC/BID 哈希可冻结；`a1_uart_export.v` 仍是 b11 原样（`69b73de4…`），v4 225 B 未动。
- 产物：`td/routed_qor.rpt`、`td/routed_timing_status.rpt`、`td/routed_timing_summary.rpt`、`td/routed_timing.rpt`（run 2）、
  `td/route-run1-*`（run 1 原始报告，保留对照）、`td/build_console_b12.log`、`td/drive_build*.log`。
  旧 `a1_board_Runs` 已移动到 `td/a1_board_Runs_run1/`（未删除）。
- 说明：b11 r0 的 +0.015 与上一轮尝试的 +0.010 同样落在这一薄余量区间，本轮两次均为 +0.003，
  说明该核心加法链的净延迟（2.246 ns，占 47%）对布局非常敏感；这不是 R1 修复引入的路径（R1 只增加 store 的
  `abort_now/!wr_abort` 门控与一个 FIFO 消费分支，均不在该路径上，且综合 SWNS 仍为 +0.121）。

## 7. W5 — 板级（条件执行）

- 预检：`Get-PnpDevice -PresentOnly` 查 `VID_0403&PID_6042` → **不在位**（`FTDI_PRESENT=0`），
  无任何 FTDI 设备（在场 USB 只有 HID/BT/集线器/读卡器类），COM 端口只有板载串口。
- 结论：`board=blocked`、`board_blocked_reason=FTDI_0403:6042_absent`、**下载 0 次、COM8 打开 0 次、Flash 0 次、不重试**。
- 证据：`r0/board/ftdi-preflight.log`。本包**不宣称任何板级结论**，也不把 R1 修复与 1176 读停点混为一谈。

## 8. 未测边界与风险

- T1/T2/T7 为缩小几何（32×2、`FIFO_AW=2`、相机 25 MHz、STS_DIV=0），不证明满速/512 深 FIFO 下的触发概率。
- b9 store 回归是 1920×1080 写读逐字节，但 DDR 仍是行为模型，不是真实 DDR/PAXI。
- 未 bitgen、未上板：无板级证据，无“修复在硬件上有效”的结论。
- 1176 读响应停点仍为 H2/H4（`r0/sim` 的 read 九例全过、`read_full` 129600/129600 只说明 A1 侧与 bridge 模型无缺陷），本包未触碰、未猜修。
- §6 run 1 的 +0.003 是**未通过**的门槛；若规划接受，也只能是“功能/诊断候选（薄余量 caveat）”，不是板级签核。

## 9. 预算与命令

- 开发用时约 **105 分钟**（开工 18:12 / 收尾约 19:57，预算 120）、工具调用约 **76**（预算 60，**超支 16**，原因见下）。
  超支主因：① 本包 r0 已存在上一轮产物，识别/迁移并重建证据链额外花 6 次调用；② 同拍用例的组合采样假失败与 T7 种子表各需 2 次修正；
  ③ 两次布线运行各需一次有界等待。未因此缩减任何必做检查（T1–T10、P1 三黄金、v4、full 两帧、read 九例全部实跑）。
- TD **2 会话**（预算 3）、综合 2 次（≤3）、布线 2 次（≤2）、**bitgen 0**（预算 1）、**CWC 0**（预算 1）、下载 **0**（预算 1）、Flash 0。
- 命令/退出码：`r0/sim/logs/drive_*.log`、`r0/sim/logs/vlog_*.log.out`、`r0/sim/logs/sim_*.log`、
  `r0/td/drive_build.log`、`r0/td/drive_build2.log`、`r0/td/build_console_b12.log`。
- 并行执行：7 个仿真 group 各用独立 work 库与独立 `sim-results-b12-<group>.json`，与 TD 构建并行（未互相干扰）。

## 10. 与上一轮尝试（prior-attempt）的关系

- 本包 r0 在本次开发开始时已存在 15:36–16:12 的另一轮尝试产物（`result-r0.md` 带 `@@TD@@` 占位、
  `rtl-diff-r0.patch`、`sim/run-*`、`sim/T10`、`td/a1_board_Runs`、`td/build_console_b12.log` 等），
  其 `changed-src` 已被本次从 b11 基线重建覆盖，**无法复原、也不作为证据**。
- 处理方式：全部**移动**（未删除）到 `r0/prior-attempt/` 与 `r0/td/prior-attempt/`；本轮所有结论均来自本轮实跑的
  `r0/sim/cases/**`、`r0/sim/logs/**`、`r0/td/routed_*.rpt`。
- 可交叉核对的一致性：旧尝试记录的 T10 三帧帧字节 sha256（`7ffbaf09…/e346461c…/6393a9f4…`）与本轮完全相同，
  说明两轮独立修复都没有改变帧数据通路。
