# T11.BRD.P1 — 结果（round 0）

## 0. 承接事实（必须置顶，不随本轮结论改写）

**P4 = ⚠**：`INT.P4` r2 的功能与系统检查 pass，但 G2（时序）fail——112 个违例端点、
WNS −0.637 ns、TNS −69.776 ns（187.5 MHz、仅内部寄存器、42 IO 的孤立综合）；
r3 虽然 G2 达 0 端点 / +0.072 ns，但其派生变体（`algo_rowwin3_p4.v` / `gray8_gaussian3x3_stream_p4.v`）
等价性 fail，**不能**作功能输入。本包功能核只取 r2（`INT.P4-r2-manifest.json`
SHA256 `DFAB7F9D7FF7B7F8FB1D9B4401844F3D76102064C99FC4338192FB8A0C59B32E`）。
**r2 的功能证据与 r3 的时序数字不得拼接**；本包报告的时序数字只属于本板级顶层，
与 P4 的 187.5 MHz 数字、与 r3 数字都无关。**本包未出 bit、未下载、未上板。**

## 1. 交付物（实际存在）

| 类别 | 路径 |
|---|---|
| 板级顶层 | `fpga/csi2/src/board_integration/brd_integrated_top.v`（`module brd_integrated_top`，继承参考 43 个端口） |
| 板级数据通路 | `.../board_integration/brd_board_datapath.v` |
| 相机前端（crop+43b CDC+unpack） | `.../board_integration/brd_cam_fe.v` |
| CDC 邮箱（C4–C7 + C6b） | `.../board_integration/brd_cdc_mailboxes.v` |
| DDR 读仲裁 | `.../board_integration/brd_ddr_rd_arb.v` |
| clk_core 150 MHz PLL | `.../board_integration/brd_a1_core_pll.v` |
| 只读复制件 | `.../board_integration/{a1_raw_crop.v,p2_ddr_bridge.v}`（b18 原字节） |
| 约束 | `T11.BRD.P1/td/brd_board.sdc`、`T11.BRD.P1/td/ph1p_pcie_case_ep.adc`（参考原字节） |
| 构建入口 | `tools/board_integration/run_td.ps1`、`td/{filelist.tcl,01_synth.tcl,02_route.tcl,03_bitgen.tcl,04_cwc.tcl}` |
| G1 仿真 | `T11.BRD.P1/sim/tb_brd_g1.v`、`tools/board_integration/run_sim.ps1` |
| 文档 | `cdc-list.md`、`build-entry.md`、`lessons.md`、本文件 |
| 位流 / CWC | **无**（见 §4） |

## 2. G0 端口 / 时钟 / 复位 / CDC（冻结核对）

- 顶层端口集 = 参考 `ph1p_pcie_ep_top` 的 43 个端口，未新增 `sys_rst_n`/HDMI/`O_uart_txd` 等同义端口；
  `pcie_power_on_rst`（R14）只出现一次。
- 引脚：43 个端口中 22 个由 `ph1p_pcie_case_ep.adc` 指定；其余 21 个（`ref_pad_clk_p/n`、`pcie_rx/tx_p/n`、
  `ddr_*`）由 IP 的 `set_ippin_assignment` 提供（与参考工程一致）。综合成功、无未分配引脚报错。
- 时钟：`sys_clk` 50 MHz、`clk_core` 150.000 MHz（新 PLL，`REFCLK_DIV=3/FBCLK_DIV=90/CLKC0_DIV=10`）、
  `cam_a/b_byte_clk` 187.5 MHz、`tl_clk_user` 62.5 MHz（TD 报出）、`usr_clk`（DDR IP）。
- 复位：每域异步置位/同步释放；`clk_core` 域 `r_core_rst_cnt` + `core_pll_lock`。
- CDC：C1–C7 逐项落地，另加 C3b（`ddr_rdy` 单比特 2FF）与 C6b（P4 状态快照回 tl 域），
  实例名与结构见 `cdc-list.md`。

