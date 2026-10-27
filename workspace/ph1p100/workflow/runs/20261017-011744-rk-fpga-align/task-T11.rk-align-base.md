# T11.rk-align-base：FPGA 侧基础夯实（环境配置合理化 + 逻辑冗余/优化只读勘察）

batch_size=1；round0；你是本包唯一新开发，不派生代理。读 fpga-dev 与 fpga-design-guide 技能、根AGENTS、user-feedback-03.md、dev-plan.md 新节『FPGA 侧基础夯实与优化子轨』、fpga-design-guide.md、request/user-feedback-01/-02；环境事实只读参考：`evidence/tool-inventory.json`、`evidence/tool-success-reuse.json`、`evidence/hardware-access.md`、`backend/hardware-ready.md`、`raw/hardware-ready.md`、`raw/change-report.md`、`raw/dev-result.json`、`raw/candidate-manifest.json`、`task-T11.rk-align-raw.md`。

**与在途测试的冲突规则（硬约束）**：T11.rk-align-raw r0 functional 测试在途，冻结输入=`raw/candidate-manifest.json`（AAB0CC08…6975）。本包**只写**新目录 `tools/env/`、本 run `env/` 与 `test-reports/` 下本包自己的文件；`fpga/csi2/pcie_integration/`、`tools/pcie_integration/`、`raw/`、`backend/` 在 T11 判定前**一律只读**，绝不触碰冻结输入。同一冻结输入不得边改边测。

## 目的

A. **环境配置合理化与固化**：把本机 FPGA 开发/构建/仿真环境从“事实散落、靠记忆和临时脚本”变成可复现、可自检、可交接的环境基线；产出环境清单、env_check 自检脚本、环境手册、板测环境清单。B. **逻辑冗余/优化只读勘察**：在不改任何代码的前提下，找出集成树（及只读范围内旧线）的逻辑冗余/死代码/重复逻辑/宽比较/时序瓶颈等优化点，逐条给证据、收益、风险、验证方式与优先级，为后续 `T11.rk-align-opt` 实施包提供清单。

## 交付物与写入范围

- 新脚本：`PROJECT_ROOT/tools/env/env_check.ps1`（可另附 ASCII 辅助脚本；编码规则见下）。新目录不存在则创建，先确认归属。
- 本 run 新目录：`OUTPUT_DIR/env/`（inventory、logs、手册、清单、勘察报告、dev-result、lessons、artifacts-manifest）。
- 测试只写 `OUTPUT_DIR/test-reports/T11.rk-align-base-r0-*.md` 与各自独立证据目录；不得改动 T11.rk-align-raw 的测试证据目录与报告。
- 只读：全部既有生产 RTL、`fpga/csi2/src/csi/`、`tools/pcie_integration/`、`raw/`、`backend/`、`backup/references/contract/artifacts/evidence`、D:/TD、D:/anlogic、其他 run/工作树。不删除、不写 Flash/发布/外部消息、不改全局系统配置（PATH/环境变量/注册表/工具安装）。

## A. 环境配置合理化（必须项）

