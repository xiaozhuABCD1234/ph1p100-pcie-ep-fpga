# handoff.md — 20261018-1631_runA_fpga_side_readchannel（终版）

日期：2026-10-19。原规划者收尾。**run 终态=finished**。本轮=Run A 的“FPGA 侧读通道”切片（无 PCIe 主机、仅 SRAM、相机单 A 已接）。batch=1；1 主要目标；4 正式包；每任务新开发 + 一个综合测试者。

## 1. 终态判定

| 包 | 判定 | 实际修复轮 | G0 | G1 | G2 | G3 | G4 |
|---|---|---|---|---|---|---|---|
| T11.runB-debug-spec | **PASS (r0)** | 0 | pass | n/a | n/a | not_run | not_run |
| T11.runB-debug-rtl | **PASS (r3)** | 3/3 | pass | pass | pass | not_run | not_run |
| T11.runB-debug-build | **PASS (r3)** | 2 | pass | pass（继承） | pass（继承） | not_run | not_run |
| T11.runB-board-readback | **PASS (r1)** | 1 | 继承 | 继承 | 继承 | **partial** | **not_run** |

- 首次通过 1/4 包；其余 3 包修复/补收后 PASS；⚠未通过 0。
- **父 T11 不置 done**：PCIe 主机侧、word6 归因、G4 长稳、三算法接入仍未覆盖。
- **G3=partial**：Tier-1 命中（身份 + word3 推进）证明 FPGA 侧读通道成立；Tier-2 的 word6 good 增长跨样本对曾非单调，未判稳定达成，按冻结判据保持 partial，**未升 pass**。

## 2. 最终候选

| 项 | 值 |
|---|---|
| bit | `bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0`（5,224,027 B；SRAM 已上板） |
| CWC | `8d2998b96ef1763c14a1302118235a687488297ce496692b1f6cd95d76981026`（81,063 B） |
| BID | `02c5cfdf…` |
| 源码 | HEAD `b0282d2a…`；4 路径 worktree-only；commit `BLOCKED_PENDING`（接受）；未推送 |
| 旧候选 | `e81d353b…2b9a`（回退）、`2385cded…1873`（NOT_MATCHED 证据）；并列保留、不混拼 |

证据：`debug-fix3/candidate-manifest.json`（`fadbf3f0…`）、`debug-build2/candidate-manifest.json`（`e6d63702…`）、`board-readback/candidate-manifest.json`（v11 `BC27553A…`/23,415 B）、三份 r 报告（P1-r3、P2-r3、P3-r1）与 `board-readback/readback-record.md`、`tier-evaluation-p1fix3.md`、`user-input-12.md`。

## 3. 板上实测（最终两样本）

- 样本 1 `2026/10/19 1:30:48`；样本 2 `1:31:7x`（秒位截断，下界 1:31:07）→ 间隔 **≥19 s**。
- word0/1/2=`50434946/31414B52/00010000`；word3=`B1BE→B2EA`（+300）；word4=`00900000` 两样本；word5=`00279000`；word6=`BE000000→EA000000`（good 190→234，bad/hdr/crc=0）；word7=`089012DE`；word8=`00000021`。
- Tier-1 PASS；Tier-2 partial（word6 稳定性）；G3=partial；G4=not_run。

## 4. CLI 与 issue 处置

- **CLI 读回永久关闭**：round1（config/get_hw OK、run_hw_cw KIT-8000）→ round2（配对后 KIT-8000、download PRG-9505/9525）→ ASCII（issue-01 排除；TD hwserver 会话可用但仍 KIT-8000）→ 最终同会话 download 成功（SRAM/同 SHA/25.871 s）后仍 KIT-8000。**无样本、不再尝试；仅保留 SRAM 下载能力**。
- **issue-01（非英文路径）已排除**；**issue-02（探针复位被 PCIe 链路钉死）已修复**：`dbg_por_rst` 复位源解耦，9 字未搬域，DDR/CSI 未动，生产 DBG-off 等价。

## 5. 安全、预算、commit

- 仅 SRAM；零 Flash/efuse/SPI/svf；未推送；未改线/电源/相机；无 GUI 自动化；物理动作仅用户断电/点击 Instant Trigger。
- 预算观测：P1 初始 **59/30 calls** 超用；CLI 20/20、20/20、20/20、12/12；TD 构建 637–693 s；下载 28.85/28.36 s；测试者均 ≤15 min。B1 属上一 run，不并入本 run。
- commit：**接受 worktree-only 冻结**（r3/P2/P3 绑定 `commit_status=BLOCKED_PENDING`；改 HEAD 会漂移并需重测）。可选用户提交命令见 `final-summary.md` §7；不推送、不阻塞收尾。

## 6. 回退与恢复

- 板：断电 10 s 清除 SRAM；重下旧 bit `e81d353b…2b9a`（SRAM，约 30–40 s）；`2385cded…` 仅证据。
- 源码：按 `debug-fix3/candidate.diff`（`21D4A910…`/7,016 B，reverse-apply RC=0）复原或丢弃 4 路径改动；HEAD 未动。
- 恢复入口：`/fpga-orchestrator 恢复：C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261018-1631_runA_fpga_side_readchannel；本轮目标：<目标>`。

## 7. 后续主题（不自动续做）

1. word6 归因（good 跨样本对不稳定）；2. G4 长稳（100 帧/10 min 级）；3. PCIe 主机侧（RKA1 读、端到端、RK 驱动配套）；4. 三算法接入（后两步之二）。

## 8. 给用户的一句话

FPGA 侧读通道已打通并读到身份/长度/CTRL/帧计数/CSI 统计；G3 按证据保守记 partial；**无需操作，保持板子现状即可**；若要恢复旧状态，断电 10 秒或重下旧位流即可。
