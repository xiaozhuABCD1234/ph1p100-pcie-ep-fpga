# T09.rk-align-algo：三种四像素预处理（灰度/高斯/CDF-min 前帧均衡）真实 RTL

batch_size=1；round0；你是本包唯一新开发，不派生代理。读 fpga-dev 与 fpga-design-guide 技能、根AGENTS、user-feedback-03/-04（基础任务含三算法）、dev-plan『基础任务扩展』『比赛要求对齐』节、fpga-design-guide.md、`parallel/algorithms/image_algorithms_ref.py`、`parallel/algorithms/tb_image_algo_stream.sv`，以及 Bayer 工作树（只读）`C:/Users/czz/.codex/worktrees/bayer-codec-reference/FPGA创新设计赛道/fpga/csi2/src/img/{rgb8_gray_stream.v,gray8_gaussian3x3_frame.v}` 与 `tools/rtl_checks/verify_{gray,gaussian}.py`（复制到本包新目录时记录来源 SHA 与 local diff，**不写工作树**）。

## 目的与本包边界

实现比赛 R2 要求的三种四像素预处理真实 RTL（4px 输入域；RAW10 样本截高位 `>>2` 到 8bit 域）：**灰度化（含 Bayer→Y8 去马赛克前端）、高斯滤波（3x3）、CDF-min 前帧均衡（HE）**；三者必须能**硬件并行**（多分支/独立流水，非串行软件模拟）并给出结构/吞吐/资源证据。本包只做算法模块与其小顶候选，不接传输顶层（后续集成包），不改旧主线与 T07/T11 冻结内容。

## 实际写入范围与工具

- 新源码/测试：`PROJECT_ROOT/fpga/csi2/src/img/`（新建；从工作树引入的候选带 provenance）。
- 新 runner/生成器/校验：`PROJECT_ROOT/tools/algo/`（新建；脚本遵循 UTF-8 BOM/ASCII 规则；判据看产物不看退出码）。
- 本 run 新目录：`OUTPUT_DIR/algo/`（candidate、g1、g2、清单/自检、change-report、source-provenance、build-entry、actual-commands、dev-result、lessons）。
- 测试只写 `OUTPUT_DIR/test-reports/T09.rk-align-algo-r0-*` 与各自证据目录。
- 只读：Bayer 工作树、`fpga/csi2/pcie_integration/`、`tools/pcie_integration/`、`raw/`、`backend/`、`fpga/csi2/src/{cam,csi,mem}` 旧主线、D:/TD、D:/anlogic、其他 run。
- 工具：TD6.2.3 CLI `D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe`；ModelSim `D:/intelFPGA/18.1/modelsim_ase/win32aloem`；环境自检可参考 `tools/env/env_check.ps1`；runner 组织方式可参考 `tools/pcie_integration/run_sim.ps1/run_td.ps1`（**在 tools/algo/ 自建副本**，不改原文件）。
- 禁止：放宽 SDC、multicycle/max_delay、改 187.5MHz/相机前提、改旧主线与冻结输入、批量删除、外部工程写、Flash/发布/队友消息。

## 必须实现

1. **灰度（含 Bayer→Y8 前端）**：RAW10 4px（Bayer CFA，相位参数化）→ 8bit 域（`>>2`）→ 固定可复现去马赛克（沿用既有定义：双线性→RGB→Y8 或等价固定路线；不新增 AWB/CCM）→ Y8 流；边界保持 CFA 奇偶；首行/末行/首列/末列规则冻结。
2. **高斯（3x3）**：Y8 域 3x3 高斯（工作树 `gray8_gaussian3x3_frame.v` 候选，provenance 引入）；行缓冲/边界规则/流水结构明确；与灰度输出对齐（同拍或登记的流水延迟）。
3. **CDF-min 前帧均衡（HE）**：前帧直方图 CDF-min 映射；换 LUT 时机与旧/新 LUT 发布语义；首帧无前帧时的定义；**四像素同 bin 冲突**计数规则；边界/坏帧语义。
4. **硬件并行**：三算法作为独立分支/流水组织（如共享 4px 输入分发、三路并行处理），给出并行结构图与并发证据（仿真中三路同时产出、互不串行等待）；资源/吞吐按 1080p30 单路与双路预算（注明头/报文另计）。
5. **接口与参数冻结**：4px 输入握手（含 stall 保持）、SOF/EOL/EOF 对齐、坏帧拒绝/不发布残片；Bayer 相位、ROI、位宽、延迟参数化并记录。

## 局部检查与冻结产物

- G1（ModelSim 真实 RTL）：逐样本与**独立软件模型**（parallel/algorithms 参考 + 本包 Python oracle，不调用 DUT helper）一致；边界/首帧/坏帧/切换（换 LUT/换模式）/停顿；至少一项可重放负对照。
- G2：小顶（三算法并行组织）在同一最终 DB：setup≥0/STNS0/hold≥0/资源≤器件/Routed/报告与 bit 同源 SHA；TD 重建记账≤2；任何改动重跑。
- 产出：`algo/change-report.md`、`algo/source-provenance.json`（含工作树来源 SHA）、`algo/build-entry.md`、`algo/actual-commands.json`、`algo/g1/`、`algo/g2/`、`algo/candidate-manifest.json`+自检、`algo/dev-result.json`、`algo/lessons-learned.md`。停止修改后 ready_for_test。

## 三维验收与停止

functional：三算法逐样本一致、边界/首帧/冲突/坏帧/切换/停顿全过、并行结构并发证据（真实 RTL；G1 必需）。engineering：独立复核同 manifest 最终 DB/STA/约束/CDC/资源与 bit（G2 必需）。system：接口/顶层接入入口、参数冻结、R2 并行展示、板测准备（不宣称 G3 实收；G3/G4 留板测包，G5 未完成）。报告 `T09.rk-align-algo-r0-{functional,engineering,system}.md` 首行唯一判定，绑定 `algo/candidate-manifest.json`。缺工具/资料直接 blocked 交原规划，不空转、不放宽。**比赛 R2 原文“剩余两项必须硬件并行实现”——验收须有真实并行硬件结构与资源/吞吐证据，不得只串行或软件模拟。**
