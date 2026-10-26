# T10.b13-ddr-retry r0 — 板级运行记录（b13b，2026-10-25 22:01）

## 0. 预检

- `Get-PnpDevice -PresentOnly`：`USB\VID_0403&PID_6042` 三个节点均为 OK（USB Serial Converter B / USB-JTAG Cable / Composite）。
- `SERIALCOMM`：`COM8` 重新枚举（另 COM3/COM4 为蓝牙串口）。**COM8 在位**。
- 因此按用户要求：先 1 次 SRAM 下载，成功后才开 COM8。

## 1. 下载（1 次，JTAG/SRAM）

- 脚本：`r0/td/dl_b13.tcl`（复制到 TD 根目录执行；绝对 Windows 路径直接传给 `td_commands_prompt` 会被 Tcl 反斜杠替换吃掉，
  首轮失败未建立连接、0 下载；改为裸文件名 + cwd=T: 后成功）。
- 日志：`r0/board/log/download_b13.log`
  - `B13_DL_DEVICE=PH1P100`
  - `PRG-2014 : Chip validation success: PH1P100`
  - `B13_DL_OK mode=jtag(sram) bit=.../r0/td/a1_board.bit`（184 s）
- 下载后 `connect_cable -close`，停 hwserver，再开 COM8。

## 2. COM8 采集（150 s，115200 8N1，只读）

- 脚本：`r0/board/capture_com8.py`；`r0/board/parse_status_v5.py`
- 原始：`r0/board/captures/com8_150s.bin`（36,150 B，SHA256 见 stats）
- 解析：`r0/board/captures/status_v5.txt` / `.json`

| 项 | 结果 |
|---|---|
| v5 状态包 | **150 个**，241 B，`bad_xor=0`（全部通过结构校验） |
| A1U1 帧 | **0**（`magic_a1u1=0`） |
| cap_frames | 0 |
| raw_pub / enc / exported | 0 / 0 / 0 |
| timeout / retry / giveup / stale_guard | 0 / 0 / 0 / 0 |
| A1 读通路 ar / r | 0 / 0 |
| 桥 br0 | 41（ddr_rdy=1, ar_pending=0, wstate=0） |

相机前端字段（#9..#23，150 包内）：

- `cam_clk_tgl_inc` 9202→515637、`cam_pkt_tgl_inc` 6525→370117（MIPI 时钟/包活动存在）
- `cam_vs_tgl_inc` 0→1、`frame_rises` 0→1、`frame_falls` 0→1
- **`cam_pix_beats` 恒 0、`cam_line_rises` 恒 0** → CSI-2 没有解出任何有效视频行
- `cam_phystat=494`、`cam_sysstat=3869`（与 b12 会话的 750/3869 不同）

## 3. 结论

- 板级 **不是本包的丢 R 故障**：camera 前端没有产生任何有效像素/行（cap=0），A1 读通路从未启动，
  `timeout/retry/giveup` 全 0。按 dev-plan §7.3 的判定："exported=0 且 timeout 不增长 → 不是本包目标故障，
  保留 v5 证据交规划，不猜修"。
- 与 b12 r1 同一相机前端（b12 实测 4,470 帧）对比，本会话 MIPI 只看到时钟/包 toggle、没有 line/pixel；
  属于相机链路/传感器会话问题（或 USB 重新枚举后的上电时序），需要用户侧检查相机连接/供电后重采。
- **并且**：本次下载的 `a1_board.bit` 是在 1080p 孤儿字修复**之前**的综合/布线结果（见 result-r0 §3），
  因此即使相机正常，该 bit 也不能作为最终重试候选。板级证据仅证明：v5 包/UART/下载链路可用。
- 未做第二次下载、未写 Flash、未重采。
