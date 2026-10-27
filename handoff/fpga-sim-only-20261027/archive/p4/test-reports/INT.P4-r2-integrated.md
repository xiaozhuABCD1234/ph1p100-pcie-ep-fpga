### 判定：FAIL

# INT.P4 r2 综合验收报告（dimension=integrated）

## 0. 元数据

- task_id：INT.P4（同候选集成交付）
- dimension：integrated（functional / engineering / system 三维由同一测试者核验，不是三个独立视角；未派生代理）
- round：2（round2 修复后复测；repair #2/3）
- run_id：`20261026-2138_fpga-integrated-delivery`
- 工作树：`D:\fpga\ph1p100`（git HEAD `27c596b01cd961dfa9d0850e4fbf879fe249de90`；候选/工具/run 目录是未跟踪产物，实际候选由 manifest 绑定）
- 冻结 manifest：`workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4-r2-manifest.json`
  - SHA256（测试前/测试后一致）：`DFAB7F9D7FF7B7F8FB1D9B4401844F3D76102064C99FC4338192FB8A0C59B32E`
  - `stopped_modifying=true`，`drift_count=0`，`round=2`
  - 上一轮 r1 manifest SHA256 复核：`CFFCF54D…`（与 dispatch 记录一致）
- 工具：ModelSim ALTERA STARTER EDITION vsim 10.5b（2016.10，`D:\intelFPGA\18.1\modelsim_ase`）；Python 3.11.5；Anlogic TD 6.2.3.210850（只读判读 r2 既有日志，未重跑 TD）；Windows
- 测试窗口：2026-10-27 05:03–05:12（本机时间）；测试者只写 `test-reports/INT.P4/r2/**` 与本报告，未改生产 RTL/约束/IP/构建脚本
- 本报告：`workflow/runs/20261026-2138_fpga-integrated-delivery/test-reports/INT.P4-r2-integrated.md`
- r2 证据目录：`workflow/runs/20261026-2138_fpga-integrated-delivery/test-reports/INT.P4/r2/**`

## 1. 范围与规划冻结门槛

按 `dispatch.json`（INT.P4 r2 gates/td_policy/task_allocation）、`dev-plan.md` §3 INT.P4 与 §3.6（2026-10-27 03:57 冻结）：

| G 层 | 规划冻结门槛（要点） | 本轮适用性 |
|---|---|---|
| G0 | 单 `clk`（187.5MHz/5.333ns）、异步低有效 `rst_n`、不新增 CDC/异步 FIFO/时钟；A1U1 vs R10F、RAW vs Y8 分离；派生变体接口/单位不变 | 适用 |
| G1 | 同一 r2 候选一次会话全量回归：dev TB MODE=4/1 默认与 `+EXTRA`（T1–T6）、P1/P2/P3 TB 与 Python 工具、A1U1 解码；派生变体同激励 y8/gau/he 数据序列等价（允许延迟，不允许顺序/sof/eol/eof 变化）；独立判据 | 适用 |
| G2 | 隔离目录综合必做；`flow.status` 的 0 Viol Endpoints、WNS/TNS≥0、hold≥0、ERAM+CWC≤300、资源在器件内、IO≤286、无未驱动 DUT 输入；route 条件 | 适用（综合已跑；布线条件，本轮未跑） |
| G3 | `not_run + awaiting_hardware`（无集成 bit/板窗） | 规划已冻结 not_run |
| G4 | `not_run`（后置，仅记差距） | 规划已冻结 not_run |
| G5 | 真实端点计数、img 10 源绑定、遗留文件/work 登记、编译文件数一致、无虚假删除、无 bit/上板/真实 PCIe/A 路通过声明；RK 待联调 | 适用 |
| bit | 本轮 not_run；b20 bit 不是本集成交付 | 规划已冻结 |

TD 政策：工程只在 `INT.P4/td/`；round2 额外 synth≤3（终身≤6，r0/r1 已用 3）；route≤1（条件）、bitgen=0、CWC=0、downloads=0、Flash=0；不写 `D:/TD/**`、不动 b18/b19/b20；不伪造 ADC/引脚/时序豁免。

## 2. 判定摘要

| 维度 | 适用性 | 结果 | 主要依据 |
|---|---|---|---|
| functional | 适用 | **pass** | 测试者独立重编译重跑：dev TB MODE=4/1 默认与 `+EXTRA` 全部 PASS（extra 65 ok/0 fail）；测试者 TB S1–S5 PASS；派生变体等价 3 seed `CHECK_REF_NEW PASS`；P1/P2/P3 TB 与 Python 工具复跑 PASS；A1U1 独立 oracle + 负对照 PASS；mode1/mode4 样例哈希 = r1 冻结值；T6 变异负对照在 r2 上复现 7 项 FAIL |
| engineering | 适用 | **fail** | manifest/哈希/候选绑定通过；但 G2 setup 仍 **112 个违例端点 / 16770**、**WNS −0.637ns / TNS −69.776ns**（r1：330 / −1.549 / −271.427），不满足 0 违例门槛；route/bit/CWC/download/Flash 均 not_run/0；TD synth 额度 round2 3/3、终身 6/6 用尽 |
| system | 适用 | **pass**（含非阻塞证据卫生残留） | 接口/通路接通、P1/P2/P3 生产路径回归通过；D5a–D5e 全部修正（330/112 真实计数、遗留“登记未删除”、img 10、10 源绑定、`work/` 登记）；无 bit/上板/真实 PCIe/A 路通过声明；残留 E5a–E5c 为日志/交接卫生问题，不影响 G2 数字 |

