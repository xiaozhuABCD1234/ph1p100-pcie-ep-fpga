# T10.b12-r1-last — handoff（规划 → 开发 / 综合测试者）

- 日期：2026-10-25；run：`20261020-0209_singleA_aplus_closedloop`；项目根：`D:/fpga/ph1p100`
- 状态：**ready**；`needs_user_input=false`；批大小 1；父 T10 **保持 blocked**
- 唯一目标：修 **R1**——FIFO 拒收/背压导致 LAST 丢失时，RAW writer 必须 abort/释放、槽归还，后续好帧恢复；坏帧不发布；保留 `raw_drop`/`raw_abort_cnt` 计数
- 唯一源基线：`T10.b11-aplus-read/r0`（v4 225 B + F_WAIT 看门狗），9 个 changed-src 哈希见 `CANDIDATE-MANIFEST-b11-aplus-read-r0.json`
- b11 构建：Routed `SWNS=+0.015 / 0 违例`；bit `7ef0e9be…`、CWC `08ad62f4…`；**未上板**（FTDI 0403:6042 不在位）
- R1 反例：`work/b10-gap-sim-20261025-132023`（只读）——FIFO 拒收 7 组含 LAST；释放背压后 writer 仍活动、slot0=WRITE、`nbytes=45/80`、`raw_abort_cnt=0`；两个好帧 `begin_deny=2`。同目录三帧小几何 **PASS**，必须保持

## 1. 必须按顺序读

1. `T10.b12-r1-last/dev-plan.md`（冻结计划、§3 修复规格、§4 定向用例、§6 时序裁决）
2. `T10.b12-r1-last/dispatch.json`
3. `work/b10-gap-sim-20261025-132023/{README.md,r1-loss/result.md,r1-loss/attempt1-slowcam/result.json,r1-loss/attempt1-slowcam/loss/trace.txt,r1-loss/check_r1.py}`
4. `T10.b11-aplus-read/r0/{CANDIDATE-MANIFEST-b11-aplus-read-r0.json,result-r0.md,changed-src/,sim/,td/}`
5. `T10.b11-aplus-read/r0/diag/read-stall-analysis.md`（1176 读停点仍是 H2/H4，**本包不修**）
6. `T10.b9-rawstore/r0/sim/tb_raw_store.v`（T3–T9 的 store 单元用例基础）

## 2. 规划已确认、不要重复推翻

- b11 源码里的 `// T10.b10 R1:` 注释是**已回退尝试的历史注释**；当前候选没有 loss-abort 功能。
- R1 根因三条：① clk_cam 拒收只 `fifo_ovf_cnt++`；② A1 侧无主 stray data beat 不消费，abort beat 会排在后面死锁；③ store 的 abort 不压过同拍写，begin+abort 无“释放旧槽/接收新帧”语义。
- 修复只动 `camera_a1_uart_top.v` 与 `a1_ddr_slot_store.v`；v4、reader、bridge、arbiter、crop、UART 帧格式全冻结。
- 1176 读响应停点不要猜修；板级若仍停 1176，只用 v4 #44–#50 判 H2/H4。

## 3. 执行顺序（严格）

1. **W1 复现（≤25 min）**：用独立反例 TB/checker 对 b11 r0 冻结源复现 `DUT_FAIL_VALID`，落 `r0/diag/r1-root-cause.md`；clean 必须先 PASS，故障前置必须命中（7 拒收含 LAST、writer/slot 卡住、两好帧被拒）。
2. **W2 修复（≤30 min）**：按 dev-plan §3 只改两文件；坏帧不发布、槽归还、下一好帧恢复。
3. **W3 定向+回归（≤35 min）**：T1–T10；P1 三黄金逐字节；v4 225 B；三帧小几何 PASS；full 两帧 129600/enc=2/exported=2；b11 read 九例不回归。
4. **W4 构建**：复制 b11 td 脚本，`a1_board.al` 只改 `<File Path>`；综合≤3、布线≤2、1 bitgen+1 CWC；Routed 0 违例；WNS 按 §6 裁决（预裁决：关键路径仍在 vendor DDR PHY 时，+0.015 可接受并记 caveat；<+0.015 或任何违例即停）。
5. **W5 板级（条件）**：先 FTDI 预检。**不在位 → board=blocked，0 下载、0 COM8、不重试**；在位 → 先下载 1 次 SRAM，释放 FTDI，再开 COM8 150 s，目标 `enc_frames/exported` 增量>0 且 ≥1 帧四 CRC+zlib。

