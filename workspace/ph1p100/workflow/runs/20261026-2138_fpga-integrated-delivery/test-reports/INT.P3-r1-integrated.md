### 判定：PASS

> 判定范围：INT.P3 round1 冻结候选的 D1（valid/ready stall 保持）修复、A/B 身份与释放、A disabled 不阻塞 B、B 优先/轮转的 functional G0/G1 验收。
> 本判定**不是**综合/STA/CDC/资源（G2）、顶层集成（G5）、上板功能（G3）或长稳/性能（G4）通过；A 路真实 b20 时序仍为 gated/pending，不能写成 A 路通过。

## 1. 任务、候选与冻结输入

- task_id: `INT.P3`
- dimension: `integrated`
- round: `1`（round0 已判 FAIL，D1 修复后复测）
- run_id: `20261026-2138_fpga-integrated-delivery`
- 输出目录: `D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery`
- 实际工作树: `D:\fpga\ph1p100`
- candidate_root: `fpga/csi2/src/integrated_delivery`
- 冻结 manifest: `D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\INT.P3-r1-manifest.json`
- manifest SHA256: `9d0dea0881fcd07c87296d056c87694d645e35dc987b62a2c21cd018e82dccc9`
- manifest `stopped_modifying`: `true`，`round`: `1`
- 候选 RTL 未被测试者修改；本轮所有写入仅在 `test-reports/INT.P3/` 与本报告文件。

### 1.1 production/tool 输入哈希核对（测试前 + 测试后各一次，均匹配）

| 类别 | 路径 | manifest sha256 | 实测 sha256 | size | 结果 |
|---|---|---|---|---|---|
| production | `fpga/csi2/src/integrated_delivery/dual_channel_capture_scheduler.v` | `0ec7c80c45ec5b787bbef390dc75b82f30c5e89f152657cd688f23ff92e4c529` | 同左 | 7962 | match |
| production | `fpga/csi2/src/integrated_delivery/tb_dual_channel_capture_scheduler.v` | `59d3421854bf354652222198d4ba9ac457bff5cc1c5a5e3fde3c771b7d95a49d` | 同左 | 6540 | match |
| tool | `tools/integrated_delivery/dual_channel_schedule.py` | `fe0e879297723289ac600ed79949398018aae0eee775e168de62e10dac105b82` | 同左 | 4551 | match |
| tool | `tools/integrated_delivery/gen_manifest_intp3.py` | `04b4e5162f9661a232b0ae1d8fa15b9f8fd381b1319ed7ec4990db3e825a54ba` | 同左 | 1969 | match |

- 测试前核对：4/4 match；测试后再次核对：4/4 match，`ALL_CHECKS_MATCH=True`（含 4/4 production/tool 与测试 TB、变异副本、关键日志绑定）。
- 证据：`test-reports/INT.P3/hash_check.txt`。
- 未发现 manifest/候选漂移；未用旧哈希拼新日志。
- 工具版本：ModelSim Intel FPGA Edition `vlog/vsim 10.5b`（Compiler 2016.10）；Python `3.11.5`。
- 未运行 TD 综合/布线/STA/CDC/资源工具，未下载 bit、未写 Flash、未操作板卡。

## 2. 本包范围、冻结门槛与 G 层

### 2.1 本包范围（按 dispatch/dev-plan）

- 双路 A/B 采集描述符、身份（camera_id/slot/epoch/session/capture_seq）与帧粒度必要调度。
- B 路优先推进；A 路由 `a_enable` 门控，b20 有效结果未到前只做接口/门控检查。
- A disabled 时不得阻塞 B；B 优先/轮转不得破坏 A/B 身份。
- 防串帧/混路/覆盖：valid/ready stall 期间不得覆盖已呈现描述符，不得丢帧。

### 2.2 G 层冻结与口径

- `dev-plan.md` 表格列 INT.P3 必要层为 G0/G1/G2；但 r1 manifest notes 与 dispatch 明确“G2 synthesis/STA/CDC/resources deferred to INT.P4”。本报告按 dispatch 的冻结口径：**G2 本包 not_run/blocked**，不把未运行当通过；G3/G4 not_run + awaiting_hardware。
- 这是输入口径差异，不是测试者临场改门槛；交由原规划在收尾时统一登记。本判定只对 G0/G1 的功能修复负责。
- A 路真实 b20 时序：`not_run` + `pending (b20 有效结果未到)`，A 路仅 gated/pending，**不写成 A 路通过**。

