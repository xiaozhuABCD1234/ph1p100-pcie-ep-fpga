import io, json, shutil, os

ROOT = r"D:\fpga\ph1p100"
RUN = ROOT + r"\workflow\runs\20261020-0209_singleA_aplus_closedloop"
PKG = RUN + r"\T10.b13-ddr-retry"

def append(path, text):
    with io.open(path, "r", encoding="utf-8") as f:
        s = f.read()
    if not s.endswith("\n"):
        s += "\n"
    s += "\n" + text.strip() + "\n"
    with io.open(path, "w", encoding="utf-8", newline="") as f:
        f.write(s)
    print("appended:", path, len(text), "chars")

dev = r"""
## 61. T10.b13-ddr-retry 冻结（2026-10-25，规划；用户选 A）

- **b12 r1 板级结论（用户已裁决 H4）**：`T10.b12-r1-last/r1/board/captures2/status_v4.txt` 实测 4,470 帧 camera/crop 正常；
  store AR=883、PAXI AR=883、PAXI R=882、rlast=882、stale=0、`ar_pending=1`、`af_rvalid=0`、`rf_rvalid=0`、`s_rvalid=0`、`ddr_rdy=1`；
  `rd_wait_cycles=0xFFFFFFFF`、`raw_rd_idx=882/129,600`、`slot0=READING`、`slot1=READY`、两槽 2,592,000 B；`raw_pub=2`、`enc=0`、`exported=0`。
  DDR 接受第 883 个 AR 后永不返回 R；A1 读通路 1:1 平衡 → **H4**；停点此前 1176、本次 882，不固定 → 偶发丢响应（刷新/读写仲裁）。
- **用户选择 A：DDR 读超时 + 重试**。新包 **`T10.b13-ddr-retry`**（ready；父 T10 保持 blocked；`needs_user_input=false`）。
- **冻结语义**：AR 接受后 8192 clk_a1 无 R → 超时；abort 当前帧读、槽保持 READING（不发布、不覆盖 READY）；
  清读 FSM + bridge 读路径（清 `ar_pending`、排空 AF、丢弃 RF/skid）；保护窗口 32768 clk_a1 内禁新 AR；晚到 R 在 `ar_pending=0` 时吞掉并计 stale；
  然后重试同一帧（从 0 重读），最多 2 次；仍失败释放槽 + `giveup`，不导出半帧。重试走正常 `rd_open`，A+ 核/压缩槽 abort 后重开，无 `a1_commit` 即无描述符。
- **只改 6 源**：`a1_ddr_slot_store.v`（超时/重试 FSM，仅 raw 实例 `RETRY_EN=1`）、`a1_ddr_arb2.v`（`m0_rd_abort` 只清 raw `rd_busy`）、
  `p2_ddr_bridge.v`（purge/guard/晚到 R/`stale_guard_cnt`，`dbg_a1` 192→256）、`camera_a1_uart_top.v`（`o_rd_abort`/超时序列/v5 512 bit 总线）、
  `p2_a1_board_top.v`（连线/宽度）、`a1_uart_export.v`（v5 241 B/59 字段）。其余 4 源与 A+ 核/crop/帧格式/SDC/时钟/DDR IP 全冻结。
- **v5**：241 B = 4 hdr + 59×u32 + XOR8，VER=5、LEN=241、XOR 覆盖 0..239；`#1..#55` 顺序不变，追加
  `#56 rd_timeout_cnt / #57 rd_retry_cnt / #58 rd_retry_giveup / #59 rd_stale_guard_cnt`。
- **仿真**：T1 clean；T2 丢 1 R→超时→重试→整帧导出（四 CRC+zlib）；T3 晚到 R 不污染；T4 连续 3 帧仅中间帧重试；
  T5 重试预算耗尽不死锁、下一好帧恢复；T6 帧中部超时；T7 保护窗口；T8 b12 R1 全回归；T9 b12 store/t7/multi；T10 b11 read 九例；
  T11 P1 三黄金逐字节；T12 full 两帧 + full 丢 1 R；T13 v5 结构。
- **构建**：综合≤3、布线≤2、1 bitgen + 1 CWC；Routed 0 违例、hold/period 正、ERAM+CWC≤300；WNS 目标 ≥+0.05；
  预裁决 0 违例且 +0.003…+0.05 → 接受为诊断候选并记 `timing_caveat`；**<+0.003 或任何违例即停**。
- **板级**：FTDI 预检；在位 → **先下载 1 次 SRAM**，成功后再开 COM8 150 s；v5 ≥120 包、`enc_frames/exported` 增量>0、≥1 帧四 CRC+zlib、无半帧；
  记录 timeout/retry/giveup/stale；若每帧同一 `rd_idx` 超时且 exported=0 → **停止转 B（DDR IP 调查）**，不二次下载/第二个 bitstream。
- **预算**：开发 120 min/60 calls；TD 3 会话、综合≤3、布线≤2、bitgen 1、CWC 1、下载 1、Flash 0；综合测试 45/30。
- **入口**：`T10.b13-ddr-retry/{dev-plan.md,fpga-design-guide.md,dispatch.json,handoff.md,user-summary.md}`；
  证据 `T10.b12-r1-last/r1/board/captures2/status_v4.txt`；基线 `T10.b12-r1-last/r0/**`、`T10.b11-aplus-read/r0/sim/**`。
"""