| G 层 | 结果 | 说明 |
|---|---|---|
| G0 | **pass** | 顶层/RTL 只有 `posedge clk`/`negedge rst_n` 一种边沿形式；SDC 仅一条 `create_clock -period 5.333`，无 false_path/multicycle/clock group；A1U1 与 R10F 分离；`m_is_raw` 与 `pk_*` 分离；派生变体端口与基础模块一致 |
| G1 | **pass**（附记录差距） | 见 §5；同候选回归、等价性、oracle、负对照均通过；HE 对停顿形态的既有敏感性作为差距记录（§5.3），不静默通过 |
| G2 | **fail** | `flow.status`：Setup WNS −637ps / TNS −69776ps / **NUM_FEPS 112**（Total 16770）；Hold 0；IO 42/286；ERAM+CWC 39/300；reg 5832、slice* 10761/71680、DSP 14；STA coverage 95.76%；无 HDL-5314 未驱动 DUT 输入；`u_arb`/`u_egress`/`u_store` 层次可见；route=not_run（G2 未过），bitgen/CWC/download/Flash=0 |
| G3 | not_run | awaiting_hardware（无集成 bit/板窗；不伪造） |
| G4 | not_run | 后置，仅记差距 |
| G5 | **pass** | D5a–D5e 全部可复核通过；build-entry/shortest-steps/protocol 与 r2 证据一致；RK 真实 PCIe 仍待联调 |
| honesty | **pass** | 未发现 bit/上板/真实 PCIe/A 路上板通过声明；b20 bit 明确未当作本集成交付；G2 明确 fail、route/bit/CWC 明确 not_run |

**总体判定：FAIL**。G2 是硬门槛（0 违例、WNS/TNS≥0），当前为 112 端点、WNS −0.637ns/TNS −69.776ns，改善属实但不能写成通过；route/bit 也不能做。

## 3. 实际执行命令与证据

工作目录均为 `D:\fpga\ph1p100`（仿真在测试者自有 work 库重编译冻结候选）；所有日志在 `test-reports/INT.P4/r2/`。未运行的命令不列入本表（TD 未由测试者重跑，见 §6）。

