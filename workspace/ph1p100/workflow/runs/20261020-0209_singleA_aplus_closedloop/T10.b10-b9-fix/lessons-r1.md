# T10.b10-b9-fix r1 -- lessons

只记可复用的根因、触发条件、修正点与验证入口。路径均相对本包 `r0/`。

## 1. `td_commands_prompt.exe <脚本>` 的路径解析（本轮实际踩到，浪费 2 次调用）

- **现象**：cwd=`r0/td` 执行 `td_commands_prompt.exe download_sram_b10.tcl` → 只打印 banner +
  `couldn't read file "download_sram_b10.tcl": no such file or directory` + `td > `，**退出码 0**（极易误判成功）。
- **根因**：b10 的这个 tcl 放在 `r0/board/`（b9 的同名脚本放在 `td/`，所以旧习惯会踩）；
  改用 Windows 反斜杠绝对路径后 Tcl 又把 `\f \p \r \b \t \n` 当转义，路径被吃成
  `D:pgaph1p100workflow...`，同样报 “no such file”。
- **修正**：传**前斜杠绝对路径**：`td_commands_prompt.exe D:/fpga/.../r0/board/download_sram_b10.tcl`（cwd 仍为 `r0/td`，
  脚本内的 bit 路径本来就是 `D:/.../a1_board.bit`）。
- **验证入口**：日志必须出现 `RUN-1002 : start command "connect_cable ..."`、`B10_DL_DEVICE=`、
  `PRG-2014 : Chip validation success`、`B10_DL_OK mode=jtag(sram)`。**只看退出码不够**：
  TD 对“脚本读不到”也返回 0。
- **附带结论**：这类“脚本没被读进 Tcl”的调用没有打开线缆、没有传比特，不计下载次数；但必须原样留日志
  （本轮 `r0/board/log-r1/download_sram_r1_badpath*_no_device.log`）并在 result 里说明，不能静默重试。

## 2. 资源指纹是最便宜的“网表是不是目标设计”检查

- r0 的 s2/s3 综合/布线都“时序好看、0 违例”，但规模只有一半：syn ERAM 28 / slice 9,793、routed ERAM 43 / slice 12,557。
- r1（40 bit 通道）与 b9 几乎相同：syn 18,264 / 18,856 / 72，routed 24,368 / 28,004 / 102。
- **用法**：只要 `#eram` 或 routed slice 相对 baseline 掉 30% 以上，先怀疑位宽/端口被误改，**不要**因为时序更好就放行。
  这比逐行读网表快得多（TD 的 `write_verilog` 会展平信号名，`crop_pix` 在 `routed_netlist.v` 里 grep 不到）。

## 3. 板级卡点是相机/MIPI 链路，不是 A1/导出逻辑（b9 已存在）

- 指纹（180 s，r1 与 b9 的 150 s 抓包完全一致）：`cam_sysstat=3869`（`lane_sticky=0xF`，4 条 lane 全粘滞）、
  `cam_phystat=494`（`sync_wait=1`、`in_frame_now=0`）、`cam_pix_beats=0`、`cam_line_rises=0`、
  只有 2~5 个 VS 上升、`cam_last_frame_cycles` 饱和 0xFFFFFF、`crop_short` 每帧 +1、verdict `C`。
- 因此任何“要求 `exported>0`”的板级任务，在相机链路修好前**必然**是 ⚠/FAIL；先把 IMX415/MIPI RX
  （lane sticky、sync_wait、VS 周期）作为独立任务处理，再谈帧导出。
- 状态侧本轮是**正面**证据：180 包 / 1 Hz / 零 XOR，说明 B9-01 修复后在“无业务帧”的极端情况下不再死锁。

## 4. 用同一解析器重解 baseline 抓包，区分“回归”与“既有条件”

把 b9 的 `captures_b9b/com8_150s.bin` 用本包的 `parse_status_v3.py` 再解一遍（只读，输出写到本包 `board/log-r1/`），
得到与 r1 相同的 `cam_phystat/cam_sysstat/pix_beats`，即可一句话排除“本轮把链路弄坏了”。比争论日志更快。

## 5. 其它

- 本版 TD **没有** `report_cdc`（`invalid command name "report_cdc"`，与 r0/b9 相同）；CDC 只能用 `check_timing`
  + `report_clock_utilization` 代偿，并在报告里写明 `cdc_unavailable`，不要伪称已做 CDC 检查。
- `USR-6144 ... pclkx5 742.5 vs 742.4 MHz` 在 b9 日志里同样出现 1 次，属既有 PLL 量化告警，不要当新问题。
- 串口刚打开时抓到的前 8 字节是上一包的尾巴（`skipped_bytes=8`），解析器会自然跳过，不影响包计数。
- `03_cwc.tcl` 的 `setup_debugger` 会打印很长的 `dbg_errors[*] | Checked` 表，属正常输出，不要误判为错误。
