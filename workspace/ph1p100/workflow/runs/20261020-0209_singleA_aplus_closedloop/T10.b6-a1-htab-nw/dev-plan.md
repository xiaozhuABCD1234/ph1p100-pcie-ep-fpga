# b6 收尾（2026-10-24，规划）

**判定：PASS（带 caveat），r0 首次验收通过，实际修复轮次 0（round1—3 未使用）。**
独立综合测试者报告：`test-reports/T10.b6-a1-htab-nw-r0-integrated.md`。
吞吐回归已修复：P2 comp 由 b5 的 374,461 cycles / 76.91 MB/s 回到 **355,261 cycles / 81.067 MB/s**（≥ 77.76 门槛）。

## 1. 验收结果（规划登记）

| 项 | 结果 |
|---|---|
| P2 comp | 355,261 cycles；50,310 B；SHA256 `2601d57c…a7c05`；zlib/strict 0 差异；`stat_matches=19,200`，355,261+19,200=374,461 与 r5 回归量吻合 |
| P2 rand | 161,479 cycles；SHA256 `54f262f2…496dd`（≤161,479 门槛满足） |
| P1 三例 | micro8x2 `fa513a2b…`、mid64x8 `ee61e620…`、full_grad `b992a8ad…` 三例逐字节等于 r4 金标（金标链 r4=b5=本轮） |
| 负对照 | r5 core 同 TB 同向量 = 374,461 cycles、同一流 SHA，差值恰为 +19,200 → 判据能区分“去掉/未去掉等待” |
| Routed | 0/19,779 违例；SWNS **+0.119 ns**；STNS 0；hold **+0.020**/HTNS 0；Period +2.200 |
| 结构 | `htab_p3v→bm_b.addrb` 路径块 b6 = 0（r4 = 8），`bm_b_spec` 出现 0 次；两条残留相关路径均为 hold +0.021 |
| 资源 | ERAM 102/300、slice 22,608/71,680、LUT6 18,743、reg 25,135、DSP 0 |
| 候选 | bit `a2757d40…ffa2`（5,224,022 B）、cwc `dc477c8f…dc57`（110,168 B）、bid `2bf011c5…d730`（96,813 B）；compiled==parent 逐字节 |
| 下载/Flash | 0 次；G4 not_run |
| 冻结 core | `r0/changed-src/a1_deflate_core.v` `6797db05…35bb`，80,196 B；manifest `2e9fd356…8880` |

## 2. 规划裁决：接受设计指南 §4.1 的实现偏差

测试者 §7.3 指出开发未采用“提前一拍 htab p3v 影子读”，改用“`htab_b3` 第 4 字节携带 `bm[ref+3]` + 删除投机 `bm_b` 读”。规划裁决：**接受**。

- 冻结的门槛没有被放宽：编译周期、字节 SHA、Routed 零违例、WNS、bit/CWC、下载禁令全部按原样验收。
- 指南中的“首选方案”是实现建议，不是可验收门槛；实际方案已独立验证目标结构性质（`bm_b` 地址锥只由 flop 驱动、`htab_p3v→bm_b.addrb` 端点组消失）。
- 记录为“等价实现（已接受）”，不记为偏差遗留；后续如需回退，仍按本包 §7 换 `changed-src` 另开新包。

## 3. 必须继承的 caveat（不得淡化）

1. 综合 SWNS **+0.280 < +0.3**（dev-plan 事先允许，最终门槛在 Routed）。
2. Routed **+0.119** 落在 +0.05…+0.20 薄余量区，仅高于下限 0.069 ns；hold 仅 **+0.020**。上板/温压/批次变化风险高于常规，板级阶段优先观察，不得宣称大裕量。
3. 边界用例 `odd8x3`/`random64x8` 为开发证据复用（PASS_EXPLORATORY），未由测试者重跑，不参与 PASS 门槛。
4. CWC 物理 ERAM 覆盖未独立读回重算（`td_rerun=0`），只验证同 DB 会话 + 单次导出 + compiled 一致。
5. G4/板级 not_run：本 PASS **不证明**上板功能、相机 `cap_frames=0`、P3 或整机行为。
6. 测试台 `tb_camera_a1_uart_top.v` 的 `out_path/stat_path` 限 128 字符，路径过长会 `TB_OPEN_FAIL`（工具限制，非 DUT 缺陷）；后续测试者用短目录。

