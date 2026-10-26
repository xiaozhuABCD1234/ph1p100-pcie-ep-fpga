# user-gui-checklist.md — 现场用户逐步操作清单（ChipWatcher 读回 9 字）

前提（已完成）：debug 位流已通过 `-mode jtag` **仅 SRAM** 下载成功（PRG-2014、100%、rc=0、28.85 s）；板仍上电。**请勿断电**（断电会清除 SRAM 位流）。

## 0. 先恢复 USB 连接（2026-10-18 更新，CLI 报 PRG-9505 后新增）

1. 把连接板子的 **USB 线拔下，等 5–10 秒再插回**同一 USB 口。
2. 打开任务管理器，确认没有残留的 `hwserver.exe`（如有，结束它）；确认没有其它 TD/BW 进程占用线缆。
3. 再按下面 A 打开 TD。若 TD 仍报 USB/线缆错误，换一个 USB 口重试一次；仍失败就把错误原文原样回报（不要反复重装/改设置）。

## A. 打开 TD 2026.2

1. 打开 TD（`D:\anlogic\TD_Release_2026.2\bin\td.exe` 或开始菜单 Anlogic TD）。
2. 若 TD 提示 **线缆/设备被占用**（例如 `usb_open() failed`、`port 5555 in use`）：用任务管理器结束 **hwserver.exe（若存在；本会话曾为 PID 30988）**，再在 TD 里重新连接。结束它不影响板上位流。

## B. ChipWatcher 打开 CWC

3. TD 欢迎页 → **Tools → ChipWatcher**（若无 Tools 菜单，用 Flow 栏的 ChipWatcher 图标）。
4. 在 ChipWatcher 窗口点打开/浏览，选择 **CWC 文件**：
   `...\workflow\runs\20261018-1631_runA_fpga_side_readchannel\debug-fix\prj\ph1p_pcie_integration_Runs\phy_1\cw\compiled.cwc`
   （SHA256 `FA24E25830FEFE882EDB3B4D9AB18DE8FD39598A9822231B8622C9A0C73F22BB`，81,063 B）
   - 若中文路径导致报错（如 PRG-8000 / 路径无效），改用 ASCII 副本：
     CWC `C:\Users\czz\AppData\Local\Temp\runa_p3\compiled_debug.cwc`，
     Bit `C:\Users\czz\AppData\Local\Temp\runa_p3\ph1p_pcie_integration_debug.bit`。
5. 确认 **Bit File** 指向同源位流：
   `...\phy_1\ph1p_pcie_integration.bit`（SHA256 `2385CDEDAE1D9985687360AF77341183517E34CB18BE9CAD0229291593411873`，5,224,027 B）。
   - 若 TD 在 Watch 时询问是否下载位流：可以允许，但必须是**同一个 bit 文件/SHA**；记录对话框原文。
   - **绝不**选择 Flash/Program Flash/efuse/SPI 相关选项；若提示写 Flash → 取消。
6. 点 **Watch**。
7. 实例列表选 **`auto_created_cwc1`**（9 view nodes / 288 trigger + 288 data nets，时钟 `tl_clk_user`）。

## C. 加入 9 个信号

8. 点 **Add Signals**，展开 `auto_created_cwc1`，勾选以下 **9 个 32-bit 整字节点**（按名字；若树中同名多份，选实例内那一份）：
   `dbg_bank_word0`、`dbg_bank_word1`、`dbg_bank_word2`、`dbg_bank_word3`、`dbg_bank_word4`、`dbg_bank_word5`、`dbg_bank_word6`、`dbg_bank_word7`、`dbg_bank_word8`
9. 触发条件留空（不做复杂触发）；采样方式选 **Instant Trigger**。

## D. 采两个样本（间隔 ≥10 s）

10. 点一次 **Instant Trigger**，等波形/Value 列表出现数据。
11. Value 列表切到 **Hex**，逐个抄下 9 个字（8 位十六进制，原样，不要换算成十进制）。
12. **间隔 ≥10 s**（看表计时，例如 22:35:10 → 22:35:25）再点一次 **Instant Trigger**，抄第二组 9 字。
13. 若报 **code mismatch / 设备不识别 / Idle、Triggered=0 / 无波形**：停止重试（最多再点 1 次 Instant Trigger），把界面原文与截图保留，原样回报；**不要**重综合、重烧、改设置或换 CWC。

## E. 预期值（用于自检，不符也请原样回报）

| 字 | 期望 |
|---|---|
| word0 | `50434946`（"FICP"） |
| word1 | `31414B52`（"RKA1"） |
| word2 | `00010000`（v1.0） |
| word3 | DDR seq，应 ≥1，两个样本间可能增长 |
| word4 | DDR base，非零，低 7 位=0（128 B 对齐） |
| word5 | DDR len = 2,592,768 = `00279000` |
| word6 | CSI 诊断 `{good,bad,hdr_err,crc_err}` 原值（两样本 good 应增长） |
| word7 | `{last_lines,last_wc}` 原值 |
| word8 | CTRL 读回：bit0=1、bit5=1、bit4=0、bit6..8=0（高位应为 0） |

## F. 回报格式（照此原样回，勿估计/勿润色）

```
样本1 时间=HH:MM:SS
word0=0x________ word1=0x________ word2=0x________
word3=0x________ word4=0x________ word5=0x________
word6=0x________ word7=0x________ word8=0x________
样本2 时间=HH:MM:SS
word0=0x________ ... word8=0x________
异常/界面原文：（如有，原样贴）
```

回报后：保持板通电即可；如需恢复原状，断电 10 s 上电（清除 SRAM），或重下旧 bit（由后续轮执行）。
