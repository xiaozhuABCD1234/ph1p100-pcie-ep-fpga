# T10.b10-b9-fix r0 -- result（开发角色，未通过 W2/W3；**blocked**）

- run：`20261020-0209_singleA_aplus_closedloop`；包：`T10.b10-b9-fix`（父 T10 **未**置 done）
- 开发角色：general 代行 fpga-dev；日期 2026-10-25
- 结论：**B9-01 / B9-02 / B9-03 已在离线证据上修复并通过针对性回归 + P1 三黄金样例；
  W2（TD 候选）与 W3（板级）未完成，状态 blocked。没有可下载的有效 bit。**

## 1. 一句话状态

| 包 | 门槛 | 结果 | 证据 |
|---|---|---|---|
| W1 fix+sim | G1 | **基本绿**：B9-01/02/03 + R2/R3 + P1 三黄金通过；**R1 未覆盖**；3 连续真实压缩帧用例失败（自建 TB 缺陷） | `r0/sim/logs/`、`r0/sim/sim-results-b10.json` |
| W2 TD | G2 | **blocked**：TD 综合/布线预算（synth 3/3、route 2/2）已用尽，且最后一次（s3）构建所用源码含一个**已定位并修复**的声明缺陷（`crop_pix` 丢失位宽），该网表不可用；**无有效 bit/CWC** | `r0/td/build_console_b10*.log` |
| W3 board | G3 | **未执行**（无有效 bit，禁止下载） | — |

**因此本轮没有下载（download_used = 0/2），没有板级计数。**

## 2. RTL 变更（相对 b9 r0）

| 文件 | 变更 | 验证 |
|---|---|---|
| `a1_uart_export.v` | B9-01 帧间统一仲裁；B9-02 1-bit 环绕指针 + 单点 `dq_cnt` + 满/同拍策略 + 仿真断言 | `tb_b10_arb`（old/new 双库）、`tb_b10_export` 四用例 |
| `camera_a1_uart_top.v` | B9-03 `CMP_BASE` 131072→**262144** + 四槽容量/区间断言；`DDR_WORDS=2^24` 常量与来源注释；**另**：修复开发过程中被误删的 `wire [39:0] crop_pix;` 声明 | `tb_b10_layout`、P1 三黄金 |
| `p2_ddr_bridge.v` | R2 `W_IDLE` 启动加 `!wf_pop`（单字重复写）；R3 无未完成 AR 时吞掉 R | `tb_b10_r123` r2/r3 |
| `p2_a1_board_top.v` | 无功能变更（层次探针被 TD 拒绝，见 §7） | 综合日志 |
| `a1_ddr_slot_store.v`、`a1_raw_crop.v`、`a1_diag_mailbox.v`、`a1_deflate_core.v` | 未改，仅哈希冻结 | `artifact-hashes.txt` |

## 3. B9-01 修复验证（G1 第 1 项，PASS）

同一 TB 源（`r0/sim/tb_b10_arb.sv`）分别编译进两个库：`work`（本包 RTL）与 `work_b9`（未修改的 b9 exporter，SHA `dae0d47f…1312`）。

| 用例 | 配置 | 结果 |
|---|---|---|
| 旧版反例 | `+EXP=old -gSTATUS_DIV=5000 -gFRAME_BYTES=2000` | `B10_ARB_RESULT old_repro=1`：`exported=1`、`estate=E_IDLE`、`sstate=S_IDLE`、`sts_want=1`、`dq_cnt=1`、UART 空闲且字节数不再增长 → 旧死锁**复现** |
| 修复版 | `+EXP=new` 同配置 | `new_pass=1`：状态包在帧边界（offset 2044）发出、XOR 正确、第 2 帧（offset 2221）随后完成，`exported=2`、`errors=0`、`both_grant=0` |
| tick/出队同拍扫描 | `STATUS_DIV ∈ {3500,4000,4500,5000,6000,8000}` | 6/6 `new_pass=1`；无“同拍双获准”（`both=0`） |
| 状态期间持续排队 | `tb_b10_export wrap`（14 描述符，`STATUS_DIV=4000`） | 状态包只出现在帧间，帧内无插包，XOR 正确 |
| 非空队列不阻塞状态 / 最后一字节完成前不交接 | 结构性质 + 上述用例 | `frame_boundary` 含 `tx_ready && !tx_valid_r`；`grant_status`/`grant_frame` 互斥 |

