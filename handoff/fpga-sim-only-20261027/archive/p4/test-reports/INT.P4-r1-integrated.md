### 判定：FAIL

# INT.P4 r1 综合验收报告（dimension=integrated）

## 0. 元数据

- task_id：INT.P4（同候选集成交付）
- dimension：integrated（functional / engineering / system 三维由同一测试者核验，不是三个独立视角）
- round：1（round1 修复后复测；同一测试者，未派生代理）
- run_id：20261026-2138_fpga-integrated-delivery
- 工作树：`D:\fpga\ph1p100`（git HEAD `27c596b01cd961dfa9d0850e4fbf879fe249de90`；候选/工具/run 目录为未跟踪路径，实际候选由 manifest 绑定）
- 冻结 manifest：`workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4-r1-manifest.json`
  - SHA256（测试前/测试后一致）：`CFFCF54DA5E4293AF56C2DAC4AFAF46A0653951E06D957DB6BAE4461D3AE15E0`
  - `stopped_modifying=true`，`drift_count=0`
- 工具：ModelSim ASE 10.5b（2016.10，`D:\intelFPGA\18.1\modelsim_ase`）；Anlogic TD 6.2.3.210850（`D:\anlogic\TD_Release_2026.2`，只读判读既有日志）；Python 3.11.5；Windows
- 测试窗口：2026-10-27 03:36–03:50（本机时间）；测试者只写 `test-reports/INT.P4/**` 与本报告，未改生产 RTL/约束/IP/构建脚本
- 本报告路径：`workflow/runs/20261026-2138_fpga-integrated-delivery/test-reports/INT.P4-r1-integrated.md`
- r1 证据目录：`workflow/runs/20261026-2138_fpga-integrated-delivery/test-reports/INT.P4/r1/**`

## 1. 本任务范围与规划冻结门槛

按 `dispatch.json`（INT.P4 gates/td_policy）与 `dev-plan.md` §3 INT.P4（2026-10-27 冻结）：

| G 层 | 规划冻结门槛（要点） | 本轮适用性 |
|---|---|---|
| G0 | 顶层接口/单位/模式/时钟/复位冻结且与 RTL 一致；A1U1 与 R10F 分离；RAW/Y8 区分 | 适用 |
| G1 | 同一 manifest 下 P1/P2/P3 回归重跑 PASS + 集成 TB 真实 DUT PASS（背压、abort、A disabled、B 优先、身份/释放、描述符/长度/尾拍/完成/释放、RAW 旁路干净）；A1U1 样例解码通过；须有独立判据 | 适用 |
| G2 | 隔离目录综合必做；clk 187.5MHz 下 WNS/TNS≥0、hold≥0、0 违例、资源在器件内、ERAM+CWC≤300；布线条件允许才做 | 适用（综合必做；布线条件） |
| G3 | `not_run + awaiting_hardware`（无集成 bit/板窗） | 规划已冻结为 not_run（无板级集成顶层/ADC/bit，不伪造） |
| G4 | `not_run`（后置，仅记录差距） | 规划已冻结为 not_run（流水深度 1 帧、长稳/性能后置） |
| G5 | manifest、协议、构建入口、解码工具、样例、最短步骤齐全且与证据一致；RK 真实 PCIe 仍待联调 | 适用 |
| bit | 本轮 not_run；b20 bit 是独立历史候选，不是本集成交付 | 规划已冻结 |

TD 政策：工程只建在 `INT.P4/td/`；synth≤2、route≤1、bitgen=0、CWC=0、downloads=0、Flash=0；不得写 `D:/TD/**`、不得动 b18/b19/b20；不得伪造 ADC/引脚/时序。

## 2. 三维与 G 层结论

| 维度 | 适用性 | 结果 | 主要依据 |
|---|---|---|---|
| functional | 适用 | **pass** | T1–T6（mode4/mode1，65/65 检查）、测试者 S1–S5、P1/P2/P3 TB、独立 oracle 与负对照全部通过；S5 反压无死锁且内容逐字节匹配独立模型 |
| engineering | 适用 | **fail** | manifest/哈希/候选绑定通过；但 TD 综合 setup 有 **330 个违例端点**（WNS −1.549ns、TNS −271.427ns），不满足 G2；route/bit/CWC/download 均 not_run；综合 harness 自身还有未驱动 DDR 握手与完整性缺口 |
| system | 适用 | **fail** | 接口/通路已接通、P1/P2/P3 生产路径回归通过；但 G5 交付一致性仍有可复核错误（manifest/result/build-entry 对负 slack 端点数和遗留文件的描述与实际不符），且 manifest 未绑定实际参与综合/仿真的 10 个 img 源文件 |

