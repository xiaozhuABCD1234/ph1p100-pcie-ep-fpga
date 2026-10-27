# T10.a1-eng-freeze r6 lessons

1. **S_EXT 的 1-cycle 预取结构可行且吞吐中性**：S_SCAN hit 时直接捕获首字节 `cq_r/fq_r`，S_EXT 每 cycle 比较已寄存的值，同时用 `ext_raddr/ext_faddr`（寄存器）读下一字节。P2 13/13、P3 20/20、0 mismatch，1080p 仍 4,677,945 cycles / 103.892 MB/s，P2 comp 81.067 MB/s，无每符号气泡。
2. **不要把 `raddr+1` 放进捕获路径**：S1 的 `cq_r <= bm_a[raddr+1]` 造成 `raddr -> cq_r` 6.735 ns（-1.466）。改为 `ext_raddr/ext_faddr` 预置读地址后，core 路径消失（S2 -1.346 的瓶颈已不在 core）。
3. **`ext_rem` 递减计数优于 `pos+len_r+1>=blk_n` 加法比较**：初始化时饱和到 0，循环中只减 1；`len_r==257` 处理 258 上限。语义与旧 S_EXT 一致，P3 整帧验证通过。
4. **core 修好后瓶颈转移到 frame_top**：S2 关键路径是 `byte_k_reg[2] -> smem we`（6.574 ns），属于 Bayer 2 行对缓存的写使能/地址路径。继续在 core 内加流水不会改善 WNS。
5. **r5 best 仍是 `a6f323ab…`（-0.949 ns）**，r6 `24bfb7d5…` 为 -1.346 ns；r6 已用满 2/2 综合、0/1 布线，FAIL 不自动 r7。若继续，需新的 frame_top 纯流水授权与预算。