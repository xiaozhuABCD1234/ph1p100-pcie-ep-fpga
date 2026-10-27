# T10.a1-bm-addr r0-route lessons（最后一次 route-only，−0.087 / 27 端点）

## 1. 触发与结论
- r2-waive routed −0.421 / 178 违约端点（`htab_p3v ERAM clk2q → bm_b.addrb`、`pos → bm_b.addrb`、`pos → w0/w1.ceb`），本包把这三类锥清掉后 routed **−0.087 / 27 端点**，报告内 `ERAM (clk2q)` 起点 **0**。距离闭合仅差 87 ps，但 routed 门槛未获豁免 → 按 dispatch FAIL 收尾（不重布线、不重综合、不改 RTL）。

## 2. 关键数据（同一工具、同一 `Report Scheme: 10 end point(s) per path group`）
| 指标 | r2-waive | r0-route |
|---|---|---|
| SWNS / STNS | −0.421 / −23.367 | **−0.087 / −1.109** |
| 违约端点 | 178 | **27** |
| ERAM clk2q 起点端点 | 3 | **0** |
| slice / reg / ERAM | 3,016 / 1,653 / 26 | 2,993 / 1,664 / 26 |
- 剩余违约全部是**小锥 flop→flop 或跨 frame/core 边界**：`adler_red_st_reg[2] → smem.addrb[12]`（−0.087，唯一真正卡住 WNS 的路径，起在 core、终到 frame_top 的 smem 读地址）、`sdata_ptr_reg[1] → state_reg[3].ceb`（−0.084）、`dtot_r_reg[1] → praddr_reg[10/12/9].d`（−0.067×3）、`pos_reg[4] → raddr_reg[12].d`（−0.084）、`hp_r_reg[10]/pos_reg[1] → bm_a.addrb[12]/[10]`（−0.058/−0.057）。

## 3. 可复用经验
1. **“先把目标锥移出关键集”是有效的**：同一把 ERAM 读出数据放在**单级 2:1 mux** 后面（另一侧全是触发器，含 `htab_byp_data[49:37]` 这个天然寄存器），routed 直接兑现 0.33 ns（−0.421 → −0.087 的主体）。改变的是**网络/层级**而不是功能，所以 G1 仍可 33/33 逐位。
2. **命中拍专用地址提前一拍寄存**（`hf1_r <= hent[49:37]+1` 与 `hf_r` 同拍）可以同时消掉“hit2 → 加法器 → 地址”和“ERAM → 加法器”两条锥。
3. **把可被后续状态覆盖的移位改成无条件**（S_SCAN 的 `w0..w2`）是把 `hit2` 从时钟使能锥移除的最省事手段；判定依据只需枚举所有会重装这些寄存器的状态（`S_PRE@1/@2/@3`、`S_REPOS@1/@2/@3`）。
4. **TD 2026.2 的报告限制必须写进证据**：`report_timing -max_paths` 不支持（`USR-8011`），`-from <pin/cell 列表>` 被忽略，`report_cdc`/`report_clocks`/`report_exceptions` 不存在。因此“全部 ERAM clk2q ≥ +0.9”只能给“报告集合内 0 条 ERAM clk2q 起点”，不能称穷举。
5. **route-only 报告一次会话就能全部落盘**：`-file ./routed_*.rpt`（相对 T:）可用；写 `../<其他目录>/...` 在 r2-waive 触发过 `USR-8002`，因此本包把报告先写 T:，再逐字节复制到证据目录（SHA256 记录在 manifest）。
6. **早失败检查三件套**（`syn_1/settings.cfg` 的 device/package、`phy_1/settings.cfg` 非空、12 s 内 `.opt_place.begin.f`）能在 12 s 内区分 harness 故障与真实布线；`.opt_route.begin.f` 一出现即写 `.stop.f` 可稳定停在 bitgen 前（本轮 `NO_BIT_FILE`，`.bit/.cwc`=0）。
7. **不要用 synth WNS 预测 routed**：本候选 synth +0.113 → routed −0.087（−0.2 ns 级落差），而 r2 synth +0.021 → routed −0.421。两者都不满足 +0.5 预布线门槛的“安全余量”假设，**+0.5 不能当 routed 收敛的充分条件**，反过来 +0.113 也不足以保证 routed 非负（仅差 87 ps）。

## 4. 验证入口
- 布线证据：`T10.a1-bm-addr/r0-route/{routed_timing_summary.rpt,routed_timing_status.rpt,routed_area.rpt,routed_check_timing.rpt,routed_clock_utilization.rpt,routed_qor.rpt,route_flow.status,route_console.log,cdc-static.md}`；权威直接 `-file` 版本在 `T10.a1-bm-addr/r0/td/`（同 SHA256）。
- 复现：`tools/td/td_env.ps1 -Force -TdDir <r0/td>` + `td_commands_prompt.exe T:/02_route_only.tcl`（2m21s，synth 0、route 1）。
- 功能证据沿用同候选：`T10.a1-bm-addr/r0/{p2,p3}/result.json`（33/33 与 r2 逐位相同）。
