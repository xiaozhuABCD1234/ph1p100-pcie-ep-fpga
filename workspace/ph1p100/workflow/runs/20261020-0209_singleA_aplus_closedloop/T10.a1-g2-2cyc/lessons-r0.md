# lessons — T10.a1-g2-2cyc r0（最终 r0-c）

1. **两拍 hit/阈值拆分零吞吐代价**：stage-1 寄存 + stage-2 决策后，P2 13/13、P3 20/20 的 stream SHA 与 run_cycles 与 r10 逐用例完全相同（1080p 4,677,945 cycles / 103.9 MB/s、comp 81.067 MB/s）。前提是每拍退休一个符号，且在 S_PRE/S_REPOS 最后一拍预计算 stage-1（无每段填充气泡）。
2. **htab 读地址必须全寄存器**：r0-a 把 `cq`（bm_a 组合读）放进地址 → -2.424 ns；改用 2 级前瞻 `x1/x2`（bm[pos+3], bm[pos+4]）后地址纯寄存器。
3. **`praddr` 调度按“可见 raddr”推导**：`praddr(T+1)=raddr(T)+3` 对所有状态成立；种子 S_BHDR=1、pre0=2、S_REPOS rp0=pos+2、S_MCHK=pos_next+1。错把 rp1 写 `raddr+2` 会读错槽并写入脏表项，症状是“计数相同但 mismatch=1”（非法 match），不是单纯漏命中。
4. **stage-1 提前插入 + 命中抑制**：`htab_we = s1_en && s1_ok && (state!=S_SCAN || !hit2)` 配合读口同址 write-first bypass，可在 1 符号/拍下保持 distance-1 与碰撞语义。
5. **把组合读地址寄存（retiming）= 零延迟、零语义风险的扇出拆分**：`rd_addr <= raddr_of(...)` 在 4 个 rd_issue 赋值点提前一拍计算、读口 `dq_r <= smem[rd_addr]`；只要 n_samp/rd_bank 在赋值点与读点相同（只在 D_IDLE/块末变化且不产生新地址），功能完全一致。r0-c 后在 S3 中 frame_top 的 `dq_r_reg`/`rd_issue_reg` 端点**清零**（S2 时它是 WNS）。
6. **综合解方差不可忽视**：同一 core RTL（e3484a60）在 S2 与 S3 的 core slack 差约 0.06 ns（S3 墙钟 24.3 min vs 8.1 min），且修好 frame_top 后 WNS 从 -0.092 变 -0.156 并非 core RTL 回归。判断“修好了吗”要看*端点归属*（frame_top 端点消失），不能只看总 WNS。
7. **最后一个已知 core 瓶颈**：`s1_ok = (s1_pos_r + 13'd2 < blk_n)` 的 13 位加法+比较（约 1.6 ns ADDER 段）串在 `s1_pos_r → htab_rd_addr(fanout 1042) → htab_rdata/rvalid` 上。最小改法：块装载时预存 `lim2 = blk_n - 2`，改 `s1_ok = (s1_pos_r <= lim2)`；可选把 s1_ok 从同址 bypass select 移出。
8. 证据技巧：对 `result.json` 的 `stream_sha256` + `stats.run_cycles` 做 r10↔r0 逐用例 diff（本次 `diffs=[]`），比只看 PASS 更能证明零语义漂移。
