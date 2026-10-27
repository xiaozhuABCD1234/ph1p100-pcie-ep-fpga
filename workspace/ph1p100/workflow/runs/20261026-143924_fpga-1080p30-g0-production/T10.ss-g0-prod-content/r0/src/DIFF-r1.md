# src/DIFF-r1.md — `tb_ss_4run_wd.v` 逐行 diff 与白名单声明（round1）

- 任务：`T10.ss-g0-prod-content`；run `20261026-143924_fpga-1080p30-g0-production`；round **1**
- 基线（冻结，未改）：`src/tb_ss_4run.v`，25,593 B，SHA256 `7f5cc29405001e4a5da868e8129819e0068715965999c7e81082e38e20947f81`
- 新文件（本 round 新增）：`src/tb_ss_4run_wd.v`，SHA256 `785c3ef1d044f8529b7232ae37ed3a67172b6c4cd512c47a713103675090b79a`
- 规模：r0 471 行 → r1 480 行；`ADDED=14`、`REMOVED=5`（净 +9 行，其中 2 行为同一行 `end` 的删/加）
- 依据：`round1-ruling.md` §2（白名单 5 项）与 `fpga-design-guide.md` §3.1（TB 看门狗语义）

## 1. 声明（先读）

- 本文件**只改 harness 的活性看门狗与 exp 事件的可观测字段**，**不改**任何验收门槛、**不改** DUT 行为、**不改**内容、**不改** G0 口径。12 个 DUT/model 源与 r0 逐字节相同。
- **未**使用 `force`/`deposit`/`release`；**未**新增 `$finish` 之外的终止路径（新增 `SS_STALL_COLD` 分支是裁决明确允许的第 2 项，且同样 `pass=0`）；**未**改 `MAX_CYCLES` 源码值（用 `-gMAX_CYCLES=60000000` 覆盖）。
- **未**改：`drive_frame` / `LINE_GAP` / `FRAME_GAP` / 几何（`CAM_W/CAM_H/ROI_X/ROI_Y/W/H`）/ 三路时钟（`clk_cam` 2.6665、`clk_a1` 2.6665 起 1.7、`clk_ddr` 2.5/2.5）/ 复位（`repeat(20)` 后 `rst_n=1`）/ `PACING` / `SINK` / `FRAMES` / `CONTENT` / `CAPTURE` 语义 / `ss_pass` 表达式 / drain（`repeat(2000)`）/ 其它 EVT 字段 / `$readmemh` 路径与格式。
- 模块名仍为 `tb_ss_4run`（只改文件名），使 diff 与 vsim 命令保持最小；r0 的 `tb_ss_4run.v` **原样保留**，本文件不覆盖它。
- r0 冻结件零改动：`manifest-r0.json` SHA 冻结前后均为 `e55e79659981e3a7f87696aec67d46b02011c3d8fe527c4ecdaf7b39553d9a74`。
- 编译/运行使用**独立库**（`%TEMP%/opencode/ss-g0-prod-content/work-r1`），与 r0 的 `work` 不共用。

## 2. 白名单 5 项对照（r1 行号）

| # | 裁决项 | r1 行 | 实际改动 |
|---|---|---|---|
| 1 | 新增 `WD_LIMIT_COLD`，保留 `WD_LIMIT` | 42 | `localparam integer WD_LIMIT_COLD = 20000000;`（`WD_LIMIT = 12000000` 原样保留在第 41 行） |
| 2 | 新增 `st_exp==0` 时按 `t_sof[1]` 锚定的冷启动分支 | 196–201, 199–204 | `if ((st_exp == 0) && ((cycles - t_sof[1]) > WD_LIMIT_COLD))` → `$display("SS_STALL_COLD ...")` + `B11_FULL_RESULT pass=0` + `$finish` |
| 3 | 原稳态分支加 `st_exp>0` 条件，保留 `SS_STALL` 文本/行为 | 205–210 | `if ((st_exp > 0) && ((cycles - last_exp_t) > WD_LIMIT))`，`SS_STALL` 文本、字段、`pass=0`、`$finish` 全部不变 |
| 4 | `kind=exp` 的 `SS_EVT` 追加只读 `bytes=%0d`（`st_expb`） | 193–194 | `$display` 与 `$fwrite` 各追加 `bytes=%0d` 及实参 `st_expb`；其余字段与顺序不变（`t=.. kind=.. frame=.. n=..` 在 `bytes=` 之前） |
| 5 | 仅注释/命名/空行 | 196–198 | 3 行注释替换原 1 行注释（`per-frame watchdog` → `two-stage watchdog` + 冷/稳态说明） |

**语义等价性说明（为什么这不是放宽门槛）**：

