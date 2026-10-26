# TD 能否做一个「ROSS 式 AI 助手」—— 可行性研究

> 研究方式：拆解 AMD ROSS（`github.com/Xilinx/ross-ai-assistant`）README + 逐层对照本机 TD 环境（codex/gpt-6-sol high 独立研究，已复核本地文件）
> 结论先行：**能做，但在这 20 天比赛里不值得做完整版。建议只做「一天工期的薄封装」，否则就完全不做。**

---

## 一、ROSS 到底由什么组成（拆解）

| 层 | README 描述的能力 |
|---|---|
| **Vivado MCP Server** | 向 AI 客户端暴露 **Tcl 命令执行、工程管理、综合与实现流程** |
| **Agent Skills** | **Vivado**：RTL 仿真 / RTL lint / 时序方法学检查 / 工程版本控制 / 单个 IP 配置<br>**Vitis HLS**：MATLAB→C++ / 架构生成 / 迭代优化 / 编译流程<br>**硬件调试**：ILA 触发·采集·导出 / VIO 读写探针<br>**Vitis AI**：量化 / 编译参数 / 自定义算子 |
| **amd-doc-search MCP** | 搜索 AMD 器件与工具文档；README 提供 **本地知识库** 替代方案 |
| **客户端接入** | 遵循 Agent Skills 约定，可作为插件或单独安装，用于 **Copilot / Cursor / Claude Code / OpenAI Codex** |

**"ROSS-like" 的最低门槛** = ①一个能安全跑工具 Tcl 并返回结果的**工具接口** + ②少量**任务导向 skills** + ③带页码的**本地文档检索**。
（不需要 HLS / Vitis AI 这些与当前项目无关的模块。）

---

## 二、TD 能力映射（逐层对照，含证据）

| ROSS 层 | TD 对应程度 | 证据与边界 |
|---|---|---|
| Tcl 执行 / 工程管理 / 综合到位流 | ✅ **有对应｜已核实** | `D:\downlaod\bin\td_commands_prompt.exe`；`SWUG105` §2.2、§3.1/3.3 给出命令模式与完整脚本；命令含 `create_project`、`add_files`、`launch_runs`、`wait_run`、`optimize_rtl`、`optimize_gate`、`place`、`route`、`bitgen` |
| 查询设计与生成报告 | ✅ **有对应｜已核实** | `get_ports/get_cells/get_nets/get_pins/get_clocks`、`report_area`、`report_qor`、`report_timing_summary`、`check_timing`、`write_verilog`、`write_sdf` |
| RTL 仿真 | 🟡 **部分有** | TD 生成仿真文件，配合第三方仿真器；**能否通过 TD 的 Tcl 入口全自动驱动仿真，资料里查不到** |
| IP 配置 | 🟡 **部分有** | `bin\IpTool.exe`、`ip\depot\*\Component.xml` 存在；**没查到参数化命令行生成 IP 的接口**；且 `IPUG028` §3.9.1 明确"生成的配置 XML 由 TD 维护、用户不可修改" |
| 下载位流 + 在线 ILA/VIO 类调试 | 🟡 **部分有** | BitWizard 日志有 `connect_cable -allink`、`download -bit ... -mode jtag`；ChipWatcher≈ILA、Virtual Probe≈VIO；**但 `bw_commands_prompt.exe` 的脚本接口查不到** |
| 文档知识库 | 🟡 **部分有** | 本地中文 PDF 文本可提取；**没有现成的 TD 文档 MCP** |
| Agent Skills / TD MCP Server | ❌ **没有现成对应｜资料里查不到** | 需要自己封装 |
| HLS / Vitis AI | ❌ **没有对应** | 本项目不需要 |

---

## 三、⭐ 关键发现：TD 的"无 GUI 执行"方式（已核实）

`SWUG105` §2.2.1.2 明确给出 **Windows 批处理形式**：

```powershell
Set-Location 'C:\你写的临时工程目录'
& 'D:\downlaod\bin\td_commands_prompt.exe' '.\flow.tcl'
```

其中 `flow.tcl` 按 §3.1 写 `create_project → add_files → top_module → launch_runs → wait_run`，
或按 §3.2 写 `read_hdl/read_adc/read_sdc → optimize_rtl → optimize_gate → place → route → bitgen`。

