# T10.a1-area-map r0 — 设计说明（开发侧，非判定）

- task_id: `T10.a1-area-map` | round r0 | run `20261020-0209_singleA_aplus_closedloop`
- 基准：`T10.a1-g2-2cyc` r1（core `47db3057…e0a2`、frame `18d51b1b…1cbe`、SDC `227dd39e…6311`）
- 本包只做存储映射/端口整理，不改协议、端口、帧语义、CRC、长度、abort、Bayer、SDC、时钟。

## 1. 证据回顾（为什么先做 cmem）

r1 综合 `syn_1`：
- `#slice* 72904 / 71680 = 101.71%`、`#lut 107906`、`#reg 68085`、`#eram 4/300`、`#dram lut 8432`。
- `SYN-5114 CRITICAL-WARNING: ... cmem_syn_101 ... may requires 65536 registers`（`a1_deflate_core.v(200)`）。
- gate 阶段 `Packing 68085 DFF`，RTL DFF 仅 2549 → 差额 **65536 = 4096 × 16**，即 cmem 被展开成寄存器。
- 层次面积：`u_core` seq **67513**、eram **0**；frame_top seq 572、eram **4**（smem 已映射 ERAM20K）。
- 因此 4 个 ERAM 属于 frame_top 的 smem，cmem 完全在寄存器里；这是 slice 超限的主因之一。

## 2. 改动（唯一 RTL 改动文件：`a1_deflate_core.v`）

改前：`cmem[4096×16]` 的写来自**主时序进程（含异步复位/abort 分支）内的三处**：
1. 写 FIFO 排空：`cmem[wq_mem[wq_rptr][28:16]] <= wq_mem[wq_rptr][15:0];`（每拍 `wq_count!=0`）
2. `S_EODONE` 尾字：`cmem[cwptr] <= {8'd0, cstage[7:0]};`
3. `S_EODONE` / `S_EODONE2` 尾字：`cmem[cwptr] <= {8'd0, cacc[7:0]};`

改后（三处写全部合并为一个写口）：
- 新增组合写口 `cmem_we_c / cmem_waddr_c[11:0] / cmem_wdata_c[15:0]`，按原优先级（尾字 > FIFO 排空）合成；尾字只在 `p0_valid/p1_valid/wq_count` 全空时产生，与排空不可能同拍。
- 新增**无复位**专用写进程：`always @(posedge clk) if (cmem_we_c) cmem[cmem_waddr_c] <= cmem_wdata_c;`
- 读口从 htab 进程内移出为独立 `always @(posedge clk) cmem_rdata <= cmem[cmem_raddr];`（同为寄存器读、同拍、无条件，延迟不变）。
- 主 FSM 内三处 `cmem[...] <=` 删除，`cwptr` 自增/状态迁移保持不变。

采用的结构与 `a1_frame_top.v` 的 `smem` 完全同型（专用无复位写进程 + 寄存器读地址），后者在同一器件上已映射为 4×ERAM20K，是本项目对该器件已验证可推断的模板。仅加 `ram_style` 不作为依据，本次未使用属性。

### 等价性论证
- 写地址/数据/使能为原三处的逐拍选择，优先级与原“最后赋值优先”一致；
- `cwptr` 上界：`S_DECIDE` 在 `cwptr > 2700` 时放弃候选，`cwptr` 每块从 0 起（`S_WAIT`/块首清 0），故 12 位地址覆盖 0..4095 全域；原数组本身即 4096 深，原 13 位写地址的高位同样被忽略，因此截断不改变可观测行为；
- 读延迟仍为 1 拍（`S_REPLAY_R` 发地址 → `S_REPLAY_RD` 等待 → `S_REPLAY_E` 用 `cmem_rdata`），无新增等待；
- 无同拍读写旁路需求（replay 读取发生在整块打包完成、写口已空之后）。

## 3. 资源检查点（提交顺序）

1. 会话 1：只综合（`00_syn_check.tcl`），看 `#slice*/#eram/#reg`、`SYN-5114` 是否消失。
2. 若 `slice ≤ 71680` 且 `SWNS ≥ 0`：会话 2（`01_final_route.tcl`，脚本内自带 `slice≤71680 && WNS≥0` 才发 phy 的门闩）做最终综合 + 唯一一次布线 + `report_cdc/check_timing/report_area`。
3. 若 `slice > 71680`：不布线，报告资源证据，交规划决定下一个存储目标（frame_top smem / bm / htab）。未做属性式“假修复”。

## 4. 吞吐不变量

P2 comp 当前 355,261 cycles（81.067 MB/s），红线 370,370 cycles（77.76 MB/s），仅 +15,109 cycles（4.253%）。
本改动只把写口合成与读进程分拆，**不增加任何每字节等待**；期望 P2/P3 的 stream SHA 与 run_cycles 与 r1 逐位相同。

## 5. 回滚

唯一改动文件 `a1_deflate_core.v`；回滚即恢复 SHA `47db3057…e0a2` 版本（r1 候选）。frame_top/SDC 未改，无需回滚。
