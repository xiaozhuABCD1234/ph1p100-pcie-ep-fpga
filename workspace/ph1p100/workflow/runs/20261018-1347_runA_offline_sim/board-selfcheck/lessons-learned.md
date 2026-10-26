# lessons-learned.md — T11.runA-board-selfcheck（B1）

1. **bw 下载要求 bit 路径为 ASCII/英文**（本包实测）: 中文路径 → `PRG-8000 ERROR: File path: ... invalid, please modify to correct English path`（未发生任何有效写操作）。修正=复制到纯 ASCII 路径（SHA256 复核一致后）再下载；源文件保持只读。最小复现: `logs/04-sram-download-runa.txt`。
2. **bw_commands_prompt.exe 的命令行参数不可携带绝对路径/非 ASCII**（反斜杠被吞、中文乱码，脚本找不到/路径无效）。修正=脚本用**相对路径**调用 + `Push-Location` 到脚本目录；脚本内路径经**环境变量**传入。最小复现: `logs/03`（首跑失败）→ `scratch/sram_download_runa.tcl`（成功形态）。
3. **本 bit/本板 UART 无命令读通道（架构性）**: `rtl/ep_side/ph1p_pcie_ep_top.v` L155/L757 将 uart rx 固定 1'b1（板上 rxd 让位 MIPI）。COM8 探测 2 次 0 字节。凡依赖 UART 命令/寄存器读的计划必须先核 RTL rx 连接，否则改为 JTAG/主机/CWC 路径。
4. **串口枚举陷阱**: 本机 COM3/COM4 是蓝牙标准串口（Microsoft BTHENUM），真实板卡 FTDI 端口是 COM8（MI_01, FTDIBUS）；`VID_0403/PID_6042` 复合设备上 MI_00=WinUSB 供 hwserver/JTAG。按“取高号口”旧登记会走错端口。
5. **可复跑的板级组合（已验证两次）**: `D:\downlaod\bin\hwserver.exe -r -s 5555 -f 12 -v -w 5556 -i 0`（预启）+ `D:\downlaod\bin\bw_commands_prompt.exe <相对脚本>`（TD 6.2.2）；成功判据=`PRG-2014: PH1P100` + 进度 100% + rc=0 + 28–40 s；`Error @ mpsse.cpp:90 : usb_open() failed` 为第二实例提示，属正常伴随行，勿误判失败。
6. **WinUSB 绑定是前提**: MI_00 若被系统更新回退为 FTDIBUS 会导致 `PRG-9505 USB device open error`；恢复入口 `D:\TD\JTAG工具\UsbDriverTool`（用户手动，管理员）。本包开始时绑定=WINUSB（正常）。
7. **测量工具进程卫生**: bw 自动拉起的第二 hwserver 会以 usb_open 失败退出；本角色显式预启的 hwserver 在会话末已停止（残留 0），避免长期占用设备。
