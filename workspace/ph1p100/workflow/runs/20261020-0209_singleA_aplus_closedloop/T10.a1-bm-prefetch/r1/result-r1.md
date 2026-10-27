# T10.a1-bm-prefetch r1 — **BLOCKED**（G1 仍红：P3 3 例流无效 + 1080p 编码与 r2 不同）

- task_id `T10.a1-bm-prefetch` | round **r1**（同包功能修复）| 日期 2026-10-22 | run `20261020-0209_singleA_aplus_closedloop`
- 角色 fpga-dev | 状态 **blocked**，非 ready_for_test；未派测试者
- 基准（逐个复算）：core `587ef708…2f16`、frame `18d51b1b…1cbe`、SDC `227dd39e…6311`
- r1 候选（已存档，工作树已回滚）：`r1/candidate-r1-blockprime.a1_deflate_core.v`，SHA256 `3cfdda78a23465a7…1adcf`（73,993 B）
- TD：**0 会话 / 0 综合 / 0 布线 / 0 CDC**（G1 未绿，按 §stop 不进 TD）；run 内 `.bit/.cwc` = 0；无下载/Flash。

## 1. r0 块起始丢 literal 的**根因已定位并修复**（P2 转全绿）

**根因（X 传播，而非 packer 逻辑）**：加了第二级读数据后，`S_PRE` 在 `pre_cnt==2` 的 htab 读地址是 `hash3(w0, x1_r, bm_a_rd2)`，而 `x1_r(P2) = bm_a_rd2(P1) = bm[praddr( S_BHDR 那一拍 )]`。`S_BHDR` 只把 **下一拍** 的 `praddr` 置 2，因此 S_BHDR 当拍的 `praddr` 还是上一块残留值（≈4805）→ **越块读**（该 bank 该地址从未写过）→ 仿真 X。块 0 恰好干净（复位后 praddr=0，读到 bm[0]）。

X 经 `htab` 读数据 → `hp_r/hb_r` → `hit2` 在每块第一个 `S_SCAN` 拍为 X → `cp_en = !hit2 && (pos < blk_n)` 为 X → **该 literal 推入被丢弃**（每块 1199 符号/4799 B）。

证据（同一 1920x64 comp 用例，A1_DEBUG）：
- 基准：`CP0 st=5 nbits=8 val=00ec off=3 cand_bits=3`（即 0x07 的定长码）紧接 `SCAN pos=0 … hit2=0 hent_pos=4505 hdist=3687`
- r0 候选：**缺**该 CP0 行；`SCAN pos=0 … hit2=x hent_pos=x hdist=x`；后续所有 `cand_bits` 少 8。

**修复（1 行，不改时序/周期）**：`S_WAIT`（所有块进入 `S_BHDR` 的唯一入口）中预置 `praddr <= 13'd1;`，使 PRE 阶段流水线读到块内 `bm[1]`，与基准一致。

修复后（`r1/dbg_fix/`）：
- `out.hex` 与基准 **逐字节相同**（SHA256 前缀 `062826BDCABB8939` 双方一致）
- `run_cycles` **355,261**、`out_bytes` 50,310、`hit2=x` 出现 **0** 次
- **P2 回归 13/13 PASS**（`r1/p2/result.json`，RC=0，40 s）：comp `len=50,310 / cycles=355,261 / sha=2601d57c…`（= 基准），rand 161,479，0 mismatch、0 X、`vlog 0/0`，bp/gapbp/abort/reset 均 PASS。

## 2. P3 首次运行暴露**两个新的 G1 失败**（r1 候选 → FAIL）

`r1/p3/result.json`（20 例，525 s，`vlog 0/0`+lint OK）：

| 用例 | 基准（587ef708） | r1 候选 | 判定 |
|---|---|---|---|
| `odd20x5_p1d1` / `bp20x5` / `abort_last`（100 B 帧） | PASS：len 107、cycles 1,459、sha `2c7272f2…` | **FAIL**：len 108、cycles 1,462、sha `88cd54b9…`、`E_BAD_ADLER stored=DA32209A calc=C7842082` | 流无效 |
| `f1080p_p1d1`（2.592 MB） | PASS：len 81,707、lit 14,876、mt 28,171、sha `b769cc66…` | PASS 但 **len 86,481、lit 20,913、mt 28,514、sha `ffafd6de…`** | 违反"与 r2 逐位相同" |
| 其余 16 例 | PASS | PASS（sha/len/cycles 与基准相同） | — |

