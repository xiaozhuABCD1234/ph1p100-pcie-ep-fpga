# dev-plan.md — 20261019-2117_runD_batch2_continue（v1）

原规划者编写；2026-10-19 21:30 +08:00；宿主 OpenCode。授权来源：本 run `request.md` 用户原话（batch=2、Track A/Track B、进度优先、仅 SRAM、不写 Flash、不推送、不接 PCIe/RK、“回来点两下”清单）+ 补充原话（“接着做”“不要和 track A 相互堵塞”）。输入核对见 `input-index.md`；工程语义见 `fpga-design-guide.md`。

## 0. 本轮定位、续接点与 done 口径

### 0.1 一个主要目标

**在不新增生产构建、不重置旧计数的前提下，续接 Codex 0212 线**：完成单 A RAW→DDR 板级闭环的候选下载/上板入口（两样本后判 G3），并把双相机同步离线原型从“编译未通过”推进到可独立验收的 G0/G1/G2；最后交一份“回来点两下”清单。

### 0.2 续接判定（读 0212 后的结论）

| 0212 成果 | 判定 | 本轮处理 |
|---|---|---|
| T06.codex-ddr-readback-int + T09.codex-production-int：integrated r0 **PASS**，0 修复，699 项 manifest `c7a40897…d757`，生产 6/6，G0/G1/G2 pass | 既成输入 | 直接复用；**不重建、不重跑算法仿真**；T09 三算法离线仿真已由 r0 报告覆盖（9 项仿真：oracle/adapter/rate/负对照/1080p 两帧） |
| T02.codex-singleA-board：1 次 SRAM 下载 120 s 超时、0 样本、加载 unknown、blocked | 未完成 | 本轮续接；新 run round0；只新增 1 次有界下载（≤180 s），不重试；未取两样本前 G3 不判 PASS |
| T08.codex-sync-offline：2 次编译尝试，`sync_offline_top.v` 两处非法位置连接“()”，未进 vsim；held | 未完成 | 本轮续接；新 run round0；新增有限 2 次编译/1 次 TD 小顶；旧 2 次保留历史 |
| 0212 旧收尾“blocked/未验收”段 | 历史 | 不覆盖、不改写；当前状态以 0212 `final-summary.md`/`handoff.md` 顶部 B01 PASS 段为准 |

### 0.3 本轮 done 口径

- **T08 done** = TB 编译 + 正例 0 mismatch + 有效负对照 + 小顶 G2（Routed、WNS/TNS≥0、3 时钟、CDC/资源）齐备，并冻结 manifest；缺 G2 时最多记 `blocked/partial`，不写 PASS。
- **T02 done（本轮包）** = 候选复算通过 + 板窗租约/机械检查 + 一次 SRAM 下载成功 + “回来点两下”清单冻结 + 板载状态记录；若用户两样本在本轮返回，则再算 G3 证据。**没有两样本就不算 T02 闭环 done**，G3=`not_run/awaiting_hardware`。
- **父任务**：T02/T06/T11 不因 B01 PASS 或 preload 置 done；G4 后放；T08 父范围（真实双路曝光同步）不因离线原型 done。
- **不混淆**：离线 G1/G2 PASS ≠ 板测 G3；preload 成功 ≠ 两样本；0207 线证据 ≠ 本 run 证据。

## 1. 安全与边界（全程）

- 板上仅 SRAM；零 Flash/efuse/SPI/svf；不改线/电源/相机/传感器表；禁止 GUI 自动化；CLI 读回永久关闭。
- 不 commit/push/amend/rebase；不批量删除；不杀他人 TD/BW/server 进程；不写其他工作树/`parallel/**`/D 盘活动工程/TD 安装目录。
- 不接 PCIe/RK、不做压缩、不做 G4 长稳/性能优化。
- 用户可能不在场：所有需要点击/上电的步骤后置为清单；开发不空等。

## 2. 并行线协调（CR-20261019-2117-01，冻结）

### 2.1 写树隔离

| 线 | 写树 | 本 run 权限 |
|---|---|---|
| 本 run T08 | `upstream/ph1p100-pcie-ep-fpga`（0212 生产检出；HEAD `b0282d2a`；B01 dirty 保留） | 仅新增/修改 T08 文件；B01 699 项只读 |
| 本 run T02 | 无生产写；只写本 run `board/t02/**` 与 `board/board-window-lease.json` | 不写生产树 |
| 0207 并行 Track A | `upstream/ph1p100-pcie-ep-fpga-wt0207`（branch `opencode/runC-0207`；HEAD `b0282d2a`；候选 `5B67A8F5…`） | 只读；不合并、不借用 |
| 0212 旧 run | 只读 | 除本 run 不写入；不覆盖其 board/t02、candidate、报告 |

