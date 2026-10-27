# closeout-KB5 — KB5 收束记录（run 20261017_162355_fpga_knowledge_book）

- 角色：fpga-planner（原规划者续接）；日期：2026-10-17；性质：中间收束（收敛首包 KB5 关闭 → 派发 KB6）。
- 依据：主 Agent 交回的 KB5 综合测试结果（r0 首次验收 PASS）；规划者按 §13 收敛规则与现行 work-limits 处置。本文件为本轮收束的**权威裁定与交接记录**；dev-plan §11「KB5 收束」为其摘要。

## 1. 结果与证据

| 项 | 结果 |
|---|---|
| 判定 | **综合 PASS（round0 首次验收，0 修复轮）**；报告 `test-reports/KB5-r0-integrated.md`（SHA256=`62136ec046843a6583d61acfe422e9988b95d0bf9a4dc2aaa81060fe3c398234`，11359B，首行唯一判定） |
| 检查清单 | functional PASS（16–20 章与 §3/§13 边界与模板；关键算术手算复核全对；三路线裁决口径）；engineering PASS（哈希 0 不一致；**01–15 与中央三文件零触碰**＝"已生成先不改"合规；link-check 24=21+1+2 自洽）；system PASS（相对引用存在、T10/M5.4 口径、"README 未写"＝规划预期） |
| 冻结清单 | `manifests/KB5-manifest.json`（SHA256(前16)=`19a3cd57…`，现场复算一致） |
| 漂移 | main-log／并行线快照按 R1 归因外部，不影响判定 |
| 交付 | 第 16–20 章（压缩篇）＋KB5 记录面；**未触碰任何既有文件**（合规证据见上） |
| 统计 | 首次通过=3（KB2、KB4、KB5）；修复 1 轮通过=3（KB0、KB1、KB3）；修复 2/3 轮=0；⚠=0；blocked=0 |

## 2. 裁定（R25–R27）

- **R25（functional 2 条低危观察）＝记录，不修**：
  - ch19"硬件层"标题并入数字节（结构小项）；ch18 问题 6 偏薄（但跨章覆盖成立）。
  - 依据：§13 收敛规则——新包内非阻断观察**仅记录**、不新增 F 类修订项；两条均不阻断判读价值。
- **R26（engineering 记录观察：OMLS 现场 HTTP 200 可达 vs link-check"404→已失效"降级）＝接受**：降级方向保守、无虚构（`fpga-design-guide` §5 允许"已失效→备选/检索词"）；仅记录。
- **R27（system：README 16–20 行"未写"）＝确认预期**：README 终版刷新归 KB7（§13），KB5 不触碰 README，非缺陷。

## 3. 下一包（KB6）边界要点（详见 dispatch.json 与 §13 权威表）

- 产物：`21_PCIe基础.md`、`22_DMA与完成语义.md`、`23_R10F帧协议.md`、`24_双路与同步.md`、`25_HDMI调试出口.md`、`26_工程方法与证据判读.md`（6 章；语义步骤 5：21／22／23／24＋25／26）。
- 轻量档；模板 10 节不变；资源 3–5 条/章；**01–15 与 README/规范/大纲只读**；不新增 F 项。
- 验收重点：PCIe/TLP/DMA/R10F 语义与冻结值（128B/640B/2,592,768B/三层 CRC/0x61/session/seq）、同步口径（SOF≠曝光、共享 XHS/XVS、失锁恢复）、HDMI 数字（742.5MHz/1485Mbps；4Kp30≈297MHz/2.97Gbps；超手册未决）、G0–G5 判读与 5.1 必检要点。

## 4. 输入漂移与文件状态

- `dev-plan.md`：本轮更新（§0⑥/§4/§8/§11/§13 执行状态）→ 新 SHA256(前16)=`BD0175A9FCBDFC86`（KB6 以新值为输入冻结并登记）。
- `docs/知识书/`：01–20 章＋README/规范/大纲；README 仍为 KB4 时点快照（16–20 行未写＝§13 预期；KB7 终版刷新）。
- run 记录：本文件新增；KB0–KB4 资产保留；KB5 三件（manifest/report/link-check/dev-notes）由 KB6 输入链引用。
- 任务板：`workflow/tasks.json` 无本流条目、未修改。用户侧：open-questions 其余 4 项默认。

## 5. 下一动作

- **派发 KB6**（见 `dispatch.json`）；KB7（27＋附录＋README 终版）待 KB6 收束后派发。
