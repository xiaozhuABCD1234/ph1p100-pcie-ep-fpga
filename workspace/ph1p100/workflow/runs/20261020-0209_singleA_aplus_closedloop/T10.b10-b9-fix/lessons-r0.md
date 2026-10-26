# T10.b10-b9-fix r0 -- lessons

只记可复用的根因、触发条件、修正点与验证入口。行号对应本包 `r0/` 副本。

## B9-01 状态包与帧出队互锁（已离线复现，已修）

- **根因**：状态启动条件含 `dq_cnt == 0`，帧出队条件含 `!sts_want`，两者互为对方的前置条件。
  只要“状态到期 + 帧已排队”，两者都不前进；后续 tick 只重复置位 `sts_want`，不能解锁。
- **触发**：第一帧发送期间第二个描述符入队，且 `STS_DIV` 在帧内到期。与业务速率无关，
  与“帧长 ≫ 状态周期”或“状态周期 ≪ 包时长”无关。
- **修正**（`a1_uart_export.v`）：
  - `status_due = sts_tick || sts_want` 单点计算；`frame_boundary = (estate==E_IDLE) && (sstate==S_IDLE) && tx_ready && !tx_valid_r`；
  - `grant_status = frame_boundary && status_due`，`grant_frame = frame_boundary && !status_due && dq_cnt!=0`，天然互斥；
  - 删除状态启动的 `dq_cnt==0`、删除出队的 `!sts_want`；
  - `sts_want` 单点赋值：`grant_status` 消费，否则 tick 置位（解决 tick 当拍旧值/双启动）；
  - 帧边界要求上一帧最后一个 UART 字节已完全发完（`tx_ready && !tx_valid_r`）。
- **验证入口**：`r0/sim/tb_b10_arb.sv`（同一 TB 编译进 `work` 与 `work_b9` 两个库）：
  `+EXP=old` 必须 `old_repro=1`，`+EXP=new` 必须 `new_pass=1`；状态包只出现在帧间，
  `sts_div` 扫描 3500..8000 全部 `new_pass=1`。
- **坑**：当 `STS_DIV` 小于一个状态包在线时长（177 B × 10 bit ≈ 1770 clk）时，tick 会持续
  在发包期间到期，`sts_want` 粘滞会让状态包连续占用帧间机会、业务帧长期得不到边界。
  板上配置 `STS_DIV=187,500,000`（1 s @187.5 MHz）远大于包时长，不触发；调参时须保持
  `STS_DIV > 177*10` 并留业务边界余量。

## B9-02 描述符队列越界与计数覆盖（源码确认，已修）

- **根因**：`dq[0:1]` 配 2-bit 指针，第 3 次 push 取 `dq[2]`、pop 取 `dq[3]`（数组外）；
  同拍 push/pop 在同一个 always 里对 `dq_cnt` 两次非阻塞赋值，后者覆盖前者。
- **修正**：1-bit 环绕指针；`dq_cnt` 只在 `case ({dq_push_ok, dq_pop_ok})` 一处更新；
  满队列同拍 pop 允许 push（保持 2），否则 `dq_reject_cnt++`（仅 TB/CWC 可观测，不进状态包）。
- **验证入口**：`tb_b10_export.sv` 的 `wrap`（14 个描述符、≥3 次环绕，逐帧头/载荷比对）/
  `samecycle`（满队列边界同拍 push+pop，`samecycle_cnt>0`）/`reject`（满且无 pop 必须拒收 1 次）/
  `empty`；模块内 `b10_assert_fails` 逐拍核对影子计数。
- **坑**：TB 若在满队列边界“假定 push 一定被接受”，一旦该拍被状态包抢走边界，
  期望序列会整体错位（表现为 frame_id 偏 1）。正确做法是只在 `dq_push_ok` 时推进期望。

## B9-03 1080p 四槽地址重叠（源码+容量核对，已修）

- 旧 `CMP_BASE=131072`：CMP0=131072..212156、CMP1=212157..293241 落在 RAW1=129600..259199 内。
- 新 `CMP_BASE=262144`：RAW0 0..129599、RAW1 129600..259199、CMP0 262144..343228、CMP1 343229..424313。
- **容量来源**（必须记录，不许抄旧值）：`td/src/vendor/ip/ddrmc_x32/ddrmc_x32.v` +
  `.params_ddrmc_x32.txt`：DDR3-1600 x32、ROW_WIDTH=14、COL_WIDTH=10、BA_WIDTH=3、CS=1
  → 2^14·2^10·2^3·32 bit = 4 Gbit = 512 MiB = 2^24 个 256-bit word；`AXI_ADDR_WIDTH=29`
  字节地址与之一致；PAXI 端口 27 bit（`MC_ADDR_WIDTH=27`）。要求 ≤424,314 word，余量 39×。
  RAW `AWB=18`（262,144 ≥129,600）、CMP `AWB=17`（131,072 ≥81,085）均满足。
