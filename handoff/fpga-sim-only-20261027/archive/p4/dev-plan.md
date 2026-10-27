# 开发计划 — 20261026-2138_fpga-integrated-delivery

## 1. 范围与拆分结论
- 主要可验收目标：1（集成候选）。
- 正式工作包：4（INT.P1~INT.P4），两级（需求→工作包），每包≤5项语义步骤。
- 批大小：1（用户未指定其他值）。
- 本轮不修改全局tasks.json、不关闭父任务、不操作硬件/下载/Flash。
- 当前进度（2026-10-27 05:20）：P1 r1 PASS、P2 r0 PASS、P3 r1 PASS；P4 r2 FAIL（functional pass / engineering fail G2：112 端点、WNS −0.637ns、TNS −69.776ns / system pass，G5 已通过），round3 为最后一次实际修复（repair #3/3）已派发，见 §3.7；失败后处理与板级承接见 §3.8。
- 用户 2026-10-27 新增的板级集成需求记于 §9，**本 run 不派发**，不改变 1目标/4包计数；P4 验收后由原规划承接。

## 2. 任务计划总表
| task_id | 问题/产物 | 实际工作树/允许写路径 | 依赖 | functional | engineering | system | 必要G层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| INT.P1 | RAW10打包修正、好帧发布/取消、三算法与选路接入、内容独立像素参考验证 | `fpga/csi2/src/integrated_delivery/` + run dir | b15链路审查结论、T09算法RTL、T06存储 | 必须 | 必须 | 必须 | G0,G1,G2 | PASS (r1) | 已完成 |
| INT.P2 | A+输出槽→PCIe发送后端；描述符/长度/尾拍/完成/释放；A1U1与R10F关系；RAW入口保留 | `fpga/csi2/src/integrated_delivery/` + run dir | INT.P1 (PASS r1 manifest)、T10 A+ RTL、T11 PCIe后端 | 必须 | 必须 | 必须 | G0,G1,G2 | PASS (r0; RK真实PCIe传输待联调) | 已完成；RK联调仍待 |
| INT.P3 | 双路A/B采集、身份、必要调度；复用离线+b20有效结果；防串帧/混路/覆盖 | `fpga/csi2/src/integrated_delivery/` + run dir | INT.P1/P2 (P2 r0 PASS)、b20有效结果或b18基线、双路离线包 | 必须 | 必须 | 必须 | G0,G1,G2 | PASS (r1; A路仍门控，待b20板级有效结果) | 已完成；A路真实接入待板级结果 |
| INT.P4 | 同一manifest集成交付：P1+P2+P3+A+核同一候选绑定；必要回归；隔离目录综合/条件布线；交付物包 | `fpga/csi2/src/integrated_delivery/` + `tools/integrated_delivery/` + run dir | INT.P1/P2/P3 PASS；A+核复用b20 r0只读候选 | 必须 | 必须 (综合必做/布线条件) | 必须 (board=not_run/条件) | G0,G1,G2(综合必做,布线条件),G5 | **⚠ 未通过（r3 收尾）**：r2 functional+system pass / G2 112端点、−0.637ns；r3 G2 0端点、+0.072ns / functional fail（派生变体等价破坏） | 收尾完成，见 §10 + `decision-matrix.md`/`final-summary.md`/`handoff.md`；不派第 4 轮；板级集成见新 run 请求 `follow-on-run-request.md` |

## 3. 包内语义步骤（每包≤5）

### INT.P1 真实输入与处理
1. 复用b15链路审查结论，修正RAW10打包（4×10bit样本→packed RAW10字节），不重修已处理PAXI。
2. 接入好帧发布与取消事务（晚CRC/FE裁决、最后ROI样本、abort/重SOF同拍commit）。
3. 接入现有三算法（Bayer→Y8、高斯、前帧HE）与模式/输出选路，保留RAW旁路。
4. 用独立源像素参考确认内容正确，不只CRC相同。
5. 冻结本包manifest与G1证据。

### INT.P2 压缩到PCIe
1. 将实际A+输出槽接入现有PCIe发送后端。
2. 贯通描述符、有效长度、尾拍、完成及释放。
3. 明确A1U1与既有R10F承载关系，保持RAW接收入口可用。
4. 提供RK可复现文件样例与解码工具；缺少RK联调明确标待联调。
5. 冻结本包manifest与G1/G2证据。

### INT.P3 双路接入
1. 复用已有双路离线成果与b20有效结果（只读）。
2. 接入A/B采集、身份与必要调度，防串帧/混路/覆盖。
3. B路优先推进；A路在b20有效结果后接入。
4. A路受阻时继续完成B路后续链路，避免全线等待。
5. 冻结本包manifest与G1/G2证据。