handoff = r"""
## 61. T10.b13-ddr-retry 冻结（2026-10-25，规划；用户选 A）

- **H4 已由 b12 r1 板级证实**：4,470 帧正常；store AR=883、PAXI AR=883、R=882、stale=0、`ar_pending=1`、`af_rvalid=0`、`ddr_rdy=1`、
  `rd_wait` 饱和、`raw_rd_idx=882/129,600`、`slot0=READING`、`slot1=READY`；停点 1176→882 不固定。证据 `T10.b12-r1-last/r1/board/captures2/status_v4.txt`。
- **新包 `T10.b13-ddr-retry`**（ready；父 T10 blocked）：A = 读超时 + 重试。8192 clk_a1 超时 → abort 当前帧读、槽保持 READING →
  清 `ar_pending`/AF/RF → 32768 clk_a1 保护窗禁新 AR、晚到 R 计 stale → 重试同一帧最多 2 次 → 仍失败释放槽 + `giveup`，不发布半帧。
- **只改 6 源**：`a1_ddr_slot_store.v`、`a1_ddr_arb2.v`、`p2_ddr_bridge.v`、`camera_a1_uart_top.v`、`p2_a1_board_top.v`、`a1_uart_export.v`；
  其余 4 源/A+ 核/crop/帧格式/SDC/时钟/DDR IP 冻结；`u_cmp_store` 用 `RETRY_EN=0` 保持旧行为。
- **v5**：241 B/59 字段，`#56 timeout / #57 retry / #58 giveup / #59 stale`；`#1..#55` 顺序不变。
- **必测**：丢 1 R→超时→重试→整帧导出；晚到 R 不污染；连续 3 帧；重试预算耗尽；帧中部超时；保护窗；b12 R1 回归；b11 read 九例；
  P1 三黄金逐字节；full 两帧 + full 丢 1 R；v5 结构。
- **构建**：综合≤3/布线≤2；Routed 0 违例；WNS 目标 ≥+0.05，0 违例且 +0.003…+0.05 接受为诊断候选并记 caveat，<+0.003 或违例即停；1 bitgen+1 CWC。
- **板级**：先下载 1 次 SRAM 后开 COM8 150 s；v5 ≥120 包、`enc_frames/exported` 增量>0、≥1 帧四 CRC+zlib；每帧同一 `rd_idx` 失败且 exported=0 → 停，转 B。
- **预算**：开发 120 min/60 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 1/Flash 0；测试 45/30。
- **入口**：`T10.b13-ddr-retry/{dev-plan.md,fpga-design-guide.md,dispatch.json,handoff.md,user-summary.md}`。
"""

user = r"""
## 62. T10.b13-ddr-retry 冻结（2026-10-25，用户选 A：超时 + 重试）

- **b12 r1 板级真相**：4,470 帧正常，但读通路在 `raw_rd_idx=882/129,600` 停住；store AR=883、PAXI AR=883、R=882、stale=0、
  `ar_pending=1`、`ddr_rdy=1`，`slot0=READING`、`slot1=READY`。判定 **H4：DDR 接受 AR 后不回 R**；停点 1176→882 不固定 → 偶发丢响应。
- **新包 `T10.b13-ddr-retry`**（ready，父 T10 仍 blocked）：AR 接受后 **8192 clk_a1** 等不到 R → 超时；abort 当前帧读、槽保持 READING；
  清 `ar_pending`、排空 AF、丢弃 RF/skid；**保护窗口 32768 clk_a1 禁新 AR**，晚到 R 计 stale 并丢弃；然后**重试同一帧**，最多 2 次；
  仍失败释放槽、`giveup`，不导出半帧；重试成功则整帧导出。
- **状态包 v5**：241 B / 59 字段，新增 `#56 timeout / #57 retry / #58 giveup / #59 stale`；`#1..#55` 原顺序不变。
- **改动**：只 6 个源（store 读 FSM、arbiter raw abort、bridge purge/guard、top 超时序列、板级连线、v5 包）；A+ 核/crop/帧格式/SDC/时钟/DDR IP 全冻结。
- **验收**：丢 1 R→超时→重试→整帧四 CRC+zlib；晚到 R 不污染；连续 3 帧；重试预算耗尽不死锁；P1 三黄金逐字节；b12 R1/b11 read 回归；full 两帧。
- **构建**：Routed 0 违例；WNS 目标 ≥+0.05；0 违例且 +0.003…+0.05 按 b12 口径接受为诊断候选并记 caveat；<+0.003 或违例即停；1 bitgen+1 CWC。
- **板级**：先下载 1 次 SRAM，再开 COM8 150 s；`enc_frames/exported` 增量>0、≥1 帧四 CRC+zlib；若每帧同一位置失败且 exported=0 → 停，转 B（DDR IP 调查）。
- **预算**：开发 120 min/60 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 1；不 Flash、不 PCIe/RK、不批量删除。
- **入口**：`T10.b13-ddr-retry/{dev-plan.md,fpga-design-guide.md,dispatch.json,handoff.md,user-summary.md}`；证据 `T10.b12-r1-last/r1/board/captures2/status_v4.txt`。
"""

