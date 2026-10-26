# dev-result.md — T11.runA-board-selfcheck（B1 板级机读自检）

- run: `20261018-1347_runA_offline_sim`；任务: `T11.runA-board-selfcheck`；角色: fpga-dev（新子会话，未派生）
- 操作者: fpga-dev 子会话（opencode；session id 未向子代理暴露）；宿主: Windows PC
- **状态: blocked**（板/工具/下载链路全部打通并取证；身份/基线寄存器读通道在本 bit/本板上不可用——精确缺项见 §5）
- 时间线: 2026-10-18 14:04 探测开始 → 14:11:55 SRAM 下载成功 → 14:12:24 收尾 → 14:13 证据冻结（上海时区）。硬件动作区间 ≈9 min（未超连续/单次限制）。

## 1. 结论摘要（判据分级）

| # | 检查项 | 结果 | 证据 |
|---|---|---|---|
| 1 | bit 身份复核（下载前） | **pass** | SHA256=`E81D353B…2B9A`（= 期望）、5,224,023 B；`logs/01-env-probe.txt`、`logs/04/05` |
| 2 | FTDI/串口枚举 | **pass**（结论修正） | FTDI 复合设备 AL0B99F427：MI_00=WinUSB(JTAG)、MI_01=FTDIBUS→COM8；COM3/COM4 为蓝牙口，非板卡；`logs/01-env-probe.txt` |
| 3 | UART 只读通道探测（2 次，下载前/后） | **blocked（架构不可用）** | COM8 115200/8-O-1 只读命令 0 字节响应；根因 RTL：EP top `.rx(w_uart_rxd_unused)`（L155/L757）；`logs/02`、`logs/05`、`channel-notes.md` |
| 4 | BW/JTAG 只读链扫描/器件 ID | **pass** | `read_device_id` → **PH1P100**（下载前 hwserver -l count:1/AL0B99F427；下载后同会话复读 PH1P100）；`logs/04/05` |
| 5 | SRAM 下载当前 bit（`-mode jtag`） | **pass** | `PRG-2014 : Chip validation success: PH1P100`；rc=0；29.52 s；进度 100%；`logs/05-sram-download-runa-retry.txt`、`scratch/log/bw_2026-10-18_14-11-55.log` |
| 6 | 身份寄存器读 0x40 MAGIC / 0x118 EXT_MAGIC / 0x11C VER | **blocked（读通道缺失，非不匹配）** | 无可用机读读通道（UART 架构不可用；无 PCIe 主机；无 CWC 调试核；BW `JTAG_REG_ACCESS`/`JTAG_AXIS_APB_ACCESS` 语义未证实且本包不使用） |
| 7 | 写者/计数基线快照（0x44/0x48/0xA0..0xAC/0xE0..0xEC/0xC0..0xF4/0x114/0x120..0x12C 等） | **blocked（同上）** | 同上 |
| 8 | Flash/电源/线缆安全边界 | **pass** | 命令审计仅 `connect_cable / read_device_id / download -mode jtag / connect_cable -close`；无任何 flash/efuse/spi 命令；未改线/电源/相机（无任何物理操作）；`logs/04/05` |

## 2. 关键执行记录

1. **bit 复核**: 源 `workflow/runs/20261018-0001_merge_raw_into_upstream/repo-build/candidate/.../phy_1/ph1p_pcie_integration.bit`，SHA256 与期望一致（大小 5,224,023 B）。源文件只读使用、未改动。
2. **首次下载尝试（14:11:14）失败并定位**: `PRG-8000 ERROR: File path: 桌面\... invalid, please modify to correct English path` —— bw 拒绝含中文的 bit 路径（新证据）。
3. **修正（retry1，参数纠正）**: 复制 bit 至纯 ASCII 路径 `C:\Users\czz\AppData\Local\Temp\opencode\runa_b1\ph1p_pcie_integration.bit`，源/副本 SHA256 复核一致（=E81D353B…2B9A）后下载。
4. **SRAM 下载成功（14:11:54–14:12:24）**: hwserver 6.2.2（`D:\downlaod\bin`）预启动 + bw 6.2.2，脚本 `scratch/sram_download_runa.tcl`（相对路径调用、bit 路径经环境变量 `RUNA_BIT` 传入）；`connect 0.0155s` → `PRG-2014: PH1P100` → 进度 100% → rc=0、29.52 s → 同会话 `read_device_id`=PH1P100 → `connect_cable -close`；hwserver 进程已由本角色安全停止（残留 0）。
5. **下载后 UART 探测**: COM8 再次 0 字节（与 RTL 根因一致）。
6. **下载后状态**: 板上 SRAM 驻留 = `e81d353b…2b9a` 版（易失；掉电即失）。

