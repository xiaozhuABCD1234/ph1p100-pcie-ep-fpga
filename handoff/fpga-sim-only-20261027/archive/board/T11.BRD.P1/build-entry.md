# T11.BRD.P1 — 构建入口与最短操作步骤

> 本文件描述**实际执行过**的命令形态。未运行过的步骤会明确标注"建议"。

## 0. 前置（每次构建前）

```powershell
cd D:\fpga\ph1p100
# 1) 必须没有他人 TD 会话（存在则 blocked，不共享、不杀进程）
Get-Process -Name pnmain,td_commands_prompt -ErrorAction SilentlyContinue
# 2) T: 必须指向本 run（run_td.ps1 内部会调用 td_env.ps1 -Force 重指）
```

`tools/board_integration/run_td.ps1` 会做三件事：他人 TD 进程预检 → `tools/td/td_env.ps1 -Force -TdDir <本run>\T11.BRD.P1\td`
→ `Y:` 标记检查（`Y:\fpga\csi2\pcie_integration`、`Y:\workflow\runs` 必须存在）。
然后以**单会话 + 硬超时**方式调用 `td_commands_prompt.exe`；超时只停止本流程自己启动的进程。

## 1. 综合（synth#1）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\board_integration\run_td.ps1 -Script 01_synth -TimeoutMin 30
```

`01_synth.tcl`：`create_project brd_board ./ -family PH1 -device PH1P100SBG484 -speed 3 -force`
→ `source ./filelist.tcl`（含守卫：`*.v.stale`、`src/src/**`、`peer-ref-2a4b253/**`、
`integrated_delivery/` 下的 r3 派生变体、缺文件 → 直接 error，不进综合）
→ `top_module brd_integrated_top` → `launch_runs syn_1` → 报告 → `close_project`。

判定（`fpga-design-guide.md` §5）：synth WNS ≥ +0.127ns → 布线；< +0.127ns → 改 125MHz 再综合；禁止改 P4 源码。

## 2. 布线（route#1，仅当 synth 通过）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\board_integration\run_td.ps1 -Script 02_route -TimeoutMin 30
```

## 3. 位流（bitgen#1，仅当 0 违例且 setup WNS ≥ +0.003ns 且 hold ≥ 0）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\board_integration\run_td.ps1 -Script 03_bitgen -TimeoutMin 20
```

`03_bitgen.tcl` 在 `bitgen` 之前解析 `candidate_timing.rpt` 的 SWNS/STNS/HWNS/HTNS/Period，
不满足门槛则 `error` 退出（不出 bit）。`+0.003…<+0.05` 记 `thin_margin`。

## 4. ChipWatcher 导出（CWC#1，仅当有位流）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\board_integration\run_td.ps1 -Script 04_cwc -TimeoutMin 20
```

## 5. G1 仿真

```powershell
# 编译 + 跑仲裁器负例（秒级）
powershell -NoProfile -ExecutionPolicy Bypass -File tools\board_integration\run_sim.ps1 -Test tb_brd_arb
# 编译 + 正例（缩尺 64x48，最长 20 分钟/次）
powershell -NoProfile -ExecutionPolicy Bypass -File tools\board_integration\run_sim.ps1 -Test tb_brd_g1_top -Scen 0 -TimeoutMin 20
# 负例：缺 EOF / 错误 ACK
powershell -NoProfile -ExecutionPolicy Bypass -File tools\board_integration\run_sim.ps1 -Test tb_brd_g1_top -Scen 1 -TimeoutMin 20 -NoCompile
powershell -NoProfile -ExecutionPolicy Bypass -File tools\board_integration\run_sim.ps1 -Test tb_brd_g1_top -Scen 2 -TimeoutMin 20 -NoCompile
```

## 6. 禁止

- **不得**执行 `upstream/ph1p100-pcie-ep-fpga/download_sram.tcl`
- 本包 `download=0`、`flash=0`：不下载、不写 Flash、不接 JTAG
- 不得把 `T:` 指到 b18/b19/b20 目录（会写坏别人的 run）

## 7. 盘符

| 盘符 | 指向 | 用途 |
|---|---|---|
| `T:` | `<本run>\T11.BRD.P1\td` | TD 工程目录（`brd_board.al` / `brd_board_Runs`） |
| `Y:` | `D:\fpga\ph1p100` | `.al` 里的 `Y:/...` 只读源 |
| `P:`/`W:` | 仿真用（本包未使用） | — |

`td/a1_eng_top.v` 与 `td/a1_small_top.sdc` 是**仅为** `tools/td/td_env.ps1` 的路径契约检查
而存在的注释占位文件（该工具要求目录里有这两个名字才允许重指 `T:`），不在任何 filelist 里、不被编译或读取。