- r0 的 `WD_LIMIT` 判据是 `(cycles - last_exp_t) > WD_LIMIT` 且 `last_exp_t` 初值 0，因此它实际约束的是「**复位后 12M cycles 内必须完成首帧导出**」。r1 把这条约束拆成两段：冷启动段给 20M（锚 `t_sof(1)`），稳态段仍为 12M（锚 `last_exp_t`，且只在 `st_exp>0` 生效）。
- 稳态 guard **没有放宽**（仍是 12,000,000，仍锚 `last_exp_t`）；冷启动预算由裁决给出并留有余量（r0 实测下界 12,440,065 / 12,901,543，余量 ≥55%/64%）。若真实值超过 20M，将如实记 `SS_STALL_COLD` + `partial`，不二次放宽。
- `WD_LIMIT_COLD` 覆盖的是首帧采集/读取/压缩/**首帧导出**的冷启动，**不进入** `S_ss`；`L_cold = t_exp(1)` 单列报告（见 guide §3）。

## 3. 逐行 unified diff（`difflib`, n=3）

```diff
--- src/tb_ss_4run.v (r0 frozen, sha256 7f5cc294)
+++ src/tb_ss_4run_wd.v (r1)
@@ -39,6 +39,7 @@
     localparam integer GX = ROI_X / 4;
     localparam integer RAW_WORDS = 129600;
     localparam integer WD_LIMIT = 12000000;
+    localparam integer WD_LIMIT_COLD = 20000000;   // round1: cold-start budget, anchored at t_sof(1)
 
     reg clk_cam = 1'b0, clk_a1 = 1'b0, clk_ddr = 1'b0, rst_n = 1'b0;
     always #2.6665 clk_cam = ~clk_cam;
@@ -189,11 +190,19 @@
             if (st_exp !== prev_exp) begin
                 prev_exp = st_exp;
                 last_exp_t = cycles;
-                $display("SS_EVT t=%0d kind=exp frame=%0d n=%0d", cycles, st_exp, st_exp);
-                if (fe != 0) $fwrite(fe, "SS_EVT t=%0d kind=exp frame=%0d n=%0d\n", cycles, st_exp, st_exp);
-            end
-            // ---- per-frame watchdog (12,000,000 cycles with no export) ----
-            if ((cycles - last_exp_t) > WD_LIMIT) begin
+                $display("SS_EVT t=%0d kind=exp frame=%0d n=%0d bytes=%0d", cycles, st_exp, st_exp, st_expb);
+                if (fe != 0) $fwrite(fe, "SS_EVT t=%0d kind=exp frame=%0d n=%0d bytes=%0d\n", cycles, st_exp, st_exp, st_expb);
+            end
+            // ---- two-stage watchdog (round1 harness fix; whitelist items 2 and 3) ----
+            //  cold start: anchored at t_sof(1) while nothing has been exported yet
+            //  steady state: original 12,000,000-cycle gap between completed exports
+            if ((st_exp == 0) && ((cycles - t_sof[1]) > WD_LIMIT_COLD)) begin
+                $display("SS_STALL_COLD frame=%0d cycles=%0d read=%0d enc=%0d exported=%0d",
+                         st_exp + 1, cycles, st_read, st_enc, st_exp);
+                $display("B11_FULL_RESULT pass=0");
+                $finish;
+            end
+            if ((st_exp > 0) && ((cycles - last_exp_t) > WD_LIMIT)) begin
                 $display("SS_STALL frame=%0d cycles=%0d read=%0d enc=%0d exported=%0d",
                          st_exp + 1, cycles, st_read, st_enc, st_exp);
                 $display("B11_FULL_RESULT pass=0");
```

## 4. 机械白名单校验（可复现）

`sim/run_content_r1.py verify` 会把上面 5 项改动**反向重构**：取 r0 TB 原文，只应用「① 插入 `WD_LIMIT_COLD` 行、④ exp 两行加 `bytes=`、②③⑤ 替换注释+看门狗块」这三处字面替换，得到 `canonical_r1`，再与实际 `tb_ss_4run_wd.v` 做**逐字节比较**。只有 `canonical_r1 == actual_r1` 时 `whitelist_ok=true`；任何白名单之外的改动都会使该比较失败（不是靠人眼看 diff）。

## 5. 复现命令

```powershell
$dst='D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\T10.ss-g0-prod-content\r0'
python "$dst\sim\run_content_r1.py" verify     # r0 冻结件 SHA + 白名单机械校验
python "$dst\sim\run_content_r1.py" compile    # 独占 %TEMP%/opencode/ss-g0-prod-content/work-r1
python "$dst\sim\run_content_r1.py" run n      # -gFRAMES=4 -gCONTENT=2 -gPACING=0 -gSINK=1 -gCAPTURE=0 -gMAX_CYCLES=60000000
python "$dst\sim\run_content_r1.py" run l
python "$dst\sim\run_content_r1.py" analyze
python "$dst\sim\run_content_r1.py" manifest
```