## 3. functional

### 3.1 D1 复测结论（round0 已确认缺陷）

round0 缺陷：`o_valid=1 && o_ready=0` 时仍接受 B（或新的 A）描述符，覆盖已呈现的 `o_capture_seq`；A 描述符丢失/串帧。

r1 RTL 修复点（静态核对，`dual_channel_capture_scheduler.v`）：
- 新增 `out_stall = o_valid && !o_ready`（第 84-85 行）；
- `a_can`/`b_can` 均加入 `&& !out_stall`（第 86-87 行）；
- 接受分支只在 `chosenA/chosenB` 时执行，故 stall 时不再改写 `o_valid/o_*` 与 inflight 身份（第 168-202 行）；
- release 身份匹配保留 camera_id/slot/epoch/session/capture_seq 全字段（第 134-159 行）。

**独立复测结论：D1 已关闭（本包冻结 RTL）。** 不是只跑开发 TB：本轮新建独立 TB `tb_intp3_indep.v`，用逐拍协议监视 + 消费顺序 scoreboard + 变异负对照判定。

### 3.2 独立 TB 的场景与结果

证据：`test-reports/INT.P3/tb_intp3_indep.v`（sha256 `62a81c523d19f3209f0168d2875dd6eb3526586a034ed75e0470a01d9fbe24d0`）

| 场景 | 激励 | 期望 | 结果 |
|---|---|---|---|
| T1 | A 描述符已呈现且 `o_ready=0`；B 连续 8 拍 pending；再叠加第二个 A pending | `o_valid/o_camera_id/o_capture_seq` 每拍保持 A(seq=7)；`a_desc_ready=0`、`b_desc_ready=0`；`st_accepted` 不变 | PASS |
| T1 续 | 释放 A 时分别用错 epoch、错 camera_id；B 用非零 status 释放 | 错误释放 `st_rejected+1` 且 A 保持 busy；正确释放 `st_completed+1`；B status=2 → `st_failed+1` 且 busy 清除 | PASS |
| T2 | B 已呈现且 `o_ready=0`；A 连续 6 拍 pending | B 身份保持；A 不接受；消费 B 后 A 在**同一拍**被接受并呈现，身份为 A(seq=22) | PASS |
| T3 | A/B 同时 pending，`o_ready` 连续两拍为 1 | B 先被接受/消费；A 在 B 消费的同一拍被接受，下一拍消费；无覆盖/无丢失 | PASS |
| T4 | `a_enable=0`，A/B 同时 pending；B 消费/释放后 A 仍 pending 4 拍 | 只选 B；A 不被接受；恢复 `a_enable=1` 后 A 以原身份(seq=41)被接受 | PASS |
| T5 | `b_priority=1` 双 pending；`b_priority=0` 轮转；先只来 B 再双 pending | B 优先；轮转选择另一路；身份不混（seq 51/52/53/54/57/58/59 全部按接受顺序消费） | PASS |
| T6 | A 端口给 `camera_id=1`、B 端口给 `camera_id=0` | 两路均不接受（ready=0），`st_accepted` 不变 | PASS |
| T6b | 释放 A 时分别错 slot / 错 session / 错 capture_seq / 错 camera_id | 逐项 `st_rejected+1`，A 保持 busy；全字段正确才释放并 `st_completed+1` | PASS |
| T7 | 呈现 A 后、stall 中断言复位 | `o_valid=0`、a/b busy=0、计数清零；该描述符按复位语义丢弃 | PASS |

关键计数：`TB_INTP3_INDEP PASS cumulative_accepted=17 cumulative_consumed=16 reset_discarded=1`，`Errors: 0, Warnings: 0`。
- 17 = 16 个正常消费 + 1 个 T7 复位主动丢弃；非复位场景没有“已接受但未消费”的描述符；复位后 scoreboard 队列 aq=cq=0。
- 逐拍监视器（每个 posedge）：
  - P1：若上一拍 stall 且当前仍未 ready，`o_valid` 必须为 1 且全部身份字段不变；
  - P2：`o_valid && !o_ready` 的拍内不得出现 `a_desc_valid&&a_desc_ready` 或 `b_desc_valid&&b_desc_ready`；
  - P3：每个 `o_valid&&o_ready` 消费的描述符必须等于接受顺序队列中最老的描述符（逐字段比较）。

