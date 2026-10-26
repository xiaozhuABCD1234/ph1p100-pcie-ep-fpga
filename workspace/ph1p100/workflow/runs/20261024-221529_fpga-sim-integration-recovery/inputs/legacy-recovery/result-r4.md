# T10.b1-a1-uart-integ r4 — BLOCKED（测试-only 中止）：核心链路 PASS-with-boundary；故障计数不可能在"含复位的单轮"中留存（已证明）

- task_id `T10.b1-a1-uart-integ` | revision **r4** | 2026-10-23 | run `20261020-0209_singleA_aplus_closedloop`
- 授权 `dispatch-b1-r4.json`（测试-only；不改 RTL；25 min/15 calls；失败即 P1 core PASS-with-boundary，不自动 r5）
- **判定 BLOCKED**：RTL 零改动且哈希与 r3 一致（`rtl_tools_drift=0` 已实测）；本次新增证据是**证明"复位会清空故障计数"**这一结构事实，并据此把故障证据拆成"无复位计数轮"与"复位恢复轮"（mode 3/4，TB-only）——但 shell 工具在最后一次编译/运行前**被拒绝两次**（`Permission denied: shell`），mode 3/4 未能运行，store-only 最大长度 TB 未编写，MODE=1 缩短帧与奇数高尾块未运行。按有界规则以 BLOCKED 交规划。

## 1. 本轮已确认的事实（可复用，均有实际输出）

1. **RTL 哈希零漂移**：读 r3 manifest 的 24 个 artifact，逐个重算 `fpga/csi2/src/a1/*` 与 `tools/a1/*` 的 SHA256 → 全部一致（`rtl_tools_drift=0`）。r4 只新增 `r4/sim/tb_camera_a1_uart_top.v`（r0 TB 的副本 + 帧长参数化 + 裁剪计数暴露），未动任何 RTL/参考/SDC。
2. **帧长参数化已落地**：TB 新增 `localparam FRAME_CYC = (ROI_Y+H)*(CG+LINE_GAP)+FRAME_GAP`；复位点、相位间隔、尾部等待全部按 `FRAME_CYC` 表达（不再用 352/3000 固定值）。
3. **复位点必须落在帧内**：`FRAME_CYC-60`（相位帧 552 cycles → 492）可跑完（4 s / 80,607 cycles）；`FRAME_CYC/2`（276）整轮超时 400 s。差异说明"在 raw 写入中途复位"会把管道留在未完成状态（见 §2 待办，需 planner 决定是否作为独立缺陷）。
4. **故障计数被复位清空的直接证据**（mode 2，80,607 cycles）：`cap=9, enc=3, exported=1, raw_pub=5, cmp_drop=0, err=0, read_words=96, dup_words=0`，同时新增的裁剪内部计数为 `crop_geom=0, crop_short=0, roi_frames=9`。
   - 驱动了 12 帧（A、B、C、D、E×8），`roi_frames=9` → **有 3 帧没有产出 ROI**，与"B 坏帧中止 + C 帧中复位 + 1 帧被丢"完全一致；
   - 但 `crop_geom/crop_short` 在复位（相位 C）时被清零，故最终读数为 0。**结论：单轮内"帧中复位 + 故障计数"不可兼得**，必须拆成两轮（mode 3 无复位计数轮 / mode 4 复位恢复轮）。
5. **无半帧发布**：`enc=3 < cap=9`，且 `err=0`；`read_words=96 = 24 字/帧 × 4 帧` 级计数自洽，`dup_words=0`（r3 首字重复修复在本轮几何下仍成立）。

## 2. 未完成（阻塞原因）

- **mode 3/4 未运行**：TB 拆分代码已在 `r4/sim/tb_camera_a1_uart_top.v` 内（`mode == 3` = A + 坏帧 + 8 快帧；`mode == 4` = A + 帧中复位 + 恢复），最后一次 `vlog`/`vsim` 前 shell 连续两次 `Permission denied`，无法编译与运行。**不得**把未运行当作已通过。
- **store-only 2,594,706 B 最大长度单元 TB 未编写**（预算耗尽 + shell 不可用）。
- **MODE=1 缩短帧**、**奇数高尾块（W=8,H=3）**：`not_run`。
- 由 §1.3：`FRAME_CYC/2` 复位超时需要单独定位（是 TB `wait_export` 自旋，还是 DUT 在写入中途复位后未恢复）；这不影响 r3 的核心链路结论，但**P3 上板前的复位行为需要该结论**。

## 3. 边界与禁止项

未改任何 RTL（哈希实测一致）、SDC、参考、协议/帧/CRC/DDR 布局、r3 冻结证据；无 TD/bitgen/下载/Flash；未放宽超时/门槛；未伪造任何计数；无半帧发布。

## 4. 预算账（如实）

calls **11/15**；wall ≈ **25/25 min**；子时限：MODE=2 相位约 14 min（含一次 400 s 超时与一次 TB 语法修复），store-only/MODE=1/tail 未进入；shell 在收尾阶段的两次拒绝为外部工具阻塞。

## 5. 结论（供规划裁决）

P1 的**核心通路证据完整且已冻结**（r3：8×2 / 64×8 / 整帧 1920×1080 全部逐样本 0 mismatch、四 CRC true、`raw_len=2,592,000`、`stream_len=40,032 ≤ 2,594,706`、`dup_words=0`、`read_words=129,600`，RTL 哈希与 r4 实测一致 → 可直接复用）。**缺项**为：故障计数语义（需 mode 3/4 两轮）、2,594,706 B 最大长度单元测试、MODE=1 缩短帧、奇数高尾块。建议按 dispatch 的 `partial` 条款把 P1 记为 **core PASS-with-boundary**，并把上述四项列为 P2 之前或 P3 之前的有界补测（每项 ≤5 min）。

## 6. 恢复入口

`…/T10.b1-a1-uart-integ/r4/`：本文件、`sim/tb_camera_a1_uart_top.v`（mode 3/4 已写好待编译）、`captures/mode2.dec|fault.dec|fault.stats`、`logs/sim_mode*.log`。
恢复文本：`恢复 T10.b1-a1-uart-integ r4 补测：shell 恢复后先 vlog r4 TB 并跑 +MODE=3（期望 geom>0/raw_drop>0 且 enc<cap）与 +MODE=4（期望复位后仅恢复帧发布、无半帧）；再写 tb_store_maxlen（81,085 字写读回）；MODE=1 缩短帧与 W=8,H=3 尾块各一轮。`
