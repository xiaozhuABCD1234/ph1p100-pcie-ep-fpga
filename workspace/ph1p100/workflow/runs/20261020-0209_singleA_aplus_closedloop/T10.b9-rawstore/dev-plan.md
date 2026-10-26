# T10.b9-rawstore 开发计划（冻结）

## 0. 本轮目标（唯一主要可验收目标）

在 b8「crop 全通但 raw 落盘 0 发布」的现状上，**让状态包 v3 能唯一定位 raw 写入卡在哪一拍/为什么没发布，并当轮修掉已静态证实的 4 个缺陷**，然后用 1 个 P2 候选 + 1 次 SRAM 下载回答：修复后 raw_pub/enc_frames/exported 是否 >0；>0 则按 44 B 头+CRC+zlib 解码。

排除：crop 几何、MIPI/I2C、图像帧格式、SDC/引脚、Flash、预览通路。

## 1. 任务表

| task_id | 问题/产物 | 实际工作树/允许写路径 | 依赖 | functional | engineering | system | 必要G层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| T10.b9-rawstore | raw 落盘 0 发布：核对契约 + 4 bug 修复 + 状态包 v3 + P2 候选 + 1 次板级取证 | 仅 `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b9-rawstore/**`（源码改 `r0/changed-src/` 与 `r0/td/src/` 副本） | b8 crop 几何结论、b8 P2 工程与 P1 黄金样例、b8 v2 解析脚本 | 全尺寸真实几何 2 帧逐字节落盘；abort/无空 slot/短帧三负例；F3 的 ddr_rdy 负例；P1 三黄金样例回归；v3 包字段与 XOR | Routed 0 违例、WNS≥+0.05、TNS 0、hold 0、period 0；1 bitgen + 1 CWC；资源不越 b8（±5%）；快照路径不新增跨域多位 | 1 次 SRAM 下载（先开 COM8）+ 90 s 采集；v3 解析四选一判定；raw/enc/exported 三目标 | G0/G1/G2/G3/G4 | ready | 派 fpga-dev（batch=1，本包内含 W1–W4） |

工作包（同属本 task，1 个开发连续做，顺序固定）：

| 包 | 内容 | 语义实现步骤（≤5） |
|---|---|---|
| W1 diag-v3 | 计数与观测 | ① `a1_ddr_slot_store.v` 增 24–41 号计数/电平输出（默认 0，P1 不受影响）；② `camera_a1_uart_top.v` 增 `i_ddr_rdy` 与 `o_st_raw_*` v3 总线，按第 5 节接线；③ `dbg_uart.v` 打包升 v3（ver=3、len=177、43 字段、XOR 同规则）；④ `p2_a1_board_top.v` 用 22 个 64b mailbox 快照送 43 字段（`snap_en` 单拍锁存）；⑤ `parse_status_v3.py`（复制 v2 脚本改 ver/len + 新字段名）。 |
| W2 fix | 4 缺陷修复 | ① F1 abort-beat 跨域 + store 清 slot + `raw_abort_cnt`；② F2 无空 slot 整帧丢弃（`skip_frame`，不冻 FIFO、不溢出）+ `fifo_ovf_cnt`；③ F3 `p2_ddr_bridge` 读引擎 `paxi_arvalid` 加 `ddr_rdy`、`af_pop=paxi_arvalid&&paxi_arready`，写通道握手复核；④ F4 raw store `ddr_ready` 接真实就绪；⑤ 格式/长度断言不变（2,592,000 B / 129,600 字 / 480 beat/行）。 |
| W3 TD | P2 候选 | ① `01_build.tcl` 改指本任务源；② 综合（≤2）；③ 布线（≤1）Routed 0 违例、WNS≥+0.05；④ 1 bitgen + 1 CWC；⑤ `CANDIDATE-MANIFEST-b9-rawstore-r0.json` + `artifact-hashes.txt`。 |
| W4 board | 1 次取证 | ① 先开 COM8 再 `download_sram_b9.tcl`（1 次 SRAM）；② 90 s 采集 `com8_90s.bin`；③ v3 解析 → 第 4 节四选一判定；④ 若 exported>0 按 44 B 头+CRC+zlib 解码并存证据；⑤ `result-r0.md` + `lessons-r0.md`。 |

依赖顺序：W1 → W2 →（G1 全绿）→ W3 → W4。W1/W2 的改动必须先通过 G1 才能开工 W3；G1 红即停，不消耗 TD/板窗。

## 2. 各包检查项与不适用理由

