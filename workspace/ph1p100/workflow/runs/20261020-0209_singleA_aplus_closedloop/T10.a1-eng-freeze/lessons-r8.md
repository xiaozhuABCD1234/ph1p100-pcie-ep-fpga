# T10.a1-eng-freeze r8 lessons

1. **raddr 自增非常有效**：`raddr <= raddr + 1` 取代 `clamp_addr(pos+4, blk_n)`，S1 WNS -1.287→-0.586，TNS -73.092→-3.641，违例端点 165→39；S_SCAN 仍每周期 1 位置，P2/P3 全通过，1080p 4,677,945 cycles 不变。
2. **hent_pos_p3 预计算只解决一半**：把 `hent_pos+3` 在 htab 读时寄存，`fq_r` 捕获路径消失，WNS 到 -0.470；但新的 `state -> htab_rd_addr -> htab 读 -> hent_pos_p3` 成为 5.739 ns 瓶颈，TNS 反而 -3.641→-37.591、端点 39→147。
3. **同一 reg 不能跨 always 块驱动**：`hent_pos_p3` 同时在 htab always 和主 always 复位，TD 报 `constantly driven from multiple places`；把 reset/abort 放进 htab always 后修复。该 3 s elaboration 失败不计入 2 次时序综合。
4. **剩余路径是 htab 读+p3 加法**：若继续 187.5 MHz，需要把 `pos+3` 直接写入 htab（加宽字段）或在 htab 读地址侧再加寄存；这是架构级改动，不是 r8 的局部补丁。
5. **r8 是最后一次局部补丁轮**：S2 WNS -0.470 仍是 FAIL；不自动 r9。下一步必须由用户选择路线 (a) 新架构或 (b) 145–150 MHz + CDC；路线 (b) 只保证 77.76，不保证 97.2。