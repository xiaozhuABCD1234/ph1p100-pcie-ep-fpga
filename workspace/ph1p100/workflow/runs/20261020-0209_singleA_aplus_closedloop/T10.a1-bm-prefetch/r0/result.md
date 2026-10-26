# T10.a1-bm-prefetch r0 — **BLOCKED**（功能红线回退，未进 TD）

- task_id `T10.a1-bm-prefetch` | round **r0** | 日期 2026-10-22 | run `20261020-0209_singleA_aplus_closedloop`
- 角色 fpga-dev（本包唯一开发）| 状态 **blocked**，**非** ready_for_test；未派测试者
- 冻结基准（本包开工时逐个复算，均一致）：core `587ef708967fbe2f…2f16`（72,445 B）、frame `18d51b1b80002e35…1cbe`、SDC `227dd39e3dba8834…6311`
- 失败候选（已保存、已从工作树回滚）：`r0/candidate-bm-prefetch.a1_deflate_core.v`，SHA256 `de59bddc0e432334…f840b`（73,493 B）
- 收尾时工作树：core 已恢复 `587ef708…2f16`、frame/SDC 未变（逐个复算）；本包 **0** 次 TD 会话、0 次综合、0 次布线、0 次下载/bitgen。

## 1. 结论（一句话）

bm 读数据第二级寄存器 + 预取前移 + `ext_mis_r` 无条件化在 **P2 `p2_perf_1920x64_comp`** 上发生**功能性回退**：压缩流每个 block（第 1 个之后）**丢失首个 literal**，导致解码数据 1 字节/块错位、Adler 校验失败；P2 comp 周期 `355,205`（≠ 基准 `355,261`）。按 §32.7「P2/P3 mismatch/X → 停，不进 TD」，**未做综合/布线/CDC**，故 ERAM clk2q 闸门本轮**无测量值**（不能声称通过或失败）。

## 2. 实际改动（仅 `a1_deflate_core.v`，4 处语义 + 4 处种子/常量）

1. 新增 `reg [7:0] bm_a_rd2`，在 bm 读口 always 块内 `bm_a_rd2 <= bm_a_rd;`（bm_a ERAM clk2q 只驱动该 flop）。
2. `htab_rd_addr` 三处 `hash3(w*, x1_r, bm_a_rd)` → `hash3(w*, x1_r, bm_a_rd2)`。
3. 预取前移一拍：`x1_r <= bm_a_rd2`；`praddr = raddr+4`（S_SCAN）/ `raddr+3`（S_PRE/S_REPOS）；种子 BHDR `2`、S_PRE cnt0 `3`、S_MCHK `pos_next_r+2`、S_REPOS cnt0 `pos+3`。
4. `ext_mis_r` 改无条件装载，前向字节经数据选择 `ext_fw_byte = (state==S_EXT) ? bm_a_rd : x1_r`（CE 去掉；D 源与基准逐拍相同）。

设计意图与对齐推导（S_SCAN 稳态）：`bm_a_rd2 = bm[pos+4]`、`x1_r = bm[pos+3]`、`w2 = bm[pos+2]`，因此 `hash3` 第三字节来自 flop，符号率仍 1 位置/拍；S_EXT 的 `bm_a_rd`/`ext_raddr`/`ext_faddr` 与基准完全一致。

## 3. 局部检查与证据（实际命令/产物）

### 3.1 P2（`tools/codec/run_p2_bm_prefetch.ps1`，54 s，RC=4）
- 产物 `r0/p2/`：`result.json`、`logs/{gen,vlog,verify,exitcodes}`、`runs/*`
- 13 例中 **12 例 PASS**（含 4 个 p1、p2_frame_16x8/bp/gapbp、rand、dist2048、len3、stored、abort/reset 负例）：zlib+strict 全通过、0 mismatch、0 X、`vlog 0/0`（`logs/vlog.log`）。
- **唯一失败**：`p2_perf_1920x64_comp`
  - `zlib_err: incorrect data check`；`strict_err: E_BAD_ADLER`；`stat_stored=0`、`stat_fixed=32`
  - `run_cycles=355,205`（基准 `355,261`，少 56）；`out_bytes=50,278`（基准 `50,310`，少 32）；`stream_sha256=9a8ba6bf…`（基准 `2601d57c…`）
  - `stat_literals/matches/max_match/max_dist` 与基准相同（19200/19200/7/351）
