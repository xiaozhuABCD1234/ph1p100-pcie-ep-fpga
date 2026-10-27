# A+ G2 流水收敛 Implementation Plan（规划建议）

> 本文件是用户本轮要求的路线建议与实施计划草案。本轮仅查阅与规划，没有启动 FPGA 开发角色链、修改 RTL/约束、运行构建或更新任务状态。后续若显式启动项目工作流，由项目 fpga-orchestrator → 原规划 → 开发 → 单一综合测试者执行；项目角色与预算规则优先，不采用通用技能的其他执行角色链。

**Goal:** 保留现行单编码器算法和 187.5 MHz，完成单路 codec 小顶的真实 Routed G2 收敛，保持现有功能与本包吞吐合同。

**Architecture:** 继续现有 T10.a1-hit-pipe：将扩展匹配字节提前读取、提前比较并寄存一位结果；状态机使用有效的寄存判定。用提前预取吸收寄存延迟，保持扩展扫描启动间隔。按新报告定位新增瓶颈，每次实验仅修改一个有证据的组合锥。

**Tech Stack:** Verilog、PH1P100SBG484 -3、TD Release_2026.2、现有 P2/P3 仿真与 zlib/strict 解码校验。

**Spec:** 本轮用户要求“查看目前的优化线路，到底该怎么去做，进行规划或者建议”；技术合同参考同 run 的 dispatch-hit-pipe.json、dev-plan.md §30、tools/td/PATH_CONTRACT.md。旧 docs/压缩方案G2复核与优化方向_2026-10-22.md 是较早快照，存储映射建议现已落实。

## Global Constraints

- 不换压缩算法、不新增第二编码器；端口、RAW/Bayer、CRC、commit/abort、zlib/fixed/stored 语法及回退上界保持。
- 187.5 MHz、5.333 ns SDC 锁定；不降频，不加 false path/multicycle，不 seed sweep，不变更 QoR 策略。
- frame_top 锁定 18d51b1b…1cbe；保留当前 26 ERAM 的存储映射和 thresh_lit8/9；写域以现有 dispatch 为准。
- 当前 hit-pipe 包 P2 comp ≤355261 cycles；总体硬上限 370370 不能替代这个包级门槛。P3 1080p 各模式 ≤6250000 cycles。
- 综合 WNS ≥+0.5 ns、TNS≥0、资源合规才进入一次布线；最终 Routed setup/hold WNS/TNS≥0、0 违例。+0.5 是预筛，不能保证布线通过。
- 当前包总预算沿用 dispatch：TD ≤3 会话、综合≤3、布线≤1、总≤120分钟；执行前扣除账本中已经消耗的次数，不重新发放预算，不自动新包或续轮。
- TD 用 T: 指当前 td、Y: 指项目根；仿真用 P:/W:。不得把 X: 映射到项目根；本轮没有运行盘符脚本。
- bitgen、下载、Flash、生产集成不在本计划实施范围。禁止批量删除；不覆盖旧 manifest 或报告。

## Review Focus

1. 命中后第一个扩展字节即失配：寄存结果须对应 pos+3/ref+3，不能误消费下一字节。
2. distance=1/2 的重叠匹配和 htab 同址写旁路：预取数据必须属于正确位置/块。
3. 长度3、最大长度258、distance=2048、块尾不足字节：不得因提前读取而错误延长匹配或越界消费。
4. PRE/REPOS、反压、stored 回退：进入和离开匹配循环时 valid/位置/比较结果一致，不能产生每次匹配的额外气泡。
5. abort/reset/连续帧/换 bank：旧预取、失配标志和哈希结果不能进入下一帧。

## 1. 现状：哪些工作已经完成

最新可完整绑定的物理候选为 T10.a1-htab-eram r2-waive2，core SHA256：

`0b084317db0608a56865a77fd18e7312add3ddb87c2a465a48f60816d8545396`。

| 项 | 实际结果 |
|---|---|
| 布线状态 | Routed |
| setup | WNS -0.436 ns、TNS -26.919 ns、138/4514 违例端点 |
| hold | WNS +0.020 ns、TNS 0、0 违例 |
| 布线资源 | 2974/71680 Slice（4.15%）、26 ERAM、32 DRAM LUT、1641 reg |
| 最差起终点 | bm_a ERAM clk2q → 4级LUT → state 寄存器 CE |
| 最差数据延迟 | 5.245 ns，含 cell 3.228 / net 2.017；ERAM clk2q 1.846 ns；max fanout 10 |
| 时钟相关项 | 有效 skew 0.385 ns、uncertainty 0.075 ns、setup 0.064 ns |
| P2 comp | 153600 B、355261 cycles、81.067 MB/s |

