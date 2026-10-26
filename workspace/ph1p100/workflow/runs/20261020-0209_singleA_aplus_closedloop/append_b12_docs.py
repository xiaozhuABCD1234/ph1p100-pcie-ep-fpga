# -*- coding: utf-8 -*-
"""Append the T10.b12-r1-last freeze section to the run-level docs.

Idempotent: refuses to append if the marker is already present.
Only appends; never rewrites or deletes existing content.
"""
import io
import json
import pathlib
import sys

RUN = pathlib.Path(r"D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop")
TASK = RUN / "T10.b12-r1-last"

DEV = """
## 60. T10.b12-r1-last 冻结（2026-10-25，规划）

### 60.1 裁决：R1 有效反例成立，b11 收为 diagnosis_only
- 独立补充验证 `work/b10-gap-sim-20261025-132023` 在 b11 冻结源上给出 **R1 有效反例**：FIFO 拒收 7 组（含 LAST）后释放背压，writer 仍活动、slot0 仍 WRITE（nbytes=45/80）、`raw_abort_cnt=0`；随后两个完整好帧的 SOF 被 FIFO 接受但 RAW begin 被拒（`begin_deny=2`），最终发布/编码/导出仍各 1。坏帧未发布，但槽未归还。
- 同目录连续三帧小几何 **PASS**（ID1/2/3、三种源、3015 B 物理 UART、四 CRC、严格解压、5 个状态包均在帧间），本包必须保持。
- b11：Routed `SWNS=+0.015 / 0 违例`，bit `7ef0e9be…`、CWC `08ad62f4…`；FTDI 0403:6042 不在位，**未上板**（下载 0/2）。b11 收为 **diagnosis_only + board blocked**，不置 done。
- 新包 **`T10.b12-r1-last`**（ready，父 T10 保持 blocked）：只修 R1，不猜修 1176 读停点；1176 仍按 H2/H4 由 v4 判别。

### 60.2 修复范围（只改两个源）
- `camera_a1_uart_top.v`：clk_cam 侧任何 `fifo_wvalid && !fifo_wready` → sticky `abort_hold`（FIFO 有空间即推 abort beat，SOF/中间/LAST 都覆盖）；A1 侧 `fifo_ready` 对“非 SOF、非 skip_frame、raw_active=0”的 stray data beat 消费丢弃，避免 abort beat 被堵在 FIFO 头；`fifo_ovf_cnt` 保留。
- `a1_ddr_slot_store.v`：abort 压过同拍 `wr_last/wr_ready`（不发布坏帧）；`wr_begin + wr_abort` 同拍时，若另一槽 FREE，释放旧槽并接收新帧（避免下一好帧被误拒）；`raw_drop/raw_abort_cnt` 语义保留。
- 其余 7 个 changed-src、v4 225 B、reader/bridge/arbiter/crop/UART 帧格式、DDR 四槽布局、SDC/引脚/时钟全冻结；不改 upstream，不改 `work/b10-gap-sim-20261025-132023/**`。

### 60.3 强制用例与门槛
- T1 clean 控制；**T2 FIFO 拒收 7 组（含 LAST）→ 释放背压 → 两个好帧恢复**（故障帧不发布、槽 FREE、writer=0、`raw_abort_cnt>=1`、`raw_drop>=1`、恢复源序列精确 `[11,1000,1001]`、两好帧四 CRC+zlib）；T3 同拍 LAST+abort；T4 同拍 begin+abort；T5 中写复位；T6 满槽并发；T7 SOF 拒收变体；T8/T9 b9 abort/nofree/rdy 回归；T10 三帧小几何 PASS。
- P1 三黄金逐字节同基线；v4 225 B/55 字段；full 两帧 `read_words=129600/enc=2/exported=2`；b11 read 九例不回归；正常路径 `raw_abort_cnt=0/raw_drop=0`。
- 构建：Routed 0 违例、hold/period 正、ERAM+CWC≤300；WNS 目标 ≥+0.05。**预裁决**：若只能 +0.015 且最差 setup 路径仍在 vendor DDR PHY（`u_ddrphy_fast_init/u_ddrphy_dcu/cal_wrlvl`），接受为功能/诊断候选并记 caveat；若最差路径落在本轮改动/v4/桥，才允许一次“只减观测、不改 LEN/VER/225 B”的精简；仍 <+0.05 → 停止交规划；WNS <+0.015 或任何违例 → 不 bitgen、不下载。1 bitgen + 1 CWC。

### 60.4 板级条件与预算
- FTDI 预检：不在位 → `board=blocked`，**0 下载、0 COM8、不重试**；在位 → 先下载 1 次 SRAM（同一冻结 bit），释放 FTDI，再开 COM8 150 s；v4 ≥120 包、`enc_frames/exported` 增量>0、≥1 帧 44 B 头+四 CRC+zlib、无半帧；正常帧路径 `raw_abort_cnt/raw_drop` 不应增长。若仍 1176，用 v4 #44–#50 判 H2/H4，本包不修 DDR/PAXI。
- 开发 **120 min / 60 calls**；TD **3 会话**、综合≤3、布线≤2、bitgen 1、CWC 1、下载 **1**、Flash 0；不 Flash/PCIe/RK/双路/G4，不批量删除。
- 开发冻结后派 **1 个新综合测试者** 做 round0 integrated 验收（哈希绑定、T1–T10 复跑、P1/v4、构建/时序、板级预检/抓包），报告写 `test-reports/T10.b12-r1-last-r0-integrated.md`。

### 60.5 入口
- `T10.b12-r1-last/{dev-plan.md,dispatch.json,handoff.md,user-summary.md}`；
- 基线 `T10.b11-aplus-read/r0/{CANDIDATE-MANIFEST-b11-aplus-read-r0.json,result-r0.md,changed-src/,sim/,td/}`；
- 反例 `work/b10-gap-sim-20261025-132023/{README.md,r1-loss/result.md,r1-loss/attempt1-slowcam/result.json,r1-loss/check_r1.py}`；
- 读停点 `T10.b11-aplus-read/r0/diag/read-stall-analysis.md`（H2/H4，本包不修）。
"""

