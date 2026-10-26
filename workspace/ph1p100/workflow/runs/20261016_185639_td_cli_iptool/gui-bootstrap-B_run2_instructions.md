# 第二次独立复现（run2）操作说明 — TD 2026.2 GUI 完整生成（T01.tool-D-B-run2）

- 生成时间：2026-10-17 14:3x（上海时区）；执行者：本工作包开发者（未启动 GUI）。
- run2 目录：`D:\TD\work\csi2\_validation\td2026_b_run2_20261017_143128`（CLI 已完成建工程+全参数注入，停在 Generate 前；`input_pins.adc` 与 run1 完全同源，SHA `F0904238…`）。
- 本次目标：用与 run1 **完全相同**的操作路径再生成一次 DDR1333 IP，用于"两次独立复现"比对。

## 第 0 步（重要）：先关闭已打开的 TD 窗口

当前机器上可能仍开着旧的 TD 实例（含昨晚的窗口）。**先把所有 TD 窗口全部关闭**（若有“是否保存”提示，选不保存/关闭即可），避免旧实例占用工程。

## 你要做的事（9 步）

1.（可选，建议）双击 `open_bootstrap_folder.cmd` —— 打开 run2 目录窗口，稍后观察新文件出现。
2. 双击 **`open_ddr1333_gui_6.2.3.cmd`** —— 启动 TD 2026.2 GUI。
3. GUI 中：**文件(File) → 打开工程(Open Project)**，地址栏粘贴：
   `D:\TD\work\csi2\_validation\td2026_b_run2_20261017_143128`
   回车后选择 **`ddr1333_proj_boot2.al`**，打开。
4. 在工程列表中找到 IP 实例 **`ddrmc_x32`**（位于 `ip_out` 下），**双击**打开配置对话框（如双击无效：右键 → 打开/配置/Open/Configure）。
5. 核对关键字段（值已由命令行写好，只核对，不要改动）：

   | 字段 | 应为 |
   |---|---|
   | DDR Type | DDR3 |
   | RefClk Freq | 50.0000 MHz |
   | DDR Speed | 1333.00 |
   | DQ Bytes | 4 |
   | IO Voltage | 1.35 |
   | Speed Bin | **DDR3-1333J** |
   | Type / Density | x16 / 2048 |
   | CL | **10**（只读派生） |
   | CWL | **7** |
   | ADC File Path | `…\td2026_b_run2_20261017_143128\input_pins.adc` |

6. 点 **确定 / OK**。
7. 出现 **“IP Generating Options”** 对话框后 —— **这次不要关闭它**，填写：
   - **Binary Path**：`D:/anlogic/TD_Release_2026.2/bin/td.exe`
   - **Synthesis Options**：`Behavior`
   - **Export to**：`D:/TD/work/csi2/_validation/td2026_b_run2_20261017_143128/ip_out`
8. 点 **Generate**，等待完成（约 1~3 分钟；期间先出进度对话框，完成后弹成功提示框）。
9. 出现 **“#IP Gen Succeeded / The IP files have been generated successfully”** 提示 → 点 **Ok** → 正常关闭 TD GUI 全部窗口 → 回报一句 **“run2 已完成”**（可附截图）。

## 不要点的东西

- 除本说明第 8 步的 **Generate** 外，不要点任何其它生成/综合/比特流按钮；
- 不要修改实例名、输出路径、ADC 路径；ADC 路径若为空或不同 → 停止并截图；
- 不要接受任何 “IP 升级 / Upgrade” 提示（选取消/否；无法取消则停止截图）；
- Generate 成功后**不要再点第二次** Generate；
- 不要在 TD 里新建 IP、不要另存工程。

## 预期观察（成功判据）

- 弹出 “#IP Gen Succeeded” 类成功提示；
- run2 目录窗口（第 1 步打开的）中 `ip_out\` 下出现：
  - `ddrmc_x32_adc.log`（≈6.0 KB）、`ddrmc_x32_drc_check.log`（≈0.5 KB）、`ddrmc_x32_proc.log`（≈0.4 KB）；
  - `ddrmc_x32\src\`、`ddrmc_x32\src\adc\`、`ddrmc_x32\src\rtl\` 等目录与大量文件。

## 停止条件（遇到任一：停止操作、保留窗口截图、回报，不要再点）

1. 双击 `open_ddr1333_gui_6.2.3.cmd` 后 30 秒内没有 GUI 窗口；
2. 打开工程报错，或找不到 `ddrmc_x32`；
3. 配置对话框的 ADC 路径为空/与上表不符；
4. Generate 后 3 分钟仍无进展、或出现任何失败/错误提示；
5. 出现“清理/删除/覆盖”类警告或要求 license/登录；
6. “IP 升级”类对话框无法取消。

## 完成后交回什么 / 后续

- 一句话“run2 已完成”（+可选截图）；关闭 GUI 即可；
- 之后由开发者执行：run2 候选 manifest 冻结、70 引脚复核、与 run1 逐字节比对（差异逐字段分析）——全部记录进证据 JSON。