### 3.3 独立判据与变异负对照（为何能发现 D1）

1. **逐拍协议监视器**：直接检查 stall 期间描述符保持和接受握手禁止；不是复用开发 TB 的期望序列。
2. **消费顺序 scoreboard**：覆盖“接受→呈现→消费”全链路，能发现覆盖、丢帧、重复消费、A/B 混路。
3. **变异负对照**：
   - `mut1_stallgate`：复制冻结 RTL，仅移除 `a_can/b_can` 的 `!out_stall` 门控，其余不变。独立 TB 结果为 `TB_INTP3_INDEP TIMEOUT`，并有 **62 条 FAIL**；首批失败为 `P2 channel B accepted during output stall`、`o_capture_seq exp=7 got=9`、`P1 presented identity overwritten during stall`，与 round0 D1 的签名一致。说明该 TB 能捕获目标缺陷类。
   - `mut2_rel_epoch`：复制冻结 RTL，仅移除 release 身份比较中的 epoch 项。独立 TB 结果为 `TB_INTP3_INDEP FAIL errors=3`：`st_completed exp=0 got=1`、`st_rejected exp=1 got=0`、`a_busy exp=1 got=0`，说明 release 全字段匹配检查有效。
   - 负对照只改测试者副本，位于 `test-reports/INT.P3/mut1_stallgate/`、`mut2_rel_epoch/`，不进入候选树。

### 3.4 开发自检声明的独立复核

| 声明（r1 manifest） | 复核结果 | 说明 |
|---|---|---|
| `vlog -lint ... -> 0 errors 0 warnings` | 复跑：0 errors/0 warnings | 证据 `lint.log` |
| dev TB `TB_DUAL_CHANNEL_CAPTURE_SCHEDULER PASS` | 复跑 PASS（285 ns） | 仅作旁证；dev TB 场景不含“stall 期间 B pending”的自检 |
| `tb_bp`: `o_capture_seq held at 3 under stall; BP DONE accepted=1` | 复跑输出一致：`BP: o_capture_seq=3 b_desc_ready=0 a_desc_ready=0 st_accepted=1`；`BP DONE accepted=1 completed=1 rejected=0` | `tb_bp.v` 只 `$display`、无 error 计数，**不是自校验 TB**；仅作旁证 |
| `tb_independent -> TB_INDEPENDENT PASS` | **不予采信**：r1 manifest 的 `test_inputs` 为空，未冻结 `tb_independent` 源文件/哈希；r0 evidence 中唯一的 `tb_independent` 日志记录 `FAIL T4 output changed under backpressure`、`FAIL T6 first not B got 0`、`TIMEOUT` | 本轮改用测试者新建 TB；该声明不影响结论，但属 manifest 证据缺口 |
| `dual_channel_schedule.py -> DUAL_CHANNEL_SCHEDULE PASS` | 复跑 PASS | 该 oracle 的 `simulate()` 没有 `o_valid/o_ready` 模型，**不能检测 D1**；只证明调度记账，不作为 D1 证据 |

### 3.5 A 路真实 b20 时序

- 未取得 b20 有效结果；A 路仅实现接口并由 `a_enable` 门控。
- 本轮只验证“A 描述符身份保持、A disabled 不阻塞 B、恢复 a_enable 后按原身份接受”。
- 结论：A 路 `gated/pending`，**不是 A 路通过**；不得据此声称双路真实接入完成。

### 3.6 非阻塞观察项

1. **状态输出存在一拍滞后**：`st_a_busy/st_b_busy/st_last_camera` 是内部状态的寄存副本，接受描述符的当拍读到的仍是旧值（例如接受后 `st_a_busy` 先为 0、下一拍才为 1）；`st_busy` 在接受的同拍为 1。冻结门槛未规定状态输出时序，本轮不以缺陷论；但 INT.P4 集成若在同拍采样 busy 状态，应使用内部握手或延后一拍。独立 TB 的同拍 ownership 检查使用 DUT 内部 `a_busy/b_busy`，避免该滞后造成误判。
2. **r0 证据与 r0 报告不一致**：`INT.P3-r0-evidence/independent_tb_sim.log` 记录 T4 FAIL（与 D1 一致）、T6 FAIL（TB 期望问题）和 TIMEOUT；r0 报告第 20 行附近却把 independent TB 的场景列为 passed。r0 的 FAIL 判定仍正确，但其 independent 证据不可复用；r1 已重新独立验证。
3. **r1 manifest 的 `tb_sim_independent` 声明无冻结源**：见 3.4；不 credited。

