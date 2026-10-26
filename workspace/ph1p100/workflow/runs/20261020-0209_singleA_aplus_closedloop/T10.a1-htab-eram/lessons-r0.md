# T10.a1-htab-eram r0 lessons

## 1. 让宽表推断成 ERAM 的可复用模板（本器件已验证）
判据：TD `gate.area` 的 `#eram` 与实例数对齐、`#dram lut` 明显下降、`#reg` 回落到 RTL DFF 附近。本轮 `htab` 从 1024×66（DRAM LUT 1184、ERAM 22）变成 4 张 ERAM（ERAM 26、core ERAM 18→22、DRAM LUT **1184→32**、reg 2581→1562、slice 5259→2955）。

可复用要点，缺一不可：
1. **按宽度拆成 ≤~20 bit 的阵列**：本器件 ERAM20K 可用约 1024×20；1024×67 被 TD 拆成 4 块。66/67 bit 单阵列会让推断结果不确定；拆成 tag 16 / p3+valid 14 / pos 13 / b 24 后 4 块稳定。
2. **读口无条件寄存器读**：`always @(posedge clk) q <= mem[addr];`，不要 `if (pref)` 读使能。bm-eram 的经验（只把写口移出复位）不够，读进程里的使能+穿透 mux 才是 htab 推断失败的主因。
3. **写口独立、无复位、单写**：每张阵列一个 `if (we) mem[wa] <= wd` 进程；清表/清零也走同一写口（`we = clr | ins`，地址/数据在进程外 mux）。
4. **不要在复位进程里 for-loop 清数组**：ERAM 没有复位。把 valid 折进某张阵列（本轮 `p3v[13]`）并在复位后做 1024 拍写 0 清扫；用完成标志门控 FSM 的首块（本轮 `S_WAIT && htab_clr_done`），保持“复位后全表无效”的语义。
5. **同址写优先旁路放在 RAM 输出之后**：RAM 读口只做纯读，旁路条件/写数据打一拍（`htab_byp/htab_byp_data`），stage-1 看到的延迟仍是 1 拍、值不变。若把旁路留在读进程里，会重新变成“带使能+反馈 mux 的寄存器”，推断失败。
6. **清表代价**：固定 1024 拍启动延迟。大用例（首块加载 ≥1024 拍）周期完全不变；小用例 +866~+1044 cycles。验收要同时看硬门槛用例（P2 comp/1080p）和逐例周期，不能只看前者。

## 2. “存储全 ERAM”之后，下一瓶颈是 fabric 算术
- bm-eram：ERAM clk2q 1.515 ns 发起 hash3→htab 读 → 6.363 ns。
- 本轮 htab 改 ERAM 后：bm ERAM clk2q→bm_a_rd→第一个扩展字节 mux→比较→state.ce = 5.410 ns；把命中拍 bm_a 地址改成 `p3_r`（第一个扩展字节由 bm_a 预取，去掉 8-bit `ext_first` mux）+ 预计算 `ext_rem==0/len_r==257` 后，bm 路径移出，但 **`w0→litlen→32 位 (cand_bits+litlen) 加法器→thresh_lit 比较→state.ce` = 5.412 ns / 7 级（ADDER=4）** 顶上。
- 结论：ERAM 化只解决“存储长线”，不解决组合算术深度。187.5 MHz/5.333 ns 下，一次 ERAM 读（1.5）+ 32 位进位链（约 1.8）+ 比较/CE（约 1）就已经超预算。预计下一包必须把 `cand_bits/thresh_lit` 的 32 位比较改成 16 位拆分/提前一拍；`cand_bits/thresh_lit` 在 `MAX_BLOCK=4800` 下都 <2^16（38,442），但必须在 RTL 里显式证明再落地。

## 3. 功能等价的强验证入口
- 即使口径改为“功能等价”，本轮 33/33 的 `stream_sha256` 与 `stream_len` 仍与 bm-eram/area-map 基准逐位相同（P2 13 + P3 20），P2 comp 355,261、1080p 4,677,945~4,866,587 也逐周期相同。**先做到逐位同**再谈“允许不同”，能最快区分“延迟/旁路接错”与“只是编码不同”。
- 复位语义的等价性用 `reset_recover`（P3 mode 9：复位后重新编码并验证）和 `multi1080p` 兜底；只跑 P2 的 reset_midblock 不够（它不重新编码）。
- 旧 `htab_v` 的复位清零是“复位后全表无效”的唯一保证；ERAM 化后必须用清扫/门控替代，否则 abort/复位后旧 tag 可能命中新流。

## 4. TD 流程与预算
- 综合在本设计上很快（40~42 s），两次综合 + 读取报告只花约 3 min；瓶颈在开发侧仿真（每轮 P2/P3 约 2~4 min）。
- 新 tcl 必须**先初始化所有解析变量**再 `regexp`：旧 `01_final_route.tcl` 的 `regexp {#dram\s+...} $atxt -> dr; puts $SYN_DRAM=$dr` 在无匹配时直接 `can't read dr` 中断。本轮改为 `set syn_dram -1` + `if {[regexp ...]}`。
- 若用 `launch_runs { phy_1 }`，默认 `end_step bitgen` 会自动跑 bitgen（BIT-8123）。本轮在 `opt_route.begin.f` 出现后写运行目录 `.stop.f`，让下一步（bitgen）在 `step_begin` 直接停，避免 bitgen；但本轮 WNS 未过门，实际未启动 phy，route 0/1。
- 综合门槛 +0.5 远高于旧 +0.1；两次综合如果第一轮只到 -0.14，就应把第二次留给“下一个瓶颈”而不是微调存储；本轮的第一次已证明 htab ERAM 成立，第二次的 bm 预取虽把 bm 路径移出，但阈值加法器让 WNS 原地不动，等于用掉了一次综合。

## 5. 证据入口
- 结果：`../p4/result-r0.md`；manifest：`../CANDIDATE-MANIFEST-htab-eram.json`；diff：`r0/candidate.diff`
- 综合：`r0/td/syn_gate_{timing,area}_s1|s2.rpt`、`r0/td/td_stdout_s1|s2.log`
- 功能：`r0/p2/result.json`、`r0/p3/result.json`、两侧 `logs/vlog.log`