final = r"""
## 61. b12 r1 板级 H4 → T10.b13-ddr-retry 冻结（2026-10-25，用户选 A）

> 本节更新 b 系列最新状态；§60 的 b11/b12 描述保留为历史。

- **b12 r1 板级实测**：camera/crop 4,470 帧正常；read 通路 store AR=883、PAXI AR=883、R=882、rlast=882、stale=0、`ar_pending=1`、`af_rvalid=0`、`ddr_rdy=1`；
  `rd_wait_cycles` 饱和、`raw_rd_idx=882/129,600`、`slot0=READING`、`slot1=READY`（各 2,592,000 B）；`raw_pub=2`、`enc=0`、`exported=0`。
  判定 **H4**（DDR 接受 AR 不回 R）；停点 1176→882 不固定 → 偶发丢响应。证据 `T10.b12-r1-last/r1/board/captures2/status_v4.txt`。
- **b12 r1 候选**：bit `9180DB8C…2F8CD3`、CWC `FFB88419…B47C9A0`、BID `96D8A5DF…9E4A32`；Routed `SWNS=+0.003 / HWNS=+0.020 / 0 违例`，
  `timing_caveat=thin_margin_+0.003`（诊断候选）；1 次 SRAM 下载；未写 Flash。b12 **不置 done**（父 T10 仍 blocked）。
- **新包 `T10.b13-ddr-retry`**（ready；`needs_user_input=false`）：DDR 读超时 + 重试。超时 8192 clk_a1 → abort 当前帧读、槽保持 READING →
  清 `ar_pending`/AF/RF → 32768 clk_a1 保护窗禁新 AR、晚到 R 计 stale → 重试同一帧最多 2 次 → 仍失败释放槽 + `giveup`，不发布半帧。
- **v5**：241 B/59 字段；追加 `timeout/retry/giveup/stale`；`#1..#55` 不变。
- **只改 6 源**：store 读 FSM、arbiter raw abort、bridge purge/guard、top 超时序列、板级连线、v5 包；A+ 核/crop/帧格式/SDC/时钟/DDR IP 冻结。
- **构建/板级**：综合≤3/布线≤2、Routed 0 违例、WNS 目标 ≥+0.05（0 违例且 +0.003…+0.05 接受为诊断候选并记 caveat，<+0.003 或违例即停）；
  1 bitgen+1 CWC；先下载 1 次 SRAM 后开 COM8 150 s，`enc_frames/exported` 增量>0、≥1 帧四 CRC+zlib；每帧同一位置失败且 exported=0 → 停，转 B。
- **预算**：开发 120 min/60 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 1/Flash 0；测试 45/30。
- **入口**：`T10.b13-ddr-retry/{dev-plan.md,fpga-design-guide.md,dispatch.json,handoff.md,user-summary.md}`。
"""

append(RUN + r"\dev-plan.md", dev)
append(RUN + r"\handoff.md", handoff)
append(RUN + r"\user-summary.md", user)
append(RUN + r"\final-summary.md", final)

tasks_path = ROOT + r"\workflow\tasks.json"
backup_path = ROOT + r"\workflow\tasks.json.before-20261025-b13.json"
shutil.copyfile(tasks_path, backup_path)
with io.open(tasks_path, encoding="utf-8-sig") as f:
    j = json.load(f)

t10 = next(t for t in j["tasks"] if t.get("id") == "T10")
bc = t10.setdefault("board_chain", {})