### INT.P4 同候选集成交付（2026-10-27 冻结）
1. 建单个集成顶层 `integrated_delivery_top.v`：P1输入处理 → A+核（b20 r0只读候选 `a1_frame_top.v`/`a1_deflate_core.v`）→ A+槽存储 → P2 `aplus_pcie_egress_adapter` → PCIe发送后端描述符面；P3 `dual_channel_capture_scheduler` 做A/B身份、门控与释放；全部单 `clk` 域。不得为待实现模块留stub充数。
2. 统一候选manifest：P1/P2/P3冻结文件按各自manifest哈希逐项复核并绑定；新增集成顶层/胶合/TB/工具/构建脚本；b20/upstream A+核以只读路径+哈希绑定；`stopped_modifying=true`。
3. 必要回归（同一冻结候选）：P1/P2/P3既有TB与工具重跑 + 新集成TB（缩尺帧，外部DDR模型+host ACK模型，真实DUT）覆盖背压、abort、A disabled/B优先、RAW与Y8不混、描述符/长度/尾拍/完成/释放、A1U1样例解码。
4. 隔离目录TD综合（必做）；布线仅当综合通过且TD接受不伪造引脚/约束的项目时尝试一次；bitgen/CWC/下载本轮不做（无板级集成顶层与ADC，不伪造）。如实记录not_run与差距。
5. 交付包：manifest、协议说明、构建入口、解码工具用法、真实样例（RTL仿真字节+A1U1解码）、最短操作步骤、回归证据；明确已接通/验证方式/剩余阻塞/下一条最短操作；随后停止修改交独立综合测试。

#### INT.P4 冻结边界与构建政策
- 集成顶层端口与内部时钟：单 `clk`（目标187.5MHz，5.333ns），异步低有效`rst_n`；本轮**不新增CDC/异步FIFO**（新增即停回规划）。
- 允许新增文件：`fpga/csi2/src/integrated_delivery/{integrated_delivery_top.v,tb_integrated_delivery_top.v}`；round2/round3 另允许仅为时序/握手的最小派生变体 `fpga/csi2/src/integrated_delivery/*_p4.v`（含等价 TB），见 §3.6/§3.7；`tools/integrated_delivery/**` 下脚本/TB/SDC/TCL/样例/证据；run目录下`INT.P4/**`与manifest/文档。
- 只读引用：b20 r0 `changed-src/{a1_frame_top.v,a1_deflate_core.v,a1_ddr_slot_store.v,a1_ddr_arb2.v}` 与 `upstream/.../codec/*`、`fpga/csi2/src/img/**`、`pcie_integration/rtl/ep_side/{ddr,img}/**`。不复制、不修改被保护源（`fpga/csi2/src/img/**` 本轮只读）；若需补丁，另建新文件并在manifest中说明来源与差异。
- 若P1/P2/P3接口无法在不改语义的前提下直连：优先加薄胶合；需改其生产文件时必须在新manifest记录新版本、重跑对应包回归并在报告写明，不得静默改。
- TD政策：工程只建在 `workflow/runs/<run>/INT.P4/td/`；源码以绝对路径引用只读树；不得写`D:/TD/work/csi2`、不得复用/改写b20工程与其synth/route/bitgen计数、不得继承其下载额度。启动前只读确认无`pnmain`等TD进程；若出现其他run的TD活动，立即停并返回blocked，不共享设备/工程。
- TD计数（本包分配，round3 更新；详见 §3.7）：synth 终身≤9（r0/r1已用3、round2已用3，round3额外≤3）、route≤1、bitgen=0、CWC=0、downloads=0、Flash=0。综合门槛：`clk` WNS/TNS≥0、hold≥0、0违例（以`flow.status`统计为准）、资源在器件内、ERAM+CWC≤300、IO≤286、无未驱动DUT输入；未达标不布线、不写bit，记录FAIL/差距。若TD因缺ADC/引脚约束拒绝布线，如实记route=not_run，不伪造ADC；若TD以自动IO布局接受布线，可跑一次，但STA只声明内部路径，IO未约束与板级时序不作通过，记差距。
- 只读核对（2026-10-27 00:50 规划）：无`pnmain`/TD进程；`vsim` PID 61632/37556 在跑（非本角色所有，不得杀）；COM8/FTDI当前存在（历史间歇，不能当稳定板窗）；b20 r0已routed 0违例、SWNS +0.012薄裕量、bit/CWC存在、board=blocked(0下载)，其计数与目录一律不动。
- round2 派发前只读复核（2026-10-27 03:57 规划）：无`pnmain`/TD/`vsim`进程；`INT.P4-r1-manifest.json` SHA256=`CFFCF54D…`（与测试者记录一致）；`fpga/csi2/src/img/*.v`=10 个；候选 `integrated_delivery/work/` 仍存在 6 文件（遗留，登记不删）。

#### INT.P4 交付物清单（冻结路径）
- 候选：`fpga/csi2/src/integrated_delivery/{integrated_delivery_top.v,tb_integrated_delivery_top.v}` + 既有P1/P2/P3文件（不改或显式记新版本）。
- 构建/仿真入口：`tools/integrated_delivery/run_integrated_sim.ps1`、`run_integrated_build.ps1`、`td/01_synth.tcl`、`td/02_route.tcl`、`td/integrated_core.sdc`、`gen_manifest_intp4.py`。
- 解码工具与样例：`tools/integrated_delivery/a1u1_decode.py`（既有）+ `evidence/integrated_sample.a1u1`/`.json`（集成仿真产生并解码校验）。
- run目录：`INT.P4-r0-manifest.json`、`INT.P4-r1-manifest.json`、`INT.P4-r2-manifest.json`、`INT.P4-r3-manifest.json`、`INT.P4-protocol.md`、`INT.P4-build-entry.md`、`INT.P4-shortest-steps.md`、`INT.P4/regression/**`、`INT.P4/td/**`（含TD日志/报告；无bit则明确not_run）、`INT.P4/result-r0.md`、`INT.P4/result-r1.md`、`INT.P4/result-r2.md`、`INT.P4/result-r3.md`、`INT.P4-lessons.md`。
- 测试：独立综合测试者报告 `test-reports/INT.P4-r0-integrated.md`、`INT.P4-r1-integrated.md`、`INT.P4-r2-integrated.md`、round3 的 `INT.P4-r3-integrated.md`（`dimension=integrated`）。
- bit：本轮冻结为not_run（无板级集成顶层/ADC，不伪造）；不得把b20 `a1_board.bit`写成集成交付bit。b20 bit仅作为独立历史候选在最终汇总中标注。

