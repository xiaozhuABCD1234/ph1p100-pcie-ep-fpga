# 方案 A 引导说明 — TD 2026.2 GUI 对 DDR1333 IP 做一次“应用/OK”（T01.tool-D-A-preboot）

- 生成时间：2026-10-17 00:1x（上海时区）；执行者：本工作包开发者（未启动过 GUI，本说明不含任何自动点击）。
- 引导目录：`D:\TD\work\csi2\_validation\td2026_gui_bootstrap_20261017_000935`
- 目的：让新版（6.2.3）GUI 对已建好的 DDR1333 IP 实例 `ddrmc_x32` 做一次 **参数应用/OK**，触发其内部 ADC 检查，使文件 **`ddrmc_x32_adc.log`** 被物化（这是 CLI 直接 `generate_target` 失败所缺的文件）。你只需点几下；**不要**点击任何 Generate/生成。

## 一、你要做的事（共 8 步）

1.（可选，建议先做）双击 `open_bootstrap_folder.cmd` —— 打开引导目录窗口，等下用它观察新文件出现。
2. 双击 **`open_ddr1333_gui_6.2.3.cmd`** —— 启动 TD 2026.2 GUI。若出现欢迎页/许可提示，正常进入即可。
3. GUI 中：**文件(File) → 打开工程(Open Project)**，在对话框地址栏粘贴：
   `D:\TD\work\csi2\_validation\td2026_gui_bootstrap_20261017_000935`
   回车后选择 **`ddr1333_proj_boot.al`**，打开。
4. 在工程的 IP/文件列表中，找到 IP 实例 **`ddrmc_x32`**（位于 `ip_out` 下）。
   **双击它**打开 IP 配置对话框；若双击无反应，右键该节点，找「打开 / 配置 / Open / Configure」。
   （若找不到该入口，见「停止条件」，截图回报，不要乱点。）
5. 在弹出的对话框里**核对关键字段**（值已由命令行写入，只核对，无需改动）：

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
   | ADC File Path | `…\td2026_gui_bootstrap_20261017_000935\input_pins.adc` |

6. 点对话框的 **确定 / OK**（如有单独的「应用 / Apply」也可）。
   **如果 OK 之后弹出「IP Generating Options / 生成选项」之类的对话框：直接点 取消 / 关闭** —— 这一步已经完成了我们要的（检查/物化），**不要点 Generate/生成**。
7. 观察第 1 步打开的目录窗口：`ip_out\` 下应在几秒内新出现 **`ddrmc_x32_adc.log`**（≈1.4KB，时间戳=刚才）。
   （若对话框内有 DRC Check 状态，应为 PASS；看到即好。）
8. 正常关闭 TD GUI 窗口。回报一句：**“已完成，adc.log 已出现 / 未出现”**，附截图（可选）。

## 二、不要点的东西（重要）

- **不要点任何 Generate / 生成 / IP生成 按钮**（本轮只做“应用/OK”）。
- 不要修改实例名、输出路径、ADC 路径；**如果对话框里 ADC 路径为空或不是上面那个路径 → 停止并截图**。
- 不要接受任何 “IP 升级 / Upgrade / 迁移” 提示 —— 出现就选 取消 / 否；若无法取消，停止截图。
- 不要在 TD 里新建 IP、不要另存工程、不要在对话框里新建/切换 Depot。

## 三、预期观察（成败判据）

- **首选**：`…\td2026_gui_bootstrap_20261017_000935\ip_out\ddrmc_x32_adc.log` 出现（≈1387 B）。
- **次选**：`…\ip_out\.IpToolIpDataBackupDir_ddrmc_x32\ddrmc_x32_adc.log` 出现。
- 两者任一出现 = GUI 步骤达成；**都不出现（OK 后等待 ≥30 秒）= 方案 A 前提不成立**，停止操作并回报，后续转入“方案 B（GUI 完整生成）”决策。

## 四、停止条件（遇到任一：停止操作、保留窗口截图、回报，不要再点）

1. 双击 `open_ddr1333_gui_6.2.3.cmd` 后 30 秒内没有出现 GUI 窗口；
2. 打开工程时报错，或打开后找不到 `ddrmc_x32` 实例；
3. 配置对话框打开但 ADC File Path 为空/与上表不符；
4. 点 OK 后 30 秒内（两个候选位置）都没有出现 `ddrmc_x32_adc.log`；
5. 出现任何“生成失败 / 清理 / 删除文件 / 覆盖”类提示，或要求 license/登录的提示；
6. 出现「IP 升级」类对话框且无法取消。

## 五、防护说明（为什么这样设计）

- 引导目录是**全新目录**，其中所有状态（工程、IP 实例、参数、staging）均已在 GUI 前冻结并留有清单（`pre_gui_manifest.json`，含每个文件 SHA256），GUI 后我们会做差异对比。
- **不点 Generate** ⇒ 不会触发工具的生成清理行为；工具的检查步骤只写日志类文件。
- 命令行侧不会自动点击/自动生成；你的操作完成后，由我们在 CLI 用 `boot_retry_generate.tcl` 重试 `generate_target`，并按 T01.tool-A 同口径（§4.1）做产物闭合、参数与 70 引脚核对与两次独立复现。
- 若 OK 后 CLI 重试仍报同一 `adc.log` 错误（存在前期反例信号），将如实记录并转入方案 B（GUI 完整生成）或进一步调查——不把 GUI 步骤算作 headless 成功。

## 六、完成后交回什么

- 一句话结果（“已完成，adc.log 已出现/未出现”）；
- 可选：两张截图（IP 配置对话框 + 目录窗口中出现 adc.log）；
- 关闭 GUI 即可，其余由我们接手（读取日志、CLI 重试、验收）。
