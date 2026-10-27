### 判定：FAIL

# INT.P4 r0 综合验收报告（dimension=integrated）

- task_id：INT.P4（同一候选集成交付）
- dimension：integrated（functional / engineering / system 三维由同一测试者核验，非三个独立视角）
- round：0（首次验收；本报告为 round0 唯一 integrated 报告）
- run_id：20261026-2138_fpga-integrated-delivery
- 工作树：`D:\fpga\ph1p100`（git HEAD `27c596b`；`fpga/csi2/src/integrated_delivery/`、`tools/integrated_delivery/`、本 run 目录均为未跟踪新增路径）
- 冻结 manifest：`workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4-r0-manifest.json`，SHA256=`31a3bbf2755677b9ce3deb2e007acdc3360bf896995c503e53a55e2dccec3f983`（测试前后一致）
- 工具：ModelSim ASE 10.5b（`D:\intelFPGA\18.1\modelsim_ase`）、Anlogic TD 6.2.3.210850（`D:\anlogic\TD_Release_2026.2`）、Python 3.11.5、Windows
- 测试窗口：2026-10-27 02:15–03:05（本机时间）；测试者最终产物只落在 `test-reports/INT.P4/**` 与本报告，未改生产 RTL/约束/构建脚本（一处临时负对照文件已移入 `test-reports/INT.P4/evidence/`，见 §7）
- 报告路径：`workflow/runs/20261026-2138_fpga-integrated-delivery/test-reports/INT.P4-r0-integrated.md`

## 1. 本任务范围与规划冻结门槛

按 `dispatch.json`（INT.P4 gates/td_policy/deliverables）与 `dev-plan.md` §3 INT.P4（2026-10-27 冻结）：

| G 层 | 规划冻结门槛（原文要点） | 本轮适用性 |
|---|---|---|
| G0 | 顶层接口/单位/模式/时钟/复位冻结且与 RTL 一致；A1U1 与 R10F 分离；RAW/Y8 区分 | 适用 |
| G1 | 同 manifest 下 P1/P2/P3 回归重跑通过 + 集成 TB 真实 DUT 通过（背压、abort、A disabled、B 优先、身份/释放、描述符/长度/尾拍/完成/释放、RAW 旁路干净）；A1U1 样例 header/stream CRC+zlib 通过；须有独立判据 | 适用 |
| G2 | 隔离目录综合必做；clk 187.5MHz 下 WNS/TNS≥0、hold≥0、0 违例、资源在器件内、ERAM+CWC≤300；布线条件允许才做 | 适用（综合必做；布线条件） |
| G3 | `not_run + awaiting_hardware`（无集成 bit/板窗） | 规划已冻结为 not_run，理由：无板级集成顶层/ADC/bit，不得伪造（dev-plan §3 验收门槛、dispatch G3） |
| G4 | `not_run`（后置，仅记录差距） | 规划已冻结为 not_run，理由：流水深度 1 帧、长稳/性能后置（dispatch G4） |
| G5 | manifest/protocol/build entry/decode/sample/shortest steps 齐全且与证据一致；RK 真实 PCIe 仍待联调 | 适用 |
| bit | 本轮 not_run（无板级集成顶层/ADC，不伪造）；b20 bit 是独立历史候选 | 规划已冻结 |

TD 策略（dispatch td_policy）：工程只建在 `INT.P4/td/`；synth≤2、route≤1、bitgen=0、CWC=0、downloads=0、Flash=0；不得写 `D:/TD/**`、不得动 b18/b19/b20；不得伪造 ADC/引脚/时序。

## 2. 三维与 G 层结果