## 3. G1 缩尺仿真（实际结果）

几何缩尺：相机 128×96、ROI 64×48（768 组/帧）、槽 1024 字（32 KiB）、`FIFO_AW=10`；
被测对象是**同一个** `brd_board_datapath`（crop → 43b CDC → P4 r2 → bridge → 仲裁 → pusher → TLP），
只有 DDR/PCIe 硬 IP 被 TB 的模型替换（DDR AXI 从模型、TLP 主机模型、BAR 寄存器模型、相机模型）。

### 3.1 正例（SCEN=0）：**FAIL**

| 检查 | 结果 |
|---|---|
| 相机帧完整性 | **PASS** — 768 组、abort=0、FIFO 溢出=0、行计数回绕正确 |
| P4 提交 | **PASS** — `st_frames_committed=1`、`st_store_published=1`、`st_drain_words=124` |
| 描述符 ARM（`desc_arm`） | **FAIL** — 始终为 0，`st_exported=0` |
| DDR 槽读 / MWr TLP / doorbell | **0 条**（因未 ARM，pusher 一次都没启动），`tx err` 先报 06 |
| 逐字节比对 | 未执行（没有 TLP 可比对，不能算 pass，也不能算 mismatch） |

根因边界：帧采集与压缩链路已通到"提交"，断在 P4 出口适配器没有发出 `desc_arm`。
本轮未定位到具体触发条件（未读 `aplus_pcie_egress_adapter` 的 ARM 判据细节），交下一轮。

### 3.2 负例

| 负例 | 结果 |
|---|---|
| 读仲裁：突发中不换手 + 迟到拍 | **PASS**（`g1_arb.log`）：burst 内没有任何 grant 给另一路、bridge 恰好拿到它的单拍、迟到拍只计数一次且未重路由、`o_switch_err=0` |
| 缺 EOF → 不 arm | **not_run**（依赖同一条导出通路；在正例不 ARM 的情况下该判据会变成空过，不具证明力） |
| 错误 ACK → 不释放 | **not_run**（同上） |
| 0 X / 无死锁 | 复位修正后无 X；正例在 12.8 ms 处按 TB 判据结束，不是死锁挂死 |

### 3.3 仿真过程中查实并修正的两个真实 RTL/集成缺陷

1. `brd_cam_fe` 原先把 `a1_raw_crop.out_last` 当行末用；该信号其实是**整幅 ROI 的最后一组**，
   导致 `eof` 永远不成立（P4 判帧失败）。改为按 `grp_cnt/row_cnt` 重建 `eol`，`eof` = 第 H-1 行最后一组。
2. 相机域复位在 TB 里未释放时整域为 X（`cam_rst_n` 直接接 1），已由 TB 复位序列修正。

## 4. G2p 真实约束 STA（本包核心结论）

- 综合：`td/brd_board_Runs/syn_1`（TD Release_2026.2，`launch_runs syn_1`，单会话，180 s）。
- **判定口径**（`flow.status` / `gate.qor`）：
  - Setup **WNS = −2.273 ns**、TNS = −31.547 ns、**违例端点 79**
  - Hold WNS = 2147483647 ps（basic 模式下无 hold 端点，即 0 违例，但也不是"已验证 hold"）
- 资源（fit）：slice 14,870 / 71,680（20.74%）、LUT 19,962、REG 15,226、ERAM 41 / 300、
  DSP 0/220、IO 107/286、PLL 4/12、`#pcie 1/1`、`#ddr_byte 7/24` → **全部在器件内**。
- 按 `fpga-design-guide.md` §5 冻结次序：150 MHz 的 synth WNS −2.273 ns < **+0.127 ns** →
  **不布线**；应改 125 MHz 做 synth#2。
- **125 MHz 未执行**：本包 TD 会话额度 4 次已用尽（2 次在 elaborate 阶段失败：HDL-8007、缺 include；
  1 次路径转义失败；1 次成功综合），synth 也已达 3 次上限。
  因此 `route`/`bitgen`/`CWC` 一次都没有启动，**本包 0 位流**。
