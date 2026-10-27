### 判定：FAIL

# INT.P4 r3 综合验收报告（dimension=integrated，repair #3/3 最后一轮）

## 0. 元数据

- task_id：INT.P4（同候选集成交付）；dimension：integrated（functional / engineering / system 由同一测试者核验，不是三个独立视角；未派生代理）
- round：3（round3 实际修复 3/3；round0 FAIL → r1 FAIL → r2 FAIL → r3）
- run_id：`20261026-2138_fpga-integrated-delivery`；工作树 `D:\fpga\ph1p100`（git HEAD `27c596b01cd961dfa9d0850e4fbf879fe249de90`；候选/工具/run 目录为未跟踪产物，判读以 manifest 绑定为准）
- 冻结 manifest：`workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4-r3-manifest.json`
  - SHA256（测试前/测试后复算一致）：`43EBFF3D110234A225DD2A449804BC863F47EC5D7FAE89966C970B5EA9526F1`（与派发文本一致）
  - `round=3`、`stopped_modifying=true`、`drift_count=0`
- 工具：ModelSim ALTERA STARTER EDITION vsim 10.5b（`D:\intelFPGA\18.1\modelsim_ase`）；Python 3.11.5；Anlogic TD Release_2026.2（**只读判读** r3_run1 既有日志/报告，未重跑 TD，不继承额度）
- 测试窗口：2026-10-27 06:18–06:46（本机时间）
- 本报告：`workflow/runs/20261026-2138_fpga-integrated-delivery/test-reports/INT.P4-r3-integrated.md`
- 本轮测试者证据：`test-reports/INT.P4/r3/**`（只写该目录；未改生产 RTL/约束/IP/构建脚本/冻结证据）

## 1. 范围与规划冻结门槛

按 `dispatch.json`（round=r3、INT.P4 gates/task_allocation/td_policy）、`dev-plan.md` §3 INT.P4、§3.6、§3.7、§3.8（2026-10-27 05:20 冻结）：

| G 层 | 规划冻结门槛（要点） | 本轮适用性 |
|---|---|---|
| G0 | 单 `clk` 5.333ns/187.5MHz、异步低有效 `rst_n`、不新增 CDC/异步 FIFO/时钟；A1U1 vs R10F、RAW vs Y8 分离；派生变体端口/参数/单位不变 | 适用 |
| G1 | 同一候选全量回归 + 测试者 S1–S5 复跑 + **派生变体 token 等价（允许固定延迟；token 顺序、标记、槽数、flush 不许变）** + 样例哈希不变；HE 停顿敏感性作为既有差距记录 | 适用（**本轮判定核心**） |
| G2 | 隔离目录综合必做；`flow.status` 0 违例、WNS/TNS≥0、hold≥0、ERAM+CWC≤300、资源在器件内、IO≤286、无未驱动 DUT 输入、无 false_path/multicycle、单时钟；route 条件 | 适用（有新综合 r3_run1） |
| G3 | `not_run + awaiting_hardware`（无集成 bit/板窗） | 规划冻结 not_run |
| G4 | `not_run`（后置，仅记差距） | 规划冻结 not_run |
| G5 | r3 真实数字、manifest 全量绑定（10 img 源只读哈希、派生变体、harness/tcl/sdc、TD 证据）、E5a–E5c 已处理、编译文件数与入口一致、**协议/入口/最短步骤与证据一致**、无 bit/上板/真实 PCIe/A 路通过声明 | 适用 |
| bit | 本轮 not_run；b20 bit 不是本集成交付 | 规划冻结 |

派发额度（规划书面）：round3 synth≤3（终身≤9，派发前 6 已用）、route≤1（条件）、bitgen=0、CWC=0、download=0、Flash=0；不写 `D:/TD/**`、不动 b18/b19/b20。派发前置（`per_run_conditions`）：**每次综合前同一文件集须先过等价仿真，且文件集哈希与上次综合不同**。

## 2. 判定摘要

| 维度 | 适用性 | 结果 | 主要依据 |
|---|---|---|---|
| functional | 适用 | **fail** | 集成 TB/测试者 TB/P1/P2/P3/Python/样例全部 PASS，但 **G1 的派生变体 token 等价门槛未达成**：同一 ready 形态下 y8 383/317/3、gau 1368/1154/10、he 1116/980/44 处数据差异（SEEDMODE 0/1/2），且 always-ready 场景仍有 13 处 gray/gau 差异；单元 TB 在停顿下出现 **token 数不等**（bayer 769 vs 783） |
| engineering | 适用 | **pass（附过程偏差与限定）** | r3_run1 由测试者按原始报告逐项复核：Setup `NUM_FEPS 0/17220`、`WNS +72ps`、`TNS 0ps`；Hold `NUM_FEPS 0/TNS 0ps`（HWNS 为 TD 无路径哨兵）；IO 42/286；ERAM+CWC 39/300；reg 6004、slice* 10691/71680、lut 12943、DSP 14；STA 95.63%；无 HDL-5314/SYN-5013；层次可见；route/bitgen/CWC/download/Flash=0。**但**该次综合违反派发"先等价后综合"前置，见 §6.2 |
| system | 适用 | **fail** | 接口身份/单时钟/生产路径回归/发布边界与"无 bit/上板/真实 PCIe 声明"均通过，但 **G5 文档一致性失败**：`INT.P4-protocol.md` r3 段写"不丢不重"，与同一 manifest 绑定的 `bayer_check_stall.log`（769 vs 783）及 rowwin 单元证据矛盾；`INT.P4-build-entry.md` r3 段"候选 8"与实际列出的 10 个不符；r2 正文仍保留 `CHECK_REF_NEW PASS` 断言未就地标注 r3 状态 |