| 维度 | 适用性 | 结果 | 主要依据 |
|---|---|---|---|
| functional | 适用 | **fail** | B 单帧内容/描述符/身份/释放通过；但 G1 要求的背压场景失败（采集死锁 + 已提交帧内容损坏），abort/bad-ACK/B 优先在集成层未执行，mode1 Y8 未验证 |
| engineering | 适用 | **fail** | manifest/哈希/候选绑定全部一致且无漂移；但 TD 综合在 MapIO 失败（SYN-8228），无 WNS/TNS/资源结论，route/bit/CWC=not_run |
| system | 适用 | **fail** | 接口/通路已接通并可复现单帧；G5 交付一致性不成立（文档未绑定、入口说明与脚本不符、结果描述超出日志）；G3/G4=not_run awaiting_hardware |

| G 层 | 结果 | 说明 |
|---|---|---|
| G0 | **pass** | 单 `clk`/`rst_n`；SDC 仅一条 `create_clock -period 5.333`，无 false_path/multicycle/CDC；A1U1 头 44B 独立解析通过，R10F 不在本通路；`m_mode/m_is_raw` 与 `pk_*` 分离 |
| G1 | **fail** | 见 §5：单帧正向与身份/释放通过，但背压场景真实 DUT 失败；abort/A-disabled/B-priority/error-ACK 集成场景未被执行；独立判据结果见 §4 |
| G2 | **fail** | `SYN-8228 ERROR: MapIO rule -- The IO number may exceed the device max IOs(286)`；IO=2813（890 in/1923 out）；无 WNS/TNS/资源结论；route/bit/CWC=not_run（非 pass） |
| G3 | not_run | awaiting_hardware（无集成 bit/板窗；不伪造） |
| G4 | not_run | 后置，仅记差距 |
| G5 | **fail** | manifest 的 docs 条目全部为 `missing`（与实物不符、未绑定哈希）；build entry 的 `-Full` 说明与脚本实际行为不符；result-r0 的场景/资源表述与日志不符；RK 真实 PCIe 待联调（与规划一致） |
| honesty | pass | 未发现 bit/上板/真实 PCIe/A 路上板的通过声明；b20 bit 未被当作本集成交付 |

## 3. 实际执行命令（测试者独立复跑）

工作目录 `/` 均为 `D:\fpga\ph1p100`；日志见 `test-reports/INT.P4/regression/`。

| # | 命令（实际执行） | 退出码/文本判定 | 证据 |
|---|---|---|---|
| 1 | `python .../test-reports/INT.P4/verify_manifest.py` | exit 1；66 条 union 记录、P1/P2/P3 共 18 个声明文件、A1 4 文件哈希全部匹配；7 条非哈希问题（见 §7） | `regression/manifest_verify_post.log` |
| 2 | `powershell -File .../test-reports/INT.P4/run_regression.ps1`（自有 work 库，重编译冻结候选 + 4 个 TB） | exit 0；`TB_RAW10_PACK PASS`、`TB_APLUS_PCIE_EGRESS_ADAPTER PASS`、`TB_DUAL_CHANNEL_CAPTURE_SCHEDULER PASS`、`TB_INTEGRATED_DELIVERY_TOP PASS`（各 `Errors: 0, Warnings: 0`） | `regression/p1_tb_raw10_packer.log`、`p2_tb_egress.log`、`p3_tb_scheduler.log`、`integrated_default.log` |
| 3 | `powershell -File .../test-reports/INT.P4/run_tester_check.ps1`（测试者自编集成 TB，自有 work 库） | exit 0；文本 `TB_INTEGRATED_TESTER FAIL errors=1`（唯一失败为 S5 背压死锁；vsim 退出码不构成 PASS 判据） | `regression/tester_integrated.log` |
| 4 | `vsim -c -do "run -all; quit -f" tb_integrated_delivery_top +MODE=4 +SAMPLE=0 +EXTRA=1`（测试者库） | exit 0；文本 `TIMEOUT state=0` + `FAIL errors=1` | `regression/dev_tb_extra1_tester_rerun.log` |
| 5 | `python .../oracle_sample.py --sample ... --raw ... --json ... --selftest` | exit 0；`ORACLE PASS`；负对照（payload 翻 1 字节）被 CRC/zlib 拒绝 | 见 §4 |
| 6 | `python .../oracle_sample.py --status ... --raw/--stream/--drain tester_*1.bin --rawA/--streamA tester_*5.bin` | exit 0；`ORACLE PASS`（B 帧全部内容检查通过）；附 `A_PATH_CONTENT MISMATCH` | `evidence/tester_*` |
| 7 | `python .../run_p1_tool_isolated.py`（重定向 verify_input_processing 输出，不写冻结 evidence） | exit 0；`INT.P1_VERIFY PASS`；重算 `golden_input_processing.json`/`verify_report.json` 与冻结文件哈希逐字节相同 | `regression/p1_verify_input_processing_tester.log` |
| 8 | `python tools/integrated_delivery/raw10_pack.py`；`dual_channel_schedule.py`；`a1u1_decode.py <sample> 4096`；`verify_integrated_sample.py <sample> <raw> <json>` | 全部 exit 0：`RAW10_PACK PASS`、`DUAL_CHANNEL_SCHEDULE PASS`、`A1U1_DECODE OK`、`VERIFY_INTEGRATED_SAMPLE PASS` | `regression/p1_raw10_pack_tester.log`、`p3_dual_channel_schedule_tester.log`、`p2_decode_sample_tester.log`、`sample_verify_tester.log` |
| 9 | 读取 TD 原始日志（只读）：`INT.P4/td/int_p4_Runs/syn_1/run.log`、`synth_console_r1.log`、`int_p4_rtl.area` | 见 §6 | 开发证据（只读引用） |