| G 层 | 结果 | 说明 |
|---|---|---|
| G0 | **pass** | 顶层只有 `clk`/`rst_n`；单 clk 域；SDC 仅一条 `create_clock -period 5.333`，无 false_path/multicycle/CDC；A1U1 与 R10F 分离；`m_is_raw` 与 `pk_*` 分离 |
| G1 | **pass** | 见 §5：T1–T6 真实执行；S1–S5 通过；P1/P2/P3 TB 与工具复跑通过；A1U1 独立 oracle + 负对照通过；T6 变异负对照证明判据可发现目标缺陷 |
| G2 | **fail** | `flow.status`：Setup WNS −1549ps / TNS −271427ps / NUM_FEPS **330**；Hold 0 违例；IO 42/286、ERAM 32/300、CWC 0、reg 4489、slice 9592/71680、DSP 14、STA coverage 96.53%；route=not_run，bitgen/CWC/download/Flash=0 |
| G3 | not_run | awaiting_hardware（无集成 bit/板窗；不伪造） |
| G4 | not_run | 后置，仅记差距 |
| G5 | **fail** | 交付物主体存在且哈希绑定，但存在可复核的一致性/完整性问题（D5/D6，见 §7）：manifest 说“10 条负 slack 端点”而日志是 330；result-r1 说遗留文件“删除”而文件仍在；build-entry 说 img 9 个而实际编译 10 个；manifest 未绑定 10 个 img 源文件；候选目录还有未登记的 `work/` 目录 |
| honesty | **pass** | 未发现 bit/上板/真实 PCIe/A 路上板的通过声明；b20 bit 未被当作本集成交付；G2 明确记 fail，route/bit/CWC 明确记 not_run |

## 3. 实际执行命令与证据

工作目录 `/` 均为 `D:\fpga\ph1p100`（仿真在测试者自有 work 库中重编译冻结候选）；日志在 `test-reports/INT.P4/r1/`。没有运行的命令不列入本表。

