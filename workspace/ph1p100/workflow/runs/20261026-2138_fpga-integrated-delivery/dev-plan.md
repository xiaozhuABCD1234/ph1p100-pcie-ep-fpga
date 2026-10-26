# 开发计划 — 20261026-2138_fpga-integrated-delivery

## 1. 范围与拆分结论
- 主要可验收目标：1（集成候选）。
- 正式工作包：4（INT.P1~INT.P4），两级（需求→工作包），每包≤5项语义步骤。
- 批大小：1（用户未指定其他值）。
- 本轮不修改全局tasks.json、不关闭父任务、不操作硬件/下载/Flash。

## 2. 任务计划总表
| task_id | 问题/产物 | 实际工作树/允许写路径 | 依赖 | functional | engineering | system | 必要G层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| INT.P1 | RAW10打包修正、好帧发布/取消、三算法与选路接入、内容独立像素参考验证 | `fpga/csi2/src/integrated_delivery/` + run dir | b15链路审查结论、T09算法RTL、T06存储 | 必须 | 必须 | 必须 | G0,G1,G2 | PASS (r1) | 已完成 |
| INT.P2 | A+输出槽→PCIe发送后端；描述符/长度/尾拍/完成/释放；A1U1与R10F关系；RAW入口保留 | `fpga/csi2/src/integrated_delivery/` + run dir | INT.P1 (PASS r1 manifest)、T10 A+ RTL、T11 PCIe后端 | 必须 | 必须 | 必须 | G0,G1,G2 | PASS (r0; RK真实PCIe传输待联调) | 已完成；RK联调仍待 |
| INT.P3 | 双路A/B采集、身份、必要调度；复用离线+b20有效结果；防串帧/混路/覆盖 | `fpga/csi2/src/integrated_delivery/` + run dir | INT.P1/P2 (P2 r0 PASS)、b20有效结果或b18基线、双路离线包 | 必须 | 必须 | 必须 | G0,G1,G2 | PASS (r1; A路仍门控，待b20板级有效结果) | 已完成；A路真实接入待板级结果 |
| INT.P4 | 同一manifest集成交付：P1+P2+P3+A+核同一候选绑定；必要回归；隔离目录综合/条件布线；交付物包 | `fpga/csi2/src/integrated_delivery/` + `tools/integrated_delivery/` + run dir | INT.P1/P2/P3 PASS；A+核复用b20 r0只读候选 | 必须 | 必须 (综合必做/布线条件) | 必须 (board=not_run/条件) | G0,G1,G2(综合必做,布线条件),G5 | ready | 开发r0 |

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
- 允许新增文件仅：`fpga/csi2/src/integrated_delivery/{integrated_delivery_top.v,tb_integrated_delivery_top.v}` 与 `tools/integrated_delivery/**` 下脚本/TB/SDC/TCL/样例/证据；run目录下`INT.P4/**`与manifest/文档。
- 只读引用：b20 r0 `changed-src/{a1_frame_top.v,a1_deflate_core.v,a1_ddr_slot_store.v,a1_ddr_arb2.v}` 与 `upstream/.../codec/*`、`fpga/csi2/src/img/**`、`pcie_integration/rtl/ep_side/{ddr,img}/**`。不复制、不修改被保护源；若需补丁，另建新文件并在manifest中说明来源与差异。
- 若P1/P2/P3接口无法在不改语义的前提下直连：优先加薄胶合；需改其生产文件时必须在新manifest记录新版本、重跑对应包回归并在报告写明，不得静默改。
- TD政策：工程只建在 `workflow/runs/<run>/INT.P4/td/`；源码以绝对路径引用只读树；不得写`D:/TD/work/csi2`、不得复用/改写b20工程与其synth/route/bitgen计数、不得继承其下载额度。启动前只读确认无`pnmain`等TD进程；若出现其他run的TD活动，立即停并返回blocked，不共享设备/工程。
- TD计数（本包分配，5倍授权内的子集）：synth≤2、route≤1、bitgen=0、CWC=0、downloads=0、Flash=0。综合门槛：`clk` WNS/TNS≥0、hold≥0、0违例、资源在器件内、ERAM+CWC≤300；未达标不布线、不写bit，记录FAIL/差距。若TD因缺ADC/引脚约束拒绝布线，如实记route=not_run，不伪造ADC；若TD以自动IO布局接受布线，可跑一次，但STA只声明内部路径，IO未约束与板级时序不作通过，记差距。
- 只读核对（2026-10-27 00:50 规划）：无`pnmain`/TD进程；`vsim` PID 61632/37556 在跑（非本角色所有，不得杀）；COM8/FTDI当前存在（历史间歇，不能当稳定板窗）；b20 r0已routed 0违例、SWNS +0.012薄裕量、bit/CWC存在、board=blocked(0下载)，其计数与目录一律不动。