## 4. B9-02 修复验证（G1 第 2 项，PASS）

| 用例 | 观察 | 结果 |
|---|---|---|
| `wrap` | 14 个描述符、3+ 次环绕；逐帧 44 B 头（magic/ver/len/id/W/H/长度/CRC 字段）与载荷逐字节比对；`dq_cnt≤2`；模块内影子计数 0 失败 | `pass=1`（14/14 帧，`asserts=0`） |
| `samecycle` | 满队列边界同拍 push+pop（`dq_push_ok&&dq_pop_ok`），计数保持 2，后续顺序/长度仍逐帧一致 | `pass=1`，`samecycle_cnt>0` |
| `reject` | 满队列且该拍无 pop → 拒收 1 次，**已接受**描述符一个不丢 | `pass=1`，`reject=1`，3/3 帧 |
| `empty` | 队列空仍能发状态包 | `pass=1`，2 包 |
| 逐拍断言 | `dq_cnt == 影子计数`、`dq_cnt≤2`、status/frame 不同拍 | `b10_assert_fails=0` |

## 5. B9-03 修复验证（G1 第 3 项，PASS）

**容量核对（记录来源，未猜）**：`r0/td/src/vendor/ip/ddrmc_x32/ddrmc_x32.v` 与 `.params_ddrmc_x32.txt`：
DDR3-1600 x32，`ROW_WIDTH=14`、`COL_WIDTH=10`、`BA_WIDTH=3`、`CS_WIDTH=1`
→ 2^14·2^10·2^3·32 bit = 4 Gbit = **512 MiB = 2^24 个 256-bit word**（`AXI_ADDR_WIDTH=29` 字节地址一致；
PAXI `MC_ADDR_WIDTH=27`，端口 26:0）。要求 ≥ 424,314 word，余量 39×。
`RAW AWB=18` → 262,144 ≥ 129,600；`CMP AWB=17` → 131,072 ≥ 81,085；无其他主设备占用 ≥262,144（顶层仅 `u_bridge` 驱动 PAXI）。
→ 容量门槛**满足**，未触发 blocked 条件。

| 用例 | 观察 | 结果 |
|---|---|---|
| 满尺寸四槽并发（新布局） | RAW0/RAW1 各 129,600 word、CMP0/CMP1 各 10,136 个 DDR word（81,085×4 B）；四槽全部读回逐字比对 | `pass=1`，`addr_err=0 ovl=0 data_err=0` |
| 旧布局反例（`-gCMP_BASE=131072`） | CMP 写入落入 RAW 区间 20,272 次；CMP 读回 162,170 个字全部不符 | `B10_LAYOUT_DONE ... ovl=20272 cmp_data_err=162170`（旧布局**必错**） |
| 区间断言 | `CMP_BASE ≥ RAW_BASE+2*RAW_WORDS`、`CMP_BASE+2*CMP_WORDS ≤ DDR_WORDS`、`SLOT_WORDS ≤ 2**AWB` | 仿真 `initial` 断言，`B10_LAYOUT_OK` |

## 6. 回归与其它用例

- **P1 三黄金样例（G1 第 6 项，PASS）**：`micro8x2` `fa513a2b5a7f268b…`、`mid64x8` `ee61e6200d9abca6…`、
  `full_grad`（1920×1080 真实压缩）`b992a8ad74063545…` **逐字节一致**，`err/raw_drop/cmp_drop/geom=0`。
  *注意*：P1 TB 的 `a1_ddr_model` 只有 262,144 word，装不下新布局的 CMP 槽（262,144…424,313），
  会把 CMP 写丢并读回 X。已把该 TB 模型改成 524,288 word（真实 DDR 是 2^24 word）后才得到一致；
  这是**测试模型容量**修正，不是 RTL 行为改变。
- **R2（PASS）**：单字写入，外部 `paxi_awvalid`/`paxi_wvalid` 各恰 1 次（两字共 2/2），
  AW/W 独立背压期间地址/数据稳定（`stable_err=0`）。修复前同一 TB 为 3 次 AW/W。
- **R3（PASS，边界有残余风险）**：AR 已握手未回 R → 业务复位 → 释放旧 R → 新 AR/R：
  `stale_seen=0`、`new_seen>0`。**未覆盖**：旧 R 晚于新 AR 才到达时仍无法区分（无 tag），需另立方案。