| # | 命令（实际执行） | 退出码/文本判定 | 证据 |
|---|---|---|---|
| 1 | `python .../r1/verify_manifest_r1.py` | exit 0；`VERIFY_MANIFEST PASS`；112 条 union 记录、P1/P2/P3 共 18 个声明文件、A1 4 文件、6 份 docs、40 条 TD 记录全部匹配；仅 1 条已记录 override；无未登记**文件** | `r1/manifest_verify.log` |
| 2 | `powershell -File .../r1/compile.ps1`（vlog 6 候选 + b20 4 + img 10 + 4 个 TB + 测试者 TB） | exit 0；`COMPILE PASS` | `r1/sim/work/_info`、`r1/compile.ps1` |
| 3 | `vsim -c -do "run -all; quit -f" tb_integrated_delivery_top +MODE=4 +SAMPLE=1 +SAMPLE_DIR=.../r1/ev4` | vsim exit 0；文本 `TB_INTEGRATED_DELIVERY_TOP PASS`；`SAMPLE_WRITTEN ... payload=3965` | `r1/run_dev_mode4_default.log` |
| 4 | `... +MODE=4 +SAMPLE=0 +EXTRA=1` | exit 0；`TB_INTEGRATED_DELIVERY_TOP PASS`；**65 ok / 0 fail**；T1–T6 全部出现 | `r1/run_dev_mode4_extra.log` |
| 5 | `... +MODE=1 +SAMPLE=0 +EXTRA=1` | exit 0；`TB_INTEGRATED_DELIVERY_TOP PASS`；**65 ok / 0 fail**；T1–T6 全部出现；T1 Y8 `m_beats=768 sof=1 eol=48 eof=1` | `r1/run_dev_mode1_extra.log` |
| 6 | `... +MODE=1 +SAMPLE=1 +SAMPLE_DIR=.../r1/ev1` | exit 0；`TB_INTEGRATED_DELIVERY_TOP PASS`；`SAMPLE_WRITTEN ... payload=3965` | `r1/run_dev_mode1_default.log` |
| 7 | `vsim ... tb_intp4_tester`（测试者自有 TB） | exit 0；`TB_INTEGRATED_TESTER PASS errors=0`；S1–S5 全部 ok；S5 `DRIVE_DONE beats=768`、无 `DRIVE_STALL` | `r1/run_tester_tb.log`、`r1/evidence/tester_*` |
| 8 | `python .../oracle_sample.py --status ... --raw tester_raw1.bin --stream tester_stream1.bin --drain tester_drain1.bin --rawA tester_raw5.bin --streamA tester_stream5.bin` | exit 0；`ORACLE PASS`；`A_PATH_CONTENT MATCH`（S5 raw 3840 字节、0 失配、zlib 解压==DUT raw==独立模型） | `r1/oracle_tester_dumps.log` |
| 9 | `vsim tb_raw10_packer`；`tb_aplus_pcie_egress_adapter`；`tb_dual_channel_capture_scheduler` | 各 exit 0；`TB_RAW10_PACK PASS`、`TB_APLUS_PCIE_EGRESS_ADAPTER PASS`、`TB_DUAL_CHANNEL_CAPTURE_SCHEDULER PASS` | `r1/r1_p1_tb_raw10_packer.log`、`r1/r1_p2_tb_egress.log`、`r1/r1_p3_tb_scheduler.log` |
| 10 | `python tools/integrated_delivery/raw10_pack.py`；`dual_channel_schedule.py`；`a1u1_decode.py <frozen> 4096`；`verify_integrated_sample.py <frozen>` | 全部 exit 0；`RAW10_PACK PASS`、`DUAL_CHANNEL_SCHEDULE PASS`、`A1U1_DECODE OK`、`VERIFY_INTEGRATED_SAMPLE PASS` | `r1/r1_py_*.log` |
| 11 | `python .../r1/run_p1_tool_isolated_r1.py`（重定向输出，不写冻结 evidence） | exit 0；`INT.P1_VERIFY PASS`；重算 `golden_input_processing.json`=`2c420c86…`、`verify_report.json`=`7e257d07…`，与冻结文件逐字节相同 | `r1/r1_p1_verify_input_processing.log` |
| 12 | `python .../r1/oracle_sample_r1.py --sample <frozen> --raw <frozen> --json <frozen> --selftest` | exit 0；`ORACLE PASS`；负对照（payload 翻 1 字节）被 stream CRC 与 zlib 拒绝 | `r1/oracle_frozen_sample.log` |
| 13 | 变异负对照：把冻结顶层 `store_wr_last`/`commit_ok` 的 `int_ok_r` 门控去掉（仅测试副本，不写生产），重编译后重跑 `+MODE=4 +SAMPLE=0 +EXTRA=1` | vsim exit 0；文本 `TB_INTEGRATED_DELIVERY_TOP FAIL errors=7`；T6 的 7 项检查全 FAIL（含 not exported） | `r1/mut/mut_noguard_extra.log`、`r1/mut/integrated_delivery_top_noguard.v` |
| 14 | TD 只读判读：`syn_gate_timing.rpt`、`syn_gate_area.rpt`、`int_p4_Runs/syn_1/{flow.status,run.log}`、`td_01_synth_console.log` | 未重跑 TD（本包 synth 额度已用尽；测试者不继承/不扩额度）；见 §6 | `INT.P4/td/**`（manifest 已绑定） |

说明：`vsim` 退出码 0 不等于 PASS；本报告以日志文本为准。TD 未由测试者重跑；测试者不消耗/不转移开发额度。

## 4. 独立判据与独立复现

开发自述不作为判据。本轮至少使用五项与开发不同的判据：

1. **测试者自有综合 TB**（`test-reports/INT.P4/tb_intp4_tester.v`，r0 已有，r1 重编译）：不依赖开发 TB 的场景表，独立驱动 A/B、独立 host/DDR 模型，dump `pk`/`ap`/`drain` 字节。S1–S5 全部通过；S5 正是 r0 失败的反压场景，r1 无死锁。
2. **独立 A1U1/RAW10 重建**（`oracle_sample_r1.py`，不 import 开发代码）：用 `struct`/`binascii.crc32`/`zlib` 解析 44B 头、重算 header/stream CRC，并按采集像素公式从零生成 packed RAW10 与 `.raw` 逐字节比较。冻结样例与 S5 dump 均 `ORACLE PASS`；负对照（翻 1 字节）被 CRC/zlib 拒绝，证明判据有效。
3. **r0→r1 差分**：同一测试者 TB 的 S5 在 r0 候选上 `DRIVE_STALL beat=760/768`、`FAIL errors=1`（`test-reports/INT.P4/regression/tester_integrated.log`，r0 证据），在 r1 候选上 `PASS errors=0` 且 S5 内容 `A_PATH_CONTENT MATCH`。这直接覆盖 r0 D2 的“反压死锁 + 已提交帧损坏”，不是开发 TB 的自比较。
4. **T6 变异负对照**：把 r1 新增的帧完整性门控从测试副本中去掉后，T6 的 7 项检查全部失败（含 `not exported`）。这证明 T6 不是空跑，能发现“截断帧被当成功帧提交”的目标缺陷；冻结候选上 T6 全 ok。
5. **独立 manifest 校验器**（`verify_manifest_r1.py`，不调用开发 `gen_manifest_intp4.py`）：逐条重算 union 112 条记录、P1/P2/P3 各自 manifest 及其声明文件、A1 只读 4 文件、docs、TD 日志；对 P1 的 `integrated_input_processing_top.v` 新版本按 manifest 记录的 `source_version_overrides` 处理，未把旧哈希当漂移。