未运行的命令不列入上表。TD 未由测试者重跑（本包 synth 额度已用 2 次中 1 次有效，见 §6；测试者不消耗/不继承开发额度）。

## 4. 独立判据与独立复现

开发自述不作为判据；本轮至少使用三项与开发不同的判据：

1. **独立 RAW10/A1U1 重建**（`test-reports/INT.P4/oracle_sample.py`）：不 import 开发 `a1u1_decode`，用 `struct`/`binascii.crc32`/`zlib` 自行解析 44B 头、重算 header/stream CRC，并由采集公式 `p=(seed+y*97+(gx*4+i)*13+(gx*y)*7)&0x3FF` 与 4x10bit 打包规则**从零生成**期望 packed RAW10 字节，与 RTL 落盘 `.raw` 逐字节比较。该判据能发现 CRC/长度/打包/字节序/内容替换类缺陷（负对照：payload 翻 1 字节 → stream CRC 与 zlib 均报错，判据有效）。
   - 冻结样例：`integrated_sample.a1u1` 4009B、stream_len=3965、raw_len=3840、header_crc=0x78aaf30d、stream_crc=0xd5006fb4、raw_crc=0xedbac353；**独立重建 == .raw == zlib 解压结果**，且 `.raw` 的 CRC 与头一致。
   - 测试者用自有库重跑开发默认 TB（MODE=4/SAMPLE=1，样例重定向到测试者目录）：产出 `integrated_sample.{a1u1,raw,json}` 三文件 SHA256 与冻结样例**完全一致**（`79e35f28…`/`1357408f…`/`76d88910…`），说明冻结样例确由该候选确定性产生。
2. **测试者自编集成 TB**（`test-reports/INT.P4/tb_intp4_tester.v`，约 700 行，独立驱动/主机模型/DDR 模型）：按 DUT 握手计数驱动 768 拍，dump `pk_*`/`ap_*`/`drain_*`，由上述 Python oracle 独立核对；覆盖开发 TB 未覆盖的“无复位第二帧 B”“a_enable=0 门控”“A 单帧可达性”，并以 m_ready 间隙复现背压。测试者 TB 的 S1 输出 stream 与冻结样例 payload 逐字节相同。
3. **复跑开发失败场景**：在测试者库中重跑 `+EXTRA=1`，独立复现 `T2 A channel … TIMEOUT state=0`。

