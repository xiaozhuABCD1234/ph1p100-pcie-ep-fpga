# result-r0：T10.ss-steady-anchor（P1 稳态实测）

- 任务：`T10.ss-steady-anchor`；run `20261025-233401_fpga-steady-state-reverdict`
- 日期：2026-10-26T00:48:01；工作树 `D:/fpga/ph1p100`；只写本任务 r0/ 与 `%TEMP%\opencode\ss-anchor\`
- 工具：ModelSim Intel FPGA ASE 10.5b（`D:\intelFPGA\18.1\modelsim_ase\win32aloem`）；Python 3.11.5；**0 次** TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG
- 冻结输入：13 个编译相关副本 + 1 个参照 TB（共 14）与 b11 manifest **0 mismatch**（`input-verified.json`）；DUT 源 0 修改；TB 仅设计指南 §3.2 白名单 1–8

## 1. 命令与预算（实际）

| 步骤 | 命令 | rc | 墙钟 s | 硬超时 s | 日志 |
|---|---|---:|---:|---:|---|
| vlib.exe | `D:\intelFPGA\18.1\modelsim_ase\win32aloem\vlib.exe work` | 0 | 0.1 | 300 | `D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict\T10.ss-steady-anchor\r0\sim\logs\vlib.log` |
| vlog.exe | `D:\intelFPGA\18.1\modelsim_ase\win32aloem\vlog.exe -sv -work work +define+SIMULATION D:\fpga\ph1p100\workflow\runs\20261025-233...` | 0 | 0.3 | 1200 | `D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict\T10.ss-steady-anchor\r0\sim\logs\vlog.log` |
| vsim.exe | `D:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe -c -lib work -l D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-st...` | 0 | 426.1 | 2700 | `D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict\T10.ss-steady-anchor\r0\sim\logs\control2.log` |
| vsim.exe | `D:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe -c -lib work -l D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-st...` | 0 | 661.3 | 2700 | `D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict\T10.ss-steady-anchor\r0\sim\logs\run4.log` |
| vlog.exe | `D:\intelFPGA\18.1\modelsim_ase\win32aloem\vlog.exe -sv -work work +define+SIMULATION D:\fpga\ph1p100\workflow\runs\20261025-233...` | 0 | 0.3 | 1200 | `D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict\T10.ss-steady-anchor\r0\sim\logs\vlog.log` |

- `vsim` 实际总墙钟：**1087.4 s**（预算 ≤100 min / 单次 2700 s）；`vlog`：0.6 s（≤1200 s）；全尺寸 vsim 次数：2（2 帧控制 1 + 4 帧 1）。
- 独占：work 库 `C:\Users\czz\AppData\Local\Temp\opencode\ss-anchor\work`；`modelsim.ini` 副本 `C:\Users\czz\AppData\Local\Temp\opencode\ss-anchor\modelsim.ini`（sha256 `f59c015e7adede3afd73c5082f4426081ece32169c8803064528b9969c742543`）；日志/统计/事件均在本任务目录。

## 2. 2 帧控制（V2）

- 结果：**PASS 逐值复现**；rc=0，426.1 s，timeout=False。
- 冻结门槛：`cycles=11445988`、`cap_bytes=80156`、`exp_bytes=80068`、`read=259200`、`cap=2/enc=2/exported=2`、`raw_drop=0/cmp_drop=0/wd=0`；实测：`cap=2 enc=2 exported=2 exp_bytes=80068 raw_pub=2 raw_drop=0 cmp_drop=0 geom=0 err=0 read=259200 dup=0 cap_bytes=80156 cycles=11445988 wd=0`。
- 说明：新增 SS_EVT 只在既有 `posedge clk_a1` 块中比较只读 `st_*`，不改变驱动/时钟/复位，因此 2 帧统计精确保持 b11 值（含导出后 2000-cycle drain）。

## 3. 4 帧稳态（Q1）

- 状态：`measured`；事件帧：[1, 2, 3, 4]；rc=0，661.3 s，timeout=False，SS_STALL=False。
- `L_cold=6766434`、`L_frame=6766393`、`S_2=4677535`、`S_23=4677535`、`S_34=4677535`、`S_ss=4677535.0`（band [4677535, 4677535]，spread=0.00%）。
- `S_avg2（事件口径，不是 S_ss）=5721984.5`；`startup=2088899`、`startup_pct=44.66%`。
- 算术：`C_ss=103.901 MB/s`、`fps=40.085`、`margin_0=+33.62%`、`margin_25=+6.89%`、`f_req_0=140.326 MHz`、`f_req_25=175.408 MHz`。
- 逐帧 export_tail：k1=480930, k2=480930, k3=480930, k4=480930；`sink_limited=false`。
- 实测 tail 480930 比理想串行 400,340（40,034 B×10）高 80590 cycles（固定 CMP 读/导出握手开销）；四帧恒定，不随 k 增长，故 sink_limited=false。
- V1=True、V2=True、V3=True、V4=True、V5=True、V6=True。
- 计数器：`cap=4 enc=4 exported=4 exp_bytes=160136 raw_pub=4 raw_drop=0 cmp_drop=0 geom=0 err=0 read=518400 dup=0 cap_bytes=160312 cycles=20801058 wd=0 ar=523408 r=523408 frames=4 ss_pass=1`。

### Q1 的回答

- 冻结 b11 的 11,445,988（stats，含 2,000 drain）拆成 `L_cold=6766434` + `S_2=4677535` = `t_exp(2)-t_rst=11443969`（`t_exp(2)=11443989`，`t_rst=20`）；事件口径 `S_avg2=5721984.5`，冻结 stats 口径 `S_avg2_stats=5,722,994`，两者都只是两帧平均，**不是**稳态间隔。
- 4 帧实测的稳态间隔为 `S_ss≈4677535.0 cycles`（band 4677535–4677535），与 b6 的 6,421,414 **不同**：6.421M 是单帧冷启动完成时间；把它当每帧服务时间会把容量低估约 27.2%。
- `startup_pct=44.66% > 15%`：把冷启动单帧当作稳态吞吐属于实质性口径错误（P2 的 `COLD_LATENCY_AS_THROUGHPUT`）。

## 4. 自检与负对照

- 结果：**PASS**（3 个解析负对照全部拒绝=True；6 个手算复核通过=True）。
  - `NEG1_THREE_FRAMES_AS_FOUR`：rejected=True，reason=`ONLY_3_FRAMES`
  - `NEG2_S_AVG2_AS_S_SS`：rejected=True，reason=`S_AVG2_AS_STEADY`
  - `NEG3_L_COLD_AS_S_SS`：rejected=True，reason=`COLD_LATENCY_AS_THROUGHPUT`
  - `H1_S_5M_CAPACITY`：expected=97.2 actual=97.2 pass=True
  - `H2_S_6.25M_CAPACITY`：expected=77.76 actual=77.76 pass=True
  - `H3_EXPORT_COST`：expected=400320 actual=400320 pass=True
  - `H4_FPS_AT_5M`：expected=37.5 actual=37.5 pass=True
  - `H5_25PCT_DEMAND`：expected=97.2 actual=97.2 pass=True
  - `H6_BYTES_1080P`：expected=2592000 actual=2592000.0 pass=True

## 5. 白名单与无影响论证（摘要；逐条见 `src/DIFF.md`）

- DUT/模型源 0 修改；`tb_ss_anchor.v` 相对 `tb_b11_full.v` 仅：`FRAMES`、SS_EVT、第 3/4 帧 slot-free 等待、8M/帧 watchdog、`MAX_CYCLES=30M`、4096-bit 路径寄存器、统计行追加 `frames/ss_pass`、DEC/STAT/EVT 绝对路径 plusarg。
- 新增 TB-only 标记 `SS_META`/`SS_PACE`/`SS_STATS` 只读状态、不改 DUT；slot-free 等待读 `dut.raw_slot_st`（`st_slot_st` 只读观测），不是 `force`/`deposit`。
- 继承的 `B11_FULL_READ_DONE` 等待仍为 `2*129600`（为保持与 b11 diff 最小），在 4 帧 run 中只是信息标记，最终门槛用 `FRAMES*129600`。

## 6. 未测 / 边界 / 回退

- **未测**：DDR sustained/刷新/行切换/多客户仲裁；真实 115200 UART 与 PCIe/高速 sink；自然图像/噪声/RAW12/1080p60/4K；双核 per-stream 与共享 PAXI；TD 综合/布线/时序/资源/bit/板卡。
- **边界**：本 PASS 只证明“在该冻结 RTL/TB/几何/内容、18.75 MB/s sim-only sink、行为 DDR 下，L_cold 与 S_ss 被正确测量”；不证明 25% 设计裕量、生产导出或系统可行。判定留给 P2。
- **回退**：本任务目录整体不被采用即可；失败日志保留；未修改/删除 b11、b6、P2、T08/T10、`workflow/tasks.json`、`docs/**`、生产 RTL。
- **漂移**：b11/b6/P2 输入快照见 `input-verified.json`；任务期间若外部改动只记录，不追逐。

## 7. 产物

- `input-verified.json`
- `src/DIFF.md`
- `src/tb_ss_anchor.v`
- `src/ref/tb_b11_full.v`
- `src/p2_a1_board_top.v（只复制/不编译）`
- `sim/run_ss.py`
- `sim/modelsim.ini`
- `sim/commands.jsonl`
- `sim/logs/vlib.log`
- `sim/logs/vlog.log`
- `sim/logs/control2.log`
- `sim/logs/run4.log`
- `sim/caps/ss2.stats`
- `sim/caps/ss2.dec`
- `sim/caps/ss2.evt`
- `sim/caps/ss4.stats`
- `sim/caps/ss4.dec`
- `sim/caps/ss4.evt`
- `out/control-2frame.json`
- `out/events-4frame.csv`
- `out/steady-state.json`
- `out/steady-state.md`
- `out/selfcheck.json`
- `lessons.md`
- `manifest-r0.json`

> `lessons.md` 与 `manifest-r0.json` 在 report 之后生成；manifest 覆盖本目录除自身外的全部文件。

