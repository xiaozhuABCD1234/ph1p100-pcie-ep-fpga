# T10.b13-ddr-retry — handoff（规划 → 开发 / 综合测试者）

- 日期：2026-10-25；run：`20261020-0209_singleA_aplus_closedloop`；项目根：`D:/fpga/ph1p100`
- 状态：**ready**；`needs_user_input=false`；批大小 1；父 T10 **保持 blocked**
- 唯一目标：DDR 丢 R 时，A1 读通路 **8192 clk_a1 超时 → 清读通路 → 保护窗口 → 重试同一帧 → 完整导出**；不发布半帧、不覆盖已发布槽、不把晚到 R 当新事务；状态包 v5 增加 timeout/retry/giveup/stale
- 源基线：`T10.b12-r1-last/r0/changed-src`（9 文件，哈希见 dev-plan §0.2）
- 板级事实（用户已裁决 H4）：b12 r1 4,470 帧正常；store AR=883、PAXI AR=883、R=882、stale=0、`ar_pending=1`、`af_rvalid=0`、`ddr_rdy=1`、`rd_wait` 饱和、`raw_rd_idx=882/129600`、`slot0=READING`、`slot1=READY`；停点 1176→882 不固定
- 证据：`T10.b12-r1-last/r1/board/captures2/status_v4.txt`（原始 `com8_150s.bin`，150 包，bad_xor=0）

## 1. 必须按顺序读

1. `T10.b13-ddr-retry/dev-plan.md`（冻结计划、§3 规格、§4 T1–T13、§6 时序预裁决）
2. `T10.b13-ddr-retry/fpga-design-guide.md`（常量、FSM、v5 包、构建/板级入口）
3. `T10.b13-ddr-retry/dispatch.json`
4. `T10.b12-r1-last/r1/board/captures2/status_v4.txt`（H4 原始证据）
5. `T10.b12-r1-last/r0/{changed-src/,sim/,td/}`（源码/仿真/构建基线）
6. `T10.b12-r1-last/{CANDIDATE-MANIFEST-b12-r1-last-r0.json,CANDIDATE-MANIFEST-b12-r1-last-r1.json}`
7. `T10.b11-aplus-read/r0/sim/**`（read 九例与 v4 TB 基础）
8. `work/b10-gap-sim-20261025-132023/{README.md,r1-loss/result.md,r1-loss/check_r1.py}`（b12 R1 回归，只读）

## 2. 规划已确认、不要重复推翻

- b12 r1 板级是 **H4**：DDR 接受 AR 后不回 R；A1 侧 883/883/882、stale=0，不是 A1 丢响应。
- 停点不固定（1176→882）→ 偶发丢响应，优先按 DDR 刷新/读写仲裁处理；**重试是恢复手段，不是 DDR 根因修复**。
- 超时必须在 **AR 已接受后**（`rd_armed=1`，`R_RW`）计时；8192 clk_a1。`R_AR` 等不到 `arready` 不属本包。
- 超时后**槽保持 READING**（不 FREE、不 READY、不发布），重试**同一帧**，最多 2 次；第 3 次失败才 FREE 并 `giveup++`。
- bridge purge **不能拉低全局 `rst_n`**（会丢 WF 写 FIFO 的写请求）；只清 `ar_pending`、排空 AF、丢弃 RF/skid。
- bridge guard 65536 clk_ddr（≈327 µs）≥ store guard 32768 clk_a1（≈175 µs），保证重试前 bridge 不发新 AR；晚到 R 在 `ar_pending=0` 时只吞掉并计数。
- 重试走正常 `rd_open` 路径（`R_GUARD` 接受），top 会 `a1_abort`/`cmp_abort` 并回 `F_IDLE`；无 `a1_commit` 就无描述符，因此不会导出半帧。
- 只 `u_raw_store` 用 `RETRY_EN=1`；`u_cmp_store` 用 `RETRY_EN=0`，行为与 b12 一致。

## 3. 执行顺序（严格）

1. **W1 复现（≤20 min）**：在 b12 r0 冻结源上注入“丢 1 个 R”，复现 `R_RW` 永久等待；落 `r0/diag/ddr-drop-repro.md`；冻结 §2 常量。
2. **W2 RTL（≤35 min）**：只改 6 个允许文件；先复制到 `r0/changed-src/`；`a1_ddr_arb2.v` 加入 changed-src 和 `.al`。其余 4 个源逐字节不变。
3. **W3 仿真（≤30 min）**：T1–T13；P1 三黄金逐字节；b12 R1 全回归；b11 read 九例；full 两帧 + full 丢 R；v5 241 B。
4. **W4 构建**：复制 b12 td 脚本/ADC/SDC/src；综合≤3、布线≤2；`a1_board.al` 只改 `<File Path>`；1 bitgen + 1 CWC；Routed 0 违例；WNS 按 §6（目标 ≥+0.05；0 违例且 +0.003..+0.05 接受为诊断候选并记 caveat；<+0.003 或违例即停）。
5. **W5 板级**：FTDI 预检；不在位 → `board=blocked`/0 下载/0 COM8；在位 → **先下载 1 次 SRAM**，确认 `B13_DL_OK`，释放 FTDI，**再开 COM8** 150 s；v5 ≥120 包、`enc_frames/exported` 增量>0、≥1 帧四 CRC+zlib、无半帧；记录 timeout/retry/giveup/stale。

