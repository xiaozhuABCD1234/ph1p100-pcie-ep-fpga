# final-summary.md — 20261018-1631_runA_fpga_side_readchannel（终版）

日期：2026-10-19。原规划者收尾。**run 终态=finished**。本轮目标：在**无 PCIe 主机、仅 SRAM、相机单 A 已接**的条件下，建立 FPGA 侧读通道并读到身份/写者基线/CSI 计数。batch=1；1 主要目标；4 正式包；两级；每任务新开发 + 一个综合测试者。

## 1. 结论

- **FPGA 侧读通道成立**：最终候选 bit `bfafdf97…`（SRAM）上板后，ChipWatcher 读到身份三字命中、CTRL=`00000021`、帧序号推进、CSI good 增长；**Tier-1 PASS**。
- **G3=partial（按冻结判据，不升 pass）**：Tier-2 的 word6 good 增长在早期样本对中出现非单调，未判定“稳定达成”；G3 维持 partial，未放宽。**G4=not_run**（未做长稳）。
- **父 T11 不置 done**：PCIe 主机侧（RKA1 读、端到端、RK 驱动配套）、word6 归因、G4 长稳、三算法接入仍未覆盖。
- **CLI 读回永久关闭**：4 次实际尝试（round1、round2、ASCII、同会话 download；3 类方案）均未取得样本；**GUI 两样本是唯一读回路径**；CLI/BW 仅保留 SRAM 下载能力。
- **issue-01（非英文路径）已排除**；**issue-02（复位域）已确认并修复**（复位源解耦，不搬域）。

## 2. 判定矩阵

| 包 | 判定 | 实际修复轮 | G0 | G1 | G2 | G3 | G4 | 报告/证据 |
|---|---|---|---|---|---|---|---|---|
| T11.runB-debug-spec | **PASS (r0)** | 0 | pass | n/a | n/a | not_run | not_run | `test-reports/T11.runB-debug-spec-r0-integrated.md` |
| T11.runB-debug-rtl | **PASS (r3)** | 3/3（r0 FAIL→r1；P1-fix/fix2→r2；fix3→r3） | pass | pass | pass | not_run | not_run | `test-reports/T11.runB-debug-rtl-r3-integrated.md`；manifest `debug-fix3/candidate-manifest.json`（`fadbf3f0…`） |
| T11.runB-debug-build | **PASS (r3)** | 2（r0 FAIL→r1；r2 FAIL→r3） | pass | pass（继承） | pass（继承） | not_run | not_run | `test-reports/T11.runB-debug-build-r3-integrated.md`；manifest `debug-build2/candidate-manifest.json`（`e6d63702…`） |
| T11.runB-board-readback | **PASS (r1)** | 1（r0 FAIL→r1；记录/重采） | 继承 | 继承 | 继承 | **partial** | **not_run** | `test-reports/T11.runB-board-readback-r1-integrated.md`；manifest v11 `BC27553A…`/23,415 B |

统计：**首次通过 1/4 包**（debug-spec）；其余 3 包经修复/补收后 PASS。P1 实际修复 3/3（最后一轮为板测发现的复位域缺陷）；P2 实际修复 2 轮；P3 实际修复 1 轮。**⚠未通过 0**；外部 blocked 均已闭合。

## 3. 最终候选与关键哈希

| 项 | 值 |
|---|---|
| 最终 debug bit | `bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0`（5,224,027 B；SRAM 已上板） |
| 最终 CWC | `8d2998b96ef1763c14a1302118235a687488297ce496692b1f6cd95d76981026`（81,063 B） |
| BID | `02c5cfdfb0920871b83f8e1d9b34888c5b09d811ce73c1bbdd26bcc98b77541d` |
| P1 manifest | `fadbf3f0…`/11,795 B；r3 report `5A8BDBF9…`；diff `21D4A910…`/7,016 B（reverse-apply RC=0） |
| P2 manifest | `e6d63702…`/11,105 B（22/22 绑定 0 不一致） |
| P3 manifest | `BC27553A…`/23,415 B（v11；83 条 0 不一致、0 null） |
| 源码 | HEAD `b0282d2a…`；4 路径 **worktree-only**；commit `BLOCKED_PENDING`（接受为冻结态；未推送） |
| 旧候选 | `e81d353b…2b9a`（5,224,023 B；回退源）、`2385cded…1873`（5,224,027 B；NOT_MATCHED 证据）；并列保留、未混拼 |

## 4. 板上实测（最终样本）

