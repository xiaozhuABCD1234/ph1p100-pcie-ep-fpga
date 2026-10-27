# lessons — T10.a1-adler-smem r0（2026-10-22）

## 可复用根因/事实

1. **综合与布线的“最差路径”不是同一条**。bm-addr r0 综合最差是 `byte_k→smem_waddr_r`（+0.113，7 级），布线后变成 `adler_red_st→smem.addrb`（−0.087）。原因：PDS 在 place/route 把 smem 地址寄存器（写地址/读地址端口）打包进 ERAM，端点由“flop D”变成“ERAM addrb”，并把 `core in_ready → 地址 mux` 暴露成组合通路。
2. **寄存 smem 写地址的“基址+小偏移”拆分有效**：把 `(wr_bank?NSAMP:0)+row_in_blk*W` 预计算为逐行寄存器 `wbase`（帧起始清 0、行尾 +W、块尾换 bank），每字节只做 `wbase + 列偏移`。7 级 → 报告集内消失，综合 WNS +0.113 → +0.233，面积 +10 reg、slice −9。数学等价（prep 的 Bayer 行项 = row_parity*W 已折进 wbase），G1 33/33 逐位无差异。
3. **`adler_blk_q` 的“忙”窗口不能直接延长**：它在 `adler_red_st 0→1` 就被清 0，窗口由 `adler_red_st==0` 补足；要缩短 `in_ready` 的锥必须再加一个与 red_st 同步清 0 的 `adler_hold`（`in_blk_end` 置位；`in_sop`/abort/reset/red_st 回 0 清零），而不是改 `adler_blk_q` 本身（否则 3 拍归约会自触发）。
4. **+0.3 综合闸门在本设计当前冻结范围内不可达**：清掉写地址锥后，下一名是 core `hp_r→bm_b.addrb` +0.233（bm 读地址/CE 锥，7 级），再下一名 `sdata_ptr→state.ce` +0.232。两者都在 bm/FSM 逻辑内，不允许改。规划下次设闸门应先读上一轮 `syn_gate_timing_a1.rpt` 的第 2/3 名路径，而不是按“目标 87 ps + 余量”估。

## 触发/修正入口

- 若未来重新授权 core bm 读地址锥：入口 `a1_deflate_core.v` 的 `bm_raddr_b`/`praddr`（bm-addr r0 已把 hit 路径改为 flop 选择），`hp_r → bm_b.addrb` 仍经 2 个 ADDER；可考虑把 `ref+4`/`pos+4` 的加法提前一拍寄存器化（需评估 S_EXT/S_SCAN 时序与周期）。
- 若未来换更大器件/QoR：本包候选（`611ad704` core / `cc330814` frame）可直接复用，G1 已 33/33 逐位、comp 355,261、1080p 81,707 B。
- 复现命令：`tools/codec/run_p2_adler_smem_r0.ps1`、`run_p3_adler_smem_r0.ps1`；TD：`td_env.ps1` 后 `cd T:\; td_commands_prompt.exe T:/00_syn_gate.tcl`（1 会话 40 s）。

## 未测/边界

- 无 routed DB：未做 routed STA、`check_timing`、`report_clock_utilization`、静态 CDC 复核；`bitgen not_run`，无 `.bit/.cwc`、无下载。
- 布线后 `adler_hold` 是否真的把 `adler→smem.addrb` 清出关键集**未验证**（本包未布线）；该结论只能由未来授权布线确认。

## 后续（r0-route，已执行）

- 规划一次性豁免 +0.3 后 route-only 1/1：Routed **−0.541 / 299 端点** → FAIL。`adler→smem.addrb` 与 `byte_k→smem_waddr_r` 确实已清出关键集，但暴露的冻结 core bm/raddr/ld_ptr 锥更差；同 harness 下与 bm-addr 的 −0.057…−0.087 相比，单次 route 的 QoR 方差可达 0.7 ns 以上（derating 不能按 0.2 ns 估）。详见 `../r0-route/lessons-r0-route.md`。