HANDOFF = """
## 60. T10.b12-r1-last 冻结（2026-10-25，规划）

- **R1 有效反例成立**：`work/b10-gap-sim-20261025-132023` 在 b11 冻结源上复现 FIFO 拒收 7 组（含 LAST）→ 释放背压 → writer/slot0 卡 WRITE（nbytes=45/80）、`raw_abort_cnt=0` → 两个好帧 `begin_deny=2`；坏帧未发布但槽未归还。
- **b11 收口**：Routed +0.015/0 违例；bit `7ef0e9be…`、CWC `08ad62f4…`；FTDI 不在位未上板 → **diagnosis_only + board blocked**，不置 done。
- **新包 `T10.b12-r1-last`**（ready，父 T10 保持 blocked）：只修 R1，不猜修 1176 读停点（H2/H4 仍由 v4 判别）。
- **只改两源**：`camera_a1_uart_top.v`（拒收即 sticky loss-abort；消费无主 stray beat；保留 `fifo_ovf_cnt`）；`a1_ddr_slot_store.v`（abort 压过同拍 LAST/写；begin+abort 同拍释放旧槽并接收新帧；保留 `raw_drop/raw_abort_cnt`）。
- **必测**：T2 7 拒收含 LAST→两好帧恢复；T3 同拍 LAST+abort；T4 同拍 begin+abort；T5 中写复位；T6 满槽并发；T7 SOF 拒收变体；T8/T9 b9 回归；T10 三帧小几何；P1 三黄金逐字节；v4 225 B；full 两帧 129600/enc=2/exported=2；b11 read 九例。
- **构建**：Routed 0 违例；WNS 目标 ≥+0.05；若只能 +0.015 且最差路径仍在 vendor DDR PHY，规划预裁决接受并记 caveat；<+0.015 或任何违例即停；1 bitgen + 1 CWC。
- **板级**：FTDI 预检；不在位 → board=blocked/0 下载/0 COM8；在位 → 先下载后开 COM8、1 次 SRAM、150 s、`enc_frames/exported` 增量>0、≥1 帧四 CRC+zlib；仍 1176 则判 H2/H4，不修 DDR/PAXI。
- **预算**：开发 120 min/60 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 1/Flash 0。
- **入口**：`T10.b12-r1-last/{dev-plan.md,dispatch.json,handoff.md,user-summary.md}`；基线 `T10.b11-aplus-read/r0/**`；反例 `work/b10-gap-sim-20261025-132023/r1-loss/result.md`。
"""