| # | 命令（实际执行） | 退出码/文本判定 | 证据 |
|---|---|---|---|
| 1 | `python .../r2/verify_manifest_r2.py` | exit 0；`VERIFY_MANIFEST PASS`；192 条 union 记录（A1 4 / new_files 22 / img 10 / docs 7 / evidence 66 / td 77 / tool_inputs 4 / legacy 2）+ `legacy_dirs` 1 目录 6 文件；P1/P2/P3 引用 manifest 及其 18 个声明文件；链式 override 802cd752→8cd7d35b→2601fa42 | `r2/manifest_verify.log` |
| 2 | `powershell -File .../r2/compile.ps1`（vlog 22 核心源 = 候选 6 + 派生 2 + b20 4 + img 10；TB 6 = 5 开发 TB + 测试者 TB） | exit 0；`COMPILE PASS` | `r2/compile_console.log`、`r2/compile_core.log`、`r2/compile_tb.log` |
| 3 | `vsim -c -do "run -all; quit -f" tb_integrated_delivery_top +MODE=4 +SAMPLE=1 +SAMPLE_DIR=.../r2/ev4` | vsim exit 0；`TB_INTEGRATED_DELIVERY_TOP PASS`；27 ok / 0 fail；`SAMPLE_WRITTEN payload=3965` | `r2/run_dev_mode4_default.log` |
| 4 | `... +MODE=4 +SAMPLE=0 +EXTRA=1` | exit 0；PASS；**65 ok / 0 fail**；T1–T6 全部出现 | `r2/run_dev_mode4_extra.log` |
| 5 | `... +MODE=1 +SAMPLE=1 +SAMPLE_DIR=.../r2/ev1` | exit 0；PASS；26 ok / 0 fail；`SAMPLE_WRITTEN payload=3965` | `r2/run_dev_mode1_default.log` |
| 6 | `... +MODE=1 +SAMPLE=0 +EXTRA=1` | exit 0；PASS；**65 ok / 0 fail**；T1 `m_beats=768 sof=1 eol=48 eof=1` | `r2/run_dev_mode1_extra.log` |
| 7 | `vsim ... tb_intp4_tester`（测试者自有 TB，r2 副本仅改 dump 路径） | exit 0；`TB_INTEGRATED_TESTER PASS errors=0`；S1–S5 全 ok；S5 `DRIVE_DONE beats=768`、无死锁、`commits=1`、stream 3966（seed 0xA500 合法长度） | `r2/run_tester_tb.log`、`r2/evidence/tester_*` |
| 8 | `vsim tb_img_algo_equiv_p4 +SEEDMODE=0/1/2` | 3 次均 exit 0；`CHECK_REF_NEW PASS`、`TB_IMG_ALGO_EQUIV_P4 PASS`；`EQUIV_COUNTS` 1720/1703/1720；`CONTROL_REF_REF2 diffs=98/99/48`（仅 stream 2=HE） | `r2/equiv_seedmode{0,1,2}.log` |
| 9 | `vsim tb_raw10_packer`；`tb_aplus_pcie_egress_adapter`；`tb_dual_channel_capture_scheduler` | 各 exit 0；`TB_RAW10_PACK PASS`、`TB_APLUS_PCIE_EGRESS_ADAPTER PASS`、`TB_DUAL_CHANNEL_CAPTURE_SCHEDULER PASS` | `r2/r2_p1_tb_raw10_packer.log`、`r2/r2_p2_tb_egress.log`、`r2/r2_p3_tb_scheduler.log` |
| 10 | `python tools/integrated_delivery/raw10_pack.py`；`dual_channel_schedule.py`；`a1u1_decode.py <frozen> 4096`；`verify_integrated_sample.py <frozen trio>`；`.../r2/run_p1_tool_isolated_r2.py`（输出重定向，不写冻结 evidence） | 全部 exit 0；`RAW10_PACK PASS`、`DUAL_CHANNEL_SCHEDULE PASS`、`A1U1_DECODE OK`、`VERIFY_INTEGRATED_SAMPLE PASS`、`INT.P1_VERIFY PASS`；重算 `golden_input_processing.json`=`2c420c86…`、`verify_report.json`=`7e257d07…` 与冻结逐字节相同 | `r2/py_*.log` |
| 11 | `python .../r2/oracle_sample_r2.py --sample <frozen> --raw <frozen> --json <frozen> --selftest` | exit 0；`ORACLE PASS`；负对照（翻 1 字节）被 stream CRC 与 zlib 拒绝 | `r2/oracle_frozen_sample.log` |
| 12 | `python .../r2/oracle_sample_r2.py --status ... --raw tester_raw1.bin --stream tester_stream1.bin --drain tester_drain1.bin --rawA tester_raw5.bin --streamA tester_stream5.bin` | exit 0；`ORACLE PASS`；`A_PATH_CONTENT MATCH`（S5 raw 3840 字节 0 失配，zlib 解压==DUT raw==独立模型） | `r2/oracle_tester_dumps.log` |
| 13 | 变异负对照：r2 顶层副本去掉 `store_wr_last`/`commit_ok` 的 `int_ok_r` 门控（仅测试副本，独立 work_mut 库）重跑 `+MODE=4 +EXTRA=1` | vsim exit 0；文本 `TB_INTEGRATED_DELIVERY_TOP FAIL errors=7`；T6 七项全 FAIL | `r2/mut/mut_noguard_extra.log`、`r2/mut/integrated_delivery_top_noguard.v` |
| 14 | TD 只读判读：`INT.P4/td/{syn_flow.status,syn_gate_timing.rpt,syn_gate_area.rpt,td_01_synth_console.log}`、`syn_r2_run{1,2,3}/`、`int_p4_Runs/syn_1/`、`td_20261027_*.log` | 未重跑 TD（额度 6/6 用尽；测试者不继承/不扩额度）；数值见 §6 | manifest 已绑定；测试者解析记录见本报告 §6 |

说明：`vsim` 退出码 0 不等于 PASS，本报告一律以日志文本为准；无 Fatal/`$stop`/scoreboard 失败。

## 4. 独立判据与独立复现

开发自述不作为判据。本轮使用五项与开发不同的判据：

1. **测试者自有综合 TB**（`test-reports/INT.P4/tb_intp4_tester.v` 的 r2 副本，仅把 6 处 dump 路径改到 `r2/evidence/`，`Compare-Object` 只显示这 6 行差异）：不依赖开发 TB 场景表，独立驱动 A/B、独立 host/DDR 模型；S1–S5 全部通过，S5 反压无死锁且内容与独立模型逐字节一致。
2. **独立 A1U1/RAW10 重建 oracle**（`oracle_sample_r2.py` 与 r1 测试者工具同哈希 `D3A736A1…`，不 import 开发代码；`struct`/`binascii.crc32`/`zlib`）：冻结样例与 S5 dump 均 `ORACLE PASS`；负对照证明能发现坏流。
3. **T6 变异负对照在 r2 上复现**：把 r2 顶层（与 r1 顶层同哈希 `149e89c1…`）的帧完整性门控去掉后，T6 七项全部 FAIL；冻结候选 T6 全 ok。证明 T6 判据有效，不是空跑。
4. **测试者独立 manifest 校验器**（`verify_manifest_r2.py`，不调用开发 `gen_manifest_intp4.py`）：逐条重算 192 条记录、P1/P2/P3 引用 manifest 及其声明文件、A1 4 文件（对照 r1 测试者记录值）、10 个 img 源（对照 r1 测试者 `compiled_unbound_inputs.txt`）、2 个派生变体、`legacy_dirs` 6 文件、链式 override；`stopped_modifying/drift/round/G2-fail` 断言。
5. **r1→r2 差分**：r1 的 330 端点/WNS −1.549/TNS −271.427 与 r2 的 112/−0.637/−69.776 都从各自 `flow.status` 原文读出（非开发文字转述）；r2 最差路径已从 r1 的 `u_front/u_row/rb0_reg` 转到 `u_gau/u_row/rb0_reg`，进步可复核但未达门槛。

