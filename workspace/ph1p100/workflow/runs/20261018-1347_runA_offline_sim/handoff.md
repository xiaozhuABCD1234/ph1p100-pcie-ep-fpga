# handoff.md — 20261018-1347_runA_offline_sim（终版）

日期：2026-10-18。原规划者收尾。**run 终态=finished**。本轮=Run A 的“离线模拟 + 可机读板级验证”切片（user-input-02：3 小时窗、用户不在场、可机读项直接上板；仅 SRAM、当前 bit、不写 Flash、不推送、不改 RK 仓）。batch=1；1 主要目标；4 正式包；两级；每任务新开发；一个综合测试者（逐包报告）。

## 1. 判定矩阵与统计（终版）

| task_id | 判定 | 修复轮 | G0 | G1 | G2 | G3 | G4 |
|---|---|---|---|---|---|---|---|
| T11.runA-bringup-kit | **PASS (r0)** | 0 | pass | pass | not_applicable | not_run | not_run |
| T11.runA-readback-checker | **PASS (r0，含 1 次成功补收)** | 0 | pass | pass | not_applicable | not_run | not_run |
| T11.runA-board-selfcheck | **blocked（已接受）** | — | pass（继承） | not_run | not_run | **partial**（SRAM 下载+器件 ID pass；寄存器读 blocked） | not_run |
| T11.runA-board-capture-readback | **awaiting_conditions（不派发）** | — | 继承 | not_run | not_run | not_run | not_run |

统计：首次通过 2（KIT/P1）；blocked 1（B1）；awaiting_conditions 1（B2）；实际修复轮 0；补收 1 次成功（P1 会话级权限问题）；⚠未通过 0；硬件层动作仅=SRAM 下载（已授权、已取证）。

## 2. 交付物与冻结 SHAs

| 交付 | 路径 | 关键 SHA/commit |
|---|---|---|
| 上板工具包（KIT，PASS） | 上游仓 `tools/bringup/`（14 文件）+ run `bringup-kit/` | 本地 commit `48be9f20d22be82e5b7936f06c97202ad0ffc412`（parent `ab811c8f…855`）；manifest `7e0ae0a02397053e1faa3e6147864ff259e83d7a606b7102b44fa344a06268e3` |
| DDR 读回校验核心（P1，PASS；未集成） | `rtl/ep_side/ddr/ddr_frame_readback_checker.v`、`sim/tb/tb_ddr_frame_readback_checker.v`、`sim/compile_checked.f` 追加 1 行 + run `ddr-readback-checker/` | 本地 commit `c89ab758`（未推送）；manifest `f202afb8…`；8 TB 回归 + 新 TB ALL PASS |
| B1 板级自检证据 | run `board-selfcheck/`（dev-result/channel-notes/manifest/logs/scratch） | manifest `0cbe3fe2…`；bit SHA 复核 `E81D353B…2B9A`（5,224,023 B）；BW `read_device_id`=PH1P100；SRAM 下载 rc=0/29.52 s |
| 报告 | `test-reports/T11.runA-bringup-kit-r0-integrated.md`、`test-reports/T11.runA-readback-checker-r0-integrated.md` | 均首行 PASS |
| 用户输入件 | `question-01.md`、`user-summary.md`、`final-summary.md`、`dispatch.json`（finished）、`dev-plan.md`（v3） | — |

配对：基线 commit `ab811c8f…855` ↔ bit `e81d353b…2b9a`（未重建）；`48be9f20`（工具）与 `c89ab758`（新增未集成模块）**不影响**该配对；三个 commit 均为本地、**未推送**。板上当前为 `e81d353b…` 的 SRAM 配置（**易失，掉电即失**）。

## 3. 重要发现（上板前置，务必带进后续轮）

1. **UART 命令通道架构不可用**：EP top 将 uart rx 固定 `1'b1`（`rtl/ep_side/ph1p_pcie_ep_top.v` L155/L757；rxd 让位 MIPI）→ `doc/uart_cmd_file_pcie.txt` 命令面对本 bit/本板不适用。
2. **串口枚举更正**：FTDI 复合设备 `AL0B99F427`：MI_00=WinUSB(JTAG)、MI_01=VCP=**COM8**（实测 0 字节）；**COM3/COM4 为蓝牙口**。
3. **BW/JTAG**：下载与器件 ID 已证；`JTAG_REG_ACCESS/JTAG_REG_ACCESS_VEC/JTAG_AXIS_APB_ACCESS` 仅命令名、无参数/读写语义文档，候选无 CWC/调试核 → 读寄存器记**不可用**（未盲试）。
4. **BW 使用约束**：bit 路径须 ASCII/英文（中文路径 → PRG-8000）；脚本相对路径调用、参数经环境变量传入。
5. **OneDrive 同步竞争**：`sim/compile_checked.f` 写入后短时跨路径不可见（曾致 2 次编译缺新模块）→ 冻结/提交前同绝对路径复核。
6. 既有 SOP 沿用：DDR 校准偶发 D37 灭 → 断电 10 s 重上+重下同 bit（LED/物理操作=用户在场项）。