### 2.2 板窗租约（单窗口、不互等）

1. 下载前做**机械检查**：无活跃 TD 构建/下载进程（`td_commands_prompt`、`run_td`、`run_build`、`bw`/`download`）；既有 `td.exe` GUI 与 hwserver 不动。
2. 读 0207 最新 `board-checklist/preload-record*.md`、`dev-result.md`：若其正在下载，或已成功预载未消费/未回退 → 本 run **不覆盖**，返回 `awaiting_board_window`。
3. 通过则写 `board/board-window-lease.json`（候选 SHA、时间、进程快照、0207 结论），再执行一次 SRAM 下载；下载后更新租约“board=本 run 候选”。
4. **有界等待=0**：占用即返回，不轮询、不催促、不杀进程。0207 下次恢复读租约必须停；双方都不阻塞对方离线工作。
5. Track B（T08）完全离线，使用 ModelSim/独立小顶 TD，**不等待板窗**；T08 的 TD 小顶也不得与正在进行的 SRAM 下载并发启动。

## 3. 正式包总表

| 顺序 | task_id | 主要可观察结果 | 工作树/允许写路径 | 依赖 | functional 验收 | engineering 验收 | system 验收 | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `T02.codex-singleA-board` | 同 B01 候选的单 A RAW→DDR 板级入口：一次 SRAM 下载 + 板窗租约 + 两点击清单；有两样本则附 G3 证据 | 本 run `board/t02/**`、`board/board-window-lease.json`；SRAM 本地日志目录；不写生产树 | B01 699 项 PASS（既成） | 下载身份 `PH1P100`、bit/CWC/BID/manifest 复算一致；两样本（如返回）满足 guide §1.2；无样本=awaiting | 同 manifest 绑定；下载前后 SHA 0 漂移；日志/退出码/时长齐；无第 7 次构建 | 仅 SRAM/零 Flash/不覆盖 0207/操作者时间记录/回退齐 | G0/G1/G2 继承；G3 本轮（样本后） | ready（本轮派发） | 开发 preflight→租约→一次下载→清单；返回 awaiting_user_gui 或 blocked |
| 2 | `T08.codex-sync-offline` | 可编译、可自检、可综合的双相机安全启动/SOF 配对离线原型 + 自身 G2 | `upstream/.../rtl/ep_side/cam/sync_offline/**`、`sim/tb/tb_sync_offline*.v|sv`、本 run `sync-offline/**` | B01 释放同写树；T02 下载完成/让出窗口后（顺序执行，不并行抢 TD） | 正例 0 mismatch、vlog Errors:0、vsim 明确 PASS；负对照预期失败；24 ms/8 帧/NACK/单路/reset/配对覆盖 | 小顶 G2 Routed、WNS/TNS≥0、3 时钟、CDC/约束/资源；manifest 0 不一致；B01 699 项 0 漂移 | 未接活动 top/未下载/零 Flash；文件范围与回退记录齐 | G0/G1/G2；G3/G4 N/A | blocked（旧 2 次编译，未验收） | 开发修 2 处 named port→编译/TB→一次小顶 G2→冻结 |

- 正式包 2 个（ready/blocked 都计）；两级（需求→工作包）；每包 ≤5 项语义步骤；batch=2 仅合并开发/测试角色，不减少任务数。
- 本轮不新增全局 T 任务，不改旧 ID；T02/T08 原任务 ID 继续使用，旧 run 计数不重置。

## 4. 详细工作包

### 4.1 P1 `T02.codex-singleA-board`（板级；本轮第 1 包）

**主要可观察结果**：确认 B01 候选身份后，在独占窗口完成一次 SRAM 下载并冻结“回来点两下”清单；若用户两样本在本轮返回，附 G3 证据；否则如实的 `awaiting_user_gui/awaiting_hardware`。

