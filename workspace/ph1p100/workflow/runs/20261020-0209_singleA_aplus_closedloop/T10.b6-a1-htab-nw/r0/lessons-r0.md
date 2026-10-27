# T10.b6-a1-htab-nw r0 — lessons（只记可复用的根因/触发/修正/验证入口）

## 1. 吞吐回归的根因是“消费端晚一拍”，不是“地址没寄存”

- 触发：r5 为解决 `htab_p3v(ERAM clk2q) → bm_b.addrb` 同拍路径，把 p3 装入 `bm_b_spec_q`，但该 flop 在命中拍前**一个**周期才可用，而 r4 的命中拍 k=0 比较需要“前一拍就发出 ref+3 地址”。于是 S_EXT 多 1 拍，P2 comp 374,461（+19,200 = 每个 match 1 拍）。
- 修正要点：要恢复 r4 的拍序，必须在**主 htab 读的前一拍**用同一窗口 hash 再读一次；影子读地址要等于“下一拍的主读地址”。

## 2. 影子读在 S_PRE/S_REPOS 重播种相位取不到 flop 地址

- 根因：S_SCAN 稳态窗 byte 全在 flop（`w2/x1_r/bm_a_rd2`），但 S_PRE/S_REPOS 的头几拍窗口来自 `bm_b` 的 ERAM clk2q（`w0/w1/w2` 依次从 bm_b_rd 装入）。影子读地址若在这些相位取 ERAM 输出，等于把违例搬到影子表地址；若改用更深 bm_a 链（`bm_a_rd3` + praddr 全量 +1），相位重播种的时序与稳态不同，需要逐相位改写并重新证明，风险高。
- 可复用判据：这类“提前一拍影子读”要先数**每次重播种相位**（每块 1 次 + 每 match 1 次）；若每次补 1 拍等待，正好抵消收益，应改方案而不是硬调。

## 3. 用“表内第 4 字节”替代投机读，最小且可判定

- 结构：`htab_b3[1024]` 存 b3 = bm[条目位置+3]；写口/清表/旁路与 `htab_b` 同源（`htab_we`/`s1_ins_addr`/`htab_byp_b3`），读口同 `htab_rd_addr`，与 `hf_r` 同拍寄存 `h4_r`。
- 正确性依据（三点，缺一不可）：
  1. 插入拍 `bm_a_rd2` 在 S_SCAN/S_PRE/S_REPOS 三种 htab_pref 相位都正好是 `x1_r` 的下一个字节（bm_a 流每拍 +1），故 b3 = bm[entry_pos+3]；
  2. 编码期间 bm 只在另一 bank 写入，本 bank 内容稳定，故 b3 与 r4 匹配时读到的 `bm[ref+3]` 同值（含越界/残值场景）；
  3. b3 不参与 3 字节比较，只作为扩展 k=0 的参考字节，match 语义不变。
- 结果：P2 comp 355,261、rand 161,479、P1 3,809/5,172/6,421,414 全部与 r4 相同。

## 4. TD / 工具坑（可复用）

- `vlib.exe`（10.5b）**不接受** `-modelsimini`；`vsim/vlog` 需要它，且路径必须是**正斜杠**（反斜杠会被包进 `{}` 导致 `vsim-7 Failed to open -modelsimini`）。统一在运行器里 `str(p).replace('\\','/')`。
- `td_env.ps1` 遇到 `T:` 指向旧 run 会 fail（本次指向 b5 r1-diag）；确认无 TD 进程占用后按脚本提示 `-Force` 重映射即可，不必手写 subst。
- 01_build.tcl 的 `stop.f` 标记会在 `opt_route.begin` 后写入，route 结束后才 `wait_run` 返回；`NO_BIT_FILE` 是预期（bitgen 单独一次）。
- 综合/布线口径非同一数值：本次 syn SWNS +0.280 → routed +0.119；引用门槛只用 routed，syn 仅作“非负”门槛 + caveat。

## 5. 冻结与交付

- 停止修改后只新建 manifest/artifact-hashes/result/lessons，未再动 RTL；P2/P1/边界/工程/候选的全部 SHA 已绑定。
- 计划里的「影子表写入/清除/旁路逐项对齐」在本实现中不适用（无影子表），对应的三条等价检查改由 §3 的三点证明 + 结构证明（`routed_timing.rpt` 无 `htab_p3v` 端点组、`bm_raddr_b` 全 flop）承担；这一点需规划/测试者显式裁决。
