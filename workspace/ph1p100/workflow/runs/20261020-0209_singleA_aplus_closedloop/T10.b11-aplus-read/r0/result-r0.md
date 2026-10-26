# T10.b11-aplus-read — result r0（**diagnosis_only**）

- run：`20261020-0209_singleA_aplus_closedloop`；包：`T10.b11-aplus-read` r0；日期 2026-10-25
- 父任务 T10：**保持 blocked**（本包不关闭 T10）
- 状态：**diagnosis_only**（dev-plan §5 第二分支）。读停点未能在 A1 RTL 内归因，因此**没有做猜测性功能修复**；
  交付 v4 状态包 + 有界看门狗 + 判别链，供下一次板级抓包直接判定 H2/H4。
- 未达成：目标（`enc_frames/exported` 增量 > 0）与“≥1 帧 44 B 头 + 四 CRC + zlib 解码”**未验证**（板级被 JTAG 设备不在线阻塞，见 §4）。
- 另有一条门槛未达成：布线 `WNS=+0.015 < +0.05`（0 违例、hold/period 正），见 §3。

## 1. 结论先行

1. **A+ 核没有死锁**（沿用 b10 规划结论，本包未推翻）：`a1_busy=frame_active`、`a1_in_ready=1`、`fstate=F_WAIT`，
   核在等数据；`a1_in_valid=0` 只是 feeder 没有 `raw_rd_valid`。
2. **1176 vs 1177 的断链不在 A1 RTL 的读通路**：`a1_ddr_slot_store → a1_ddr_arb2 → p2_ddr_bridge` 在静态结构上
   保证“每 AR 恰好一个 R”，且我用真双时钟、真 arbiter/store/bridge 的 129,600 字整帧读回逐拍比对 **bad=0**（见 §2）。
   H1/H3 结构性排除；剩下 **H2（AR 进了 AF FIFO 但不再被 PAXI 弹出：`ddr_rdy=0` / `paxi_arready=0` / `ar_pending` 卡死）**
   与 **H4（PAXI 收了 AR 不回 R）**，两者都在 A1 RTL 写域之外，需要板级 #44–#50 判别。
3. 1176 不是地址/行列边界伪影（字地址 1176 = DDR3-1600 x32 的行 1 / 列 152），只能是计数/事件造成的停点。
4. v4 状态包按冻结格式实现并仿真通过：**225 B、LEN=0xE1、VER=4、55 字段、XOR 覆盖 0..223，全字段逐字节正确**；
   #1–#43 与 v3 同源同序（P1 三黄金逐字节一致作为功能等价证明）。
5. 构建：**Routed 0 违例（25627 端点）、SWNS +0.015 ns、HWNS +0.020 ns**。
   ⇒ **布局布线余量门槛 WNS ≥ +0.05 ns 未达成**（+0.015 满足 ≥0 与 0 违例，但不满足余量要求），记 caveat。
   bitgen/CWC 按其自身 STA 门槛（sw≥0/hw≥0/period≥0、0 违例）执行。

## 2. 局部检查（实际命令与结果）

驱动：`r0/sim/run_b11.py`（ModelSim ASE 10.5b，`D:\intelFPGA\18.1\modelsim_ase\win32aloem`，独占库
`%TEMP%\opencode\b11\simwork`）。日志：`r0/sim/logs/*.log`，汇总 `r0/sim/sim-results-b11.json`。

