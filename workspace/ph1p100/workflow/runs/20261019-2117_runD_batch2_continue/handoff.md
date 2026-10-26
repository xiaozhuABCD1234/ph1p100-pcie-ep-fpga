# handoff.md — 20261019-2117_runD_batch2_continue（收尾）

状态：**finished（T08 PASS r0；T02 最终 FAIL/partial：functional/engineering PASS、system PARTIAL、G3=partial，按 B 收尾；无后续自动派发）**。
日期：2026-10-19 22:0x +08:00｜原规划者｜宿主 OpenCode｜batch=2（T02+T08）｜正式包 2｜两层。

## 1. 接手先读

- `final-summary.md`（判定矩阵/统计/偏差/边界）
- `user-summary.md`（用户短总结，主原样转发）
- `dev-plan.md`（v1 + 文末 v1.1 收尾更新）
- `input-index.md`
- `board/t02/board-checklist-final.md`（v2，最终上板入口；v1 为冻结证据）
- `test-reports/T02.codex-singleA-board-r0-integrated.md`（FAIL/blocked）
- `test-reports/T08.codex-sync-offline-r0-integrated.md`（PASS）

## 2. 当前真实状态

| 任务 | 状态 | 关键身份 |
|---|---|---|
| T02.codex-singleA-board | **FAIL（blocked，DEVICE_MISSING）**；G3 not_run；0 download/0 样本；不派修复轮 | B01 manifest `c7a40897…d757`（699）；bit `b68c6e18…f9bf`；CWC `b28e3d4e…4ce`；BID `4dcdc263…8f33`；T02 manifest `485b2346…4598` |
| T08.codex-sync-offline | **PASS r0**；G0/G1/G2；实际修复 0 | manifest `3e513628…8775`（35/35）；TB `dd03c079…09c1`；G2 TD `td-work4`；B01 699 项 0 漂移 |
| T06/T09 B01 | PASS r0（既成输入） | 699 项 `c7a40897…d757`；生产 6/6；无第 7 次 |
| 0207 并行 Track A | awaiting_user_gui；`preload-record-v4` 为 PRG-8000、0 download | 候选 `5B67A8F5…`/CWC `8DDA54D4…`；本 run 未覆盖 |

- 板上加载状态：**unknown**（本 run 未 download）；`td.exe` 45416、`hwserver.exe` 45596（5555）当时存活；租约 `board/board-window-lease.json` 已释放。
- 用户操作入口：`user-summary.md` + `board/t02/board-checklist-final.md`。**现在不能点 ChipWatcher**；先物理检查，再由新授权轮次下载。

## 3. 本 run 与 0207 的互不堵塞

- 写树：本 run T08 只写 0212 生产树的 T08 新文件；T02 不写生产树；0207 只写 `wt0207`；两线候选/证据不合并。
- 板窗：本 run 下载前读取 0207 最新 preload/dev-result；本次发现 0207 未持窗（0 download、PRG-8000、awaiting），本 run 写租约后只读探测；未取得器件即停、0 download、租约释放。**未覆盖 0207，也未让其等待本 run。**
- T08 纯离线（ModelSim+独立小顶 TD），不等待板窗/点击；未与 SRAM 下载并发。
- 结论：互不堵塞安排已执行；后续仍按该租约规则，不杀进程、不互等。

## 4. 精确恢复指令（仅示例，尚未授权执行）

```text
/fpga-orchestrator 恢复：C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-2117_runD_batch2_continue；本轮目标：先按 user-summary/清单做现场物理检查；由新的明确授权轮次重做板窗机械检查+只读 read_device_id（≤60s）+一次≤180s SRAM download；成功后按 board-checklist-final.md 取两样本判 T02 G3；仍仅 SRAM、不写 Flash、不推送、不接 PCIe/RK。
```