| G 层 | 结果 | 说明 |
|---|---|---|
| G0 | **pass** | 候选非 TB 源只有 `always @(posedge clk …)` / `negedge rst_n` 一种边沿形式；SDC 仅一条 `create_clock -period 5.333 -waveform {0 2.667}`，无 false_path/multicycle/clock group；派生变体端口与基础模块逐一相同（manifest diff 摘要 + 实例替换可核） |
| G1 | **fail** | 见 §5：差异不限 HE、always-ready 仍不同、停顿下 token 数可不等；固定延迟不能解释。派发书写的"超出固定延迟/既有 HE 敏感性即判 G1 失败"条件成立 |
| G2 | **pass（限定）** | 数字真实、可复核、同一最终 DB；`route=not_run`（harness 42 IO 无引脚约束，理由成立）；但综合前置未满足，且只证明"该 RTL 时序收敛"，不证明交付语义 |
| G3 | **not_run** | awaiting_hardware（无集成 bit/板窗；未伪造） |
| G4 | **not_run** | 后置，仅记差距 |
| G5 | **fail（结构项通过、文档一致性失败）** | manifest 291 条 union 记录 + legacy 目录 6 文件 + P1/P2/P3 引用 + 27 项文件集全部逐哈希通过；E5a–E5c 已按可复核方式处理；编译数 24+6 / 综合 25 与入口一致；无 bit/上板/真实 PCIe/A 路通过声明。缺陷见 §6.5 |
| honesty | **部分 pass** | 开发在 `result-r3.md`/manifest 中主动上报 G1 未达成与"先综合后等价"偏差，未伪造 PASS；manifest 绑定的 128 条证据哈希全部一致，r1 旧日志保持原样并加注，未发现日志改写。但两处关键表述与自有证据不符（§5.2 第 4 条、§6.5） |

**总体判定：FAIL。** 本轮 G2 从 r2 的 112 端点/−0.637ns 收敛到 **0 端点/+0.072ns**（真实、可复核），但同一候选的派生变体语义等价未达成，且失败面**超出**规划允许的"既有 HE 停顿敏感性"。因此 r3 不能作为集成交付候选通过；r2 则是 functional 通过、G2 不通过。**三轮实际修复用尽，本 run 内不得再派第 4 次修复。**

## 3. 实际执行命令与证据

工作目录 `D:\fpga\ph1p100`（或 `test-reports/INT.P4/r3/sim`，测试者自有 work 库，vlog 24 核心源 + 6 TB）。未运行项不列入本表。

