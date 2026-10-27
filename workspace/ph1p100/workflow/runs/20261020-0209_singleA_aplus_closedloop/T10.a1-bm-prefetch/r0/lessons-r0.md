# T10.a1-bm-prefetch r0 lessons（可复用：根因/触发/修正/验证入口）

## L1. 时序"再打一拍 + 预取前移"本身可做到零周期，但 P2 逐位等价才是裁决点
- **做法（已实现且对齐正确）**：bm 读数据加第二级 `bm_a_rd2`；S_SCAN 预取地址整体前移一拍（`praddr = raddr+4`，S_PRE/S_REPOS `raddr+3`，四处种子 +1）；`x1_r <= bm_a_rd2`；`hash3` 第三字节取 `bm_a_rd2`。稳态对齐：`bm_a_rd2=bm[pos+4]`、`x1_r=bm[pos+3]`、`w2=bm[pos+2]`，符号率不变。
- **关键易错点**：`bm_a_rd(k) = bm[praddr(k−1)]`，但 `bm_a_rd2(k) = bm[praddr(k−2)]`；推导对齐必须按"周期 k 的寄存器值 = 上上拍地址"算，且 S_PRE/S_REPOS 的种子同样要 +1（BHDR `2`、S_PRE cnt0 `3`、S_MCHK `pos_next_r+2`、S_REPOS cnt0 `pos+3`）。若只改 S_SCAN 的 `+4` 而不改种子，块首/复位后首窗口会错位。
- **注意**：命中拍（`bm_hit_a`）的 bm_a 地址是 `p3_r+1`（与预取流水解耦），因此 **S_EXT 必须继续用 `bm_a_rd` + 原 `ext_raddr/ext_faddr`**；把 S_EXT 比较改到 `bm_a_rd2` 会因命中拍地址跳变而错位。本轮就是这样保留的，S_EXT 语义与基准逐拍相同。

## L2. `ext_mis_r` 去 CE 的正确写法
- 不能简单把两条条件赋值合并成一个比较：命中拍的前向字节是 `x1_r`，S_EXT 拍是 `bm_a_rd`。写成
  `wire [7:0] ext_fw_byte = (state == S_EXT) ? bm_a_rd : x1_r;` + `ext_mis_r <= (ext_fw_byte != bm_b_rd);`
  可去掉 CE、保持 D 源逐拍不变（数据选择代替使能）。本轮该改动未见副作用（12/13 例通过）。

## L3. 本轮实际失败根因（未完全定位到 RTL 行，但症状/边界已证）
- **症状**：`p2_perf_1920x64_comp`（32 块 × 4800 B）中，压缩流**第 1 个之后每个 block 丢掉首个 literal**；块内其余符号序列与基准逐项相同。解码数据从块边界起错位，Adler 失败；总流 −32 B、周期 355,205（基准 355,261）。
- **排除项（有证据）**：`A1_DEBUG` 逐拍 trace 显示 37,005 条 SCAN 的 `w0/w1/w2` 与 `xform` 逐位置一致（0 mismatch），19,200 条匹配全部块内合法、每块覆盖恰 4800 B ⇒ **bm 窗口数据、命中/匹配裁决没坏**，坏在"每块第一个 literal 未进入压缩流"的 emit/packer 侧。
- **触发条件**：只有多块（≥2）且块首位置为 literal 的流暴露；小块例（p2_frame_16x8 等）与随机例（`p2_perf_1920x64_rand`）通过，容易被"12/13 PASS"掩盖 ⇒ **必须保留 comp 这类高压缩、多块、块首为 literal 的用例**。
- **下一步验证入口**：在候选 `de59bddc…f840b`（`r0/candidate-bm-prefetch.a1_deflate_core.v`，可 `r0/patch_bm_prefetch.py` 重放）上，用 `A1_DEBUG` 的 `CP0 st=…` 行在块边界比对 `cp_en/cp_value/p0_valid`，并查 `S_EODONE` 排水、`cp_rst`/`pbit_off`/`cand_bits`、`cwptr/clane` 的块起始状态。

## L4. 诊断手法（低成本、可复用）
- 逐位置窗口比对：`A1_DEBUG` 的 `SCAN pos/blk_n/w=` 行 + `.xform` 期望值（块偏移 4800）⇒ 先把"读数据错"与"打包错"分离。
- 符号级定位：对 `out.hex` 做固定 Huffman 解码（literal/length 用 MSB-first canonical，**distance 用 5 bit 定长、需按位反转**），按 block 比 `符号数/覆盖字节/首末符号` ⇒ 一轮就能定位"缺第几个符号"。
- 坑：`stat_literals` 与流内实际 literal 数可以不一致（本轮 19,200 vs 19,169）⇒ **不能用 stats 自证流正确**，必须解流。

## L5. 收尾纪律
- G1 失败即停在 TD 之前（本轮 0 综合/0 布线），并把失败候选另存 + 工作树恢复基准（`restore_baseline.py` 带双向哈希断言），避免锁定的最佳候选被污染。
- 本轮实际用量：约 36 次工具调用、约 85 min；未用 deepseek、未派生代理。
