# recovery-plan-01.md — T02 板卡“无法识别”有界恢复（2026-10-19）

原规划者冻结；触发=用户新输入 `user-input-01.md`：“我换了根线，但是感觉这个好像无法识别有可能是其他问题，再做尝试和其他排查”。本文件只覆盖 `T02.codex-singleA-board` 的恢复；T08 已 PASS r0，不重开。

## 1. 读完证据后的判断

### 1.1 关键新事实（只读交叉核对）

- **0207 线在 21:55–21:56 已用用户控制台成功识别并下载**：`read_id_v5.bwcmd` 两次输出 `PH1P100`；`download_v5.bwcmd` 在 21:56:53 完成，`PRG-2014 : Chip validation success: PH1P100`、100%、30.037585 s；下载后 `read_device_id=PH1P100`。证据：0207 `user-input-05.md`、`preload-record-v6.md`、`D:\anlogic\runa_runC\20261019_192056\{read_id_v5.bwcmd,download_v5.bwcmd}`。
- **0207 根因诊断**：21:48 的只读探测曾报 `usb_open() failed` + `PRG-8000 transfer failed`，原因是 5555 端口同时有两个 `hwserver` 监听（PID 45596 非 FTDI 实例与 PID 74620 持 FTDI 实例），会话落在非 FTDI 实例；用户关闭/清理后，21:55 起同一 `.bwcmd` 路径成功。证据：0207 `preload-record-v5.md` §4—§5。
- **本 run 上轮 T02 失败方式**：21:28/21:29 两次 `bw.exe read_id.tcl` 60 s 超时、stdout/stderr 均 0 B、无 `PH1P100`；脚本使用 `connect_cable -host_name 127.0.0.1:5555 -usr_args {-r -s 5555 -f 12 -v -w 5556 -i 0} -open`。当时 `td.exe` 45416、`hwserver.exe` 45596（5555）存活；0207 v4 同时间段为 `PRG-8000`。证据：`board/sram/20261019_213000/{probe-result.json,read_id.tcl}`、`board/board-window-lease.json`。
- **0212 历史 120 s 下载超时**：20:59:46 启动，121.3 s、exit 1、0 device lines、无成功标记、load unknown；与上述同时间段工具/服务器层问题一致。证据：0212 `board/t02/sram-execution.json`、`question-sram-timeout.md`。

### 1.2 结论（诊断假设，不冒充已证）

“无法识别”**更像工具/服务器实例层问题，而不是板卡或线缆必然损坏**：

1. 用户换线后，0207 控制台路径在同一块板上成功识别并下载，证明板卡供电/JTAG/USB/线缆至少在该路径下可用。
2. 上轮 T02 的 `bw.exe + Tcl -usr_args` 路径与 0207 成功的 `bw_commands_prompt.exe v5.bwcmd`（无 `-usr_args`、正斜杠、单 FTDI server）不同；且当时存在重复 hwserver / 非 FTDI 实例。
3. 但**尚未用 T02 自己的绑定日志**取得 `PH1P100`；0207 的成功不能直接作为 T02 的 G3/G0 证据，只能作为诊断依据。必须先做一次 T02 绑定的只读 ID。

### 1.3 当前板载冲突（必须先解决）

- 0207 v6 明确：**当前板载=0207 候选 `5B67A8F5…1D52`**，21:56 下载成功，尚未采样，“可以点了”。
- T02 要下载的是**另一个候选** `b68c6e18…f9bf`（B01 699 项）。任何 T02 SRAM 下载都会覆盖 0207 当前候选，使 0207 的采样窗口失效。
- 因此：**只读 ID/排查可以先做；T02 download 必须等用户明确选择窗口归属**，不得静默覆盖。

## 2. 冻结的恢复顺序

### Phase A — 只读排查（本次可执行；≤12 calls / ≤15 min）