#### INT.P4 验收门槛
- G0：顶层接口/单位/模式/时钟/复位冻结且与RTL一致；A1U1与R10F、长度命名、RAW/Y8区分无冲突。
- G1：同一manifest下P1/P2/P3回归重跑通过 + 集成TB真实DUT通过（背压、abort、A disabled、B优先、身份/释放、描述符/长度/尾拍/完成/释放、RAW旁路不被Y8污染）；A1U1样例解码header/stream CRC与zlib通过；独立判据不得只复用开发TB。
- G2：隔离目录综合必做并出报告；布线条件允许才做。通过=clk 187.5MHz下0违例且WNS/TNS≥0、hold≥0、资源在器件内、ERAM+CWC≤300；未运行=not_run，不得写pass。
- G3/G4：not_run + awaiting_hardware（无bit/无板窗）；不得把仿真/P2接口仿真写成真实PCIe/上板通过。
- G5：manifest、协议、构建入口、解码工具、样例、最短步骤齐全且与证据一致；RK真实PCIe传输仍标待联调。
- 判定口径：本包PASS=交付包与同候选功能/工程证据通过，**不是**整机/bit/上板完成。

### INT.P4 round2 修复（2026-10-27 03:57 冻结；repair #2/3）

权威输入：`test-reports/INT.P4-r1-integrated.md`（失败清单 D5a–D5e/E1–E4）、`INT.P4/result-r1.md`、`INT.P4-r1-manifest.json`（SHA256 `CFFCF54D…`）、本文件 §3 INT.P4。范围仍是同一包：不加功能、不做板级集成（§9 为验收后后续线）。

包内语义步骤（≤5，round2）：
1. **G2 时序收敛**：最差路径在 DUT 内部 `u_p1/u_algo`：`u_obuf_gau/count_reg[0]`→`u_front/u_row/rb0_reg[0].d`（6.818ns，net 4.199ns，fanout 320，8级），即 P1 三算法共享流的全或全无 ready 链穿过前端行缓冲写路径。`fpga/csi2/src/img/**` 本轮**只读**，不得原地改；优先在 `fpga/csi2/src/integrated_delivery/` 下新增仅做时序/握手的最小派生变体（如 `img_algo_parallel_top_p4.v`，确有必要才加子模块派生副本），插入寄存器/小 skid 边界，使下游 FIFO 占用不再组合直达前端行缓冲写路径，并从 `integrated_input_processing_top.v` 实例化；manifest 记录源哈希+diff 摘要。能只在既有集成文件内解决更好。不新增 CDC/异步 FIFO、不改时钟。像素/数据语义必须不变（见第4步等价证据）。
2. **综合 harness 完整性**：`tools/integrated_delivery/synth/integrated_delivery_synth_wrap.v` 必须驱动全部 DUT DDR 从口输入（`ddr_awready/ddr_wready/ddr_arready/ddr_rvalid/ddr_rdata`），消除 `HDL-5314` 未驱动 DUT 输入告警；`u_egress`/`u_arb` 的资源/时序须在面积或映射报告中可核对；文档写明覆盖边界（仅内部寄存器 STA、IO 未约束、harness 不是板级顶层；不伪造 ADC/引脚/时序豁免；内部路径不得 false_path/multicycle；保持单 5.333ns 时钟）。
3. **G5 交付一致性**：`01_synth.tcl` 改为从 `flow.status`/时序报告取真实 `Viol Endpoints`（不得再统计打印的 `Slack : -` 行）；把 r1 真实 **330** 端点与新 r2 数字写回 manifest/result/build-entry/shortest-steps；img 源数量 9→**10**；遗留候选文件表述改为“已登记、未删除”；`work/` 目录按遗留未登记产物登记（不批量删除）；把实际编译的 10 个 img 源、b20 4 文件、派生变体、TB、harness、TCL/SDC 全部绑定进 r2 manifest。
4. **全量回归（同一候选、一次会话）**：开发 TB mode4/mode1 默认与 `+EXTRA`（T1–T6）；P1/P2/P3 既有 TB 与 Python 工具；A1U1 解码；mode1/mode4 样例哈希须等于 r1 冻结样例哈希。若引入派生 algo 变体，须给同激励下 y8/gau/he 与原始 `img_algo_parallel_top` 的数据序列等价证据（允许增加延迟，不允许顺序/sof/eol/eof 标记变化）并留日志；否则必须显式记录“算法内容未核验”的差距，不得声称语义未变。
5. **冻结与停手**：`INT.P4-r2-manifest.json`（`stopped_modifying=true`、`drift_count=0`）、`result-r2.md`（真实数字）、build-entry/shortest-steps/protocol/lessons 更新；在本节额度内综合出 G2 证据；route 仅在 G2 通过且 TD 接受合法约束时做 1 次；bitgen/CWC/下载/Flash 保持 0。随后停止修改，交同一综合测试者 `INT.P4-r2-integrated.md`。

