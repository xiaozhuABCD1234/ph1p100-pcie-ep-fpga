# ISS-20261018-02 — 调试探针快照域被 PCIe 链路复位钉死（无主机时 9 字恒 0）

## 登记信息

- 登记时间：2026-10-18（上海）
- 来源：`user-input-08.md`（用户 GUI 实读）+ `board-readback/zero-read-diagnosis.md`（开发离线诊断）+ manifest v7
- 状态：**已确认、修复中**（并入 `T11.runB-debug-rtl` 第 3/3 修复轮；不新增包）

## 问题陈述

- 用户 GUI 操作无误：9 信号、`auto_created_cwc1`、`Instant Trigger`、`Triggered:1`、Bit File 为同源 `2385CDED…1873`；9 字全 `0x00000000`（1 样本）。
- 根因：9 个 `MARK_DEBUG` 快照寄存器（`ep_bar_win.v` L464–499）在 `tl_clk_user` 域，异步复位 `tl_rst_user` 由 `ph1p_pcie_rst_sync`（L52–74）产生，仅当 `pl_link_up && LTSSM==L0` 持续满足才释放；本轮无 PCIe 主机 → 复位恒有效 → 寄存器停留复位值 0。
- 常量字（word0=`0x50434946` FICP、word1=`0x31414B52` RKA1、word2=`0x00010000` 1.0）也为 0，是“整体被复位冻住”的决定性证据。
- `tl_clk_user` 采样时钟仍运行（PLL 由板载 `sys_clk` 产生），ChipWatcher 能触发但采到复位值 0；CWC/bit 配对与 SHA 正确。

## 影响

- P3 `T11.runB-board-readback` = **NOT_MATCHED / awaiting-fix**；当前候选 `2385cded…` 不满足“无 PCIe 主机”的 G3 读回目标。
- 不能用 GUI 重试、改触发位置或重下同 bit 解决。

## 处置（裁定）

- **路径①（采用）**：修 RTL 调试路径 + 重建 + G1/G2 + 新 CWC/bit + 上板 GUI 重读；并入原 P1（`T11.runB-debug-rtl`，同 task_id，不新增第 5 包）。
  - 允许改动：`DBG_*` 门控的调试快照/复位/时钟绑定；debug-only SDC 变体；debug 顶层 wrapper；新 TB；`debug-fix3/**` 新输出。
  - 禁止：PCIe 硬核/IP、生产 SDC 语义、`00_all` 默认行为、DBG 关闭时的生产行为。
  - 目标：无链路时 9 字均可读（身份/版本/CTRL 非零；DDR/CSI 计数可动）；CWC 探针时钟显式绑定。
  - 预算：dev ≤75 min/≤35 calls；TD 构建 ≤30 min×≤2（第 2 次需新证据）；G2 阈值不放宽；CWC 重生成 + `--multipiece` 0 失败。
  - 记账：P1 第 3/3 个实际修复轮（最后一轮；若 FAIL 保留 ⚠，不自动续修）。
- **路径②（不采用）**：现有 CWC 仅 9 个信号，全部位于被复位钉死的域，无“无链路可读子集”。
- **路径③（不采用）**：把 G3 改为需 PCIe 主机在场，与用户既定范围（PCIe 不验证、严格 FPGA 侧）冲突；不得静默放宽判据。

## 参考

- `board-readback/zero-read-diagnosis.md`、`user-input-08.md`、`board-readback/user-message-02.md`
- `board-readback/candidate-manifest.json`（schema v7）
- RTL：`rtl/ep_side/img/ep_bar_win.v` L464–499；`rtl/ep_side/pcie_ep_engine.v` L397–399；`rtl/common/ph1p_pcie_rst_sync.v` L52–74
- CLI 读回：`board-readback/cwc-cli/final-attempt-record.md`（download OK、run_hw_cw KIT-8000 → CLI 永久关闭）
