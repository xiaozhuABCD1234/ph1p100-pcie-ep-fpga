# 收帧写者卡死：静态分析结论（子智能体，2026-10-27）

本轮请了一个子智能体做纯静态分析，结论与我板测数据高度吻合，记录在此作为下一轮的施工图。

## 结论：授权粒度是「一整帧」，不是「一整突发」

- `cam_r10f_writer.v` 的 `axi_busy = (a_st != A_IDLE)` 覆盖整帧：
  一帧从 SOF 进 `A_AW`，之后 `A_B` **在同一拍**就 `m_axi_awvalid <= 1'b1; a_st <= A_AW` 续发下一笔，
  突发之间没有空档，只有整帧收尾 `A_RW3` 才回 `A_IDLE`。
- `ddr_wr_arb.v` 的换手条件只有「当前被授权者 busy=0」⇒ 端口按整帧独占。
  仲裁器头注释里「每客户机约 96% 空闲」的前提（busy 只覆盖一个 4KB 突发）在 R10F 写者上不成立。
- 输的那片：卡在 `A_AW` 等 `awready`（未授权时恒 0）⇒ `beat_taken=0` ⇒ `data_ready=0` ⇒ `pop=0`
  ⇒ FIFO 灌满 1023 ⇒ `tmo` 数到 `21'h1F_FFFF`（≈21ms @100MHz，注释写 10ms 是错的）⇒ 强制收口
  ⇒ 补零 ⇒ `verdict_bad` ⇒ `pub_ok=0` ⇒ `wr_frame_seq` 不自增 ⇒ **SEQ 冻结、valid=0/busy=1/err=1**。
  与板测逐位吻合。
- 谁先抢到 `sel` 谁吃满整帧，所以「重新 arm 一次」会换人卡 —— 也与板测一致。

## 修法（尚未落地验证）

核心两条，缺一不可：**（a）数据攒够才拉 awvalid；（b）等数据期间回 A_IDLE（busy=0）让出端口**。

1. 加 `gray2bin()`，用 `wgray_s2`/`rptr_bin` 算 FIFO 占用；
2. `burst_ok = (occ >= 828) || (fifo_bytes >= pay_left) || ((s_state != S_PAY) && (s_state != S_HDR))`；
3. 新增 `mid_frame` 寄存器：`A_B` 非末突发改成 `awvalid<=0; mid_frame<=1; a_st<=A_IDLE`，
   `st_frame_go` 也只置 `mid_frame` 不再立刻发 AW；
4. `A_IDLE` 顶部加放行分支：`mid_frame && burst_ok` 才 `awvalid<=1; a_st<=A_AW`。

为什么安全：换手口收缩到 `A_IDLE` 那一拍，此时 `awvalid/wvalid/bready` 全 0，三通道没有在途握手；
突发进行中 busy=1，sel 被冻结，128 拍仍原子。端口占用降到 633 × 1.32us ≈ 0.84ms/帧 ≈ 1.3%。

## 本轮试过但**失败**的版本（不要再走）

按上面 1~4 实现后上板：两路都变成 0 帧，`verdict=0x7`、两路诊断字完全相同
（`beats=81024` 整帧补零、`wcnt=14727`）。说明放行门槛或 `fifo_occ` 的口径不对，
真数据只出去了约 30 行就被超时收口。下次必须先单路验证（另一路 arm 掉）：
先确认「单路 + 突发门槛」能跑满整帧，再开第二路测并发。

排查提示：`beat_vld` 在无突发在飞时会一直保持 1（`data_ready=0`），
所以「等 FIFO 攒够」期间源侧不会 pop；要核对 `fifo_occ` 是否真的能涨到 828，
以及第（4）步放行后是否只发了一笔就再没触发。
