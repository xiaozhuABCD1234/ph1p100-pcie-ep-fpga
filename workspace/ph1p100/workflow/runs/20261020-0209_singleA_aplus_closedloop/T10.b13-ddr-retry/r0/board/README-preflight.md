# T10.b13-ddr-retry r0 — 板级预检（b13b 更新）

日期：2026-10-25 22:00（b13b 续跑）；主机 `LAPTOP-HE7N8DN4`。

## FTDI / COM 枚举（本轮实测，未打开串口前）

```
FTDI_PRESENT=1
USB\VID_0403&PID_6042&MI_01  USB Serial Converter B   OK
USB\VID_0403&PID_6042&MI_00  USB-JTAG Cable           OK
USB\VID_0403&PID_6042        USB Composite Device     OK
SERIALCOMM: COM8 = \Device\VCP0   （COM3/COM4 为蓝牙串口）
```

- 首轮预检时 COM8 未枚举；b13b 续跑时 COM8 **已重新枚举**，因此按用户要求执行了
  "先 1 次 SRAM 下载，成功后再开 COM8 150 s"。

## 本轮板级动作

- `downloads=1`（JTAG/SRAM，`B13_DL_OK`，184 s）
- `COM8_capture=150 s`（36,150 B，150 个合法 v5 包，bad_xor=0）
- A1U1 帧 0；`cap=0`、`timeout/retry/giveup=0`；相机 `pix_beats=0`、`line_rises=0`
- 结论与证据：见 `board-run-b13b.md`、`captures/`、`log/`
- 未做第二次下载、未写 Flash、未 PCIe/RK。

## 注意

本次下载的 `r0/td/a1_board.bit` 产生于 1080p 孤儿字修复**之前**，不是最终候选；
最终 RTL 需要下一轮重新综合/布线/1 bitgen + 1 CWC 后再下载（见 `result-r0.md` §3/§6）。
