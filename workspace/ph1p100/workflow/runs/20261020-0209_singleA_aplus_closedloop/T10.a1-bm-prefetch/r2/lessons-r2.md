# T10.a1-bm-prefetch r2 lessons

## L1. 预取"再加一级"时，`S_PRE`/`S_REPOS` 需要**多一拍历史**，来源是各自的前驱状态
- 2 级读数据（`bm_a_rd2=bm[A(k-2)]`、`x1_r=bm[A(k-3)]`）后，重定位（`S_REPOS`）第一拍的比较数据来自 `R2` 拍发出的地址，其中第三/第二字节分别要 `bm[P+2]`/`bm[P+1]`；而它们要追溯到 **`S_MCHK` 那拍** 的地址（`A(S_MCHK)=P+1`），不是 `R0`。
- `S_MCHK` 的 `praddr` 由它的前驱（`S_MLEN`）决定 → 必须在 `S_MLEN` 加种子 `praddr <= pos + len_r + 1`。同理块首由 `S_WAIT` 提供（r1 已修）。
- 结论：**每次"预取再提前/再加一级"，都要为每个消费点倒推 3 拍，并把种子放到"前驱状态"里**，而不是只改本状态的种子。

## L2. 症状指纹：重定位漏命中 vs 数据错
- `A1_DEBUG` 逐事件（SCAN/MDIST/CP0）比对基准与候选：首个差异若是 `hit2=1 hent_pos=7 hdist=35`（基准）对 `hit2=0 hent_pos=x`（候选）→ **漏命中 + X**，先查 htab 读地址的第二/第三字节，再查 X 源。
- `w=` 窗口字节差一（如基准 `e80818` vs 候选 `e80808`）是"x1_r 落后一拍"的直观指纹。
- 修好后应做到**事件流完全一致**（本包 198/198）再跑大回归，能省 9 min 的 P3。

## L3. 综合闸门证据的解读边界
- TD 的 `gate.timing` 是"每组 10 端点"，**不能**用来证明"全部 ERAM clk2q 起点 ≥ +0.9"；只能证明"报告集合内无该类端点"。
- 本轮 synth WNS 最差 +0.021 起于**锁定的 frame_top**（`grp_in_row_reg[3] → smem_waddr_r_reg[15].d`），与 hit-pipe r0 同路径（当时布线后该路径 +0.020 通过）；核心内下一个是 `p3_r → ext_zero_r` +0.402、`hp_r → thresh_base CE` +0.419。
- `bm ERAM clk2q` 锥在综合报告前 10 中已消失（结构目标达成），但"全局 WNS≥+0.5"这道闸门由 frame_top 的锁定路径决定，不是本包能改的。

## L4. TD 调用坑（本轮两次空跑，均无副作用）
1. `td_commands_prompt.exe` 必须 **cwd=T:**，否则 tcl 里的 `./a1_eng_top.v`、`./a1_small_top.sdc` 解析到别处 → `add_files` 忽略 → `launch_runs syn_1` 失败（`PRJ-8806 ERROR`）。
2. tcl 文件**不能带 UTF-8 BOM**：PowerShell `Set-Content -Encoding utf8` 会写 BOM，TD 报 `invalid command name "锘¿#"`。用 `[IO.File]::WriteAllText(..., New-Object Text.UTF8Encoding($false))`。
3. 从模板复制 run 脚本时，路径替换要兼容 `\\r0`、`\r0`、`/r0` 三种写法（正则 `T10\.a1-bm-prefetch(\\+|/)r0`）；否则 `W:` 与 `$run` 指向不同轮次，verifier 会写出伪 FAIL 并覆盖旧轮 result.json。

## L5. 收尾
- G1 全绿（33 例逐位同 r2）是本次真实成果；综合 1/1 未达 +0.5 → 未布线。
- 工作树保留 `df6124d4`（功能最好的候选）；回退 `r2 0b084317`。预算：约 22 次调用、约 62 min（略超 60 min 合同，已如实记录）；未用 DeepSeek、未派生代理。
