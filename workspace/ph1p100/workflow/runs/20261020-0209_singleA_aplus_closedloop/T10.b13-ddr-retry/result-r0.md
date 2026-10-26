# T10.b13-ddr-retry r0（b13b 续跑）— result（开发自检，非综合测试结论）

- 日期：2026-10-25；run `20261020-0209_singleA_aplus_closedloop`；包 `T10.b13-ddr-retry` r0
- **status = blocked**（功能仿真在最终 RTL 上 PASS；但 1 次 bitgen/CWC 已在最后一次 RTL 修复前用掉，
  最终 RTL 没有可用 bit；板级相机链路本会话无有效像素）
- 父任务 T10 仍 blocked；本包不关闭 T10
- 本轮目标：修掉"丢 R → 超时 → 重试"整链死锁并完成验证/构建/板级

## 1. 本轮修复（只动允许的 2 个 RTL + 测试台）

| # | 文件 | 修复 |
|---|---|---|
| 1 | `a1_ddr_slot_store.v` | 超时后 store 在 `R_AR/R_GUARD` 持续 `rready`（排空模式，数据只在 `R_RW` 锁存）；`RETRY_EN=0` 时行为不变 |
| 2 | `p2_ddr_bridge.v` | 整个 abort/guard 窗口（不只 4 拍 purge）不装载 skid、持续排空 RF |
| 3 | `p2_ddr_bridge.v` | **AF 写使能改为握手限定** `af_push = s_arvalid && s_arready`（原接请求电平，guard 期间每拍写入同一地址，AF 被 addr0 副本填满） |
| 4 | `camera_a1_uart_top.v` | 超时后 `orphan_drain` 窗口：消费 A+ 核孤儿输出字（`a1_out_ready` 握手）但 `wr_valid` 门控不写槽，16 拍后 abort 压缩槽（修复 1080p 重试永不启动） |

超时/重试预算未放宽：`TIMEOUT_N=8192`、`GUARD_N=32768 clk_a1`、`MAX_RETRY=2`、bridge guard 65536 clk_ddr、
A1 `s_arready` 门控 70000 clk_a1 全部保持。

## 2. 功能仿真（最终 RTL）

### 2.1 强制定向（64×8 整链，生产默认超时参数）

| 用例 | 结果 |
|---|---|
| clean | PASS：exported=1，exp_bytes=666，四 CRC+zlib+独立参考全过，timeout/retry/giveup/stale=0 |
| drop1（word 16 丢 R） | **PASS**：timeout=1 retry=1 giveup=0，exported=1，四 CRC+zlib 全过 |
| late1（晚 12000 拍） | **PASS**：timeout=1 retry=1 stale_guard=1，exported=1，晚到 R 未进入重试流 |
| three_f2（3 帧，仅第 2 帧丢 R） | **PASS**：exported=3、ID 不同、四 CRC+zlib；计数恰 1/1/0；第 1/3 帧 stale=0 |
| budget（首帧每次 AR 丢 R） | **PASS**：timeout=3 retry=2 giveup=1；该帧不发布/不导出、槽 FREE；下一好帧导出 |

### 2.2 单元 / 结构

| 用例 | 结果 |
|---|---|
| store clean/retry/guard/budget | 全 PASS（guard：`TB13_GUARD cycles≈128 ar=0 open_ready=0`；budget 3/2/1） |
| v5 状态包 | PASS：3 包，241 B / 59 字段 / VER=5 / LEN=241 / XOR 0..239，字段值逐一比对 |

### 2.3 回归（最终 RTL）

| 项 | 结果 |
|---|---|
| b12 R1 clean/loss | PASS（两好帧恢复、故障帧不发布、槽 FREE） |
| t7（SOF 拒收/头阻塞排空） | PASS |
| b12 store T3–T6 | 全 PASS |
| multi control/triple（3 帧） | PASS（3 帧、3 状态包、distinct raw SHA） |
| P1 三黄金 | **逐字节相同**：micro8x2 `fa513a2b5a7f268b…`、mid64x8 `ee61e6200d9abca6…`、full_grad `b992a8ad74063545…` |
| b11 read 用例（one/multi/bp/late/stray/dup/reset/full） | 全 PASS：`read_full=129600/129600`，其余 2000/9000 字全对 |
| full 两帧（1920×1080 真核） | PASS：`read=259200`、`enc=2`、`exported=2`、`dup=0`、`wd=0`、bridge ar=r=rlast=261704（`sim-results-b13-main2.json`） |
| **full 丢 1 R（1920×1080，word 60000）** | **PASS**：timeout=1 retry=1 giveup=0；read_words=189600（60,000+129,600），exported=1，exp_bytes=2,594,706，四 CRC+zlib+独立参考全过，dup=0，drain_words=0；`dq_end=0`（`sim-results-b13-fullchain.json`） |