- 结论：**G1 FAIL**（不是"不同但合法"，流本身不可解）。

### 3.2 失败定位（自建符号级 inflate 解析 + A1_DEBUG 逐拍 trace）
- `r0/dbg_comp/stdout.log`（`vlog +define+A1_DEBUG`，153,600 B 输入，7.0 MB）
- **窗口数据正确**：37,005 条 `SCAN` 行，`w0/w1/w2` 与 `cases/p2_perf_1920x64_comp.xform` 逐位置比对 **0 mismatch**（块偏移 4800 B）；19,200 条 `MDIST` 匹配全部在块内合法（0 条跨块/错距离）；每块覆盖恰好 4800 B。
- **流层错误**：对两版 `out.hex` 做固定 Huffman 符号级解析
  - 基准：32 个 block，每块 1200 符号，解码 153,600 B，无错。
  - 候选：block 0 正常（1200 符号/4800 B）；**block 1–31 各 1199 符号、4799 B**，解码合计 153,569 B。
  - 差异位置精确：基准 block1 头部 `[L(7), M(7,1), L(8), M(7,1)…]`，候选 `[M(7,1), L(8), M(7,1), L(9)…]` —— **每块首个 literal 缺失**；其后符号序列逐项相同。候选流的首个 dist=1 匹配因此从上一块末字节（0x2b）复制，解码自块边界起即错位（`dec[4800:]=2b2b…` vs `xform[4800:]=0707…`）。
- 因此：**字节窗口/匹配裁决正确，缺陷在"每块第一个 literal 未能进入压缩流"**（块起始的 emit/packer 路径），而非 bm 预取数据对齐本身。

### 3.3 未做（按停止条件主动停止）
综合 0/2 次、布线 0/1 次、`report_clock_utilization`/`check_timing`/`report_timing_summary` 未跑、CDC 静态证据未取、bitgen not_run、无 `.bit/.cwc`、无下载/Flash。P3 未跑（P2 已失败，避免无意义仿真）。
工作树已恢复基准 core（复算 `587ef708…2f16`），失败候选留 `r0/candidate-bm-prefetch.a1_deflate_core.v`（`de59bddc…f840b`）；`r0/patch_bm_prefetch.py`（正向）与 `r0/restore_baseline.py`（反向，带哈希断言）可无损重放。

## 4. 最小下一步（交原规划，不在本包执行）

1. 在该失败候选（`de59bddc…f840b`，可直接重放 patch）上只查**块起始 emit 路径**：为何 S_REPOS→S_SCAN 后第一个 S_SCAN 周期的 `cp_en` 推入未进入流（对照 `p0/p1/p2` 与 `S_EODONE` 排水、`cp_rst`/`pbit_off`/`cand_bits`、`cwptr/clane`）。可用 `A1_DEBUG` 的 `CP0 st=…` 行在块边界处对齐比对。
2. 若 1 证明需要改 bm 预取/`ext_mis_r` 之外的逻辑（如 packer、S_EODONE、块头），按 §32.7 属**越界**，须由规划决定是否新开窄包；本包不做。
3. 不允许以此候选进 TD（ERAM 闸门、Routed、CDC 全未测）；不得放宽 P2 逐位相同/周期 355,261 门槛。

## 5. 恢复入口

- 现状：工作树 = 最佳候选 `587ef708…2f16`（hit-pipe r1 已判 FAIL routed，不得当 G2 输入）；本包 blocked，无待测候选。
- 失败证据起点：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-bm-prefetch/r0/`（`result.md`、`lessons-r0.md`、`CANDIDATE-MANIFEST-bm-prefetch.json`、`candidate-bm-prefetch.a1_deflate_core.v`、`patch_bm_prefetch.py`、`restore_baseline.py`、`p2/`、`dbg_comp/`）。
- 精确续接文本：读本 `result.md` §3.2/§4 + `p2/result.json` + `dbg_comp/stdout.log`，在候选 `de59bddc` 上只定位块起始首个 literal 丢失；改动超出 bm 预取/`ext_mis_r` 即停并交规划。