#### INT.P4 交付物清单（冻结路径）
- 候选：`fpga/csi2/src/integrated_delivery/{integrated_delivery_top.v,tb_integrated_delivery_top.v}` + 既有P1/P2/P3文件（不改或显式记新版本）。
- 构建/仿真入口：`tools/integrated_delivery/run_integrated_sim.ps1`、`run_integrated_build.ps1`、`td/01_synth.tcl`、`td/02_route.tcl`、`td/integrated_core.sdc`、`gen_manifest_intp4.py`。
- 解码工具与样例：`tools/integrated_delivery/a1u1_decode.py`（既有）+ `evidence/integrated_sample.a1u1`/`.json`（集成仿真产生并解码校验）。
- run目录：`INT.P4-r0-manifest.json`、`INT.P4-protocol.md`、`INT.P4-build-entry.md`、`INT.P4-shortest-steps.md`、`INT.P4/regression/**`、`INT.P4/td/**`（含TD日志/报告；无bit则明确not_run）、`INT.P4/result-r0.md`、`INT.P4-lessons.md`。
- 测试：独立综合测试者报告 `test-reports/INT.P4-r0-integrated.md`（`dimension=integrated`）。
- bit：本轮冻结为not_run（无板级集成顶层/ADC，不伪造）；不得把b20 `a1_board.bit`写成集成交付bit。b20 bit仅作为独立历史候选在最终汇总中标注。

#### INT.P4 验收门槛
- G0：顶层接口/单位/模式/时钟/复位冻结且与RTL一致；A1U1与R10F、长度命名、RAW/Y8区分无冲突。
- G1：同一manifest下P1/P2/P3回归重跑通过 + 集成TB真实DUT通过（背压、abort、A disabled、B优先、身份/释放、描述符/长度/尾拍/完成/释放、RAW旁路不被Y8污染）；A1U1样例解码header/stream CRC与zlib通过；独立判据不得只复用开发TB。
- G2：隔离目录综合必做并出报告；布线条件允许才做。通过=clk 187.5MHz下0违例且WNS/TNS≥0、hold≥0、资源在器件内、ERAM+CWC≤300；未运行=not_run，不得写pass。
- G3/G4：not_run + awaiting_hardware（无bit/无板窗）；不得把仿真/P2接口仿真写成真实PCIe/上板通过。
- G5：manifest、协议、构建入口、解码工具、样例、最短步骤齐全且与证据一致；RK真实PCIe传输仍标待联调。
- 判定口径：本包PASS=交付包与同候选功能/工程证据通过，**不是**整机/bit/上板完成。

## 4. 依赖与顺序
- INT.P1 → INT.P2 → INT.P3 → INT.P4（P1 r1 PASS、P2 r0 PASS、P3 r1 PASS，链路已满足）。
- INT.P4 复用b20 r0 A+核候选（只读、薄裕量+0.012、board blocked）；A路仍按`a_enable`门控，不声称A路通过。
- 并行仅限互不冲突的离线验证/文档/解码工具准备；不得多开发同时修改同一顶层。
- 其他活动run（`20261026-231711_fpga-a-plus-h-prototype`、`20261026-143924_fpga-1080p30-g0-production`等）与b18/b19/b20一律只读，不共享TD/板卡。

## 5. G层与门槛
- G0：接口/单位/预算/双方责任（本run指南+§3 INT.P4冻结边界）。
- G1：模型/仿真/软件正反向、边界、恢复、反压；INT.P4须同候选回归+集成TB真实DUT。
- G2：综合（必做）、条件布线、最终STA、约束覆盖、CDC/复位、资源；未运行如实not_run。
- G3：上板功能（本轮无条件：无集成bit/无板窗）→ not_run + awaiting_hardware。
- G4：长稳/性能（本轮后置，仅记录差距）→ not_run。
- G5：集成/发布（本轮部分：manifest、协议、构建入口、解码工具、样例、最短步骤）。
- 时序门槛：clk_a1 187.5MHz WNS/TNS≥0、hold≥0、0违例；资源在器件内；ERAM+CWC≤300。
- 压缩：最坏膨胀+0.1044%；吞吐≥77.76MB/s（功能先跑通，未达记录差距）。
- PCIe：描述符/长度/尾拍/完成/释放贯通；不把文件回放/接口仿真写成真实PCIe传输通过。
- bit：本轮not_run（无板级集成顶层/ADC）；不得用b20 bit冒充。

## 6. 工具/设备/预算
- TD/板卡只由一个责任流程使用；下载不得继承b20额度；INT.P4下载=0（无bit）。
- 全局上限：Flash=0；下载≤1；综合≤3；布线≤2；bitgen≤1；CWC≤1。
- INT.P4子分配：synth≤2、route≤1、bitgen=0、CWC=0、downloads=0；剩余额度不转移、不继承。
- 执行预算（5倍用户授权，仅限当前任务）：
  - 规划：75分钟（默认15×5），150次工具调用（默认30×5）。
  - 开发：225分钟（默认45×5），150次工具调用。
  - 综合测试：225分钟（默认45×5），150次工具调用。
  - 单问题搜索/读取：15轮（默认3×5）。
  - 同失败命令：首次+最多9次重试（默认1+1×5？按5倍放宽为最多10次），仅新证据/参数纠正时重试。
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
- 派INT.P4开发（新开发角色），用本题冻结候选+N P4冻结边界；完成后交唯一综合测试者 `INT.P4-r0-integrated.md`。
- 测试PASS后由原规划写`handoff.md`/`final-summary.md`/`user-summary.md`收尾；bit/上板缺项如实列差距。
- 主仅按dispatch.json调度；详细内容留本计划。