| # | 命令（实际执行） | 退出码 / 文本判定 | 证据 |
|---|---|---|---|
| 1 | `python .../r3/verify_manifest_r3.py`（测试者自写，独立于 gen_manifest_intp4.py） | exit 0；`VERIFY_MANIFEST PASS`；291 条 union 记录（A1 4 / new_files 24 / img 10 / docs 8 / evidence 128 / td 111 / tool_inputs 4 / legacy_untracked 2）+ legacy_dirs 1 目录 6 文件；P1/P2/P3 引用 manifest 与 18 文件；链式 override 802cd752→8cd7d35b→2601fa42；**r3 文件集 25 Verilog + tcl/sdc 逐项对盘复核通过**；G2/G1 文本与 `flow.status` 互校 | `r3/manifest_verify.log` |
| 2 | `powershell -File .../r3/compile.ps1`（vlog 24 核心：候选 10 + b20 4 + img 10；TB 6：5 开发 TB + 测试者 TB） | exit 0；`COMPILE PASS core=24 tb=6`；work 库 `_info` 列出 24 源 + 6 TB（`vlog -quiet` 无输出，故未生成逐源日志） | `r3/compile_console.log`、`r3/sim/work/_info` |
| 3 | `vsim -c -do "run -all; quit -f" tb_integrated_delivery_top +MODE=4 +SAMPLE=1 +SAMPLE_DIR=.../r3/ev4` | exit 0；`TB_INTEGRATED_DELIVERY_TOP PASS`；**27 ok / 0 fail**；`SAMPLE_WRITTEN payload=3965` | `r3/run_dev_mode4_default.log` |
| 4 | `... +MODE=4 +SAMPLE=0 +EXTRA=1` | exit 0；PASS；**65 ok / 0 fail**；T1–T6 全部出现 | `r3/run_dev_mode4_extra.log` |
| 5 | `... +MODE=1 +SAMPLE=1 +SAMPLE_DIR=.../r3/ev1` | exit 0；PASS；**26 ok / 0 fail** | `r3/run_dev_mode1_default.log` |
| 6 | `... +MODE=1 +SAMPLE=0 +EXTRA=1` | exit 0；PASS；**65 ok / 0 fail** | `r3/run_dev_mode1_extra.log` |
| 7 | `vsim tb_intp4_tester`（测试者自有 TB，r3 副本仅把 6 处 dump 路径 r2→r3，`Compare-Object` 仅这 6 行差异） | exit 0；`TB_INTEGRATED_TESTER PASS errors=0`；S1–S5 全 ok；S5 `DRIVE_DONE beats=768`、无死锁、`commits=1 stream_n=3966` | `r3/run_tester_tb.log`、`r3/evidence/tester_*` |
| 8 | `vsim tb_img_algo_equiv_p4 +SEEDMODE=0/1/2`（冻结 TB，测试者独立重编译重跑） | 3 次 exit 0；`CHECK_REF_NEW FAIL errors=2867/2451/57`；`EQUIV_COUNTS 1720/1703/1720` 三 DUT 相同；`CONTROL_REF_REF2 diffs=98/99/48` | `r3/equiv_seedmode{0,1,2}.log` |
| 9 | 测试者控制 TB（`tb_equiv_control.v`：三个 DUT 全为基础 RTL，dut1 ready 相位可 +1 拍）`+SEEDMODE=0/1/2 +SHIFT=0` 与 `+SHIFT=1` | `+SHIFT=0`：3 seed 全 `CHECK_REF_NEW PASS`；`+SHIFT=1`：seed0 **180（全 HE）**、seed1/2 **PASS** | `r3/ctrl_shift{0,1}_seed{0,1,2}.log`、`r3/tb_equiv_control.v`、`r3/make_equiv_control.py` |
| 10 | 单元 TB（冻结源）独立重编译重跑：`tb_rowwin_retime_check`、`tb_bayer_retime_check`（默认与 `+STALL`） | rowwin(默认) `base=45 p4=45 err=3` → **FAIL**；rowwin(+STALL) 同结果（该 TB 无 STALL 开关）；bayer(默认) `769/769 err=0` → PASS；bayer(+STALL) `base=769 p4=783 err=762` → **FAIL** | `r3/tester_tb_rowwin_retime_check{,_STALL}.log`、`r3/tester_tb_bayer_retime_check{,_STALL}.log` |
| 11 | `tb_raw10_packer`；`tb_aplus_pcie_egress_adapter`；`tb_dual_channel_capture_scheduler` | 各 exit 0；`TB_RAW10_PACK PASS`、`TB_APLUS_PCIE_EGRESS_ADAPTER PASS`、`TB_DUAL_CHANNEL_CAPTURE_SCHEDULER PASS` | `r3/p1_tb_raw10_packer.log`、`p2_tb_egress.log`、`p3_tb_scheduler.log` |
| 12 | `python tools/integrated_delivery/{raw10_pack,dual_channel_schedule}.py`；`a1u1_decode.py <frozen> 4096`；`verify_integrated_sample.py <frozen trio>`；`run_py_tools_r3.py`（把 `verify_input_processing.py` 输出重定向到 r3/evidence/p1_tool，不写冻结 evidence） | 全部 exit 0；`RAW10_PACK PASS`、`DUAL_CHANNEL_SCHEDULE PASS`、`A1U1_DECODE OK`（padding 87B）、`VERIFY_INTEGRATED_SAMPLE PASS`、`INT.P1_VERIFY PASS`；重算 `golden_input_processing.json`=`2c420c86…`、`verify_report.json`=`7e257d07…` 与冻结逐字节相同 | `r3/py_tools.log`、`r3/py_*.log` |
| 13 | `python .../r3/oracle_sample_r3.py --sample <frozen> --raw <frozen> --json <frozen> --selftest`；再对 S5 dump（status/raw/stream/drain/rawA/streamA） | 均 exit 0；`ORACLE PASS`；S5 `A_PATH_CONTENT MATCH`（3840 B 逐字节，zlib 解压==DUT raw==独立模型） | `r3/oracle_frozen_sample.log`、`r3/oracle_tester_dumps.log` |
| 14 | 负对照：坏 header 副本 → `a1u1_decode`；坏 payload 副本 → `a1u1_decode` 与独立 oracle | 均按预期**被拒绝**：`header_crc mismatch`、`stream_crc mismatch`、`ORACLE FAIL ['inflated == .raw','stream_crc recomputed over payload','zlib inflate']` | `r3/neg_header_decode.log`、`r3/neg_payload_decode.log`、`r3/neg_payload_oracle.log` |
| 15 | 样例哈希：`ev1/`、`ev4/` 与 `tools/integrated_delivery/evidence/` 三文件 | 两侧 3 文件逐个相同：`79e35f28…`(a1u1,4009B) / `1357408f…`(raw,3840B) / `76d88910…`(json,825B) | 本报告 §4.1；`r3/ev1/**`、`r3/ev4/**` |
| 16 | 只读判读 r3_run1：`syn_flow.status`、`syn_gate_timing.rpt`、`syn_gate_area.rpt`、`td_01_synth_console.log`、`int_p4_Runs/syn_1/{run.log,gate.qor,int_p4_gate.area}`、`r3_run1-fileset.sha256`、`td/README-EVIDENCE.md`、`INT.P4/td/**` 目录与进程/路径污染核对 | 未重跑 TD（测试者不继承/不扩额度）；数字见 §6.1；判读记录见本报告与 `r3/manifest_verify.log` | manifest 已绑定；`INT.P4/td/r3_run1/**` |