- **R1（未覆盖）**：丢 LAST→孤儿 writer 的定向顶层用例未能构造成功（自建小几何相机驱动只产出部分 ROI 行，
  首拍不带 SOF）。本轮尝试过的三处 R1 改动（丢拍触发 abort、无主数据拍丢弃、`raw_active` 延后释放）
  已**全部回退到 b9 语义**，以避免未经证实的改动进入候选；结论如实记为 `not_covered`，
  风险与复现线索见 `lessons-r0.md`。
- **3 连续真实压缩帧（未通过/未覆盖）**：`tb_b10_multi` 只跑出状态包（`frames=0, exported=0`），
  属自建 TB 的相机驱动缺陷，不是 RTL 判定；多帧/状态仅帧间性质由 `wrap`（14 帧）+ `full_grad` 覆盖。

## 7. 工程（W2）与板级（W3）：blocked

**TD 实际使用**：会话 3；综合 3（s1 综合失败：层次化 MARK_DEBUG 引用被拒；s2 成功；
s3 成功但源码含 `crop_pix` 声明缺陷）→ **综合 3/3 用尽**；布线 2（s2、s3）→ **布线 2/2 用尽**；
bitgen 0、CWC 0、下载 0。

| 构建 | 综合 SWNS | Routed SWNS/TNS | hold | 违例端点 | 说明 |
|---|---|---:|---|---|---|
| s2 | +0.464 | **+0.267 / 0.000** | +0.020 / 0.000 | 0 / 8683 | RTL 含 `crop_pix` 缺陷（1-bit）→ 网表无效 |
| s3 | +0.468 | **+0.239 / 0.000** | +0.020 / 0.000 | 0 / 8665 | R1 已回退，但仍含同一 `crop_pix` 缺陷 → 网表无效 |

- s2/s3 的时序数字说明“新增逻辑不破坏时序”（WNS ≥ +0.05 有充足余量、0 违例），
  但两份网表都建立在**功能不完整**的源码上（`crop_pix` 1 bit），因此**不能**作为交付候选，
  也不能据此 bitgen/CWC/下载。
- 缺陷在 P1 黄金回归时被抓住（`exported=0`），修复后 P1 三黄金全部一致；修复后的源码
  **没有**经过 TD 综合/布线（预算用尽）。
- CWC 层次探针：TD 综合器拒绝顶层层次化引用（`external connection to net 'estate[1]' is not allowed`），
  记为 `cwc_hier_not_available`；未改顶层端口，仅保留既有 `MARK_DEBUG` 计数器。

**板级**：无有效 bit → 未下载、未开 COM8、无计数。`download_used = 0/2`。

## 8. 交给规划/测试者的下一步（不改本轮结论）

1. 授权 1 次 TD 会话（综合 1 + 布线 1 + bitgen 1 + CWC 1）重建候选：当前 `r0/changed-src` 源码
   已含 `crop_pix` 修复且 P1 三黄金一致，预计时序与 s3 同量级（+0.2 ns 余量）。
2. bitgen/CWC 通过后按“先下载、后开 COM8”跑 1 轮 180 s（下载额度仍为 0/2 已用）。
3. R1 定向用例与 3 连续真实帧用例建议由测试者/下一开发用“复用 tb_p1_chain 的已知良好相机驱动”
   重建（本轮自建驱动失败原因已记录）。
4. R3 的“旧 R 晚于新 AR”需独立方案（读事务 tag 或复位后排空协议），本轮未覆盖。

## 9. 证据索引

- 仿真：`r0/sim/logs/`（`sim_arb_old.log`、`sim_arb_new*.log`、`sim_export_*.log`、
  `sim_layout_*.log`、`sim_r1..r3.log`、`sim_p1_*.log`）、汇总 `r0/sim/sim-results-b10.json`
- TB：`r0/sim/{tb_b10_arb.sv,tb_b10_export.sv,tb_b10_layout.sv,tb_b10_r123.sv,tb_b10_multi.v,tb_p1_chain.v}`
- 驱动：`r0/sim/{run_sims_b10.py,check_multi.py}`
- 旧版反例原件：`r0/sim/repro/`（b9 审查 TB/日志/results.json，未修改）
- TD：`r0/td/{01_build.tcl,build_console_b10*.log,syn_gate_*.rpt,routed_*.rpt,params_after.tcl}`
- 板级脚本（未执行）：`r0/board/{download_sram_b10.tcl,run_board_b10.ps1,capture_com8.py,parse_status_v3.py,decode_frame.py}`