## 5. 功能结果（functional）

### 5.1 通过项（同一冻结候选，RTL 仿真 64×48）

| 场景 | 判据 | 结果 |
|---|---|---|
| T1 B 单帧（mode4，RAW 旁路） | 开发集成 TB + 测试者 S1 + oracle | PASS：raw_len 3840、stream_len 3965、payload==stream、描述符 4096/身份/释放；`m_is_raw=1`；RAW 监视 768 拍逐拍位精确 |
| T2 A 单帧 + 监视反压 + DDR 写停顿 | 开发集成 TB T2（mode4 与 mode1 各一遍） | PASS：无死锁；`pk beats=768`；`stream_len==golden 3965`（mode4）；RAW 监视 bit-exact；Y8 768 拍/sof1/eol48/eof1（mode1）；release completed、arm 恰 1 次 |
| T3 abort（beat 120） | 开发集成 TB T3 | PASS：failed release、身份/seq 匹配、无 arm、store dropped、sched failed |
| T4 A 禁用 + B 优先 → 使能 A | 开发集成 TB T4 | PASS：B 获授、A 未获授；使能后 A 获授并完成；sched completed=2 |
| T5 错误 ACK → 正确 ACK | 开发集成 TB T5 | PASS：错误 ACK 不释放且 adapter err 计数；正确 ACK 完成释放 |
| T6 截断帧（EOF 在 700/768） | 开发集成 TB T6 + 变异负对照 | PASS：failed release、无 arm、not published/exported、dropped、aborted、committed=0；变异后 7 项全 FAIL，判据有效 |
| 测试者 S1 B 单帧 | 测试者 TB + 独立 oracle | PASS：描述符/长度/尾拍/drain/release 全字段匹配；`pk==模型`、zlib 解压==`pk` |
| 测试者 S2 无复位第二帧 | 测试者 TB | PASS：再次 grant/commit/arm/release |
| 测试者 S3 `a_enable=0` | 测试者 TB | PASS：A 全程未获授、sched accepted 不变 |
| 测试者 S4 A 单帧（复位后、m_ready 恒定） | 测试者 TB | PASS：grant/commit/release（camera=0） |
| 测试者 S5 A 单帧 + `m_ready` 间隙 | 测试者 TB + 独立 oracle | PASS：无 `DRIVE_STALL`、commit=1、release；S5 raw 3840 字节与独立模型 **0 失配**；zlib 解压==raw==模型；stream_len=3966 是 seed `0xA500` 内容对应的合法压缩长度（不是损坏） |
| mode1/mode4 A1U1 样例一致性 | 测试者重跑并逐文件 SHA256 | mode1 与 mode4 的 `.a1u1`/`.raw`/`.json` 三文件哈希完全相同，且等于冻结样例 `79e35f28…`/`1357408f…`/`76d88910…` |
| A1U1 冻结样例 | 独立 oracle、负对照 | PASS：header/stream CRC、zlib、pattern-derived raw 全部通过；负对照被拒绝 |
| P1/P2/P3 既有 TB | 测试者重编译重跑 | PASS：`TB_RAW10_PACK`、`TB_APLUS_PCIE_EGRESS_ADAPTER`、`TB_DUAL_CHANNEL_CAPTURE_SCHEDULER` |
| P1/P2/P3 Python 工具 | 测试者重跑 | PASS：`RAW10_PACK`、`INT.P1_VERIFY`（重算 evidence 与冻结哈希相同）、`DUAL_CHANNEL_SCHEDULE`、`A1U1_DECODE`、`VERIFY_INTEGRATED_SAMPLE` |

### 5.2 functional 未测/不外推

- 仅 64×48 缩尺；1920×1080 全尺寸未仿真，不把缩尺结果外推为全尺寸吞吐/时序。
- Y8/高斯/HE 只做结构、marker、非零数据与选路检查；算法像素级内容（高斯 3×3 边界、HE）未逐像素独立核对（P1/P2/P3 各自包的历史判据不等于 P4 全尺寸）。
- 看门狗（`FRAME_WD=0x0400_0000`）未单独注入“源丢 EOF”测试；T6 只覆盖提前 EOF。
- 双路自由运行/每通道暂存未实现（协议已注明），真实自由运行双相机需补暂存。
- 不声称真实 PCIe/RK、bit、上板、A 路上板通过。

