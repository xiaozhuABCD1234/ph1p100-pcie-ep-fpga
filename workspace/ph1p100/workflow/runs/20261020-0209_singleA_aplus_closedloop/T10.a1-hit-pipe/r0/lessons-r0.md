# T10.a1-hit-pipe r0 lessons

## 1. r2 的 138 个违例只有一条锥，而且不是 hash 路径
- r2 routed `phy_pr_timing.rpt` 报告 10 条端点（每端点 1 条），**全部**是 `bm_a ERAM clk2q → state_reg[*].ceb`，−0.436…−0.412；下一条正常路径 +0.020。所以"再差 0.4 ns"其实是**一个结构点**：`S_EXT` 的 `if (bm_a_rd != bm_b_rd) state <= S_MLEN;`。
- 该比较的输入是两个 ERAM clk2q（`bm_a_rd`/`bm_b_rd`），落点是 27 态 CE 网络（`mux271*`），4 级 5.245 ns（cell 3.228 / net 2.017）。
- 可复用判据：把「最差 10 条路径的 Begin/End Point 全列出来」比读 `SWNS` 有效得多——若 10 条同源，改一个结构点即可；若分散，才需要逐锥处理。

## 2. 要让扩展字节比较寄存化，必须把字节对预取一拍（且第一个字节另有来源）
- 单口 ERAM + 1 拍潜伏 + 每符号 1 拍 ⇒ 第 k 个扩展字节的比较结果若想是寄存器，其字节对必须在 k-1 拍已就位；做法是把 S_EXT 的前向/参考读地址整体 +1（`p3_r+2` / `hf_r+2`，命中拍 `+1`）。
- 第一个扩展字节（k=1）没有"前一拍"：前向字节 = `x1_r`（命中拍已寄存），参考字节必须在**命中前那一个 s1_en 拍**读 `hent[49:37]`（=ref+3）。
- 关键坑：`bm_b` 口在 `S_SCAN` **以及 `S_PRE(pre_cnt==3)`/`S_REPOS(rp_cnt==3)`** 这三类 s1_en 拍上都是"读了不用"（S_SCAN 窗口靠 `w0..w2/x1_r` 移位链；PRE/REPOS 的 w0..w2 用的是**前一拍**的读数据）。若只按 `state==S_SCAN` 选投机读，则"重新起扫第一拍就命中"的情形会拿到 `raddr` 那一路字节 → 比较错拍。
- 症状学（下次可快速定位）：`stat_max_match` 顶到 258、`MDIST len` 比基线多 1~4、`E_BAD_ADLER`、literal/match 计数漂移。逐位 stream sha 对比能立刻把"错拍"和"只是编码不同"分开。
- 调试入口：`vlog +define+A1_DEBUG` + `vsim` 单例，`$display` 里直接打印 `bm_a[{enc_bank,p3_r}]`、`hent[49:37]`、`x1_r`、`bm_b_rd` 与各自的地址，一次就能把"哪个 flop 等于 d(1)"钉死；不要靠注释推导流水偏移（本设计注释里的 `bm_a_rd = bm[pos+4]` 与实测差一拍：实测 `x1_r=d(1)`、`bm_a_rd=bm[pos+5]`）。

## 3. `hit2`（pos 派生、含 13 bit 距离算术）不能当数据通路的 mux 选择
- 把范围判定从 stage 1 移到 stage 2 后，`hit2` 变成"寄存器 → 13 bit 减法 → 比较 → AND"，若再用它做 `(x1_r vs bm_a_rd)` 的输入 mux，就会得到 `pos → hit2 → mux → XOR → ext_mis_r.d` = 5.259 ns（第 1 次综合 WNS +0.010）。
- 改法：拆成两个独立的 `if (cond) ext_mis_r <= (...)`，让 `hit2` 只落到 flop 的 **CE**，数据锥只剩比较本身 → 最差路径降到 +0.150 以下，WNS 由 frame_top 决定（+0.021）。
- 可复用：在 187.5 MHz 下，任何"迟到的控制信号"都应只进 CE/写使能，不要进数据 mux。

