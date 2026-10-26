# T10.b13-ddr-retry — lessons（b13b 续跑，2026-10-25）

## 一、本轮新根因（最重要）

1. **64×8 小几何通过 ≠ 重试路径通过**：整链丢 R 在 64×8/32 字时重试成功，但 1920×1080/129,600 字时
   重试**永不启动**。小帧在 abort 前碰巧把编码器最后一个输出字消耗掉，掩盖了孤儿字死锁。
   → 任何"超时中止 + 重试"特性，必须在**生产几何**（至少一次全帧丢 R）上验收后才允许 bitgen。
2. **超时清理必须覆盖读通路的全部下游缓冲**：store 只在 `R_RW` 拉 `rready` 时，
   bridge 的 `skid → rf_pop → paxi_rready → ar_pending → AF → s_arready` 会与 `R_AR` 形成循环等待。
   修法是把"超时后非 `R_RW` 一律消费并丢弃"做成结构约束（store 在 `R_AR/R_GUARD` 常拉 `rready`，
   bridge 在整个 abort/guard 窗口不装载 skid、持续排空 RF），而不是靠 guard 时间余量。
3. **FIFO 的写使能必须用握手，不能用请求电平**：`s_arvalid` 在 `R_AR` 会一直保持到被接受；
   当 `s_arready` 被 guard 门控 37k 拍时，AF 的 `w_valid=s_arvalid` 每拍写入同一地址，
   深度 16 的 AF 被 addr0 副本填满 → 重试读 32 字里前 19 字全是 word0（`dup_words=18`，
   压缩流 374 B ≠ 黄金 666 B）。修法：`af_push = s_arvalid && s_arready`。
   教训：**valid 保持 + ready 延迟 = 必须把 push/pop 改成握手限定**。
4. **帧级 abort 后 A+ 核仍可能吐出一个孤儿输出字**：超时路径先 `cmp_abort` 释放压缩槽（`wr_active=0`），
   之后核的 `svalid` 仍为 1；`a1_out_ready=cmp_wr_ready=0` → `out_valid` 恒 1 → `F_IDLE` 无法重开。
   修法：timeout 后开一个 `orphan_drain` 窗口，让核完成 `out_ready` 握手但 `wr_valid` 被门控（丢弃），
   16 拍尾窗后再 abort 压缩槽。**abort 路径必须自己保证能把上游流水排空，不能假设下游还有消费者。**
5. **验证参数的物理含义要换算**：v5 状态包 241 B × 10 bit × UART_DIV=4 = 9640 clk_a1；
   TB 的 `STS_DIV=10000` 把 UART 占满，帧边界永远被状态包抢走 → 导出饿死（不是 RTL）。
   板上 `STS_DIV=1 s`（241 B @115200 ≈ 21 ms），不存在饱和。小帧在首个状态包前导出会掩盖该问题。

## 二、工具/仿真坑（可复用）

6. **ModelSim `run <N>` 的单位是时间（ns），不是时钟周期**：`run 3050000` 只跑了 3.05 ms（≈57 万拍），
   探针落在读刚开始处，误判成"store 回 IDLE"。全帧超时在 2.7M 拍 ≈ 14.5 ms，应写 `run 16ms`。
7. **端口宽度不匹配会留 z**：`i_dbg_bridge(192'd0)` 接 256 位端口时，高 64 位在 ModelSim 里是 z，
   状态包 #59（`stale_guard`）变成 `z z z z x`，多帧 checker 直接报 `invalid literal 'z'`。
   接 `256'd0` 即修复。**所有新观测字段都要按全宽连接。**
8. **`max_dq` 是全程峰值，不是结束时深度**：正常导出 1 帧必然出现瞬时 dq=1；"队列非空"判据必须
   在结束时采样 `dq_cnt`（新增 `dq_end`），不能拿峰值当终值。
9. **TD Tcl 参数中的 Windows 反斜杠会被 Tcl 吃掉**：`td_commands_prompt.exe <绝对路径>` 报
   `couldn't read file "D:pgaph1p100..."`。把脚本复制到 TD 根目录、用裸文件名 + cwd=T: 执行。
10. **TD 与 ModelSim 对重复线网声明容忍度不同**：`wire x; ... wire x = expr;` TD 静默接受、
    ModelSim 报 `already declared`。多工具链以最严格的仿真器为准，先跑一次 vlog。
11. **TD 被杀进程会留下 run.exe / hwserver**：改名 run 目录前先停 `run.exe`；下载前停 `hwserver`，
    下载后 `connect_cable -close` 再开 COM8。
12. **TD Tcl 不接受 UTF-8 BOM**：PowerShell `Set-Content -Encoding UTF8` 会写 BOM，用 ASCII 或
    `[IO.File]::WriteAllBytes` 去 BOM。
13. **v5 状态包在帧内 tick 会被推迟到帧边界**：TB 若在导出完成后立刻结束，会抓不到状态包；
    必须等至少一个 `status_grants` 并等发送完（241 B × 10 bit × UART_DIV）。
14. **时间余量必须换算到真实时间**：`65536 clk_ddr @200 MHz = 327 µs` 大于
    `32768 clk_a1 @187.5 MHz = 175 µs`。仅比较周期数会得出相反结论；A1 侧 guard 用 70000 clk_a1（373 µs）
    门控 `s_arready`，让重试 AR 停在 `R_AR`（该状态不计超时），等 bridge 窗口真正结束。

## 三、本轮留下的边界/风险

15. **单 outstanding、R 无 tag 的 PAXI 读口**：比 bridge guard（327 µs）更晚的 R 理论上仍可能与后续新 AR
    混叠。四 CRC + 严格 zlib 是最终检出手段，不能宣称绝对排除；result/manifest 已登记。
16. **bitgen 前必须冻结 RTL**：本轮在 64×8 通过后先 bitgen，随后 1080p 丢 R 暴露孤儿字死锁，
    导致 1 次 bitgen/CWC 作废、板级下载的 bit 不是最终 RTL。**顺序应为：全几何仿真（含 drop-R）→
    RTL 冻结 → 综合/布线/bitgen/CWC → 下载**。

## 四、有效验证入口

- 单元：`python run_b13.py store`（clean/retry/guard/budget，秒级）
- 整链：`python run_b13.py chain`（clean/drop1/late1/three_f2/budget，~4 min）
- 全帧丢 R：`python run_b13.py fullchain`（1920×1080，word 60000 丢 R，~10 min）
- 回归：`python run_b13.py regress`（R1/t7/store T3–T6/multi/P1/read/full）
- 探针：`vsim ... -do probe.do`，注意 `run 16ms` 单位与 unpacked 数组的 Tcl 引号
- 板级：`r0/board/run_board_b13.ps1`（先下载后 COM8；`parse_status_v5.py`）