## 4. engineering

| 检查 | 结果 | 证据/说明 |
|---|---|---|
| manifest/工作树/SHA 完整性 | pass | 4/4 production+tool 哈希前后一致；manifest SHA `9d0dea...`；`hash_check.txt` |
| RTL 编译/lint | pass | `vlog -lint dual_channel_capture_scheduler.v` → 0 errors/0 warnings；`lint.log` |
| TB 编译 | pass | `vlog dual_channel_capture_scheduler.v tb_intp3_indep.v` → 0/0；`indep_compile.log` |
| 单模块仿真 | pass | `TB_INTP3_INDEP PASS`；`indep_sim.log`；日志无 Fatal |
| 候选唯一性/回退 | pass | 以 manifest SHA 绑定；r0 报告与 manifest 保留；未覆盖旧候选 |
| 生产文件影响（文件级） | pass（文件级） | P1 的 `frame_good_publish_cancel.v`、`integrated_input_processing_top.v`、`raw10_sample_vector_to_packed.v` 与 P2 的 `aplus_pcie_egress_adapter.v` 当前哈希均匹配各自冻结 manifest；未做 P1/P2 回归/集成测试（INT.P4 范围） |
| G2 综合/STA/约束覆盖/CDC/资源 | **not_run / blocked** | 按 dispatch 冻结延后 INT.P4；未运行 TD，未产生约束/时序/资源报告；单模块静态看为单时钟 + 异步低有效复位，但**不能替代 G2** |
| CDC/复位 | 静态观察 only | RTL 只有 `clk` 一个时钟、`rst_n` 异步复位；无跨时钟域逻辑。未做 CDC 工具检查 |
| 位流/CWC/候选绑定 | not_run | 本包无 bit/CWC，不能声称候选与位流配对 |

## 5. system

| 检查 | 结果 | 说明 |
|---|---|---|
| 顶层连接/集成 | **not_run / blocked** | 在 `fpga/` 下检索 `dual_channel_capture_scheduler`，仅命中模块本体和 dev TB，无顶层实例化；顶层集成按计划属 INT.P4 |
| 时钟/复位域 | 静态 pass（模块级） | 单时钟、异步复位；未做跨模块集成检查 |
| 地址映射/数据通路连续性 | not_run | 本包为描述符调度器，无地址/PCIe/DMA 数据通路集成证据 |
| 生产路径影响 | 文件级 pass；集成 not_run | P1/P2 生产 RTL 哈希未变；未运行 P1/P2 回归，不能声称整链无影响 |
| 板级 G3（下载/复位/恢复/帧完整性/稳定性） | **not_run + awaiting_hardware** | 无板卡窗口/下载授权；未下载、未写 Flash |
| G4 长稳/性能 | **not_run + awaiting_hardware** | 无真实硬件/长稳窗口；单模块仿真不代表吞吐 |
| 发布/交接 | partial | manifest、r1 报告、测试 TB、日志齐备；bit/构建入口/协议/样例由 INT.P4 汇总 |
| 候选身份 | 文件级 pass；位流 not_run | 仅 manifest SHA；无 bit/CWC |

## 6. G 层汇总

| G 层 | 结果 | 说明 |
|---|---|---|
| G0 接口/单位/预算/责任 | pass（模块级） | 端口/参数与冻结 RTL 一致；顶层责任划分留 INT.P4 |
| G1 模型/仿真/正反向/边界/恢复/反压 | pass（模块级） | 独立 TB 覆盖 D1、身份、释放、A disabled、B 优先/轮转、复位；17 接受/16 消费/1 复位丢弃 |
| G2 综合/最终 STA/约束覆盖/CDC/资源 | **not_run / blocked** | dispatch 冻结延后 INT.P4；不能把单模块仿真当 G2 |
| G3 上板功能 | **not_run + awaiting_hardware** | 无板卡窗口/下载 |
| G4 长稳/性能 | **not_run + awaiting_hardware** | 无真实硬件/长稳 |
| G5 集成/发布 | **not_run / partial** | 顶层集成、bit、构建入口、样例汇总属 INT.P4 |