| 检查 | 命令 | 结果 |
|---|---|---|
| 编译 | `run_b11.py compile` | vlog 0 error 0 warning（含 `+define+SIMULATION`） |
| v4 包 | `run_b11.py v4` | `B11_V4_RESULT pass=1`：packets=3、bad=0、len=225、ver=4、fields=55；无 `B10_ASSERT_FAIL` |
| 读通路 one/multi/bp/late/stray/dup/reset | `run_b11.py read_one ... read_reset` | 全部 `pass=1`，`bad=0`；stray/dup 只增 `stale_r_cnt`，不位移 |
| **整帧读回** | `run_b11.py read_full`（NWRITE=129600） | **`pass=1` words=129600 bad=0**，ar_hs=r_cnt=rlast=129601 |
| P1 三黄金 | `run_b11.py p1` | micro8x2 `fa513a2b…`、mid64x8 `ee61e620…`、full_grad `b992a8ad…` **逐字节同冻结基线** |
| 集成两帧全尺寸 | `run_b11.py full`（真 1920×1080、真 A+ core、真 bridge CDC） | **`pass=1`**：`enc=2 exported=2 read=259200 dup=0 err=0 wd=0`，`ar=r=rlast=261704 stale=0 block=0`（首次因 drain 太短未跑完，加长 drain 后通过） |

## 3. 构建（`r0/td`，`T:`=`r0/td`、`Y:`=项目根，`td_commands_prompt.exe 01_build.tcl`）

- 综合：`P2_SYN_SWNS=0.043 STNS=0.000 SLICE=18660 ERAM=72 REG=19523`（正余量，1 次）
- 布线：`P2_ROUTED_SWNS=0.015 STNS=0.000 HWNS=0.020 HTNS=0.000 VIOL_EP=0 TOTAL_EP=25627`（1 次）
  - **WNS+0.015 < 门槛 +0.05** → 本条门槛 **未通过**（无违例、hold/period 均正）。
  - 未做第二次布线：策略/参数/种子冻结，重跑确定性相同（b10 经验“两次逐位相同即停”）。
- 资源：b10 r1 为 ERAM 102 / DRAMHARDCON 85（合计 187 ≤ 300）；本包 ERAM=72（综合），CWC 映射见
  `r0/td/cwc_console_b11.log` / `routed_area.rpt`。
- bit/CWC：见 `r0/td/{a1_board.bit,a1_board.cwc,a1_board_inst.bid}` 与 `artifact-hashes.txt`（bitgen 1 次、CWC 1 次）。

## 4. 未做 / 未测（明确边界）

- **板级下载被硬件阻塞**：`r0/board/download_sram_b11.tcl` 两次尝试均返回
  `mpsse.cpp:90 device not found` + `PRG-8000 Hardware server start timed out`
  （FTDI 0403:6042 未枚举，JTAG 电缆/板子当前不在线）。**实际下载次数 0/2，未写 SRAM/Flash，未开 COM8。**
  因此 `enc_frames/exported` 增量、44 B 头/四 CRC/zlib、v4 实包数量均**未验证**。
  日志：`r0/board/download_sram_b11.log`。
- 未验证：v4 包在真实 115200 波特流中的错帧/重启行为（仿真只覆盖 exporter idle 边界）。
- 未做：reader 侧读超时中止（会改 reader 语义，需先证明 reader 有责），见 lessons §6。

## 5. 回退

源与 bit 均以 b10 r1 冻结件为基线；本包不改 upstream、旧 run、证据与 `workflow/tasks.json`。
若需回退，只需把 `a1_board.al` 的 `<File Path>` 指回 `T10.b10-b9-fix/r0/changed-src/**` 并重建。

## 6. 下次启动建议（交规划）

1. 若接受 SWNS +0.015（0 违例）作为**诊断候选**：直接烧本包 `r0/td/a1_board.bit`（SRAM，≤2 次），
   跑 `board/parse_status_v4.py` 读 #44–#50，按 `diag/read-stall-analysis.md` §6 判定 H2/H4。
2. 若必须满足 +0.05 余量：优减观测逻辑（例如只保留 #44/#45/#47/#49 四字、去掉邮箱中的 wstate/aw_seen/w_seen/wf_*）
   或允许第二次构建，再走 P1 三黄金 + 构建。
3. 判定为 H4 时按计划停止（DDR IP/PAXI 侧，不在 A1 RTL 写域）。