1. **身份/证据复核**：B01 699 项 `c7a40897…d757`、bit `b68c6e18…f9bf`、CWC `b28e3d4e…4ce`、BID `4dcdc263…8f33`、probe map `96eb210b…888a`；读 0207 v6/v5、`user-input-05.md`、当前 0207 `board-checklist/dev-result.md`（判断是否已有两样本）。
2. **进程/端口/工具层**（只读）：
   - `Get-Process hwserver,td`、`netstat -ano | findstr :5555`、必要时 `wmic process get ProcessId,CommandLine` 只看命令行；记录每个 hwserver 的启动时间/命令行/是否持 FTDI。
   - 若 5555 有 **两个** hwserver 监听：**不运行 ID 探测**，不杀进程；返回 `NEEDS_USER_SERVER_CLEANUP`，给用户逐条关闭“非 FTDI 那个”的步骤（保留控制台打印 `Open device vid=0x0403 pid=0x6042` 的实例；不结束 `td.exe` 45416；不结束 74620/37440 中持 FTDI 者）。
   - 确认成功工具路径存在：`D:\downlaod\bin\bw_commands_prompt.exe`（BW Release_2026.1_SP2，0207 成功路径）；记录版本/banner。若不存在，记录并停，不猜替代路径。
3. **T02 绑定只读 ID**：在**本 run**新建 `board/t02/recovery01/read_id_v6.bwcmd`（纯 ASCII、CRLF、正斜杠；内容=`connect_cable -host_name 127.0.0.1:5555 -open` / `read_device_id` / `connect_cable -close`），用成功工具路径执行，deadline ≤60 s，owned PID tree；输出日志写到本 run `board/sram/<ts>/`。
   - 判据：stdout 含 `PH1P100` 且 rc=0；记录工具版本、server PID/命令行、FTDI VID/PID、时间、耗时。
   - 失败：仅当有**具体新证据/参数纠正**（例如确认并清理了重复 server、确认工具路径/BW 版本差异）才允许第 2 次；否则停。历史 2 次超时不重置，本次新增次数单独记账。
4. **分层结论**：
   - 得到 `PH1P100` → 证明“板卡可识别、T02 工具路径已修复”；**仍不下载**，读 0207 是否已有两样本：
     - 0207 已采样/已让出 → 可进入 Phase B（需用户明确“窗口给 T02”）。
     - 0207 未采样 → 返回 `awaiting_user_window`，附 A/B/C 选项；不覆盖。
   - 仍未得到 `PH1P100` → 记录是否 `usb_open failed`/PRG-8000/空日志；只读检查 PnP/USB VID/PID、驱动、`td.exe` 是否独占、cable/channel；返回 `blocked`，给用户具体物理/工具步骤，不下载。
5. **不动作**：0 download、0 Flash/efuse/SPI/svf、0 CLI readback、0 GUI 自动化、0 杀他人进程、0 commit/push；只写本 run `board/t02/recovery01/**`、`board/sram/<ts>/**`、`board/board-window-lease.json`。

### Phase B — 条件下载（仅用户明确 A/B 后另派/续接；≤12 calls / ≤10 min）

前置（全部满足）：
- Phase A 已取得 T02 绑定 `PH1P100`；
- 用户明确选择：A=0207 两样本已完成并让出窗口；或 B=授权覆盖 0207 当前候选（0207 需以后重下）；
- 5555 仅一个持 FTDI 的 hwserver；`td.exe` GUI 未被杀/未被自动化；
- 新租约写入候选 SHA、进程/server 快照、0207 状态/用户选择。

执行：
1. 复核 bit/CWC/BID/manifest SHA 与 0207 当前板载状态；确认要覆盖/已释放。
2. 使用 `D:\downlaod\bin\bw_commands_prompt.exe`，在本 run 新建 `download_v6.bwcmd`（纯 ASCII、CRLF、正斜杠；`connect_cable -host_name 127.0.0.1:5555 -open` / `download -bit <本run绝对路径/current.bit> -mode jtag -spd 7 -cable 0` / `read_device_id` / `close`）；**一次**，≤180 s，owned PID tree。
3. 成功判据：`PRG-2014 Chip validation success: PH1P100` + 进度 100% + 下载后 `read_device_id=PH1P100` + rc=0；失败/超时/PRG-8000/PRG-2014 不成功 → 停、不重试、保存日志，返回 `awaiting_hardware`。
4. 成功后更新 `board/t02/board-checklist-final.md` 的“当前板载=本 run 候选/可以点了”状态（追加记录或 v3），冻结 recovery manifest；返回 `awaiting_user_gui`，不空等点击。