## 7. 实际执行命令、工作目录、退出码与完成标记

| # | 命令（实际执行） | 工作目录 | 退出码 | 完成标记/产物 | 日志 |
|---|---|---|---|---|---|
| 1 | `vlog -lint D:\fpga\ph1p100\fpga\csi2\src\integrated_delivery\dual_channel_capture_scheduler.v` | `...\test-reports\INT.P3\msim` | 0 | `Errors: 0, Warnings: 0` | `test-reports/INT.P3/lint.log` |
| 2 | `vlog D:\...\dual_channel_capture_scheduler.v D:\...\test-reports\INT.P3\tb_intp3_indep.v` | `...\test-reports\INT.P3\msim` | 0 | 0 errors/0 warnings；top=`tb_intp3_indep` | `indep_compile.log` |
| 3 | `vsim -c -do "run -all; quit -f" work.tb_intp3_indep` | `...\test-reports\INT.P3\msim` | 0 | `TB_INTP3_INDEP PASS cumulative_accepted=17 cumulative_consumed=16 reset_discarded=1`；`Errors: 0, Warnings: 0` | `indep_sim.log` |
| 4 | `powershell -NoProfile -ExecutionPolicy Bypass -File ...\run_mutations.ps1` | `...\test-reports\INT.P3` | 0（脚本级） | MUT1: `TIMEOUT` + 62 条 FAIL；MUT2: `FAIL errors=3` | `mutation_run.log`、`mut1_stallgate/sim.log`、`mut2_rel_epoch/sim.log` |
| 5 | `vlog RTL + tb_dual_channel_capture_scheduler.v`；`vsim ... work.tb_dual_channel_capture_scheduler` | `...\test-reports\INT.P3\dev_tb` | 0 / 0 | `TB_DUAL_CHANNEL_CAPTURE_SCHEDULER PASS` | `dev_tb_compile.log`、`dev_tb_sim.log` |
| 6 | `vlog RTL + INT.P3-r0-evidence\tb_bp.v`；`vsim ... work.tb_bp` | `...\test-reports\INT.P3\bp_tb` | 0 / 0 | `BP: o_capture_seq=3 b_desc_ready=0 a_desc_ready=0 st_accepted=1`；`BP DONE accepted=1 completed=1 rejected=0`（打印，非自校验） | `bp_tb_compile.log`、`bp_tb_sim.log` |
| 7 | `python tools\integrated_delivery\dual_channel_schedule.py` | `D:\fpga\ph1p100` | 0 | `DUAL_CHANNEL_SCHEDULE PASS`（无 stall 模型，仅调度记账） | `oracle.log` |
| 8 | manifest/hash 核对（PowerShell `Get-FileHash` + manifest 比较） | `D:\fpga\ph1p100` | 0 | `ALL_CHECKS_MATCH=True` | `hash_check.txt` |

- `vsim` 的进程退出码 0 不等于 TB 通过；上表以 TB 完成标记为准。MUT1 的 TIMEOUT 是负对照预期现象（缺陷导致 TB 等待超时），其日志同时含 62 条明确 FAIL。
- 所有测试产物位于 `test-reports/INT.P3/`；报告位于 `test-reports/INT.P3-r1-integrated.md`；未写生产 RTL。

## 8. 独立复现与输入绑定

- 独立判据不是开发 TB 的镜像：逐拍协议监视器 + 接受顺序消费 scoreboard + 两个隔离变异负对照；开发 TB/bp/oracle 只作旁证。
- 独立 TB 源哈希：`62a81c523d19f3209f0168d2875dd6eb3526586a034ed75e0470a01d9fbe24d0`（26034 bytes）。
- 变异脚本哈希：`c2a37a1035b46ea5120f929d8167a6bc5c1b5320ab63cffbc351679b231cc7b6`（2894 bytes）。
- 变异 RTL 哈希：MUT1 `694dfeec7f62a121c7a2bcfd254d207677be39f8ab2e55881959f467b09b4c8f`；MUT2 `255b50b09da722873814b5aedc1aa7a458bcea80b492ebeaffba6414b935965a`。
- 关键日志哈希：`indep_sim.log` `65f9813b86de0f0b2eadb9c000388b5f68558d359e07646323282ff2b90b9d53`；`lint.log`；`hash_check.txt`。
- 全部证据绑定到当前 `INT.P3-r1-manifest.json`（SHA `9d0dea...`）；没有把 r0 结果混入 r1 PASS。

