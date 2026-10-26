# T10.b20-a-timing -- user summary (规划冻结, 尚未执行)

**状态：ready（可派发），needs_user_input=false。父任务 T10 仍保持 blocked/active，不由本包关闭。**

## 这次要做什么

b19 的 A 路离线全过，只差最后一步布线时序：综合 +0.127 ns，布线 **-0.098 ns / 10 个违例端点**，
全部在 `clk_a1` 自己域；最差路径是 `a1_abort_reg -> smem.addrb[10]`（abort 信号穿过 5 级 LUT 打到
ERAM 读地址，6 级逻辑）。其余时钟域都过（`ddr_user` 仅 +0.007，也很薄）。

按你的要求，本轮只做**一处定点修复**：在 `a1_frame_top.v` 的 abort→smem 地址路径里加一级寄存/流水，
abort 数据本来就要丢，所以只接受“abort 收尾慢 1 拍”。正常帧必须**一拍不差**（用 b19 的精确计数
卡住：`cycles=37,465,298`、`cmp_words=648,677`、`cmp_writes=81,085`、P1 三黄金逐字节相同）。

## 冻结的候选

- 基线 = b19 changed-src（CAM_SEL=0、PAXI ×8/mask=0、retry/R1、v6），SDC `0888b6a7…`、ADC `1cb30346…`
  逐字节不变；11 个源文件里 **只有 `a1_frame_top.v` 允许改**。
- 仿真：A 几何全链四 CRC+zlib、16 字原生、P1 三黄金、丢 R 重试（这条就是 abort 恢复路径）、v6 bit12=0、
  真实顶层 CAM_SEL=0。
- 重建：**只布一次线**，要求 0 违例且 WNS ≥ +0.05；若落在 +0.003…<+0.05，只能作为“薄裕量 caveat 候选”
  （可出 bit/上板，但不能宣称时序稳健）。< +0.003 或仍有违例 → 直接 FAIL，不出 bit。
- 出 1 个 bit + 1 个 CWC，然后 **1 次 SRAM 下载**（绝不写 Flash）→ R14 复位对齐 → COM8 采 300 s。

## 需要你配合的一件事

上板那一步需要**你在板子旁边按一次 R14 复位**（下载完成、COM8 打开之前）。如果你不在场，流程会停在
`blocked_operator`，保留 bit 和下载记录，不会误判“A 没图像”。另外请确认 A 相机已接好、板子已上电。

## 预算与边界

开发 100 分钟 / 55 次调用；TD 3 个会话、综合 ≤2、**布线 1**、bitgen 1、CWC 1、下载 1、Flash 0。
不改 SDC/时钟/频率/种子，不做第二块 bit、不二次下载、不批量删文件。

## 判定口径（先说清楚，避免事后争议）

- 布线 0 违例且 ≥ +0.05：工程维度 PASS（若 < +0.05 则 PASS 但带 thin-margin caveat）。
- 单次布线仍 < +0.003 或仍有违例：本包 FAIL，保留 routed DB/报告，回到规划另行决定（不在本包内再试）。
- 上板 A 仍无 pix/line/frame：`blocked_A_no_pixels`，保留 300 s 原始抓包与状态证据，结论归 A 前端/硬件，
  不重建、不二次下载。
- 有像素但导出/CRC/zlib 不过：真实缺陷，按同任务修复轮处理（最多三轮）。

## 文件在哪

`D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b20-a-timing\`
（`dev-plan.md`、`fpga-design-guide.md`、`input-index.md`、`dispatch.json`、本文件、`handoff.md`、`final-summary.md`）

恢复文本：`恢复：D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b20-a-timing；本轮目标：<目标>`
