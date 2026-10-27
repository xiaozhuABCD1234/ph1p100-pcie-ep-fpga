# T10.a1-eng-freeze r4 lessons

1. **1-cycle 预取能把 bm/htab 链切断，但会把瓶颈推到预取地址本身**：S1 的关键路径变为 `raddr -> clamp_addr -> bm_a -> pcq_r`（7.376 ns）。预取地址必须来自寄存器（两拍前瞻 `praddr <= raddr+2`），不能仍用 `raddr+clamp` 的组合地址。
2. **同一 reg 不能跨 always 块驱动**：`pcq_r` 同时在 htab always 和主 always 赋值，TD 报 `constantly driven from multiple places`；ModelSim 仿真不报错但 TD elaboration 失败。预取/复位/abort 赋值应统一放在主 always 块。
3. **修掉一层关键路径会暴露下一层**：S2 把 htab 链拆掉后，关键路径变成 `len_r -> lval/ltot -> left_shift -> cstage/accw -> cmem`（7.578 ns）。TNS 从 -417.972 改善到 -183.480、违例端点 508→388，但 WNS 仍 -2.446。
4. **吞吐中性已验证**：pcq_r/praddr 预取不增加 S_SCAN 周期；P2 13/13、P3 20/20、0 mismatch、vlog 0/0，1080p p1d1 仍 4,677,941 cycles / 103.892 MB/s，P2 comp 仍 81.084 MB/s（>77.76）。
5. **下一轮候选**：对 `len_r` 的长度码/extra-bit 或 packer 移位做 1-cycle 流水，保持 match 2 cycle；必须重新检查 97.2 余量与 match-heavy 81.084 的薄余量。不要再用局部 htab 拆分；该方向已用尽。
6. **收敛轨迹**：r2 -3.792 / 109.589 → r3 S1 -2.853 / 122.160 → r3 S2 -2.374 / 129.752 → r4 S1 -2.107 / 134.409 → r4 S2 -2.446 / 128.551（TNS -183.480，违例 388）。方向有进展但不单调，需按路径逐段处理；r4 已用满 2 次综合、0 次布线，r5 不自动开。