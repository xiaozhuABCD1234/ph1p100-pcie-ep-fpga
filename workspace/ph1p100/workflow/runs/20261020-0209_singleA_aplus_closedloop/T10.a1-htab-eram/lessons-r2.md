# T10.a1-htab-eram r2 lessons

## 1. 把 flag 更新移出比较相关分支，是移除 ERAM clk2q 的有效手法
- r1 的 `ext_zero_r/len_cap_r` 只在“字节匹配且继续扩展”的 else 分支更新，使能含 `bm_a_rd != bm_b_rd`（bm_b ERAM DOB），最差路径 5.514 ns / 3 个端点。
- r2 把它们移到 `S_EXT` 开头、每个 S_EXT 周期无条件更新：
  `ext_zero_r <= (ext_rem == 13'd1); len_cap_r <= (len_r == 9'd256);`
- 结果：3 个端点→**1 个**，TNS -0.465→**-0.017**，WNS -0.245→**-0.017**；flag 路径从关键路径消失。功能 33/33 逐位不变。
- 可复用判据：若一个“辅助寄存器”只在某分支更新，且分支条件含存储输出，则它的 D/CE 会继承该存储的 clk2q；只要该寄存器在每次重装点都会重新赋值、离开该状态后 don't-care，就可以改成无条件更新。这个变换不需要改周期/协议，先做它，再考虑压比较逻辑。

## 2. htab ERAM 的 stage-1 距离路径是新的地板
- r2 后唯一端点：`htab_tag ERAM clk2q (1.515) → hent_pos → 13 位减法器 s1_hdist → (hdist<=2048)&&(hent_pos<s1_pos_r) → hrg_r_reg.d` = 5.286 ns / 5 级，slack -0.017。
- 这是 r0 htab ERAM 化的直接结果：ERAM 的 1.5 ns clk2q 直接发起 13 位减法+比较。要再降，必须让 hent_pos 不进 13 位进位链，例如预计算 `s1_pos_r`/`s1_pos_r-2048` 两个边界后直接比较 hent_pos，或把 hent_pos 再打一拍（会改变 stage-1 时序，需重新验证）。
- 这一项已超出 r2 的 flag 范围；按 dispatch 停在 blocked，不自行扩大。

## 3. 综合阶段“17 ps”也要按门槛停
- 综合 WNS -0.017 ns 看起来是噪声级，但冻结门槛是 WNS ≥0（目标 +0.3），且综合与布线的 net delay 估算差异在历史上可达 1 ns 量级；用 -0.017 去赌布线通过不符合门槛。
- 也**不要**用“同 RTL 再综合一次”碰运气：那是 seed sweep/盲重跑，规则禁止；要继续只能做有语义依据的等价改写，并且仍需新的综合次数/会话授权。

## 4. Tcl 文件不要带 UTF-8 BOM
- PowerShell `Set-Content -Encoding utf8`（Windows PowerShell 5.1）会写 BOM；TD 的 Tcl 解释器把它当命令名，直接 `invalid command name "锘?"` 并在任何 TD 命令前退出。
- 正确做法：用 Python `open(..., 'w', encoding='utf-8', newline='\n')` 写 tcl，或写完用 `encoding='utf-8-sig'` 读、`utf-8` 重写去 BOM。本轮首次 TD 调用就是因此空转了一次。
- 另：`wait_run syn_1` 要包 `catch`，并在 catch 后检查 gate.timing/area 是否存在；r1 的 PRJ-8806 就是 wait_run 报错导致 tcl 在解析/门控前退出，虽然综合已完成。

## 5. PRJ-8806 证据保留规范
- 即使父 tcl 报 `Run syn_1 has exited unexpectedly`，只要 run 目录里 `run.log`、`flow.status`、`*_gate.timing`、`*_gate.area`、`*_gate.db` 都在且 flow.status 显示 opt_gate 完成，综合结果就是完整的；复制报告后要用 SHA256 证明复制件与 raw 文件一致。
- r2 的 manifest 已列出 r1 s2 raw 文件的路径与哈希，供独立测试逐项核验；r2 s1 综合正常完成（无 PRJ-8806）。

## 6. 证据入口
- 结果：`../p4/result-r2.md`；manifest：`../CANDIDATE-MANIFEST-htab-eram-r2.json`；diff：`r2/candidate.diff`
- 综合：`r2/td/syn_gate_{timing,area}_s1.rpt`、`r2/td/td_stdout_s1.log`
- 功能：`r2/p2/result.json`、`r2/p3/result.json`、两侧 `logs/vlog.log`
- PRJ-8806 raw：`r1/td/a1_ht_r1_Runs/syn_1/{run.log,flow.status,a1_ht_r1_gate.timing,a1_ht_r1_gate.area,a1_ht_r1_gate.db}`
