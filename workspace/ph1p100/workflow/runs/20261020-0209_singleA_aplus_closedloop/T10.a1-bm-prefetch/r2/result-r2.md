# T10.a1-bm-prefetch r2 — **BLOCKED at synth gate**（G1 全绿；综合 WNS +0.021 < +0.5 → 未布线）

- task_id `T10.a1-bm-prefetch` | round **r2**（一次性例外）| 2026-10-22 | run `20261020-0209_singleA_aplus_closedloop`
- 候选（当前工作树）：`df6124d4aa48725e…14a9c`（74,440 B），由 `3cfdda78` 叠加 r2 两处种子修正 + `S_MLEN` 提前量种子
- frame `18d51b1b…1cbe`、SDC `227dd39e…6311` 锁定未动
- **G1 全绿**；**综合 1/1 用尽，未达 WNS≥+0.5 → 按 dispatch stop condition 不布线**；route 0/1、CDC 未取、bitgen not_run、无 `.bit/.cwc`

## 1. 根因（r1 遗留）与修正

r1 的 4 个 P3 失败来自 `S_REPOS` 重定位后**漏命中**（trace：基准 `SCAN pos=42 hit2=1 hent_pos=7 hdist=35`，r1 候选 `hit2=0 hent_pos=x`）。两段原因：

1. **X**：2 级读数据后，重定位的查询地址在 `pre_cnt/rp_cnt` 早期拍用到的 `x1_r`/`bm_a_rd2` 来自更早的地址；r1 把 `S_MCHK`/`R0` 种子整体 +1 后，所需历史拍落在 `S_MLEN`（未被预置）→ 越块读 → X。
2. **错位**：把种子"缩小"又会把 hash3 第二字节取成 `bm[P+1]`（trace 里 `w=e80808` vs 基准 `e80818`）。

正确解（地址代数，`A(k)`=第 k 拍 bm_a 地址，`bm_a_rd2(k)=bm[A(k-2)]`、`x1_r(k)=bm[A(k-3)]`；重定位位置 P）：
`A(S_MCHK)=P+1`（新增 **S_MLEN** 种子 `praddr <= pos + len_r + 1` 提供历史）、`A(R0)=P+2`（S_MCHK 种子 `pos_next_r+2`，恢复 r0 值）、`A(R1)=P+3`（R0 种子 `pos+3`，恢复 r0 值）、`A(R2)=P+4`/`A(R3)=P+5`（`raddr+3` 链）。

修正后 `odd20x5_p1d1` 与基准 **逐事件相同**（198/198 事件、stream 107 B、crc `29c79a13`、cycles 1459）。

## 2. G1（全绿，唯一目标已达成）

| 项 | 结果 |
|---|---|
| P2 | **13/13 PASS**、0 mismatch、0 X、`vlog 0/0`；comp `len 50,310 / cycles 355,261 / sha 2601d57c…`；rand 161,479；bp/gapbp/abort/reset PASS |
| P3 | **20/20 PASS**、0 mismatch、0 X、`vlog 0/0`；`f1080p_p1d1` `81,707 B / sha b769cc66…08ff / cycles 4,677,945`；1080p 各模式 ≤5.19M |
| 逐位对比 | 与基准候选（`587ef708`=r2 同流）**20/20 P3 + 13/13 P2 全部 len+sha 相同（differing=0）** ⇒ 33 例逐位同 r2 |
| 产物 | `r2/p2/result.json`、`r2/p3/result.json`、`r2/dbg_base|dbg_cand/stdout.log`、脚本 `run_p2/p3_bm_prefetch_r2.ps1` |

## 3. 综合 1/1（未过闸门，未布线）

TD Release_2026.2，`T:/`=`r2/td`，`Y:`=项目根，1 会话（223 s），无 QoR/降频/seed 变更：

- **SYN WNS +0.021 / TNS 0.000**、slice 3,080、ERAM 26（core 22）、reg 1,633、DRAM LUT 32
- 闸门 `WNS≥+0.5` **未达** → tcl 自动 `SYN_GATE_STOP no_route`（未消耗布线）
- 报告前 10 条（`syn_gate_timing_s1.rpt`，Synthesized、10 endpoint/group）：
  - `+0.021` `grp_in_row_reg[3] → smem_waddr_r_reg[15].d`（**a1_frame_top，锁定文件**）
  - `+0.063` 同源 `smem_waddr_r_reg[14].d`
  - `+0.402` `u_core/p3_r_reg[0] → ext_zero_r_reg.d`；`+0.419` `hp_r_reg[0] → thresh_base_reg[3..9].ce`
- **关键结构结论**：报告集合内**没有任何 ERAM clk2q 起点端点**（r1/r0 的 `bm_a ERAM clk2q → htab/CE` 锥已消失）。注意：该报告为"每组 10 端点"，**不能**当作"全部 ERAM clk2q 起点 ≥ +0.9"的穷举证明；穷举需要定向 `report_timing` 过滤，本轮**未做**（闸门先失败）。

## 4. 已做 / 未做

已做：重放 `3cfdda78`；用 `odd20x5_p1d1` 基准/候选逐事件 trace 定位漏命中并推出地址代数；两处种子恢复 + `S_MLEN` 种子；P2 全回归、P3 全回归、逐位对比；综合 1 次并解析闸门与端点清单。
未做：布线 0/1、routed 报告、`report_clock_utilization`/`check_timing`（tcl 只在布线后执行）、静态 CDC、bitgen。

## 5. 最小下一步（交规划）

- 综合 WNS +0.021 的最差路径是**锁定的 a1_frame_top**（`grp_in_row_reg[3] → smem_waddr_r_reg[15]`），与 hit-pipe r0 同一路径（当时 +0.021/布线后该路径 +0.020 通过）。若规划愿意给"一次性 +0.5 预布线豁免"（§31.3 同类先例），本候选可直接布线 1 次；否则本包按 synth gate 收口。
- 若要严格满足"全部 ERAM clk2q 起点 ≥ +0.9"，需在综合 DB 上做定向 `report_timing -from <ERAM clk2q registers>` 穷举（1 会话内可做）。
- 无 r3；回退 `r2 0b084317`（routed −0.436，非 G2 PASS）。

## 6. 恢复入口

`T10.a1-bm-prefetch/r2/`：`result-r2.md`、`lessons-r2.md`、`CANDIDATE-MANIFEST-bm-prefetch-r2.json`、`patch_r2_repos_seed.py`、`patch_r2b_mlen_seed.py`、`p2/`、`p3/`、`dbg_base/`、`dbg_cand/`、`td/`（`00_syn_then_route.tcl`、`syn_gate_timing_s1.rpt`、`syn_gate_area_s1.rpt`、`run_console2.log`、`a1_bp_r2_Runs/`）。
工艺注意：`td_commands_prompt.exe` 必须在 **cwd=T:** 下运行，且 tcl 不能带 UTF-8 BOM（本轮两次失败均由此，均无副作用、未产生综合/布线）。