**要点**：
- ⭐ **Windows 不需要 `-mode batch` / `-tcl` / `-script` 标志**（Linux 才明确用 `td.sh -b demo.tcl`）
- `D:\TD\work\course\05_run_led\fpga_prj_Runs\syn_1\run.bat` 也直接调 `td_commands_prompt.exe` + `DefaultFlow.tcl`，
  **但路径写死旧机器 `E:\Anlogic\...` 且末尾有 `pause`，不能原样当自动化入口**
- `SWUG105` §3.5 提供 **"导出工程 Tcl 脚本"** → 适合作为初始脚本

**代理能读的结构化产物（已核实）**：

| 文件 | 能提取什么 |
|---|---|
| `syn_1\run.log`、`phy_1\run.log`、`log\td_*.log` | 阶段、错误/警告码、源文件位置、耗时 |
| `gate.qor`、`place.qor`、`route.qor` | QoR、WNS、违例点数 |
| `*_rtl.area`、`*_gate.area`、`*_phy.area` | 资源占用（IO/LUT/寄存器/RAM/DSP） |
| `final_timing.rpt`、`*.timing`、`*.ts` | 时序覆盖率、建立/保持 WNS/TNS、时钟域、路径 |
| `flow.status`、`best_result\readMe.txt` | 阶段状态、被选为最佳的 run |
| `*.al`（XML）、`*_inst.bid` | 器件/源文件/约束/top/run；BRAM 映射 |