说明：`vsim` 退出码 0 不等于 PASS，本报告一律以日志文本为准；无 Fatal/`$stop`/scoreboard 未解释失败。

## 4. 独立判据与独立复现

开发自述不作为判据。本轮使用六项与开发不同的判据：

1. **测试者自有集成 TB**（`test-reports/INT.P4/tb_intp4_tester_r3.v`，与 r2 版仅 6 行 dump 路径差异）：不依赖开发 TB 场景表，独立驱动 A/B、独立 host/DDR 模型；S1–S5 全通过，S5 反压无死锁且内容与独立模型逐字节一致。
2. **独立 A1U1/RAW10 重建 oracle**（`oracle_sample_r3.py`，与 r2 同哈希 `D3A736A1…`，不 import 开发代码，只用 `struct`/`binascii.crc32`/`zlib`）：冻结样例与 S5 dump 均 `ORACLE PASS`；两处单体负对照被 CRC/zlib 拒绝，证明判据能发现坏流。
3. **测试者控制 TB**（`tb_equiv_control.v`，从冻结等价 TB 派生：三个 DUT 全为基础 RTL，模块名/变体选择/ready 生成器改动，激励与比较逻辑逐字保留）：
   - `+SHIFT=0`（同 RTL 同 seed）→ 3 seed 全 0 差异 ⇒ **等价 TB 本身不产生假阳性**；
   - `+SHIFT=1`（同 RTL，dut1 ready 相位纯延 1 拍）→ seed0 180 处**全 HE**，seed1/2 0 差异 ⇒ **纯延迟/相位偏移不会造成 gray/gau 差异**，且 always-ready 下相位偏移无影响。
4. **冻结单元 TB 独立重编译重跑**（`tb_rowwin_retime_check.v` / `tb_bayer_retime_check.v`，manifest 绑定源）：rowwin 默认 45/45 err=3 FAIL、bayer +STALL 769 vs 783 err=762 FAIL —— 与 §5 的全链结论方向一致，且**前者是本轮 token 数不等的直接证据**。
5. **测试者独立 manifest 校验器**（`verify_manifest_r3.py`，不调用开发生成器）：逐条重算 291 条记录、P1/P2/P3 引用 manifest 及声明文件、A1 4 文件（对照 r1 测试者记录）、10 个 img 源（对照 r1 测试者 `compiled_unbound_inputs.txt`）、4 个派生变体、legacy 目录 6 文件、链式 override、**r3 文件集 27 项逐哈希对盘**、G2/G1 文本与原始报告互校；另用独立脚本解析 4 对派生/基础模块的端口声明，**端口名集合逐一相同**（24/24、23/23、26/26、43/43）。
6. **日志级 token 分类器**（`analyze_equiv_tester.py`，测试者自写）：不读开发分析脚本，直接解析冻结/自跑日志的 `CHECK_REF_NEW MISMATCH`/`CONTROL_REF_REF2 MISMATCH`，按 stream、marker 位（abort/sof/eol/eof）、数据位与索引分布分类。**它能发现"差异是否仅 HE""标记是否一致""是否只是个别 bit"**，这正是本轮门槛的判据。

### 4.1 通过项（同一 r3 冻结候选，RTL 仿真 64×48）

| 场景 | 判据 | 结果 |
|---|---|---|
| MODE=4 默认（RAW 旁路） | dev TB 27 项 | 27 ok / 0 fail；`T1 raw bypass` beats/eol/eof/sof 全 ok |
| MODE=4 `+EXTRA` | 65 项（T1–T6） | 65 ok / 0 fail |
| MODE=1 默认（Y8） | dev TB 26 项 | 26 ok / 0 fail |
| MODE=1 `+EXTRA` | 65 项 | 65 ok / 0 fail |
| 测试者 S1–S5 | 描述符/释放/身份/反压/无死锁 | 全 ok；`STATUS_WRITTEN errors=0` |
| P1/P2/P3 既有 TB | 3 个 | 全 PASS |
| P1/P2/P3 Python | 5 个入口 | 全 exit 0；重算证据与冻结逐字节相同 |
| A1U1 样例 | 解码 + 独立 oracle + 负对照 | `A1U1_DECODE OK`（raw_len_ok、padding 87B）、`ORACLE PASS`；坏 header/payload 均被拒 |
| 样例哈希 | mode1/mode4 与冻结 | 两侧 3 文件全同（§3 #15） |

## 5. 关键独立判定：派生变体 token 等价残余（G1）

### 5.1 事实（测试者自跑，非开发转述）

| seed | y8 diffs | gau diffs | he diffs | 合计 | marker 差异 | token 数（y8/gau/he） | 控制组（同 RTL 异 seed） |
|---|---|---|---|---|---|---|---|
| 0 | **383** | **1368** | 1116 | 2867 | **0** | 1720/1703/1720（三 DUT 相同） | 98（全 HE） |
| 1 | **317** | **1154** | 980 | 2451 | **0** | 1720/1703/1720 | 99（全 HE） |
| 2（always-ready） | **3** | **10** | 44 | 57 | **0** | 1720/1703/1720 | 48（全 HE） |

