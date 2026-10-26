# final-summary.md — 20261019-0207_runA_ddr_readback_loop（终版）

日期：2026-10-19。原规划者收尾。**run 终态=finished**。本轮目标：DDR 读回校验集成闭环候选（checker 集成 + 几何核对 + 一次构建 + 坏帧/100 帧仿真 + “回来点两下”上板清单），全程 FPGA 侧、仅 SRAM、不写 Flash、不推送、不接 PCIe/RK；并行线 0212（Codex）独立推进，两线不合并。

## 1. 结论

- **四包全 PASS**：P1 `checker-integrate` **r1**（1 修复轮）、P2 `build` **r0**、P3 `sim-campaign` **r0**、P4 `board-checklist` **r0**；首次通过 **3/4**；⚠未通过 **0**。
- **DDR 读回自证闭环成立并已在板上实测**：G3 = **Tier-1 PASS + Tier-2 PASS**（用户 GUI 四样本；C→D 间隔 30 s）。
- **板载=新候选** bit `5B67A8F5…1D52`（SRAM，2026-10-19 21:56:53 下载；断电即失）。回退=断电 10 s 或重下旧 `e81d353b…`（SRAM，≈30–40 s）。
- **父 T11 不置 done**：G4 长稳 not_run；PCIe/RK 主机侧、生产 DBG-off 常驻、真实几何/相位完整板证、三算法仍缺；0212 线独立，不合并。

## 2. 判定矩阵

| 包 | 判定 | 轮 | 实际修复 | G0 | G1 | G2 | G3 | G4 | 报告 / manifest |
|---|---|---|---|---|---|---|---|---|---|
| T11.runC-checker-integrate | **PASS** | r1 | 1/3（r0 FAIL→r1） | pass | pass | not_run | not_run | not_run | `test-reports/T11.runC-checker-integrate-r1-integrated.md`；`checker-integrate/candidate-manifest.json`（`68AB235E…`） |
| T11.runC-build | **PASS** | r0 | 0 | pass | pass(继承) | pass | not_run | not_run | `test-reports/T11.runC-build-r0-integrated.md`；`build/candidate-manifest.json`（`0F67D299…`） |
| T11.runC-sim-campaign | **PASS** | r0 | 0 | pass | pass | not_run | not_run | not_run | `test-reports/T11.runC-sim-campaign-r0-integrated.md`；`sim-campaign/candidate-manifest.json`（`01938ebb…`） |
| T11.runC-board-checklist | **PASS** | r0 | 0 | pass | pass(继承) | pass(继承) | **pass（Tier-1+Tier-2）** | not_run | `test-reports/T11.runC-board-checklist-r0-integrated.md`；`board-checklist/candidate-manifest-v8.json`（`3594bb40…`） |

统计：首次通过 3/4；实际修复 1（P1）；**blocked 2 次（非 FAIL、不计轮）**——P1 首派遇共享工作树冲突（用户改派 Codex 后重锚至独立 worktree）、P4 首返 awaiting_user_gui（板窗被 0212 TD 构建占用）；⚠未通过 0；待条件 0。

## 3. 最终候选与关键哈希

| 项 | 值 |
|---|---|
| bit | `5B67A8F5…1D52`（5,224,027 B；`phy_1\…bit` 与 `cw\compiled.bit` 逐字节相同） |
| CWC | `8DDA54D4…664F`（143,444 B；16 视图 / 512+512 / 26 pieces；multipiece 校验 rc=0） |
| BID | `A068E42E…F1DB`（151,492 B） |
| P1 manifest / diff | `68AB235E…67BD`（9,368 B）/ `5907B38F…8CB2`（59,091 B） |
| P2 manifest | `0F67D299…6919`（16,523 B；29/29 复算 0 不一致） |
| P3 manifest | `01938ebb…af72`（17,323 B；9 项工件 9/9 MATCH） |
| P4 manifest v8 | `3594bb40…ecb5fa`（13,682 B；14/14 工件、freeze-verify 55/0、哈希链 56 MATCH） |
| worktree | `upstream/ph1p100-pcie-ep-fpga-wt0207`（branch `opencode/runC-0207`，HEAD `b0282d2a`，6 M + 4 ??，worktree-only，未 commit/未推送） |
| 旧候选（并列保留） | `bfafdf97…813d0`（前板载）、`2385cded…1873`（早期证据）、`e81d353b…2b9a`（回退）、`AFFC4396…`（仅证据） |