全帧丢 R 用例的测试条件：`UART_DIV=1`（板上为 1628）、`STA_DIV=25000`、`MAX_CYCLES=60M`。
2.59 MB 的压缩流在物理 UART 上需要 2.59M×10 = 26M clk_a1，`UART_DIV=4` 时 104M 拍不可能在
20M 拍预算内导完（首轮全帧用例因此被看门狗截断，只证明到"重试重启 + 帧发布"）。
测试台只改速率/上限，不改帧/CRC/zlib 判据；`check_b13.py` 的流长上界从 `raw+256` 放宽到
`raw+4096`，覆盖不可压缩随机数据（2,594,706 = raw+2,706）的 deflate 存储块开销。

- 全部链/回归 JSON：`r0/sim/sim-results-b13-{chain,store,status,regress-final,main2,fullchain}.json`
- 帧头/CRC/压缩字节未变（P1 三黄金逐字节一致）

## 3. 重建与候选（关键 caveat）

| 项 | 值 |
|---|---|
| 综合 | SWNS=+0.246，slice 18,731，ERAM 72，reg 19,923 |
| 布线 | **SWNS=+0.003 / HWNS=+0.020 / 0 违例 / 26,391 端点 / ERAM 102（≤300）** |
| bitgen | 1 次：`r0/td/a1_board.bit` SHA256 `56A01332…22EF` |
| CWC | 1 次：`r0/td/a1_board.cwc` SHA256 `684009FF…BEC5`；`cw/compiled.{bit,cwc}` 与父件逐字节相同 |
| BID | `r0/td/a1_board_inst.bid` SHA256 `ED634379…CE01` |
| 时序裁决 | WNS=+0.003 落在预裁决 +0.003…+0.05，`timing_caveat=thin_margin_+0.003`（诊断候选，非生产签核） |

**caveat（必须交给规划）**：上述综合/布线/bit/CWC 是在 `camera_a1_uart_top.v` 的 1080p 孤儿字修复
**之前**生成的；修复后最终 RTL 与布线数据库/bit 不再对应。按冻结的"1 bitgen + 1 CWC，第二次 bitgen 即停止"
规则，本轮**没有**对最终 RTL 重新 bitgen，因此**没有可下载的最终候选**。

## 4. 板级

- COM8 已重新枚举（FTDI `VID_0403&PID_6042` 三节点 OK）。
- **1 次 SRAM 下载成功**：`B13_DL_DEVICE=PH1P100`、`PRG-2014 Chip validation success`、`B13_DL_OK`（184 s）。
- 随后 COM8 150 s：36,150 B、**150 个合法 v5 包（bad_xor=0）**、A1U1 帧 0。
- 状态字段：cap=0、raw_pub=0、enc=0、exported=0、**timeout/retry/giveup=0**、ar=r=0；
  相机前端 `pix_beats=0`、`line_rises=0`、`vs_tgl` 仅 0→1，而 `clk_tgl/pkt_tgl` 持续增长 → **CSI-2 没有解出有效视频行**。
- 结论：板级未进入本包目标故障（A1 读通路从未启动），属相机链路/会话问题；且下载的 bit 是过期候选。
  按 dev-plan §7.3："exported=0 且 timeout 不增长 → 保留 v5 证据交规划，不猜修"。未做第二次下载、未写 Flash。
- 证据：`r0/board/board-run-b13b.md`、`r0/board/captures/`、`r0/board/log/`。

## 5. 为什么停在这里

1. 功能：最终 RTL 的丢 R 超时/重试在 64×8 与 1920×1080 两种几何都通过；未发布半帧、未泄漏槽、晚到 R 不污染。
2. 工程：1 次 bitgen + 1 次 CWC 已用，且产生于最后一次 RTL 修复之前；按冻结规则不得第二次 bitgen。
3. 板级：相机本会话无有效像素，且 bit 过期；即使再下载也无法验证重试。

## 6. 下一轮（规划决定）

- 用**最终 RTL**（当前 `r0/changed-src`，含 §1 的 4 处修复）重新跑 1 次综合/布线（WNS 目标 ≥+0.05，
  0 违例且 ≥+0.003 可接受并记 caveat），再做 **1 次 bitgen + 1 次 CWC**，然后 1 次 SRAM 下载 + COM8 150 s。
- 板级前先确认相机链路：本会话 `pix_beats=0`/`line_rises=0`，需要用户检查相机供电/连接或重新上电，
  否则板级仍无法进入丢 R 故障。
- 复测清单：`r0/sim` 全量（chain/fullchain/store/status/regress-final/main2）+ 新 bit/CWC 哈希 + 板级 v5。