## 5. 功能结果与缺陷

### 已验证通过（同一冻结候选）

| 场景 | 判据 | 结果 |
|---|---|---|
| B 单帧端到端（64x48, mode4） | 测试者 TB S1 + 独立 oracle | PASS：commit/publish/export/arm/drain/release；描述符 `frame_bytes=4096`、`stream_len=3965`、`src_sel=0`、`camera_id=1`、`seq=7`、`epoch=11`；release `cam=1/slot=1/epoch=11/session=0x1234/seq=7/status=0(completed)`；`pk` 字节与独立模型逐字节相同；stream zlib 解压 == `pk` == 模型；drain 前缀 == stream |
| B 第二帧（无复位，slot0/seq8） | 测试者 TB S2 | PASS：再次 grant/commit/arm/release |
| `a_enable=0` 门控 | 测试者 TB S3 | PASS：200 拍内 A 描述符未被 grant，scheduler accepted 不变 |
| A 单帧（复位后、m_ready 恒定） | 测试者 TB S4 | PASS：grant/commit/release（camera=0） |
| P1/P2/P3 既有 TB 与工具 | 测试者重编译重跑 | PASS（3 个 TB + 5 个 Python 入口，见 §3） |
| A1U1 样例 | 独立解析 + 负对照 | PASS |

### 缺陷（可复现）

**D1（G2，工程）综合在 MapIO 显式失败**
- 触发：`INT.P4/td/01_synth.tcl`（TD 6.2.3，`PH1P100SBG484`，`top_module integrated_delivery_top`，SDC 5.333ns）在 `syn_1` 的 Stage 2.2 报错。
- 期望：完成综合并给出 WNS/TNS/hold/违例/资源；实际：`SYN-8228 ERROR: MapIO rule -- The IO number may exceed the device max IOs(286)`，`wait_run` 以 `PRJ-8806 ERROR: Run syn_1 has exited unexpectedly` 结束；`int_p4_rtl.area` 显示 `#IO 2813`（input 890 / output 1923）。无 `*_gate.timing`/`*_gate.area`，故无 WNS/TNS、无 ERAM/CWC 结论（开发 result-r0 中“u_algo 264 ERAM”只是 area 的 `macros` 列，不是 ERAM 计数，不能作为 G2 资源结论）。
- 影响：G2 无时序/资源签核；route/bitgen/CWC/download 全部 not_run；不得记 pass。

**D2（G1，功能）监视流反压导致 A 通道采集死锁，且**已提交帧内容损坏
- 触发：A 通道单帧，`m_ready` 在帧中制造间隙（60/40/40/10 拍，等同开发 TB T2 的背压模型）。
- 期望：`a_s_ready` 不长期阻塞；即使阻塞也不得重复/丢拍；任何不完整帧不得以“完成”提交。
- 实际（测试者 TB S5）：采集在 `beat=760/768` 处 `a_s_ready=0` 持续 >200000 拍（>1.07ms）→ 采集死锁；但该帧仍以 `st_raw_len=3840`、`stream_len=3927`（正确为 3965）提交并释放；独立 oracle 显示 `pk` 内容自第 55 字节起与模型不符（3305 字节不一致，呈 5 字节组重复），zlib 解压仍“成功”。开发 TB 在同一反压条件下的 T2 以 `TIMEOUT state=0` 结束（测试者独立复现），表现不同但同为该背压路径失败。
- 影响：G1“背压”门槛不成立；存在**静默帧损坏 + 死锁**风险，任何真实相机/PCIe 反压都可能触发。根因未由测试者定位（开发负责）；但同驱动在 m_ready 恒定时 S1/S2/S4 均逐字节正确，唯一差异是 m_ready 间隙，可排除驱动本身。