- **允许写范围**：`workflow/runs/20261019-2117_runD_batch2_continue/board/t02/**`；`.../board/board-window-lease.json`；`.../board/sram/<timestamp>/**`（新建日志/脚本副本）。若冻结的 `run_sram.py` 不支持输出目录覆盖，复制到本 run 并只改输出路径，记录原/新 SHA 与 diff；下载命令语义不变。不写 0212 旧 run、不写生产树。
- **保护**：0212 B01 699 项 manifest/bit/CWC/BID/DB/报告/脚本；0212 `board/t02/**` 既有文件；0207 run/wt0207；基线 bit/CWC；`workflow/tasks.json`；TD 安装目录。
- **语义步骤（≤5）**：
  1. **Preflight（无硬件）**：复算 B01 manifest 699 项、bit/CWC/BID SHA、probe map；核对 T06/T09 r0 PASS 报告与 2 份同 manifest；读 0212 `t02-board-plan.md`、`board/t02/two-capture-checklist.md`、上次超时日志；确认生产 6/6 不再构建。
  2. **板窗/现场机械检查**：进程表；0207 最新 preload/dev-result；`read_device_id` 只读；记录电源/USB/JTAG/5555 状态。非 `PH1P100`、server 不在、0207 占用 → 停并返回 `awaiting_hardware/awaiting_board_window`，不下载。
  3. **一次 SRAM 下载**：写租约 → `download -mode jtag`（≤180 s，owned PID tree，失败不重试）→ 记录 rc/PRG-2014/时长/SHA/设备身份；零 Flash、零 CLI 读回、零 GUI 自动化。
  4. **上板清单**：冻结 `board/t02/board-checklist.md`（候选绝对路径+SHA、当前板载、两次点击≥20 s、16 字原值/截图/时间戳、期望值、几何/ROI/相位、内部 abort+恢复、异常分流、回退旧 bit/CWC、G3 tier）；如用户两样本已返回，按 guide §1.2 逐项核对并记录原始值。
  5. **冻结**：写 `board/t02/candidate-manifest.json`（preload 记录/清单/日志 SHA、manifest 绑定、历史 120 s 超时与本轮结果分列）、`dev-result.md`、`lessons.md`；停止活动后 `ready_for_test`（若仅 preload/清单则状态仍 `awaiting_user_gui`，tester 可先核证据，不判 G3 PASS）。
- **综合测试三维对象**：functional=候选/下载/清单语义与冻结期望一致；有两样本则独立核 G3（不重拍、不重下）；无样本则 `blocked/awaiting_hardware`。engineering=699 项/bit/CWC/BID/DB 身份、下载日志/退出码/时长、manifest 0 不一致、无第 7 次构建。system=仅 SRAM/零 Flash/不覆盖 0207/操作者时间/回退链/CLI 读回关闭。
- **必要 G 层**：G0（候选/现场）、G1/G2 继承 B01 同 manifest；G3 本轮（样本后）；G4 not_run（用户后放）。
- **工具/超时**：只读 `read_device_id` ≤60 s；download ≤180 s；样本收集每组 ≤5 min；总 3 组上限沿用 0212（本轮最多 1 组首次 + 2 组针对性补样）。
- **停止/回退**：板不在/身份不符/窗口占用/下载失败 → 不重试，保留日志，返回 `awaiting_hardware/awaiting_board_window`；需改候选/新构建 → 停，交原规划；回退=旧 bit/CWC 或断电（用户按清单），不自动电源循环。
- **预算（冻结）**：dev **≤20 min / ≤20 calls**（理由：preflight+租约+一次下载+清单；上次同类用 30 calls，本轮只做单包）；tester **≤20 min / ≤20 calls**（证据/哈希/清单，不重跑硬件）。

### 4.2 P2 `T08.codex-sync-offline`（离线 RTL；本轮第 2 包）

**主要可观察结果**：可编译、可自检、可综合的双相机安全启动/SOF 配对离线原型；自身 G0/G1/G2 证据；不接活动 top、不下载。

