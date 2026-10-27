# T10.a1-eng-freeze r7 lessons

1. **frame_top smem 写端口寄存有效**：把 `smem_we/smem_waddr/smem_wdata` 寄存一拍后，`byte_k -> smem we` 的 9 级 6.574 ns 路径消失；TNS -416.270→-73.092、违例端点 404→165，G1 仍 PASS，1080p 仍 4,677,945 cycles / 103.892 MB/s。
2. **写延迟与块发布同沿是安全的**：最后字节的寄存写在块发布（`bank_busy`/`dblk`）同沿完成，drain 首读至少晚一拍；P3 的 A/B、stored、abort/reset、multi-frame 全部通过。
3. **下一瓶颈回到 core**：S1 关键路径 `pos_reg[2] -> hash_ok -> raddr_reg[10]`（6.556 ns，-1.287），是 `raddr <= clamp_addr(pos+4, blk_n)` 的更新链；r7 的 frame_top-only 范围无法修。
4. **不要在 r7 强行用 S2**：S1 已证明新关键路径在 core，r7 禁止改 core；按 stop_conditions 停止，保留 1/2 综合与 0/1 布线，而不是盲试第二条 frame_top 修改。
5. **下一步**：若继续，需要 r8（改 core 的 raddr 更新）或用户明确选择 route b（~150 MHz + CDC/异步 FIFO，≥77.76 成立、97.2 不成立）。r7 的 frame_top 改动可作为后续基线保留。