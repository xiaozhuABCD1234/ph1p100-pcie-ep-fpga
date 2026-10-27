# dev-notes — T01-F（DDR1333 候选上板验证：SRAM 下载 / 硬件探测）

- 角色：fpga-dev（F）；日期：2026-10-17；run：`workflow/runs/20261017_182621_T01_board_and_tmst7700/`
- 状态：**已下载成功（SRAM，1333 主候选 bit，2026-10-17 19:12），待用户经 HDMI 观察（清单已启用）；1600ctl 对照待命**。全程未碰 Flash/NVM/OTP。（首跑失败与重试见 §9。）
- 会话/工作目录（新建，ASCII）：`D:\TD\work\csi2\_board_verify_20261017_T01F\`（脚本、探测输出、bw 会话日志均在其中的 `log\`）。

## 1. bit 定位 + SHA256 复核（下载前重算，2026-10-17 18:29）

| 候选 | 路径 | 大小 | SHA256（本机实测，完整） | 对照预期前缀 |
|---|---|---|---|---|
| 1333 主候选 | `D:\TD\work\csi2\prj\camera_rgb565_ddr1333_20261017_160741\camera_ddr_display.bit` | 5,224,029 B | `B7EF91CF499BA0899C49F0F4AD43752707CE372285AB9D85F052A16DEED150E3` | b7ef91cf… ✅ 一致 |
| 1600ctl 对照 | `D:\TD\work\csi2\prj\camera_rgb565_ddr1600ctl_20261017_160741\camera_ddr_display.bit` | 5,224,029 B | `1447B243B7402FA2F0AE0F3125A502EA4EC25CE03367C5D4F0F4C724C3686DA6` | 1447b243… ✅ 一致 |

（mtime：1333=17:15:35、ctl=17:17:06；两 bit 互异、尺寸与 E2 记录一致。SHA 为复核后重算值，无漂移。）

## 2. 硬件探测结果（只读）

- **下载线**：`USB\VID_0403&PID_6042\AL0B99F427`（复合设备；BusReportedDeviceDesc=**"USB-JTAG Cable"**；即 Anlogic FT2232H-based USB-JTAG 下载器，USB 端口实例 `8&f3ba9bd`，今日 16:35:59 插入/到齐）。
  - 通道 A（MI_00）：现绑 **FTDIBUS（FTDI VCP）**，对应 COM7；通道 B（MI_01）：FTDIBUS，COM8。COM7/COM8 均可正常打开（说明线体与驱动栈本身健康）。
  - 另有历史幽灵设备：Anlogic AL-Link Mini（`USB\VID_336C&PID_1002`，ANLOCYUSB/`anlocyusb.inf`），最后到齐 2026-09-26，**当前未连接**。
- **FPGA 器件 ID：尚未读取**（需要经下载器 JTAG 访问；预期下载时由 `PRG-2014 : Chip validation success: PH1P100` 给出——历史成功日志均为 PH1P100）。
- **bw CLI 命令面（无硬件副作用探测）**：可用 `connect_cable / download / read_device_id / read_sram / get_bit_info …`；**任何 Flash 系命令（program_spi/erase_spi/program_efuse 等）全程未使用，也不会使用**。bw 自建会话日志于 `<cwd>\log\bw_*.log`（本会话均在 `_board_verify_20261017_T01F\log\`）。
- **hwserver 能力（v1.0c，TD 6.2.3 与 D:\downlaod 两份同版）**：`-l/-L`（列适配器）、`-c A|B|C|D`（选 FTDI 通道）、默认 VID/PID=0x0403/0x6042（即本线）、`-b`（旧 AL-Link/anlocyusb 专用）。用法输出留档 `hwserver_h.err.txt`。

## 3. 实测阻塞现象（证据）

1. `hwserver.exe -l`（6.2.3 与 6.2.2 两份均测）：
   `List all adapters, count: 1` → `ftdi_usb_get_strings failed: -4 (libusb_open() failed)`。
   即 **libusb 能枚举到线，但打不开设备**（hwserver 内嵌 libusb-1.0.23，静态链接；打开需要 WinUSB/libusbK 类驱动绑定，而当前通道 A 绑的是 FTDI VCP）。
   日志/输出：`hwserver.out.txt`、`hwserver2.out.txt`。
2. `bw` 直连尝试（`connect_cable -allink` + `read_device_id`）→ `PRG-9505 ERROR: USB device open error`（同因）。输出：`probe_hw.out.txt`（`F4B4B098…`）。
3. 1333 下载脚本预检（一次性语法/通路验证，预期失败）：bw 自动拉起 hwserver → 同样 `usb_open() failed` → `PRG-8000 Hardware server start timed out` → `result=connect_failed`。输出：`sram_download_1333.preflight.out.txt`（`14B77053…`）。**未发生任何有效写操作**。

## 4. 根因（PnP 事件日志实证，`Microsoft-Windows-Kernel-PnP/Configuration`）

| 时间 | 事件 |
|---|---|
| 2026-10-07 14:52:25 | USB-JTAG Cable 首次到齐，父设备 usbccgp；MI_00/MI_01 先绑 FTDIBUS（VCP，COM7/8） |
| **2026-10-07 14:55:30** | **MI_00 被改绑 WinUSB**：`oem137.inf` = `winusb_device.inf_amd64_82d12a3e1ae76339`，类 GUID `{88bae032-…}`（USBDevice），Service=**WINUSB**，DriverVer=10/07/2026 |
| 2026-10-07 15:55 / 22:10 | bw 会话：`connect_cable -host_name 127.0.0.1:5555` 成功；22:10 **实际下载成功**（`PRG-2014: Chip validation success: PH1P100`）——即当时通道 A 是 WinUSB 绑定，hwserver 可开 |
| **2026-10-15 05:59:00** | **MI_00 被改回 FTDIBUS**（`oem135.inf`，2.12.36.20）——与当晨系统/驱动维护（USB 栈批量更新包 05:54–05:59）同一时段；WinUSB 包随后从驱动仓库被清（现 `winusb_device.inf_amd64_…` 不存在，`C:\Windows\INF\oem137.inf` 已被 Lenovo UDC 驱动复用） |

- 生成该 WinUSB 绑定的工具 **仍在本机**：`D:\TD\JTAG工具\UsbDriverTool\UsbDriverTool.exe`（Sysprogs UsbDriverTool；`WinUSB_Mini\winusb_device.inf` 模板即 10-07 落盘的 `winusb_device.inf` 同名同源；其临时证书 `CN=UsbDriverToolTemporaryCertificate`（thumbprint `58FE98AE…`）仍留存在 LocalMachine\Root + TrustedPublisher（签发于 10-07 22:55））。该工具夹内另有 FTDI CDM 2.12.06 WHQL（含 ftdibus/ftdiport inf-cat）与 WinUSB/libusb 模板、AndroidUsb 模板。
- 结论一句话：**不是线坏、不是板坏、不是 TD 装错——是 10-15 的驱动维护把 10-07 手工做的 WinUSB 绑定覆盖回了 FTDI VCP**，而 hwserver/bw 只能经 WinUSB 类绑定访问该线。任何下载路径（CLI 或 TD GUI 的下载对话框——同一个 hwserver）在当前绑定下都会同样失败。

## 5. 已就绪（修复绑定后即可执行；无需再改任何东西）

- 下载脚本（本会话目录）：
  - `sram_download_1333.tcl`（`763AFD9E…`）：定位/尺寸校验 → 连 127.0.0.1:5555（bw 会按 `-usr_args` 自动拉起 hwserver）→ `download -bit <1333bit> -mode jtag -spd 7 -cable 0`（**jtag=仅 SRAM**）→ 收尾标记 `T01F_1333_SRAM_DOWNLOAD_END result=ok`。
  - `sram_download_1600ctl.tcl`（`CF411304…`）：同流程，bit=1600ctl（第二步对照用，等调度通知）。
- 执行命令（将记录 tee 日志）：`bw_commands_prompt.exe ./sram_download_<x>.tcl`，cwd=`_board_verify_20261017_T01F`；bw=TD 6.2.3 版（与 bitgen 同版；6.2.2 版为备用）。若 bw 自动拉起 hwserver 失败则手工先起：`hwserver.exe -r -s 5555 -f 12 -v -w 5556 -i 0`。
- 回退备选（无需改驱动）：若用户手头有 **AL-Link Mini（VID_336C）**、可接板 JTAG 并插同一 USB 口，则 `hwserver -b` + 同 bw 流程亦可（其 anlocyusb 驱动已装；9-26 曾用过）。
- 约束执行记录：全程只读探测 + 仅 SRAM 意图；**未执行任何 flash/efuse/otp 命令**；未改候选/证据/脚本；未写 `D:\downlaod`；未动硬件连接。

## 6. 用户已执行的操作（**已完成**，2026-10-17 19:03）

> 完成注记：用户已按本节运行 UsbDriverTool；MI_00 已恢复为 **WINUSB**（新实例 `oem56.inf` = `winusb_device.inf`），19:04 `hwserver -l` 成功列出适配器（Serial `AL0B99F427`）。本节文字保留为记录。

> 背景（可原样转述）：10-15 的 Windows 驱动更新把这条 USB-JTAG Cable 的通道 A 驱动从 WinUSB 覆盖回了 FTDI 串口驱动，TD 的下载服务因此打不开线；需要用上次（10-07）同一个工具把它拨回 WinUSB。只需一次、约 1 分钟。

步骤（推荐路径 A）：
1. 打开文件夹 `D:\TD\JTAG工具\UsbDriverTool\`，**右键 `UsbDriverTool.exe` → 「以管理员身份运行」→ UAC 点「是」**。
2. 在窗口上方设备列表中选中条目 **`USB Serial Converter A`**（在其「Device ID」列确认含 `USB\VID_0403&PID_6042&MI_00`；**不要选 B / MI_01**）。
3. 在下方「Please select a driver to install」下拉选择 **`WinUSB`/`WinUSB_Mini`**（即 10-07 成功装过的那个；若下拉里两项都近似 WinUSB，优先与 `WinUSB_Mini` 目录对应的一项；如第一个报错再试另一个）。
4. 点按钮 **「Change driver type」（变更驱动类型）** 执行安装；若弹「Automatic driver installation failed… try manually?」选继续/手动；如有安装确认对话框选安装/继续。
5. 完成后窗口内该设备驱动状态应变为 WinUSB（COM7 会随之消失；COM8 不受影响）。**无需重启**。
6. 回来告知「已执行」——我方将立即继续：`hwserver -l` 复验（应能列出适配器）→ 自动下载 1333 bit（≤1 分钟）→ 转达观察清单。

回退/注意：
- 若不想用该工具：设备管理器把「USB Serial Converter A」卸载（勾选删除驱动）后扫描改硬件亦可拨回 FTDI（可逆操作）。
- 该绑定今后仍可能被 Windows 更新覆盖（本次即 10-15 事件重演）；再遇同样现象按同法恢复即可。
- 备选路径 B：接 AL-Link Mini 到板 JTAG（同 USB 口），通知后我方用 `hwserver -b` 流程（亦仅 SRAM）。

## 7. 观察清单（下载成功后原样转用户）

① 屏幕是否有实时图像（非黑屏/花纹）？② 颜色：白纸是否中性、红/蓝身份是否正确（G3 口径）？③ 稳定运行先 5–10 分钟（延长由用户决定，G4）；④ 任何异常（闪烁/撕裂/间歇黑屏/死机）？

## 8. 日志/证据清单（本会话，均在工作目录）

- `log/bw_2026-10-17_18-31-27.log(w)`、`log/bw_2026-10-17_18-31-38.log(w)`（探测）、`log/bw_2026-10-17_18-45-21.log(w)`（预检）——bw 自建会话日志（原始）。
- `probe_cmds.tcl/.out.txt`（命令面）、`probe_hw.tcl/.out.txt`（`READ_DEVICE_ID` 失败证据）、`hwserver.out/err.txt`、`hwserver2.out/err.txt`、`hwserver_h.out/err.txt`（用法）、`sram_download_1333(.preflight).out.txt`、两个下载脚本。
- PnP 事件与注册表/驱动仓库结论见 §4（可按需重查：`Get-WinEvent -LogName 'Microsoft-Windows-Kernel-PnP/Configuration'` + `Get-PnpDeviceProperty`）。

## 9. 上板执行记录（2026-10-17 19:03–19:12）

1. **绑定复验（19:04）**：MI_00 = WINUSB（`oem56.inf`=winusb_device.inf 新实例）；`hwserver -l` 输出 `Device Id: 0, Serial Number 'AL0B99F427'`（EXIT=0）——线可打开。证据：`hwserver_l_after_rebind.out.txt`。
2. **读器件 ID（19:05）**：`read_device_id` → **PH1P100**（`probe_device_id.out.txt`；bw 日志 19-05-02）。
3. **首跑 run1（19:05:12，bw=TD6.2.3 + 预启 hwserver）**：连接 OK 0.019s；`PRG-2014: PH1P100`；传输至 ~54.3s 失败——`PRG-8000 ERROR: transfer failed`（rc=1）；hwserver 侧大量 `usb bulk write failed` 后 `Assertion failed: cur_state==state, rbb.cpp:212` 崩溃；**设备在 19:05:54 发生一次重新枚举**（LastArrivalDate 更新；PnP Configuration 通道无对应事件）。异常点：下载阶段 bw 另起第二 hwserver 实例（设备被首实例独占故打不开）。日志：`sram_download_1333.run1.out.txt`、bw 19-05-12、`hwserver_run.out/err.txt`。
4. **重试 run2（19:11:44；仅单变量变更=换用 10-07 已验证的 6.2.2 组合 `D:\downlaod\bin\bw_commands_prompt.exe`+`hwserver.exe`）**：连接 OK 0.014s；`PRG-2014: PH1P100`；**进度条满、无影响结果的错误行（仅第二实例 usb_open 提示）、rc=0、28.4s**（与 10-07 成功 31.7s 同量级）；`T01F_1333_SRAM_DOWNLOAD_END result=ok`；收尾 close。**全程无设备重枚举**（LastArrivalDate 保持 19:05:54 不变）。日志：`sram_download_1333.run2.out.txt`、bw 19-11-44、`hwserver_622.*`（stdout 缓冲未落盘，不影响判定）。
5. **观察项**：CLI 方式日志无 `GUI-1001: Downloading succeeded!` 横幅（10-07 为 GUI 驱动会话；同 build 6.2.2.200067 的本地 CLI 会话均无此横幅）；按 rc=0+无影响结果的错误行+满进度+预期时长判为**工具层成功**，功能层正据=用户 HDMI 目视（清单启用）。
6. 后置复核：bit SHA 仍 `B7EF91CF…D150E3`；无残留进程；helper server 已关闭；全程 `-mode jtag`（SRAM），未触任何 Flash/EFUSE/OTP 命令；未写 `D:\downlaod`。
7. **用户观察（1333）**：黑屏（原话"貌似是黑屏呀"；工具层全绿）→ 触发本轮对照判别。
8. **1600ctl 对照下载（19:16:40，同 6.2.2 组合、单次）**：下载前 SHA 复核 `1447B243…86DA6` ✓；连接 OK 0.013s；`PRG-2014: PH1P100`；**rc=0、28.2s、满进度、无影响结果的错误行（仅第二实例 usb_open 提示）**；`T01F_1600CTL_SRAM_DOWNLOAD_END result=ok`；全程无设备重枚举（LastArrivalDate 保持 19:05:54）。日志：`sram_download_1600ctl.run.out.txt`、bw 19-16-40、`hwserver_622_ctl.*`。**当前板上 bit=1600ctl（SRAM 驻留）**；待用户观察（主调度转达）。
9. **用户观察反馈**：1600ctl 仍黑屏；LED：**D37 闪、D38 黑、D39 常亮、D40 常亮**（解读见 §10）。判别=排除 DDR 换芯因素，指向管线/环境侧。
10. **140836 环境对照（首跑 fail / 单次重试 ok）**：首跑 19:24:58——`PRG-8000 transfer failed`（rc=1、25.7s），期间设备再次中途重枚举（LastArrivalDate 19:25:16）+ hwserver `rbb.cpp:212` 断言 + usb bulk 洪流；**重试 19:27:05——rc=0、32.9s、满进度、无影响结果的错误行（仅第二实例 usb_open 提示）**，`T01F_140836_SRAM_DOWNLOAD_END result=ok`，全程无重枚举。日志：`sram_download_140836.run.out.txt` / `.run2.out.txt`、bw 19-24-58 / 19-27-05、`hwserver_622_140836*.out/err`。**当前板上 bit=140836**，待用户观察。
11. **COM8 遥测尝试（只读）**：115200、15s 零字节（`com8_telemetry_after_140836.txt`）——该物理接线是否引出 R17 UART 未证；未再重试。若后续需要，改走 ChipWatcher（JTAG）读分类计数。
12. **中途重枚举事件汇总（间歇）**：19:05:54（run1 1333-6.2.3）、19:25:16（140836 首跑）两次；1333-run2、1600ctl、140836-重试三次均无。原因未定位（重试即过的间歇 USB 事件）；不归因 DDR/候选/设计。
13. **用户观察（140836 环境对照）**：**出图**、灯= **D38 亮 + D39 黑**（正常签名）——**环境验证通过**（相机/显示/板卡全好；偏色=旧已知行为、用户明确不管）。**基线好态签名 = D37 闪 / D38 亮 / D39 灭 / D40 亮**。
14. **002820 本体下载（19:3x，同 6.2.2 组合、单次，首跑成功）**：下载前 SHA 复核 `4D591C31…DD8865` ✓；连接 OK 0.015s；`PRG-2014: PH1P100`；**rc=0、30.3s、满进度、无影响结果的错误行（仅第二实例 usb_open 提示）、无重枚举**；`T01F_002820_SRAM_DOWNLOAD_END result=ok`。日志：`sram_download_002820.run.out.txt`、bw 最新会话日志、`hwserver_622_002820.*`。**当前板上 bit=002820（原始本体，从未上板→本轮首验）**；待用户观察。
15. **分支计划（待命，各一句）**：①若 002820 出图 → 先做 002820↔1600ctl 只读构建差分（工具锚/脚本 SHA/native_* 记录/bit `get_bit_info` 与 STA 行），6.2.3 独有 TMST-7700 列第一嫌疑；②若 002820 也黑 → 整理 140836→002820 只读变更清单（WB 流水/裁决延拍/统计）与最可疑项，下一入口= ChipWatcher 在 002820（或 1333）读分类计数（good_frames/crc_errors/frame_timeouts 等）区分"相机无流 vs 帧被丢"。
16. **用户观察（002820 本体）：黑屏；D37/D38/D39 全灭、D40 亮**——**与 1333/1600ctl（D37 闪+D39 亮）签名不同**。解读：D37 灭 ⇒ `ddrphy_rdy=0`（DDR PHY 未就绪），**DDR 域逻辑整体处于复位**（D38/D39 灭属连带，不代表"错误未触发"）；D40 亮=50M 域配置流程照常。已交复核提示（30s 盯 D37）与备用断电重上电指令。
17. **002820 bit 家族（只读清点）**：`camera_ddr_display.bit`=**正式交付**（SHA `4D591C31…DD8865`，本次下载对象，尺寸 5,224,033 B）；`cw\compiled.bit` **与交付 bit 逐字节相同**（同 SHA）⇒ 交付 bit **自带调试核**；配套 `camera_ddr_display.cwc`（134,611 B；1282 个 MARK_DEBUG 节点）与 `camera_ddr_display_inst.bid`（104,896 B）；无其它 bit 变体。结论：本次下载 = 正式 bit ✓；ChipWatcher 可直接读当前位流（同 bit）。
18. **140836→002820 变更清单（只读）与嫌疑排序**：差异=①Bayer 相位 0→3 + WB 增益 R/B=2400/2062(Q10) + 黑电平 50；②"乘积后寄存一级"；③"显示帧信号与下游帧裁决同延后一拍"；④原始统计时序保持；⑤未用模块 `camera_ddr_capture_top.v` ROM 重定位（不进位流）。嫌疑排序（针对黑屏/新签名）：**(1) DDR 域未起本身**——间歇校准（重上电/重下或可恢复）vs 重摆放后 DDR I/O 时序边缘（002820 setup +0.000ns 贴边；140836 今日多次可起）；**(2) 裁决延拍**（唯一动过帧握手）；(3) WB 寄存；(4) 参数/统计（颜色/诊断性质，不致黑屏）。最小二分：先断电 10s 重上电+重下 002820（判间歇 vs 稳定复现）；若稳定复现，从 140836 出发只加"乘积寄存+裁决延拍"构建单变量候选，以"D37 是否起"立即二分。
19. **ChipWatcher 读取计划（002820，用户 GUI）**：关闭 BitWriter → `File→Close Project` → 欢迎页 `Work With a Tool→ChipWatcher` → 打开 `camera_rgb565_wb_20261015_002820\camera_ddr_display.cwc` → `Watch` → 选 **cwc1**（相机字节域）→ Add Signals 加 `u_camera/w_a_good_frames[31:0]`、`w_a_bad_frames`、`w_a_crc_errors`、`w_a_header_errors`、`w_a_packet_timeouts`、`w_a_frame_timeouts`（可选 `w_a_last_wc/w_a_last_lines`、`raw_stat_valid`、`raw_stat_sequence[31:0]`）→ 总线改 **Unsigned Decimal** → **Instant Trigger** ×2（间隔数秒）记录。注意：DDR 域（cwc2）在 `ddrphy_rdy=0` 下计数冻结（全 0 属预期），**优先 cwc1**；若工具要求下载/报 code mismatch 停在提示反馈原文。
20. **用户断电重上电 + 002820 重下（19:56–19:5x）**：重上电后 USB-JTAG Cable 19:56:32 重新到齐、**WinUSB 绑定保持**；下载前 SHA 复核 `4D591C31…DD8865` ✓；6.2.2 组合单次成功——`PRG-2014: PH1P100`、**rc=0、40.2s、满进度、无影响结果的错误行（仅第二实例 usb_open 提示）、无重枚举**；`T01F_002820_SRAM_DOWNLOAD_END result=ok`。日志：`sram_download_002820.run2.out.txt`、`hwserver_622_002820_r2.*`、bw 最新会话日志。备注（如实）：本次时长 40.2s，长于该机历史 28–33s（不解读，仅记录）。**当前板上 bit=002820（重上电后的第二跑）**；等用户报灯（重点 D37 是否闪）。
21. **用户观察（002820 重跑）：出图且颜色接近正常** ⇒ 三项结论：①先前 002820 黑屏=**间歇性 DDR 校准问题**（断电重上电后自愈）；②**WB 管线板级有效**；③**DDR 读路径通**。此结论同时回溯解释 1333/1600ctl 早前两次黑屏（同属间歇 DDR 未起，非候选缺陷；当时未断电）。
22. **1333 主候选重下（重上电后，20:0x）**：下载前 SHA 复核 `B7EF91CF…D150E3` ✓（尺寸 5,224,029 B）；6.2.2 组合**单次成功**——`PRG-2014: PH1P100`、**rc=0、32.6s、满进度、无影响结果的错误行（仅第二实例 usb_open 提示）、无重枚举**；`T01F_1333_SRAM_DOWNLOAD_END result=ok`。日志：`sram_download_1333.run3.out.txt`、`hwserver_622_1333_r3.*`、bw 最新会话日志。**当前板上 bit=1333 主候选**；待用户观察：出图？颜色（G3：白纸中性/红蓝身份）？灯态？稳定性（先 5–10 分钟起，G4）。
23. **用户最终观察（1333 主候选）：工作正常**——出图；颜色基本中性、红蓝色正确（**G3 口径基本达成**）；屏幕基本正常（强光/反光下轻微噪点，较此前"还好些"）；LED= **D37 闪/D38 亮/D39 灭/D40 亮**（好态签名）。⇒ 先前黑屏统一归因为**间歇性 DDR 校准**（断电重上电+重下自愈）、非候选缺陷。证据包见 §13。
24. **审计后事件（R2 登记）**：20:08:57 主机侧线缆再枚举一次（`USB\VID_0403&PID_6042\AL0B99F427` 及 MI_00/MI_01 的 LastArrivalDate 更新；WinUSB 绑定保持 `oem56.inf`/ProblemCode=0；无 LastRemoval；PnP Configuration 通道无事件；晚于证据冻结、未改动任何 F 产物）——engineering 审计 §6 项，已在证据 JSON R2 `post_freeze_usb_link_event` 登记（含系统侧 hcmon 事实记录、不作因果归属）。
25. **稳定性补记（R2）**：用户原话"稳定性没问题"（**1600ctl 干净对照=用户明确不做，关闭**）；按 §13 格式补记（≈20:10–20:20、image=正常、color=基本中性、LED=好态签名、anomaly=无、uptime≈15+ min）。

## 10. LED 语义与"无相机预期"（源码依据；解读 1600ctl 现场）

**引脚/位序**：`board.adc`：`O_led[0]=E21、[1]=D21、[2]=E22、[3]=D22`；**D37=O_led[0]、D38=[1]、D39=[2]、D40=[3]**（按板丝印，与既有文档口径一致）。

**语义**（`ddrmc_display_top.v` L205–208 + `f9p_camera_display_core.v` L225，全部低有效）：
- **D37 闪** = `~(ddrphy_rdy&&clk_cnt[25])`：DDR PHY 就绪后的心跳；
- **D38 亮** = `~pass_seen`：≥1 帧"完整好帧"（存储→读回校验）通过（`passed_frames!=0` 粘滞）；
- **D39 亮** = `~error_seen`：粘滞错误（`failed_frames || protocol_errors || underflow（显示欠载，需曾起帧）|| capture_drops（采集丢帧）` 任一）；
- **D40 亮** = `~camera_led[0]` = A 口 I2C **配置流程完成**（不证明收到图像）。

**用户现场（1600ctl：D37 闪 / D38 黑 / D39 常亮 / D40 常亮）解读**：
- D37 闪 → DDR 已就绪、设计在运行；D40 亮 → A 口配置流程已跑完；
- **D38 黑 = 任何完整好帧都未通过**；**D39 常亮 = 至少一条粘滞错误已触发**。
- 历史对照：本签名与 **155843"无图像"** 完全一致（D37闪/D38灭/D39亮/D40亮，见 `docs\CSI帧完整性_实现与验证_2026-10-12.md`）；正常出图态= D37闪/**D38亮/D39灭**/D40亮；**222159**（出图+彩点）观察时 D39 灭（D38/D40 当时未逐一确认）。

**无相机预期（一句）**：本 DDR 管线在"没有任何帧通过"时**像素引擎恒输出黑**（`rgb565_display_pixels.v` L33 `rgb<=0`，仅 armed 帧才给色），HDMI 时序照常——**黑屏即"无可用帧"的设计行为（非无信号）**；且按源码推演，**纯"相机完全静默"时 D38/D39 都应保持灭**（欠载计数需"曾起帧"、采集丢帧需采集活动）——现场 **D39 常亮**说明发生过"已接入"的错误事件（更典型解释=相机侧产生过帧活动但未通过；不排除等效异常激励），**不能简化成"相机没插"**。最终判定以 140836 环境对照为准。

## 11. 历史已验证 bit 备查清单（环境对照用；本轮未下载其中任何 bit）

| # | 候选 | bit 路径 | 大小 | SHA256（本机重算） | 板上验收出处（简要） |
|---|---|---|---|---|---|
| 1 | **140836**（最近一次真实出图；环境对照首选） | `D:\TD\work\csi2\prj\camera_rgb565_20261014_140836\camera_ddr_display.bit` | 5,224,033 B | `E4A3E980C4BB2305C52E6316DA4164F8F1588E6BC7819EDF0FB68FD8F99BBF7E`（与档案 `e4a3e980…` 一致） | 真实出图（严重玫红、G3 失败）：`README.md` L35；用户照片：`docs\知识书\08_Bayer与颜色.md`；ChipWatcher 重下后"HDMI 实时图像正常变化"：`docs\ChipWatcher空白波形_读回映射修复_2026-10-14.md` L5；"当前板上仍为用户确认的140836"：`docs\140836白平衡原始统计_逐步读取.md` L7 |
| 2 | 215134（RGB332 参考；次级） | `D:\TD\work\csi2\prj\camera_rgb332_reference_20261013_215134\camera_ddr_display.bit` | 5,224,033 B | `5C8D3081AE5A56E8CD9C35DE134CA75C7FECE5F5379D33587B727D73A9EA35CD`（与档案一致） | "同一215134位流未更换，实时相机后来已恢复"（`docs\RGB332偏色_同负载参考色条_2026-10-13.md` L1）；**上下文关联、无独立下载日志/位流读回**（同文档 L9） |
| 3 | 002820（白平衡候选；前身但未板上验） | `D:\TD\work\csi2\prj\camera_rgb565_wb_20261015_002820\camera_ddr_display.bit` | 5,224,033 B | `4D591C31DA9A71B9C261972E5089930AF3E441C2096ED37736C8D2340DDD8865`（= 档案 `4D591C31…`） | **从未下载/上板**（"待人工SRAM板验"，`CODEX_HANDOFF.md`）——仅前身参照，不作环境对照 |
| 4 | 233658 | — | — | — | 最终 STA 失败（−1.849ns/TNS−24.474），**无 bit**（排除） |

- 备注：1333/1600ctl/002820 系 6.2.3 产物 = 5,224,029 B；旧 6.2.2 产物（140836/215134）= 5,224,033 B（工具版本差异，如实记录）。

## 12. 修订记录

- 2026-10-17 首版（阻塞时点）：状态=blocked（唯一动作：§6）；未下载；观察清单待下载成功后启用；1600ctl 脚本就绪。
- 2026-10-17 二版：§6 完成注记；新增 §9 上板执行记录（run1 失败/诊断/run2 成功）；状态=已下载成功、待观察；1600ctl 待命（建议沿用 6.2.2 组合）。
- 2026-10-17 三版：§9 增补第 7/8 条（1333 黑屏观察、1600ctl 对照下载成功）；新增 §10 历史已验证 bit 备查清单（140836/215134/002820/233658，含本机重算 SHA 与出处）。
- 2026-10-17 四版：§9 增补第 9–12 条（LED 观察、140836 环境对照 fail→重试 ok、COM8 遥测尝试、重枚举事件汇总）；新增 §10 LED 语义与无相机预期（源码依据）；原 §10 历史清单顺延为 §11，修订记录为 §12。
- 2026-10-17 五版：§9 增补第 13–15 条（140836 出图环境验证通过、002820 本体首跑成功、两分支计划）；板上 bit 序列记录：1333→1600ctl→140836→002820。
- 2026-10-17 六版：§9 增补第 16–19 条（002820 黑屏+新签名 DDR 未就绪、bit 家族清点、变更清单与嫌疑排序、ChipWatcher 计划）。
- 2026-10-17 七版：§9 增补第 20 条（断电重上电后 002820 重新下载成功、链路/绑定复核、时长备注）。
- 2026-10-17 八版：§9 增补第 21–22 条（002820 重跑出图+颜色近正常 ⇒ 间歇 DDR 校准自愈/WB 板级有效；1333 主候选重下成功、待 G3 观察）。
- 2026-10-17 九版：§9 增补第 23 条（1333 最终观察=工作正常/G3 基本达成）；新增 §13 收尾（证据包路径+SHA、最终结论、板态、稳定补记格式、回退）。
- 2026-10-17 十版（R2 审计后补记轮）：证据 JSON 修订为 R2（R1 审计锚 `8DB60A3F…` → R2 `F38F440B…`）；修项=obs#3 原话/注解分离、obs#5 四灯回填、稳定补记格式统一 §13 版、间歇段措辞修正、20:08:57 线缆再枚举登记、稳定性补记与 1600ctl 关闭落盘；本 notes 中"无错误行/无错误"表述统一改为"无影响结果的错误行（仅第二实例 usb_open 提示）"；§9 增 24–25 条；§13 更新证据包 R1/R2 编号与板态/G4 口径。

## 13. 收尾（F 完成，2026-10-17 20:0x）

- **证据包**：`docs/evidence/board_verify_ddr1333_20261017.json`——**R1（审计锚）**=`8DB60A3F9DDAE875B1C74E457182EB49509CA8AF04F0F9001C57064C62C6FD38`（15,174 B）；**R2（本修订）**=`F38F440B586C838714C30051D34E91669BD6269A1337D44ECDC9D5EA16EC5619`（18,762 B；审计后补记/格式修订，清单见 JSON `revision_history`）。
- **最终结论（以用户观察为准）**：1333 主候选上板**工作正常**——出图、颜色基本中性、红蓝色正确（**G3 口径基本达成**）、灯态=好态签名（D37 闪/D38 亮/D39 灭/D40 亮）；此前黑屏=**间歇性 DDR 校准**（断电重上电+重下后自愈；同一 bit 逐字节不变）。
- **当前板态**：板上=1333（SRAM，掉电即失）；**G4 短窗=用户口述通过**（原话"稳定性没问题"）；长稳 not_run（不宣称长稳通过）。
- **稳定性补记格式（一行）**：
  `- [HH:MM] 1333 稳定观察：image=有/无/异常；color=中性/偏X；LED=D37 闪|灭 / D38 亮|灭 / D39 亮|灭 / D40 亮；anomaly=none|闪烁|撕裂|黑屏|死机；uptime=__min`
- **稳定性补记（R2 落盘，用户原话"稳定性没问题"）**：
  `- [约20:10–20:20] 1333 稳定观察：image=正常；color=基本中性；LED=D37 闪/D38 亮/D39 灭/D40 亮；anomaly=无；uptime≈15+ min（用户语）`
- **1600ctl 干净对照：用户明确不做（关闭，不再悬挂）**。
- **审计后事件登记（R2）**：20:08:57 主机侧线缆再枚举一次（WinUSB 绑定保持、无 PnP Configuration 事件、晚于冻结、不改动任何 F 产物）——见证据 JSON `post_freeze_usb_link_event`。
- **已知项备注**：强光/反光下轻微噪点（用户称"较此前还好些"）；1600ctl 干净对照=用户已关闭；WinUSB 绑定若被系统更新重置 → 用 `D:\TD\JTAG工具\UsbDriverTool`（管理员）恢复。
- **回退**：140836（`e4a3e980…`）、002820（`4d591c31…`）bit 均已板上验证可用。
- 清理与约束：helper 进程已清理、无残留；候选/证据/脚本零改动（本任务仅新增证据 JSON 与本 notes）；全程 SRAM-only、未触 Flash/EFUSE/NVM/OTP。
