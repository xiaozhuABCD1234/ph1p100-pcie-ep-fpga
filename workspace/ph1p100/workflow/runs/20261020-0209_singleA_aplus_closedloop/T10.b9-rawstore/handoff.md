# T10.b9-rawstore 交接（给 fpga-dev）

## 一句话

b8 已证明「相机→MIPI→crop 全通」，但 raw 落盘在早期发布 2 帧后**永久冻结**。本任务：①加状态包 v3 让 raw 段卡点可唯一定位；②当轮修掉静态已证实的 4 个缺陷（F1–F4）；③P2 重建 + **1 次** SRAM 下载 90 s 取证。

先读 `fpga-design-guide.md`（冻结格式/v3 布局/4 缺陷定位），再读 `dev-plan.md`（包与门槛）。本文件只给启停与坑。

## 必须守住

- 只写 `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b9-rawstore/**`；`fpga/csi2/src/**`、b8/b7 run 目录、`D:/TD/work/csi2` 全部只读。
- 数据格式不动：480 beat/行、4 组/256-bit 字、129,600 字/帧、2,592,000 B、`EXPECT_BYTES` 精确匹配才 publish。
- 1 次 SRAM 下载；**先开 COM8 再下载**；失败不二次下载、不 Flash。
- G1（仿真）不绿不进 TD；TD 布线违例即停。

## 起点（照抄即可）

1. 建目录：`r0/{changed-src,td,sim,board}`。
2. 拷基线：
   - `T10.b8-crop-geom/r0/changed-src/*.v` → `T10.b9-rawstore/r0/changed-src/`（a1_raw_crop.v 本任务**不要改**，只为哈希齐全而拷）
   - `T10.b8-crop-geom/r0/td/` 整棵 → `r0/td/`（含 `src/`、`01_build.tcl`、`02_bitgen.tcl`、`03_cwc.tcl`、`p2_board.sdc`）
   - `T10.b8-crop-geom/r0/sim/` 整棵 → `r0/sim/`（含 `a1_ddr_model.v`、`tb_p1_chain.v`、`run_sims.py`）
   - `T10.b8-crop-geom/r0/board/{capture_com8.py,parse_status_v2.py}` → `r0/board/`
   - `fpga/csi2/src/a1/a1_ddr_slot_store.v` → `r0/changed-src/a1_ddr_slot_store.v`（本任务要改它）
3. 改 `r0/td/01_build.tcl`：把所有 `T10.b8-...` 路径换成 `T10.b9-rawstore`；`add_files …/a1_ddr_slot_store.v` 指向本任务 `r0/changed-src/`。

## 4 个缺陷（细节见设计指南第 3 节，行号为 b8 生效版本）

| 编号 | 位置 | 一句话 | 修法要点 |
|---|---|---|---|
| F1 | `a1_raw_crop.v` L135/L144 + 顶 L115 | `out_abort` 只拉一拍且**同拍 `out_valid=0`**，CDC 只写 valid 拍 → abort 永远到不了 A1 侧 → store 永久停在 WRITE | abort 必须随一个有效 beat 跨域；A1 侧见 abort-beat 即 `wr_abort` + 清 `raw_active` + `raw_drop+1` + `raw_abort_cnt+1`；不写 DDR |
| F2 | 顶 L148-156 | `e_sof` 且 `!raw_begin_ready` 时 `fifo_ready` 恒 0 → FIFO 写满且写侧 `w_ready` 未接、满时 `push=0` → **整帧静默丢数**，而 `raw_drop` 仍是 0（板级 `raw_drop=0` 不能当"没丢帧"用） | 整帧丢弃：`fifo_ready=1` + `skip_frame` 直到下个 `e_sof`；`raw_drop+1`、`raw_begin_deny+1` 并计原因；另加 FIFO 溢出计数 |
| F3 | `p2_ddr_bridge.v` L178-186 | `af_pop = af_rvalid && paxi_arready && ddr_rdy` 未与 `paxi_arvalid` 握手耦合，`paxi_arvalid` 又未限 `ddr_rdy` → 丢 AR（读永久卡在某字）或重发 AR（重复 rdata） | `paxi_arvalid = af_rvalid && !ar_pending && ddr_rdy`；`af_pop = paxi_arvalid && paxi_arready`；`ar_pending` 只由已发出 AR 置位、由 `paxi_rvalid && paxi_rready` 清；写通道同样复核握手 |
| F4 | 顶 L206 | raw store `.ddr_ready(1'b1)` 硬接 | 顶加 `i_ddr_rdy`，P2 接 bridge 的 `ddr_rdy`；P1 TB 接 1 保持黄金样例不变 |

## 状态包 v3 要点

- ver=3、len=177（5 B 头 + 43×32b）；前 23 字段与 v2 **顺序语义完全一致**；24–43 见设计指南表格。
- **整包同一拍快照**：`clk_a1` 域一个 `snap_en` 把 43 字段整体锁存并保持到发完，禁止逐位直采计数器。
- 建议 22 个 64-bit `cam_diag_mailbox` 实例（与 b7 同构，不改 UART 分频、不改协议）。
- 打包在 `r0/td/src/camera/uisrc/01_rtl/dbg_uart.v`；接线在 `r0/td/src/p2_a1_board_top.v`。
- 解析脚本 `r0/board/parse_status_v3.py`：复制 v2 脚本，改 ver/len 并加 20 个字段名。

## 板级一次机会怎么用

1. `tools/td/open_td.ps1` → 环境就绪。
2. **先开 COM8**（`capture_com8.py` 起监听/占口）。
3. `download_sram_b9.tcl` 执行**唯一一次** SRAM 下载，日志记 bit SHA256 与 BID。
4. 采 90 s → `r0/board/captures_pwr/com8_90s.bin`。
5. `parse_status_v3.py` → 四选一判定（A/B/C/D）+ 计数表 + 三目标；`exported>0` 再解码 44 B 头 + CRC + zlib。

## 交付

`r0/` 全套证据 + `CANDIDATE-MANIFEST-b9-rawstore-r0.json` + `artifact-hashes.txt` + `result-r0.md` + `lessons-r0.md`。做到诊断门（四选一）即算本轮主目标达成；修复门达成再加解码。