- 所有差异均为**数据位**差异（差异字段统计：数据位 3219/10145/6602 等），**sof/eol/eof/abort 标记 0 差异**，token 计数与 3 个 DUT 的 good/abort/hepub/herej/gauabt 计数完全一致。
- **差异不是仅 HE**：y8（gray 支路）与 gau（高斯支路）分别有 383/1368（seed0）、317/1154（seed1）、3/10（seed2）处 token 数据差异。开发自述"差异全部是数据值的少量样本位差"在"数据位"意义上成立，但**在"仅 HE"意义上不成立**（manifest/result 未声称仅 HE，但 §5.3 的门槛判定必须以此为准）。
- **always-ready（SEEDMODE=2）仍不精确**：外部 ready 恒 1，仍出现 3+10+44 处差异；y8 差异集中在 idx 9/777/1545 = **9 + 768·k**，即每帧起始若干拍；gau 亦在帧起始附近。这与"固定 +1 拍延迟"不相容（固定延迟不改变同 token 的数据）。
- 差异幅度：always-ready 下多为单字节 ±1…±4 LSB（例：y8 idx9 `c8927d9c → c9957ea0`；gau idx8 `a28c8395 → a38c8395`），随机 ready 下分布更广（y8 最长连续 3、gau 最长 25、he 最长 771）。

### 5.2 归因实验（区分"固定延迟/既有 HE 敏感性"与"派生变体新语义变化"）

1. **同 RTL 同 seed 控制**：0 差异 → 比较器无假阳性。
2. **同 RTL、ready 相位纯延 1 拍**：seed0 180 处差异**全部在 HE**（idx 768–1718），gray/gau **0**；seed1/2 0 差异；always-ready（seed2）0 差异。
   ⇒ 纯延迟/相位偏移在既有 RTL 上（seed0）**只**影响 HE，**不会**产生 gray/gau 差异；因此本轮 1751/1471/13 处 gray/gau 差异**不能**归因于固定延迟或既有 HE 敏感性。
3. **冻结单元 TB**（manifest 绑定源，测试者重跑）：
   - bayer 默认 ready：`base=769 p4=769 err=0` PASS；`+STALL`（75% ready）：**`base=769 p4=783 err=762` FAIL** ⇒ 停顿形态下派生前端**多出 14 个 token**（token 数不等，违反"槽数/flush 不变"）。
   - rowwin 默认（en 由 LFSR，含间隙）：`base=45 p4=45 err=3` FAIL（3 处为 abort 窗口值，开发已如实披露为良性）；开发日志另有"连续 en"版 `base=1331 p4=1330 err=0` 且该 TB 自身判 **FAIL**（计数不等，p4 少 1 token）。
4. **开发冻结日志与冻结 TB 源不匹配（证据卫生缺陷）**：manifest 绑定的 `rowwin_retime_check.log`（sha `b85f357a…`）`$finish` 在 `tb_rowwin_retime_check.v(127)`，其 TRACE 列（`rd_c/rb0/ra0/cbq`）与绑定 TB 源的 TRACE 列（`en/evt_en/ra0/rb0/cbq/cpa_b`）不同；绑定 TB 源（sha `44009c89…`）`$finish` 在 144 行、默认跑出 45/45/3。⇒ 该日志由**另一版 TB** 产生，**不能**作为绑定源的可复现证据；`result-r3.md` "无停顿 rowwin 单元 1330 token 逐 token 完全一致"的表述缺乏绑定可复现证据，且其自身日志显示 base=1331≠p4=1330。

### 5.3 判定

- 规划派发要求："**token 序列不变、仅固定延迟**"；并明确"若残余差异超出固定延迟/既有 HE 敏感性，必须判 G1 失败"。
- 事实：标记一致、计数一致，但 **gray/gau 数据在任意 ready 形态下都不完全一致**，always-ready 仍不一致，停顿下单元 token 数可不等；同 RTL 的相位控制证明这些差异**不是**固定延迟或既有 HE 敏感性可以解释。
- 结论：**G1 fail**。残余差异属于 **r3 派生变体引入的新语义变化**（最可能是读地址/描述符延拍与帧起始/flush、gap 的对齐改变；`img/**` 只读未改，r2 同一 TB 为 `CHECK_REF_NEW PASS`，进一步把变化定位在 r3 的 rowwin 派生变体）。规划允许的"既有 HE 停顿敏感性"差距仍然存在（98/99/48），但**不足以覆盖**本轮 gray/gau 差异。

## 6. 工程（G2）与系统（G5）核验

### 6.1 G2 数字复核（只读 r3_run1，逐项对原始报告）

