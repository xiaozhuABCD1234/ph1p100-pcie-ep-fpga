# T10.b10-b9-fix 收尾摘要（**未收尾**：r1 已冻结并派发，待开发/独立测试回填）

> 本文件只记录 r0 实际结果、r1 冻结口径与当前未完成状态。**不得**被理解为候选已重建、板级已恢复或父 T10 已完成。

## 1. 任务与当前轮次

| 项 | 值 |
|---|---|
| 任务/父任务 | `T10.b10-b9-fix` / T10（父**不置 done**） |
| run | `20261020-0209_singleA_aplus_closedloop` |
| 当前轮次 | **r1**（同包续轮；r0 已 blocked） |
| 可写根 | `T10.b10-b9-fix/**`（r1 产物仍在 `r0/` 下，新证据用 `r1` 后缀命名） |
| 上级候选 | `T10.b9-rawstore/r0`（只读；bit `950b6e4a…a06`、CWC `b9515f79…1cdd7`、BID `67c289a8…70a8b`） |

## 2. r0 实际结果（已冻结）

| 项 | 结果 |
|---|---|
| B9-01 | **PASS**：旧版反例复现（`exported=1`、`sts_want=1`、`dq_cnt=1`、UART 停），修复版 `exported=2`、状态包在帧间 offset 2044、`both_grant=0`；`STATUS_DIV` 6/6 扫描通过 |
| B9-02 | **PASS**：14 描述符/3+ 次环绕、同拍 push/pop、满拒收、空边界全过，`dq_cnt` 影子计数断言 0 失败 |
| B9-03 | **PASS**：DDR 512 MiB 容量足够；四槽 0–259,199 / 262,144–424,313 无重叠；旧布局反例 `ovl=20272` |
| P1 三黄金 | **PASS**（`fa513a2b…` / `ee61e620…` / `b992a8ad…` 逐字节一致） |
| R2 / R3 | **PASS**（R3 残余：旧 R 晚于新 AR 的区分 `not_covered`） |
| R1 | **not_covered**（定向顶层用例未构造成功，三处尝试已全部回退） |
| 3 连续真实帧 | **not_covered**（`tb_b10_multi` 自建相机驱动缺陷，`frames=0`，非 RTL 判定） |
| TD | s2/s3 时序好（Routed +0.267/+0.239，0 违例），但**源码含已修复的 `crop_pix` 1-bit 缺陷**，网表不可用；综合 3/3、布线 2/2 用尽 |
| bit/CWC/下载 | 无有效 bit/CWC；**下载 0/2**；Flash 0 |

## 3. r1 唯一主要目标

用 r0 已冻结并通过 P1 的 `r0/changed-src` 源码，**重新综合 1 + 布线 1 + bitgen 1 + CWC 1**，得到唯一有效候选；随后「先下载、后开 COM8」采 180 s，要求 `raw_pub/enc_frames/exported` 增量 >0 且至少 1 帧 44 B 头 + stream CRC + zlib 解码通过。

## 4. r1 冻结的关键决定

1. **不修改 RTL/参数/SDC/引脚/端口**。源哈希以 r0 manifest 为准（exporter `ff0ce16d…`、camera top `612d42a5…`、bridge `b9e83481…`、board top `98d6c446…`）；`crop_pix` 已确认 `[39:0]`。
2. `camera_a1_uart_top.v` 的 `// T10.b10 R1:` 注释为 r0 **已回退**尝试的历史注释；本候选**无** R1 功能修复。r1 manifest/result 必须如实写明，禁止为清注释改文件。
3. TD 严格单次：综合 1、布线 1、bitgen 1、CWC 1；先在 `r0/td` 内归档 s2/s3 报告并改写 `a1_board_Runs`/`a1_board.al` 名称，再新建工程；失败即停。
4. G2-r1：Routed 0 违例、SWNS ≥ +0.05、TNS 0、hold/period 0；资源相对 b9 ≤5% 且 ERAM 不增；bit 与 `cw/compiled.bit` 字节一致；BID 存在。
5. G3-r1：**先下载（COM8 关闭）→ 释放 FTDI → 后开 COM8 180 s**；≥2 个合法 v3 包；三计数增量均 >0；≥1 帧解码通过。
6. 下载 1 次（累计 ≤2）；失败/静默/部分达成均停，不二次下载、不写 Flash。
7. R1/3 连续帧补测为**可选证据**，只在 G3 证据落盘后、预算内做；不改候选。

## 5. 预算

- 开发：90 min / 50 calls。
- TD：1 会话 / 60 min；综合 1、布线 1、bitgen 1、CWC 1。
- 下载：1（累计上限 2）；Flash 0。
- 综合测试者：45 min / 30 calls；0 TD 重跑、0 下载。

## 6. 当前实际状态

| 项 | 状态 |
|---|---|
| r0 修复 | B9-01/02/03、P1 PASS；R1/3 帧 not_covered |
| r0 候选 | **无**（TD 预算用尽 + 最后网表源码缺陷） |
| r1 规划冻结 | **完成**（dev-plan §7、handoff、user-summary、dispatch） |
| r1 开发 | **未开始** |
| G1-r1（源复核对） | 规划侧已复核，开发需在 TD 前再算一次 |
| G2-r1 / G3-r1 / G4-r1 | **not_run** |
| 实际修复轮数 | r0 = 1 轮（离线修复）；r1 不计修复轮，只重建候选 |
| 下载次数 | 0 / 2（r0 未消耗；r1 计划 1） |
| 父 T10 | 保持 blocked / not done |
| 板级根因 | **仍未确认**；r0 修复只证明离线缺陷，不证明板上已恢复 |

## 7. 收尾条件

- 开发回填 `CANDIDATE-MANIFEST-b10-b9-fix-r1.json`、`result-r1.md`、bit/CWC/BID、`captures_r1/**`；
- 独立 fpga-tester 产出 `test-reports/T10.b10-b9-fix-r1-integrated.md`，绑定同一 manifest；
- 原规划据实更新本文件、`handoff.md`、`user-summary.md`；父 T10 不因本包自动置 done。

## 8. 下一次准确启动文本

```text
使用 fpga-planner 恢复：D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b10-b9-fix；
本轮目标：核对 r1 开发/测试回填（G2-r1/G3-r1、实际下载次数、候选哈希），更新 final-summary 与 handoff；
PASS 则推进父 T10 板链证据；FAIL/⚠ 则按原开发/原测试续接（最多三轮实际修复）。
```

开发入口：`T10.b10-b9-fix/dispatch.json`（r1 当前）→ `next_action.prompt_path`（`dev-plan.md` §7）。