另：派生变体“握手 only”用**归一化源码差分**独立复核——`bayer_raw10_demosaic4_p4.v` 相对基础文件只删/改 10 行（模块头 + `pipe_en`/`m_*` 输出接线），新增的是 2 拍弹性级；`img_algo_parallel_top_p4.v` 相对基础只改 17 行（模块头、`u_front` 改派生、插入 `u_stage_b`、输出改由弹性级驱动），数据算术、all-or-nothing 规则、obuf/HE/高斯结构与端口不变。

## 5. functional 结果

### 5.1 通过项（同一 r2 冻结候选，RTL 仿真 64×48）

| 场景 | 判据 | 结果 |
|---|---|---|
| dev TB MODE=4 默认 | 测试者重编译重跑 | PASS：27 ok / 0 fail；样例 payload=3965 |
| dev TB MODE=4 `+EXTRA`（T1–T6） | 同上 | PASS：65 ok / 0 fail；T1–T6 真实执行 |
| dev TB MODE=1 默认 | 同上 | PASS：26 ok / 0 fail；样例 payload=3965 |
| dev TB MODE=1 `+EXTRA`（T1–T6） | 同上 | PASS：65 ok / 0 fail；T1 Y8 `m_beats=768 sof=1 eol=48 eof=1` |
| 测试者 S1 B 单帧 | 测试者 TB + 独立 oracle | PASS：描述符/长度/尾拍/drain/release 字段匹配；`pk==模型`、zlib 解压==`pk` |
| 测试者 S2 无复位第二帧 | 测试者 TB | PASS：再次 grant/commit/arm/release |
| 测试者 S3 `a_enable=0` | 测试者 TB | PASS：A 全程未获授 |
| 测试者 S4 A 单帧 | 测试者 TB | PASS：grant/commit/release（camera=0） |
| 测试者 S5 A 单帧 + `m_ready` 间隙 | 测试者 TB + 独立 oracle | PASS：无死锁、commit=1、release；raw 3840 字节 **0 失配**；zlib 解压==raw==模型 |
| 派生变体等价（`+SEEDMODE=0/1/2`） | 同激励+同输出 ready 形态，dut0=基础 / dut1=派生 | 3/3 `CHECK_REF_NEW PASS`；每流 token 1720/1703/1720、状态计数一致；数据/顺序/sof/eol/eof/abort 标记一致，仅延迟允许 |
| P1/P2/P3 既有 TB | 测试者重编译重跑 | PASS：`TB_RAW10_PACK`、`TB_APLUS_PCIE_EGRESS_ADAPTER`、`TB_DUAL_CHANNEL_CAPTURE_SCHEDULER` |
| P1/P2/P3 Python 工具 | 测试者重跑 | PASS：`RAW10_PACK`、`INT.P1_VERIFY`（重算 evidence 与冻结哈希相同）、`DUAL_CHANNEL_SCHEDULE`、`A1U1_DECODE`、`VERIFY_INTEGRATED_SAMPLE` |
| A1U1 冻结样例 | 独立 oracle、负对照 | PASS：header/stream CRC、zlib、pattern-derived raw；负对照被拒绝 |
| mode1/mode4 样例哈希 | 测试者重跑并逐文件 SHA256 | 两者相同且等于冻结值：`79E35F28…`（a1u1）/`1357408F…`（raw）/`76D88910…`（json） |

### 5.2 派生变体“握手 only”复核

- 等价 TB 的构造经源码复核：dut0/dut1 共用同一组 ready 种子（SEEDMODE 决定），dut2 用另一组；比较函数按 token 序列比较（data + sof/eol/eof/abort + 每流状态计数），因此“增加延迟”不会造成误判，顺序/标记变化会失败。
- `EQUIV_STATUS` 三实例逐流一致（good=2 abort=1 hepub=2 herej=1 gauabt=1）。
- 归一化差分显示派生变体只改握手/输出接线，数据算术与基础模块逐行相同；因此在本轮覆盖范围内可接受“时序 only 派生变体”的主张。

### 5.3 HE ready 形态敏感性（既有差距，必须如实记录）

- 等价 TB 的对照实例 `CONTROL_REF_REF2`（**同一份基础 RTL**，仅输出 ready 序列不同）在 3 个 seed 下分别出现 **98 / 99 / 48** 处差异，全部在 **stream 2 = HE**；差异位置集中在 HE 输出尾部 token，dut0/dut1（同 ready）无差异。测试者独立重跑复现该现象。
- 判断：这**不是** r2 派生变体引入的问题，也不是 P4 本轮冻结门槛的直接失败项——G1 只要求“引入派生变体时给同激励下 y8/gau/he 与原始模块的数据序列等价证据”，当前证据在“同激励 + 同输出 ready 形态”下成立，并且开发/测试者都没有声称“任意背压下像素唯一”。因此**不以此单独阻塞 P4**。
- 但它必须作为**既有差距/风险**保留：`fpga/csi2/src/img/gray8_he_cdfmin_frame.v` 的直方图/映射对停顿形态敏感，意味着
  1. 不能用“结构/marker 检查通过”推断 HE 像素在任意反压下正确或可复现；
  2. 板级真实 DDR/PCIe 动态反压时，HE（mode3）内容可能随停顿形态变化，P4 的“像素语义不变”只能在定义好的 ready 纪律下声明；
  3. 若后续要修，需要放开 `img/**` 只读或另建派生修复，属范围变更，交原规划。
