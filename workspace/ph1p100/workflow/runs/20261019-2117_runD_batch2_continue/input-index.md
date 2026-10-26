# input-index.md — 20261019-2117_runD_batch2_continue

更新时间：2026-10-19 21:30 +08:00。规划者只读核对了本文件列出的输入；未修改任何旧 run、生产源码、候选或硬件。

## 1. 本轮需求、授权与口径

- 用户原话（`request.md`）：“FPGA 侧闭环加速推进，进度优先，稳定性/优化后放”；“本轮明确授权 batch=2：Track A=单A RAW→DDR 板级闭环（读回校验/几何/坏帧）；Track B=T09 三算法并入生产工程+离线仿真+双相机同步RTL离线起步”；“尽量合并构建；仅 SRAM、不写 Flash、不推送；不接 PCIe/RK；最后留‘回来点两下’的上板清单”。
- 补充原话：“我之前把这项任务交给了codex，现在有一定进展，看后进行接着做，并且不要和track A相互堵塞”。
- 授权解释（本轮冻结）：
  - batch=2 为**实际实现批**：T02 单A板级闭环 + T08 双相机同步离线原型，一开发顺序实现、一综合测试覆盖全批。
  - “接着做”指续接 0212 Codex run 已冻结的 B01/T02/T08 成果；不是重置旧计数，也不是把旧 run 的失败改名为成功。
  - 板卡仅 SRAM；不写 Flash/efuse/SPI/svf；不推送远端；不接 PCIe/RK；禁止批量删除。
  - “不要和 Track A 相互堵塞”按本 run `dev-plan.md` §2 的板窗租约和独立 worktree 规则执行：本 run 的 Track B 不等待板窗；本 run 的 Track A 与 0207 线只通过机械窗口检查/租约记录串行，不互等、不杀进程。

## 2. 只读输入与采用版本

### 2.1 基线 run（finished）

| 项 | 路径 | 状态/用法 |
|---|---|---|
| 基线 run | `workflow/runs/20261018-1631_runA_fpga_side_readchannel/` | finished；4 包 PASS；G3=partial、G4=not_run。仅作历史/回退参照，不重开其修复轮。 |
| 基线 bit/CWC | `debug-fix3/prj/ph1p_pcie_integration_Runs/phy_1/cw/compiled.bit` / `compiled.cwc` | bit `bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0`；CWC `8d2998b96ef1763c14a1302118235a687488297ce496692b1f6cd95d76981026`。仅回退候选，不是本轮新候选。 |
| 基线 manifest | `debug-fix3/candidate-manifest.json` | 只读身份参照。 |

### 2.2 0212 Codex run（用户要求“接着做”的主输入）

路径：`workflow/runs/20261019-0212_codex_fpga_closedloop_b2/`

| 项 | 路径/身份 | 采用结论 |
|---|---|---|
| 当前交接 | `final-summary.md`、`handoff.md` 顶部“B01 r0通过，T02板验入口已派发” | 当前状态以此为准；下方旧收尾为历史。 |
| B01 两包报告 | `test-reports/T06.codex-ddr-readback-int-r0-integrated.md`；`test-reports/T09.codex-production-int-r0-integrated.md` | 均 **PASS round0**，实际修复 0。 |
| B01 最终 manifest | `recovery01/B01/timing-continuation01/remaining-attempts01/candidate/manifest.json` | SHA256 `c7a40897166467f2beafb096701dba9cf836e1007d77ae03d90009d06f80d757`；699 项；本 run 作为既成输入，**不重建、不重跑算法仿真、不申请第 7 次生产构建**。 |
| B01 bit/CWC/BID | 同目录 `current.bit` / `current.cwc` / `current.bid` | 报告身份：bit `b68c6e183e97eb0d465db77078f5049feca3a947fac51f99633621dd99b3f9bf`、CWC `b28e3d4ee476731b118da0b12c3bad8dcca1dadfbd9b7ae4dc418c4d225a74ce`、BID `4dcdc26382f6b49e7ed9b95a40a1d57c05191c0130050812a74b853c16b38f33`。下载前必须复算；不符即 `INPUT_CONFLICT`，不下载。 |
| 板测计划 | `t02-board-plan.md`、`board/t02/two-capture-checklist.md`、`board/t02/probe-reference.md` | T02 的 G3 验收、40 项探针、两次采样、几何/相位/内部 abort 口径取自此处。 |
| 上次 SRAM 尝试 | `board/t02/sram-attempt-notes.md`、`sram-entry.stdout.log`、`question-sram-timeout.md`、`sram-execution.json` | 1 次 120 s 超时、0 样本、加载状态 unknown、blocked 未重试；本轮只新增 1 次有界尝试，不隐去旧失败。 |
| 固定 SRAM 入口 | `recovery01/B01/timing-continuation01/remaining-attempts01/scripts/run_sram.py`、`board-entry.md` | 只读；沿用其 connect/read_device_id/download 语义。若脚本不支持输出目录覆盖，可复制到本 run 并只改输出路径，记录 diff。 |
| T08 任务冻结 | `task-T08-sync-offline.md`、`sync-offline/`（26 项 manifest `94FF1150…DF06A`） | 旧离线任务：2 次编译尝试，第二次报 `sync_offline_top.v` 两处非法位置连接“()”，未进入 vsim；旧计数保留。 |
| T08 开发建议 | `handoff.md` §“每包恢复边界”：named `.src_busy()` 技术建议，未实施/未验证 | 本轮可由原 T08 任务续接实施，作为新 run 的 round0，不能声称旧编译已通过。 |