- **允许写范围**：`upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/cam/sync_offline/**`（含既有 T08 文件）；`sim/tb/tb_sync_offline*.v|sv`；本 run `sync-offline/**`（脚本、小顶、SDC、Tcl、g1/g2、日志）。不改 `sim/compile_checked.f` 的生产默认行为（如需追加仿真文件，只在本 run 的 local filelist 中记录）。
- **保护**：B01 699 项、活动 top、原 I2C/寄存器表、生产约束/IP/ADC、旧 run/证据、`workflow/tasks.json`。
- **语义步骤（≤5）**：
  1. **定位并修复**：读 0212 `task-T08-sync-offline.md`、`sync-offline/development-report.md`、第二次编译日志；只修 `sync_offline_top.v` 两处非法位置连接（按 named `.src_busy()` 等方式），不改功能/常数/接口；记录 before/after diff。
  2. **编译 + 自检 TB**：ModelSim 编译（本轮最多 2 次：首次 + 1 次有新证据纠正；旧 2 次历史另计）；跑正例（角色顺序、24 ms/8 帧、NACK/timeout/单路缺失/reset/恢复、SOF 配对/回绕），`vlog Errors:0`、`vsim` 明确 PASS、mismatch=0。
  3. **负对照**：至少 1 个隔离副本上的有效负对照，产生预期失败/拒绝且无编译错误；不改生产 TB/oracle 原文件。
  4. **小顶 G2**：一次 TD 综合（≤25 min）：50 MHz/187.5 MHz×2 三时钟约束落点、Routed、WNS/TNS≥0、CDC 边界/复位/资源；不生成可下载声明；TD 占用/失败即记录 `blocked`，不重试、不等待。
  5. **冻结**：B01 699 项改前/改后 0 漂移；T08 manifest（RTL/TB/小顶/SDC/日志/命令/负对照/restore 缺口）；`dev-result.md`、`lessons.md`；停止修改后 `ready_for_test`。
- **综合测试三维对象**：functional=独立重编译/重跑正例+负对照（同一 DB）、复核 24 ms/8 帧/角色/CDC；engineering=小顶 G2 报告/DB/时钟/CDC/资源/约束、manifest 复算、B01 699 项 0 漂移；system=未接 top/未下载/零 Flash/文件范围/回退、旧 T08 26 项不冒充新 PASS。
- **必要 G 层**：G0/G1/G2；G3/G4 not_applicable（离线未接硬件）；G5 not_applicable（不推送）。
- **工具/超时**：读/搜 60 s；单 TB ≤5 min；整组 ≤15 min；TD 小顶 ≤25 min×1；无生产构建、无下载。
- **停止/回退**：改活动 top/I2C/生产约束/需扩范围 → `SCOPE_CLARIFICATION` blocked；2 次编译仍失败/2 循环无进展 → `LIMIT_REACHED/NO_PROGRESS`；回退=丢弃本轮新增/修改（不批量删除，按单文件或保留 worktree-only），旧 26 项 manifest 保身份。
- **预算（冻结）**：dev **≤40 min / ≤35 calls**（理由：修 2 处语法+TB 编写/调试+一次小顶 G2；旧同类 30 calls 上限不够覆盖编译失败后的有效纠正）；tester **≤30 min / ≤30 calls**（独立重编译/复跑+小顶报告核对，不重建）。

### 4.3 批内顺序与互斥

- 一个 batch 开发**顺序**执行：先 T02（preflight→下载→清单；下载后板交给用户，开发不再等），再 T08（离线；可与用户点击并行，但不得与 SRAM 下载并发抢 TD/USB）。
- T02 下载占用 ≤3 min（含 180 s 上限），T08 TD 小顶在下载结束后启动；ModelSim 仿真可在任意时刻，但与 TD 小顶不并发同一 license 资源（罕见冲突一次即 `blocked`）。
- 不合并 T08 小顶与 B01 生产构建（不同 top、生产 6/6 已封顶）；不重复 T09 仿真。

## 5. 综合测试安排（一个综合测试者覆盖全批）

- 新建**一个**与开发独立的综合测试者，覆盖 T02 + T08；每任务每轮一份报告，`dimension=integrated`；首行唯一判定。
- 报告路径：本 run `test-reports/T02.codex-singleA-board-r0-integrated.md`、`test-reports/T08.codex-sync-offline-r0-integrated.md`。
- T02：`ready_for_test` 且有完整现场证据才做 G3；仅有 preload/清单 → `blocked/awaiting_hardware`，核 preload/哈希/清单，不重下载、不判 PASS。若本轮用户两样本返回，按 guide §1.2 独立核验。
- T08：独立重编译/重跑 TB 正例+负对照（同一 DB），核小顶 G2 报告/DB/时钟/CDC/资源、manifest 0 不一致、B01 699 项 0 漂移；不重建生产、不下载。
- 测试者预算：**≤50 min / ≤45 calls**（理由：两任务一份会话；T08 独立重编译+复跑约占 30 min，T02 证据/哈希约 10 min）。只写 test-reports 与隔离副本；不改候选/现场原文。
- 修复：同任务 FAIL 且 blocked 为空 → 续**真实原开发**，再续**真实原测试**；round1—3 最多三轮实际修复，逐任务分账；blocked/缺设备不计轮，交原规划备条件。