## 4. 任务状态

- **T10.b6-a1-htab-nw = PASS / done**（吞吐回归关闭）。该子包不再派发。
- **T10 父任务仍 blocked / 未 done**，原因不在吞吐：需求二（真实 RAW/参数）与需求三（板级端到端）未完成，且板级诊断暴露相机前端 `cap_frames=0`。
- b6 候选可用于后续板级诊断的“A1 链路基线”，但**不得**把 b6 的 G2/G3 PASS 表述为上板通过。

---

# T10.b6-a1-htab-nw 开发计划（r0）

日期：2026-10-24。规划：本轮唯一正式包；两级（需求→工作包）；5 项语义步骤。状态：ready。

## 1. 任务表

| task_id | 问题/产物 | 工作树/允许写路径 | 依赖 | functional | engineering | system | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| T10.b6-a1-htab-nw | r5 每 match +1 拍等待导致 P2 comp 374,461 cycles / 76.91 MB/s；去掉等待、保持字节不变，回到 355,261 cycles | 新包 `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw/**`；只改 `r0/changed-src/a1_deflate_core.v`；TD 工程在 `r0/td/**` | r5 core `29b1e3e1…`；r4 金标 `d4b79961…`；P2 向量；b5 r0 TD 模板 | P2 comp/rand、P1 三例、8×3/64×8 边界 | Routed 0 违例、WNS ≥ +0.05、hold/period/资源/关键路径 | 接口/协议/帧/CRC/DDR/SDC/UART 不变；板级 not_run（不下板） | G0/G1/G2/G3 | **PASS / closed**（r0） | 无（已由独立综合测试验收；T10 父任务仍 blocked） |

## 2. 五项语义实现步骤（每步可独立复核）

1. **搭包与冻结起点**：建 `r0/{changed-src,sim,td}`；从 b5 r0 复制 r5 core（校验 SHA `29b1e3e1…`），从 b5 r0 复制 TD 模板（只改 core 路径）；记录所有输入 SHA、工具版本、盘符。
2. **实现无等待扩展**：按设计指南 §4.1 增加提前一拍的 htab p3v 影子读（必要时加 `bm_a_rd3`），保留 `bm_b_spec_q` 与 flop-only `bm_raddr_b`；恢复 r4 的 hit 拍首字节比较和 `ext_raddr=p3_r+2 / ext_faddr=hf_r+2`；删除 `ext_first` 等待拍。影子写/清/旁路与主表逐项对齐。
3. **P2 核级验收**：用同一 comp/rand 向量、`+BP=0 +GAP=0` 跑 ModelSim；comp 必须 **355,261 cycles**、流 SHA `2601d57c…a7c05`、zlib/strict 0 差异；rand 必须 SHA `54f262f2…496dd`、cycles ≤161,479。不过则回 RTL，不进 TD。
4. **P1 与边界回归**：P1 三例逐字节对 r4 金标（`fa513a2b…` / `ee61e620…` / `b992a8ad…`），记录 cycles（应回到 r4 的 3,809 / 5,172 / 6,421,414）；复测奇数尾块 8×3、随机 stored 64×8 的 core 相关项；双路同步/负对照未改，注明复用理由。
5. **工程与候选冻结**：TD `01_build.tcl`（syn+route，冻结策略组同 b5 r0）→ Routed 门槛 → `02_bitgen.tcl`（1 次，fail-closed）→ `03_cwc.tcl`（1 次）；写 `CANDIDATE-MANIFEST`、`result-r0.md`、`lessons-r0.md`、`artifact-hashes.txt`；停止修改后交综合测试。**本轮不下载。**

## 3. 检查项矩阵

| 维度 | 必须检查 | 证据 |
|---|---|---|
| functional | P2 comp cycles/SHA/zlib/strict；P2 rand SHA/cycles；P1 三例逐字节+stats；8×3、64×8 边界；无 X/半帧 | `r0/sim/` 日志、stats、dec/hex、`p2-regression.json`、`p1-regression.json` |
| engineering | 综合报告；Routed setup/hold/period/TNS/违例端点；关键路径组（确认 `htab_p3v→bm_b.addrb` 消失）；LUT/REG/ERAM/slice；组合环/无时钟网；STA coverage | `r0/td/syn_gate_timing.rpt`、`routed_timing.rpt`、`routed_qor.rpt`、`routed_area.rpt`、`routed_check_timing.rpt` |
| system | 端口/协议/帧/CRC/DDR/SDC/UART 状态包不变；bit/CWC 一致；板级/下载 not_run 及理由 | diff、manifest、bit/CWC SHA、`result-r0.md` |
| G0/G1 | 字节/格式/CRC/长度/边界 | 同上 |
| G2 | Routed 0 违例、WNS ≥ +0.05、TNS 0、hold ≥0、period 0、资源在器件内 | 路由报告 |
| G3 | 1 bitgen + 1 CWC；`compiled.bit`=`a1_board.bit`；`compiled.cwc`=cwc | bit/CWC/BID SHA |
| G4 | 不适用（无下载/无板级授权） | 明确 not_run |