- W1 functional：`tb_status_v3`（字段数/顺序/长度/XOR/版本）+ `tb_status_v3_snapshot`（单拍快照一致性：注入递增计数，包内 43 字段必须同拍、无撕裂）。engineering：综合后新增寄存器不引入 clk_a1→sys50 多位直通（每字段独立 mailbox 或握手）。system：解析脚本对 90 s 实流 bad_xor=0、bad_len_ver=0。
- W2 functional：① 全尺寸 2 帧落盘（129,600 字/帧、2 次 publish、len=2,592,000、0 drop/0 err，地址 = base+slot 偏移）；② abort 负例（ROI 中途撤 in_frame → 该帧不发布、`raw_abort_cnt=1`、slot 回 FREE、**下一帧照常发布**）；③ 无空 slot 负例（连续 3 帧只读不走 → 第 3 帧整帧丢弃、`raw_begin_deny=1`、`fifo_ovf_cnt=0`、不产生半帧写入）；④ F3 负例（读中 `ddr_rdy` 拉低 N 拍 → 每字恰一次 AR 握手、无丢 AR、无重复 rdata，读完 129,600 字）；⑤ 短帧负例（少一个 beat → 不发布、`raw_drop+1`）。engineering：不新增跨时钟组合路径；`p2_ddr_bridge` 仍单拍、无 burst/B 通道依赖。system：不适用（本包不上板）。
- W3 engineering：Routed 0 违例、WNS≥+0.05 ns、TNS 0、hold 0、period 0、无未约束路径新增；LUT/FF/BRAM 相对 b8 增幅 ≤5%（v3 计数器 + 22 mailbox 预计 +3~4 k FF，如实记录）。functional：bit 与 netlist/源码哈希绑定。system：候选唯一、bit/CWC/BID 独占。
- W4 functional：v3 四选一判定必须给出唯一结论与对应计数；raw_pub/enc_frames/exported 三目标；若 exported>0 则 44 B 头+CRC+zlib 解码通过（图像尺寸 1920×1080）。engineering：下载日志含 bit 哈希、CWC 一致。system：1 次下载、先开 COM8、90 s、失败不二次下载。

## 3. 门槛（全部可测）

**G1（仿真，硬门）**：W2 的 5 项 + W1 的 2 项全绿，且 b8 P1 三黄金样例（`fa513a2b…cef`/`ee61e620…789`/`b992a8ad…da9`）逐字节不变、`err/raw_drop/cmp_drop/geom/dup=0`。

**G2（工程，硬门）**：Routed 0 违例、WNS ≥ +0.05 ns、TNS = 0、hold 违例 0、period 违例 0；1 bitgen + 1 CWC；候选 manifest 绑源码/网表/bit/CWC SHA256。

**G3（板级，本轮主门）**：
1. **诊断门（必须满足，独立于是否修好）**：v3 包能按第 4 节表唯一定位 A/B/C/D 之一，并给出对应计数三元组；报告须写出"卡在哪一拍/为什么没发布"的一句话结论。达不到即本轮 FAIL（观测不足）。
2. **修复门**：`raw_pub>0` 且 `enc_frames>0` 且 `exported>0`（90 s 内）。达到 → 按 44 B 头 + CRC + zlib 解码并给图像/尺寸证据。
3. 部分达成（`raw_pub>0、enc_frames>0、exported=0`）记 ⚠ 未通过但保留候选与证据，写清导出/带宽原因，不二次下载。
4. `crop_geom_err=0`、`crop_short=0` 必须保持；`errors` 若增长须给出原因。

**G4（收尾）**：`result-r0.md`（含四选一判定、计数表、三目标、解码结论）、`lessons-r0.md`、manifest/hashes 齐备；tester 独立报告绑同一 manifest。

## 4. 判定口径（复述设计指南第 4 节，tester 直接用）

| 结论 | 判据 |
|---|---|
| A 读已打开但 DDR 不回数 | `raw_rd_open_ok>0`、`raw_ar_valid>0`、`raw_rv_cnt=0`，`rd_state=R_RW` |
| B 读连 AR 都发不出 | `raw_rd_open_ok>0`、`raw_ar_valid>0`、`raw_ar_hs=0`，`rd_state=R_AR` |
| C 读根本没打开 | `raw_rd_open_ok=0`，`rd_state=R_IDLE`，看 `raw_rd_state` 里 `a1_busy/a1_out_valid/raw_rd_open_ready/cmp_begin_ready/fstate` 谁卡 |
| D 写侧没起来 | `raw_begin_ok=0`、`raw_wr_beats=0`、`raw_pub` 不涨 |

## 5. 预算与停止条件

- 开发：**120 min / 60 calls**（含仿真、TD、板级）。TD 3 会话、综合 ≤2、布线 ≤1、bitgen 1、CWC 1、**下载 1**、Flash 0。
- 综合测试者：45 min / 30 calls，0 次 TD 重跑、0 次下载（只复算/复解析同一冻结输入）。
- 停止：G1 红即停；TD 布线违例即停（不反复跑）；下载后无论结果如何**均不二次下载**；缺 COM8/板卡/工具即 blocked 交回规划。
- 重试：同失败命令首次 + 1 次有新证据的重试；连续 2 次无进展 → blocked。

## 6. 回退

- RTL 回退点：b8 候选 `T10.b8-crop-geom/CANDIDATE-MANIFEST-b8-crop-geom-r0.json` + `r0/changed-src/*`（bit/CWC 哈希已绑）。
- 若 W2 任一修复在 G1 无法证明安全，**只回退该条修复并保留 v3 观测**，本轮仍以诊断门交付（G3.1），不得为凑 PASS 保留未证明的改动。
- 板级失败不删证据；`r0/board/**` 全留。

## 7. 后续主题（本轮不做）

1. 若判定为 A/B（DDR 读通路）：下一轮独立任务修 PAXI 读时序/加读超时看门狗与 slot 回收（需新冻结）。
2. 若判定为 C 且卡在 `a1_busy`：下一轮查 A+ 帧顶启动条件与压缩使能。
3. 导出带宽：115200 下整帧 2.6 MB 传输时间过长，后续单独评估提高波特/分块导出。