## 6. 统一阈值（冻结）

| 门槛 | 值 |
|---|---|
| T02 候选 | manifest 699 项 SHA `c7a40897…d757`；bit `b68c6e18…f9bf`；CWC `b28e3d4e…4ce`；BID `4dcdc263…8f33`；任一不符不下载 |
| T02 下载 | `read_device_id=PH1P100`；单次 ≤180 s；rc=0 + `PRG-2014 Chip validation success: PH1P100`；100%；失败不重试 |
| T02 G3 | 两不同 seq；`words=648192`、`len=2592768`、四 ok=1、`err=0`、`flags[31]=1`、`flags[3:0]=15`、`flags[15:8]=0`、`fault=0`、pass_count 推进；`cl_identity=0x434c0101`、`algo_identity=0x414c0101`；几何/ROI 依据；一次内部 abort+恢复；短窗 ≥20 s |
| T02 安全 | 仅 SRAM；零 Flash/efuse/SPI/svf；零 CLI 读回；零 GUI 自动化；不覆盖 0207 活跃窗口 |
| T08 G1 | vlog Errors:0；vsim 明确 PASS；正例 mismatch=0；负对照预期失败且无编译错误；单 TB ≤5 min、组 ≤15 min |
| T08 G2 | Routed；setup/hold WNS≥0、TNS=0；50/187.5/187.5 MHz 三时钟 0 违例；CDC 边界/约束/复位逐项；资源≤器件；无宽泛豁免 |
| 身份/保护 | B01 699 项改前/改后 0 漂移；T08 新文件全部 SHA 可复算；旧 26 项/旧报告只读；无 commit/push |
| manifest | 每包 0 不一致；报告绑定当前 manifest；不拼不同输入 PASS |

## 7. 预算、停止与回退

- 规划自我预算：≤15 min/≤30 calls；实际读取见 `input-index.md` 所列，未改旧 run。
- 开发（batch 两会话角色，顺序）：T02 ≤20 min/≤20 calls；T08 ≤40 min/≤35 calls；合计 ≤60 min/≤55 calls。tester ≤50 min/≤45 calls。角色不得自行扩预算。
- 命令 deadline：读/搜 60 s；局部静态/单 TB 5 min；TD 小顶 25 min；SRAM 180 s；样本组 ≤5 min。
- 停止：缺工具/设备/授权/资料 → blocked；连续 2 循环无新证据/产物 → NO_PROGRESS；预算到限 → LIMIT_REACHED；T08 两次编译失败/小顶时序不收敛 → blocked，不改门槛。
- 回退：T02 旧 bit/CWC 或断电（用户执行）；T08 丢弃本轮改动/保留 worktree-only，旧 26 项 manifest 不覆盖；不批量删除。

## 8. 用户配合与“回来点两下”清单

- 本轮不需要用户先回答现场问题：开发做机械检查；板不在/窗口占用就返回 `awaiting_hardware/awaiting_board_window`，清单照样冻结。
- 下载成功后，用户回来只需：打开 paired `current.cwc` → ChipWatcher Watch 16 字/40 探针 → Instant Trigger ×2（间隔 ≥20 s）→ 保存原值+截图+时间戳；若板已断电，清单第一步给一次 SRAM 重下（≈30–40 s）。
- 清单必须写明：候选 SHA、当前板载、期望值、异常即停、回退旧候选；不得写“点两下就 PASS”。

## 9. 后续主题（≤3，不自动续做）

1. 用户回传两样本 → T02 G3 判定/补样（最多总 3 组）、几何/物理相位与坏帧因果；G4 后放。
2. T08 真实双路主从/电气/曝光同步板验与接入活动 top（父 T08，需另轮/硬件条件）。
3. G4 长稳/性能优化、PCIe/RK/压缩集成（用户明确后另轮；本轮不做）。

---

## 10. v1.1 收尾更新（2026-10-19 22:0x）

本轮综合测试已返回，按固定分支收尾，不改本计划 §0—§9 的历史冻结内容；本节为当前状态覆盖。

### 10.1 最终判定

| 任务 | verdict | 处置 | 实际修复轮 |
|---|---|---|---|
| `T02.codex-singleA-board` | **FAIL（blocked/awaiting_hardware，DEVICE_MISSING）** | 不派修复轮、不自动重试；保持 awaiting_hardware；G3=not_run；清单升级 v2 | 0/3 |
| `T08.codex-sync-offline` | **PASS（round0）** | 收束为 done_offline；G0/G1/G2 PASS；真实双路同步另轮 | 0/3 |

