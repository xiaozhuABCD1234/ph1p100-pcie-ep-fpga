# T10.b6-a1-htab-nw 设计冻结（r0，输入索引并入）

日期：2026-10-24。角色：规划。状态：ready（尚未开发、尚未冻结候选）。

## 0. 目标与边界

- 唯一目标：在保持 r5 压缩字节完全不变的前提下，去掉 r5 每个 match 的 1 拍等待，使 P2 comp 回到 **355,261 cycles**（153,600 B，187.5 MHz 换算 **81.067159 MB/s**，≥ 77.76 MB/s 门槛）。
- 只允许改 `a1_deflate_core.v` 的 htab/bm_b 读地址结构；允许为影子读增加一级 bm_a 预取寄存器。
- 不改：协议、帧头/帧长、CRC、DDR 布局、SDC/引脚/时钟/复位、UART 状态包、match 阈值、stored 回退、块/帧语义。
- 本轮不下载、不 Flash、不碰相机 `cap_frames=0` 问题；该系统问题是独立主题。

## 1. 输入索引（只读；不得覆盖）

| 对象 | 路径 | SHA256 / 事实 |
|---|---|---|
| r5 起点 core | `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b5-a1-htab-pipe/r0/changed-src/a1_deflate_core.v` | `29b1e3e1a66abef78c228c4189322b0139a266d43bf02827dd1ebe498cdc9828`；79,788 B |
| r5 同源冻结副本 | `workflow/runs/20261024-221529_fpga-sim-integration-recovery/inputs/a1-r5/src/a1_deflate_core.v` | 同上 |
| r4 生产 core | `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v` | `d4b799612519d4cb6c32a0c0e87807be84dec711fc01e2146b054d464d1b88de`；78,114 B |
| b5 r0 结果/证据 | `.../T10.b5-a1-htab-pipe/r0/result-r0.md`、`CANDIDATE-MANIFEST-b5-a1-htab-pipe-r0.json`、`rtl-diff-r0.patch` | 记录 r5 的 +1 拍等待、P1 三例、TD Routed +0.100/0、bit/CWC |
| b5 r0 TD 模板 | `.../T10.b5-a1-htab-pipe/r0/td/{01_build.tcl,02_bitgen.tcl,03_cwc.tcl,src/,a1_eng_top.v,a1_small_top.sdc,p2_board.sdc,board_p2.adc}` | 只读复制；只允许改 core 源路径一行 |
| P2 comp 输入 | `work/parallel-sim-20261024-2204/codec-throughput/comp/in.hex` | `edbfdeaedb06824ced20ad76b260979e95e1322d6f6e3bab5e7a951a268f9849`；614,400 B |
| P2 comp 元数据/期望 | `.../comp/in.meta`、`.../comp/in.xform` | `e98c9a1c...80fe`、`b836b51d...ba7a` |
| P2 comp r5 结果 | `.../comp/stats.txt`、`.../result.json` | 374,461 cycles；流 50,310 B，SHA `2601d57cd98d1fe69b2e46fe8423779a5d44bd14c00e1fe2d5faab6ff15a7c05`（以 result.json 为准，前缀是 2） |
| P2 rand 输入/结果 | `.../rand/{in.hex,in.meta,in.xform,out.hex,stats.txt}` | 161,479 cycles；流 153,766 B，SHA `54f262f2a600a3e2f12129f2937a390737d1ec8018d8f0236979e604760496dd` |
| P2 TB / runner / 参考 | `upstream/ph1p100-pcie-ep-fpga/sim/tb/codec/tb_a1_deflate_core.v`、`work/.../codec-throughput/{run.py,run-paired.py}` | TB 端口/统计不变；`+BP=0 +GAP=0` |
| P1 TB | `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/r0/sim/tb_camera_a1_uart_top.v` | b5 r0 实际使用的 TB；`vlog_r0.log` 记录精确文件表 |
| P1 r4 金标 | `.../T10.b5-a1-htab-pipe/r0/sim/captures/{micro8x2,mid64x8,full_grad}.dec` | 63 B `fa513a2b...def`；150 B `ee61e620...789`；40,076 B `b992a8ad...ada9` |
| P1 命令记录 | `.../T10.b5-a1-htab-pipe/r0/sim/logs/{vlog_r0.log,sim_micro8x2.log,sim_mid64x8.log,sim_full_grad.log}` | 复用其 vlog/vsim 参数；新 core 替换旧 core |
| 核心边界用例 | `.../T10.b5-a1-htab-pipe/r0/sim/captures/` 及 `work/.../boundaries/{odd8x3,random64x8}` | 奇数尾块 8×3、随机 stored 64×8；只复测 core 相关项 |
| SDC/约束 | b5 r0 `td/p2_board.sdc`、`a1_small_top.sdc`、`board_p2.adc` | 逐字节不变；禁止新增 false path/multicycle |
| 现有 r5 TD 结果 | b5 r0 `td/routed_timing.rpt`、`syn_gate_timing.rpt`、`routed_qor.rpt` | Routed WNS +0.100/0、hold +0.020/0；synth +0.222；ERAM 101/300 |
| 独立探索结论 | `work/parallel-sim-20261024-2204/summary.md`、`codec-throughput/result.md` | r5 比 r4 多 19,200 拍 = 每 match 1 拍；功能正确、吞吐 FAIL |

