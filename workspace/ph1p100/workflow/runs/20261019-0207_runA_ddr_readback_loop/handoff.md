# handoff.md — 20261019-0207_runA_ddr_readback_loop（终版）

日期：2026-10-19。原规划者收尾。**run 终态=finished**。本轮=Track A 全链切片（checker 集成→构建→几何核对→坏帧/100 帧仿真→上板清单+实测），仅 SRAM、不写 Flash、不推送、不接 PCIe/RK；与并行线 0212（Codex）物理隔离、互不合并。

## 1. 终态判定

| 包 | 判定 | 轮 | G0 | G1 | G2 | G3 | G4 |
|---|---|---|---|---|---|---|---|
| T11.runC-checker-integrate | **PASS** | r1（修复 1） | pass | pass | not_run | not_run | not_run |
| T11.runC-build | **PASS** | r0 | pass | pass(继承) | pass | not_run | not_run |
| T11.runC-sim-campaign | **PASS** | r0 | pass | pass | not_run | not_run | not_run |
| T11.runC-board-checklist | **PASS** | r0 | pass | pass(继承) | pass(继承) | **pass（Tier-1+Tier-2）** | not_run |

- 首次通过 3/4；实际修复 1 轮（P1）；blocked 2 次（非 FAIL、不计轮：P1 工作树冲突→重锚；P4 板窗占用→awaiting）；⚠未通过 0。
- **父 T11 不置 done**；`workflow/tasks.json` 本轮未写（保护范围）。

## 2. 最终候选

| 项 | 值 |
|---|---|
| bit | `5B67A8F5…1D52`（5,224,027 B；SRAM 已上板 2026-10-19 21:56:53） |
| CWC | `8DDA54D4…664F`（143,444 B） |
| BID | `A068E42E…F1DB`（151,492 B） |
| manifest 链 | P1 `68AB235E…` → P2 `0F67D299…` → P3 `01938ebb…` → P4 v8 `3594bb40…` |
| 源码 | wt0207（branch `opencode/runC-0207`，HEAD `b0282d2a`，6 M + 4 ??，worktree-only，未 commit/未推送） |
| 旧候选 | `bfafdf97…`（前板载）、`2385cded…`（早期证据）、`e81d353b…`（回退）、`AFFC4396…`（仅证据）；并列保留 |

## 3. 板上实测与 G3

- 用户 GUI 四样本（A/B 秒位截断；C `22:13:15`、D `22:13:45`，间隔 30 s）：身份三字全中、w8=`00000021`、w3 单调 `3216→3818→15293→15764`、w4 BASE1/BASE0 轮换、w5=2,592,768、w6 good 模 256 自洽且坏计数 0、w9=`0x3E`、w10=648,192、w13=w3、w11/12 非零、w14=w15=w12。
- G3=**Tier-1 PASS + Tier-2 PASS**；G4=not_run（长稳/热态未测）。
- 预加载：`download -mode jtag` 1/1 次、PRG-2014、100%、30.037585 s、下载后 PH1P100；零 Flash。

## 4. 证据索引（关键路径）

- 报告：`test-reports/T11.runC-checker-integrate-r1-integrated.md`、`T11.runC-build-r0-integrated.md`、`T11.runC-sim-campaign-r0-integrated.md`、`T11.runC-board-checklist-r0-integrated.md`。
- 冻结件：`checker-integrate/`、`build/`（含 `hardware-ready.md`）、`sim-campaign/`、`board-checklist/`（`candidate-manifest-v8.json`、`evidence-index.md`、`board-checklist.md`、`rollback.md`、`board-samples-01/02.md`、`preload-record-v6.md`、`hash-chain-recompute.txt`）。
- 暂存：`D:\anlogic\runa_runC\20261019_192056\`（paired bit/CWC、`preload.bwcmd`、`staging-record.txt`；只读保留）。

## 5. 非阻塞观察（报告 §5，供后续触碰时修正）

1. 开发报告 §2.3 把 B 样本 hdr/pay 两位读反（`0x2D` 应为 hdr=1/pay=0）；tester 已在报告更正，结论不变；如需改 `board-samples-01.md` 须新 manifest 版本，不必重跑。
2. manifest v8 `generated_at` 与 mtime 不一致（元数据笔误；P2 同类）。
3. `board-checklist.md` §4 来源措辞：word4/5/7/8 实为基线参考，非全部来自 `hardware_ready`。
4. word4 双缓冲直接源应为 `cam_ddr_writer.v` L132-133/L788-790（`ddr_frame_pusher` 为旁证）。
5. 预算超用如实登记：P2 dev 31/30 calls；P4 dev 首返 30/30 calls/≈35 min；P4 tester ≈31/25 calls。

## 6. 两线协调状态（0212 = Codex，独立）

- 本线唯一写树=wt0207；共享树 `upstream/ph1p100-pcie-ep-fpga` 归 0212，本线只读；两线不合并树/候选/构建产物（CR-20261019-0207-02）。
- TD 构建窗口同机串行；板卡/下载窗口单一互斥（本线本次下载 1 次）；若未来择一上板，由用户/原规划裁定。
- 0212 线进展本 run 不跟踪、不引用；如需合并/对照，另立交接规则。

## 7. 回退

- 板：断电 10 s 清 SRAM；重下旧 `e81d353b…`（≈30–40 s，SRAM，不写 Flash）。
- 源码：wt0207 worktree-only；按需逐文件还原/删除新增 TB（遵守单文件删除禁令）。
- 产物：丢弃 run 本包目录即可（默认不删、单文件操作）；旧候选/旧证据不受影响。

## 8. 恢复入口与后续主题（≤4，不自动续做）

1. G4 长稳/热态（100 帧→10 min 级；word6 good 稳定性归因）。
2. checker 生产路径（DBG-off 常驻）+ PCIe/RK 主机侧寄存器与端到端（需授权）。
3. 真实几何/相位完整板证（MP07/08）+ 三算法接入。
4. 与 0212 候选择一/统一（如用户要求；板窗互斥）。

恢复入口：`/fpga-orchestrator 恢复：C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-0207_runA_ddr_readback_loop；本轮目标：<目标>`。
