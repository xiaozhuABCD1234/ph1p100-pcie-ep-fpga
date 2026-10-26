# T02 开发结果 — `T02.codex-singleA-board`（runD batch2）

日期：2026-10-19 21:32 +08:00｜角色：fpga-dev（一开发顺序实现 T02→T08）｜状态：**awaiting_hardware**

## 1. 结论

本 run 完成了 B01 候选身份复算、板窗机械检查与**一次**只读 `read_device_id` 入口（含 1 次记录脚本纠正重试），但两次均在 60 s 内无任何输出/无 `PH1P100`。按预检门禁**未执行 SRAM download**（本轮 0 次），板上加载状态保持 unknown。返回 `awaiting_hardware`；不重试、不等待、不杀他人进程。T02 未闭环，G3=`not_run`，不得判 PASS。

## 2. 已做与证据

1. **候选复算（MATCH）**：manifest 699 项 `c7a40897…d757`；bit `b68c6e18…f9bf`；CWC `b28e3d4e…4ce`；BID `4dcdc263…8f33`；probe map `96eb210b…d888a`（40 探针/3 时钟域）。未重建、未重跑 T06/T09。
2. **读 0212 计划/清单/上次超时**：`t02-board-plan.md`、`two-capture-checklist.md`、`sram-execution.json`（20:59:46 启动，exit 1、timeout true、121.3 s、0 设备行、pass=false、load unknown）。历史 1 次 SRAM 超时保留，不重置。
3. **板窗机械检查**：无 `td_commands_prompt`/`run_td`/`run_build`/download 活跃；`td.exe` PID 45416、`hwserver.exe` PID 45596（5555）存活且未触碰。0207 最新 `preload-record-v4.md`：0 次 download、21:20 `PRG-8000`、`awaiting_user_gui`，未持有板窗、无“已预载未消费”。租约已写 `board/board-window-lease.json`，判定 `awaiting_hardware`，窗口释放、不阻塞 0207。
4. **只读探测**：`board/sram/20261019_213000/read_id.tcl`（connect→read_device_id→close，仅只读）；两次 60 s 超时、stdout/stderr 0 字节、无 device 行。第一次为记录脚本语法失败后的 `first + 1` 有证据纠正重试；无 download。证据 `probe-result.json`。
5. **清单冻结**：`board/t02/board-checklist.md`（候选绝对路径+SHA、当前板载、两次 Instant Trigger ≥20 s、16 字/40 探针原值+截图+时间戳、期望值、几何/ROI/PHASE、内部 abort+恢复、异常分流、回退旧 bit/CWC、G3 tier）。
6. **零漂移**：B01 manifest 前后同为 `c7a40897…`、699 项、0 漂移。零 Flash/efuse/SPI/svf、零 CLI 读回、零 GUI 自动化、零 commit/push。

## 3. 未做/未测

- 未执行 SRAM download（前置身份门禁未通过），因此没有新的板载候选、没有下载日志/PRG-2014、没有两样本。
- 未做 G3/G4；未接 PCIe/RK；未构建生产；未改任何生产树或 0212/0207 文件。

## 4. 阻塞与最小下一步

- `problem_id`: `T02.codex-singleA-board:DEVICE_MISSING:read_device_id_timeout`
- `reason_code`: `DEVICE_MISSING`；`new_information`: true（本 run 与 0207 均在同一时段无法取得 PH1P100；本 run 两次 60 s 空日志超时）
- 需要用户/现场：检查板电源与指示灯（DDR 校准）、USB/JTAG 线是否为板卡口并插稳、必要时换线/换口；保持原接线与传感器配置。
- 恢复输入：`workflow/runs/20261019-2117_runD_batch2_continue/board/t02/board-checklist.md` + `board/board-window-lease.json`；物理检查完成后由**新授权轮次**重跑机械检查、只读 `read_device_id`（≤60 s）与一次 ≤180 s SRAM 下载；仍禁止 Flash/CLI 读回/GUI 自动化。
- 回退：旧 bit `bfafdf97…`/CWC `8d2998b9…`（不自动执行）；断电/上电由用户按清单执行。

## 5. 预算与计数

- 历史累计：0212 线 SRAM 1 次（120 s 超时、0 样本），保留。
- 本轮新增：SRAM download **0 次**；只读 `read_device_id` 2 次（首次 + 1 次记录纠正）；未重试下载。
- 综合测试建议：可核身份/租约/清单/日志/0702 不覆盖与零漂移，但 **G3 必须记 `blocked/awaiting_hardware`**，不得 PASS。

## 6. 复测清单（如进入修复轮）

- 必测：候选四 SHA + 699 项；租约/0207 不覆盖；只读探测日志；清单语义/期望值/回退；G3 仍无样本则继续 blocked。
- 输入变化项：`board/t02/**`、`board/board-window-lease.json`、`board/sram/20261019_213000/**`。
- 未影响项：B01 699 项/G0–G2、T06/T09 报告、0207 候选与证据（只读引用，不合并）。