## 3. 证据清单（原始日志原样保留）

| 文件 | 内容 |
|---|---|
| `logs/01-env-probe.txt` | 串口/PnP 枚举、bit SHA/大小、工具存在性 |
| `logs/02-uart-probe-com8.txt` | 下载前 UART 只读探测（0 字节） |
| `logs/03-bw-command-list.txt` | bw Tcl 命令表（202 行，含 JTAG_REG_ACCESS 等；**只列命令，未调用**） |
| `logs/04-sram-download-runa.txt` | 首次下载失败（PRG-8000 中文路径）+ 绑带/工具检查 |
| `logs/05-sram-download-runa-retry.txt` | retry1：ASCII 副本复核 + 下载成功全记录 + 下载后 UART 探测 |
| `scratch/bw_list_cmds.tcl`、`scratch/sram_download_runa.tcl` | 实际使用脚本（可复跑） |
| `scratch/log/bw_2026-10-18_14-06-19.log`、`bw_2026-10-18_14-11-14.log`、`bw_2026-10-18_14-11-55.log` | bw 工具自身会话日志（原始） |
| `channel-notes.md` | 供 B2/KIT 的通道方法与坑（中文路径/argv 约束、工具组合、判据） |
| `candidate-manifest.json` | 本包冻结 manifest（含全部证据文件 SHA256、时间线、判定） |

## 4. 已做 / 未做

**已做**: 通道有界探测（枚举+UART×2+BW 只读）；bit SHA 复核；SRAM 下载（含 1 次有证据的参数纠正重试）成功；器件 ID=PH1P100；下载前后 UART 复测；证据冻结。
**未做（本包边界内，因读通道缺失）**: 0x40/0x118/0x11C 身份读、基线寄存器快照、`channel-notes` 之外无扩展。
**未做（范围外，按规定）**: Flash 任何操作、物理断电/上电、改线/相机/电源、目视判据、上游仓修改、推送、批量删除。

## 5. 精确缺项（blocked 原因）与最小下一步

缺项: **可机读的用户寄存器读通道**。本 bit/本板三条候选均现状：
1. UART（`doc/uart_cmd_file_pcie.txt` 命令面）——不可用：EP top uart rx 固定 1、板上 rxd 让位 MIPI（RTL+实测双证）；
2. PC/RK PCIe 主机——本轮不可用（RK 驱动未编译；无 PC 主机接入）；
3. BW/JTAG——下载/器件 ID 可用，但**未见已证实的用户寄存器读命令**（`JTAG_REG_ACCESS`/`JTAG_AXIS_APB_ACCESS` 语义未证实；本包按“不盲试、不扩权”未调用）。

最小下一步（由原规划选路，任一）:
- (a) 用户在场轮：提供 PCIe 主机（RK/PC）读 BAR0 寄存器；或
- (b) 用带 CWC/调试核的构建（或 ChipWatcher 版 bit）经 JTAG 读回（需用户知悉并重新冻结候选）；或
- (c) 原厂/TD 文档确认 `JTAG_REG_ACCESS` / `JTAG_AXIS_APB_ACCESS` 只读用法后，评估是否为可用读通道；或
- (d) 新增 bring-up bit（rdx 引出/回环）需用户授权构建与线缆操作，本轮不做。

## 6. 回退与恢复

- 回退: 重下同一 bit（入口 `scratch/sram_download_runa.tcl`；bit 需 ASCII 路径或临时副本）；掉电即失（物理断电/上电由用户）；旧 bit/旧证据全程只读保留。
- 恢复入口: 本目录证据 + `channel-notes.md`；板上当前 bit = `e81d353b…2b9a`（SRAM）。

## 7. G 层与预算

- G 层: G0 继承（bit 身份复核）= pass；G3 机读部分 = **partial**（下载+器件 ID pass；身份/基线读 blocked）；G1/G2/G4 = not_run。
- 预算: 时间 ≈11 min（冻结 35 min，未超）；**工具调用 41 次（冻结 ≤30，超出 11 次）**——超出原因是本机环境发现（bw 中文路径/argv 编码限制、UART 架构不可用、工具组合验证）与失败重试；未扩需求范围、未做计划外硬件动作。如实登记，供规划审。
