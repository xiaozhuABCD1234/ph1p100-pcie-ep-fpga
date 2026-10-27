# T10.b13-ddr-retry r1 — 板级运行记录（2026-10-25 23:1x）

## 0. 预检

- `Get-PnpDevice -PresentOnly`：`USB\VID_0403&PID_6042` 三节点 OK（USB Serial Converter B / USB-JTAG Cable / Composite）。
- `SERIALCOMM`：**COM8 在位**（COM3/COM4 蓝牙）。
- 无残留 `hwserver`/`run.exe`；`T:` 由 `td_env.ps1 -TdDir r1/td -Force` 重映射到本轮目录。

## 1. 下载（1 次，JTAG/SRAM）

- 脚本：`r1/board/run_board_r1.ps1` → `r1/board/dl_b13.tcl`（复制到 `r1/td` 后以裸文件名执行，cwd=T:）。
- bit：`r1/td/a1_board.bit` SHA256 `aa7f75698529a56ae6ffe66d59ab1bc619b6f64a22733610b5359524272f6a5e`（最终 RTL 产物）。
- 日志 `r1/board/log/download_r1.log`：
  - `B13_DL_DEVICE=PH1P100`
  - `PRG-2014 : Chip validation success: PH1P100`
  - `B13_DL_OK mode=jtag(sram) bit=.../r1/td/a1_board.bit`（26.6 s）
- 下载后 `connect_cable -close`，停 hwserver，**再**开 COM8。

## 2. COM8 采集（150 s，115200 8N1，只读）

- `r1/board/capture_com8.py`；解析用冻结的 `r0/board/parse_status_v5.py`（v5 241 B / 59 字段）。
- 原始：`r1/board/captures/com8_150s.bin`（36,150 B，SHA256 `aa8963a814b70615acfdb56cc71b3cdf77e61230d3b99ae52b2823b3c4ad9a27`）
- 解析：`status_v5.txt` / `status_v5.json`，`wall_elapsed=150.276 s`

| 项 | 结果 |
|---|---|
| v5 状态包 | **150 个**，241 B，`bad_xor=0`，`noise=0` |
| A1U1 帧 | **0**（`magic_a1u1=0`） |
| cap_frames / raw_pub / enc_frames / exported | 0 / 0 / 0 / 0 |
| timeout / retry / giveup / stale_guard | 0 / 0 / 0 / 0 |
| ar / r / rlast / stale_r / rd_wait | 0 / 0 / 0 / 0 / 0 |
| br0 / src0 | 41 / 1024 |

相机字段（v5 #9..#23，首包→末包）：

```
cam0 clk_tgl_inc        12601 -> 519036
cam1 pkt_tgl_inc         6472 -> 257917
cam2 vs_tgl_inc             0 -> 22
cam3 pix_beats              0 -> 0        <-- 无有效像素
cam4 line_rises             0 -> 0        <-- 无有效行
cam5 frame_rises            0 -> 22
cam6 frame_falls            0 -> 22
cam7 last_frame_cycles      0 -> 16777215 (饱和)
cam10 crop_short            0 -> 22
cam12 phystat             494
cam13 sysstat            3869
```

## 3. 结论

- 相机前端只看到 MIPI 时钟/包 toggle 与 VS 跳变，**没有像素/行**（`pix_beats=0`、`line_rises=0`），
  因此 `cap_frames=0`，A1 读通路从未启动，`timeout/retry/giveup` 全 0 → **本包目标故障未被触发**。
- 与 r0（旧 bit）现象一致（r0：`pix_beats=0`，`frame_rises 0→1`；本轮：`pix_beats=0`，`frame_rises 0→22`），
  两个不同 bitstream 复现同一现象 → 相机/MIPI 链路或上电会话问题，不是 b13 重试改动。
- 按本轮指令：**停止**。未做第二次下载、未重采、未写 Flash。留证交规划/用户。