## 6. 工程/TD 结果（engineering）

### 6.1 实际日志判读（只读，不重跑 TD）

来源：`INT.P4/td/syn_gate_timing.rpt`、`syn_gate_area.rpt`、`int_p4_Runs/syn_1/flow.status`、`run.log`、`td_01_synth_console.log`（均在 r1 manifest 中绑定）。

| 项 | 实际值 | 门槛 | 判定 |
|---|---|---|---|
| 综合完成 | `INT_SYN_RUN_COMPLETE`（console）；无 `SYN-8228` | 必做 | 完成 |
| IO | 42 / 286 | ≤286 | 通过（仅指 synth harness 的 IO；IO 时序未约束，G2 gap） |
| ERAM + CWC | 32 + 0 | ≤300 | 通过 |
| hold | HWNS/HTNS 0.000/0.000；0 hold endpoints | ≥0 | 通过 |
| setup | SWNS −1.549ns，STNS −271.427ns，**330 Viol Endpoints / 13481 Total Endpoints** | ≥0，0 违例 | **未通过** |
| 资源 | reg 4489；slice* 9592/71680；DSP 14；PLL 0 | 器件内 | 通过 |
| STA coverage | 96.53% | 记录 | 有 3.47% 未覆盖；IO 时序未约束 |
| route | 0（未布线） | 条件（综合通过才允许，最多 1 次） | not_run（G2 未通过，正确） |
| bitgen / CWC / download / Flash | 0 / 0 / 0 / 0 | 0 | 未做 |

最差路径（报告原文）：Begin `u_dut/u_p1/u_algo/u_obuf_gau/count_reg[0].clk` → End `u_dut/u_p1/u_algo/u_front/u_row/rb0_reg[0].d`；`Data Path Delay 6.818ns (cell 2.619 / net 4.199)`，fanout 320，8 级逻辑，setup slack −1.549ns。10 条打印路径是同一 16-bit 目的总线 `rb0_reg[0..15]` 的多个 bit，不是“10 个负 slack 端点”；真实违例端点是 **330**。

**最差路径归属复核**：起点/终点都在 DUT 的 `u_p1/u_algo` 内，不在综合 harness 顶层；但延迟表中两个中间 LUT 的 netlist 标签是 `u_aplus/u_core/blk_full1_reg_syn_*`（很可能是 TD retiming/重命名后的标签），因此“整条路径都在 P1 三算法 ready 链”是开发解释，不是报告直接证明。可以确认的是：这是 DUT 内部 P1→行缓冲方向的 setup 违例，G2 fail 不因 harness 而消失。

### 6.2 工程缺陷/差距（本轮未修复）

**E1（G2，硬门槛）setup 未收敛**：330 个 setup 违例端点，WNS −1.549ns、TNS −271.427ns。按冻结门槛必须 fail；route/bit/CWC/download 保持 not_run/0。下一最短动作是收敛 `u_p1/u_algo`（最差路径 6.8ns，4.2ns 为 net、fanout 320）的 ready/行缓冲路径，再在额度内重综合；不得把 `INT_SYN_PERIOD_WNS=2.533` 当作 setup 通过。

**E2（G2 证据完整性）综合 harness 不是完整的同候选签核**：
- `run.log` 有 `HDL-5314 WARNING: net 'ddr_awready'/'ddr_wready'/'ddr_arready'/'ddr_rvalid'/'ddr_rdata[255]' does not have a driver`（`integrated_delivery_synth_wrap.v` 第 59/60 行）。这些是 DUT 的 DDR 从口输入，未驱动意味着 A+ store/DDR 仲裁/排空路径在综合中被常量传播/裁剪，STA 不覆盖该接口。
- `syn_gate_area.rpt` 的层次表中没有单独的 `u_egress`/`u_arb` 行（其逻辑并入 `u_dut` 残余），P2 egress 与 DDR arbiter 的资源/时序不能从报告独立核对。
- manifest/build-entry 写“片上 DDR 模型”，但实际 ready/rvalid/rdata 未驱动；这是文档过度描述，不是伪造 ADC/引脚/时序。
- 该 harness 是 `tools/integrated_delivery/synth/` 下的综合专用 RTL，不在 dev-plan 列举的“脚本/TB/SDC/TCL/样例/证据”类型内（虽在 dispatch 宽写范围内）。G2 的 42 IO/32 ERAM 数字只能代表 harness，不是板级/完整候选签核；G2 fail 的 P1 路径仍有效。

