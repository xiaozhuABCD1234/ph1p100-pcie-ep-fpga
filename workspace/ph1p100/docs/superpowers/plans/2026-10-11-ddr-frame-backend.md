# DDR完整帧后端实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 完成可验证的三帧DDR后端与本板独立全帧读回候选，等待真实硬件验收。

**Architecture:** 保留当前相机工程；在独立候选中复用本板DDR/MCU/APB初始化，加入单拍PAXI三帧存储和图案逐字校验。先同域验证，再推进相机/显示CDC接入。

**Tech Stack:** Verilog/SystemVerilog、ModelSim、TD CLI、Python。

**Spec:** `docs/superpowers/specs/2026-10-11-ddr-frame-backend-design.md`

## Global Constraints

- PH1P100SBG484/-3；960×540灰度、16200个256bit字/帧；PAXI地址步长8、全写mask0。
- 不覆盖当前相机候选，不批量删除，不修改厂商原资料或生成IP内部。
- 用户已指定连续原生执行；在独立候选目录隔离，无新增Git worktree，避免现有D盘绝对工程与镜像脱节。
- 实物反馈前只称仿真/构建通过；不称DDR视觉闭环。

## Review Focus

- AW/W非同拍或掩码极性错误造成静默数据损坏。
- LAST异常、abort或ready丢失造成半帧发布。
- 换帧和发布同拍导致READING槽被覆盖。
- 围栏读与普通读返回混淆、返回背压丢字。
- ROM路径错误、未初始化就发命令或LED误报成功。

### Task 1: 三帧后端及反压回归

**Files:** `fpga/csi2/src/mem/ddr_frame_store.v`、`fpga/csi2/tb/tb_ddr_frame_store.sv`、`tools/td/run_ddr_frame.py`。

**Interfaces:** Consumes DDR ready/PAXI; produces frame_begin/ready、input256 valid/ready/last/abort、switch/ready、read offset request及data返回，以及计数/错误状态。

- [x] 写测试，4字/帧，包含普通读回、反压、最新帧替换、abort/短帧、故障和ready恢复。
- [x] 运行负对照，预期DDR_FRAME_FAIL（空功能stub仅测试目录）。
- [x] 实现同域后端，命令一次一拍，末字围栏后发布。
- [x] 运行测试，预期DDR_FRAME_PASS且0 errors。

### Task 2: 独立板级全帧读回探针

**Files:** `fpga/csi2/src/mem/ddr_frame_probe.v`、对应TB；`tools/td/prepare_ddr_frame_probe.py`、本板vendor依赖快照和清单。

**Interfaces:** Consumes Task1接口；产生16200字图案，逐字验证读回，输出完整帧通过/累计错误；板级沿用MCU APB及DDR ready。

- [x] 用有延迟/反压的内存模型验证连续多帧、三槽覆盖与错误注入，负对照预期PROBE_FAIL。
- [x] 实现图案发生及比较器，预期PROBE_PASS。
- [x] 复制官方源码依赖到独立候选，修正自写顶层的ROM路径，原生成IP不改。
- [x] TD创建唯一run，读取最终STA/异常/资源；通过后生成候选bit。

### Task 3: 归档与交接

- [x] 跑受影响回归和源码/镜像哈希核对。
- [x] 独立代码审查，修复重要问题并复测。
- [x] 更新交接/下载说明，Git提交并推送；记录DDR尚待实物验证。

## 执行记录

Pre-flight: Task1→Task2使用同一帧流/PAXI契约；Task2→Task3以实际run及哈希为准。

Ruling: 用户明确授权按已推荐顺序连续实施，沿已有方案写具体spec/plan后直接原生执行，不再插入相同范围的重复审批。代价：若用户希望改变灰度帧尺寸需调整参数后重新验证。

Ruling: 先交付独立DDR后端探针，实物通过后合并CDC/视频，保留已通相机。代价：本轮结束仍不是相机DDR显示闭环。


### 2026-10-11执行与交接记录

Task1完成：RED空模块触发预期看门狗，GREEN后端77项检查通过。Task2完成：16200字/帧行为模型下4个完整好帧、检出1个损坏字，覆盖三槽；probe负对照有效。比较器按8×32位分组寄存并分级更新结果。

TD四轮目录191316、191816、192822、194120均保留；前三轮setup违例，第四轮setup +0.006ns、hold +0.020ns、period +2.200ns、TNS均0。父进程open_run失败后核对96个输入并显式重载导出数据库，重新STA并生成bit。重载覆盖93.40%与子进程95.78%有差异，但时序正文逐行相同；未确定工具统计差异原因，不声称全部约束覆盖。

Task3完成：独立审查与修改后回归、仓库和D盘100个新增文件逐一哈希一致。相机RTL/约束均匹配已编译哈希；D盘工程清单发现缺少两项引用，已备份后仅补回，见camera_manifest_repair证据。没有重建相机bit。完整报告/输入清单/测试结果归档，交接及下载说明更新，随后提交并核验远端检查点。Git提交号以实际提交结果为准。

**待用户操作门槛（未完成）：** 独立DDR候选SRAM下载，核对ready/首个好帧/错误标志及持续计数。随后才做CSI→DDR、DDR→HDMI异步FIFO和垂直消隐换帧。绿色闪点未修复，不把本轮DDR后端称为视觉闭环。
