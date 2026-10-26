# T10.a1-bm-addr r0 — **BLOCKED at the synth gate**（G1 全绿；综合 WNS +0.113 < +0.5 → 按 dispatch 不布线）

- task_id `T10.a1-bm-addr` | round **r0**（最后一次定向尝试） | 2026-10-22 | run `20261020-0209_singleA_aplus_closedloop`
- 基准：`T10.a1-bm-prefetch` r2 `df6124d4`（G1 33/33 逐位、comp 355,261、1080p 81,707 B）
- frame `18d51b1b…1cbe`、SDC `227dd39e…6311`、bench top `544cecfc…f9aa` 锁定未动（开工逐个复算一致）
- 候选：`35ea7364…0942`（75,877 B，只改地址/CE 锥；diff 68 行，`r0/patch.diff`）
- **判定 BLOCKED**：G1 通过；综合 1/1 得全局 WNS **+0.113**（TNS 0.000）< 派发闸门 +0.5 → `SYN_GATE_STOP no_route`；route 0/1、CDC 未取、bitgen not_run、`.bit/.cwc` = 0、无下载
- 按 `dev-plan.md §36.5`：T10 记 **3/4 PASS + 1 ⚠**，保留 r2 `0b084317` 与 bm-prefetch/hit-pipe 证据，不自动扩轮、不新包

## 1. 改了什么（只地址/CE 锥，5 项语义步骤内）

| # | 位置 | 改动 | 目标锥 |
|---|---|---|---|
| 1 | `bm_raddr_b`（原 713–716 行） | 端口地址改为**单级 2:1 mux**：`bm_b_from_ram = s1_en && !htab_byp && !bm_hit_a`，RAM 值取 `htab_q[49:37]`；其余全部走**触发器值** `bm_b_flop_addr`（hit→`hf1_r`、S_EXT→`ext_faddr`、bypass→`htab_byp_data[49:37]`、else→`raddr`）。优先级与旧三元链逐项等价 | `htab_p3v ERAM clk2q → bm_b.addrb[11]`（−0.421/−0.362/−0.359） |
| 2 | 新增 `hf1_r`（声明/复位/`s1_en` 装载） | `hf1_r <= hent[49:37] + 13'd1`，与 `hf_r` 同拍寄存 → hit 拍的 `ref+4` 地址不再经“pos/hit2→加法器→地址”链 | `pos_reg[1] → bm_a/bm_b.addrb`（−0.407/−0.406/−0.322） |
| 3 | `S_SCAN` 开头无条件 `w0<=w1; w1<=w2; w2<=x1_r`（原在 advance 分支内） | 命中/块尾路径都会在 `S_REPOS`/`S_PRE` 由 `bm_b_rd` 重装 `w0..w2`，故功能等价；`hit2` 不再进入 w0/w1/w2 时钟使能锥 | `pos_reg[1] → w0/w1.ceb`（−0.347/−0.332） |

未改：bm 预取/ext_mis_r、htab/bm 存储位宽与端口、`thresh_lit8/9`、协议/端口/帧/CRC/长度/abort/Bayer/SDC；无新增流水拍、无 QoR/降频/exception。

## 2. G1（全绿，33/33 逐位）

| 项 | 结果 |
|---|---|
| P2 | **13/13 PASS**、0 mismatch、0 X、`vlog 0/0`；comp `len 50,310 / cycles 355,261（=硬上限内精确相等）/ sha 2601d57c…`；rand 161,479 |
| P3 | **20/20 PASS**、0 mismatch、0 X、`vlog 0/0`（含 `vlog -lint`）；`f1080p_p1d1` **81,707 B / `b769cc66…08ff` / cycles 4,677,945**；bp 等价 true |
| 逐位对比 | 与 r2 `df6124d4` 的 `result.json` **逐 case 深度 JSON 比较：P2 13/13 + P3 20/20 全字段相同（0 处差异）**，含 stream_len/sha256/cycles/negative/strict/zlib/Bayer |
| 命令 | `r0/p2/logs/exitcodes.txt` 20/20 exit=0；`r0/p3/logs/exitcodes.txt` 24/24 exit=0 |