## 2. 数据/接口冻结

- `a1_deflate_core` 端口、位宽、时钟、复位、`in_*`/`out_*` 握手不变。
- `a1_frame_top`、`camera_a1_uart_top`、`a1_uart_export`、`a1_ddr_slot_store`、`a1_ddr_arb2`、`a1_raw_crop`、`capture_async_fifo` 全部不动。
- UART 状态包保留（诊断用），格式/字段/波特率不动。
- 帧头、块头、固定 Huffman、stored 回退、Adler32、CRC、长度、DDR 槽位/布局不动。
- 187.5 MHz 时钟、`p2_board.sdc`、引脚/ADC 不动；无 multicycle/false path/clock 改动。
- P2 TB 的 `+BP=0 +GAP=0` 固定；不得用喂数节流掩盖吞吐。

## 3. r5 已定位的吞吐根因（必须消除）

r5 为闭合 `htab_p3v_q[12:0] → htab_q[49:37] → bm_raddr_b → bm_b.addrb` 的 ERAM→ERAM 同拍路径，把 bm_b 的候选地址寄存为 `bm_b_spec_q`：

```verilog
reg [12:0] bm_b_spec_q;
always @(posedge clk) if (s1_en)
    bm_b_spec_q <= htab_byp ? htab_byp_data[49:37] : htab_q[49:37];
wire [12:0] bm_raddr_b = s1_en ? bm_b_spec_q
                       : (state == S_EXT) ? ext_faddr
                       : raddr;
```

该寄存器比 r4 晚一拍，导致 hit 拍拿不到 `bm[ref+3]`，S_EXT 增加 `ext_first` 等待拍；comp 19,200 个 match 正好 +19,200 cycles。b6 必须保留 `bm_b_spec_q` 的“flop 驱动 bm_b 地址”结构，但让它在 hit 拍之前就装好正确候选的 p3。

## 4. 允许的实现结构

### 4.1 首选 A：提前一拍的 htab p3v 影子读（推荐）

1. 保留现有主 htab 读/比较/插入/旁路拍序：`htab_rd_addr`、`htab_q`、`s1_ins_addr`、`htab_we`、`htab_byp` 不得改拍。
2. 新增一个只读影子端口（`1024×13` 的 p3 影子，或 `1024×66` 的全表影子；写/清与 `htab_p3v` 同源），其读地址比主读地址**早一拍**：主读在 T-1 发地址、T 出数据给 stage-1 比较；影子读必须在 T-2 发同一窗口的 hash，T-1 出数据并装入 `bm_b_spec_q`。
3. 影子读地址必须只由 fabric flop 驱动。若当前可用的 window hash 字节仍含 `bm_a` 的 ERAM clk2q 输出，允许新增一级 `bm_a_rd3 <= bm_a_rd2` 预取，并只用该更深寄存器参与影子 hash；**不得改变现有 `bm_a` 读地址、`w0..w2/x1_r` 窗口链、`p3_r/praddr` 更新**。
4. 影子路径的写优先旁路必须与主表同语义：
   - 影子读地址在 T-2 与 `s1_ins_addr` 同址时，用当场 `s1_ins_data` 的 p3 值；
   - `bm_b_spec_q` 在 T-1 装载时，若主 `htab_byp` 有效（T-1 同址写），必须用 `htab_byp_data[49:37]` 覆盖影子值。
   两条缺一不可；这是 distance-1 匹配和 10-bit hash 碰撞时保持字节不变的关键。
5. `bm_raddr_b` 仍为 r5 的 flop-only 形式：
   ```verilog
   wire [12:0] bm_raddr_b = s1_en ? bm_b_spec_q
                          : (state == S_EXT) ? ext_faddr
                          : raddr;
   ```
   禁止任何 ERAM clk2q 直接驱动 `bm_raddr_b` 或 htab 读地址。
6. 恢复 r4 的 hit 拍扩展比较：hit 拍 `cq_r <= x1_r`；`ext_raddr <= p3_r + 2`；`ext_faddr <= hf_r + 2`；`bm_b_rd` 在 hit 拍必须是 `bm[ref+3]`；`ext_mis_r` 在 hit 拍寄存 k=0 比较；S_EXT 从下一拍起按 r4 每拍判决。删除 r5 的 `ext_first` 等待分支及其“等待拍 +1 地址推进”。

### 4.2 备选 B：htab 读+比较整体后移一拍

若 A 的资源/时序不可接受，可把 htab 读地址、输出寄存、stage-1 比较、插入/旁路整体后移一拍，并用新增 bm_a 预取保证地址为 flop-only。该方案会改变 `s1_pos_r` 与 `pos` 的固定 skew，必须用 P2/P1/边界全量证明字节不变；风险高于 A，未证明前不得采用。

### 4.3 禁止

