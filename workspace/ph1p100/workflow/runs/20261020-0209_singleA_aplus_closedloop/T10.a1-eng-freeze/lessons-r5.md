# T10.a1-eng-freeze r5 lessons

1. **packer 三级流水可行**：p0 码值/bit offset、p1 left_shift、p2 cacc/word select，配 4-entry cmem write FIFO；match 路径仍 2 cycle，P2 13/13、P3 20/20、0 mismatch，1080p 仅 +4 cycles（4,677,945）。
2. **nbw=1/clane=0 必须写 `cstage` 而不是发 word**：旧逻辑先缓存 16-bit 窗口，下一符号才组合成完整 word；把 `p2_we` 设成 `nbw!=0` 会提前发 word，导致低字节为 0、stored LEN/NLEN 错位。
3. **输出 skid FIFO 需要入队侧 bit offset**：FSM 可以跑在 bit packer 前面，`S_SALIGN` 不能再用 bit packer 的 `obits`，必须用 `opq_bit_off`；`S_TRAIL` 也必须等 `opq_count==0` 后再做最终对齐。
4. **当前 WNS 瓶颈已从 packer 转移到 `cq -> S_EXT/state`**：S2 关键路径 6.215 ns、-0.949 ns；继续在 packer 内加流水收益已很小。S3 的 `ext_end_r` 预计算反而更差（-1.864），说明该路径不是简单“少一级比较”能解决。
5. **best candidate 是 S2 `a6f323ab…`**，S1 `8e9e…`（opq 前）和 S3 `bb935b…`（ext_end）都不如它；已回退到 S2 并重跑 P2/P3 PASS。r5 用满 3/3 综合、0/1 布线。
6. 下一轮若继续，应评估 match-extension 的 speculative 1-cycle lookahead 或 state 决策寄存器切片；必须保持每符号 1 cycle，P2 comp 81.07 MB/s 的余量很小。不得降频/false path/multicycle/seed sweep。