原始最差路径的预算为：`5.333−5.245−0.385−0.075−0.064=−0.436 ns`。ERAM 输出后的约 3.399 ns 组合逻辑/布线超出该路径约 2.963 ns 的剩余预算。这解释了为何“4级逻辑、数据延迟小于周期”仍然失败。

公开 top-10 setup 路径均为 bm_a → state CE 家族；报告只展示10个端点，不能据此把全部138个违例都归为同一家族。下一轮须获取更完整的负裕量端点/路径分布。

评审所见工作树 core 已是 `3be08d993554cd7ebc88ac23493e32a23b40f94c8e21fcc7be69f112ce1aec14`，带有 hit-pipe 修改：

- core:689–710：命中前利用参考读口投机预取；命中拍发出 pos+4/ref+4。
- core:1090–1107：登记候选字段、范围判断换级，寄存 ext_mis_r。
- core:1397–1420：S_EXT 消费寄存失配结果。

本包已有 P2 PASS/355261 cycles 的局部产物，但评审时未见完整 P3 结果、本包工程 manifest 或 TD/route 结果；不能把这部分结果绑定成当前工作树完整 PASS。后续不应重复开发已存在的提前比较逻辑，应先验证它。

## 2. 三条路线比较

| 路线 | 收益与代价 | 推荐程度 |
|---|---|---|
| A. 当前提前预取 + 一位判定寄存 + 控制锥整理 | 对准真实最差路径，可用提前读吸收延迟；需证明位置/valid/首次比较对齐 | 首选，继续现有 hit-pipe |
| B. 有限的块级填充/更完整流水 | 用固定启动延迟换取更清晰边界；必须实测累计周期，可能需要改变当前“不增加周期”的包级合同 | A 不收敛后的设计讨论候选，不在当前包自动实施 |
| C. 降频或更换压缩微架构 | 会扩大 CDC/系统接口或验证范围；当前周期数在150MHz仅64.85MB/s，在173.34MHz约74.945MB/s | 当前不推荐 |

资源已经足够容纳合理的寄存器和局部数据复制，下一步应利用这些资源形成稳定的流水边界。当前证据不支持再次换压缩算法、继续优化压缩比，或继续重复做 RAM 映射。

## 3. Task 1：在现有 hit-pipe 包内完成有界收敛

**Files / responsibilities:**

- 修改范围候选：upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v 的 bm 读数据/比较/state 控制流水；严格受 dispatch 写域限制。
- 只读对照：T10.a1-htab-eram/r2/candidate-0b084317.a1_deflate_core.v、r2/td/phy_pr_timing.rpt、r2-waive2 manifest。
- 验证入口：upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p2_hitpipe_r0.ps1、run_p3_hitpipe_r0.ps1。
- 新增定向 TB 仅在现有包允许的 sim/tb/codec 下；新增证据保存在 T10.a1-hit-pipe/r0 对应新子目录，不覆盖旧候选。
- frame_top、SDC、其他生产工程文件、workflow/tasks.json 不由本计划改动。

**Interfaces:** 外部端口不变。内部约定为“读请求的位置/参考位置/帧块归属、返回数据、比较结果、消费有效性”同步推进；S_EXT 只能消费属于当前扩展字节的寄存结果。哈希插入和同址旁路保持原功能。

- [ ] **Step 1：锁定输入并画出至少一次命中到首次失配的逐拍表。**
  先核对当前候选/原开发活动与证据归属，沿现有包恢复，不能直接覆盖工作树。表中逐拍列 state、pos、候选pos、两个RAM地址/返回字节、ext_mis_r、ext_rem、len_r、消费valid；覆盖首次失配与连续成功两种轨迹。当前包次数从原账本扣减。

- [ ] **Step 2：先证明当前3be…版本的预取对齐。**
  用现有 len3_dist4、dist2048_len258、块尾、abort/reset/反压用例并补最小 distance1/2 与首字节失配用例。断言每次有效消费的两个字节具有正确位置、长度不超过258、终止标志不跨块/帧复用。检查预取未就绪时不得消费，而不是放过 X；若对齐失败，先修该反例再做 TD。

- [ ] **Step 3：根据新报告只处理一个控制/地址锥。**
  首先验证 ext_mis_r 已真正切断 ERAM→state CE；若新瓶颈落在 ext_mis_r 的使能/首字节选择，考虑在结果无消费者的状态每拍更新、仅在消费边界检查valid，移除不必要的命中相关CE。若瓶颈转到 htab 输出→bm_b 读地址，处理提前地址和候选字段对齐；若转到寄存字段→范围判断→state，单独评估该锥。每个假设必须有明确起终点及预期减少的逻辑级，不能同时混改三个位置。若必须越出本包写域，停止交原规划。