## 4. 把 htab 的 hdist/range 移到 stage 2 是可行的等价改写
- stage-1 结果被消费的那一拍恒有 `pos == 上一拍 s1_pos_r`（literal 路径同步 +1；S_PRE/S_REPOS 回卷拍 `s1_pos_r` 被装成 `pos` 且 `pos` 保持），所以 `pos - hp_r` 与旧 `s1_pos_r - hent_pos` 逐值相同，`(hp_r<pos)&&(<=MAX_DIST)&&(pos<lim2)` 与旧 `s1_ok&&s1_rng` 相同。
- 效果：`htab_tag ERAM clk2q → hent_pos → 减法/比较 → hrg_r.d`（r2 综合 −0.017）整条消失，且 **P2/P3 13+20 例逐位同基线、cycles 全同**。与 r2-b lessons 的"改写比较会更差"不矛盾：那次是把比较改写成两个变量比较（仍留在 ERAM 锥里），这次是把整条算术搬到下一拍（换掉发起寄存器）。

## 5. 预布线 +0.5 门槛在"只改 core"的前提下不可达
- 现状综合最差是锁定的 `a1_frame_top`：`grp_in_row_reg[3] → smem_waddr_r_reg[15].d` 5.248 ns / 7 级，+0.021（r2 同路径 +0.130，r2-waive2 布线后 +0.020 通过）。
- 也就是说：core 的两条 ERAM clk2q 锥修完以后，synth WNS 由 **锁定文件** 决定；任何"core-only + WNS≥+0.5"的门槛都会把包卡在综合前。要么豁免一次布线，要么开 frame_top/smem 写地址的新包。
- 判据建议：这类门槛应写成"WNS≥0.5 或 连续两次综合的最差路径均不在本包写域内"，否则 blocked 是唯一合法结果。

## 6. 流程
- `PRJ-8806 Run syn_1 has exited unexpectedly` 在两次综合里都出现，但 `gate.timing/area/db` 完整；按 r2-b lessons 的 harness 继续解析即可，不要当综合失败。
- tcl 里 `create_project ... -speed 3` 会报 `PRJ-7003 auto change to -3`，无影响（与 r2 相同）。
- 仿真 harness 只需把 r2 的 `run_p2/p3` 脚本替换 run 目录即可复用（`T10.a1-htab-eram/r2` → `T10.a1-hit-pipe/r0`）；P2 + P3 合计约 8 min。

## 7. r0-route（route-only 实测）：被杀的不是那条锥，而是另一条 ERAM clk2q → CE
- 结果：Routed **SWNS −0.577 / STNS −57.504 / 311 违例端点**（hold +0.020 通过）；最差 10 条端点 Begin 全是 `bm_a ERAM clk2q`，End 是**同一个 CE 组**（`htab_byp_data.ce`、`htab_byp_n.ce`、`ext_mis_r.ce`、`add74.ce`），4 级 5.499 ns。
- 关键事实：综合 s2 里同一类路径是第 6 条端点 `bm_a_syn_41.clkb → htab_byp_reg.d` **+0.339 通过**，布线后退化到 −0.577（≈0.9 ns）。**这条锥（`bm_a_rd → hash3 → htab 读地址 → 与 s1_ins_addr 比较 → 写使能`）在 r0 计划阶段被判为"通过、不用动"，布线后却成了唯一主锥。**
- 教训 1：ERAM clk2q 锥的 synth→route 退化**不是常数**。r2 的 bm_a→state CE 锥综合 ≥+0.13、布线 −0.436（退化 ~0.57）；htab 锥综合 −0.017、布线 +0.020（"变好"）；这次的 hash/bypass 锥综合 +0.339、布线 −0.577（退化 ~0.92）。**只看综合 WNS 或只看"是否在 top-3"都会误判**；必须把 synth 报告的**全部 10 条端点**逐条列出，并假设 ERAM clk2q 锥可能退化 ~1 ns。
- 教训 2：TD 会把**不同寄存器的 CE 合并**成一组（本例 `ext_mis_r` 的 `state==S_EXT || bm_hit_a` 与 htab 旁路的写使能并到一起，于是把本不相关的一条 ERAM 地址锥带进了 311 个端点）。新增寄存器的 CE 要尽量做成**无条件写**（无 CE），否则会被并进别人的 CE 组。
- 教训 3：把 r2 的失败锥消灭 ≠ 得到改进。本包把 r2 的 `bm_a→state.ce` 比较锥消掉了，却因为上述合并 + 未处理 hash 锥，routed 结果从 −0.436 变成 **−0.577**。**"消除了已知最差锥"必须用一次真实布线验证，不能用综合推断替代。**
- 下一轮最小改动方向（未实施，交规划）：给 bm 读数据加一级寄存器 + 扫描预取整体前移一拍（`praddr = raddr+5`，`x1_r/w2` 对齐），使 `hash3` 第三字节来自 flop；`ext_mis_r` 改无条件赋值去掉 CE。两项都不加周期，但要重跑 P2/P3 逐位对比。