**E3（过程/计数）synth 额度超包分配**：
- r0 已用 1 次有效 synth（另有 1 次未建工程）；r1 又用 2 次（03:20:58 一次被拒、03:24:33 一次作为 G2 证据），总计 **3 次有效 synth**，超过 INT.P4 `synth_max=2` 的包分配。全局 `execution_limits.synth_max=3` 未超，但包额度已超 1 次；剩余额度不转移/不继承。
- r1 第一次被拒 run 的 timing report 未保留，只有 TD 会话日志；其“最差路径在 harness `%480`”的说明不能独立复核。`01_synth.tcl` 用 `Slack : -` 行数统计，得到 `INT_SYN_NEGATIVE_SLACK_ENTRIES=10`，而真实统计是 `330 Viol Endpoints`；manifest/result/build-entry 重复了 10 这个错误计数。

**E4（manifest 完整性）综合/仿真的 10 个 img 源文件未被哈希绑定**：
- `run_integrated_sim.ps1`、`01_synth.tcl`、`int_p4.prj` 都编译 `fpga/csi2/src/img/*.v`（10 个），但 r1 manifest 的 `new_files`/`p1p2p3_hash_verification`/`readonly_a1_inputs` 均未包含它们。本测试者已记录其当前 SHA256 到 `r1/compiled_unbound_inputs.txt`；测试期间无变化（mtime 2026-10-17），但这不是 manifest 证明。若这些文件变动，当前 manifest 无法发现，违反“同一候选”完整性。

## 7. 系统/交付一致性（system）

### 7.1 已接通/接口

- 捕获 A/B → P1 输入处理 → b20 r0 A+ 核 → A+ 槽存储 → DDR 仲裁 → P2 egress adapter → PCIe 描述符面；P3 scheduler 提供 A/B 身份、`a_enable` 门控、B 优先/轮转、全字段 release；host ACK → slot_release → drain → release 闭环。
- P1/P2/P3 生产文件哈希与各自 manifest 一致（P1 的 `integrated_input_processing_top.v` 是 r1 显式新版本，manifest 记录旧/新哈希与 override 原因；P2/P3 无变化）。P1/P2/P3 回归通过，说明新增集成通路未破坏原 RAW/三算法。
- 顶层实例均为真实冻结模块（`u_aplus/a1_frame_top`、`u_core/a1_deflate_core`、`u_store/a1_ddr_slot_store`、`u_arb/a1_ddr_arb2`、`u_egress/aplus_pcie_egress_adapter`、`u_p1/img_algo_parallel_top`、`u_sched/dual_channel_capture_scheduler`），未发现 stub/placeholder。

### 7.2 G5 交付一致性问题（导致 system fail）

- **D5a 负 slack 端点计数错误**：manifest `gates.G2`、`result-r1.md` §4、`INT.P4-build-entry.md` §3 都写“10 条负 slack 端点”；`syn_gate_timing.rpt` 的 Statistics 与 `flow.status` 都是 **330 Viol Endpoints**。10 只是“Report Scheme: 10 end point(s) per path group”的打印条数；`01_synth.tcl` 的正则按打印的 `Slack : -` 行计数，产生了这个错误指标。
- **D5b 遗留文件描述错误**：`result-r1.md` §1 写“候选目录 2 个遗留文件删除并登记”，但 `fpga/csi2/src/integrated_delivery/sim_output.txt`、`transcript` 仍在（mtime 00:08/00:16，早于 P4），manifest `legacy_untracked` 也明确写“deletion is blocked ... registered instead”。实际“登记”成立，“删除”不成立。
- **D5c build-entry 文件数错误**：`INT.P4-build-entry.md` 写“img 9 文件”，实际 `fpga/csi2/src/img/*.v` 有 **10** 个（algo_obuf、algo_rowwin3、algo_rowwin_reader、bayer_raw10_demosaic4、gray8_gaussian3x3_frame、gray8_gaussian3x3_stream、gray8_he_cdfmin_frame、img_algo_parallel_top、img_algo_top_g2、rgb8_gray_stream）。
- **D5d manifest 未绑定 img 源**：见 E4；这是“完整 manifest”缺口。
- **D5e 候选目录未登记 `work/`**：`fpga/csi2/src/integrated_delivery/work/` 是 6 个文件、574343 字节的旧 ModelSim 库（mtime 00:16，早于 P4），未在任何 manifest 中登记；不是本轮新增，但候选目录“无未登记产物”仍不成立。
- **D5f 文档覆盖范围**：protocol/build-entry/shortest-steps 与证据总体一致；`-Full` 已真的运行 P1/P2/P3 TB（本测试者独立复跑亦通过）。上述 D5a–D5e 是可修复的文档/清单问题，不是功能失败。