round2 判定门槛（覆盖 r1 失败项）：
- **G2 pass** = `flow.status` 的 `Viol Endpoints = 0`、WNS≥0、TNS≥0、hold≥0、ERAM+CWC≤300、资源在器件内、IO≤286、无未驱动 DUT 输入告警；端点数以报告统计为准，不得用打印条数。布线后若运行，最终 STA 以 routed DB 为准，IO 未约束记差距。
- **G5 pass** = 端点真实计数、img 10 文件全部绑定、遗留文件/work 目录登记、build-entry 编译文件数与实际一致、无虚假“删除”、无 bit/上板/真实 PCIe/A 路通过声明。
- **G1 pass** = 上述全量回归通过 + 独立测试者 S1–S5 在新 manifest 上复跑；派生变体等价证据齐备或差距显式记录。
- G3/G4 仍 not_run（无板级 bit/板窗；长稳后置）。

额度（本轮明确授权，见 dispatch.td_policy/task_allocation）：
- INT.P4 round2 额外 **synth≤3**（任务终身 ≤6；r0/r1 已用 3：1 次有效 + 1 次未建工程 + 1 次 harness 重跑）。全局 `synth_max` 由 3 调至 **6**。
- 授权来源：用户 2026-10-26 21:38“正常防死循环的5倍额度”原话 + 规划在本 dispatch 书面授予的有限子额度。理由：G2 是硬门槛，前 3 次被未建工程与 harness 重跑消耗，实际时序修复后至少需 1 次综合并有有限重试余量；6 仍有限、每次综合数分钟、不涉及 bitgen/下载。**不自动续期**：round2 第 3 次综合后若 G2 仍未过，停手返回 FAIL；round3 额度只能由原规划见新证据后书面追加。
- route≤1（条件、未用）、bitgen=0、CWC=0、downloads=0、Flash=0；不写 `D:/TD/**`、不动 b18/b19/b20 目录与计数。

### INT.P4 round3 修复（2026-10-27 05:20 冻结；repair #3/3，最后一轮）

**决策：派发 round3 实际修复。** 依据（只读 r2 证据，不做全面复审）：
- r2 已把 setup 从 330 端点 / WNS −1.549ns / TNS −271.427ns 压到 **112 端点 / WNS −0.637ns / TNS −69.776ns**；同一 5.333ns 时钟、无豁免、无 false_path/multicycle。剩余 gap 只有 0.637ns，且失败家族已收敛到单一结构。
- 最差路径：`u_dut/u_p1/u_algo/u_obuf_gau/count_reg[0]` → `pipe_en`(fo199) → `evt_en`(fo155) → `ra0`(fo256) → 320 深 LUT RAM 读 mux → `u_gau/u_row/rb0_reg[0].d`（5.906ns，cell 2.304 / net 3.602）；`u_front` 有同构副本。本质是"行缓冲读地址在同一个周期内由高扇出使能组合生成，并直接进深读 mux"。
- 标准、非放宽式修复：把读地址/使能做成寄存器边界，并按同一固定延迟对齐数据窗口与 `prod_*` 标记；这属于 retime，不是重写算法、不是改约束、不是降频。
- 若不派：P4 只能以 ⚠（G2 fail）收口，且该路径原样进入板级整机网表，板级重新计时后仍是同一违例家族；用户明确"以推进度为先"、期限 2026-10-27，一轮定位明确的 retime 比把已知违例带进板级更省时。
- 代价有限：`fpga/csi2/src/img/**` 仍只读、不改 b20/upstream、不加 CDC/异步 FIFO、不改时钟；只新增派生变体，用同一等价 TB + 全量回归证明 token 序列不变；综合每次数分钟。

范围仍是同一包（INT.P4），不加功能、不做板级集成（§9 为验收后后续线）。权威输入：`test-reports/INT.P4-r2-integrated.md`、`INT.P4/result-r2.md`、`INT.P4-r2-manifest.json`（SHA256 `DFAB7F9D…`）、`INT.P4/td/syn_r2_run2/**`、本文件 §3 与 §3.6。