### 2.3 并行 OpenCode Track A（0207，in flight，只读）

路径：`workflow/runs/20261019-0207_runA_ddr_readback_loop/`

| 项 | 状态/身份 | 本轮协调结论 |
|---|---|---|
| P1—P3 | PASS r1 / PASS r0 / PASS r0 | 仅作并行线状态，不并入本 run 候选。 |
| P4 | `awaiting_user_gui`；`board-checklist/preload-record-v3.md`：19:58—20:13 有界等待 0212 构建，**0 次 download**；板已上电（用户报告） | 0207 当前不持有板窗（未下载）。其候选 bit `5B67A8F5…1D52`/CWC `8DDA54D4…664F` 属另一条线。 |
| 写树 | `upstream/ph1p100-pcie-ep-fpga-wt0207`（HEAD `b0282d2a`，6 M+4 ??） | 本 run **不写**、不合并、不采集其证据。共享树 `upstream/ph1p100-pcie-ep-fpga` 是 0212 本线写树；0207 只读。 |
| 板窗 | 0207 未下载；其 P4 清单已冻结 | 本 run 下载前读其最新 `preload-record*.md`/`dev-result.md` 与进程表；若其正在下载/已成功预载未消费，则本 run 停止并返回 `awaiting_board_window`，不等待、不覆盖。 |

### 2.4 本轮新建输出（规划者）

- `workflow/runs/20261019-2117_runD_batch2_continue/dev-plan.md`
- `.../fpga-design-guide.md`
- `.../input-index.md`（本文件）
- `.../dispatch.json`

## 3. 复用/不复用裁定

1. **复用且不再构建**：T06.codex-ddr-readback-int + T09.codex-production-int 的 B01 r0 PASS、699 项 manifest、bit/CWC/BID、生产 6/6 构建结果、G0/G1/G2 报告。T09 三算法离线仿真已在该 PASS 中覆盖（oracle/adapter/rate/负对照/1080p 两帧），本轮**不重复运行、不重复构建**；只在 T08 改动前后复核 699 项哈希未漂移。
2. **本轮真正的新实现**：仅 T08 的编译修复、离线 TB、负对照与一个小顶 G2；以及 T02 的一次有界 SRAM 下载、板窗租约、上板清单。
3. **不复用**：0207 的候选、manifest、报告不并入本 run；旧 T02 的 0 样本不能当 G3；T08 旧 manifest 26 项不能当新 PASS；旧 bit `bfafdf97…` 只作回退。
4. **不重置计数**：0212 的 T02 SRAM 1 次超时、T08 2 次编译尝试保留为历史。本轮是用户新指令触发的新 run/新 round0；dispatch 与报告中同时写“历史累计”和“本轮新增”，不写“清零”。
5. **不把离线 PASS 外推硬件**：T08 未接活动 top，G3/G4 不适用；T02 未取得两样本前，G3 仍 `not_run/awaiting_hardware`，不得用 preload 记录代替。

## 4. 写范围与保护（摘要，详见 dev-plan）

- T02 开发：只写本 run `board/t02/**`、本 run `board/board-window-lease.json`、SRAM 本地日志目录；生产源码、0212 旧 run 既有文件、0207 run/wt0207 均只读。
- T08 开发：只新建/修改 `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/cam/sync_offline/**`、`sim/tb/tb_sync_offline*.v|sv`、本 run `sync-offline/**`；不改活动 top、`sim/compile_checked.f`、I2C/寄存器表、约束/IP/ADC、B01 699 项、`workflow/tasks.json`。
- 保护：B01 699 项 manifest/bit/CWC/BID/DB/报告/脚本；0212 旧 run 全部证据；0207 run 与 wt0207；基线 bit/CWC；TD 安装目录；其他工作树/`parallel/**`/D 盘活动工程；全局配置。
- 禁止：commit/push/amend/rebase、Flash/efuse/SPI/svf、PCIe/RK、GUI 自动化、杀他人进程、批量删除。

## 5. 未决/假设（规划已给定处理方式）

| 未决项 | 处理 |
|---|---|
| 板当前是否仍上电、USB/JTAG 是否独占、5555 是否有 server | 开发先做机械检查与只读 `read_device_id`；不是 PH1P100 即停，不下载、不重试，返回 `awaiting_hardware`。 |
| 0207 是否同时抢板窗 | 下载前读 0207 最新记录 + 进程表；活跃/已预载未消费即停；本 run 不等待、不杀进程。 |
| T08 小顶 TD 是否被占用 | 一次 TD 综合 ≤25 min；被占用即记录 `blocked`、G2 `not_run`，不以离线 G1 冒充 G2，也不等待。 |
| 用户何时“点两下” | 开发下载成功后立即返回 `awaiting_user_gui` 与清单，不空等；主转达后由后续续接记录两样本。 |
| T08 修复是否需改活动 top | 不允许；若必须改，停并交原规划 `SCOPE_CLARIFICATION`。 |
