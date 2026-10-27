# T10.b11-aplus-read — lessons (r0, diagnosis_only)

只记可复用的根因/触发/验证入口。

## 1. “AR 握手数 ≠ DDR 收 AR 数”是这块板读停的正确定位入口

- `a1_ddr_slot_store.ddr_arready` 来自 **地址 FIFO 写侧**（`p2_ddr_bridge.s_arready = af_wready`），
  所以 v3 的 `raw_ar_hs=1177` 只证明“地址进了 AF FIFO”，**不能**证明第 1177 个 AR 打到过 PAXI。
  必须把“进 FIFO(store 侧) / 出 FIFO(PAXI 侧) / 回 R / 被吞(stale)”四个计数分开看（v4 #37/#45/#47/#49）。
- 复用入口：`r0/board/parse_status_v4.py` 的判别链 + 退出码（0 平衡 / 3 AR 卡 AF / 4 DDR 不回 R / 5 不确定）。

## 2. 该读通路在 RTL 上不会“吞掉真 R”（可直接排除 H1/H3）

- `p2_ddr_bridge`：`af_pop = paxi_arvalid && paxi_arready` 与 `paxi_rvalid && paxi_rready` 因
  `paxi_arvalid` 含 `!ar_pending` 而**互斥**，AR/R 严格 1:1；没有在途 AR 时来的 R 只进 `stale_r_cnt`。
- `a1_ddr_arb2`：`rd_busy` 置位含 `!rd_busy`、清零经 `s_rready = rd_busy ? m_rready : 0` 门控，**同拍不可能覆盖**。
- `capture_async_fifo`：`r_ready` 只能随 `r_valid` 拉高（`af_pop` 含 `af_rvalid`、`rf_pop=s_load` 含 `rf_rvalid`），
  所以“预取到空 FIFO 幽灵项”不会发生；`fetch=1 ⇒ mem[rbin]` 一定已写。
- 验证入口（可重复）：`r0/sim/tb_b11_read.sv` + `run_b11.py read_*`，特别是 `read_full`：
  真双时钟 CDC + 真 arbiter/store，129600 字逐拍比对 **bad=0**。

## 3. 台架要覆盖的三类“假丢拍”，否则会把模型缺陷当成 DUT 缺陷

- 我第一版 PAXI 模型在注入“多余 R”后把 `start_rd` 也一起关掉，于是 dup 用例在 4096 字停住，
  看起来像 DUT 死锁——实际是模型不再应答后续 AR。**结论：故障注入器本身必须有“注入后继续正常服务”的自检**
  （本例改成只注入一次、后续 AR 继续 1:1 应答后，dup 用例 9000 字全对、只多一个 `stale_r_cnt`）。
- 无主 R（`+STRAY_R`）在真 RTL 上只会被吞，不会位移数据；这是可以放心保留的“H1 负对照”。
- 判“停点”必须同时看 `store 收到数` 与 `模型发出数`，只看 store 侧会把“模型停发”误判成“DUT 丢拍”。

## 4. 状态包扩字段时的两个坑

- `cam_diag_mailbox`（stable-hold + toggle）是唯一可用的 clk_ddr→clk_a1 多比特通道；
  直接把 clk_ddr 计数器打进 clk_a1 快照会得到撕裂值（dev-plan 已明确禁止）。
- dev-plan 的 #52 位图把 3 bit 的 `eidx` 塞进 2 bit（[11:10]），实际必须整体上移一位；
  **扩包时先核对每个字段所需的位宽再冻结 parser**，否则 parser 与 RTL 各写一套。

## 5. TD 复用的两个具体点

- 新包构建 = 复制上一包 `td/`（含 `src/` 树、`01/02/03 tcl`、`a1_board.al`），
  把 `a1_board.al` 与 `01_build.tcl` 里的 `T10.b1x-.../r0` 前缀整体替换成本包前缀，
  再把 `a1_frame_top.v` 从 `Y:/upstream/...` 指到本包 `changed-src/`（upstream 只读），
  并把改过的 `p2_a1_board_top.v`/`p2_ddr_bridge.v` 覆盖进 `td/src/`（`.al` 用相对 `src/` 路径）。
- 构建入口：`td_commands_prompt.exe 01_build.tcl`（把脚本名当第一个参数，**没有** `-tcl` 开关）。
  先跑 `tools/td/td_env.ps1 -TdDir <r0/td> -Force` 建好 `T:/Y:`。

## 6. 有界看门狗放在 feeder 还不够

- 读停时 `raw_rd_state=R_RW`，store 的 `rd_close` 只在 `R_HOLD` 生效，所以 feeder 超时 abort 只能
  “让 feeder 不再永久挂住 + 计数”，**释放不了卡在 R_RW 的 raw 槽**（后续帧仍会被 `raw_begin_ready=0` 拒）。
  要真正自愈必须让 store 能中止读（`R_RW/R_AR` 超时 → 计数 + 回 `R_IDLE` + 释放槽），
  这属于 reader 语义变更，本轮 W1 未证明 reader 有责，故**未做**，记入后续候选。

## 7. 预算/流程事实

- 本轮实际约 165 min（超 150 min 预算约 10%）、63 次工具调用（预算 70）；TD 会话 2 次（构建、bitgen+CWC）、
  综合 1 次、布线 1 次、bitgen 1 次、CWC 1 次、下载 0 次。
- 超时主因：TD 布线段 place 10.8 min + 时序报告，与两轮全尺寸真核仿真（P1 full_grad 354 s、
  集成两帧 599 s）串行重叠不足。下次应把 TD 构建与长仿真相交启动（本机 32 逻辑核，实测无资源冲突）。
- 板级在预算内未完成：JTAG 设备未枚举（`mpsse.cpp:90 device not found`），属缺设备，按规则直接 blocked，不空转。