包内语义步骤（≤5，round3）：
1. **行缓冲读路径 retime（核心）**：在 `fpga/csi2/src/integrated_delivery/` 下新增 `algo_rowwin3_p4.v`（派生自只读 `fpga/csi2/src/img/algo_rowwin3.v`；端口、参数、帧调度语义不变），把 `ra0/ra1/ra2`（及必要的 bank 选择 / `cbq`/`ubq`）改为寄存器输出后再读 `bank0/1/2`，使 320 深读 mux 的地址与 bank 选择来自触发器；同步把 `rb*` → `rd_c/rd_u` → `rdc_r1/r2,rdu_r1/r2` → `win_*`/`prod_*` 对齐增加**同一固定延迟**。只允许"固定增加延迟"：token 顺序、sof/eol/eof/abort 标记、生产槽数量、flush 时序与帧调度都不许变。若地址寄存仍不足，可在派生 `gray8_gaussian3x3_stream_p4.v` / `bayer_raw10_demosaic4_p4.v` 内把 `pipe_en`/`evt_en` 也做寄存器边界，但不得改变 `s_ready` 接受速率与背压语义。**禁止**以 `ram_style` 等属性实验充当修复（r2 run3 已证 netlist 不变）。
2. **两个实例都换用派生变体**：`bayer_raw10_demosaic4_p4.v` 的 `u_row` 改实例化 `algo_rowwin3_p4`；新增 `gray8_gaussian3x3_stream_p4.v`（仅实例/握手差异）并在 `img_algo_parallel_top_p4.v` 中替换 `u_gau`（当前直接实例化只读 `gray8_gaussian3x3_stream`）；`gray8_gaussian3x3_frame_p4.v` 仅在确有必要时新增。`fpga/csi2/src/img/**` 一律不原地改。
3. **等价与全量回归（同一候选、一次会话）**：更新 `tb_img_algo_equiv_p4.v` 以覆盖新增固定延迟（按 token 序列比较、允许延迟），三 seed 仍 `CHECK_REF_NEW PASS`；dev TB MODE=4/1 默认 + `+EXTRA`（T1–T6）65/0；P1/P2/P3 TB 与 Python 工具；A1U1 解码；mode1/mode4 样例哈希必须等于 r2 冻结值（`79E35F28…`/`1357408F…`/`76D88910…`）。新增延迟周期数与派生 diff 摘要写入 manifest。
4. **TD 综合取证（有限额度）**：每次综合前必须已有该源集的等价仿真通过证据，且该次源集哈希与上一次综合**不同**（禁止同 netlist 重跑）；取 `flow.status` 的 `NUM_FEPS`/WNS/TNS/hold/资源/ERAM+CWC/IO/未驱动告警；route 仅在 G2 通过且 TD 接受合法约束时做 1 次。
5. **证据卫生与冻结**：修 E5a–E5c（`INT.P4/td/run.log` 的 r1 旧日志移入 `r1-evidence/` 或 manifest 加注；`INT.P4/td/01_synth.tcl` 标注 run3 实验副本或替换为正式副本；`int_p4_Runs/syn_1/` 混合目录注明权威证据是 `syn_r2_run2/`）；冻结 `INT.P4-r3-manifest.json`（`stopped_modifying=true`、`drift_count=0`）、`result-r3.md`、build-entry/shortest-steps/protocol/lessons；bitgen/CWC/下载/Flash 保持 0。

round3 判定门槛（覆盖 r2 唯一失败项 G2）：
- **G2 pass** = `flow.status` 的 `Viol Endpoints = 0`、WNS≥0、TNS≥0、hold≥0、ERAM+CWC≤300、资源在器件内、IO≤286、无未驱动 DUT 输入告警；端点以 `flow.status`/报告统计为准；无 false_path/multicycle；单 5.333ns 时钟；若布线，以 routed DB 的最终 STA 为准并记录 IO 未约束差距。
- **G1 pass** = 全量回归通过 + 测试者 S1–S5 复跑 + 派生变体 token 等价（允许固定延迟）+ 样例哈希不变；HE 停顿敏感性仍作为既有差距记录，不因本轮通过而消失。
- **G5 pass** = r3 真实数字、manifest 全量绑定（10 个 img 源只读哈希、派生变体、harness/tcl/sdc、TD 证据）、E5a–E5c 已处理、编译文件数与入口一致、无 bit/上板/真实 PCIe/A 路通过声明。
- G3/G4 仍 not_run（无集成 bit/板窗；长稳后置）。
- **判定口径**：G2 是硬门槛，未达 0/≥0 不得写 pass，也不得写 route/bit。

额度（本轮明确授权，见 dispatch.td_policy/task_allocation）：
- INT.P4 round3 额外 **synth≤3**，任务终身 ≤**9**（r0/r1 3 次 + round2 3 次 = 6 已用）；全局 `synth_max` 由 6 调至 **9**（仍低于默认 3 的 5 倍上限 15）。
- 授权来源：用户 2026-10-26 21:38"正常防死循环的5倍额度"原话（`request.md`）+ 规划在本 dispatch 书面授予的有限子额度。
- 理由：最后一轮修复；retime 涉及 2 个派生变体与两个实例，至少需要"修复后一次取证 + 残留路径再收敛一次 + 一次流程/推断失败余量"；单次综合数分钟，不涉及 bitgen/下载/板卡。**不自动续期**：round3 三次用尽仍不过 G2 即停手返回 FAIL，不得第 4 次。
- 每次综合必须满足"源集哈希不同 + 该源集等价仿真已过 + 有明确假设"；否则视为浪费额度，不允许。
- route≤1（条件、未用），bitgen=0、CWC=0、downloads=0、Flash=0；不写 `D:/TD/**`、不动 b18/b19/b20 与计数。
- round3 派发前只读复核（2026-10-27 05:20 规划）：无 `pnmain`/TD/`vsim` 进程；`INT.P4-r2-manifest.json` SHA256=`DFAB7F9D…`（与测试者记录一致）；`fpga/csi2/src/img/*.v`=10；候选目录 13 个 `.v` + 2 个遗留文本文件，`work/` 仍在（登记、不删）。

### INT.P4 round3 失败后的处理与板级工作线承接（2026-10-27 05:20 冻结）