**D3（G1，覆盖）开发集成 TB 的 abort/A 禁用/B 优先/错误 ACK 场景实际未执行**
- 触发：`tb_integrated_delivery_top` 仅在 `+EXTRA=1` 下进入 T2；T2 失败后 T3（abort）/T4（A disabled+B priority）/T5（错误 ACK）从未运行；默认运行只有 T1。
- 期望：上述场景至少各有一次真实 DUT 运行记录；实际：日志只到 T2。`result-r0.md` 第 18–19 行把它们并列为“同一仿真内第二帧起…超时未通过”，并称“A 通道整帧未完成”，与日志不符（测试者 S4 证明 A 单帧在无监视反压时可完成）。
- 影响：G1 的必需集成场景缺证；开发报告的场景表述需修正（不得用未执行的场景充数）。

**D4（G5，交付一致性）manifest 未绑定文档；入口说明与脚本不符；两处未登记文件**
- `INT.P4-r0-manifest.json` 的 `docs` 5 项全为 `state:"missing"`，但 `INT.P4-protocol.md`、`INT.P4-build-entry.md`、`INT.P4-shortest-steps.md`、`INT.P4-lessons.md`、`INT.P4/result-r0.md` 均存在（mtime 02:11:53，早于 manifest 02:12:53）→ 文档未纳入哈希绑定，G5“齐全且一致”不成立。
- `INT.P4-build-entry.md` 称 `-Full` 追加运行 `tb_raw10_packer`/`tb_aplus_pcie_egress_adapter`/`tb_dual_channel_capture_scheduler`，但 `run_integrated_sim.ps1` 的 `-Full` 只运行 Python 工具（无 TB 仿真）；开发证据中也只有 Python 日志，无 P1/P2/P3 TB 复跑日志（测试者本轮补跑，均 PASS）。
- 候选目录存在未登记文件 `fpga/csi2/src/integrated_delivery/{sim_output.txt,transcript}`（mtime 00:08/00:16，早于 P4 开发 01:42，属此前包遗留），未列入任何 manifest，候选目录“无未登记产物”不成立。
- 流程观察：`result-r0.md` 自述开发工具调用约 156 次，超过本角色 150 次派发上限（不影响技术判定，但属预算偏差，应记录）。

**D5（补充，未计入本轮必需门槛）mode1 Y8 监视流未被验证**
- 开发日志 `integrated_mode1_y8_attempt.log` 显示 T1 中 Y8 监视流 0 拍、随后 T2 超时；测试者未重跑 mode1（G1 必需项是 RAW 旁路干净，已在 S1 验证）。该路径需在修复后复测，不得视为通过。

## 6. 工程/工具/候选核对（TD 与边界）

- 综合仅建在 `workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4/td/`；`int_p4_Runs` 下只有 `syn_1`，无 route/bitgen run；未发现 `*.bit`/`*.cwc`（全 run 目录递归检索为空）。
- TD 原始日志核对：`syn_1/run.log` 明确含 `SYN-8228`；`td_20261027_021027.log` 以 `wait_run` 失败结束；`synth_console_r0.log` 是首次调用因 tcl 未复制到 run 目录而失败（`couldn't read file "01_synth.tcl"`），未建工程。综合调用共 2 次（1 次无效 + 1 次有效），在 synth≤2 内；route=0、bitgen=0、CWC=0、download=0、Flash=0。
- 未伪造引脚：`int_p4.al` 中 `Pin/IOB/Location/PACKAGE_PIN` 匹配数为 0；SDC 只有一条 `create_clock`，无 false_path/multicycle；顶层源文件仅一个 `always @(posedge clk or negedge rst_n)`，无第二时钟域/CDC。
- 未写 `D:/TD/**`：`D:\TD` 下无 2026-10-27 00:00 之后修改的文件；无 `pnmain`/`td_commands_prompt` 进程残留（测试时点）。
- b20 只读：`T10.b20-a-timing` 在 P4 开发/测试窗口（01:42–03:05）内无文件修改；存在的 00:37–00:49 `board/captures_*` 文件早于 P4 派发（00:50 只读核对），非本任务写入。b20 工程/计数未被复用或改写。
- 顶层实例均为冻结实现（area 层次含 `u_aplus/a1_frame_top`、`u_core/a1_deflate_core`、`u_store/a1_ddr_slot_store`、`u_arb/a1_ddr_arb2`、`u_egress/aplus_pcie_egress_adapter`、`u_p1/img_algo_parallel_top`、`u_sched/dual_channel_capture_scheduler`），未发现 stub/placeholder（仅注释中出现 “not a stub”）。