### 7.3 板级/发布边界

- G3/G4：not_run + awaiting_hardware；无集成 bit/板窗。
- bitgen/CWC/download/Flash：0；无 `*.bit`/`*.cwc` 产物；b20 bit 是独立历史候选，不是本集成交付。
- RK 真实 PCIe 传输：未做，仍待联调；样例只是 RTL 仿真字节。
- 未写 `D:/TD/**`，未动 b18/b19/b20 目录与计数；未操作硬件/COM/JTAG/Flash。

## 8. 输入漂移与边界核对

- 测试前后 `INT.P4-r1-manifest.json` SHA256 均为 `CFFCF54D…`；冻结样例三文件哈希不变（`79e35f28…`/`1357408f…`/`76d88910…`）。
- 独立校验：union 112 条记录全部 path/sha256/size 匹配；P1/P2/P3 引用 manifest 自身哈希及其 18 个声明文件匹配（P1 的 `integrated_input_processing_top.v` 按记录的 override 处理，实际新哈希 `8cd7d35b…` 与 manifest `new_files` 一致）；A1 四文件 `cda28c…`/`a91c2e…`/`6c619c…`/`b84019…` 与 dispatch 冻结值一致；6 份 docs 全部存在且哈希匹配；40 条 TD 记录匹配；`stopped_modifying=true`；`drift_count=0`。
- 测试期间：`D:/TD` 无 00:50 之后修改的文件；b20 目录无 00:50 之后修改的文件；`tools/td`、`tools/pcie_integration`、`fpga/csi2/pcie_integration`、`upstream/.../codec`、`fpga/csi2/src/img` 均无 00:50 之后修改；`workflow/tasks.json` mtime 仍为 2026-10-26 02:03；无 `pnmain`/TD 进程；未杀他人 vsim 进程。
- 证据复用说明：测试者自有的 `oracle_sample.py`、`tb_intp4_tester.v`、`run_p1_tool_isolated.py` 工具可在“同哈希 + 绑定新 manifest”时复用；r0 的 FAIL 结论、r1 的 PASS 日志不得跨候选拼接。注意：本次 r1 重跑测试者 TB 时，其硬编码路径 `test-reports/INT.P4/evidence/tester_*.bin/tester_status.txt` 覆盖了 r0 的同名 dump；r0 的文本日志（`regression/tester_integrated.log`）和 r0 报告仍在，但 r0 原始二进制 dump 已不可恢复。r1 dump 已复制到 `r1/evidence/`。

## 9. 已接通 / 已验证 / 阻塞 / 下一最短动作

- **已接通**：A/B 捕获 → P1 → A+ 核/槽存储 → DDR 仲裁 → P2 egress → 描述符/身份/完成/释放面；P3 身份/门控/释放；host ACK→drain→release 闭环（B 单帧、B 第二帧无复位、A 单帧、A 反压单帧）。
- **已验证（独立判据）**：T1–T6 真实执行；S1–S5；S5 反压无死锁且内容逐字节匹配独立模型；mode1/mode4 样例哈希一致；A1U1 独立重算 + 负对照；P1/P2/P3 TB 与工具；T6 变异负对照；manifest 全量哈希与无漂移；TD 日志只读判读（G2 fail、330 端点）。
- **阻塞/未通过**：
  1. G2 setup 未收敛（330 端点，WNS −1.549/TNS −271.427），route/bit/CWC 不能做；
  2. G5 交付一致性（D5a–D5e）需修正；
  3. 综合 harness 的 DDR 未驱动/层次不完整，不能作为完整同候选签核；
  4. synth 包额度已超（3 vs 2），下一轮需原规划明确额度；
  5. 板级/RK/bit/A 路上板均未做（规划冻结的 not_run/待联调）。
- **下一最短动作（按顺序）**：
  1. 由原开发在 P1 `u_algo` 的 ready/行缓冲汇合处打拍或解耦（最差路径 6.8ns、net 4.2ns、fanout 320），重跑 functional 回归（T1–T6、S1–S5、P1/P2/P3 TB、oracle），再由原规划在明确额度内重综合；G2 通过后才允许一次 route。
  2. 修 D5a–D5e：把 330 端点写回 manifest/result/build-entry；把 result-r1 的“删除”改为“登记未删除”；build-entry 的 img 数量改为 10；把 10 个 img 源文件纳入 manifest；登记/清理候选 `work/`。
  3. 若继续用 synth harness，补驱动 `ddr_awready/ddr_wready/ddr_arready/ddr_rvalid/ddr_rdata`（或明确声明 DDR 路径不在 G2 覆盖内），并修正“DDR 模型”描述；否则改用真实顶层 + 自动 IO 的隔离综合。
  4. RK 侧仍按 `a1u1_decode.py` 头定义联调真实 PCIe；本轮不声称通过。