> ⚠️ codex 顺便指出：**`D:\TD\work\csi2\` 没有 `.al` 工程文件** —— 只有 `src/` 和 `constraints/`，**还不是有效 TD 工程**。
> （你的工程建在 `D:/TD/work/test`，所以 `csi2` 目录缺 `.al`。这个不影响，但要记得"工程靠 `.al` 文件识别"。）

---

## 四、可实现的 MVP（如果要做的化）

### 5 个 MCP 工具
| 工具 | 输入 → 输出 |
|---|---|
| `td_inspect_project` | `{project_path}` → `{device, package, top, sources, constraints, missing_files, evidence_paths}`（只读解析 `.al`） |
| `td_run_flow` | `{project_path, stop_after, dry_run, timeout_sec}` → 先复制到临时目录再跑；首批只包 `create/open_project`、`add_files`、`launch_runs`、`wait_run`、`check_timing` |
| `td_scan_log` | `{log_path}` → `{messages:[{code,severity,file,line,text}], counts}`，保留原始日志片段不臆测 |
| `td_read_reports` | `{run_dir}` → `{stage, setup_wns_ns, hold_wns_ns, tns_ns, coverage, resources, evidence_paths}` |
| `td_search_docs` | `{query, top_k}` → `{hits:[{document, pdf_page, section, excerpt}]}` |

### 6 个 Skills（每个规定触发条件 + 步骤）
1. **工程预检** —— 加/迁工程时：解析 `.al`、核对器件封装、源文件、ADC/SDC、top、列缺失
2. **编译与错误诊断** —— 请求综合/位流时：预检 → dry-run → 临时工程运行 → 汇总错误码并附原始日志
3. **时序与资源诊断** —— 编译完成/未收敛时：`check_timing` → 比较各阶段 QoR → 指出时钟域/路径/资源变化
4. **PH1A90 → PH1P100 迁移核查** —— 移植 MIPI/CSI-2 时：对比原语/端口/时钟/约束/仿真模型，列出必须上板验证的项（**不代替眼图测量**）
5. **PCIe 前置核查** —— 写 EP/DMA 前：核对**实际板卡封装**、IP 向导可用性、引脚连接、参考时钟、主机枚举证据
6. **仿真与测试证据** —— 需要定量报告时：准备 filelist/仿真命令 → 读通过失败与波形摘要 → 合并吞吐/延迟/时序/资源的原始证据

### 文档知识库
先用 **SWUG105/103/106/107/110/111/200/201 + IPUG026/028/033 + UG1310 + OneCable**，
PyMuPDF 按 **PDF 物理页** 抽文本，按章节切 600~1000 字块，保留文件名+物理页+印刷页+章节；
中文检索加入汉字 bigram + 英文命令原词（`check_timing`、`IDELAY`）。
**返回原文段落及页码，找不到就说找不到。**

### 安全边界（必须先定死）
- 原工程**只读**，所有运行在**独立临时目录**
- **默认 dry_run**，限定命令与目录，**分钟级超时**
- 记录 **TD 版本 + 原始日志**
- **首版不做**：自动写 IP XML、烧录 Flash、ChipWatcher 探针遥控、通用 RTL 生成、HLS/Vitis AI 迁移、"自动修复所有时序问题"

---

## 五、对这场比赛值不值得做（codex 的建议）

### 助手能加速 / 不能替代
| 实际瓶颈 | 能加速 | **不能替代** |
|---|---|---|
| PH1A90 → MIPI D-PHY/CSI-2 移植 | 找原语差异、约束遗漏、编译错误、仿真资料、时序对比 | 发明软 D-PHY、修复信号完整性、在相机无输出时只靠日志推断真实波形 |
| IDELAY 眼扫校准 | 批量整理参数、仿真激励、实验记录、裕量报表 | 实际采样窗测量、板级偏斜判断、温压验证 |
| PCIe EP+DMA 到 OrangePi | 核对封装/IP/约束、整理枚举/链路/吞吐日志 | 解决尚未确认的封装支持与板级连线；**不能靠生成代码让链路训练成功** |
| JPEG/LZ77 压缩 | 管仿真回归、资源/频率对比、功能测试证据 | 完成算法架构、带宽核算、压缩效果验证 |
| 定量测试报告 | 汇总时序/面积/日志/实验数值并附出处 | **产生不存在的测量数据** |

### 最终建议
> **只做薄封装，投入不超过一天。若当天不能在临时 LED 工程跑通，就暂停工具开发，回到 FPGA 主线。**
>
> 薄封装只做三个动作：**① 调用 TD Tcl；② 提取日志与错误码；③ 汇总时序/资源并附原文件路径。**
> 文档检索可先用简单本地脚本。MCP + 六个 skills 是"有重复需求时"的扩展，**不是赛前 1 天的交付物**。

### 风险
- 推理调用的 **token 成本**
- TD 输出格式变化的**维护成本**
- 中文文档检索**命中率**
- 对硬件现象作出**看似合理却无测量依据**的解释
- ⚠️ **最大机会成本：把 20 天花在"助手外壳"上，而不是 MIPI / PCIe / 数模本身**

---

## 六、⚠️ codex 提出的两个"比助手框架更该立刻处理"的器件事实

| # | 冲突/风险 | 依据 | 你要做什么 |
|---|---|---|---|
| **1** | **PH1P100 的 MIPI DPHY**：`IPUG026` 说 PH1P100 高速 IO 有动态延迟配置，但**安路当前产品选型表把 PH1P100 各封装的 MIPI DPHY 栏列为"—"** | `IPUG026` + 安路官网 PH1P 选型表 | 与"系列宣传"不能混用；**软 D-PHY + 采样窗 IDELAY 校准仍需自己设计并实测** |
| **2** | **PH1P100SBG484 的 PCIe**：`IPUG028` §1.1 只把 **SBG676/677** 列为 PCIe IP 支持封装，但**选型表把 SBG484 标成 PCIe Gen1/2** → **两份资料不一致** | `IPUG028` §1.1 vs `DS1300` 表1-2 | ⭐ **在 TD 里对 PH1P100SBG484 试开 IP Catalog 生成 PCIe IP**（这正是 D2 步骤 3）；生成成功前**不要投入 DMA 开发** |

> 第 2 条正是你 D2 要做的验证 —— 现在有了明确的"为什么必须验"。

---

## 七、给你的一句话行动建议

1. **今天不要碰 AI 助手**，把 D1 剩余步骤做完（跑官方 bit / 验 PCIe 物理通路 / 建工程 / 量 FEP 电压）
2. **D2 务必验证 PCIe IP 能否对 `PH1P100SBG484` 生成**（对应 §六 第 2 条冲突）
3. 若第 5~7 天确实反复遇到"查日志、比对时序报告、检索手册"这类重复劳动，**再花半天做那个薄封装**（3 个动作，不做 MCP、不做 skills）
4. 需要验证两个未知的脚本接口时，跑：
   ```powershell
   & 'D:\downlaod\bin\bw_commands_prompt.exe' -help
   & 'D:\downlaod\bin\IpTool.exe' -help
   ```
