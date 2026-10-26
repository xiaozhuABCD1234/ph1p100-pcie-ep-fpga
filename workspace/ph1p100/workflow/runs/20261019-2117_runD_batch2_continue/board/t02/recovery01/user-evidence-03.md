# 用户证据 03 + Phase A/B 结果（T02 recovery03）

时间：2026-10-19 23:09–23:16 +08:00｜run：`20261019-2117_runD_batch2_continue`｜任务：`T02.codex-singleA-board`

## 1. 用户原话与 PowerShell 输出（原样）

```text
PS C:\Users\czz> tasklist | findstr /i hwserver
hwserver.exe                 37440 Console                    1         20 K
hwserver.exe                 64540 Console                    1      9,972 K
PS C:\Users\czz> netstat -ano | findstr :5555
  TCP    0.0.0.0:5555           0.0.0.0:0              LISTENING       64540
PS C:\Users\czz> tasklist | findstr /i td.exe
td.exe                       45416 Console                    1     14,712 K
PS C:\Users\czz> 选 A：0207 采完，窗口给 T02 下载、
```

用户选择：**A**（0207 两样本已完成，窗口给 T02；允许覆盖板上 0207 候选）。

## 2. Server/进程只读证据

- 5555 唯一 LISTENING = **PID 64540**。
- 64540：`D:\downlaod\bin\hwserver.exe`，命令行 `hwserver.exe  -r -f 1 -s 5555`，启动 23:06:57，加载 `WinUSB.DLL`，端点 `0.0.0.0:5555 LISTEN`。
- 37440：旧残留（父 45596 已消失、无路径/命令行/端点/监听），未触碰、未杀。
- `td.exe` 仅 45416（00:59 启动），未触碰、未结束。
- FTDI PnP：`USB-JTAG Cable` / `VID_0403&PID_6042` / COM8，状态 OK。

## 3. Phase A（只读 ID，0 download）

- 第 1 次：23:10:13，wrapper 把 ASCII 暂存路径以反斜杠传给 `bw_commands_prompt`，工具把 `\t` 当转义，`couldn't read file`，0.249 s、未建立连接、无设备行。**这是工具路径参数错误，不是硬件失败**；日志 `board/sram/20261019_231013/`。
- 第 2 次（首次+1 有具体新证据纠正）：23:13:45，改为正斜杠路径；`connect` 0.0158 s → `read_device_id` **PH1P100** 0.0242 s → close 0.0019 s；rc=0、总 0.174 s；日志 `board/sram/20261019_231345/`。
- 历史 2 次 60 s 空日志超时（`board/sram/20261019_213000/`）保留，不重置。

## 4. Phase B（A 已授权，一次 SRAM 下载）

- 0207 条件核对：`board-samples-01.md`、`board-samples-02.md` 均存在；`T11.runC-board-checklist-r0-integrated.md` 首行 `### 判定：PASS`。用户 A 明确窗口给 T02。
- B01 复核：manifest `c7a40897…d757`（699 项）、bit `b68c6e18…f9bf`、CWC `b28e3d4e…4ce`、BID `4dcdc263…8f33`、probe `96eb210b…888a` 全部 MATCH。
- 0207 候选不同：bit `5B67A8F5…1D52`（现场 `compiled.bit` 直接哈希 MATCH）；CWC 以 v8 manifest 的 prestage 副本 `8DDA54D4…664F` 为准；现场 `D:/anlogic/runa_runC/20261019_192056/compiled.cwc` 直接哈希为 `2362a86e3b8720649757979e08cd6fca5ba9bee8732576cafce32f264c751755`（与 v6 文字不一致，疑为另存/时间戳变化；不用于 T02 判定）。
- ASCII 暂存：`C:\Users\czz\AppData\Local\Temp\opencode\t02_phaseb_20261019_231409\current.bit`（`b68c6e18…`）、`current.cwc`（`b28e3d4e…`）；只复制、不覆盖源。
- 下载：23:14:29，`bw_commands_prompt.exe` + `download_v6.bwcmd`，`download -bit …/current.bit -mode jtag -spd 7 -cable 0`；日志 29.426807 s，`PRG-2014 : Chip validation success: PH1P100`，进度条到 100%，随后 `read_device_id` 仍为 `PH1P100`，rc=0；日志 `board/sram/20261019_231429/`。
- 下载后复核：23:15:16 再跑一次只读 ID，`PH1P100`、0.202 s、rc=0；日志 `board/sram/20261019_231516/`。
- `usb_open() failed` 旁路提示出现（mpsse.cpp:90），与 0207 成功下载时相同，属 bw 自动拉起第二实例的提示，不单独判败；主 server 64540 全程唯一监听。

## 5. 计数/边界

- Phase A：**2 次 read_device_id**（1 次路径纠正 + 1 次成功）；本轮新增 download **0**。
- Phase B：**1 次 SRAM download**（成功，≤180 s，不重试）；下载后 **1 次**只读 ID。
- 0 Flash/efuse/SPI/svf、0 CLI readback、0 GUI 自动化、0 杀进程、0 commit/push、0 批量删除。
- 未覆盖 0207/B01/T02 冻结文件；0207 线只读引用。
- G3 仍 `not_run`：需用户按 `board-checklist-final.md` 点两次 Instant Trigger（≥20 s）并回传 16 字/40 探针原文；无样本不判 PASS。