1. **P4 状态**：若 round3 仍 FAIL，INT.P4 记为 **⚠ 未通过**：`functional=pass`、`system=pass`、`engineering=G2 fail`（写真实端点/WNS/TNS），route/bit/CWC/download/Flash 仍为 0/not_run。**任何文档、handoff、final-summary、user-summary 不得把该 ⚠ 写成 PASS，也不得写"时序已收敛/RK 通过/上板通过"**。已通过的功能与交付证据仍按 manifest 引用，但只能表述为"仿真功能与交付一致性通过；187.5MHz 单时钟核心 setup 未收敛"。
2. **原因归属**：剩余违例属设计/门槛失败（不是 blocked、不是缺设备）。round3 额度用尽即停止，不再尝试第 4 次综合；后续若再修该路径，须由原规划在新任务/新授权中处理，不得复用本轮 P4 额度。
3. **板级工作线可在 ⚠ 下继续**（决策），但必须同时满足下列诚实标注条件；理由是板级线交付的是带真实时钟/引脚/CDC 的独立候选，本来就要重新计时与签核，P4 的 G2 失败既不会被新顶层自动继承为通过，也不会因等待而消失：
   - (a) 板级计划/交接首段必须写"承接自 ⚠ INT.P4（G2 fail：X 端点、WNS −Y ns；未做 route/bit）"，并把 `algo_rowwin3` 行缓冲读路径列为**已知带出风险**；
   - (b) 板级 bit 必须有自己的真实顶层 STA/时序报告（真实时钟、IO 约束），**不得用 P4 综合数字代表板级时序**，不得声称"P4 通过"或"整机时序签核"；
   - (c) 若板级在 187.5MHz 仍违例而为 bring-up 生成 bit/下载，必须标注"**带已知时序违例的 bring-up bit**"，且需用户硬件窗口与独立冻结额度；不得写成性能/可靠性达标；
   - (d) P4 的仿真证据只作"冻结 manifest 上的仿真功能通过"，不等于板上验证；
   - (e) 板级线的 TD/板卡/下载/Flash 额度与 P4 分开冻结，不继承 P4 的已用或剩余计数。
4. **若 round3 PASS**：P4 记 PASS（附 G3/G4 not_run、HE 停顿敏感性、RK 待联调、IO 未约束等差距）；route 若做则绑定 routed DB 与最终 STA；bit 仍不在本包，由 §9 板级线另立。
5. **收尾责任**：无论 PASS/⚠，均交回原规划写 `handoff.md`/`final-summary.md`/`user-summary.md`，并在 `workflow/tasks.json` 记录真实状态（不改本 run 外的全局任务板由主源负责）；板级线由原规划准备后续 run 的计划与启动文本，本 run 不派发（§9）。

## 4. 依赖与顺序
- INT.P1 → INT.P2 → INT.P3 → INT.P4（P1 r1 PASS、P2 r0 PASS、P3 r1 PASS，链路已满足）。
- INT.P4 复用b20 r0 A+核候选（只读、薄裕量+0.012、board blocked）；A路仍按`a_enable`门控，不声称A路通过。
- INT.P4 round3 是本任务最后一次实际修复（repair #3/3），只承接 r2 唯一失败项 G2；PASS 后由原规划收尾，FAIL 则保留 ⚠ 并按 §3.8 处理。
- 板级集成工作线（§9）排在本 run 之后，不属于本 run 的包；其启动以 P4 结果（PASS 或经用户知情的 ⚠ 承接）为前置，且需独立冻结 TD/板卡/下载额度与设备窗口。
- 并行仅限互不冲突的离线验证/文档/解码工具准备；不得多开发同时修改同一顶层。
- 其他活动run（`20261026-231711_fpga-a-plus-h-prototype`、`20261026-143924_fpga-1080p30-g0-production`等）与b18/b19/b20一律只读，不共享TD/板卡。

## 5. G层与门槛
- G0：接口/单位/预算/双方责任（本run指南+§3 INT.P4冻结边界）。
- G1：模型/仿真/软件正反向、边界、恢复、反压；INT.P4须同候选回归+集成TB真实DUT。
- G2：综合（必做）、条件布线、最终STA、约束覆盖、CDC/复位、资源；未运行如实not_run。round3 以 0 违例/WNS/TNS≥0 为唯一通过口径。
- G3：上板功能（本轮无条件：无集成bit/无板窗）→ not_run + awaiting_hardware。
- G4：长稳/性能（本轮后置，仅记录差距）→ not_run。
- G5：集成/发布（本轮部分：manifest、协议、构建入口、解码工具、样例、最短步骤）。
- 时序门槛：clk 187.5MHz WNS/TNS≥0、hold≥0、0违例；资源在器件内；ERAM+CWC≤300；IO≤286；无未驱动 DUT 输入。
- 压缩：最坏膨胀+0.1044%；吞吐≥77.76MB/s（功能先跑通，未达记录差距）。
- PCIe：描述符/长度/尾拍/完成/释放贯通；不把文件回放/接口仿真写成真实PCIe传输通过。
- bit：本轮not_run（无板级集成顶层/ADC）；不得用b20 bit冒充；round3 PASS 也不产 bit。
- ⚠ 口径：round3 仍 FAIL 时 P4 保持 ⚠（functional/system pass、G2 fail），不得写 PASS；板级线可继续但须满足 §3.8 的全部诚实标注。