- 恢复前必须由用户确认电源/USB/JTAG/单 A 现场；不能把“板子上电了”推定为 JTAG 可识别。
- 新轮次计数重新冻结（不沿用本轮 T02 26/20 超用值）；旧 0212 的 1 次下载超时、T08 2 次编译历史保留，不重置、不冒充。
- T08 已 PASS；若 canonical TB/RTL/G2 DB 任一变化，必须重新冻结并重跑受影响项，不得拼旧 PASS。

## 5. 板测恢复条件（T02）

1. 物理检查：电源/指示灯、DDR 校准完成、USB/JTAG 插在板卡口并插稳、必要时换线/换口；不改相机/电源/传感器表。
2. 机械检查：无活跃 `td_commands_prompt`/`run_td`/`run_build`/download；读 0207 最新记录；既有 `td`/`hwserver` 不杀。
3. 只读 `read_device_id`：≤60 s；必须得到 `PH1P100`；否则停，返回 awaiting_hardware，不 download。
4. 一次 SRAM download：≤180 s，`PRG-2014 Chip validation success: PH1P100` + 100%；失败不重试。
5. 用户两样本：`board-checklist-final.md` §4—§5；≥20 s、两个不同 seq、16 字/40 探针、cl_words/cl_len、几何/PHASE=3/内部 abort 恢复；没有两样本不判 G3 PASS。
6. 回退：旧 bit `bfafdf97…`/CWC `8d2998b9…`（只作入口，不自动执行）或断电；不写 Flash、不自动电源循环。

## 6. 保护与不要做

- 不覆盖：B01 699 项/bit/CWC/BID/DB/报告；0212 旧 run 既有文件；0207 run/wt0207；基线候选；本 run 的 T02 manifest/v1 清单/T08 manifest/报告/复跑证据。
- 不写：活动 top、`sim/compile_checked.f`、I2C/寄存器表、生产约束/IP/ADC、`workflow/tasks.json`（本 run protected，未更新全局板）、TD 安装目录。
- 禁止：commit/push、Flash/efuse/SPI/svf、PCIe/RK、GUI 自动化、批量删除、杀他人进程。
- G 层不要混：T08 离线 G1/G2 ≠ 真实双路同步；T02 preload/清单 ≠ G3；T02 G0/G1/G2 inherited PASS ≠ 板级闭环 done。

## 7. 过程偏差（已登记，不改变判定）

- T02 dev 26/20 calls（+6）；T08 正例编译 3/2、TD 4/1；T02 manifest `generated_at` 与 mtime 差异；T02 清单 v1 两处文档缺陷（v2 已修正）。详见 `final-summary.md` §7。后续预算重新冻结，不扩权。

---

## 8. 2026-10-19 22:xx 恢复更新（用户新输入：换线后再试+其他排查）

### 8.1 新证据（只读交叉核对）

- 用户换线后，**0207 线 21:55–21:56 已成功识别并下载**：`read_id_v5.bwcmd` 两次 `PH1P100`；`download_v5.bwcmd` 21:56:53 `PRG-2014 Chip validation success: PH1P100`、100%、30.037585 s；下载后 `read_device_id=PH1P100`。证据：0207 `user-input-05.md`、`preload-record-v6.md`、`D:/anlogic/runa_runC/20261019_192056/{read_id_v5.bwcmd,download_v5.bwcmd}`。
- 0207 v5：21:48 只读探测曾 `usb_open() failed`/`PRG-8000`，根因是 5555 同时有两个 hwserver（45596 非 FTDI；74620 持 FTDI），会话落在非 FTDI 实例；用户清理后成功。
- 本 run 上轮 T02 的 `bw.exe` + Tcl `-usr_args {...}` 探测两次 60 s 超时、0 B 日志；与重复 server/非 FTDI 实例一致，更像工具/服务器层问题，不证明板卡/线缆损坏。
- 0212 历史 120 s 下载超时、0 device lines，同时间段，同层问题；历史计数保留。

### 8.2 当前板载冲突

