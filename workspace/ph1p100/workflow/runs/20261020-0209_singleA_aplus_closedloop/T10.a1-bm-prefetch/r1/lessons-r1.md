# T10.a1-bm-prefetch r1 lessons

## L1. 加一级读数据后，"预取流水线需要更多提前量"会在**块边界**变成 X 传播
- 现症：每块（除首块）首个 literal 丢失、流短 1 B/块、`E_BAD_ADLER`，而窗口数据与匹配裁决都对。
- 真因：`S_PRE` 在 `pre_cnt==2` 的 htab 读地址用到 `x1_r`，它的值来自 **S_BHDR 那拍** 发出的地址；`S_BHDR` 只置下一拍的 `praddr`，所以那一拍仍是上一块残留地址 → 越块读 → 仿真 **X** → `hp_r/hb_r/hit2` X → `cp_en = !hit2 && …` X → literal 推入被丢。首块"恰好"干净（复位 praddr=0 读到 bm[0]），非常容易误判为"多块相关"。
- 修正：在**所有块进入 S_BHDR 的唯一入口** `S_WAIT` 预置 `praddr <= 1`（1 行，零周期、不改稳态对齐）。修后 comp 的 `out.hex` 与基准逐字节相同、355,261 周期、`hit2=x` 归零。
- 复用检查法：`A1_DEBUG` 的 `SCAN`/`CP0` 行按块对齐比对；**先看 `hit2`/`hent_pos` 是否 X**，再谈 packer。基准 vs 候选的 CP0 条目差异（多/少一行 `st=5 nbits=8`）是"literal 未入流"的直接指纹。

## L2. 预取级数 +1 必须同时重推**钳位**，不只重推 `praddr`
- r1 证据（P3）：100 B 小块 `odd20x5_p1d1`/`bp20x5`/`abort_last` 流无效（len +1、cycles +3、Adler 不符）；`f1080p_p1d1` 虽可解码但编码与 r2 不同（len 81,707→86,481，lit 14,876→20,913，匹配更多）。P2 13 例全同只说明"未被钳位路径覆盖"。
- 机理：`S_PRE`/`S_REPOS` 的 `clamp_addr(1/2/3, blk_n)`、`lim1/lim2/lim3`、`last_a` 按"读延迟 1 拍"推导；加一级后 `x1_r` 又晚一拍，块尾/小块处钳位与 `x1_r` 对应地址错开一拍 → 窗口字节错。
- 结论：以后任何"预取再提前/再加一级"必须重推 **地址种子 + 全部钳位 + 每个消费点的拍对齐**，并用"小块 + 块尾 + 多块"三类用例作为验收（P2 的 4800 B 多块用例只覆盖了帧中段）。

## L3. 判定顺序与最小证据集（本次有效）
1. `.xform` 逐位置对比 `SCAN w0/w1/w2` → 分离"读数据错"与"打包错"。
2. 符号级解析 `out.hex`（定长 Huffman；distance 5 bit 需位反转）→ 定位"缺第几个符号/哪块"。
3. `CP0` 行跨块比对 → 定位"哪一拍没推入"及是否 X。
4. `out.hex` 与基准逐字节比 → 比 stats/sha 更直接（stats 可以"看着对"）。

## L4. 脚本路径坑（本次真实踩到）
- 复制 run 脚本改轮次时，`"…\\r0\\p2"` 是**双反斜杠**字面量，只替换单反斜杠会漏；漏掉时 `$run` 仍指旧轮，而 `W:` 已换 → sim 写到新轮、verifier 在旧轮找不到流，写出伪 FAIL **覆盖旧轮 result.json**。
- 处置：改脚本必须 `Select-String` 复核所有含轮次的行；误覆盖后用**未被覆盖的 runs/** 重跑 verifier 即可复原（verifier 只依赖 out.hex + cases）。
- 另外：本机 ModelSim ASE 在含中文/空格的长绝对路径下会 `Fatal: Exiting VSIM license process`；用 `subst W:` 短路径可稳定运行。

## L5. 收尾
- G1 未绿（P2 绿、P3 3 例无效 + 1 例编码不同）⇒ 不进 TD（0 综合/0 布线/0 CDC，无 bit/.cwc）。
- 候选存档 `r1/candidate-r1-blockprime.a1_deflate_core.v`（`3cfdda78…`），工作树回滚 `587ef708…2f16`；`save_and_restore_r1.py`/`patch_r1_block_prime.py` 可无损重放。
- 实际用量：约 19 次工具调用、约 65 min；未用 DeepSeek、未派生代理。