- 用放宽阈值、降频、改 SDC、false path、multicycle、seed sweep 换 PASS。
- 改 match 阈值、stored 回退、块/帧/CRC/UART/DDR 布局。
- 用“减少 match 数”或“改输出”换周期；目标是同输入同输出少 19,200 拍。
- 改 `upstream/**`、b5 r0 证据、`D:\TD\work\csi2`、共享 bit/CWC。

## 5. 精确等价条件（硬门槛）

1. P2 comp：`run_cycles == 355,261`；流 50,310 B，SHA `2601d57c...a7c05`；zlib 与 strict 解码 0 字节差异；TB `done=1/out_last=1/timeout_hit=0`。
2. P2 rand（stored 回退）：流 153,766 B，SHA `54f262f2...496dd`；cycles ≤ 161,479。
3. P1 三例逐字节与 r4 金标一致：
   - micro8x2：63 B，`fa513a2b...def`，cycles ≤ 3,809；
   - mid64x8：150 B，`ee61e620...789`，cycles ≤ 5,172；
   - full_grad：40,076 B，`b992a8ad...ada9`，cycles ≤ 6,421,414。
4. core 相关边界：奇数尾块 8×3、随机 stored 64×8 的 RAW/码流/CRC/尾垃圾/重复读与 r5 记录一致；双路同步/负对照 RTL 未改，可复用 b5 结论并注明未重跑理由。
5. 结构证明：新关键路径不得出现 `htab_p3v_q → bm_b.addrb` 端点组；`bm_raddr_b`/htab 地址必须由 flop 驱动；影子表写入/清除/旁路与主表逐项对齐。

## 6. 资源、缓冲与时序预算

- 影子表新增 ≤ 2 个 ERAM（全表 66 bit）或 ≤ 1 个 ERAM（仅 p3 13 bit）；b5 r0 ERAM 101/300，新增后必须记录实际值且不得超器件。
- 允许新增少量 fabric flop（`bm_a_rd3`、影子输出寄存、旁路寄存）；不得改变现有 BRAM 深度/宽度语义。
- Routed 门槛：WNS ≥ +0.05 ns、TNS=0、0 违例端点；hold ≥ 0、period check 0、组合环 0、无时钟网 0；记录 Fmax、LUT/REG/ERAM/slice、STA coverage、最差路径。
- b5 r0 Routed +0.100 ns 是已知薄余量；b6 若落在 +0.05…+0.10 必须在结果/manifest 写 caveat，不得宣称 +0.2 稳健。

## 7. 工作目录与构建入口

- 包根：`D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b6-a1-htab-nw\`
- 开发在 `r0/`；`r0/changed-src/a1_deflate_core.v` 是唯一 RTL 变更；`r0/sim/` 放 P1/P2 证据；`r0/td/` 放 TD 工程。
- TD 目录由 b5 r0 `td/` 的 `src/`、`a1_eng_top.v`、`a1_small_top.sdc`、`p2_board.sdc`、`board_p2.adc`、`01_build.tcl`、`02_bitgen.tcl`、`03_cwc.tcl` 复制而来；不复制 `a1_board_Runs/`、`cw/`、旧 bit/cwc/bid/报告。`01_build.tcl` 只改 core 源路径一行到 b6 changed-src。
- 盘符：`powershell -NoProfile -ExecutionPolicy Bypass -File tools\td\td_env.ps1 -TdDir <包 r0/td 绝对路径>`；`T:`=td 目录，`Y:`=项目根。TD CLI 用 `D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe`，cwd=td 目录，脚本 `./01_build.tcl`、`./02_bitgen.tcl`、`./03_cwc.tcl`。
- 仿真：ModelSim 10.5b；P1 复用 b5 r0 `logs/vlog_r0.log` 的文件表与 `sim_*.log` 的 generics/plusargs；P2 复用 `codec-throughput` 的 TB/向量与 `+BP=0 +GAP=0 +TIMEOUT=2000000`。
- 所有构建/仿真实测必须写命令、cwd、exit、超时、产物 SHA；不得只抄旧结果。

## 8. 验收阈值汇总

| 维度 | 门槛 |
|---|---|
| functional | P2 comp 355,261 + SHA；P2 rand SHA；P1 三例逐字节；8×3/64×8 边界 |
| engineering | Routed 0 违例、WNS ≥ +0.05、TNS 0、hold ≥ 0、period 0、无组合环/无时钟网；资源在器件内；记录 caveat |
| system | 本轮仅离线；UART 状态包保留、接口/协议/帧/CRC/DDR/SDC 不变；板级/下载 not_run（用户明确本轮不下载） |
| G 层 | G0/G1 功能；G2 小拓扑/板级 P2 工程 Routed；G3 bitgen+CWC；G4 板级不适用/推迟 |

## 9. 不适用与推迟

- 相机前端 `cap_frames=0`、真实曝光同步、板级吞吐/稳定性：独立问题，本轮不混入。
- P3 下载/COM8 采集、Flash：本轮 0 次，不授权。
- 双路同步控制 RTL：本包未改，复用既有 PASS 结论，不重复消耗仿真轮次。