- 本报告不静默通过该项；G1 的 pass 是“冻结门槛 + 显式差距记录”，不是“HE 任意反压已正确”。

### 5.4 functional 未测/不外推

- 仅 64×48 缩尺；1920×1080 全尺寸未仿真，不外推全尺寸吞吐/时序。
- HE 只在算法块等价 TB 中覆盖；集成 TB 只跑 mode1/mode4，HE 集成路径（mode3）与 HE 逐像素模型核对未做；高斯 3×3 边界未逐像素核对。
- 看门狗（源丢 EOF）未单独注入；T6 只覆盖提前 EOF。
- 双路自由运行/每通道暂存未实现（协议已注明）；真实自由运行双相机仍需补暂存。
- 不声称真实 PCIe/RK、bit、上板、A 路上板通过。

## 6. engineering 结果（TD/G2，只按实际日志）

### 6.1 r2 综合证据（run2，绑定的 G2 证据）

来源：`INT.P4/td/syn_flow.status`、`syn_gate_timing.rpt`（Generated Tue Oct 27 04:40:40 2026）、`syn_gate_area.rpt`、`td_01_synth_console.log`，并与 `INT.P4/td/syn_r2_run2/` 同名文件逐哈希一致；r2 run2 的 `run.log` 分析 23 个 verilog 文件（候选 6 + 派生 2 + b20 4 + img 10 + harness 1）。

| 项 | 实际值（日志原文） | 门槛 | 判定 |
|---|---|---|---|
| 综合完成 | `INT_SYN_RUN_COMPLETE`；无 `SYN-8228` | 必做 | 完成 |
| setup 端点 | **112 Viol Endpoints / 16770 Total**（`flow.status NUM_FEPS 112`，报告 Max 行一致） | 0 | **未通过** |
| setup slack | **SWNS −0.637ns / STNS −69.776ns** | ≥0 | **未通过** |
| hold | HWNS/HTNS 0.000/0.000；0 端点 | ≥0 | 通过 |
| IO | 42 / 286 | ≤286 | 通过（仅 harness IO；IO 时序未约束=gap） |
| ERAM + CWC | 39 + 0 = 39 / 300（`#eram 39`、`#fifo20k 0`） | ≤300 | 通过 |
| 资源 | reg 5832、slice* 10761/71680、lut 13009、DSP 14、PLL 0 | 器件内 | 通过 |
| STA coverage | 95.76% | 记录 | 4.24% 未覆盖；IO 时序未约束 |
| 未驱动 DUT 输入 | 无 `HDL-5314`；无 `SYN-5013 Undriven` 指名项（仅有通用 `SYN-5025 WARNING: Using 0 for all undriven pins and nets` 一次，未指名 DUT DDR 从口） | 无 | 通过（源级复核 ddr_* 由 harness 驱动） |
| 层次可见 | `u_arb`=a1_ddr_arb2(5 lut/2 seq)、`u_egress`=aplus_pcie_egress_adapter(129/33/115)、`u_store`=a1_ddr_slot_store(355/129/724) | 可核对 | 通过 |
| 最差路径 | Begin `u_dut/u_p1/u_algo/u_obuf_gau/count_reg[0].clk` → End `u_dut/u_p1/u_algo/u_gau/u_row/rb0_reg[0].d`；`Data Path Delay 5.906ns (cell 2.304 / net 3.602)`；slack −0.637ns | — | 记录 |
| route / bitgen / CWC / download / Flash | 0 / 0 / 0 / 0 / 0 | 0（route 条件） | not_run（G2 未过；无板级集成顶层/ADC，不伪造） |

补充：`Report Scheme: 10 end point(s) per path group` 只是打印条数；真实端点数是 `flow.status` 的 112，r1 的 330 亦是真实统计（r1 文档误写成 10，本轮已在 manifest/result/build-entry/shortest-steps 修正）。

### 6.2 TD 额度与 r2 三次综合

| 运行 | 会话/证据 | 结果 | 用途 |
|---|---|---|---|
| r2 run1 | `td_20261027_042508.log` / `syn_r2_run1/` | 277 端点，WNS −1.483 / TNS −255.655（Total 16697） | 首个修复版（harness 捕获仍组合输出） |
| **r2 run2** | `td_20261027_043708.log` / `syn_r2_run2/` | **112 端点，WNS −0.637 / TNS −69.776（Total 16770）** | **绑定的 G2 证据** |
| r2 run3 | `td_20261027_044634.log` / `syn_r2_run3/` | 112 端点，−0.637 / −69.776（ERAM 行缓冲实验；TD 未接受 `ram_style`，netlist 与 run2 相同） | 实验，未改写结论 |

- **round2 3/3 附加 synth 用尽**，任务终身 6/6（r0/r1 已用 3：`021027` 有效、`032058` 被拒、`032433` 有效；另有 `021001` 未建工程会话不计有效综合）；未做第 4 次、未自扩额度。
- 三次 TD 工程均建在 `INT.P4/td/`（`flow.status` 的 Location 可证）；未写 `D:/TD/**`（03:57 后无修改）；b18/b19/b20 目录与计数未动（03:57 后无修改；`T10.b20-a-timing` 文件 mtime 均早于该时刻）；`workflow/tasks.json` mtime 仍为 2026-10-26 02:03；无 bitgen/CWC/download/route 命令（TD 日志仅有 `save_best_bits` 提示性文字，未执行）。

