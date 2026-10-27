# T11.BRD.P1 — lessons（可复用根因 / 触发 / 修正 / 验证入口）

本轮为 round 0。以下每条都在本包实际踩到并已定位，供后续包与规划复用。

## 1. P4 "r2 基线"的两个 `_p4` 依赖其实是 r3 版本（最危险的一条）

- **根因**：`fpga/csi2/src/integrated_delivery/` 目录里现在放着的
  `algo_rowwin3_p4.v`（sha `863932B3…`）与 `gray8_gaussian3x3_stream_p4.v`（sha `B8096430…`）
  **不是** r2 用的版本。`INT.P4-r2-manifest.json` 登记的是 `F3F345ED…` / `158AAE4D…`，
  对应文件现在在 `workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4/r2-timing-experiment/`。
- **触发**：`bayer_raw10_demosaic4_p4.v` 例化 `algo_rowwin3_p4`、
  `img_algo_parallel_top_p4.v` 例化 `gray8_gaussian3x3_stream_p4`，二者缺一不能 elaborate。
  若直接按目录名取文件，就会把 r3 派生变体静默编进板级位流——正是本 run 明令禁止的。
- **修正**：filelist 显式指向 `r2-timing-experiment/` 的两份 **r2 哈希**文件；
  `filelist.tcl` 守卫对 `*/integrated_delivery/algo_rowwin3_p4.v`、
  `*/integrated_delivery/gray8_gaussian3x3_stream_p4.v` 直接 error。
- **验证入口**：`td/filelist.tcl` 的 guard 段 + 本包 manifest 的 `p4_dependencies` 段（含两个 SHA256）。
- **教训**："目录里有什么就编什么"在本项目会直接把 r3 源拼进 r2 功能基线。任何 P4 相关构建都要按 manifest 哈希取文件，不按目录取。

## 2. TD 的 HDL-8007：clocked block 里 `if` 不能引用同块内赋值的 reg

- **触发**：`brd_ddr_rd_arb.v` 里 `always @(posedge clk or negedge rst_n)` 内写
  `if (r_hs && !busy)`（`busy` 在同一 always 里被赋值）→
  `HDL-8007 ERROR: if-condition does not match any sensitivity list edge`，模块变黑盒，综合失败。
- **修正**：把这类判断改成**赋值右侧的算术/三目**：
  `o_late_cnt <= o_late_cnt + {{31{1'b0}}, (r_hs & ~busy)};`、
  `beats_left <= (beats_left == 0) ? 0 : beats_left - 1;`。
  同理把几处"值变化才发一次"的写法改成
  `wire go = (bus != prev) & free; ... hold <= go ? bus : hold;`。
- **验证入口**：`td/brd_board_Runs/syn_1/run.log`（应无 HDL-8007/1007）。
- **代价**：这条各烧掉一次综合机会（本轮 3 次额度里 2 次是它和下面的 include 问题）。

## 3. 复制只读模块时必须检查文件内 `include` 的相对路径

- **触发**：把 `ddr_frame_pusher.v` 复制到 `board_integration/` 后，文件内
  `` `include "../../common/TLP_FMT_TYPE.v" `` 相对原目录才成立，复制后编译报
  "Cannot open include file" + 一堆宏未定义语法错。
- **修正**：`ddr_frame_pusher.v` **不复制**，filelist 直接指向
  `fpga/csi2/pcie_integration/rtl/ep_side/ddr/ddr_frame_pusher.v`；同时把误复制的同名文件
  改成不含 module 的说明文件，避免出现重复 `module`。
- 同理 `brd_integrated_top.v` 复制后其 `` `include "../common/ph1p_pcie_case_param.v" ``
  失效，改为 `"../../pcie_integration/rtl/common/ph1p_pcie_case_param.v"`。

## 4. `tools/td/td_env.ps1` 的目录契约与 `td_commands_prompt.exe` 的 Tcl 转义