- 3 个 100 B 用例失败值完全相同（同一帧、同一错误），+3 周期/+1 字节 → 块内/块尾字节账目错位，Adler 不符。
- 1080p 例压缩率反而更好（31.7 → 33.8），说明**匹配裁决与基准不同**（不是等价重编码）。

**剩余根因判断（未修，超 r1 授权范围）**：`S_PRE`/`S_REPOS` 的预取地址钳位（`clamp_addr(1/2/3, blk_n)`、`lim1/lim2/lim3`、`last_a`）是按"读延迟 1 拍"写的；加了一级后 `x1_r` 比 `bm_a_rd2` 再晚一拍，块尾/小块处钳位生效的拍与 x1_r 对应的地址错开一拍 → 窗口第三/第二字节取错 → 决策不同或块尾账目错。修正需重推 PRE/REPOS 预取种子与钳位（属 r0 冻结的 bm 预取区），r1 派发只允许"块起始首个 literal 的 emit/packer"，故**停止并交规划**。

## 3. 已做 / 未做

已做：重放 `de59bddc`；A1_DEBUG CP0/SCAN 跨块比对（基准 vs r0 候选）定位 X 源；1 行 S_WAIT 预置修复；P2 全回归（13/13 PASS、comp 355,261、out.hex 逐字节同基准）；P3 全回归（20 例）；保存 r1 候选并回滚工作树；修复 r1 仿真脚本路径并在 r0 流上重跑 verifier 复原 `r0/p2/result.json`。
未做：综合 0/2、布线 0/1、`report_clock_utilization`/`check_timing`/`report_timing_summary`、静态 CDC、bitgen（全部 not_run）。

## 4. 最小下一步（交规划）

1. 在 `3cfdda78` 上只重推 **S_PRE/S_REPOS 预取种子与钳位**（`clamp_addr`/`lim*`/`last_a` 与 `x1_r` 的拍对齐），使小块/块尾窗口字节与基准一致；不得改协议/端口/帧语义/SDC/frame。
2. 之后仍须 G1 全绿（P2 13/13 + P3 20/20 且 SHA/len/cycles 与 r2 逐位相同、comp 355,261）才可进综合；ERAM clk2q 闸门本轮**无测量值**。
3. 若"重推钳位"被判为超出本包范围，则本包按 r1 G1 fail 收口，保留 r2 `0b084317` 为最佳回退、`587ef708` 为工作树候选。

## 5. 恢复入口

- 失败证据：`T10.a1-bm-prefetch/r1/`（`result-r1.md`、`lessons-r1.md`、`CANDIDATE-MANIFEST-bm-prefetch-r1.json`、`candidate-r1-blockprime.a1_deflate_core.v`、`patch_r1_block_prime.py`、`save_and_restore_r1.py`、`dbg_fix/`、`base_dbg/`、`p2/`、`p3/`）
- 工作树：core `587ef708…2f16`（已回滚）、frame `18d51b1b…1cbe`、SDC `227dd39e…6311`
- 续接文本：读本文件 §1–§4 + `p3/result.json`（3 个 20x5 用例 + f1080p_p1d1）+ `r0/lessons-r0.md L1/L2`，在 `3cfdda78` 上只动 PRE/REPOS 预取钳位；超范围即停。

## 6. 过程瑕疵（已修复，如实记录）

第一次跑 r1 的 P2 脚本时，脚本内 `$run` 仍指向 `r0\p2`（只替换了单反斜杠形式，漏掉 `\\r0`），而 `W:` 已指向 r1 → sims 写到 r1、verifier 在 r0 找不到流，写出一个伪 FAIL 覆盖了 `r0/p2/result.json`。已修正脚本（双反斜杠）并在**未被覆盖**的 r0 流上重跑 verifier，`r0/p2/result.json` 恢复为 r0 原始结论（FAIL、comp `50278 B / 355,205 cycles / sha 9a8ba6bf…`）。r0 的 `dbg_comp/`、`runs/`、`cases/` 未受影响。
