# T02 recovery03 lessons（2026-10-19）

## 根因/触发/修正

1. **`bw_commands_prompt` 把反斜杠当转义**：wrapper 首次把 `C:\Users\...\t02_readid_v6\read_id_v6.bwcmd` 原样传入，日志出现 `C:Usersczz...opencode<TAB>02_readid_v6` → `couldn't read file`，0.249 s、未连接。修正：命令行参数用 `.as_posix()`（正斜杠），`.bwcmd` 内部路径也用正斜杠。这是本次 Phase A 首次失败的唯一原因，不是硬件/线缆。
2. **判 server 看“唯一 5555 listener”而不是进程数**：现场同时有 37440（无 FTDI/无端点/无 listener 的旧残留）与 64540（`D:\downlaod\bin\hwserver.exe -r -f 1 -s 5555`，WinUSB，唯一 LISTENING）。不要杀 37440；只要 64540 持 FTDI 且唯一监听即可探测。用户关闭多余 TD 窗口后环境变干净。
3. **A 流程可一次闭环**：用户明确 A 且 0207 有 `board-samples-01/02` + T11 r0 PASS → 先只读 ID `PH1P100`，再复制 bit/CWC 到 ASCII 暂存、一次 `download -mode jtag`（29.43 s，`PRG-2014`，100%，rc=0），再只读 ID 复核 `PH1P100`。全程 0 Flash/0 CLI readback/0 GUI 自动化。
4. **`usb_open() failed` 不单独判败**：成功下载日志里仍出现 `mpsse.cpp:90`，是 bw 自动拉起第二实例的旁路提示；判据是 `PRG-2014` + 100% + 下载后 `PH1P100` + rc=0。
5. **0207 回退 CWC 以 prestage 哈希为准**：v6 文字写 `8DDA54D4…`，现场 `compiled.cwc` 直接哈希为 `2362a86e…`（疑另存/时间戳变化）。回退时用 v8 manifest 的 prestage 副本，不以文字代替哈希；T02 自己的 CWC `b28e3d4e…` 已 MATCH。
6. **证据分层**：Phase A 失败日志（`board/sram/20261019_231013/`）保留为诊断；成功日志 `20261019_231345`/`20261019_231429`/`20261019_231516` 分列；历史 2 次 60 s 超时不重置。

## 验证入口

- `board/sram/20261019_231345/{read_id_v6.log,result.json}`（Phase A `PH1P100`）
- `board/sram/20261019_231429/{download_v6.log,result.json}`（下载 `PRG-2014`/29.43 s）
- `board/sram/20261019_231516/{read_id_v6.log,result.json}`（下载后 `PH1P100`）
- `board/t02/recovery01/{lease-recovery03.json,manifest-recovery03.json,verification-recovery03.txt}`
- `board/t02/board-checklist-final.md`

## 下次最小动作

用户按 `board-checklist-final.md` 点 T1/T2（≥20 s），回传 16 字/40 探针原文；无样本不判 G3 PASS，不重下。