## 6. 工具/设备/预算
- TD/板卡只由一个责任流程使用；下载不得继承b20额度；INT.P4下载=0（无bit）。
- 全局上限：Flash=0；下载≤1；综合≤9（round3 授权由6上调，限定用途见 §3.7）；布线≤2；bitgen≤1；CWC≤1。
- INT.P4子分配（round3 更新）：synth 终身≤9（r0/r1 3 次 + round2 3 次 = 6 已用，round3 额外≤3）、route≤1（未用）、bitgen=0、CWC=0、downloads=0；剩余额度不转移、不继承；round3 用尽仍不过 G2 则停手返回 FAIL，不自行扩额。
- 执行预算（5倍用户授权，仅限当前任务）：
  - 规划：75分钟（默认15×5），150次工具调用（默认30×5）。
  - 开发：225分钟（默认45×5），150次工具调用。
  - 综合测试：225分钟（默认45×5），150次工具调用。
  - 单问题搜索/读取：15轮（默认3×5）。
  - 同失败命令：首次+最多9次重试（默认首次+1次，按5倍放宽），仅新证据/参数纠正时重试。
  - 无进展循环：10次（默认2×5）。
  - 授权来源：用户2026-10-26 21:38原话"同时我给这次任务开正常防死循环的5倍额度"及request.md机械登记。
- 授权不改变任务/包/层上限（1目标、4包、两级、每包5步）。
- 用户期限：最迟2026-10-27。开发/测试到点仍无结论，冻结现有证据返回，不空转。

## 7. 停止/回退/阻塞
- 缺工具/设备/资料/授权/用户输入/额度→blocked交原规划备条件，不空转。
- TD：出现其他run的TD/`pnmain`进程、license错误、缺ADC导致无法布线→停止并记录；不共享、不伪造ADC/引脚/时序。
- 两轮无进展或单问题超15轮→返回blocked/problem，不刷次数。
- 三轮实际修复后仍FAIL→保留⚠未通过，由原规划在本轮边界内派独立任务。
- 回退：保留b18/b19/b20及历史候选/manifest；删除只针对单个明确路径。
- 不批量删除、不写Flash、不自动操作硬件、不发外部消息、不杀他人进程（含PID 61632/37556）。
- 权威协作仓（2026-10-27 AGENTS更新）：本任务只在本工作区产出，不向`D:/fpga/repos/**`或GitHub授权仓提交/推送/fork；协议/样例保持自包含，供用户后续授权同步。

## 8. 下一动作
- 派 INT.P4 原开发 round3（repair #3/3，最后一轮）：按 §3.7 对 `algo_rowwin3` 行缓冲读路径做寄存器 retime（派生 `algo_rowwin3_p4.v` + `gray8_gaussian3x3_stream_p4.v`，两个实例都换用），保持 token 序列不变；同步修 E5a–E5c 并冻结 r3 manifest；额度见 dispatch（round3 额外 synth≤3、终身≤9，route 条件≤1，bitgen/CWC/下载/Flash=0）。
- round3 冻结后交同一综合测试者 `test-reports/INT.P4-r3-integrated.md`。PASS 后由原规划写 `handoff.md`/`final-summary.md`/`user-summary.md` 收尾；FAIL 则按 §3.8 保留 ⚠ 并记录板级承接条件；bit/上板/真实 PCIe/A 路缺项一律如实列差距。
- 板级集成线（§9）本 run 不派发，由收尾后的原规划准备后续 run。
- 主仅按dispatch.json调度；详细内容留本计划。

## 9. 后续工作线：INT.P4 验收后的板级集成（用户 2026-10-27 新需求，本 run 不派发）

**用户原话（原样记录）**：“当前 P4 完成并验收后，沿同一工作线继续板级集成。复用已通 A/B 工程，将 P4 接入真实相机、DDR 和 PCIe，补齐板级顶层、时钟复位及必要跨时钟连接、引脚约束和构建入口，完成整机 bit。下一目标是先 B 后 A 的真实单路压缩帧 PCIe 完整导出。以推进度为先，长稳和非阻塞优化后置。”

**归属与计数关系**：
- 本 run 仍是 **1 个主要可验收目标、4 个正式包（INT.P1–P4）**、两级、每包≤5 步。板级集成**不是第 5 包**，不改变本 run 的计数、依赖与验收口径；本 run 不为它建任务、不派发、不预支其额度。
- 板级线是同一工作线的**后续 run**（新目标）：由原规划在 P4 收尾后准备其需求拆分、边界、TD/板卡额度与启动文本；用户已给出“P4 完成并验收后沿同一工作线继续”的明确方向，但具体范围/额度仍需后续规划冻结。
- 后续主题仍为 3 条（板级整机与 B→A 单路导出；RK/真实 PCIe 联调；长稳/性能优化），保留原需求路径 `request.md`。

**权威协作仓（2026-10-27 用户明确指定）**：
- FPGA：`https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-fpga`，完整本地 checkout `D:\fpga\repos\ph1p100-pcie-ep-fpga`。
- RK：`https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-driver`，完整本地 checkout `D:\fpga\repos\ph1p100-pcie-ep-driver`。
- 用户要求直接更新两仓 `main`、不建 fork；后续代码/协议/样例/队友结果以两仓为协作入口。本 run 与 P4 round3 **不**向 `D:/fpga/repos/**` 或 GitHub 提交/推送/fork（写范围仍限本 run 目录与 P4 授权目录）；板级线若要落仓，须在其自己的任务中显式授权并核对 `REPOSITORIES.md` 与两仓 `docs/PROJECT_SYNC_20261027.md`，不以参考实现覆盖同名生产实现。