## 9. 证据复用决定

- **未复用 P1/P2 仿真/功能证据**：INT.P3 的调度器是独立新模块；P1/P2 文件只是被核对哈希未变，未运行 P1/P2 回归/集成（INT.P4）。因此本报告的 PASS 不依赖、也不覆盖 P1/P2 的链路。
- **未复用 r0 的 independent TB 结果**：r0 日志本身记录 T4 FAIL/T6 FAIL/TIMEOUT（见 3.6），不存在可复用的 r0 independent PASS；r1 全部用新建 TB 重跑。
- **`tb_bp.v` 源文件**来自 r0 evidence，但本轮是针对 r1 候选重新编译/仿真的新日志，不是复用旧结果；且其非自校验，仅作旁证。
- **dev TB** 针对 r1 候选重新编译/仿真（新日志），只作旁证；判定依赖测试者 TB 与变异负对照。
- input_status: `same`（测试前后 manifest + 全部 production/tool 哈希一致，无漂移）。

## 10. 未测项、缺陷与下一动作

### 未测项（本轮不声称通过）

1. A 路真实 b20 时序/接口结果：`gated/pending`；A 路仅门控与身份检查。
2. G2 综合、最终 STA、约束覆盖、CDC、资源：`not_run/blocked`，延后 INT.P4。
3. 顶层集成、P1/P2 整链回归、位流构建/候选绑定：INT.P4。
4. G3 上板功能、G4 长稳/性能：`not_run + awaiting_hardware`。
5. 随机长跑/持续吞吐、计数器 2^16 饱和、生产者违反 valid/ready 协议（valid 期间改字段）、release 与呈现同拍的异常消费者行为：未覆盖，超出本包冻结门槛。
6. 未做形式验证/CDC 工具检查；单时钟为静态观察。

### 缺陷

- **D1 已关闭**：本包冻结 RTL 不再在 stall 期间接受/覆盖；独立 TB + 变异负对照证明。
- 本轮未发现新的功能性缺陷。
- 非阻塞观察：状态输出一拍滞后（3.6.1）；r0 evidence/report 不一致（3.6.2）；r1 manifest 的 `tb_sim_independent` 声明无冻结源（3.6.3）。

### 下一动作

1. 原规划按本报告更新 INT.P3 记录；B 路与 A 门控/身份可进入 INT.P4 集成。
2. A 路待 b20 有效结果后补真实时序/接口验证，再决定是否声称 A 路通过。
3. INT.P4 统一执行 G2（综合/STA/CDC/资源）与顶层集成、bit/构建入口/样例/协议文档；条件具备时 G3/G4。
4. 若原规划要求修正 r0 evidence/report 记叙，按原责任角色（综合测试）补正，不改变 r0 FAIL 结论。

## 11. 回退入口

- 当前候选按 `INT.P3-r1-manifest.json` 的 4 个 SHA 回退；r0 报告与 r0 manifest 保留在 `test-reports/INT.P3-r0-integrated.md`、`INT.P3-r0-manifest.json`。
- 本报告与测试 TB/日志保留在 `test-reports/INT.P3/`；变异副本仅在证据目录，不进入候选树。
- 未修改生产 RTL/约束/IP/构建脚本；未下载/写 Flash/操作硬件。

## 12. blocked / retest（返回元数据口径）

- **blocked（任务级）**：空。G2/G3/G4 的未运行已在维度/G 层表记录为 `not_run/blocked` 与 `awaiting_hardware`，不在本轮 PASS 范围内；不把未运行当通过。
- **retest**：
  - required_dimensions: `[]`（本任务无失败项需复测）
  - required_checks: `[]`
  - report_paths: `test-reports/INT.P3-r1-integrated.md`
  - input_status: `same`
  - reuse_decision_paths: `test-reports/INT.P3-r1-integrated.md`（第 9 节复用决定）、`test-reports/INT.P3/hash_check.txt`