- [ ] **Step 4：完成同一候选的功能与吞吐验收，再综合。**
  执行当前包 P2/P3 脚本，预期13/13、20/20通过；独立zlib+strict恢复RAW零差异，0 X、vlog 0/0，负例/长度/CRC/stored上界正确。P2 comp ≤355261，P3 1080p各模式≤6250000。SHA和周期差异按现行合同记录：SHA仅诊断；P2周期上限仍为硬要求。通过后综合，核全部负slack家族、RAM映射和资源；WNS≥+0.5、TNS≥0才进入一次route。启动每个命令前配置实际超时/终止办法，工具yield不能作为超时。

- [ ] **Step 5：一次真实布线、证据冻结与独立综合测试。**
  使用已纠正device/package的T:/Y:流程，在启动前确认流程止于opt_route，禁止进入bitgen。产出Routed setup/hold、资源、clock/check_timing及同网表静态单时钟证据；WNS/TNS/HWNS/HTNS≥0且0违例才通过工程门槛。开发停止修改后冻结RTL/SDC/Tcl/日志/网表/全部报告与SHA，由一个独立综合测试者复核功能、工程和系统吞吐。任何失败按原包计数停止，不另开包绕过次数。

建议验证命令（供后续实施使用；本轮未执行）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File upstream\ph1p100-pcie-ep-fpga\tools\codec\run_p2_hitpipe_r0.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File upstream\ph1p100-pcie-ep-fpga\tools\codec\run_p3_hitpipe_r0.ps1
```

TD命令/阶段终点应从本包真实且已验证的脚本确定；不复制旧X:流程，不编造工具不支持的参数。

## 4. 验证成本控制与停止规则

当前包总额内建议最多三个有不同证据的综合检查点：①现有look-ahead候选；②根据①报告的最差控制锥改动；③仅对②仍可定位的残留锥收口。每次都先过功能/周期，再做综合。已有消耗须扣除；实际不足三个时不补发次数。

以下任一条件出现即停止本包：功能/valid错误未排除、P2超过355261、存储映射退化、写域需要扩大、综合/布线预算用尽、一次route失败或静态单时钟证据不能成立。保留旧0b084317作为可复现基线；不覆盖其原始物理报告。

如果零周期增加的A路线在现有预算内不收敛，下一次决策应明确讨论B的延迟合同：允许固定块级填充，并测量是否仍满足总体硬门槛。当前数据下不能允许朴素每match加一拍：P2有19200次match，355261+19200=374461，超过370370。每块加一拍的示例仅增加32拍，约81.06MB/s，但它仍违反当前≤355261合同，且仅作算术示例，不代表新架构能只增加32拍或已获得实施授权。

## 5. G2 边界与证据措辞

TD 2026.2没有report_cdc；新dispatch已经接受同一routed网表的静态单时钟证据。要求核所有时序单元时钟引脚归属于同一个根clk、无生成异步域、无未约束时钟、无跨域路径，并实际运行可用的clock/check_timing报告。物理上同源GCLK/SCLK分支不应误判成不同逻辑时钟域。报告注明“静态单时钟证据，非report_cdc工具签核”，不把check_timing本身称为CDC。

既有check_timing含47个无input-delay、73个无output-delay及1个dangling项；SDC明确small-top故意不约束内部SoC接口。当前结论限codec块级内部时序。记录并解释这些项；生产集成时另补真实接口时序，不临时放宽或增加本包门槛。

## 6. 本计划自检与来源

自检：建议覆盖最新route瓶颈，避免重复已完成的ERAM迁移；区分355261包级门槛和370370总体硬限；未把现有P2局部结果称为当前候选全通过；未把综合+0.5视为route保证；未重新分配预算或接续旧dispatch。

主要来源（均相对于 workflow/runs/20261020-0209_singleA_aplus_closedloop）：

- T10.a1-htab-eram/r2/td/phy_pr_timing.rpt:10,27–28,69–85,104–144。
- T10.a1-htab-eram/r2/td/phy_area.rpt:15,26；原生phy_1/a1_ht_r2_phy.area一致。
- T10.a1-htab-eram/CANDIDATE-MANIFEST-htab-eram-r2-waive2.json；本次只读核查12项证据hash相符。
- T10.a1-htab-eram/r2/p2/runs/p2_perf_1920x64_comp/stats.txt:1,5,11,14–15。
- T10.a1-hit-pipe/r0/p2/result.md:119（局部证据，不代替本包完整manifest）。
- dispatch-hit-pipe.json、dev-plan.md §30；最新user-summary §31作为索引，结论以原始证据为准。