- **验证入口**：`tb_b10_layout.sv` 满尺寸双 store 并发：RAW 两槽各 129,600 word、CMP 两槽各
  10,136 个 DDR word（81,085×4 B），全部读回逐字比对；地址监视器对每个 master 的读写地址
  做区间断言，并专门检测 CMP 地址落入 RAW 区间。
- **坑**：`a1_ddr_model.v` 用 `mem[awaddr[23:0]]`，只能覆盖 2^24 word；CMP_BASE=131072+
  2*81,085=293,241 仍在其内，所以旧布局在旧模型里“看起来能跑”，必须用区间断言而不是
  靠越界错误来发现重叠。

## R1 丢 LAST → 孤儿 writer（新发现，已修）

- **根因 1**：CDC FIFO 写满时丢 beat 只累加 `fifo_ovf_cnt`，不产生 abort；被丢的若是一帧
  的 LAST，store 永远停在 WRITING，后续 SOF 全部被拒（孤儿 writer）。
- **根因 2**（更深）：`fifo_ready` 对“无主的普通数据 beat”（`raw_active=0`、非 SOF、非 abort）
  保持 0，FIFO 头 beat 永远出不去 → 后面排队的 abort beat 也永远推不进去 → 硬死锁。
- **根因 3**：`raw_active` 在 LAST 只是“进入 skid”时就清零，store 还没真正收下 LAST，
  下一帧 SOF 就会被 store 的 `wr_active` 拒掉。
- **修正**：丢 beat 时置位既有 `abort_hold`（复用 abort beat 通道，FIFO 有空位即入队）；
  无主数据 beat 直接消费丢弃；`raw_active` 改为 LAST 被 store 真正接收（`skid_take && skid_last`）
  时释放。
- **验证状态**：修正已实现；store 级 abort 用例仍通过。**顶层定向“活跃帧丢 LAST”用例未能在
  本轮预算内构造成功**（小几何下自建相机驱动只产出部分 ROI 行，首拍不带 SOF），如实记为
  not_covered，风险与复现线索见 result-r0.md。
- **坑**：用“相机时钟远快于 clk_a1”去压 FIFO 会破坏 `capture_async_fifo` 的格雷指针同步
  前提（写指针每个读时钟最多前进 1），得到的是 CDC 损坏而不是可解释的溢出，不能作为证据。

## R2 bridge 单字被写两次（已修）

- **根因**：`wf_pop` 是寄存器输出，pop 后 `wf_rvalid` 还要一个周期才掉；`W_IDLE` 在同一拍
  用旧 `wf_rvalid` 重启 `W_RUN`，把同一个 FIFO 字再发一次 AW/W。
- **修正**：`W_IDLE` 启动条件加 `!wf_pop`。外部 `paxi_awvalid`/`paxi_wvalid` 各恰一次。
- **坑**：bridge 的 `s_awready = wf_wready && s_wvalid` 是同拍组合接受；TB 若把 `s_awvalid`
  拉高两个周期，会真的写入两次（不是 bug）。单字用例必须只拉高一拍。

## R3 复位后旧 R（部分覆盖）

- 修正：`paxi_rready = ar_pending ? rf_wready : 1'b1`，`rf_push = paxi_rvalid && ar_pending`——
  没有未完成 AR 时的 R 被吞掉，绝不进 RF FIFO。用例（AR 挂起→业务复位→释放旧 R→新 AR/R）
  通过：`stale_seen=0`、`new_seen>0`。
- **未覆盖**：旧 R 晚于“新 AR 已发出”才到达时，bridge 无法区分它与新 R（无 tag/无跨复位计数），
  仍可能把旧数据当新结果。要彻底解决需在 store/桥加读事务 ID 或复位后强制排空协议，超出本轮
  最小修复范围，记为残余风险。

## 工程/流程

- TD 的综合器**不支持**从顶层做层次化引用（`external connection to net ... is not allowed`），
  因此 CWC 探针只能落在已有 `MARK_DEBUG` 计数器上，`estate/sstate/sts_want/dq_cnt` 记为
  `cwc_hier_not_available`；不要为了探针改顶层端口。
- 板级顺序必须“先下载、后开 COM8”：b9 的静默窗口源于监听器先占用 FTDI，JTAG `usb_open` 失败。
