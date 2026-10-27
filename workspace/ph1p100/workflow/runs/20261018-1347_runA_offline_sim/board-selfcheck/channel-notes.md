# channel-notes.md — T11.runA-board-selfcheck（B1 通道结论，供 B2/KIT 复用）

- run: `20261018-1347_runA_offline_sim`；任务: `T11.runA-board-selfcheck`
- 操作者: fpga-dev 子会话（opencode，session id 未向子代理暴露）；宿主: Windows PC（用户 czz）
- 采样时间: 2026-10-18 14:04–14:13（上海时区）

## 1. 串口/物理通道实况（本机枚举，证据 `logs/01-env-probe.txt`）

- FTDI USB-JTAG Cable `USB\VID_0403&PID_6042\AL0B99F427`（复合设备，Serial=AL0B99F427）：
  - MI_00 = `USB-JTAG Cable`，service=**WINUSB**（hwserver/bw 可打开；JTAG 下载与器件 ID 走此通道）
  - MI_01 = `USB Serial Converter B`，service=FTDIBUS → 本机唯一 FTDI VCP = **COM8**（可正常打开）
- **COM3/COM4 = 蓝牙链接标准串口（Microsoft BTHENUM），非板卡**；先前 input-index 登记“FTDI 双通道 → COM3/COM4”在本机实况不成立，正确端口为 COM8（且 COM8 亦非可用命令通道，见下）。

## 2. UART 命令通道 = 不可用（架构性，非本次偶发）

证据 A（RTL，只读引用）: `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/ph1p_pcie_ep_top.v`
- L30 注释: “uart signals（rxd 让位给 MIPI 子卡的 cam_a_xclr_n，板上不再用串口接收）”
- L155: `wire w_uart_rxd_unused = 1'b1;`；L757: `pcie_uart` 例化 `.rx (w_uart_rxd_unused)`

证据 B（实测）: COM8 打开正常，115200/8-Odd-1/hex，只读探测命令 `46 45 44 43 42 41 00 00 40 90 00 00 00 00`（APB read PF0 Link Status，`doc/uart_cmd_file_pcie.txt` 第 1 条）
- 下载前（14:05:18 起 8 s窗口）: rx=0 字节（`logs/02-uart-probe-com8.txt`）
- 下载后（14:12:2x 起 8 s窗口）: rx=0 字节（`logs/05-sram-download-runa-retry.txt` 尾部）

结论: **本 bit/本板不存在 UART 命令读通道**（EP top 将 uart rx 固定为 1，板上 rxd 让位 MIPI）。B2/KIT **不要**依赖 UART 读写寄存器/内存。

## 3. BW/JTAG = 可用（本包唯一机读通道）

- 工具组合（2026-10-17 同法验证过，本包再次成功）:
  - bw: `D:\downlaod\bin\bw_commands_prompt.exe`（TD 6.2.2；6.2.3 `D:\anlogic\TD_Release_2026.2\bin\bw_commands_prompt.exe` 备用）
  - hwserver: `D:\downlaod\bin\hwserver.exe`，先启参数 `-r -s 5555 -f 12 -v -w 5556 -i 0`
- 只读: `connect_cable -host_name 127.0.0.1:5555 -open` → `read_device_id` = **PH1P100** → `connect_cable -close`
- SRAM 下载: `download -bit <bit路径> -mode jtag -spd 7 -cable 0`（`-mode jtag` = PROGRAM SRAM，绝不写 Flash）
- 会话日志: `<脚本cwd>\log\bw_YYYY-MM-DD_HH-MM-SS.log(.logw)`

### 3.1 关键约束（本包踩坑→修正，务必沿用）

1. **bit 文件路径必须为 ASCII/英文**：中文路径 → `PRG-8000 ERROR: File path: ... invalid, please modify to correct English path`（`logs/04-sram-download-runa.txt`）。修正=复制到 `C:\Users\czz\AppData\Local\Temp\opencode\runa_b1\ph1p_pcie_integration.bit`（SHA 复核一致后下载）。
2. **bw 的命令行参数绝对路径会被破坏**（反斜杠被吞、中文乱码）：脚本文件一律用**相对路径**调用（先 `Push-Location` 到脚本目录）；脚本内的路径经**环境变量**（如 `$::env(RUNA_BIT)`）传入，避免脚本/参数中出现非 ASCII。
3. 下载成功判据（本机口径）: `PRG-2014 : Chip validation success: PH1P100` + 进度条 100% + `download` rc=0 + 时长 ~28–40 s；日志中 `Error @ mpsse.cpp:90 : usb_open() failed` 是 bw 自动拉起的第二 hwserver 实例提示，**不影响结果**（伴随成功日志出现）。
4. 失败重试仅在有新证据/参数纠正时进行（本包 retry1 = ASCII 路径修正，成功）。

## 4. 其它入口（本包未使用，供规划评估）

- bw 命令表存在 `JTAG_REG_ACCESS` / `JTAG_AXIS_APB_ACCESS`（字段语义未证实，可能含写操作，本包**不使用**、不盲试）；本候选无 CWC/调试核产物。
- RK PCIe 主机: 本轮不可用（驱动未编译）。若在场上板轮提供 PC/RK 主机或改接 UART rx，寄存器读路径方可成立。
- 禁止命令面（本包全程未出现）: `program_spi / erase_spi / program_efuse / read_flash / program_svf / *flash*` 等；Flash 决策属用户授权范围。