- **板上现为 0207 候选 `5B67A8F5…1D52`**（21:56 下载成功），0207 尚未采样、“可以点了”。
- T02 候选为 `b68c6e18…f9bf`；T02 download 会覆盖 0207 当前候选。**在用户明确 A/B 前不得覆盖。**
- 只读 `read_device_id` 可以先做，不影响 0207 候选。

### 8.3 本次恢复派发

- 计划：`recovery-plan-01.md`；问题：`question-01.md`；用户短总结：`user-summary-recovery.md`；`dispatch.json` 已改为 recovery/ready。
- 角色：**续真实原 batch 开发 sessionID `ses_eaba8efb1ffe7iWxJYBv40A2fQ`**（同 T02；不是修复轮，round0 仍未完成，G3 仍 not_run；不重置旧计数）。
- Phase A 只读排查（≤12 calls/15 min，**0 download**）：复核 B01 身份/699；读 0207 v6/v5/当前 sample 状态；检查 5555/进程/FTDI；用成功路径 `D:/downlaod/bin/bw_commands_prompt.exe` + 本 run `read_id_v6.bwcmd`（无 `-usr_args`、正斜杠）只读 ID ≤60 s；首次+1 次仅有具体新证据纠正。
- Phase A 得到 `PH1P100` 后仍**不下载**：读 0207 是否已采样；未采样→`awaiting_user_window` + A/B/C；已让出→等用户明确选择。仍失败→记录错误层并 blocked。
- Phase B（仅用户 A/B 后另派/续接）：一次 SRAM download ≤180 s，失败不重试；成功后更新清单/冻结 recovery manifest，返回 `awaiting_user_gui`。
- Phase C：用户两样本后，原 tester 续 T02 r0；无样本不判 G3 PASS。

### 8.4 用户选择（详见 question-01.md）

- **A（推荐）**：先完成 0207 两样本，再让窗口给 T02（互不堵塞）。
- **B**：明确授权 T02 立即覆盖 0207 候选下载；0207 本次窗口作废，需以后重下。
- **C**：只做只读 ID/排查，暂不下载。
- 若 5555 有两个 hwserver：用户关闭非 FTDI 实例，保留控制台显示 `Open device vid=0x0403 pid=0x6042` 的实例；不结束 `td.exe` 45416。

### 8.5 边界

- 仅 SRAM、不写 Flash、不推送、不接 PCIe/RK；禁止 GUI 自动化/批量删除/杀他人进程；不覆盖 0207、B01、0212 旧 run、T02/T08 冻结证据；`workflow/tasks.json` 仍 protected。
- 0207 的 `PH1P100`/样本不能作为 T02 G3 证据；T02 仍 `G3=not_run`。

---

## 9. 2026-10-20 00:xx T02 recovery01 判定与 recovery02 补证

### 9.1 判定（保留原样）

- 报告：`test-reports/T02.codex-singleA-board-r0-recovery01-integrated.md`；**verdict=FAIL（blocked，EVIDENCE_INSUFFICIENT）**，不是 DUT 实现失败。
- functional=**PARTIAL**（身份/长度/words/flags/fault/pass/writer_good/seq/source_good/algo complete/overflow/geometry/cl_base/dbg_mark 与冻结值或 RTL 语义相符；abort/recovery 与 RTL 语义相容，但缺原始事件级证据、ROI X/Y/SKIP/相位证据）；engineering=**PASS**（699/SHA/bit/CWC/BID/probe map 0 漂移；下载 rc=0/PRG-2014/100%/post PH1P100；samples-01 6/6）；system=**FAIL/blocked**（仅聊天截图主转录，无 CSV/原始导出、截图未落盘、操作者/接线/供电连续性未提供）；G3=**partial/blocked**；G4=not_run。
- `problem_id=T02.codex-singleA-board:REPRO_DETAIL:sample-provenance`；证据 `user-samples-01.md`、`board/t02/samples/sample-record.json`。
- **计数**：T02 r0-recovery01 FAIL/blocked **不计实现修复轮**，actual repair rounds 仍 **0**；T08 PASS r0 不受影响；T02/父任务未 done。