FINAL = """
## 60. 当前状态更新：b11 diagnosis_only，b12 R1 修复包冻结（2026-10-25）

> 本节更新 b 系列当前状态；本文件 2026-10-21 的 T10 头部结论（a1 RTL 3/4 PASS + 1 warning、G2 未闭合）仍然有效，但不再代表 b9–b12 的最新进展。

- **b11 `T10.b11-aplus-read` = diagnosis_only + board blocked**：1176/1177 读停点不在 A1 读通路 RTL（真 CDC/arbiter/store/bridge 全尺寸 129,600 字 bad=0）；剩余 H2（AR 进 AF FIFO 但不再被 PAXI 弹出）与 H4（PAXI 收 AR 不回 R）需板级 v4 判别。Routed `SWNS=+0.015 / 0 违例`；bit `7ef0e9be…`、CWC `08ad62f4…`；FTDI 0403:6042 不在位，**未上板**。
- **R1 = 有效反例，尚未修复**：独立补充验证 `work/b10-gap-sim-20261025-132023` 在 b11 冻结源上复现：FIFO 拒收 7 组（含 LAST）→ 释放背压 → writer/slot0 仍 WRITE（nbytes=45/80）、`raw_abort_cnt=0`；随后两个完整好帧被拒（`begin_deny=2`）。同目录三帧小几何 PASS。
- **新包 `T10.b12-r1-last`（ready；父 T10 仍 blocked）**：只修 R1——clk_cam 拒收即 sticky loss-abort；A1 消费无主 stray beat；store abort 压过同拍写、begin+abort 同拍释放旧槽并接收新帧；保留 `raw_drop/raw_abort_cnt`、v4 225 B、P1 三黄金逐字节。
- **必测**：T2 7 拒收含 LAST→两好帧恢复；T3 同拍 LAST+abort；T4 同拍 begin+abort；T5 中写复位；T6 满槽并发；T7 SOF 拒收变体；T8/T9 b9 回归；T10 三帧；P1 三黄金；v4；full 两帧；b11 read 九例。
- **构建/板级**：1 bitgen+1 CWC；Routed 0 违例、WNS 目标 ≥+0.05（若只能 +0.015 且关键路径仍在 vendor DDR PHY，接受并记 caveat）；FTDI 不在位则 board=blocked/0 下载；在位则先下载后开 COM8、150 s、`enc_frames/exported` 增量>0、≥1 帧四 CRC+zlib；仍 1176 只判 H2/H4，不修 DDR/PAXI。
- **预算**：开发 120 min/60 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 1/Flash 0。
- **入口**：`T10.b12-r1-last/{dev-plan.md,dispatch.json,handoff.md,user-summary.md}`；`T10.b11-aplus-read/r0/result-r0.md`；`work/b10-gap-sim-20261025-132023/README.md`。
"""

USER = """
## 61. T10.b12-r1-last 冻结（2026-10-25，规划）

- **R1 已确认是有效缺陷**：FIFO 拒收 7 组（含 LAST）后释放背压，RAW writer 仍卡在 WRITE、槽不归还，后续两个好帧被拒；坏帧没有发布。根因是源码只加 `fifo_ovf_cnt`，没有生成本帧 loss-abort。
- **新包 `T10.b12-r1-last`**（ready，父 T10 仍 blocked）：只修 R1，不猜修 1176 读停点。改动只限 `camera_a1_uart_top.v`（拒收即 sticky abort + 消费无主 stray beat）和 `a1_ddr_slot_store.v`（abort 压过同拍写；begin+abort 同拍释放旧槽并接收新帧）。
- **验收**：7 拒收含 LAST → 释放 → 两个好帧恢复，故障槽 FREE、`writer=0`、`raw_abort_cnt>=1`、`raw_drop>=1`，恢复源序列 `[11,1000,1001]`，四 CRC+zlib 全过；新增同拍 LAST+abort、begin+abort、中写复位、满槽并发、SOF 拒收变体；P1 三黄金逐字节、v4 225 B、三帧小几何、full 两帧、b11 read 九例不回归。
- **构建**：1 bitgen+1 CWC；Routed 0 违例；WNS 目标 ≥+0.05；若只能 +0.015 且最差路径仍在 vendor DDR PHY，接受并记 caveat；<+0.015 或任何违例即停。
- **板级**：FTDI 当前不在位。不在位 → board=blocked、0 下载、0 COM8；在位 → 先下载后开 COM8，1 次 SRAM、150 s，目标 `enc_frames/exported` 增量>0 且 ≥1 帧四 CRC+zlib；仍 1176 只判 H2/H4，不修 DDR/PAXI。
- **预算**：开发 120 min/60 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 1；不 Flash、不 PCIe/RK、不批量删除。
- **入口**：`T10.b12-r1-last/dev-plan.md`、`dispatch.json`、`handoff.md`、`user-summary.md`。
"""

FILES = [
    ("dev-plan.md", "## 60. T10.b12-r1-last 冻结", DEV),
    ("handoff.md", "## 60. T10.b12-r1-last 冻结", HANDOFF),
    ("final-summary.md", "## 60. 当前状态更新", FINAL),
    ("user-summary.md", "## 61. T10.b12-r1-last 冻结", USER),
]

# Sanity: task files exist and dispatch parses.
for name in ("dev-plan.md", "dispatch.json", "handoff.md", "user-summary.md"):
    p = TASK / name
    if not p.exists():
        print("MISSING", p)
        sys.exit(2)
json.load(io.open(TASK / "dispatch.json", encoding="utf-8"))

for name, marker, block in FILES:
    p = RUN / name
    if not p.exists():
        print("MISSING", p)
        sys.exit(3)
    text = io.open(p, encoding="utf-8").read()
    if marker in text:
        print("SKIP (already present):", name)
        continue
    # Ensure a blank line boundary before the appended section.
    with io.open(p, "a", encoding="utf-8", newline="\n") as f:
        if not text.endswith("\n"):
            f.write("\n")
        f.write("\n")
        f.write(block.strip("\n"))
        f.write("\n")
    print("APPENDED:", name)
print("OK")
