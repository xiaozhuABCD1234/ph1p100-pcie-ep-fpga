# T10.a1-pipe-split r0 lessons（可复用根因/触发/修正/验证入口）

## 1. 结论速览（本轮实测）
- **结构分拍成功消除了旧的最差锥**：`pos_reg[3] → bm_a.addrb`（qor-retime −0.039 / 45 端点）不再是限制项；hit2 变为 4 个 flop 的 1 级 LUT，Routed 达到 **零违例（0/4,649）**、hold +0.021、Fmax 189.179 MHz。
- **但未达 dispatch 的 +0.2 ns 门槛**：Routed SWNS **+0.047 ns**（0 TNS、0 违例）。按门槛判 **BLOCKED**，交规划裁决（不得自行放宽）。
- 功能侧 **cycle-neutral 成立**：33/33 逐位相同、0 mismatch/0 X、vlog 0/0、P2 comp 355,261 精确、1080p 81,707 B / 4,677,945 cycles。
- 关键工程事实：**187.5 MHz 下 13-bit 减法/比较不能放在 ERAM clk2q 之后**（synth 实测 5.324 ns，−0.055）；换成“预计算边界 + 双源并行比较、只选 1-bit 结果”后同一谓词归零（synth +0.275）。

## 2. 可复用事实（TD Release_2026.2 / ModelSim 实测）
1. **htab ERAM clk2q 很大**：slow_125c 下 `htab_tag` clk2q = **1.515 ns**；`bm_a/b` clk2q = **1.846 ns**。任何 13-bit 算术放在它后面都会吃掉 5.3 ns 周期的一大半。
2. **预计算边界技巧**：`hent_pos < s1_pos_r` ⇔ `hent_pos <= s1_pos_r-1`；`s1_pos_r - hent_pos <= MAX_DIST` ⇔ `hent_pos >= (s1_pos_r>MAX_DIST ? s1_pos_r-MAX_DIST : 0)`（在第一条成立时）。边界由 `s1_pos_r`（flop）提前算好，ERAM 后只剩两条并行比较。
3. **把 mux 从 ERAM 锥里移走**：`hent = byp ? byp_data : ram` 的 42-bit mux 每 bit 是 LUT3+net ≈0.64 ns；对两个源**各做一份比较**、最后按 `htab_byp` 选 1-bit 结果，等价且把 mux 移出关键路径（面积 +26 比较单元，slice 3,128/71,680 可忽略）。
4. **`s1_ok`（`s1_pos_r < lim2`）要单独寄存**：留在 ERAM 锥里会给最终 AND 增加一级；寄存为 `s1_ok_r` 后 `hit2` 为 4-flop 1-LUT，组合 `s1_ok` 仍供 `htab_we`（语义不变）。
5. **`pos + 1 >= blk_n` 是上一包 routed 的下一瓶颈（−0.036，5.028 ns）**：它等价于 stage-1 的 `s1_pos_r + 1 >= blk_n`；寄存为 `s1_last_r` 后 `pos`/`thresh_base` 的 CE 锥大幅缩短（本轮 synth 该锥不再进 top-10）。
6. **`post_route_opt ultra` 不保证执行**：本轮 param 表为 `ultra (*)`、`PRJ-1105 succeed`，但 phy 流程统计只有 place 40 s / route 29 s / fix_hold 1 s，**没有 post-route phys_opt 阶段**（上一包 718 s）。判定必须看 run.log 的阶段表，不能只看参数表。
7. **`report_cdc` 仍不存在**（TD 2026.2）；`report_clock_utilization` 只能在 place 之后跑（gate db 上报 `RUN-8001`）。`update_timing -mode final` 在 gate db 上会 `TMR-8029`，综合级只能用 `basic`。
8. **`wait_run` 竞态**：综合/布线进程正常结束后偶发 `PRJ-8806 Run syn_1 has exited unexpectedly`；以 run.log 的 `Flow Statistics` 与 `gate.timing`/`pr.timing` 的生成时间为准，不要仅凭 wait_run 报错误判失败。

## 3. 触发/根因（为什么仍差 0.153 ns 到 +0.2）
- 旧锥消除后，新的限制项是**扩展字节比较**：`bm_a/b` ERAM clk2q（1.846）→ `bm_a_rd/bm_b_rd` → `ext_mis_r` 比较（LUT6/LUT4/LUT6）→ `add41`，数据 5.003 ns，slack +0.047；紧随其后 `praddr`（+0.140）、`len_r→add9`（+0.170）、`fifo_rptr→str_crc`（+0.173）。
- 这些属于 `ext_mis_r`/`praddr`/CRC 路径，**不在本包授权范围**（分拍只针对 ERAM→range-test→address/CE 锥）。要到 +0.2 ns 需要再对这些锥做结构性处理或更大器件/QoR，需新授权。

## 4. 验证入口（下次直接复用）
- 策略脚本：`td/01_syn_ps.tcl`（纯综合检查）、`td/02_syn_route_ps.tcl`（synth+单次布线，stop marker 停在 bitgen 前）；`T:`=r0/td、`Y:`=项目根，`td_commands_prompt.exe ./02_syn_route_ps.tcl`。
- 仿真：`run_p2_pipe_split.ps1`（`A1_P2_RUN=../T10.a1-pipe-split/r0/p2`）、`run_p3_pipe_split.ps1`（P:/W: subst）。
- 静态扫描：`analysis/scan_netlists.py analysis/netlist_scan.txt td/ps_elab_netlist.v td/ps_gate_netlist.v td/ps_routed_netlist.v`。
- 哈希/冻结：`freeze_manifest.py` → `CANDIDATE-MANIFEST-pipe-split-r0.json` + `artifact-hashes.txt`。
- 判定口径：Routed 零违例 **且** setup ≥ +0.2 ns、hold ≥0；本轮 +0.047 只能判“零违例但未达门槛”，不得以“0 违例/更高 Fmax”代替门槛。

## 5. 教训（流程）
1. **不要对同一 run 目录并行跑两次 P3/P2**：vsim 会同时写 `runs/<case>/out.hex`、`stats.txt` 和同一 work 库，verifier 会读到半写文件（本轮 `f1080p_p1d0` 的假 FAIL 就是这样产生的，基线 stream_len=2,566,969 与本次一致）。长回归必须串行，或每次用独立 run 目录/work 库。
2. 修改 RTL 后先跑 P2（≈45 s）拦截功能错误，再跑 P3（≈8–12 min）；两者都必须在**最终 RTL** 上重跑，证据绑定哈希。
3. 综合检查与功能回归可并行（都只读 RTL），但**同一 TD 会话**与仿真不要争用 `P:`/`T:` 盘符；盘符重启后会丢，脚本开头要重新 `subst`。

## 6. 边界与未测
- 未改 frame/SDC；未 bitgen/`.bit`/下载/Flash；未跑门级仿真/形式等价（预算内无流程）。
- 未实施步骤 3（`p3p1_r`）；未做第二次布线、未加额外 RTL 修复轮（dispatch 禁止）。
- 失败收尾：T10 保持 3/4 PASS + 1 ⚠；是否接受 +47 ps 由规划/用户裁决，不用新 ID/改名/新 run 绕限。