### 6.3 约束/harness 覆盖边界（未伪造）

- `integrated_core.sdc` 仅一条 `create_clock -name clk -period 5.333 -waveform {0.000 2.667}`；无 false_path/multicycle/clock group。
- `integrated_delivery_synth_wrap.v` 顶层端口仅 `clk`、`rst_n`、`obs[31:0]`、`frame_cnt[7:0]`（42 IO），无 ADC/封装引脚；DDR 从口 `ddr_awready=rst_n`、`ddr_wready=rst_n`、`ddr_arready=rst_n&&!rd_v`、`ddr_rvalid=rd_v`、`ddr_rdata=rd_d`，行为 DDR 模型单 outstanding 读；文件头写明“仅内部寄存器 STA、IO 未约束、不是板级顶层、不伪造 ADC/引脚/时序豁免”。r2 的 `run.log` 无 r1 的 HDL-5314；`u_front/u_algo/u_gau` 下可见派生变体与 `int_p4_elastic_beats`（`u_ofifo`/`u_stage_b`/`u_algo_in`）层次行。

### 6.4 工程/证据卫生残留（不改变 G2 数字，但应修）

- **E5a（证据卫生）**：`INT.P4/td/run.log` 是 **r1 的运行日志**（mtime 03:27:15，内容含 `HDL-5314` 指名 `ddr_awready/ddr_wready/ddr_arready/ddr_rvalid/ddr_rdata`，与 `td/r1-evidence/run.log` 同哈希 `8023b305…`），而顶层 `syn_flow.status`/`syn_gate_timing.rpt`/`syn_gate_area.rpt`/`td_01_synth_console.log` 是 r2 run2 的副本。manifest 把它列入 `td` 且无备注；虽然 build-entry 已明确 G2 证据是 run2、并以 `syn_r2_run2/` 为准，但同一证据包内保留旧失败日志容易被误读为“r2 仍有未驱动输入”。建议改名/移入 `r1-evidence/` 或在 manifest 加 note。
- **E5b（工程 tcl 副本）**：`INT.P4/td/01_synth.tcl`（7504B，mtime 04:44:40）是 run3 实验副本，含两行 `add_files .../algo_rowwin3_p4.v`、`.../gray8_gaussian3x3_stream_p4.v`（实验文件已移出候选目录，现不存在）；绑定/正式的 `tools/integrated_delivery/td/01_synth.tcl`（7336B，mtime 04:51:23）不含这两行。run2 `run.log` 分析 23 个文件（= 正式 tcl 列表），run3 分析 25 个（+2 实验文件）。工程目录副本无法直接重跑，建议在 package 内注明“run3 实验副本，勿用”。
- **E5c（目录混合）**：run3 复用了同一 TD 工程目录，`int_p4_Runs/syn_1/` 现有 run2 的 `flow.status`/`gate.qor` 与 run3 的 `int_p4_gate.timing/area` 混合（mtime 4:40 与 4:50）；权威且自洽的 run2 证据集是 `syn_r2_run2/`。这不影响 G2 判定，但交接时应指向 `syn_r2_run2/`。
- **E5d（非候选副作用）**：`tools/integrated_delivery/__pycache__/*.pyc`（3 个，mtime 22:53/23:22/02:53，均早于 r2，由更早的工具运行产生）未绑定 manifest；属 Python 字节码缓存、非编译源、不影响候选，但严格“无未登记产物”口径下应在后续清理或登记。
- **E5e（操作提示）**：`run_integrated_sim.ps1` 默认 `-Sample 1` 会重写 `tools/integrated_delivery/evidence/integrated_sample.*`（内容确定，哈希不变）；复跑时建议显式 `-Sample 0` 或用 `-SampleDir` 隔离。

## 7. system 结果

### 7.1 已接通/接口

- 捕获 A/B → P1 输入处理（packed RAW10 + 三算法/旁路；r2 新增 2 拍弹性级）→ b20 r0 A+ 核 → A+ 槽存储 → DDR 仲裁 → P2 egress adapter → PCIe 描述符面；P3 scheduler 提供 A/B 身份、`a_enable` 门控、B 优先/轮转、全字段 release；host ACK → slot_release → drain → release 闭环。全部单 `clk`/`rst_n`，无 CDC/异步 FIFO/时钟改动（源码只出现 `posedge clk`/`negedge rst_n`）。
- 顶层实例均为真实冻结模块（`u_aplus/a1_frame_top`、`u_core/a1_deflate_core`、`u_store/a1_ddr_slot_store`、`u_arb/a1_ddr_arb2`、`u_egress/aplus_pcie_egress_adapter`、`u_p1/img_algo_parallel_top_p4`、`u_sched/dual_channel_capture_scheduler`），未发现 stub。
- P1/P2/P3 回归通过，新增弹性级未破坏 RAW 旁路/T1 监视/描述符/释放闭环；S5 RAW 内容逐字节匹配独立模型。

### 7.2 G5（D5a–D5e）复核