## 3. 综合 1/1（未过闸门，未布线）

TD Release_2026.2，`T:/`=`r0/td`，`Y:`=项目根，1 会话 **46 s**；`create_project`→`syn_1`→闸门判定，无 QoR/seed/降频：

| 项 | r2 `df6124d4` | **本候选 `35ea7364`** | 闸门 | 结论 |
|---|---|---|---|---|
| 全局 WNS / TNS | +0.021 / 0.000 | **+0.113 / 0.000** | WNS ≥ +0.5 | **FAIL** |
| slice | 3,080 | 3,085 | ≤ 71,680 | pass |
| ERAM（core） | 26（22） | **26（22）** | 26 与实例相符 | pass |
| reg / DRAM LUT | 1,633 / 32 | 1,646 / 32 | — | +13 = `hf1_r` |
| 报告内 ERAM clk2q 起点端点 | 0（10 端点/组） | **0（`ERAM (clk2q)` 全文 0 次，10 端点/组）** | 全部 ≥ +0.9 | 报告集合内 vacuous-pass，**非穷举** |

- 最差路径变成**锁定的 `a1_frame_top`**：`byte_k_reg[2] → smem_waddr_r_reg[14/15].d`（**+0.113**，7 级）；r2 同一文件里是 `grp_in_row_reg[3] → smem_waddr_r_reg[15].d`（+0.021）。
- core 侧最差 **+0.232**：`sdata_ptr_reg[0] → state_reg[0..7].ce`（与地址锥无关）；r2 的 +0.402/+0.419 路径不再是最差集。
- 即：r2-waive routed 的 10 条违约端点（`htab_p3v→bm_b.addrb`、`pos→bm/addrb|w0/w1.ceb`）在综合报告集合中**已无 ERAM clk2q 起点**；但 `report_timing -from <pin/cell 列表>` 在 TD 2026.2 仍被忽略（r2-waive §3 已实证），无法给出“所有 ERAM clk2q ≥ +0.9”的穷举证明。

## 4. 为什么停在这里（不布线）

- 派发闸门：`Global synth WNS ≥ +0.5` 才布线。实测 +0.113 → 按 stop condition **不布线**（route 0/1）。
- 结构性事实：本设计综合最差路径位于**锁定不可改**的 `a1_frame_top`（+0.113），本包允许范围内不可能达到 +0.5；因此本包即使把目标地址/CE 锥完全清出关键集，也无法解锁布线。
- 未做（按 dispatch）：布线、routed STA、`report_clock_utilization`/`check_timing` 布线后报告、静态 CDC、bitgen、门级仿真、第二轮综合（无新证据不重跑）。

## 5. 回退与恢复入口

- 工作树已恢复为 G1 全绿基线 **`df6124d4`**（复算一致），最佳回退仍是 r2 `0b084317`（routed −0.436，非 G2 PASS）。
- 本包候选留档：`T10.a1-bm-addr/r0/td/a1_deflate_core.v`（`35ea7364…`）、原始基线 `r0/base/a1_deflate_core.df6124d4.v`、`r0/patch.diff`。
- 证据：`r0/p2/`、`r0/p3/`、`r0/td/`（`syn_gate_timing_a1.rpt`、`syn_gate_area_a1.rpt`、`run_console.log`、`00_syn_then_route.tcl`）、`r0/CANDIDATE-MANIFEST-bm-addr-r0.json`。

## 6. 给规划的最小下一步（不在本包执行）

1. T10 按 §36.5 收口为 **3/4 PASS + 1 ⚠**（功能/吞吐已 33/33 逐位全绿；G2 时序未闭）。
2. 若要继续，唯一未试过的类别是**锁定文件 `a1_frame_top` 的 `byte_k/grp_in_row → smem_waddr` 锥**（综合 +0.113、routed 该同一路径曾 +0.020 通过）或**更大器件/QoR 策略**——两者都超出本包授权，需用户明确新授权。
3. 不再对地址/CE 锥派发新包：本包证据显示该锥已不在综合关键集内。
