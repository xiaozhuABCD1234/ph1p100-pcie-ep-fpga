# T10.b5-a1-htab-pipe r1-diag -- lessons

只记可复用的根因/触发/修正/验证入口。

## 1. 路由器：空闲心跳是低成本、可自证的在线探针

- 做法：把 `0x55` 换成 35 B 定长包（魔数 + 8×u32 小端 + XOR），只在
  `estate==E_IDLE && dq_cnt==0` 发；包内计数器**先锁存再发**，避免撕裂。
- 结果：61/61 包、`bad_xor=0`、2135 = 61×35，无半包。即使 115200 下单包 3 ms，
  也远小于帧间隔，实测从不插入帧内。
- **可复用判据**：包能持续发出 ⇒ `clk_a1` 活、`a1_rst_n` 已释放（PLL+DDR ready）、
  TX/引脚通。这一条把"FPGA 没配置/复位没释放"整类问题一次性排除。

## 2. 计数器顺序与语义必须写死，否则诊断会被误读

- `cap_frames` 是**完整 ROI 帧**计数（`a1_raw_crop` 收满 NGRP 才 +1），不是行/组计数。
  所以 `cap_frames=0` 既可能是"相机没出流"，也可能是"出流但 tap/in_line/in_frame 语义不对"。
  两种都指向相机前端——但**不能**进一步区分，报告里必须写清。
- `exported` / `errors` 用与 `o_st_*` **完全相同的表达式**（`errors=raw+cmp+exp`），
  否则同一名字两个值，测试者会判失败。

## 3. 参数默认值要落在"冻结顶层不覆盖"的那一层

- 冻结的 `p2_a1_board_top.v` 只覆盖 `UART_DIV`/`HB_DIV`，所以 1 s 周期只能做成
  `camera_a1_uart_top` 的新参数默认值（`STS_DIV=187500000`），再传给 exporter。
- 代价：P1 冻结 TB 也会拿到这个默认值。full_grad 只跑 6.42 M 周期（34 ms）< 1 s，
  所以不影响既有回归；**但凡后续要跑 >1 s 的仿真，必须显式 `STS_DIV=0`**。
- 心跳与状态包互斥用 `hb_en = (HB_DIV>0) && (STS_DIV==0)` 实现，避免两种探针交织。

## 4. 两个生产者共享 `tx_byte_r` 时的最小安全仲裁

- 不需要额外的 mux：只用"包 FSM 之后仍是同一个 always 块的帧 case"这一 Verilog
  优先级，加上两条结构性约束即可：
  1. 包只能在 `estate==E_IDLE && dq_cnt==0 && !desc_push` 启动；
  2. `E_IDLE` 只有 `sstate==S_IDLE` 才允许开帧。
- 结论：帧永远赢；包最多让帧晚 3 ms（35 B @115200），远小于 33 ms 帧间隔，无丢帧风险。

## 5. 诊断候选的工程代价可以忽略

- 新增 ~35 B 状态机后：综合 +0.431（r0 +0.222）、布线 +0.173 / 0 违例（r0 +0.100），
  ERAM 仍 101，`htab→bm_b` 端点仍为 0。最差路径变成 `u_raw_store/st_dup_words` 的
  统计计数器 CE，说明新增逻辑不在关键路径上。
- 所以"为了看见计数器而重建一次 bit"是值得的：1 次综合 + 1 次布线 + 1 bitgen + 1 CWC
  约 18 min，换取把故障域从"整条 A1 链"缩到"相机前端"。

## 6. 板级下载日志里的 `usb_open() failed` 不是失败

- `download -bit ... -mode jtag` 日志出现 `Error @ mpsse.cpp:90 : usb_open() failed`
  之后紧跟 `PRG-2014 : Chip validation success`，命令 Tcl 无错返回。
- 判据应以 **`PRG-2014` + Tcl 返回值**为准；随后 60 s 收到 61 个包，反证下载成功。
  不要因为这一行就重试下载（会浪费唯一额度）。

## 7. 状态包上线后，旧的 `resync_decode.py` 立即失效

- 它只跳过单字节 `0x55`；`A5 5A` 会被当成坏帧头，导致 `frames_found=0` 的假阴性。
- 后续若保留状态包，PC 解码第一步必须是"剥离 35 B 状态包"，再交给帧解码。
  本轮用 `parse_status.py` 取代，且**没有**改 `resync_decode.py`（保持 r4 冻结）。