### Phase C — 两样本与 G3（用户点击后另派/续接）

- 按 `board/t02/board-checklist-final.md` §4—§5：两次 Instant Trigger ≥20 s、两个不同 seq、16 字/40 探针、`cl_words/cl_len`、几何/PHASE=3、内部 abort 恢复；仍不判 PASS，交 tester r0。

## 3. 诊断层面与每层判据

| 层面 | 只读诊断 | 判据/分流 | 需用户动作 |
|---|---|---|---|
| 物理/电源 | 电源灯、DDR 校准、单 A、USB/JTAG 口 | 灯不亮/校准未完成→停 | 是（用户） |
| 线缆/USB | 已换线；PnP VID/PID `0x0403/0x6042`；设备管理器 | 无 FTDI 设备→换口/线/驱动 | 是 |
| server 实例 | 5555 监听 PID、命令行、是否持 FTDI | 两个实例/非 FTDI→停，清理后再试 | 是（用户关多余窗口） |
| 工具/版本 | `D:\downlaod\bin\bw_commands_prompt.exe` vs TD `bw.exe`；banner | 路径不存在/版本不符→记录，不猜 | 否（只读） |
| 命令/脚本 | `.bwcmd` 无 `-usr_args`、正斜杠、无 BOM、CRLF | 含反斜杠/`-usr_args`→修正后再试一次 | 否 |
| 板卡/JTAG | `read_device_id` 是否 `PH1P100` | 是→板卡可识别；否→记录错误文本/空日志 | 可能 |
| 候选/下载 | 仅身份通过后 | 不把“识别失败”归因候选；不下载 | 否 |

## 4. 计数、预算与停止

- **历史保留**：0212 SRAM 1 次 120 s 超时；本 run T02 read_device_id 2 次 60 s 超时、0 download；T08 历史 2 次编译/3 次正例/4 次 TD 不因本轮变化。
- **本轮新增**：Phase A read_device_id **≤2 次**（首次 + 1 次仅有具体新证据的纠正）；download 0 次。Phase B（另派）download **1 次**，≤180 s，不重试。
- **预算**：Phase A dev ≤12 calls/15 min；Phase B dev ≤12 calls/10 min。不是修复轮；T02 round0 仍未完成，G3 仍 not_run。旧计数不重置、不伪装成 round1。
- **停止**：重复 server 未清理/PH1P100 未取得/工具路径不存在/用户未选择窗口 → 停，返回 `NEEDS_USER_SERVER_CLEANUP`/`awaiting_user_window`/`blocked`，不空等、不自动重试；连续 2 循环无新证据 → 停。
- **回退**：不覆盖 0207；不写 Flash；如需恢复旧 bit，按清单由用户执行；不自动电源循环。

## 5. 测试安排

- Phase A 只读诊断**不派 tester**（无候选/无样本；G3 仍 blocked）。开发返回 `awaiting_user_window`/`NEEDS_USER_SERVER_CLEANUP`/`blocked` 时，主转用户，不新建测试者。
- Phase B 下载成功后仍不判 G3；等两样本回传、T02 manifest 冻结后，才由原 batch 测试者续 `T02.codex-singleA-board` r0 integrated（同任务同测试者；若原 tester 会话失效，按文件恢复并登记映射）。
- 不得用 0207 的 PH1P100/样本替代 T02 证据；不得把“板卡可识别”写成 T02 G3 PASS。

## 6. 用户选择（另见 `question-01.md`）

- **A（推荐）**：先完成 0207 两样本（板载已是 0207 候选，点两下即可），再让出窗口给 T02；T02 现在先做只读 ID/排查。
- **B**：明确授权 T02 立即覆盖 0207 当前候选；0207 当前采样窗口丢失，需以后重下。
- **C**：只做只读 ID/排查，暂不下载。
- 若发现 5555 有两个 hwserver：请用户关闭**非 FTDI** 的那个窗口/实例；保留控制台显示 `Open device vid=0x0403 pid=0x6042` 的实例；不要结束 `td.exe` 45416。