## 4. 硬约束

- 只写 `run/T10.b13-ddr-retry/**`；源先复制到 `r0/changed-src/`；`work/b10-gap-sim-20261025-132023/**` 只读。
- 不改 A+ 核/压缩核心/crop/camera 前端、44 B 帧头/CRC、压缩字节、UART_DIV/HB_DIV、引脚/SDC/时钟、DDR 四槽布局、DDR IP/PAXI 协议。
- 不改 upstream、旧 run/证据/manifest、`workflow/tasks.json`；不 false path/multicycle/改 seed/降频/新增 ERAM。
- 不写 Flash、不 PCIe/RK、不做双路/G4；SRAM 下载 ≤1；不批量删除。
- 预算：开发 **120 min / 60 calls**；TD **3 会话**、综合≤3、布线≤2、bitgen 1、CWC 1、下载 1、Flash 0；综合测试 45 min/30 calls。

## 5. 条件分支

- T2/T3 重试后仍不导出，或 T4/T5/T6 出现半帧/槽泄漏/两个 WRITE/晚到 R 污染 → **停止**，不 bitgen、不下载，交规划。
- 需要第二个 bitstream，或修复需要改 DDR IP/PAXI/A+ 核/frame 格式/SDC → **停止交规划**，不自行扩预算。
- 布线 WNS <+0.003 或任何违例 → **停止**，不 bitgen、不下载。
- FTDI 不在位 → `board=blocked` 是合法完成，不是 FAIL；写清 `FTDI_0403:6042_absent`、0 下载。
- 板级 exported=0 且 ≥3 帧同一 `rd_idx` 超时 → **停止转 B（DDR IP 调查）**；不第二次下载/第二个 bitstream；把 v5 #44–#59 与 H4 证据一并交规划。

## 6. 综合测试（冻结后）

- 开发冻结唯一 manifest 后，派 **1 个新综合测试者**做 round0 integrated 验收：哈希绑定、T2/T3 丢 R 与晚到 R 重跑、P1 三黄金、v5 241 B、b12 R1/b11 read 回归、Routed/时序/资源、板级抓包复算。
- 报告：`test-reports/T10.b13-ddr-retry-r0-integrated.md`；功能/工程/系统是同一测试者的检查清单，不拆成三个代理。
- 板级 PASS 需要真实证据；若 `board=blocked`，只能判工程/仿真 PASS，硬件结论保持未测。

## 7. 恢复文本

> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 **`T10.b13-ddr-retry` r0**（ready；1 bitgen+1 CWC；SRAM 下载 ≤1；先下载后开 COM8）。
> 先读 `T10.b13-ddr-retry/{dev-plan.md,fpga-design-guide.md,handoff.md,dispatch.json}`、
> `T10.b12-r1-last/r1/board/captures2/status_v4.txt`、`T10.b12-r1-last/r0/{changed-src/,sim/,td/}`、
> `T10.b11-aplus-read/r0/sim/`。
> 事实：b12 r1 板级 4,470 帧正常；store AR=883、PAXI AR=883、R=882、stale=0、`ar_pending=1`、`rd_wait` 饱和、
> `slot0=READING`、`slot1=READY`、`raw_rd_idx=882/129600` → H4；停点 1176→882 不固定。
> 目标：读等待 >8192 clk_a1 → abort 当前帧读、清 ar_pending/AF/RF、保护窗口 32768 clk_a1 禁新 AR、
> 晚到 R 当 stale → 重试同一帧（最多 2 次）→ 完整导出；不发布半帧、不覆盖已发布槽、不把晚到 R 当新事务；
> v5 追加 timeout/retry/giveup/stale 四字段（241 B/59 字段）。
> 只改 `a1_ddr_slot_store.v`、`a1_ddr_arb2.v`、`p2_ddr_bridge.v`、`camera_a1_uart_top.v`、
> `p2_a1_board_top.v`、`a1_uart_export.v`；其余全冻结。
> 先 T2/T3（丢 R→超时→重试→导出；晚到 R 不污染），再 T4–T13、P1 三黄金、b12 R1、b11 read、full 两帧；
> 综合/布线/1 bitgen+1 CWC；板级先下载 1 次 SRAM，再开 COM8 150 s，目标 `enc_frames/exported` 增量>0 且 ≥1 帧四 CRC+zlib；
> 若每帧同一位置失败 → 停，转 B（DDR IP 调查）。
> 120 min/60 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 1；失败即停，不自扩预算，不批删。