- `td_env.ps1` 要求 TdDir 里存在 `a1_eng_top.v` + `a1_small_top.sdc` 才允许重指 `T:`。
  本包用两个**注释占位文件**满足检查（不含 module、不在 filelist、不被编译），已在
  `build-entry.md` 注明；不要把它们当成真实源或约束。
- `td_commands_prompt.exe` 把参数交给 Tcl 解释，**反斜杠 Windows 路径会被当转义吃掉**
  （`D:\fpga\...` → `Dpgaph1p100...`）。`run_td.ps1` 现在统一把脚本路径转成 `/` 再传。

## 5. 推帧引擎（只读）对 DDR 槽基址有硬约束：4 KiB 对齐且非零

- `ddr_frame_pusher` 的 ARM 合法性要求
  `((ddr_base[11:0] == 0) && (ddr_base != 0) && (ddr_base + frame_bytes <= cap))`。
- 而 `integrated_delivery_top` 的槽 1 基址 = `SLOT_BASE_WORD + SLOT_WORDS` 个字；
  冻结值 `SLOT_WORDS=81085` → 槽步长 2,594,720 B，**不是** 4 KiB 整数倍，槽 1 永远非法；
  并且基址 0 也被拒绝。
- **本轮处理（需规划确认）**：用 `SLOT_WORDS=81920`（640 KiB/槽，4 KiB 对齐）+
  `SLOT_BASE_WORD=2048`（字节 0x1_0000，非零）。只改**参数**，P4 r2 源码零改动。
- **教训**：`SLOT_WORDS=81085` 与 pusher 的 4 KiB 对齐契约在主源里是矛盾的，本 run 之后若要回到 81085，
  必须先改 pusher 的判据或另写槽映射。

## 6. 地址单位：P4 是 256bit 字号，参考写者/推帧是字节地址，`p2_ddr_bridge` 是 ×8

- P4 `ddr_awaddr` = 256-bit 字索引（`a1_ddr_slot_store`: `BASE_WORD + slot*SLOT_WORDS + waddr`），
  一字节地址应为 `字×32`；`p2_ddr_bridge` 输出 `{word[23:0], 3'b000}` = 字×8。
- 参考工程的 `cam_r10f_writer`/`ddr_frame_pusher` 用**字节地址**（`BEAT_BYTES=32`、`BURST_STEP=4096`）。
- **本轮处理**：在 bridge 的 PAXI 侧统一再 ×4（`{paxi_addr, 2'b00}`），使 P4 的 1 个字落在 32 连续字节上，
  与 pusher 的字节读一致；pusher 的 `BASE0/BASE1` 参数按**字节**给（`SLOT_BASE_WORD*32`）。
- **边界**：这只在 G1 仿真（自建字节寻址 DDR 模型）里验证过；**硬件未验证**，P2 必须首先确认。

## 7. ModelSim 里"整片 X"优先怀疑隐式网

- 现象：`arm_seq=x`、`push_done=x`，而仿真 0 error 0 warning。
- 根因：TB 端口写成 `.tl_rst_n(tl_rst_n)`，但声明的是 `wire rst_tl_n`；
  Verilog 于是造了一个**未驱动的隐式 1-bit 网**，`tl_rst_n=x`，
  `if (!tl_rst_n)` 取 else 分支 → tl 域永不复位 → 全部 X。
- **教训**：TB 端口连接名与声明名不一致不会报错；整域 X 先查复位网是否 implicit。
  另外改完 TB 必须重新 `vlog` 才能生效（本轮有一次跑的是旧编译单元）。

## 8. 综合结果文件的口径

- `brd_board_Runs/syn_1/flow.status` 与 `gate.qor` 的 `Setup WNS/TNS/NUM_FEPS` 是**流程判定口径**
  （本轮 150 MHz：WNS −2273 ps / TNS −31547 ps / 79 端点）。
- `brd_board_gate.timing` 顶部那行 `Max : SWNS …` 是**该报告内路径分组**的统计，会与上面不一致
  （本轮报 +3.931 ns）。判 PASS/FAIL 一律用 `flow.status` / `gate.qor`，不要用 `.timing` 的抬头行。
