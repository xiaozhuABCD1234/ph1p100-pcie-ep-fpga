# final-summary.md — 20261018-1347_runA_offline_sim（终版）

日期：2026-10-18。原规划者收尾；**run 终态=finished**。本轮=Run A 的“离线模拟 + 可机读板级验证”切片（3 小时窗、用户不在场；仅 SRAM、不写 Flash、不推送）。batch=1、1 主要目标、4 正式包、两级；每任务新开发；一个综合测试者（逐包报告）。

## 1. 判定矩阵（终版）

| task_id | 判定 | 修复轮 | G0 | G1 | G2 | G3 | G4 |
|---|---|---|---|---|---|---|---|
| T11.runA-bringup-kit | **PASS (r0)** | 0 | pass | pass | not_applicable | not_run | not_run |
| T11.runA-readback-checker | **PASS (r0，含 1 次成功补收)** | 0 | pass | pass | not_applicable | not_run | not_run |
| T11.runA-board-selfcheck | **blocked（已接受）** | — | pass（继承） | not_run | not_run | partial（下载+器件 ID；寄存器读 blocked） | not_run |
| T11.runA-board-capture-readback | **awaiting_conditions（不派发）** | — | 继承 | not_run | not_run | not_run | not_run |

统计：首次通过 2；blocked 1；awaiting 1；实际修复轮 0；补收 1 次成功；⚠未通过 0。预算观测：B1 41/30 calls（超用）、KIT 25/25、P1 首轮 ~30 + 会话级权限拒绝（补收正常）、P1 测试者 10/8 min 超时——均如实登记，未扩权。

## 2. 实际完成（有证据）

1. **上板下载链路打通并取证**：BW/JTAG SRAM 下载当前 bit `e81d353b…2b9a`（SHA 复核、`-mode jtag`、rc=0、29.52 s、无任何 flash/efuse/spi 命令）；器件 ID=PH1P100；板即当前 bit（易失）。未改线/电源/相机。
2. **KIT 工具包（PASS）**：`tools/bringup/`（寄存器计划、fail-closed 判定器、CRC/长度复算、夹具、schema、runbook）；本地 commit `48be9f20`；manifest `7e0ae0a0…268e3`。
3. **P1 读回校验核心（PASS，未集成）**：`ddr_frame_readback_checker.v` + TB（1080p 全帧 + N1—N5/T8/T9/T0 负例 + busy 重入拒绝；同包 8 TB 回归通过）；本地 commit `c89ab758`；manifest `f202afb8…`。
4. **报告**：两份 integrated r0 PASS（`test-reports/`）。

## 3. 未完成 / 待条件（如实登记，不冒充）

- **寄存器级板验证全部未做**（身份、写者基线、CSI 统计、发布确认、100 帧/10 min、DDR 读回）——缺用户寄存器读通道：UART 架构不可用（EP top rx 固定 1）；无 PCIe 主机；无 CWC；BW JTAG 读语义未证实。
- **G2 not_run**（不重建 bit）；**G4 not_run**（无长稳；允许的短稳亦因读通道缺失未执行）。
- P1 非阻塞观察：TB abort 后无恢复（T9 末项；DUT fail-safe err=6）——集成触碰时复核。

## 4. 边界与回退

- 未推送任何远端；未写 Flash；未改 RK 仓；未批量删除；硬件动作仅 SRAM 下载（授权范围内、有日志）。
- 回退：板=掉电即失/重下同 bit（`board-selfcheck/scratch/sram_download_runa.tcl`）；仓=`git revert c89ab758`/`48be9f20` 或逐个丢弃新文件；基线 `ab811c8f…855` 与既有证据只读保留。
- 配对：`ab811c8f…855` ↔ `e81d353b…2b9a`（未变）；新本地 commits 未推送、不改配对。

## 5. 下一步（用户回来）

1. 回答 `question-01.md`：读通道四选一（PCIe 主机 / CWC 版 bit / JTAG 只读语义确认 / bring-up bit）；**相机是否已接（单 A）**；是否接受本轮板级止于下载+器件 ID。
2. 明示启动上板轮：`/fpga-orchestrator 执行：<需求>` 或 `恢复：<本 run 路径>；本轮目标：<目标>`；建议目标=读通道恢复 → B2 采集统计/发布确认/100 帧+短稳/条件读回 → 真实几何/相位回填后重跑 G1/G2；物理断电/接线由用户执行；Flash 仍不写。
3. 后续主题（不自动续做）：P1 checker 集成 + 新 bit 重建（板内读回替代路径）；Run B 三算法接入；RK 环境修复后端到端 G4。

## 6. 备注（user-input-03，2026-10-18）

- 用户排除 PCIe 主机通道（未接、不验证），要求验证**严格限制在 FPGA 侧**；用户已回到现场（物理断电/接线/相机确认可执行）。
- 因此 §5 的建议路径调整为 **FPGA 侧读通道**：推荐主路径=**CWC/调试核位流**（项目有既有 ChipWatcher 证据与读回脚本），备选=UART 镜像/命令面恢复（均换 bit，`e81d353b…` 保留回退）；手段对比、代价、推荐包序与拍板项见 `next-round-proposal.md`。
- 本轮（finished）判定与统计不变。
