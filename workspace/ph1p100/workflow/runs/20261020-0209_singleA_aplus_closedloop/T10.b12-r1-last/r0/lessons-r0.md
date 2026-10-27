# T10.b12-r1-last r0 — lessons

## 可复用根因/触发/修正

1. **“只计数不动作”的丢失路径**：CDC FIFO 拒收如果只 `ovf_cnt++`，丢的若是 LAST，下游 store 就永远等不到 `wr_last`。
   `camera_a1_uart_top.v` 里 b10 留下的 `// T10.b10 R1:` 注释描述的是**已回退**的实现，不要按注释判断能力；
   判断“有没有修”必须看 `if/else` 分支本体，并用反例 TB 复现。
   修正：任一 `fifo_wvalid && !fifo_wready`（SOF/中间/LAST 任一拍）→ `abort_hold<=1`，sticky 到 abort beat 被 FIFO 接收。

2. **abort beat 的 head-of-line 死锁**：abort 请求是排在队尾的独立 beat，若队头是“无主数据 beat”而 `fifo_ready` 为 0，
   abort 永远推不进去，前面的修复等于没做。`fifo_ready` 必须为 `!raw_active && !skip_frame && !e_sof` 的数据 beat 提供消费路径。
   这一条用“只改 clk_cam”的中间版本无法发现（T2 仍会 fail），必须两层一起改。

3. **store 的 abort 必须压倒同拍写**：`accept` 含 `wr_abort` 时，同拍 `wr_last+wr_abort` 仍会 flush 并发布坏帧。
   `accept = wr_active && ddr_ready && wr_valid && !wr_abort` 同时门控 `wr_ready`（不消费该拍）与 `ddr_wvalid`（不写 DDR）。

4. **abort+begin 同拍**：`wr_begin_ready = ... && (!wr_active || abort_now)`。若要求 `!wr_active`，abort 同拍到达的新 SOF 会被整帧丢弃，
   表现为“修好后仍要再等一帧”。同拍分支里必须**两个不同槽**各写一次 `slot_st`（旧槽 FREE、新槽 WRITE），并清零 wcnt/pack_r/nbytes/waddr。

5. **计数器口径**：`fifo_ovf_cnt` 只统计 `crop_valid && !fifo_wready`，否则 abort beat 在满 FIFO 上的重试会把“数据丢失”放大。
   TB 侧独立从 `u_cam_fifo.w_valid/!w_ready` 计数，因此 RTL 口径变化不影响判据（本包 T2 仍为 7）。

## 验证方法

6. **同拍用例的采样陷阱**：在 `negedge` 驱动 `wr_begin/wr_abort` 后立即读组合 `wr_begin_ready` 会读到旧值（delta 未更新）。
   驱动后加 `#1;` 再采样，否则得到假失败（本包 T4 首轮即此原因，DUT 行为原本正确）。

7. **冻结检查器的种子表**：独立 `check_r1.py` 的 `packets()` 只识别 `[11,100,1000,1001]`。
   新几何/新种子的用例（T7 的 seed 300）必须带自己的种子表，不能直接复用，否则报 “RAW source CRC mismatch” 掩盖真实结果。

8. **旧 TB 与新端口的 4 态**：b10 三帧 TB 早于 v4，未接 `i_dbg_bridge` → v4 扩展字段是 `z`，解析器直接 `int('z')` 崩。
   在 TB 副本里把该**纯观测输入**接 0（并注明仅消除 4 态）后，22 个 v4 包全部可校验；帧字节 sha256 与 b10 黄金三帧完全相同（`7ffbaf09/e346461c/6393a9f4`）。

## 流程/陷阱

9. **本包 r0 目录里已有上一轮尝试的产物**（result/lessons/patch、`sim/run-*`、`td/a1_board_Runs` 等，时间 15:36–16:12）。
   新开发必须先按时间戳识别并**移入 `prior-attempt/`**（移动不删除），再写自己的证据；否则 `create_project -force` 会覆盖或复用旧 run 目录，
   旧 `result-r0.md` 的 `@@TD@@` 占位也会被误当作本轮结论。旧产物未经本轮复跑，不作为证据。

10. **TD 构建机的 `T:` 映射**必须先 `tools/td/td_env.ps1 -TdDir ... -Force`；`td_commands_prompt.exe 01_build.tcl` 无 `-tcl` 开关。
    `01_build.tcl` 里的 9 条 `add_files` 是绝对 `Y:` 路径，拷包时必须和 `a1_board.al` 的 `<File Path>` 一起重定向（只改路径，不改参数）。

11. **ModelSim 参数里的 Windows 反斜杠**：`-modelsimini C:\...` 会被当成转义/非法参数（vsim-7），必须传正斜杠；`vlog` 同样。
    `-voptargs=+acc` 不能省，所有 TB 都层次化引用 `dut.*` 内部信号。

12. **并行跑仿真**：每个 group 用独立 work 库 + 独立 modelsim.ini；结果写 `sim-results-b12-<group>.json`，
    不要多个进程共写一个 JSON（读-改-写会互相覆盖）。
