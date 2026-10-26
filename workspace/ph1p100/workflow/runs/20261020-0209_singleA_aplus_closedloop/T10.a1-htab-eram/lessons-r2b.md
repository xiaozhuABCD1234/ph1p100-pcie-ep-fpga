# T10.a1-htab-eram r2-b lessons

## 1. `a >= b`（两边都是变量）会被综合成减法器，不能把迟到操作数移出进位链
- 目标：`hent_pos`（htab ERAM clk2q）本来经过 `s1_hdist = s1_pos_r - hent_pos` 的 13 位减法器到 `hrg_r`，5.286 ns / -0.017。
- 改写：用预计算下界 `s1_lo = max(s1_pos_r-2048,0)`，写成 `hent_pos < s1_pos_r && hent_pos >= s1_lo`，以为“直接比较”会绕开减法器。
- 实际综合：TD 把 `hent_pos >= s1_lo` 降成 13 位减法器（`lt34` ADDER 链），`hent_pos` 仍在进位链里；再加上两个比较的 AND 和 hrg 逻辑（3 个 LUT4 级），路径变成 **5.817 ns / -0.548**，比原方案更差。
- 结论：**“换成比较”不等于“移出 carry chain”**。要真正去掉，必须让迟到信号不进入减法/进位的被减数或被比较变量，例如：
  - 把 `hent_pos` 在 htab 读出后**寄存一级**（这会把 stage-1 变成 3 级 hit 流水，必须重做 hit2 对齐并复跑 P2/P3；本轮未做）；
  - 或把 range 判断改成基于寄存器的、`hent_pos` 只作为选择/mux 控制的形式（不再是 13 位算术的输入）；
  - 任何方案都必须以真实综合报告为准，不能只做逻辑等价推导。

## 2. 综合结果对“同功能不同写法”非常敏感；最后一次机会要用在最确定的结构上
- r1b（阈值预计算）把 WNS 从 -0.722 拉到 -0.245；r2（flag 无条件更新）再拉到 -0.017；r2-b（stage-1 边界比较）反而 -0.548。
- 三次改写的功能都逐位相同，差别全在综合/打包。结论：
  - 每次只改一个结构点，并保留每一次的 raw 报告与 candidate hash；
  - 当只剩 1 次综合时，优先选择“有同器件先例”的结构（如寄存器/预计算寄存器），不要选“让综合去推断比较器”的写法；
  - 本次 `>=` 的教训：综合器优先用减法器实现无符号比较，迟到操作数会吃掉整条进位链。

## 3. PRJ-8806 是可复现的 TD 状态检测异常，不是综合失败
- r2-b s1 再次出现 `PRJ-8806 Run syn_1 has exited unexpectedly`，但 `run.log`、`flow.status`、`gate.timing/area/db` 全部完整（opt_gate 约 40 s 完成）。
- 正确的 harness：`wait_run` 包 `catch`，之后检查 gate.timing/area 是否存在，存在就继续解析/门控；复制报告后用 SHA256 与 raw 文件比对。
- 本轮 raw 与复制件的 SHA256 已列入 manifest，供独立测试核验。
- 另注意：Tcl 不要带 UTF-8 BOM（PowerShell `Set-Content -Encoding utf8` 会写 BOM），否则 TD 直接 `invalid command name`；用 Python `utf-8` + `newline='\n'` 写 tcl。

## 4. 当前最佳与边界
- 最佳候选仍是 **r2 `0b084317`**：1/4640 端点、SWNS -0.017、STNS -0.017、slice 3068、ERAM 26、DRAM 32；P2/P3 逐位不变。
- r2-b `47b131fc` 保留为“被综合否决的等价改写”证据，不建议继续使用。
- r2 的 2/2 综合、1/1 布线额度已用尽（布线 0/1），按 dispatch 停止，**无 r3**；任何后续都需要新的用户/规划授权与新的综合/布线预算，且不得 seed sweep、降频或放宽 SDC。

## 5. 证据入口
- 结果：`../p4/result-r2b.md`；manifest：`../CANDIDATE-MANIFEST-htab-eram-r2b.json`；diff：`r2-b/candidate.diff`
- 综合：`r2-b/td/syn_gate_{timing,area}_s1.rpt`、`r2-b/td/syn_run_s1.log`、`r2-b/td/syn_flow_status_s1.rpt`、`r2-b/td/td_stdout_s1.log`
- 功能：`r2-b/p2/result.json`、`r2-b/p3/result.json`、两侧 `logs/vlog.log`
- PRJ-8806 raw：`r2-b/td/a1_ht_r2b_Runs/syn_1/{run.log,flow.status,a1_ht_r2b_gate.timing,a1_ht_r2b_gate.area,a1_ht_r2b_gate.db}`
