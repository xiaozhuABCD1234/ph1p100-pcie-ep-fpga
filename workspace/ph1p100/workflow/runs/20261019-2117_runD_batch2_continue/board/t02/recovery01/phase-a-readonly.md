# T02 Phase A 只读排查记录（recovery01）

- run：`20261019-2117_runD_batch2_continue`｜task：`T02.codex-singleA-board`｜时间：2026-10-19 22:15 +08:00
- 状态：**NEEDS_USER_SERVER_CLEANUP**（按 dispatch server 门禁停止；**本轮 0 次 read_device_id、0 次 download**）
- 性质：T02 外部 blocked 后的用户新输入触发的只读排查；不是修复轮，round0 仍未完成，G3 仍 `not_run`；旧计数不重置。

## 1. B01 身份复核（只读，MATCH）

| 项 | SHA256 | 大小 |
|---|---|---|
| manifest（699 项） | `c7a40897166467f2beafb096701dba9cf836e1007d77ae03d90009d06f80d757` | 255465 |
| current.bit | `b68c6e183e97eb0d465db77078f5049feca3a947fac51f99633621dd99b3f9bf` | 5224034 |
| current.cwc | `b28e3d4ee476731b118da0b12c3bad8dcca1dadfbd9b7ae4dc418c4d225a74ce` | 312109 |
| current.bid | `4dcdc26382f6b49e7ed9b95a40a1d57c05191c0130050812a74b853c16b38f33` | 188792 |
| probe-map.json | `96eb210bb0c55eed110b2a35a8ae0d3ccd3d8823c3d4286a635f9f9dd46d888a` | 238857（40 探针） |

未重建、未重跑 T06/T09；生产 6/6 仍为上限。

## 2. 工具/进程/端口/FTDI（只读快照）

- 成功工具路径：`D:\downlaod\bin\bw_commands_prompt.exe` **存在**，14,752,536 B，SHA256 `5a6aae58ce0c66a5e38fe9194b96789d08b9df9da029a92252b3146f5fc7c0c4`；该 exe 无版本资源（FileVersion 空），0207 成功日志中的 server banner 为 `Anlogic hwserver v1.0c (g1deb3940) Build 2024-12-09`。
- `netstat -ano | findstr :5555`：**无任何监听/连接**。
- `hwserver.exe`：仅 PID **37440**（启动 21:48:47；父进程 45596 已不存在；ExecutablePath/CommandLine 为空；无 FTDI/USB/mpsse 模块；无 TCP 端点）。判断：**不是可用的持 FTDI server**，是旧 server 退出后的残留实例。
- `td.exe`：PID **45416**（00:59:16，旧 GUI，**未触碰**）与 PID **23384**（21:59:27，新 GUI，用户新开，未触碰）。两者都不应被本角色结束。
- FTDI PnP：`USB-JTAG Cable`、`USB Serial Converter B`、`USB Serial Port (COM8)`，`USB\VID_0403&PID_6042\AL0B99F427`，状态均 **OK**。物理层至少被 Windows 正常枚举。

## 3. 为什么停

dispatch 明确：5555 监听/hwserver 未持 FTDI 时停，返回 `NEEDS_USER_SERVER_CLEANUP`，不探测。当前事实满足该停止条件：

1. 5555 **没有** listener，`connect_cable -host_name 127.0.0.1:5555 -open` 没有可用 server；
2. 唯一残留 `hwserver` 37440 不持 FTDI、无端点；
3. 存在第二个 `td.exe` 23384，可能占用/竞争 JTAG；
4. 若此时直接运行 `bw_commands_prompt`，可能再次自动拉起第二个 server，重演 21:48 的 `usb_open failed`/`PRG-8000` 场景。

本轮**未**执行 `read_device_id`，未新建/执行 `read_id_v6.bwcmd`；没有产生新的 USB/PRG 错误文本。历史 2 次 60 s 空日志超时（`board/sram/20261019_213000/`）保留，单独计旧账。

## 4. 0207 并行线状态（只读）

- `preload-record-v6.md`：21:56 用户控制台路径下载成功，`PRG-2014 Chip validation success: PH1P100`、100%、30.04 s；板载=0207 候选 `5B67A8F5…1D52`。
- 其后已出现 `board-samples-01.md`、`board-samples-02.md`、`test-reports/T11.runC-board-checklist-r0-integrated.md`、`candidate-manifest-v8.json`：0207 已完成 A/B/C/D 多次采样并有 r0 报告。**0207 采样窗口大概率已完成**，但板上仍是其候选；T02 未下载、未覆盖。
- 仍需用户明确窗口归属（A/B），不能由开发自行判定“已让出”。

## 5. 请用户执行的清理步骤（按顺序）

1. **不要结束 `td.exe` PID 45416**（旧 GUI）。
2. 若 PID **23384** 的 TD 只是你刚打开用于“看看能否识别”的窗口，请**关闭该新 TD 实例**（它可能占用 JTAG/USB）。
3. 结束残留 `hwserver` PID **37440**（无窗口、父进程 45596 已不存在）：在普通/管理员命令提示符执行
   `taskkill /PID 37440 /F`
   （本角色未执行，留给你操作）。
4. 只启动**一个**持 FTDI 的 hwserver 控制台（沿用 0207 成功路径），确认它打印
   `Open device vid=0x0403 pid=0x6042`，并监听 5555。
5. 在命令提示符核对：
   - `tasklist | findstr /i hwserver` → 只应有一个 PID；
   - `netstat -ano | findstr :5555` → 只应有一个 `LISTENING` PID，且与上一步 hwserver PID 一致。
6. 完成后告诉主“server 已清理/唯一 5555 监听”，主再续 Phase A；届时只跑一次 `read_id_v6.bwcmd`（≤60 s，**仍不下载**）。

## 6. 用户窗口选择（0207 采样已完成，仍需明确）

- **A（推荐）**：确认 0207 两样本已完成并让出窗口；T02 在 server 清理 + 只读 `PH1P100` 成功后，经新授权再执行一次 SRAM 下载。
- **B**：明确授权 T02 立即覆盖 0207 当前候选；0207 采样窗口作废（需以后重下）。
- **C**：只做只读排查，暂不下载；等现场/窗口确认。

## 7. 安全与计数

- 本轮新增：`read_device_id` **0 次**、download **0 次**、Flash/efuse/SPI/svf **0**、CLI readback **0**、GUI 自动化 **0**、杀进程 **0**、commit/push **0**、批量删除 **0**。
- 旧计数保留：0212 SRAM 1 次 120 s 超时；本 run T02 read_device_id 2 次 60 s 超时；T08 不受影响。
- 未覆盖 0207/B01/T02 既有冻结件；仅新增本 recovery01 记录。