| 项 | 原始证据原文 | 与开发自报 | 判定 |
|---|---|---|---|
| Setup | `syn_flow.status`：`Setup : WNS 72ps TNS 0ps NUM_FEPS 0`；`syn_gate_timing.rpt`：`Max : SWNS 0.072ns, STNS 0.000ns, 0 Viol Endpoints, 17220 Total Endpoints` | 一致 | **pass** |
| Hold | `Hold : WNS 2147483647ps TNS 0ps NUM_FEPS 0`（TD 无路径哨兵）；timing `Min : HWNS 0.000ns, HTNS 0.000ns, 0 Viol` | 一致（开发已注明哨兵） | **pass** |
| 资源 | `syn_gate_area.rpt`：`#IO 42 out of 286`、`#lut 12943`、`#reg 6004`、`#slice* 10691 out of 71680`、`#eram 39`、`#dsp 14` | 一致 | **pass** |
| 覆盖率 | timing `STA coverage : 95.63%` | 一致 | 记录 4.37% 未覆盖 |
| 未驱动 | `td_01_synth_console.log` 无 `HDL-5314`、无 `SYN-5013` | 一致 | **pass** |
| 层次 | `syn_gate_area.rpt` 有 `u_front=bayer_raw10_demosaic4_p4`、`u_front/u_row=algo_rowwin3_p4`、`u_gau=gray8_gaussian3x3_stream_p4`、`u_gau/u_row=algo_rowwin3_p4`、`u_arb`/`u_egress`/`u_store` | 一致 | **pass** |
| 约束 | `01_synth.tcl`/`integrated_core.sdc` 只有一条 `create_clock -period 5.333`；无 false_path/multicycle/clock group | 一致 | **pass** |
| 文件集 | `r3_run1-fileset.sha256` 27 行（25 Verilog + tcl + sdc）**逐项重算与磁盘一致**；两支 r3 新派生源在列；r2 综合（04:45）不可能含 05:30/05:58 才创建的文件 ⇒ 文件集必然不同 | 一致 | **pass** |
| route/bitgen/CWC/download/Flash | `INT.P4/td/**` 无 .bit/.adf/.cwc；无 route 目录；`budget_notes` 记 0/0/0/0/0 | 一致 | not_run（理由成立） |
| 额度 | r3 只 1 个综合会话 `td_20261027_060141.log` + `r3_run1/`；此前 6 次（r0/r1 3 + r2 `syn_r2_run1..3`）⇒ 终身 7/9 | 一致，无自扩 | **pass** |
| 路径污染 | `D:/TD/work/csi2` 最新 mtime 2026-10-17（未写）；b20 `changed-src` mtime ≤2026-10-26 21:35（未动）；A1 4 文件哈希 = 测试者 r1 记录 | 一致 | **pass** |

观察到的告警（不改变数字，但须记录）：`HDL-5007 could not find top-level module/unit; aborting hierarchy tree creation`（早期提示）；`PRJ-8806 Run syn_1 has exited unexpectedly` + `INT_SYN_WAIT_ERR`（TD 在 `wait_run` 前退出），但脚本完成标记 `INT_SYN_RUN_COMPLETE`、`INT_SYN_VIOL_ENDPOINTS=0`、`INT_SYN_TOTAL_ENDPOINTS=17220` 与完整非空报告（timing 105 KB、area 7.9 KB、gate DB 7.4 MB、run.log）齐备且自洽。`run.log` 另有"Bitgen will abort…unconstr_io"提示，正与 harness IO 未约束、本轮不做 bitgen 的边界一致。

### 6.2 综合前置偏差对 G2 证据效力的结论

- **数字有效**：r3_run1 是对**当前冻结文件集**（27 项逐哈希对盘）的真实综合，报告完整、可复核；因此"0 违例 / WNS +0.072ns / TNS 0 / hold 0 / 资源在器件内 / IO 42 / ERAM+CWC 39"作为**该网表的综合结果**成立。
- **效力受限（必须限定表述）**：(a) 该 RTL 的**功能等价未被证明**（G1 fail），所以 G2 不能升级为"集成交付时序通过"；(b) 派发 `per_run_conditions` 的"等价先于综合"前置未满足，属**过程偏差**，开发已在 manifest `r3_synth_fileset`/`honesty` 与 `result-r3.md` §3 主动记录，测试者核实记录属实、未改日志、未放宽阈值；按 dev-plan §3.7 该次综合本应"视为浪费额度，不允许"，规划可据此决定如何在收尾中记账（额度已实际消耗：终身 7/9）；(c) harness 无引脚/IO 约束，只覆盖内部寄存器到寄存器路径，**不是板级时序**。
- 因此本报告将 G2 记为 **pass（限定）**：它证明"r3 这份 RTL 在 187.5MHz 内部路径上收敛"，不证明交付可用；P4 总判定仍为 FAIL。

### 6.3 接口/集成（system 其余项）

- 接口身份：派生变体端口名集合与基础模块**逐一相同**（测试者解析：`algo_rowwin3_p4` 24/24、`gray8_gaussian3x3_stream_p4` 23/23、`bayer_raw10_demosaic4_p4` 26/26、`img_algo_parallel_top_p4` 43/43；manifest diff 摘要 + 实例替换可核）；`img/**` 10 源哈希与 r1 测试者记录一致（只读未改）。
- 单时钟/复位：候选非 TB 源只有 `posedge clk`/`negedge rst_n`；无第二时钟、无异步 FIFO、无 CDC 结构；SDC 单 `create_clock`。
- 生产路径：P1/P2/P3 既有 TB 与 Python 工具在同一候选上全部 PASS；A1U1 vs R10F、RAW 旁路 vs Y8 的分离由 MODE=4/1 + T1/T4/T5/T6 覆盖。
- 发布边界：无 bit、无 route、无 CWC、无下载/Flash；b20 bit 未被冒充；真实 PCIe/RK 仍标待联调。