## 7. 输入漂移检查

- 测试开始与结束各跑一次独立 manifest 核对（`regression/manifest_verify_post.log`）：
  - union manifest 66 条（A1 只读 4、new_files 11、tool_inputs 2、evidence 23、td 26）路径/SHA256/大小全部匹配；
  - INT.P1-r1 / INT.P2-r0 / INT.P3-r1 三个引用 manifest 自身 SHA256 与其记录的 `manifest_sha256` 一致，且其中 18 个声明文件的实际哈希与各自 manifest 一致、与 union 的 `expected_sha256` 一致；
  - A1 四文件（`a1_frame_top.v` cda28c…、`a1_deflate_core.v` a91c2e…、`a1_ddr_slot_store.v` 6c619c…、`a1_ddr_arb2.v` b84019…）与 dispatch 冻结值一致；
  - `stopped_modifying=true`；manifest 文件 SHA256 测试前后均为 `31a3bbf2…`；冻结样例哈希测试前后不变（`79e35f28…`）。
- 结论：**无输入漂移**；测试者产生的所有日志/dump/脚本仅在 `test-reports/INT.P4/**`，未回写冻结候选。说明：oracle 首次负对照曾把 `INT.P4_neg_control.a1u1` 临时写到项目根（cwd），随即移入 `test-reports/INT.P4/evidence/`，并把 oracle 的负对照输出路径改为该 evidence 目录；冻结目录未被写入（`tools/integrated_delivery/evidence` 仍为 6 个原文件，哈希未变）。
- 7 条非哈希问题即 §5 D4（5 条 docs `missing` + 2 个未登记遗留文件），属交付一致性缺陷，不是哈希漂移。

## 8. 已接通 / 已验证 / 阻塞 / 下一最短动作

- **已接通（同一候选、单 clk）**：捕获 A/B → P1 输入处理 → b20 r0 A+ 核 → A+ 槽存储 → DDR 仲裁 → P2 egress adapter → 描述符/身份/完成/释放面；P3 调度器提供 A/B 身份、`a_enable` 门控与全字段释放；host ACK → slot_release → drain → release 闭环在 B 单帧与 A 单帧（无监视反压）上走通。
- **已验证（独立判据）**：B 单帧内容/描述符/身份/释放/RAW 旁路逐字节；B 第二帧无复位复用；`a_enable=0` 门控；A 单帧可达；P1/P2/P3 既有 TB/工具；A1U1 样例（独立重建 + 负对照）；manifest 全量哈希与无漂移。
- **阻塞/未通过**：G2 综合（MapIO IO 超限，无时序/资源）；G1 背压（采集死锁 + 已提交帧内容损坏）；abort/错误 ACK/B 优先集成场景未执行；mode1 Y8 未验证；G3/G4 not_run（awaiting_hardware）；真实 PCIe/RK、bit、Flash 未做。
- **下一最短动作**：
  1. 板级集成壳或收敛观测/状态总线，把顶层 IO 从 2813 降到 ≤286，重跑一次 synth（本包 synth 剩余 1 次），拿到 WNS/TNS/hold/资源后再决定是否布线。
  2. 定位 P1 共享流在 `m_ready` 反压下的重复/丢拍与死锁（同一驱动无间隙时逐字节正确，可先做“监视反压”定向波形），并增加“帧不完整不得提交”的保护（按拍数/CRC 校验）。
  3. 用集成 TB（或本报告 S1–S5 结构）补 abort、A 禁用/B 优先、错误 ACK、mode1 Y8 的场景，每场景独立复位。
  4. 重新冻结 manifest：把 5 份文档纳入哈希、登记或清理 `sim_output.txt`/`transcript`、修正 build-entry 的 `-Full` 说明与 result-r0 的场景/资源表述。
  5. RK 侧按 `a1u1_decode.py` 头定义联调真实 PCIe（本轮未做，不得宣称通过）。

