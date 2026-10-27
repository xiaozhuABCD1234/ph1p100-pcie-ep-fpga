# T10.b1-a1-uart-integ r0 — lessons（可复用根因/触发/修正/验证入口）

1. **行/帧边界计数不能从 0 起**（`a1_raw_crop`）：`line_idx` 从 0 起会把"帧起后第一个 line_rise"当成"上一行结束"校验，每帧首行必误判几何错。修正：帧起置 `16'hFFFF`，首个 line_rise 即 line 0。验证：`st_geom_err==0` 且 `st_raw_pub=1`。
2. **AT-stream 标记不能与数据分离**：`soflast` 与 40-bit 像素同拍寄存时，消费者若把 sof 当纯标记就会丢该拍数据（raw 每帧少 1 组 = 635 B）。修正：sof 拍同时装填数据 skid。验证：`slot_len == W*H*10/8`。
3. **DDR 字容量 ≠ 字节数/32**：MODE0 每 256-bit 字只装 4 组（20 B），回读字数必须 `ceil(len/20)`，否则只读回 62%。验证：`rd_words == GROUPS/4`。
4. **多拍流里 `first` 必须与帧计数绑定**：每个 DDR 字都置 `first` 会让 `in_sof` 每 4 组重复出现，触发 `a1_frame_top` 的 `proto_abort`（现象：`xlen` 恒 0、每 4 组一次 `frame_abort`）。修正：`first <= (grp_sent==0)`。验证：探针中除首组外全部 `sof=0`。
5. **abort 与 sof 同拍的优先级**：FIFO 标记同拍出现时必须 abort 优先，否则 begin 会吞掉 abort，slot 永久停在 WRITE（现象：`wr_active=1` 永不释放、`cmp_begin_ready=0` 死锁）。
6. **探针比日志更快**：用 `vsim -do "do probe.do"` + `examine` 在固定时间点取 10–20 个内部信号，30 s 内定位到 4 个功能 bug；`$display` 追踪只在状态机每拍事件上开（`+TRACE`）。
7. **ModelSim 命令行**：`-do` 里的路径必须用 `/`，反斜杠会被 Tcl 当转义（报 `Cannot open macro file`）；`Start-Process -ArgumentList` 传 `-do "..."` 必须整段带引号。
8. **统计必须独立文件句柄**：TB 只开一个 fd 写字节流时，`STAT` 行会写进字节文件而 `.stats` 永远不存在，会让 verify 误报"无统计"。
9. 小几何（64×8）只适合故障注入，A+ 每块仅 128 B，块启动开销使吞吐降到 ~22 c/B，**不能**用它的耗时推断 1080p；吞吐结论必须用 4800 B 块基准（2.31 c/B）。