- 未启动布线 ⇒ 没有 routed 的 0 违例结论、没有 `candidate_timing.rpt`、没有未约束 IO 的逐条清单
  （`report_timing_ignored` 只在 `03_bitgen.tcl` 里跑）。
- 结论：**G2p = fail（no bit）**。这是指南 §5 明确允许的停止点（"不出 bit 并返回规划"），
  但严格说只测到 150 MHz 一档，125 MHz 档因额度用尽未测。

## 5. G5 构建入口 / 可复现性

- `td/filelist.tcl` 是唯一源列表，含守卫：`*.v.stale`、`*/src/src/*`、`peer-ref-2a4b253`、
  `*/integrated_delivery/algo_rowwin3_p4.v`、`*/integrated_delivery/gray8_gaussian3x3_stream_p4.v`、
  缺文件 → 直接 `error`，不进综合。
- P4 r2 的两个 `_p4` 依赖按 **r2 manifest 哈希**从
  `workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4/r2-timing-experiment/` 取
  （`F3F345ED…` / `158AAE4D…`）；`src/integrated_delivery/` 下的同名文件是 r3 版本
  （`863932B3…` / `B8096430…`），被守卫拒绝。见 `lessons.md` §1。
- `T:` 由 `run_td.ps1` 用 `tools/td/td_env.ps1 -Force` 重指到本 run；`Y:` 校验为项目根；
  构建前预检他人 `pnmain`/`td_commands_prompt`（存在即 blocked）。
- 未执行 `upstream/.../download_sram.tcl`；`download=0`、`flash=0`。

## 6. 与冻结指南的偏差（须规划确认）

1. **槽参数**：`SLOT_WORDS=81920`（640 KiB，4 KiB 对齐）、`SLOT_BASE_WORD=2048`（字节 0x1_0000）。
   指南 §8 写的 81085 / 基址 0 与本包只读复用的 `ddr_frame_pusher` 的 ARM 判据
   （要求 `ddr_base != 0` 且 `ddr_base[11:0]==0`）冲突：81085 字 = 2,594,720 B 不是 4 KiB 倍数，
   槽 1 基址永远非法。P4 r2 **源码零改动**，只改例化参数。若规划要求回到 81085，
   必须先允许改 pusher 判据或另做槽映射。
2. **BAR 0x130..0x13C 与 CTRL[9..11] 未实现**：`ep_bar_win.v`/`pcie_ep_engine.v` 是只读保护文件，
   本轮未做只读副本改造。因此 `a_enable` 固定 0、`trigger_mode` 固定 0、`p4_desc_owner` 固定 1；
   P4 状态字在 RTL 内聚合成 `o_p4_st[127:0]`（`brd_board_datapath`），但**主机暂时读不到**。
3. **DDR 地址映射 ×4**：P4 输出 256-bit 字索引，`p2_ddr_bridge` 转成 ×8，而参考写者/推帧用字节地址
   （32 B/拍），故在 bridge 的 PAXI 侧统一再 ×4。仅在 G1 仿真（自建字节寻址模型）验证，**硬件未验证**，
   P2 必须首先确认。
4. **A 路**：双 CSI 前端与双 `brd_cam_fe` 都在网表里，但 P1 只验证 B 路（`a_enable=0`）；
   A 路描述符被 `a_enable=0` 门控，未做 A 路仿真。
5. `cfg_phase`（Bayer 相位）仍为 0（b18 未板证占位）；`prep/pred=1/1` 取 b18 板级已证值。

## 7. 未证明 / 未运行（必须如实继承）

- 位流、CWC、下载、上板、真实 PCIe 传输、主机/RK 解码：全部 **not_run**（P1 不下载；额度 0 消耗）。
- 1080p30 实测、长稳/吞吐（G4）：not_run（用户后置）。
- A 路真实像素：未验证。
- 本包任何"仿真通过"都不代表硬件行为；任何"综合资源 fit"都不代表时序通过。