## 4. 预算与过程登记（不改判定）

- B1 工具调用 **41/30**（超用 11；≈11 min≤35；未扩范围）；KIT **25/25 calls、15/15 min 恰用尽**；P1 首轮 ≈30 calls 并 3 次 `Permission denied`（会话级；补收 ≤15 min/≤20 calls 正常完成）；P1 综合测试者 ≈10/8 min 超时登记。
- problem（已闭合）：`T11.runA-readback-checker:PERMISSION_MISSING:shell`（补收后恢复）。
- P1 非阻塞观察：TB 对 abort 后无恢复用例（T9 末项；DUT fail-safe err=6）——集成触碰时复核。
- 全程：仅 SRAM、未写 Flash、未改线/电源/相机、未推送、无批量删除、无新增外部依赖。

## 5. 未完成项与恢复条件（B1/B2）

- **B1 寄存器部分**（0x40/0x118/0x11C、写者基线、CSI 统计）：缺**用户寄存器读通道**。
- **B2 全部**（采集使能确认、0x120..0x12C 统计、发布确认 seq/len=2,592,768、100 帧+10 min 短稳、DDR 读回条件项）：依赖同一读通道 + 相机现场确认。
- **恢复条件（用户拍板）**：(a) ~~现场接 PCIe 主机（RK/PC）~~ **用户已排除**（user-input-03：PCIe 未接、该通道不验证）；(b) 授权构建带 CWC/调试核新候选 bit（bit 更替+重新冻结+G1/G2）**← 现推荐主路径**；(c) 用户/原厂确认 BW JTAG 只读语义（低成本先试）；(d) 授权 bring-up bit（rdx 引出/回环，需改线）。用户已回到现场（物理断电/接线/相机确认可执行）；手段对比、推荐顺序与拍板项见 `next-round-proposal.md`。
- 详见 `question-01.md`（问题清单）与 `final-summary.md` §5。

## 6. 恢复与回退入口

- 板：掉电即失；重下同 bit 用 `board-selfcheck/scratch/sram_download_runa.tcl`（bit 需 ASCII 副本、先复核 SHA）；hwserver 已停、无残留。
- 仓：`git revert c89ab758`（P1）/ `48be9f20`（KIT）或逐个丢弃新增文件；基线 `ab811c8f…855` 与既有证据全程只读未动；禁止批量删除。
- 续做入口：用户明确输入 `/fpga-orchestrator 执行：<需求>`，或 `恢复：C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261018-1347_runA_offline_sim；本轮目标：<目标>`。

## 7. 建议下一轮（上板轮）与后续主题

- **建议下一轮目标**：先解决寄存器/内存读通道（上 §5 四选一），随后执行 B2：真实单 A 采集 → 统计/几何/错误读数 → 发布确认（len=2,592,768）→ 100 帧 + 10 min 短稳 →（可行时）DDR 读回核验；读数回填真实几何/相位后重跑 G1/G2；物理断电/接线由用户执行。
- **后续主题（不自动续做）**：① P1 checker 集成生产顶层 + 状态寄存器 + 重跑 G1/G2 + 新 bit 候选（板内读回自证替代路径）；② Run B 三算法接入 + 板级验证；③ RK 环境（KDIR/工具链）修复后的端到端 G4。

## 8. 边界变更记录（user-input-03，2026-10-18）

- 用户原话：“PCIE没接，这个通道先不验证，先严格把验证限制在fpga侧，现在我回来了，能开始干什么”。
- 边界：①PCIe 主机通道**不验证**（排除原选项 a）；②验证**严格限制在 FPGA 侧**（仅板 + JTAG/串口线缆）；③用户**在现场**（物理断电/接线/相机确认可由用户操作）；④仍仅 SRAM、不写 Flash、不推送。
- 处置（本轮规划侧，未派发、未触硬件）：更新 handoff（本节与 §5）、final-summary 备注、question-01 选项状态；新增 `next-round-proposal.md`（FPGA 侧可立即开始的方案 + 推荐顺序 + 拍板项）。
- 下一轮入口不变：`/fpga-orchestrator 执行：<需求>`（或 `恢复：<本 run>；本轮目标：<目标>`）；建议目标=“FPGA 侧读通道成立（调试核位流）+ 身份/基线/统计读回”。**注意：该路径换 bit（新调试候选），`e81d353b…` 保留回退。**
