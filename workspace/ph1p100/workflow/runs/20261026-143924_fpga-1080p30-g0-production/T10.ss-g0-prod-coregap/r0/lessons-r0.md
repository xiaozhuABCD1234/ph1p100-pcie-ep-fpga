# lessons — T10.ss-g0-prod-coregap r0

只记可复用的根因/触发/修正/验证入口。

## L1 TB 的「stats 打印在最后」与 `MAX_CYCLES` 收尾冲突（N#1 白跑 695 s）

- 触发：`FRAMES=1` 时，TB 继承的 `while ((st_read < 2*129600) && (cycles < MAX_CYCLES))` 永不满足，
  仿真必跑到 `MAX_CYCLES` 再由 `if (cycles > MAX_CYCLES) → B11_FULL_TIMEOUT; $finish` 收尾；
  而 `SS_STATS`/任何放在它之后的 `CORE_STAGE` 都在这之后才执行 → **永远打印不出来**。
- 后果：日志里只有 `SS_EVT`（t_pub/t_enc/exp），9 个 core counter 一个都没有 → 该次运行不算探针证据。
- 修正：把只读 dump 挂**在事件上**（`st_enc==1` 后 8 拍），不要挂在 stats 之后；`MAX_CYCLES` 只用来限制跑飞。
- 验证入口：日志必须同时出现 `CORE_STAGE ... t_enc1=<非 -1>` 与 `kind=enc frame=1`；否则直接判无效。

## L2 单帧探针的 `t_enc(1)-t_pub(1)` 与 4 帧 run 的帧 1 **逐位相同**

- 实测：N 7,476,245、L 6,979,811，与 P1 r1 帧 1 差 0.000%（两次独立编译/运行）。
- 复用：以后需要核级锚点时，1 帧探针（约 610–790 s）可信，不必重跑 4 帧（约 1,800–1,960 s）。

## L3 把链级 `S_ss` 当核级锚点是类别错误（C1）

- C1 的 P4 `S_ss=4,677,970` 被 dev-plan 列为第 4 个校准点，但模型给出的 C1 核级上界只有 1.44M–1.58M 拍（33.7%），
  因此该数由采集/喂入支配，不能拟合核级系数。判据入口：先算 `B + r·S(+k·块)` 的下界，若远小于锚点 → 该锚点是链级。
- 反例价值：把 C1 硬塞进拟合会推出 `k≈2,861 拍/块`，与 N/comp 的 294 冲突 → 自证类别错误。

## L4 两参数（replay+块）在两份内容上不可辨识，必须加 abort 抵扣

- `{N,L}` 无约束解给出 `k = −2418 拍/块`（非物理）。根因：stored 块由 `cand_abort` 提前结束扫描，
  内容越平坦 abort 越多（L 210 vs N 83），模型少算了「少扫的拍数」。
- 修正：三参数 `(r, k, c_ab)`，三点闭合；验证改用 leave-one-out（2 参数折 + `k≥0` 约束折），三折 ≤5%。

## L5 b11 的 hash 表是**块作用域**（`blk_tag` 比较），所以 htab/窗口参数基本无效

- 离线 matcher：hbits 10→12/13 无变化；`MAX_DIST` 2048→4800 只改 0.2–0.5% 的 literals。
- 含义：想用「更多候选/更大窗口」必须同时改块作用域与单候选结构，那是换核级别的工作，不是参数级。

## L6 该核每块天然两遍（扫描 + emit/stored），单靠参数改动无法跨过 2.4 cycles/B

- 实测 N：扫描 61.3% + emit 32.5% + stored 5.3% + 每块 2.1%（−abort 1.2%）。
  两块结构性开销都在同一量级，故「只调 htab/窗口/时钟」不可能闭合；能闭合的是**同时**压扫描拍与 emit 拍（A+H）。

## L7 环境

- ModelSim ASE 10.5b：`Start-Process -ArgumentList` 单字符串时 `-do "run -all; quit -f"` 必须自己带引号，
  否则 vsim 把 `run` 当文件名（`vsim-4004 The -f option requires an argument`），0.2 s 退出且无日志；
  用 `& vsim ... -do "run -all; quit -f"`（数组参数）最稳。
- 后台长跑用 `Start-Process -PassThru` + `WaitForExit(1500000)` 才能落实「硬超时」；`-l` 日志有缓冲，判断进度看进程 CPU 时间而非日志尾。
