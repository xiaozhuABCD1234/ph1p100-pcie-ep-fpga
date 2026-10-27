# T10.a1-htab-eram r1 lessons

## 1. 字面量阈值比较：预计算阈值差是最稳的写法
- 目标式：`cand_bits + litlen >= thresh_lit`。`litlen` 是 w0 的 fixed-Huffman 码长，字面量只可能是 8（w0<144）或 9；因此等价于 `cand_bits >= thresh_lit - litlen`。
- 有效写法：新增 `thresh_lit8 = thresh_lit-8`、`thresh_lit9 = thresh_lit-9` 两个寄存器，在 `thresh_lit` 的每个赋值点同步更新（S_WAIT、S_SCAN 字面量通过、S_MCHK），比较写成 `lit_ge = (litlen==9) ? (cand_bits>=thresh_lit9) : (cand_bits>=thresh_lit8)`。32 位比较从寄存器出发，w0 路径只剩 litlen+2:1 select。
- 效果（本器件、本设计）：r0 的 `w0→32 位加法→比较→state.ce` 路径消失；综合从 -0.146/40 端点/TNS -4.909 变成 -0.245/**3 端点/TNS -0.465**。字面量路径不再是关键路径。
- **不要用 17 位低半和**：`{1'b0,cand_bits[15:0]} + litlen >= {1'b0,thresh_lit[15:0]}` 虽然数学正确（有 16 位范围证明），但这次综合把 bm_a_rd→state.ce 重新排成 5.988 ns / 6 级，WNS 反而 -0.722。小改动会改变综合的 LUT 打包/重定时，必须用真实综合验证，不能只推逻辑深度。

## 2. 任何“使能依赖 ERAM 输出”的寄存器都会继承 1.5 ns clk2q
- r0 step-2 为缩短 S_EXT 加的两个 flag：
  `ext_zero_r <= (ext_rem==13'd1)`、`len_cap_r <= (len_r==9'd256)` 只写在“字节匹配且未停止”的 else 分支里。于是它们的 D/CE 使能依赖 `bm_a_rd != bm_b_rd`（bm_b ERAM DOB），r1b 综合后最差路径变成 `bm_b ERAM clk2q → 字节比较 → ext_zero_r_reg.d = 5.514 ns`（3 个端点）。
- 这两个 flag 每次命中都会重装（hit 分支 `ext_zero_r <= (ext_rem_new==0); len_cap_r<=0`），离开 S_EXT 后是 don't-care。因此可以把更新改成 **S_EXT 内无条件**（或提前一拍由 ext_rem/len_r 直接算），既保持语义又把 ERAM clk2q 移出 D 路径。这是下一轮唯一有证据的 0.245 ns 修法。
- 通用规则：对“只在某分支更新”的辅助寄存器，先问它的使能是否含存储输出；若是，改成无条件更新/用寄存器预计算，比继续压比较逻辑更有效。

## 3. 综合不确定性要用“端点/TNS”一起看
- 同一功能、不同等价写法：r1a（17 位和）-0.722/39 端点/TNS -18.177；r1b（阈值预计算）-0.245/3 端点/TNS -0.465。WNS 数值甚至比 r0（-0.146）差，但 TNS/端点数大幅改善，说明修对了方向、只是暴露了下一条窄路径。
- 报告只列 10 条/组；用 `flow.status` 的 `NUM_FEPS` 和 TNS 判断整体，别只看 WNS 数值的绝对值。
- 本设计综合很快（37~42 s），但预算仍应按“综合次数/会话次数”冻结；本轮两次综合各用一次会话，第三次修法没有预算。

## 4. TD `PRJ-8806 Run exited unexpectedly` 的可恢复姿势
- 本轮 s2 综合的父 tcl 在 `wait_run syn_1` 处报 `PRJ-8806`，tcl 在复制/解析/门控之前退出。
- 但 run 目录里 `run.log`、`flow.status`、`*_gate.timing`、`*_gate.area`、`*_gate.db` 均存在，`flow.status` 显示 opt_gate 完成且导出 DB。说明这是 run 状态检测异常，不是综合缺结果。
- 处置：直接检查 run 目录并手工复制报告；不要因为父 tcl 报错就判“综合失败”。修复 tcl 时应在 `wait_run` 外包 `catch`，然后无条件走“报告存在才解析/门控”的路径（本轮 tcl 只 catch 了 phy 的 wait，没 catch syn 的 wait，是教训）。
- 该异常下仍未启动 phy/bitgen（门控 WNS 未过），route 0/1、bitgen 0 保持不变。

## 5. 证据入口
- 结果：`../p4/result-r1.md`；manifest：`../CANDIDATE-MANIFEST-htab-eram-r1.json`；diff：`r1/candidate.diff`
- 综合：`r1/td/syn_gate_{timing,area}_s1|s2.rpt`、`r1/td/syn_flow_status_s2.rpt`、`r1/td/syn_run_s2.log`、`r1/td/td_stdout_s1|s2.log`
- 功能：`r1/p2/result.json`、`r1/p3/result.json`、两侧 `logs/vlog.log`