### 6.4 E5a–E5c 证据卫生复核

- E5a：`INT.P4/td/run.log` 与 `td/r1-evidence/run.log` 同哈希 `8023b305…`，README/manifest 注明其为 r1 旧日志、非 r3 证据。**通过（加注式处理，规划允许）**。
- E5b：`01_synth.tcl` 已改名 `01_synth_r2run3_experiment_copy_DO_NOT_USE.tcl`；正式入口 `tools/integrated_delivery/td/01_synth.tcl` 与 `td/r3_run1/01_synth.tcl` 同哈希 `e9a7522a…`。**通过**。
- E5c：`int_p4_Runs/syn_1/` 混合目录已在 README/manifest 标注，r2 权威 `syn_r2_run2/`、r3 权威 `r3_run1/`。**通过**。

### 6.5 G5 缺陷（文档一致性，非数字问题）

1. **`INT.P4-protocol.md` r3 段（第 9 行）**："停顿（en=0）时延迟组整体冻结，下一 en=1 拍消费一次，**不丢不重**"。与同一 manifest 绑定的 `bayer_check_stall.log`（`base=769 p4=783 err=762`，测试者已复现）及 rowwin 连续 en 日志（1331 vs 1330）**矛盾**。该 r3 段也未提及 p4 自身 57–2867 处差异，只写"既有 HE 差距 48–99"，易被读成"只有既有 HE 问题"。
2. **`INT.P4-build-entry.md` r3 段（第 5 行）**：写"候选 **8**"，随后实际列出 **10** 个文件；总数 24（10+4+10）与实测一致，属计数笔误。
3. **r2 正文残留**：`INT.P4-build-entry.md` 第 39–51 行"编译清单（r2…）"、`INT.P4-shortest-steps.md` 第 39 行"期望…`CHECK_REF_NEW PASS`"、`INT.P4-protocol.md` 第 96–97 行"`CHECK_REF_NEW PASS`"仍保留 r2 断言，未在就地标注"r3 已不成立"。文件顶部有 r3 段与历史说明，但对只读单节的接收方仍有误导风险。

上述 1 与"协议与证据一致"直接冲突，故 G5 记 fail；2、3 为同批修正项。manifest 的结构性绑定、真实数字、E5a–E5c、编译数一致、无 bit/上板声明等其余 G5 项均 pass。

## 7. 输入漂移检查

| 检查 | 结果 |
|---|---|
| manifest SHA256（测试前/后） | `43EBFF3D…526F1` 两次一致；`stopped_modifying=true`、`drift_count=0`、`round=3` |
| 291 条 union 记录 + legacy 目录 6 文件 | 全部哈希/大小一致；P1/P2/P3 引用 manifest 及其 18 个声明文件一致；链式 override 一致 |
| r3 综合文件集 27 项 | 全部与磁盘一致（综合输入 = 冻结候选） |
| 候选/工具目录未登记文件 | 无（`__pycache__` 3 个 .pyc 为运行绑定工具的副产物，已忽略并记录） |
| 测试者写入范围 | 仅 `test-reports/INT.P4/r3/**`；未写 `tools/integrated_delivery/evidence`（重定向）、未写候选、未写 TD/b20 |
| 冻结 evidence mtime 观察 | `tools/integrated_delivery/evidence/{golden_input_processing.json,verify_report.json}` mtime = 2026-10-27 05:58:57（开发 r3 会话内被工具就地重写），但**内容哈希仍等于 manifest 绑定值**（`2c420c86…`/`7e257d07…`）⇒ 无内容漂移，记录为卫生观察 |
| git 跟踪文件 | HEAD 未变；`tools/td/*`、`workflow/tasks.json` 的改动与本包无关（非本轮产物），`fpga/csi2/src/img/**` 未被修改（哈希对照 r1 记录） |

## 8. 未测项、差距与不外推

- 仅 64×48 缩尺帧；1920×1080 全尺寸、真实相机/ADC、真实 DDR 器件时序未测。
- G3/G4：无集成 bit、无板窗、无真实 PCIe/RK 传输、无长稳/吞吐/恢复——全部 `not_run + awaiting_hardware`，不作通过。
- HE/高斯未逐像素与软件参考核对（只做 DUT-vs-DUT 等价）；HE 停顿敏感性仍是既有差距（98/99/48）。
- 看门狗、坏帧撤销以外的错误注入、双相机自由运行暂存未覆盖（同 r1/r2）。
- 综合 harness 无引脚/IO 约束，非板级顶层；bitgen 提示 `unconstr_io`，本轮不产 bit。
- 芯片内 A 路（R10F）与 b20 板的薄裕量（+0.012ns）未被本包改动，也不因本包结论而变化。

## 9. 可复现缺陷清单