| 项 | r1 问题 | r2 实际 | 判定 |
|---|---|---|---|
| D5a 端点计数 | 文档写 10，日志 330 | `endpoint_counts` 写 r1 330 / r2 112；result/build-entry/shortest-steps 均 112（16770 total），`flow.status` 与报告一致 | 通过 |
| D5b 遗留文件 | result 声称“删除”，实际仍在 | manifest `legacy_untracked` 2 文件（`sim_output.txt`、`transcript`）哈希匹配、注明“REGISTERED, NOT DELETED”；result 措辞已改 | 通过 |
| D5c img 数量 | 文档写 9 | build-entry 写 10 并列出名称；manifest `img_source_count=10`；磁盘 `.v` 恰 10 个 | 通过 |
| D5d img 绑定 | 10 源未绑定 | `img_sources` 10 条 sha256+size 全部匹配；与 r1 测试者独立记录逐项相同（证明 `img/**` 未被改） | 通过 |
| D5e work/ 登记 | 未登记 | `legacy_dirs` 登记 `.../work`（6 文件逐一哈希/大小），不删除 | 通过 |
| 编译文件数/入口 | — | 仿真入口 22 核心源 + 6 TB；综合入口 23 源（含 harness）；与 build-entry 一致 | 通过 |

### 7.3 发布边界

- G3/G4：not_run + awaiting_hardware；无集成 bit/板窗。
- bitgen/CWC/download/Flash：0；run 目录无 `*.bit`/`*.cwc`；b20 `a1_board.bit` 是独立历史候选，未被当作本集成交付。
- RK 真实 PCIe 传输：未做，仍待联调；样例仅为 RTL 仿真字节（`.json` 也注明 RTL simulation），`a1u1_decode.py` 可解。
- 未写 `D:/TD/**`、未动 b18/b19/b20 目录与计数；未操作硬件/COM/JTAG/Flash。

## 8. 输入漂移与边界核对

- 测试前后 `INT.P4-r2-manifest.json` SHA256 均为 `DFAB7F9D…`；独立校验 192 条 union 记录全部 path/sha256/size 匹配；P1/P2/P3 引用 manifest（`d6c524f6…`/`b5073d55…`/`9d0dea08…`）及其 18 个声明文件匹配；链式 override 802cd752→8cd7d35b→2601fa42 成立；A1 4 文件 `cda28c…/a91c2e…/6c619c…/b84019…` 与 r1 测试者记录一致；10 个 img 源与 r1 记录一致；2 个派生变体存在且不在 `img/**`；`legacy_dirs` 6 文件匹配；`stopped_modifying=true`、`drift_count=0`。
- 冻结样例三文件哈希不变（`79E35F28…`/`1357408F…`/`76D88910…`），`tools/integrated_delivery/evidence/*` 的 mtime 在测试期间未变（测试只读）。
- 测试期间未修改生产 RTL/约束/IP/构建脚本；`fpga/csi2/src/img`、`tools/td`、`docs`、`upstream` 等在 04:59 后无文件修改；`workflow/tasks.json` mtime 2026-10-26 02:03；无 `pnmain`/TD/vsim 残留进程。
- 说明：仓库对 HEAD 的 `docs/`、`tools/td/`、`workflow/tasks.json` 存在**更早工作**造成的既有修改/未跟踪项（mtime ≤ 2026-10-26），非本任务/本测试产生；本报告不把它们计入 r2 候选。
- 证据复用说明：测试者工具的 r2 副本均“同哈希或仅路径替换”；r1 的 PASS 日志未用于 r2 RTL；r1 TD 报告仅作历史（r2 用 `syn_r2_run2/`）；不拼不同输入 PASS。

## 9. 已接通 / 已验证 / 阻塞 / 下一最短动作

- **已接通**：A/B 捕获 → P1（RAW10 打包、三算法/旁路、r2 输入弹性级）→ b20 A+ 核/槽存储 → DDR 仲裁 → P2 egress → 描述符/身份/完成/释放面；P3 身份/门控/释放；host ACK→drain→release 闭环（B 单帧、无复位第二帧、A 单帧、A 反压单帧）。
- **已验证（独立判据）**：dev TB MODE=4/1 默认+EXTRA（65/0）；测试者 S1–S5；S5 反压无死锁且内容逐字节匹配独立模型；派生变体等价 3 seed；P1/P2/P3 TB 与工具；A1U1 独立 oracle + 负对照；mode1/mode4 样例哈希；T6 变异负对照；manifest 全量哈希与无漂移；TD r2 run2 只读判读（G2 fail、112 端点、无 HDL-5314、层次可见）。
- **阻塞/未通过**：
  1. **G2 setup 硬门槛未过**：112 端点、WNS −0.637 / TNS −69.776（改善但未达 0/≥0）；route/bit/CWC 不能做；
  2. 违例集中在 `algo_rowwin3` 行缓冲读使能/地址路径（`u_front`、`u_gau` 各一份，5.906ns），收敛需改 `fpga/csi2/src/img/algo_rowwin3.v` 或调整 P1 时钟/约束，均属本轮冻结范围外（范围变更/授权）；
  3. **TD synth 额度已用尽**（round2 3/3、终身 6/6）：没有原规划书面新授权就不允许第 4 次综合，因此当前无法用新 RTL 重新证明 G2；
  4. HE 停顿敏感性为既有差距（§5.3），板级动态反压下 HE 像素确定性未定义；
  5. E5a–E5c 证据卫生残留（不影响本轮数字，但交接前应修）。