- 时间：样本 1 `2026/10/19 1:30:48`；样本 2 `1:31:7x`（秒位截断，下界 1:31:07）→ **间隔 ≥19 s**。
- 9 字：word0=`50434946`、word1=`31414B52`、word2=`00010000`、word3=`0000B1BE`→`0000B2EA`（Δ=0x12C=**300** 帧）、word4=`00900000`（两样本）、word5=`00279000`（2,592,768）、word6=`BE000000`→`EA000000`（good **190→234**，bad/hdr/crc=0）、word7=`089012DE`（last_lines=2192/last_wc=4830）、word8=`00000021`（bit0=1/bit5=1/bit4=0/bit6..8=0）。
- **Tier-1 PASS**：身份三字 + 至少一组计数可复读（word3 推进）。**Tier-2 partial**：word6 good 增长在早期样本对中曾非单调，未判稳定达成；按冻结判据 G3=partial，不升 pass。**G4=not_run**（未做长稳）。

## 5. 过程要点与统计

- **问题链**：P2 首次构建因 debug wrapper 打乱生产 SDC 对象 → debug-only SDC 变体 + fail-closed 校验；CWC 校验器与 TD 多片 ERAM 口径不符 → 多片覆盖模式（默认 strict 不变）；无 PCIe 主机下 9 字全零 → 根因 issue-02（探针复位被链路钉死）→ 复位源解耦（`dbg_por_rst`，9 字未搬域、DDR/CSI 未动、生产 DBG-off 等价）。
- **CLI 读回**：round1 `config/get_hw` 可用但 `run_hw_cw` KIT-8000；round2 配对后仍 KIT-8000、TD download PRG-9505/9525；ASCII 轮排除 issue-01（路径）且 TD 自带 hwserver 会话可用，但 `run_hw_cw` 仍 KIT-8000；最终同会话 download 成功（SRAM、同 SHA、25.871 s）后仍 KIT-8000 → **永久关闭**。证据 `board-readback/cwc-cli/`（含 `final-attempt-record.md`）。
- **预算观测（如实）**：P1 初始开发 **59/30 calls**（超用，已登记）；CLI round1/round2/ASCII 均 **20/20**、最终轮 **12/12**；TD 构建 637–693 s（≤30 min）；P3 下载 28.85 s / 28.36 s；P1-r3 测试者 ≈12 calls、P2 r2/r3 测试者 ≈4 calls、P3 r0/r1 测试者 ≈5 calls（均在限内）。**B1 属上一 run（20261018-1347），不并入本 run 统计。**
- **安全**：全程仅 SRAM；零 Flash/efuse/SPI/svf；未推送；未改线/电源/相机；无 GUI 自动化；物理动作仅用户断电/点击 Instant Trigger（按清单）。

## 6. 仍缺 / 后续主题（不自动续做）

1. **word6 归因**：good 增长跨样本对不稳定的原因（采集流水/显示路径/统计窗口），需单独实验。
2. **G4 长稳**：100 帧/10 min 级持续采集与稳定性能未测。
3. **PCIe 主机侧**：RKA1 寄存器读、端到端图像、RK 驱动配套包落实；本轮已明确不验证 PCIe。
4. **三算法接入**（后两步之二）：灰度/高斯/HE 的真实并行硬件接入与板级验证。

## 7. 回退与恢复入口

- **板**：当前 SRAM 为 `bfafdf97…`；**断电 10 s 即清除**（无 Flash）。需要旧状态时重下 `e81d353b…2b9a`（SRAM，约 30–40 s）；`2385cded…` 仅作 NOT_MATCHED 证据，不再使用。
- **源码**：4 路径 worktree-only（HEAD `b0282d2a…`）；按 `debug-fix3/candidate.diff`（`21D4A910…`/7,016 B，reverse-apply RC=0）复原或丢弃改动。**可选用户提交命令**（不推送）：
  ```
  cd upstream\ph1p100-pcie-ep-fpga
  git add rtl/ep_side/img/ep_bar_win.v rtl/ep_side/pcie_ep_engine.v rtl/ep_side/ph1p_pcie_ep_top.v sim/tb/tb_ep_bar_win_debug.v
  git commit -m "debug: decouple dbg snapshot reset from PCIe link (issue-02)"
  git rev-parse HEAD
  git status --short
  ```
- **run 入口**：`/fpga-orchestrator 恢复：C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261018-1631_runA_fpga_side_readchannel；本轮目标：<目标>`。

## 8. 一句话

**FPGA 侧读通道已打通，身份/长度/CTRL/帧计数/CSI good 均读到；G3 按证据保守记 partial，未把“读到了”吹成“全部通过”；板子保持现状即可，无需操作。**
