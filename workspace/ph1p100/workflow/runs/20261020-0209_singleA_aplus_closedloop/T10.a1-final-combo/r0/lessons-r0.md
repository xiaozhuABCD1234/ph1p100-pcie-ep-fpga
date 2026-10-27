# T10.a1-final-combo r0 lessons（可复用根因/触发/修正/验证入口）

## 1. 结论速览（本轮实测）
- **单点 cycle-neutral 微修 + 组 1（retiming + phys_opt high）**：synth +0.021；**Routed −0.091 / STNS −0.308 / 12 端点**，hold +0.021/0；未达“零违例且 ≥+0.2 ns”。端点从组 1 的 45 降到 12，但 WNS 反而从 −0.039 退到 −0.091（同一 5.333 ns 周期）。
- 微修**按设计生效**：`(pos < lim2)` 比较器已离开 hit2 锥（旧最差发射点 `pos_reg[3]` 消失，新发射点 `hp_r_reg[4]`），gate 网表有 `s1_ok_r_reg`；但剩余 `(hp_r < pos)` 比较链 + hit2→bm_raddr mux→ERAM 地址锥仍 4.730 ns。
- 功能侧：33/33 逐位相同（P2 comp 355,261、1080p 81,707 B），证明该“寄存 s1_ok 复用于 stage-2”变换确实 cycle-neutral；**功能等价不等于时序收益**。

## 2. 可复用事实（TD Release_2026.2 实测）
1. **微修对布局布线的作用是“转移锥”而非“消锥”**：`rng2` 换用 `s1_ok_r` 后，路径发射点由 `pos_reg[3]` 移到 `hp_r_reg[4]`，终点仍是 `bm_a.addrb`（ERAM 地址）；残余链 `(hp_r<pos)` 比较（lt60 ADDER 链）→ `rng2_n2`（fo=6）→ `mux409`（hit2 门控）→ `bm_raddr_a` LUT6/LUT5 → `bm_raddr_a[3]` 长线（1.293 ns）→ ERAM addrb。
2. **同策略不同网表的 phys_opt 收敛差异很大**：组 1 phys_opt 718 s；本包（多一个 flop、retiming 复制点不同）261.8 s；两运行参数与命令一致（`phys_opt -post_route -effort high`），时长差异来自收敛，不是参数差异。
3. **retiming 结果随网表变化**：组 1 主要复制 `adler_fold_b_reg[8..18]`；本包为 `dval_r_reg[7..13]`、`ext_zero_r_reg`、`adler_fold_b_reg[8..10]` 等（`#reg 1,646→1,692`）。`s1_ok_r` 本身未被 retiming 移动。
4. **未加复位的单点寄存器是安全的（本设计）**：`lim2/s1_pos_r` 复位为 0，`s1_ok_r` 第一个有效沿即确定；`hit2` 由复位为 0 的 `s1_vld_r` 门控，33 例 0 X 佐证。可在“只改一处”的边界内复用该写法。
5. 报告与证据落点同组 1：`console_fc.log` 的 `PRJ-1105`/`FC_*` 标记、`a1_fc_Runs/{syn_1,phy_1}/run.log`、`routed_timing_summary.rpt`（直接 `-file`）；`report_cdc` 不存在（`RPT_CDC_UNAVAILABLE invalid command name`），`postrt_opt_loc/extra_round` 无确认行。

## 3. 触发/根因（为什么微修不足以过 +0.2 ns）
- 原 −0.039 的锥只是“13-bit `(pos < lim2)` 比较器在发射端”的贡献之一；本设计 `rng2` 里同时存在 `(hp_r < pos)` 比较与 `hdist2 = pos − hp_r` 减法（2 个 ADDER），且 `hit2` 还要经过地址 mux 驱动 `bm_a/b` 的 ERAM 地址。
- 去掉一个比较器后，剩余组合链（比较 + mux + 地址译码 + 1.3 ns 长线）在 5.333 ns 周期下仍缺 91 ps；端点数量减少说明“锥更集中”，但 WNS 取决于最差单条。
- 该包再次印证 run 的既有结论：**187.5 MHz 下剩余缺口是多条 5–6 ns 级同量级路径并存**，单点 RTL 微修 + 实现策略不能稳定闭合；要么对 `hp_r/hit2→地址` 链做结构性分拍（会动 match 语义/吞吐预算），要么换器件/QoR 手段（均超出本包授权）。

## 4. 验证入口（下次直接复用）
- 策略脚本：`r0/td/01_syn_route_final_combo.tcl`（`T:`=r0/td、`Y:`=项目根；`td_commands_prompt.exe T:/01_syn_route_final_combo.tcl`；stop marker 在 `.opt_route.begin.f` 后落 `.stop.f`，停在 bitgen 前）。
- 仿真：`r0/run_p2_final_combo.ps1`、`r0/run_p3_final_combo.ps1`（P:/W: subst；P2 走 `A1_P2_RUN` 环境变量，P3 走 argv）；基线比对脚本思路见 result §3。
- 哈希复核：`r0/artifact-hashes.txt`、`CANDIDATE-MANIFEST-final-combo-r0.json`；差异 `r0/patch.diff`；候选存档 `r0/candidate-final-combo.a1_deflate_core.v`。
- 判定口径：Routed 零违例 + setup ≥ +0.2 ns + hold ≥0；本包 FAIL，不得以“端点更少”“synth +0.021”代替。

## 5. 边界与未测
- 未改 frame/SDC；未 bitgen/`.bit`/下载/Flash；未跑门级仿真/形式等价（预算内无流程），以 RTL 级逐位回归 + gate 网表静态证据替代。
- 未尝试第二处 RTL 修改、未加综合/布线（dispatch 明确禁止）；phys_opt 时长差异已登记，不声称参数差异。
- 失败收尾：T10 保持 **3/4 PASS + 1 ⚠**；工作树已回 `35ea7364`（最佳 routed 候选）；若后续再战，需用户明确新授权（结构性分拍或更大器件/QoR 策略），不得用新 ID/改名/新 run 绕限。