| ID | 触发 | 期望 | 实际（可复现） | 影响 |
|---|---|---|---|---|
| D-r3-1 | `tb_img_algo_equiv_p4 +SEEDMODE=0/1/2`（冻结 TB，64×48，两好帧+一中止帧，两 DUT 同 ready seed） | 三流 token 数据/标记/计数完全一致（允许固定延迟） | `CHECK_REF_NEW FAIL 2867/2451/57`；y8 383/317/3、gau 1368/1154/10、he 1116/980/44；标记 0 差异、计数一致 | **G1 不通过**：派生变体改变了 gray/高斯像素数据 |
| D-r3-2 | 同上 `+SEEDMODE=2`（外部 ready 恒 1，无外部停顿） | 无停顿场景精确一致 | 仍 3+10+44 处差异（y8 集中在 9+768·k 帧起始） | 说明差异非停顿相位假象，指向帧起始/flush 对齐改变 |
| D-r3-3 | `tb_bayer_retime_check +STALL`（75% ready） | token 数与内容一致 | `base=769 p4=783 err=762` FAIL（多 14 个 token） | 停顿下前端可多发 token；与协议"不丢不重"矛盾 |
| D-r3-4 | `tb_rowwin_retime_check`（冻结 TB 默认 en 含间隙） | 一致 | `45/45 err=3` FAIL（3 处 abort 窗口值，开发已披露） | 局部偏差已披露；结合 D-r3-3 构成"停顿下非等价" |
| D-r3-5 | 绑定证据可复现性 | 日志与绑定 TB 源对应 | `rowwin_retime_check.log`（`$finish` 行 127/旧 TRACE 格式）≠ 绑定 TB 源（行 144）；开发"连续 en 1330 精确"不可由绑定源复现，且该日志自报 base=1331≠p4=1330 | G1 的部分支撑证据不可复现（证据卫生） |
| D-r3-6 | 文档一致性 | 协议与证据一致 | `protocol` r3 段"不丢不重"与 D-r3-3/D-r3-5 矛盾；`build-entry` "候选 8" vs 实列 10 | G5 fail（交接误导风险） |

## 10. 结论与后续（本 run 不再派第 4 轮）

- **判定 FAIL**；G2 已真实收敛（0 端点 / WNS +0.072ns / TNS 0 / hold 0），但 G1（派生变体语义等价）不通过，且失败面超出"固定延迟/既有 HE 敏感性"。按派发门槛，**任何 PASS、route、bit 均不得写**。
- **轮次**：round3 是第 3 次实际修复，已用尽；本 run 内不得再派修复，也不得复用本轮 synth 额度。是否属"可修设计问题"：**是**（局部、定位明确的 retime 对齐问题，`img/**` 仍可只读、只改 `integrated_delivery/` 派生变体），但必须由原规划在**新任务/新授权**中处理。
- **两个候选不可合并**：r2 = functional pass / G2 fail（112 端点，−0.637ns）；r3 = G2 pass / functional fail。**不得**以 r3 的时序数字配 r2 的功能证据拼成 PASS（不同输入，报告合同禁止）。
- **建议的最短下一步（新任务，不含本轮已用额度）**：
  1. 在 `algo_rowwin3_p4`（或必要的 `gray8_gaussian3x3_stream_p4`）内把延迟组与**帧起始/flush/gap 对齐**一起处理，使 (a) 停顿下 token 数相等（先修 `bayer +STALL` 769→783），(b) always-ready 下 y8/gau 逐 token 相等（先清 9+768·k 的帧起始差异）；用测试者控制 TB（同 RTL ready 相位 +1 拍 = gray/gau 0 差异）作为"非延迟伪差"判据。
  2. 重新冻结 manifest → 3 seed 等价 + 全量回归 + 样例哈希 → **等价通过后**再做 1 次新综合（必须换文件集哈希）；综合作业按本轮同样的只读复核口径。
  3. 修正 §6.5 的文档缺陷；把"停顿冻结=不丢不重"改为"在以下实测条件下成立/未证明"。
- **板级工作线承接（规划 §3.8 口径，允许但须诚实标注）**：若继续板级线，首段必须写"承接自 ⚠ INT.P4（r3：G2 通过但派生等价 fail；r2：功能通过但 G2 fail；未做 route/bit）"，把 **rowwin 帧起始/停顿对齐**列为已知带出风险；板级 bit 必须有自己真实顶层 STA（真实时钟/IO 约束），不得用 P4 综合数字代表板级时序，也不得声称"P4 通过/整机时序签核"；若为 bring-up 产 bit，须标注"带已知功能/时序残余风险的 bring-up bit"并另立额度与硬件窗口。建议以 **r3 的时序干净网表**作为板级起点（其定时结构已收敛），但把 gray/高斯帧起始像素差与停顿多发 token 当作**已知功能风险**；若板级要求先有功能基线，则只能以 **r2 候选 + 已知 0.637ns 违例**带出，两者都要在交接中标明。

## 11. 回退与入口

- 本报告只对应 `INT.P4-r3-manifest.json`（`43EBFF3D…`）绑定的候选；r2 结论对应 `DFAB7F9D…`，r1 对应 `CFFCF54D…`，r0 对应各自 manifest。
- 复测入口（新任务时）：冻结候选 + 本文 §3 命令；测试者控制 TB 与分类器在 `test-reports/INT.P4/r3/`（`tb_equiv_control.v`、`make_equiv_control.py`、`analyze_equiv_tester.py`、`verify_manifest_r3.py`、`run_py_tools_r3.py`、`compile.ps1`）。
- 测试者未修改任何生产文件；证据仅写 `test-reports/INT.P4/r3/**`。