### 9.2 裁定：A（一次有界补证）

- 理由：六窗口字段与冻结身份/长度/计数趋势高度一致，功能语义有强证据；缺的是原始证据形式与操作条件，用户可低成本补齐；值得一次有界补证。若补证后仍 partial，再按 B 接受“转录+原图+RTL 语义”的 partial 边界收尾。
- 用户只需：把 6 张原图按 `user-action-samples.md` 命名存到 `board/t02/samples/T1/`、`T2/`；回三句话（操作者、接线/供电连续性、已存好）。**不重下载、不重拍、不改接线/电源。**
- 开发（续原 batch 开发 `ses_eaba8efb1ffe7iWxJYBv40A2fQ`，只登记/绑定）：核 6 文件存在/可读/SHA，逐张对应图1—图6，记录操作者/接线/供电；新建 `provenance-01.md` 与 `manifest-samples-02.json`（不覆盖旧 manifest/sample-record；补 BID 字段）；缺图/缺句→blocked 列缺项。≤8 calls/10 min。
- 测试者（原 T02 tester 续接；失效按文件恢复并登记映射）：出 `T02.codex-singleA-board-r0-recovery02-integrated.md`；只核新增证据与同候选/同 699；不重下载/不重拍；ROI X/Y/SKIP/PHASE 仍无直接证据则如实 partial，不因补图强行 PASS。≤15 calls/20 min。
- 若 recovery02 仍 partial：按 B 收尾，写清 partial、未通过项、证据限制、恢复入口；**不称 PASS**，不再自动补证。

### 9.3 当前板载/窗口

- 板上为 T02 候选 `b68c6e18…f9bf`（23:14 下载成功，29.43 s，PRG-2014，post PH1P100）；0207 候选已被覆盖，0207 需另轮重下。
- 两样本来自该板载会话（T1 23:50:29—23:51:59；T2 23:52:13—23:53:10；间隔 104/57/71 s）；原图待用户落盘。
- `dispatch.json` 当前 `status=needs_user_input`，`next_action=relay_to_user` 指向 `user-action-samples.md`；用户回传后续 dev 绑定 → tester recovery02。

---

## 10. 2026-10-20 00:xx T02 recovery02 判定与最后一次命名修正

### 10.1 判定（保留原样）

- 报告：`test-reports/T02.codex-singleA-board-r0-recovery02-integrated.md`；**verdict=FAIL（blocked，INPUT_CONFLICT + EVIDENCE_INSUFFICIENT）**，不是 DUT 实现失败。
- functional=**PARTIAL**：6 图数值与转录一致；T1 cwc1/cwc2/cwc3、T2 cwc1 全对；但 `T2_cwc2_dhi_...235228.png` 实际是 cwc3 TL/23:53:10，`T2_cwc3_tl_...235310.png` 实际是 cwc2 DHI/23:52:28，两图内容互换。
- engineering=**FAIL**：B01 699/SHA/bit/CWC/BID/probe map 0 漂移、下载成立、samples-02 19/19 哈希一致；但 samples-02 实例映射错误、`user_statement` 编码损坏、sample-record 仍写“未落盘/未提供”。
- system=**FAIL/blocked**：操作者未具名、接线/供电仅口述、无 CSV/原始导出；`PHASE=3` unknown。
- G3=**partial/blocked**；`problem_id=T02.codex-singleA-board:INPUT_CONFLICT:t2-cwc2-cwc3-image-swap`。
- **计数**：recovery01/02 均为证据轮，不计实现修复轮；actual repair rounds 仍 **0**；T08 PASS r0 不受影响；T02/父任务不 done。

### 10.2 裁定：A（最后一次有界修正）