## 4. 硬约束

- 只写 `run/T10.b12-r1-last/**`；源先复制到 `r0/changed-src/`；`work/b10-gap-sim-20261025-132023/**` 只读，不改、不覆盖。
- 不改 reader FSM、`a1_ddr_arb2.v`、`p2_ddr_bridge.v`、DDR 四槽布局、44 B 帧头/CRC、crop 几何、UART_DIV/HB_DIV、引脚/SDC/时钟、v4 LEN/VER/225 B。
- 不改 upstream、旧 run/证据/manifest、`workflow/tasks.json`；不 false path/multicycle/改 seed/降频/新增 ERAM。
- 不写 Flash、不 PCIe/RK、不做双路/G4；SRAM 下载 ≤1 次；不批量删除（只能一次删一个明确路径，需批量先问用户）。
- 预算：开发 **120 min / 60 calls**；TD **3 会话**、综合≤3、布线≤2、bitgen 1、CWC 1、下载 1、Flash 0。

## 5. 条件分支

- T2 修复后仍失败，或 T3–T7 任一出现坏帧发布/槽泄漏/两 WRITE → **停止**，不 bitgen、不下载，交规划。
- 需要第二个 bitstream，或修复需要改 reader/bridge/arbiter/DDR IP → **停止交规划**，不自行扩预算。
- 布线 WNS <+0.015 或任何负 slack/违例 → **停止**，不 bitgen、不下载。
- FTDI 不在位 → `board=blocked` 是本包的合法完成，不是 FAIL；result 写清 `FTDI_0403:6042_absent`、下载 0 次。
- 板级仍 1176 停点 → 用 v4 判 H2/H4，写进 result；**不把 R1 修复与读停点混为一个结论**，本包不修 DDR/PAXI。

## 6. 恢复文本

> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 **`T10.b12-r1-last` r0**（ready；1 bitgen+1 CWC；SRAM 下载 ≤1，FTDI 不在位则 board blocked）。
> 先读 `T10.b12-r1-last/{dev-plan.md,handoff.md,dispatch.json}`、`T10.b11-aplus-read/r0/CANDIDATE-MANIFEST-b11-aplus-read-r0.json`、
> `work/b10-gap-sim-20261025-132023/{README.md,r1-loss/result.md,r1-loss/attempt1-slowcam/result.json,r1-loss/check_r1.py}`。
> 先复现 R1：FIFO 拒收 7 组（含 LAST）→ 释放背压 → writer/slot0 卡 WRITE、`raw_abort_cnt=0`、两好帧被拒；
> 只改 `camera_a1_uart_top.v`（拒收即 sticky loss-abort；消费无主 stray beat）与 `a1_ddr_slot_store.v`（abort 压过同拍写；abort+begin 同拍释放旧槽并接收新帧）；
> 再跑 T1–T10、P1 三黄金、v4、full、read 九例；1 bitgen+1 CWC（Routed 0 违例、WNS 按 §6、ERAM+CWC≤300）；
> 板级先 FTDI 预检；不在位即 board=blocked/0 下载；在位则先下载后开 COM8，150 s，目标 `enc_frames/exported` 增量>0 且 ≥1 帧四 CRC+zlib。
> 120 min/60 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 1；失败即停，不自扩预算，不批删。
