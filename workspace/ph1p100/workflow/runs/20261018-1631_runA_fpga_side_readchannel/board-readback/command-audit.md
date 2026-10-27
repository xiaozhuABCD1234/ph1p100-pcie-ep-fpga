# command-audit.md — T11.runB-board-readback（P3）

审计范围：本包全部 bw/hwserver 命令（`board-readback\logs\01-bw-sram-download.txt` 原文 + `board-readback\scratch\log\bw_2026-10-18_22-21-16.log`）。

## 1. 实际执行的命令（全量枚举）

| # | 命令 | 时间(+08:00) | 结果 |
|---|---|---|---|
| 1 | `connect_cable -host_name 127.0.0.1:5555 -usr_args  -open` | 22:21:16 | OK |
| 2 | `read_device_id` | 22:21:16 | PH1P100 |
| 3 | `download -bit C:\Users\czz\AppData\Local\Temp\runa_p3\ph1p_pcie_integration_debug.bit -mode jtag -spd 7 -cable 0` | 22:21:16–22:21:45 | rc=0，PRG-2014，100% |
| 4 | `read_device_id` | 22:21:45 | PH1P100 |
| 5 | `connect_cable -close` | 22:21:45 | OK |

- `-mode jtag` = PROGRAM SRAM（易失）；**无**任何第二下载、无 Flash 目标。

## 2. 禁止命令审计

对 bw 输出做 token 扫描 `flash|efuse|spi|svf|erase|program_` → **hits=0**。

| 检查项 | 结论 |
|---|---|
| Flash 写入/擦除 | 0 命中 |
| efuse/OTP | 0 命中 |
| SPI（spi flash/svf） | 0 命中 |
| svf | 0 命中 |
| `program_*` | 0 命中 |

## 3. 物理边界

- 未改线、未改电源、未动相机（本包无任何物理操作）。
- 未推送/未改上游仓（本包零上游写入）。

## 4. 未执行/未审计项（如实登记）

- CWC 读回命令：**未执行**（GUI 流程；见 user-gui-checklist.md）。
- hwserver 进程：仍运行（PID 30988）；停止请求被宿主 shell 权限层拒绝（未绕过、未用其他方式强杀）。
