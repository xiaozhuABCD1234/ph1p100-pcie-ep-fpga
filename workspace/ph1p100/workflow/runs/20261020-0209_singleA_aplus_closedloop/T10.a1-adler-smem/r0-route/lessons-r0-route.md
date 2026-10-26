# lessons — T10.a1-adler-smem r0-route（2026-10-22）

## 可复用根因/事实

1. **“综合最差路径”不能预测布线最差路径，尤其跨模块到 ERAM 地址端口**。r0 综合 +0.233 的最差是 core `hp_r→bm_b.addrb`；本候选布线后同族变成 −0.530，且新出现 `ld_ptr→smem.addrb` −0.541（`ld_ptr < MAX_BLOCK` 是 `in_ready` 的一项，`in_ready` 又进入 frame_top 的 smem 读地址 mux）。PDS 的 place/route 对“core 组合 → frame_top ERAM 地址”的跨模块锥非常敏感。
2. **一次 route 的 QoR 方差很大**：bm-addr `35ea7364` 同族路径 routed −0.057…−0.087；本候选 `611ad704`（同 harness、同 settings.cfg、同 `-jobs 4`、无 QoR/seed 变更）同族 −0.47…−0.54，slice/reg/ERAM 基本相同（3,005/1,679/26 vs 2,993/1,664/26）。即：综合 +0.233 的“余量”在布线上不保证，derating 可达 0.7 ns 以上（此前按 0.2 ns 估）。
3. **清掉小锥不一定改善全局**：本候选确实把 r0 的两个目标锥（`byte_k→smem_waddr_r`、`adler_red_st→smem.addrb`）清出报告集，但暴露的 bm/raddr/ld_ptr 锥更差；单次 route 无法回退到更好的 placement。
4. **harness 事实**：`reset_run` 在 TD 2026.2 batch 中不存在（`invalid command name "reset_run"`），但 `launch_runs phy_1` 仍能新建 run；`report_cdc`/`report_clocks`/`report_exceptions` 均不存在；`report_timing -file X` 实际写出的是 timing_summary 格式（与 `report_timing_summary` 同 SHA），不要当两条独立证据。
5. **停比特流做法有效**：`.opt_route.begin.f` 出现即写 `.stop.f`，phy 流程在 fix_hold 后结束，无 `.bit/.cwc`。

## 下次入口（若用户新授权）

- 若继续追时序：应针对 **core bm 读地址 / raddr CE / `ld_ptr < MAX_BLOCK`（in_ready）** 三族做“寄存器化/预计算”，并接受需要**多次 route 或更大器件/QoR**；不要再以“adler/smem 写地址”小锥 + 单次 route 的方式尝试。
- 若只求可交付：最佳回退仍是 r2 `0b084317`（routed −0.436）或 bm-addr `35ea7364`（routed −0.087，27 端点，最接近）。
- 复现：`r0/td/02_route_only.tcl`（1 会话，route-only，约 1m38s 流程）；报告全部 `-file` 直写，`r0-route/` 为逐字节副本。

## 未测/边界

- 未做 bitgen、无 `.bit/.cwc`、无下载。
- 未做多 seed / QoR 策略 / 降频 / false path / multicycle（均未授权）。
- G1 未在本 revision 重跑（无 RTL 改动；沿用同候选 r0 的 33/33 逐位证据）。