- T02：B01 四身份 MATCH、699 项 0 漂移、租约/日志/清单可复核；两次只读 `read_device_id` 60 s 超时、0 B 日志、无 `PH1P100`、0 download、0 样本。报告 `test-reports/T02.codex-singleA-board-r0-integrated.md`；问题对象 `T02.codex-singleA-board:DEVICE_MISSING:read_device_id_timeout`，证据 `board/sram/20261019_213000/probe-result.json`。
- T08：独立重编译/复跑正例 `SYNC_OFFLINE_PASS mismatch=0`、负对照 `SYNC_FAIL tx=5` 预期拒绝；G2 Routed、三时钟 50/187.512/187.512 MHz、SWNS 0.294/STNS 0、HWNS 0.043/HTNS 0、资源在器件内；manifest `3e513628…8775` 35/35；B01 699 项 0 漂移。报告 `test-reports/T08.codex-sync-offline-r0-integrated.md`。
- T06/T09 B01 r0 PASS 作为既成输入复用，未第 7 次构建、未重跑算法仿真。

### 10.2 上板清单 v2

- 最终入口 `board/t02/board-checklist-final.md`：补 `cl_words`/`cl_len` 前缀、16 字/40 探针链接（0212 `probe-reference.md`）、收尾状态“NOT READY TO CLICK”、物理检查/新授权下载/两样本/异常/回退。
- v1 `board/t02/board-checklist.md`（SHA `41a70391…b2ed`）保持冻结、不覆盖；v2 为重述+修正，不改候选/期望值/门槛。

### 10.3 过程偏差（登记，不改变判定/不扩预算）

- T02 dev 26/20 calls（+6；batch 总计 ≤55）；T08 正例编译 3/2、TD 会话 4/1（第 3 次正例由 21:39:29 外部改写 TB 触发；最终 G2 来自第 4 次，未改 RTL/时序/约束门槛）；T02 manifest `generated_at` 与 mtime 差异（哈希一致）；T02 清单 v1 两处文档缺陷（v2 已修正）。
- 后续恢复须重新冻结有限预算，不沿用本轮超用值；旧 0212/T08 计数不重置。

### 10.4 并行线

- 板窗租约已执行：本 run 未覆盖 0207；0207 `preload-record-v4` 为 `PRG-8000`、0 download、awaiting；本 run 0 download、租约释放。
- T08 纯离线，不等待板窗/点击，未与 SRAM 下载并发；互不堵塞安排已执行。

### 10.5 本轮不做/未测

- T02 G3/几何/物理相位/坏帧恢复/短窗全部未测；父 T02/T06/T11 未 done；G4 后放。
- T08 真实双路曝光同步、活动 top 接入、电气/寄存器读回未测；无 bit/CWC；G3/G4 N/A。
- 全局 `workflow/tasks.json` 本 run protected，未更新；以本 run `final-summary.md`/`handoff.md` 为准。

### 10.6 v1.2 恢复（2026-10-19 22:xx，用户换线后新输入）

- 用户真实新增输入：`user-input-01.md`（换线后再试+其他排查）。据此冻结 `recovery-plan-01.md`，只恢复 `T02.codex-singleA-board`；T08 已 PASS 不重开。
- 关键新证据：0207 线 21:56 已用 `D:/downlaod/bin/bw_commands_prompt.exe` + `read_id_v5/download_v5.bwcmd` 成功 `PH1P100`/`PRG-2014`/30.04 s；此前 T02 超时与 5555 重复 hwserver/非 FTDI 实例一致，更像工具/服务器层问题。历史 2 次 read ID 超时、0 download 保留，不重置。
- 当前板载=0207 候选 `5B67A8F5…`（未采样）；T02 候选 `b68c6e18…` 下载会覆盖。Phase A 只读 ID 可做；Phase B download 仅在用户明确 A（0207 先采样）或 B（授权覆盖）后另派/续接，一次 ≤180 s，不重试。
- 角色：续真实原 batch 开发 `ses_eaba8efb1ffe7iWxJYBv40A2fQ`；不是修复轮，T02 round0 仍未完成，G3 仍 not_run。Phase A ≤12 calls/15 min、0 download；Phase B ≤12 calls/10 min。详见 `recovery-plan-01.md`、`question-01.md`、`dispatch.json`。
