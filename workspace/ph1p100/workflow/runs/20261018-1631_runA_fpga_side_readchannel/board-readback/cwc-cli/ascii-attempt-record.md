# ascii-attempt-record.md — ASCII 路径有界重试（T11.runB-board-readback，issue-01 核实）

- 时间：2026-10-18 23:23:33–23:24:37（+08:00）；操作者=开发子会话（TD 官方 Tcl，无 GUI 自动化）
- 用户授权：user-input-06（D 盘 TD 附近 ASCII 目录、继续自动尝试）
- ASCII 工作目录：`D:\anlogic\runa_p3\ascii_20261018_232333\`（新建；未覆盖既有文件；未写入 TD 安装目录）
- 复制件（与冻结候选逐字节一致，SHA 复核）：
  - `compiled.cwc` = `FA24E25830FEFE882EDB3B4D9AB18DE8FD39598A9822231B8622C9A0C73F22BB` / 81,063 B
  - `compiled.bit` = `2385CDEDAE1D9985687360AF77341183517E34CB18BE9CAD0229291593411873` / 5,224,027 B
  - 源：`debug-fix\prj\ph1p_pcie_integration_Runs\phy_1\cw\{compiled.cwc,compiled.bit}`
- 结论：**ASCII 路径假设排除**（就 PRG-9505 而言）；`run_hw_cw` 仍 KIT-8000，CLI 读回仍 0 样本。**本轮未下载 bit、未写板、零 Flash/efuse/SPI/svf。**

## A1（23:23:45，cwd=ASCII 目录，无 hwserver）

- `list_cable` → 打印 `PRG-1000 : Connect device:`（无列表）
- `connect_cable`（裸）→ `PRG-8000 ERROR: host name is empty.`
- `read_device_id` → `PRG-9505 ERROR: USB device open error, please re-connect the USB cable!`（×2）→ 脚本按预检中止
- 交互：与 round2 在中文 cwd 下**同样**的 PRG-9505 → 说明是“没有可用的 hwserver 会话”，与路径无关

## A2（23:24:05）：启动 TD 2026.2 自带 hwserver 后 — **USB 通了**

- 启动：`D:\anlogic\TD_Release_2026.2\bin\hwserver.exe -r -s 5555 -f 12 -v -w 5556 -i 0`（PID 73028；监听 5555 成功）
- `connect_cable -host_name 127.0.0.1:5555 -open` → OK
- **`read_device_id` → `PH1P100`**（关键新证据：同一 ASCII cwd 下 USB 访问正常）
- `config_chipwatcher <ascii>/compiled.cwc` → KIT-1004 import `auto_created_cwc1`（9 view/288+288）
- `report_cwc_status auto_created_cwc1` → **`KIT-1004 : compile chipwatcher successfully!`**（硬件侧编译成功——round1/2 从未出现）
- `run_hw_cw auto_created_cwc1 -trigger_now -cable 0` → **`KIT-8000 No watcher instance matched`**
- 会话尾部：`Error @ mpsse.cpp:90 : usb_open() failed`（TD 另起直连 USB 的第二实例提示，伴随上述编译成功）

## A3（23:24:20）：探针枚举 + 无/有 `-cable` 变体

- `get_cw_probes * -nocase -verbose` → 返回值仍是 9 个空 `{}`，但 **stdout 打印 KIT-1001 Total Matches 9**，逐条给出 9 个总线名：
  `u_top/u_pcie_ep_engine/u_ep_bar_win/g_dbg_mark$dbg_mark_word0[31:0]` … `word8[31:0]`
- `run_hw_cw auto_created_cwc1 -trigger_now`（无 `-cable`）→ KIT-8000
- `run_hw_cw auto_created_cwc1 -trigger_now -cable 0` → KIT-8000

## A4（23:24:36）：对象名矩阵（全部 KIT-8000）

- `get_hw_cws *` → `auto_created_cwc1`；`-verbose` 对 `config_chipwatcher`/`report_cwc_status` 是**非法选项**（`USR-8011`），对 `get_hw_cws` 可用
- 依次尝试对象：`auto_created_cwc1_trigger`、`*`、9 个总线名列表、`auto_created_cwc1`（均 `-trigger_now -cable 0`）→ **全部 `KIT-8000 No watcher instance matched`**
- 无 CSV、无样本

## issue-01 定性

| 假设 | 结论 | 依据 |
|---|---|---|
| 非英文路径导致 PRG-9505 / USB 打开失败 | **排除** | 同一 ASCII cwd，启动 TD 自带 hwserver 后 `read_device_id`=PH1P100；未启动 hwserver 时 ASCII cwd 同样 PRG-9505 |
| 非英文路径导致 KIT-8000 | **排除** | ASCII cwd + 硬件连接 + `compile chipwatcher successfully` 后仍 KIT-8000 |
| 真正的 USB 前提 | **已确认** | 必须先有可用的 hwserver（TD 2026.2 自带 `bin\hwserver.exe` 或等价服务）并在 Tcl 里 `connect_cable -host_name 127.0.0.1:5555 -open`，`read_device_id` 才成功 |
| KIT-8000 根因 | **仍待定（非路径/非配对/非 USB）** | 硬件编译成功后 `run_hw_cw` 仍找不到 watcher 实例；可能需 GUI 侧 Watch/注册，或 `run_hw_cw` 需要 GUI 才生成的 hw 句柄 |

## 安全与残留

- 未下载/未重下 bit（板上仍为早前 SRAM debug 位流）；未写 Flash/efuse/SPI/svf；未改线/电源/相机；无 GUI 自动化；未改 TD 安装；未删除既有文件。
- **残留进程：TD hwserver 6.2.3（PID 73028）仍在运行并占用 5555**（本轮末 shell 工具被宿主权限层拒绝，未能停止）。用户用 TD GUI 前需先结束该进程（任务管理器 → hwserver.exe），否则可能报端口/设备占用。
- 证据：`board-readback/cwc-cli/phaseASCII1..4_stdout.txt`、ASCII 目录内 `ascii_probe.tcl..ascii_probe4.tcl`（+ hwserver_out/err）。**本轮新文件 SHA256 未能复算**（轮末 shell 权限拒绝），文件原位保留。