note = (
    " | 20261025_b13-dispatch: b12 r1 board proved H4 (store AR=883 / PAXI AR=883 / R=882 / stale=0 / ar_pending=1 / ddr_rdy=1, "
    "raw_rd_idx=882 of 129600, slot0=READING, slot1=READY; stop moved 1176->882). User selected A (DDR read timeout + retry). "
    "T10.b13-ddr-retry frozen and ready (parent T10 stays blocked): TIMEOUT_N=8192 clk_a1 after an accepted AR, abort current frame read, "
    "keep the slot READING, clear ar_pending/drain AF/discard RF+skid, guard 32768 clk_a1 with no new AR and late R swallowed as stale, "
    "retry the SAME frame from word 0 up to MAX_RETRY=2, then free the slot and give up; no half frame, no overwrite of READY, no late R as a new transaction. "
    "v5 status packet 241 B / 59 fields appends timeout/retry/giveup/stale; fields #1..#55 unchanged. Only 6 sources may change: "
    "a1_ddr_slot_store.v, a1_ddr_arb2.v, p2_ddr_bridge.v, camera_a1_uart_top.v, p2_a1_board_top.v, a1_uart_export.v; A+ core/crop/frame format/SDC/clock/DDR IP frozen. "
    "Sim: drop-1-R -> timeout -> retry -> full frame four CRCs+zlib; late R; 3 frames; retry budget; mid-frame; guard; P1 three goldens; b12 R1; b11 read; full two frames. "
    "Build: synth<=3/route<=2, Routed 0 violations, WNS target >=+0.05, thin +0.003..+0.05 accepted under the b12 rule with caveat, <+0.003 or any violation stops; 1 bitgen + 1 CWC. "
    "Board: 1 SRAM download FIRST then COM8 150 s; enc_frames/exported delta >0 and >=1 frame four CRCs+zlib; if every frame fails at the same rd_idx with exported=0, stop and go to B (DDR IP investigation). "
    "Budget dev 120 min/60 calls; TD 3 sessions; download 1; Flash 0. Dispatch: workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b13-ddr-retry/dispatch.json. "
    "T10 remains blocked/not done."
)
t10["status_note"] = t10.get("status_note", "") + note

bc["b12"] = "diagnosis_only_board_H4_lost_R"
bc["b12_package"] = "T10.b12-r1-last"
bc["b12_stop_word"] = "882 of 129600 (previous 1176; not fixed)"
bc["b12_bit"] = "9180DB8C13751CA34179E6CF3DE73DB178F259546565AFDD1CFFDAB3702F8CD3"
bc["b12_cwc"] = "FFB88419D3A0A18A686EF0DCFD161DD0E4B719319AFC4D6B103FBF46EB47C9A0"
bc["b12_swNs"] = 0.003
bc["b12_evidence"] = [
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b12-r1-last/r1/board/captures2/status_v4.txt",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b12-r1-last/r1/result-r1.md",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b12-r1-last/CANDIDATE-MANIFEST-b12-r1-last-r1.json",
]
bc["b13"] = "ready"
bc["b13_package"] = "T10.b13-ddr-retry"
bc["b13_option"] = "A: DDR read timeout + retry"
bc["b13_semantics"] = "TIMEOUT_N=8192 clk_a1 after accepted AR; slot stays READING; clear ar_pending/AF/RF; GUARD_N=32768 clk_a1 no new AR; late R stale; retry same frame MAX_RETRY=2; then free+giveup; no half frame"
bc["b13_status_packet"] = "v5 241 B / 59 fields; #56 timeout, #57 retry, #58 giveup, #59 stale; #1..#55 unchanged"
bc["b13_dispatch"] = "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b13-ddr-retry/dispatch.json"
bc["b13_budget"] = "dev 120 min/60 calls; TD 3 sessions, synth<=3, route<=2, bitgen 1, CWC 1, download 1, Flash 0; tester 45/30"
bc["b13_floor"] = "Routed 0 violations; WNS >= +0.003 (thin accepted as diagnostic candidate with caveat); target >= +0.05; < +0.003 or any violation stops"

ev = t10.get("latest_evidence", [])
for p in [
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b13-ddr-retry/dev-plan.md",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b13-ddr-retry/dispatch.json",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b13-ddr-retry/fpga-design-guide.md",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b12-r1-last/r1/board/captures2/status_v4.txt",
]:
    if p not in ev:
        ev.append(p)
t10["latest_evidence"] = ev

t10["blocker"] = (
    "T10 blocked / not done: b12 r1 board proved H4 (DDR accepts AR 883 but never returns R; stop moved 1176->882; both slots correct, 4470 camera frames). "
    "b12 is diagnosis-only and not done. T10.b13-ddr-retry is frozen/ready (option A: timeout + retry; v5; 6 sources; 1 bitgen+1 CWC; 1 SRAM download then COM8) "
    "and will not close T10 by itself; demands 2/3 remain incomplete."
)

with io.open(tasks_path, "w", encoding="utf-8") as f:
    json.dump(j, f, ensure_ascii=False, indent=2)
    f.write("\n")

print("backup:", backup_path)
print("T10 state:", t10["state"], "b12:", bc.get("b12"), "b13:", bc.get("b13"))
print("evidence count:", len(t10["latest_evidence"]))