**P4 验收后的承接方式与 ⚠ 条件**：
- 前置：INT.P4 round3 PASS（G2 0 违例、WNS/TNS≥0，G1/G5 同候选通过）；若 round3 FAIL，则按 §3.8 的 ⚠ 承接条件继续——P4 仍记 **⚠**（functional/system pass、G2 fail），**不写 PASS**。
- 承接动作（由原规划在本 run 收尾后执行）：写 `handoff.md`/`final-summary.md`/`user-summary.md`，列出 P4 唯一候选/manifest、已通项、G2 真实数字、带出风险（`algo_rowwin3` 行缓冲读路径、HE 停顿敏感性、IO 未约束、RK 待联调、G3/G4 not_run），并给出后续 run 的准确启动/恢复文本；若宿主入口规则要求显式指令，用户/主使用该文本恢复，主不自行选任务。
- 板级线技术边界（用户要点，待后续规划细化）：复用已通 A/B 工程；把 P4 候选接入真实相机、DDR 与 PCIe；补齐板级顶层、时钟复位及必要跨时钟连接、引脚约束、构建入口；完成整机 bit；**先 B 后 A** 的真实单路压缩帧 PCIe 完整导出；“推进度为先”，长稳与非阻塞优化后置。
- 板级线必须独立冻结的项：TD/板卡独占窗口、synth/route/bitgen/CWC/下载/Flash 额度、真实引脚/时钟约束、CDC 检查、板级时序门槛；不得用 P4 综合数字或 b20 `a1_board.bit` 冒充板级结果。
- 诚实标注（同 §3.8）：板级 bit 若来自带已知违例的网表，必须标注“**带已知时序违例的 bring-up bit**”；不得声称 P4 G2 通过、整机时序签核、长稳/性能达标或 A 路上板通过。

**技术与资料前置（后续规划读取，不在本轮展开）**：b18 B 路真实 1080p 帧基线、b20 A 路候选（薄裕量、board blocked）、P4 交付包（`INT.P4-protocol.md`、`INT.P4-build-entry.md`、`INT.P4-shortest-steps.md`、样例/解码工具）、真实板卡原理图/引脚表/相机与 PCIe 参考工程、`tools/td/PATH_CONTRACT.md`。缺资料/设备/窗口时板级线 blocked，不空转。

**TD/板卡窗口与保护**：本 run 的 b18/b19/b20、其他活动 run、权威两仓只读约束继续有效；板级线不得复用本 run 的 TD 工程目录或计数。

## 10. 收尾记录（2026-10-27 07:00 冻结，原规划）

**判定**：本 run 主目标（同一候选集成交付）**未达成**。INT.P1/P2/P3 PASS（P1 r0 FAIL→r1 PASS 修复 1 轮；P2 r0 PASS；P3 r0 FAIL→r1 PASS 修复 1 轮），**INT.P4 记 ⚠ 未通过**（r0–r3 全 FAIL，3 轮实际修复用尽）。综合测试共 9 轮、实际修复 5 轮。

**INT.P4 结论（不写 PASS、不拼分支）**：

- r2（`DFAB7F9D…`）：functional pass、system pass、**G2 fail 112 端点 / WNS −0.637ns / TNS −69.776ns** → 唯一可用作**功能基线**。
- r3（`43EBFF3D…`）：**G2 pass（限定）0 端点 / WNS +0.072ns / TNS 0**、functional fail（派生变体等价破坏：y8 383/317/3、gau 1368/1154/10、he 1116/980/44；bayer +STALL 769 vs 783）、system fail（G5 文档矛盾）。
- 两者输入不同、结论不同，**不得拼接**。route/bitgen/CWC/下载/Flash 全部为 0；TD synth 终身 7/9，剩余不转移。

**板级后续决策（用户原话条件"P4 完成并验收后"未被字面满足）**：选择 **(a) 在 ⚠ 下继续，作为新 run**。理由：用户"以推进度为先"、期限 2026-10-27；板级顶层必须用自己的真实时钟/IO 重新签核；P4 的 G2 失败不会因等待消失。硬约束沿用 §3.8(3)(a)–(e)（首段承接声明、自有板级 STA、bring-up bit 标注、仿真证据不外推、额度分账）。

**新 run 请求（本 run 不派发）**：`follow-on-run-request.md`（建议 run_id `20261027-0700_fpga-board-integration`；1 目标 / 4 包 BRD.P1–P4 / 两级 / 每包 ≤5 步；功能基线 r2；禁止 r3 派生变体；B 先 A 后单路压缩帧 PCIe 完整导出；整机 bit；长稳后置；TD/板卡/下载独立冻结，Flash=0；5 倍额度不自动继承）。

**交付文档**：`decision-matrix.md`、`final-summary.md`、`handoff.md`、`user-summary.md`、`user-question.md`、`follow-on-run-request.md`；`dispatch.json` 置 `status=needs_user_input`、`run_state=closed`、`needs_user_input=true`，`task_ids=[]`，无下一派发。