- 用户只做：在 `board/t02/samples/T2/` 按 `user-action-rename.md` 三步互换两张 PNG 文件名；不重拍/不重下载/不改接线/电源；回一句。
- 开发（续 `ses_eaba8efb1ffe7iWxJYBv40A2fQ`）：核 T2 最终两文件 SHA 映射（cwc2 DHI=`424e2f09…cf12`，cwc3 TL=`680bfc05…2b69`）；新建 `sample-record-v3.md/json` 与 `manifest-samples-03.json`，修正 `user_statement` 可读文本/陈旧字段；不覆盖旧文件；≤8 calls/10 min。
- 测试者：出 `T02.codex-singleA-board-r0-recovery03-integrated.md`；逐张 6/6；**命名修正不自动升 PASS**；操作者/接线/供电口述、无 CSV/事件条带、ROI X/Y/SKIP/PHASE 无直接证据 → G3 至多 **partial**；≤15 calls/20 min。
- **停止规则**：recovery03 若仍 partial，立即按 B 收尾（G3=partial/blocked，写清证据限制/恢复入口），不再要求补图、不再开 recovery04。

### 10.3 当前状态

- 板上为 T02 候选 `b68c6e18…f9bf`（23:14 下载成功）；0207 候选已被覆盖，0207 需另轮重下。
- `dispatch.json` 当前 `status=needs_user_input`，`next_action=relay_to_user` 指向 `user-action-rename.md`；用户回传后 dev 重冻 samples-03 → tester recovery03。
- 旧 `manifest-samples-01/02`、`sample-record.md/json`、recovery01/02 报告只读；不覆盖。

---

## 11. 2026-10-20 最终收尾（recovery03，按 B 接受 partial）

### 11.1 最终状态

- 报告：`test-reports/T02.codex-singleA-board-r0-recovery03-integrated.md`；T02 **verdict=FAIL（按规划 B 收尾）**：functional=**PASS**、engineering=**PASS**、system=**PARTIAL**、G3=**partial**、G4=not_run。
- 6/6 原图逐项匹配；T2 cwc2/cwc3 命名已修正；`manifest-samples-03.json` SHA `cba3256f…1468` 21/21；`sample-record` 编码/陈旧字段已修；B01 699/候选 0 漂移。
- **计数**：recovery01/02/03 均为证据轮，不计实现修复轮；actual repair rounds 仍 **0**；T08 PASS r0 不受影响；T02/父任务未 done。
- **不再要求用户补 CSV/截图/操作者；不再派 tester；本 run 结束。**

### 11.2 证据边界（为什么 G3 partial）

- 操作者未具名；接线/供电仅为用户口述“没变/没断”；无 CSV/原始导出/独立观察者/电源/接线记录。
- ROI 的 X0/Y0/SKIP37 与物理 Bayer 相位无直接探针；`source_geometry=089012DE` 是 4K 源几何（2192 行/4830 B），不是 ROI 尺寸。
- 因此不能把“同一未复位、同供电、同接线会话”提升为完全独立的系统证据；G3 只能 partial，不因命名修正/下载成功升 PASS。

### 11.3 板载与回退

- 板上为 T02 候选 `b68c6e18…f9bf`（SRAM **易失**；断电需重下）。
- 0207 候选已被 T02 覆盖；0207 若还要采，需另轮重下。
- 回退：旧 bit `bfafdf97…`/CWC `8d2998b9…`（基线 `debug-fix3`）；只作入口，不自动执行；不写 Flash、不自动电源循环。

### 11.4 未来入口

- 若未来要争取完整 G3 PASS：只能由用户明确新授权的新轮次补独立操作者/电源/接线记录、CSV/事件条带、ROI X/Y/SKIP 与物理相位直接证据；不得复用本轮 partial 冒充 PASS。
- `dispatch.json` 最终：`status=finished`、`needs_user_input=false`、`user_summary_path=user-summary.md`、`final_summary_path=final-summary.md`。