## 10. 未测项与回退

- 未测：1920×1080 全尺寸仿真；HE/高斯逐像素算法正确性；看门狗注入；自由运行双相机每通道暂存；真实 DDR/PCIe IP 适配；route/bit/CWC/download/Flash；板级/长稳/吞吐（G3/G4）。
- 回退：本报告与 `test-reports/INT.P4/r1/**` 只针对 manifest `CFFCF54D…`。若开发修复后重新冻结，旧 r1 功能 PASS 不可直接复用；只有“文件哈希不变且绑定新 manifest”的未受影响项可按 retest 的 reuse 路径复用。不得把 r0 FAIL 结论或 r1 PASS 日志与下一轮不同输入拼接成 PASS。

## 11. retest 元数据

- required_dimensions：`functional`、`engineering`、`system`
- required_checks：
  - manifest 重新冻结并全量哈希复核（P1/P2/P3、A1、new_files、docs、TD、**补齐 10 个 img 源文件**），`stopped_modifying=true`，无漂移；
  - 修复后重跑：测试者 S1（B 单帧）、S2（无复位第二帧）、S3（`a_enable=0`）、S4（A 单帧）、S5（`m_ready` 间隙：不得死锁、不得提交损坏帧、内容逐字节匹配独立模型）；
  - 开发 TB 默认 + `+EXTRA=1`（T1–T6 必须真实执行；T6 变异负对照保持有效）；
  - P1/P2/P3 既有 TB 与 Python 入口复跑；P1 若再改，重跑 P1 回归并更新/说明 P1 manifest 版本；
  - A1U1 样例独立重算（`oracle_sample.py`）+ 负对照；mode1/mode4 样例哈希一致；
  - TD 综合：clk 5.333ns 下 WNS/TNS≥0、hold≥0、**0 违例**、ERAM+CWC≤300、IO≤286（若仍用 harness，须补 DDR 驱动并说明覆盖边界）；route 条件执行并绑定最终 DB/报告；bitgen/CWC/download/Flash 保持 0；
  - 文档/manifest/build-entry/shortest-steps 一致性（特别是 330 端点、遗留文件、img 数量、候选 work 目录）；未伪造引脚/ADC/时序；未写 `D:/TD/**`、未动 b20 目录与计数。
- input_status：`changed`（r1 相对 r0：P1 生产文件、集成顶层、TB、构建脚本、文档、manifest 均变化）；下一轮若改 RTL 仍为 `changed`，仅改文档时为 `same`（但必须绑定新 manifest）。
- reuse_decision_paths（仅以下工具/证据可在“同哈希 + 绑定新 manifest”时复用）：
  - 测试者工具：`test-reports/INT.P4/r1/verify_manifest_r1.py`、`oracle_sample_r1.py`、`run_p1_tool_isolated_r1.py`、`test-reports/INT.P4/tb_intp4_tester.v`；
  - r1 日志：`test-reports/INT.P4/r1/run_dev_mode4_{default,extra}.log`、`run_dev_mode1_{default,extra}.log`、`run_tester_tb.log`、`oracle_tester_dumps.log`、`oracle_frozen_sample.log`、`r1_*`、`mut/mut_noguard_extra.log`（仅在对应文件哈希不变时）；
  - 冻结样例与 `tools/integrated_delivery/evidence/integrated_sample.*`（哈希一致时内容判据可复用）；
  - 不得复用：r0 的 FAIL 结论作为 r1 修复证据；r1 的 PASS 日志用于下一轮不同 RTL；已被 r1 覆盖的 r0 二进制 dump。
- report_paths：`workflow/runs/20261026-2138_fpga-integrated-delivery/test-reports/INT.P4-r1-integrated.md`、`.../test-reports/INT.P4/r1/**`
- manifest_path：`workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4-r1-manifest.json`（SHA256 `CFFCF54D…`）
- blocked：`[]`（无外部设备/工具/权限阻塞；TD 可用、综合已实际运行。G2 是设计/门槛失败，不是 blocked；下一轮额外 synth 需原规划明确额度。G3/G4 为规划冻结的 not_run。）