- **下一最短动作（按顺序）**：
  1. 由原规划决定是否开 round3：若开，需同时（a）书面追加 synth 额度（当前 6/6 已尽，不可自动扩），（b）批准对 `algo_rowwin3` 行缓冲读路径的修复载体（改 `img/**` 或等价派生变体），（c）保持单 5.333ns 时钟与不伪造时序豁免；否则按“G2 未通过”收口，不写 bit/route。
  2. 若继续修复：在 P1 行缓冲读调度/存储形态上收敛（把 READ 地址/使能从同一周期的高扇出使能链中解耦），再在冻结候选上一次综合取证；route 仅在 G2 通过后做 1 次。
  3. 修 E5a–E5c（旧 run.log 重命名/备注、工程 tcl 标注实验副本、`syn_1` 混合目录指向 `syn_r2_run2/`）。
  4. HE 停顿敏感性：由原规划决定是否作为后续独立任务（板级集成线的前置风险），本轮不声称已解决。
  5. RK 侧仍按 `a1u1_decode.py` 头定义联调真实 PCIe；本轮不声称通过。

## 10. 未测项与回退

- 未测：1920×1080 全尺寸仿真；HE/高斯逐像素算法正确性；看门狗注入；自由运行双相机每通道暂存；真实 DDR/PCIe IP 适配；route/bit/CWC/download/Flash；板级/长稳/吞吐（G3/G4）。
- 回退：本报告与 `test-reports/INT.P4/r2/**` 只针对 manifest `DFAB7F9D…`。r1 报告/证据只对应 `CFFCF54D…`；r2 未通过时不得把 r1 PASS 结论当 r2 结论。若后续重新冻结，只有“文件哈希不变且绑定新 manifest”的未受影响项可按 reuse 路径复用；不得把 r0/r1 日志与新 RTL 拼成 PASS。

## 11. retest 元数据

- required_dimensions：`functional`、`engineering`、`system`
- required_checks：
  - manifest 重新冻结并全量哈希复核（P1/P2/P3、A1、new_files、**10 个 img 源**、派生变体、TB/harness/tcl/sdc、docs、TD 证据、legacy/work 登记），`stopped_modifying=true`、无漂移；
  - 修复后重跑测试者 S1–S5（含 S5 `m_ready` 间隙：不得死锁、不得提交损坏帧、内容逐字节匹配独立模型）；
  - dev TB MODE=4/1 默认 + `+EXTRA`（T1–T6 真实执行）；T6 变异负对照仍有效；
  - 派生变体等价（同激励、同 ready 形态；y8/gau/he 顺序/标记不变）或显式算法内容差距；
  - P1/P2/P3 既有 TB 与 Python 入口复跑；A1U1 独立 oracle + 负对照；mode1/mode4 样例哈希；
  - TD 综合：`flow.status` 0 违例、WNS/TNS≥0、hold≥0、ERAM+CWC≤300、IO≤286、无未驱动 DUT 输入、层次可见；route 条件执行并绑定最终 DB/报告；bitgen/CWC/download/Flash 保持 0；
  - 证据卫生：旧 `td/run.log` 不得与 r2 证据混放、工程 tcl 副本标注、`syn_1` 混合目录指向 `syn_r2_run2/`；未伪造引脚/ADC/时序；未写 `D:/TD/**`、未动 b20 目录与计数。
- input_status：`changed`（相对 r1：新增 2 个派生变体与等价 TB、改 P1 `integrated_input_processing_top.v`、harness、tcl、manifest/文档；样例哈希不变）
- reuse_decision_paths（仅“同哈希 + 绑定新 manifest”可复用）：
  - 测试者工具：`test-reports/INT.P4/r2/verify_manifest_r2.py`（需按新 manifest 调整常量）、`oracle_sample_r2.py`（与 r1 工具同哈希 `D3A736A1…`）、`run_p1_tool_isolated_r2.py`、`tb_intp4_tester_r2.v`（与 r1 TB 仅 dump 路径不同）；
  - r2 日志/样例：`test-reports/INT.P4/r2/**`（仅在对应文件哈希不变时）；
  - 冻结样例 `tools/integrated_delivery/evidence/integrated_sample.*`（哈希一致时内容判据可复用）；
  - 不得复用：r1 的 PASS 日志用于新 RTL；r1 TD 报告当作 r2 证据；r0/r1 二进制 dump；不得把不同输入拼成 PASS。
- report_paths：`workflow/runs/20261026-2138_fpga-integrated-delivery/test-reports/INT.P4-r2-integrated.md`、`.../test-reports/INT.P4/r2/**`
- manifest_path：`workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4-r2-manifest.json`（SHA256 `DFAB7F9D7FF7B7F8FB1D9B4401844F3D76102064C99FC4338192FB8A0C59B32E`）
- blocked：`[]`（无外部设备/工具/权限阻塞；G2 是设计/门槛失败，非 blocked。但 TD synth 额度已 `6/6` 用尽，属限制到达：第 4 次综合必须由原规划书面授权，不能由执行角色自扩。）