## 4. 阈值与判定

- **PASS 必要条件**：P2 comp 355,261 且 SHA 一致；P1 三例逐字节；rand SHA 一致；Routed 0 违例且 WNS ≥ +0.05；bitgen/CWC 各 1 次且哈希记录。缺一即 FAIL，不得用“功能对但慢一点”换 PASS。
- 允许的 caveat：Routed WNS 在 +0.05…+0.20 之间；综合 SWNS < +0.3（b5 r0 为 +0.222，仍可进入布线）；板级 not_run。caveat 必须写入 manifest 与 result，不得口头淡化。
- 不允许：改 SDC/false path/multicycle/clock、seed sweep、降频、改阈值、减少 match、改输出、改帧/CRC/DDR、下载/Flash。

## 5. 预算与停止

| 项 | 上限 | 说明 |
|---|---|---|
| 开发 | 90 min / 50 calls | 单会话；超时/超调用主动 blocked |
| TD | 3 sessions / 150 min | S1 syn+route；S2 bitgen；S3 CWC/应急 |
| 综合 | ≤3 次 | 优先 1 次；失败仅允许因 RTL 变化重跑 |
| 布线 | ≤2 次 | 第 1 次失败后仅允许一次 RTL 修正 + 第 2 次；不调 QoR 旋钮 |
| bitgen | 1 次 | fail-closed |
| CWC | 1 次 | 与 bit 同候选 |
| 下载 | 0 次 | 用户明确本轮不下载 |

停止条件（任一）：
- P2 comp 不能同时满足 355,261 与 SHA 一致，且 90 min 内无法定位 → 停止，保留 FAIL 证据，不进 TD。
- 综合为负或布线第 2 次仍 WNS < +0.05/有违例 → 停止，交规划；不得放宽门槛。
- 缺少 ModelSim/TD/许可/磁盘/真实工具 → blocked，附恢复入口；不空转。
- 任何需要改 SDC/协议/帧/CRC/DDR/下载的动作 → 停止，交规划/用户。

## 6. 交付物

- `r0/changed-src/a1_deflate_core.v`（唯一 RTL 变更）+ `r0/rtl-diff-r0.patch`
- `r0/sim/`：P2 comp/rand 日志、stats、流、`p2-regression.json`；P1 三例捕获、stats、`p1-regression.json`；边界证据
- `r0/td/`：`01_build.tcl`/`02_bitgen.tcl`/`03_cwc.tcl`、synth/route 报告、`a1_board.bit`、`a1_board.cwc`、`a1_board_inst.bid`
- `CANDIDATE-MANIFEST-b6-a1-htab-nw-r0.json`、`artifact-hashes.txt`、`result-r0.md`、`lessons-r0.md`
- 停止修改后的唯一输入清单；综合测试只按该 manifest 验收

## 7. 回退

- 若影子读方案在 90 min 内无法同时满足周期与字节一致，回退到 r5 core（`29b1e3e1…`）并保留本包 FAIL 证据；不得把 r5 当 PASS（吞吐已 FAIL）。
- 若 TD 失败，保留 b5 r0 的 bit/CWC 作为历史候选，但不得声称 b6 已上板；b6 无 bit/CWC 即 G3 not_run。
- 任何回退只替换本包 `changed-src`，不动 b5 r0/upstream。

## 8. 下一动作

主按 `dispatch.json` 派 **fpga-dev**，输入本计划 + `fpga-design-guide.md` + `handoff.md`；开发完成后在同一包内冻结 manifest，再由主新建 **一个** 综合测试者（独立于开发）按同一 manifest 验收；同任务 FAIL 才续原开发/原测试，最多三轮实际修复。