## 4. 板上实测（P4，用户 GUI 四样本）

- 时间：A `22:0:22*`、B `22:1:0*`（截图秒位截断；A/B 间隔不可证）、C `22:13:15`、D `22:13:45`（C→D=30 s）。
- 身份：w0=`50434946`、w1=`31414B52`、w2=`00010000`——**四样本全中**；w8=`00000021`（bit0/bit5=1、bit4=0、bit6/7=0）。
- 计数/基线：w3 `3216→3818→15293→15764`（单调）；w4 `00900000`/`00100000`（BASE1/BASE0 轮换，RTL 直接源 `cam_ddr_writer.v` L132-133/L788-790）；w5=`00279000`（2,592,768）；w6 good `144/234/189/148`（模 256 与 seq 差自洽；bad/hdr/crc=0）。
- checker 字：w9=`0000003E`（B=`0000002D` 校验中、位域更正后自洽）；w10=`0009E400`（648,192）；w13 完成态=w3（B=w3−1 可解释）；w11/12 非零；**w14=w15=w12**（头内存储 CRC=重算载荷 CRC）。
- 预加载：`download -mode jtag`，`PRG-2014` 成功、100%、30.037585 s、下载后 `read_device_id`=PH1P100；下载 **1/1** 次；零 Flash/efuse/SPI/svf、零 GUI 自动化、零 push。
- **G3=Tier-1 PASS + Tier-2 PASS；G4=not_run（长稳/热态未测，不外推）**。

## 5. 过程要点与统计

- **两线协调**：02:32 CR-01 曾判本线暂停（用户把任务改派 Codex 试用）；13:0x 用户要求重锚 → **CR-02**：本线独立 worktree 沙箱、共享树只读、TD/板卡窗口串行互斥、跨线不合并构建/候选。0212 线同期自行推进，本 run 不消费其产物。
- **预算**：P1 首派 blocked 前 ≈19 calls（零写入）；P2 dev **31/30 calls**（超 1 次，已登记、不判 FAIL）；P4 dev 首返 **30/30 calls/≈35 min**；P4 tester **≈31/25**（报告已如实登记、未影响结论）；其余测试者均在预算附近/内。
- **安全**：全程零 Flash/efuse/SPI/svf；零 push；未改线/电源/相机；禁 GUI 自动化；旧候选未覆盖/未混拼；下载 1 次仅 SRAM。
- `workflow/tasks.json`：本轮**未写**；父 T11 不置 done。

## 6. 仍缺 / 后续主题（不自动续做）

1. **G4 长稳/热态**（100 帧→10 min 级；word6 good 跨样本对稳定性归因）——按用户口径后置。
2. **checker 生产路径（DBG-off 常驻）** + PCIe/RK 主机侧寄存器暴露与端到端（需主机授权，另 run）。
3. **真实几何/相位完整板证**（MP07/08：OB/起点/镜像/phase）+ 三算法接入（另轮）。
4. **与 0212 线候选择一/统一**（如用户要求；板窗互斥，另行裁定；默认不合并）。

## 7. 回退与恢复入口

- **板**：当前 SRAM=新候选 `5B67A8F5…`；**断电 10 s 即清除**；重下旧 `e81d353b…`（SRAM，≈30–40 s，不写 Flash）；`bfafdf97…` 亦为可用旧态；`2385cded…` 仅证据。
- **源码**：wt0207 worktree-only（6 M + 4 ??；HEAD `b0282d2a`）；按需逐文件还原/删除新增 TB（遵守单文件删除禁令）；未 commit、未推送。
- **run 入口**：`/fpga-orchestrator 恢复：C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-0207_runA_ddr_readback_loop；本轮目标：<G4/生产化/板证/归档>`。

## 8. 一句话

**DDR 读回自证闭环已从“核心 RTL”推进到“集成+构建+坏帧/100 帧仿真+板内实测”：身份/长度/校验状态/CRC 自洽与运行计数均在板上读回，G3 双 Tier 通过；G4 与生产化按用户口径后置；两线隔离与父子任务边界如实登记。**