1. **环境清单** `env/environment-inventory.json`：逐项记录（含获取命令与原始输出摘要/SHA）：TD 绝对入口与版本（`D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe`，实查版本与完成标记约定）、ModelSim 入口（`D:/intelFPGA/18.1/modelsim_ase/win32aloem/{vsim,vlog}.exe`）、Python/GCC、PowerShell 版本与 ACP（936）、git 状态与 HEAD、subst 当前映射、临时参考库路径（`C:/Users/czz/AppData/Local/Temp/opencode/ref_*`）、磁盘/路径中文限制与既有规避。**只记录事实，不修改任何环境**。
2. **env_check 自检脚本** `tools/env/env_check.ps1`：无副作用（除写 `env/logs/` 外不写任何位置）；检查：工具存在性与版本/SHA、入口脚本存在且 BOM/编码在位、subst 仅报告、输出目录可达、D 盘只读约定；输出人类可读日志+机器可读 JSON（含时间戳、命令、结果）。注意本机已知坑：UTF-8 无 BOM+中文注释在 PS5.1/ACP936 下会被吞换行（`tools/pcie_integration/*.ps1` 的 BOM 是功能性要求）；新脚本遵循同样规则并验证。**判据看产物不看退出码**（-File 下失败也可能 exit 0）。
3. **环境手册** `env/environment-handbook.md`：从干净 shell 开始的可复制步骤——仿真入口、TD 单会话 `00_all` 规则（分阶段会丢 device_name 的教训）、subst 映射规则（只建自用、用完撤销）、编码/BOM 规则、产物与完成标记判定（PRJ-1406/1424、T07_ALL_DONE、vlog Errors: 0、run.do/vsim.log 齐备）、失败留痕规则、回退（002820 与既有候选 bit）、以及“哪些操作被禁止”（不装工具、不改全局、不写 D 盘）。
4. **板测环境清单** `env/board-env-checklist.md`：操作者上板前需要确认/采集的事项与只读探测步骤（JTAG/BW 入口与器件识别方法、独占窗口、SRAM 加载与恢复步骤引用、UART/ChipWatcher 观测点、RK 侧需提供的事实：BDF/内核/PAGE_SIZE/MPS/IOMMU）。本包**不操作硬件**、不扫描 JTAG；只写程序与清单。
5. 任何需要改动 `tools/pcie_integration/` 或 RTL 才能“合理化”的项：**不改**，写成 `env/optimization-survey.md` 中的建议条目（含风险与验证），留给 `T11.rk-align-opt`。

## B. 逻辑冗余/优化只读勘察（必须项）

产出 `env/optimization-survey.md`，条目格式：`ID｜位置(file:line)｜现象｜类别（死代码/重复逻辑/冗余寄存器/宽比较/不可达状态/常量逻辑/时序瓶颈/资源热点）｜估计收益（时序余量/面积/可维护性）｜风险｜验证方式｜优先级`。要求：

- 范围：主=集成树 `fpga/csi2/pcie_integration/`（含 T07/T11 引入的 checked/写者/pusher 接线）与只读 STA 报告（`raw/g2/`、`backend/g2/` 的最差路径与余量）；次=旧主线只读备注（标注所属线）。
- 已知项必须收录并核对现状（不得照抄旧结论）：`rtl/checked/csi_rx_packet_integrity.v` 的 `END_PACKET` 死分支与陈旧头注释（T07 change-report §8.5/§10.3）；`raw/g2/README.md` §2 的 clk1 单值笔误；`backend/g2/README.md` §6 的旧 manifest 绑定句（F5-r3）；`g1/crc16_upd4.generated.v` 中间产物标注；相机字节域余量薄（+0.115 ns，67% 布线）相关的最差路径。
- 每条必须有可复核证据（读文件/报告行号）；不确定的写“待验证”，不得推断为事实；不得修改任何文件来“验证”。
- 分两组：**安全快速项**（如注释/文档/生成物一致性、无行为风险的等价简化）与**结构项**（如死状态删除、CRC/计数链重构、宽比较收缩——需差分 oracle 与 G2 重跑）。给出建议实施顺序与每项所需验证。

## 冻结与产出

- 记录勘察快照：`env/input-snapshot.json`（勘察涉及文件在读取时的 SHA/mtime，用于证明只读）。
- 产出 `env/change-report.md`（做了什么/没做什么/边界）、`env/artifacts-manifest.json`（本包产物+只读输入快照 SHA）、`env/dev-result.json`、`env/lessons-learned.md`。
- G 层：G0 局部（输入冻结快照）+ G1（env_check 实际运行、勘察证据复读复核）必需；**G2—G5 事前不适用**（本包无生产构建、无候选位流、不操作硬件）；不得声称任何板测/时序结论。
- 停止修改后按合同仅返回元数据；缺工具/权限直接 blocked 交原规划，不放宽、不空转。