## 9. 未测项与回退

- 未测：1920x1080 全尺寸仿真（仅 64x48 缩尺）；最终 STA/CDC 报告（综合未过）；abort/错误 ACK/B 优先的集成行为；mode1/2/3 监视流；真实 DDR/PCIe IP 适配；bit/上板/长稳/吞吐（G3/G4）。
- 回退入口：本报告与 `test-reports/INT.P4/` 证据只针对冻结 manifest `31a3bbf2…`；若开发修复后重新冻结，旧证据仅可在“文件哈希不变且重新绑定新 manifest”时复用于未受影响项（见下 retest 的 reuse_decision_paths），不得把本轮 FAIL 场景与新一轮修复日志拼成 PASS。

## 10. retest 元数据

- required_dimensions：`functional`、`engineering`、`system`
- required_checks：
  - manifest 重新冻结并全量哈希复核（P1/P2/P3/A1/新文件/文档），`stopped_modifying=true`，无漂移；
  - 修复后重跑：测试者 TB S1（B 单帧内容/描述符/身份/释放）、S2（无复位第二帧）、S3（`a_enable=0` 门控）、S4（A 单帧）、S5（监视反压：不得死锁、不得提交损坏帧）；
  - 开发集成 TB 默认场景 + `+EXTRA=1`（须真正执行 abort/A disabled+B priority/错误 ACK）；
  - P1/P2/P3 既有 TB 与 Python 入口复跑；
  - A1U1 样例独立重算（本报告的 `oracle_sample.py` 可直接复用）；
  - TD 综合：clk 5.333ns 下 WNS/TNS≥0、hold≥0、0 违例、ERAM+CWC≤300、IO≤286；route 条件执行并绑定最终 DB/报告；
  - 文档/manifest/build-entry/shortest-steps 一致性；未伪造引脚/ADC/时序；未写 `D:/TD/**`、未动 b20 目录与计数、bitgen/CWC/download/Flash 保持 0。
- input_status：`same`（本轮为冻结输入的首次验收，无漂移）；修复后复测预期为 `changed`（需重新绑定新 manifest）。
- reuse_decision_paths（仅以下证据可在“同哈希 + 绑定新 manifest”时复用）：
  - `workflow/runs/20261026-2138_fpga-integrated-delivery/test-reports/INT.P4/oracle_sample.py`、`analyze_s5.py`、`verify_manifest.py`（测试者工具本身）；
  - `tools/integrated_delivery/evidence/integrated_sample.{a1u1,raw,json}` 与 `test-reports/INT.P4/evidence/integrated_sample.*`（哈希一致时，样例内容判据可复用）；
  - `test-reports/INT.P4/regression/{p1_tb_raw10_packer.log,p2_tb_egress.log,p3_tb_scheduler.log,integrated_default.log}`（若 P1/P2/P3/集成默认 RTL 哈希不变）；
  - 不得复用：本轮 S5/开发 TB T2 的失败结论作为“新候选已修复”的证据；不得复用未执行的 abort/错误 ACK/B 优先场景。
- blocked：`[]`（无外部设备/工具/权限阻塞；TD 工具可用、综合已实际运行；G3/G4 为规划冻结的 not_run。）
