# T10.b10-b9-fix 开发计划（冻结）

- run：`20261020-0209_singleA_aplus_closedloop`（同 run，不新开）
- 父任务：T10（本包**不**把父 T10 置 done）
- 冻结日期：2026-10-25；规划角色：fpga-planner（本轮以 general 代行）
- 直接上级候选：`T10.b9-rawstore/r0`（只读，**不得修改**；原 b9 与复现反例永久保留）
- 审核输入：`docs/OpenCode_b9审核建议与验证清单_2026-10-25.md`（已读；B9-01/02/03 结论采纳，R1/R2/R3 按“待验证”处理）

## 0. 本轮目标（唯一主要可验收目标）

在 b9 冻结 RTL 上**修掉 B9-01 状态包/帧出队互锁、B9-02 描述符队列越界与计数覆盖、B9-03 1080p 四槽地址重叠**，并用 R1/R2/R3 最小用例确认 top/bridge 是否还有同类缺陷（暴露即最小修复），重建 1 个 P2 候选，用「**先下载、后监听**」的板级顺序回答：修复后 `raw_pub/enc_frames/exported` 是否增量 >0 且帧 CRC/解压通过。

**排除**：crop 几何、MIPI/I2C/IMX415、44 B 帧头/流 CRC/zlib 格式、UART 分频/协议、帧内插包（明确否决）、SDC/引脚、Flash、显示与预览通路、父 T10 的压缩吞吐（b6 已 PASS，不动）。

## 1. 任务与工作包

| task_id | 问题/产物 | 实际工作树/允许写路径 | 依赖 | functional | engineering | system | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| T10.b10-b9-fix | b9 三个已确认缺陷修复 + R1/R2/R3 归因 + P2 候选 + 先下载后监听 1 轮取证 | 仅 `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b10-b9-fix/**`（源码副本放 `r0/changed-src/`、`r0/td/src/`） | b9 r0 候选与 G1/G2 证据；`work/b9-opencode-audit-20261025` 复现 TB/脚本/日志；b8/b9 的 P1 三黄金样例 | B9-01/02/03 反例→通过对照 + 12 描述符环绕 + 同拍 push/pop + 四槽不重叠 + 满尺寸双槽并发 + 连续多帧长度/CRC/解压 + 状态仅帧间且 XOR 正确 + R1/R2/R3 最小用例 + P1 三例逐字节回归 | Routed 0 违例、WNS ≥ +0.05 ns、TNS 0、hold 0、period 0；资源不越 b9（±5%）；无新增跨域多位/组合环；1 bitgen + 1 CWC，bit/CWC/BID 与 manifest 绑定 | 1 次下载**后**开 COM8 采集；`exported` 增量 >0 且 ≥1 完整帧 44 B 头+stream CRC+zlib 解码通过；状态包仅帧间 | G0/G1/G2/G3/G4 | ready | 派 fpga-dev（batch=1，本包 W1→W2→W3） |

正式工作包 3 个（ready 计入），每包 ≤5 项语义步骤，顺序固定；独立综合测试者不计包。

| 包 | 内容 | 语义实现步骤（≤5） |
|---|---|---|
| W1 fix+sim | B9-01/02/03 修复 + R1/R2/R3 归因 + 全量离线回归 | ① `a1_uart_export.v` 帧间统一 `status_due` 仲裁（tick 同拍、`accepted_pop` 来自实际仲裁、非空队列不阻塞状态、状态期间不出队）；② 1-bit 环绕指针 + 按实际接受事件集中更新 `dq_cnt` + 明确满/同拍策略；③ 四槽布局 `CMP_BASE=262144` + 容量/单位核对 + 区间断言；④ R1/R2/R3 最小 TB（暴露 bug 时在 `camera_a1_uart_top.v`/`p2_ddr_bridge.v` 做最小修复）；⑤ 全量回归：B9-01 反例对照、12 描述符环绕、同拍 push/pop、满/空、满尺寸双槽并发、连续多帧长度/CRC/解压、状态仅帧间/XOR、P1 三黄金样例 |
| W2 TD | P2 候选 | ① `01_build.tcl` 改指本任务源；② 综合（≤3）；③ 布线（≤2）Routed 0 违例、WNS ≥ +0.05；④ 1 bitgen + 1 CWC（含仲裁/队列/DDR 等待探针，端口不变）；⑤ `CANDIDATE-MANIFEST-b10-b9-fix-r0.json` + `artifact-hashes.txt` |
| W3 board | 1 轮板级取证 | ① **先** `download_sram_b10.tcl`（COM8 关闭，避免 FTDI 争用）并记 bit SHA/BID；② **后**开 COM8 监听采集 180 s；③ 解析 v3 状态包（XOR/ver/len）+ 计数增量；④ `exported` 增量 >0 时按 44 B 头 + stream CRC + zlib 解码并给图像/长度证据；⑤ `result-r0.md` + `lessons-r0.md`，失败即停 |

依赖顺序：W1 →（G1 全绿）→ W2 →（G2 全绿）→ W3。G1 红即停，不消耗 TD/板窗；G2 红即停，不下载。

## 2. 冻结的技术口径（开发照此实现，测试按此判定）

### 2.1 目录与基线（隔离，不覆盖证据）

1. 新建 `T10.b10-b9-fix/r0/{changed-src,td,sim,board}`。
2. 基线照抄（**复制**，不移动、不改原文件）：
   - `T10.b9-rawstore/r0/changed-src/{a1_uart_export.v,camera_a1_uart_top.v,a1_ddr_slot_store.v,a1_raw_crop.v,cam_diag_mailbox.v,a1_deflate_core.v}` → `r0/changed-src/`
   - `T10.b9-rawstore/r0/td/` 整棵 → `r0/td/`（`src/`、`01_build.tcl`、`02_bitgen.tcl`、`03_cwc.tcl`、`p2_board.sdc`）
   - `T10.b9-rawstore/r0/sim/` 整棵 → `r0/sim/`（`tb_raw_store.v`、`tb_status_v3.v`、`tb_p1_chain.v`、`run_sims_b9.py`、`a1_ddr_model.v`、`p2_paxi_model.v`、`old_bridge/`）
   - `T10.b9-rawstore/r0/board/{capture_com8.py,parse_status_v3.py,decode_frame.py}` → `r0/board/`
   - `work/b9-opencode-audit-20261025/{tb_b9_arb_repro.sv,run_repro.py,analysis.md,results.json,sim_sts_64.log,sim_sts_0.log}` → `r0/sim/repro/`（**复制**，作旧版失败对照的原始证据）
3. 允许修改的文件**仅**：`r0/changed-src/a1_uart_export.v`、`r0/changed-src/camera_a1_uart_top.v`、`r0/changed-src/a1_ddr_slot_store.v`（必要处）、`r0/td/src/p2_ddr_bridge.v`（必要处）、`r0/td/src/p2_a1_board_top.v`（仅接线/探针/参数传递）、`r0/td/03_cwc.tcl`（探针）、本任务 sim/board 脚本。`a1_raw_crop.v`、`a1_deflate_core.v`、`cam_diag_mailbox.v` 只随哈希冻结，**不得改**。

### 2.2 B9-01 状态包与帧出队的帧间统一仲裁（必须满足的性质）

- `status_due = sts_tick || sts_want`，由**同一处**仲裁决定本拍「发状态」还是「开下一帧」；两者互斥。
- 帧边界机会**不依赖队列为空**：`dq_cnt>0` 不能阻止状态获得帧间机会；状态获准时该拍不得 `accepted_pop`/开帧。
- tick 当拍必须处理：不得因 `sts_want` 是旧值而同拍同时启动两个状态机、双写 `tx_byte_r` 或错误 pop。
- `accepted_pop` 只能来自实际仲裁结果（描述符真正被接受进入 E_OPEN 的那一拍），`dq_rd/dq_cnt` 与之一致。
- 保持帧头+载荷连续：最后一个 UART 字节完成（`tx_ready && !tx_valid_r` 且 `estate` 回 E_IDLE）之前不得启动下一帧或状态。
- 结论性质：**在持续有帧排队时，状态最迟在下一个帧边界发出**，不要求业务空闲；但仍不保证 DDR 故障导致帧内永久挂起时还能出状态（本轮不承诺，不据此加帧内插包）。

### 2.3 B9-02 描述符队列

- `dq[0:1]` 深度 2 不变；指针改 **1-bit 环绕**（`dq_wr/dq_rd` 只在 0/1 取值），不得出现 `dq[2]/dq[3]` 访问。
- `dq_cnt` 由 `accepted_push`/`accepted_pop` 在**单一处**集中更新；同拍 push/pop 不得双赋值覆盖。
- 满/同拍策略（冻结）：`dq_cnt==2` 且该拍接受 pop → **允许**该 push（计数保持 2）；`dq_cnt==2` 且无 pop → 拒收该 push 并计数（计数可只在 TB 层次/CWC 观测，**不新增状态包字段**）；空队列不可能有 pop。
- 逐拍断言：`dq_cnt == 实际占用数`；环形访问指针 ∈ {0,1}。

### 2.4 B9-03 四槽 DDR 布局（256-bit word 地址，含端点）

| 槽 | 起始 | 结束 | 词数 |
|---|---:|---:|---:|
| RAW0 | 0 | 129,599 | 129,600 |
| RAW1 | 129,600 | 259,199 | 129,600 |
| CMP0 | 262,144 | 343,228 | 81,085 |
| CMP1 | 343,229 | 424,313 | 81,085 |

- 冻结常量：`RAW_BASE=0`、`CMP_BASE=262,144`（=2^18，对齐边界）。理由：满足 `CMP_BASE ≥ RAW_BASE + 2*RAW_WORDS = 259,200`，且最小改动（`CMP_BASE` 在源码中仅 `camera_a1_uart_top.v` L43 默认值与 L483 `.BASE_WORD` 一处使用；`p2_a1_board_top.v` 不覆盖该参数）。
- 必做核对并记录到 `result-r0.md`：① DDR IP 实际容量 ≥ 424,314 word（13.58 MiB），从 TD IP 配置读出；② PAXI 地址位宽 27 bit，上述最大地址 424,313 « 2^27；③ `CMP` 实例 `AWB=17`（≤131,072 词）仍容得下 81,085 词，`RAW` 实例 `AWB=18`（262,144）容得下 259,200；④ 无其他主设备占用 word ≥262,144。任一项不成立即 **blocked** 交回规划，不猜常量、不改位宽凑合。
- 静态断言（仿真 `$error`/`initial`）：`CMP_BASE >= RAW_BASE + 2*RAW_WORDS` 且 `CMP_BASE + 2*CMP_WORDS <= DDR_WORDS`；`SLOT_WORDS <= 2**AWB`。

### 2.5 R1/R2/R3（先写最小 TB，暴露 bug 才修，范围限于 top/bridge）

- **R1**：FIFO 满时丢 LAST / LAST 在 skid 受背压时 abort。要求：坏帧不发布、`raw_drop`/abort 计数正确、slot 回收 FREE、无孤儿 writer、下一好帧照常发布读取。
- **R2**：只送 1 字后停止输入 → 外部 AW/W **各恰一次**；AW/W 独立背压时 valid 期间地址/数据保持；不能只数 store 提交次数（须看真实 `paxi_awvalid/paxi_wvalid`）。
- **R3**：AR 已握手但 R 未返回时业务复位，再发新 AR 后释放旧 R；另测旧 R 已 valid 且受背压。旧响应不得交给新会话（不得把旧 rdata 当新地址结果）。若本任务无法在不大改 bridge 的前提下安全覆盖，则**如实记 not_covered 并给出证据与风险描述**，不得假装通过。

## 3. 各包检查项与不适用理由

- **W1 functional**：见 §2.2–§2.5 全部性质；用例清单见 §5 G1。
- **W1 engineering**：改动只在 `clk_a1`/`dhi_clk` 原域内，不新增跨域多位直通、不新增组合环、不新增 ERAM；`p2_ddr_bridge` 仍单拍、无 burst/B 通道依赖。system：不适用（离线包，板级在 W3）。
- **W2 engineering**：Routed 0 违例、WNS ≥ +0.05 ns、TNS 0、hold 违例 0、period 违例 0、无新增未约束路径；LUT/FF/ERAM 相对 b9 增幅 ≤5% 且 ERAM 不增；17 时钟 CC/CDC 报告不新增未解释项。functional：bit/CWC/BID 与同一 manifest 绑定的源码哈希一致（重算，不沿用旧值）。system：候选唯一、bit/CWC/BID 独占窗口。
- **W2 functional（CWC 探针）**：`03_cwc.tcl` 在**不改端口**前提下优先映射 `estate/sstate/sts_want/dq_cnt/a1_busy` 及 DDR AR/R 等待、业务复位电平；TD 不支持层次探测时记 `cwc_hier_not_available` 并只用现有计数器，**不因此判 FAIL**。
- **W3 functional**：`raw_pub`/`enc_frames`/`exported` 增量 >0；≥1 完整帧：44 B 头 `A5 5A` + ver/len 合法、`stream_len` 与实收一致、stream CRC 通过、zlib 解压出 1920×1080/2,592,000 B；177 B 状态包 ver=3/len=177/XOR 全对且**仅出现在帧间**（解码器按 `stream_len` 恰好消费载荷可反证无插包）。
- **W3 engineering**：下载日志含 bit SHA256 与 BID，且与 W2 manifest 一致；CWC 与 bit 同候选；采集时间戳、端口（COM8）、baud 115200 8N1 记录完整。
- **W3 system**：顺序必须「先下载、后监听」；下载 ≤2、Flash 0；单采集窗口；静默/失败即停并保留全部证据（不二次下载）。

## 4. 门槛

**G1（仿真，硬门）** —— 全绿才进 TD：
1. **B9-01 对照**：同一 TB 下，**未修改的 b9 exporter** 必须复现旧失败（≈`E_IDLE/S_IDLE/want=1/count=1`、UART 空闲不再发）；**修复版**必须完成「状态在第一帧中到期 + 下一帧已排队」→ 状态发完后继续出帧；tick 与出队同拍只一方获准；状态发送期间持续入队不混流。旧版失败日志与新版通过日志都进 `r0/sim/logs/`。
2. **B9-02**：≥12 个被接受描述符环绕（含 3 次以上环绕）→ 顺序/长度/CRC 全对、无重复漏发；同拍 push/pop；满/空边界；指针断言与 `dq_cnt` 逐拍一致。
3. **B9-03**：四槽区间断言通过且**满尺寸**双槽并发（RAW 与 CMP 同时各写 2 槽并读回）逐字一致、地址不重叠。
4. **连续多帧**：≥3 个有效压缩帧连续导出，逐帧 44 B 头/长度/stream CRC/zlib 解压正确；177 B 状态包仅帧间且 XOR 正确。
5. **R1/R2/R3** 最小用例各自给出 pass/fail 与证据；未覆盖项显式写 `not_covered` + 原因。
6. **P1 三黄金样例** `fa513a2b…cef` / `ee61e620…789` / `b992a8ad…da9` 逐字节不变，`err/raw_drop/cmp_drop/geom/dup=0`。

**G2（工程，硬门）**：Routed 0 违例、WNS ≥ +0.05 ns、TNS = 0、hold/period 违例 0；1 bitgen + 1 CWC；manifest 绑源码/网表/bit/CWC/BID SHA256；资源与 b9 对比如实记录。

**G3（板级，本轮主门）**：
1. 顺序：先下载（COM8 关闭）→ 记录 `B10_DL_OK`/bit SHA/BID → 再开 COM8 采集 180 s。
2. **PASS**：`raw_pub`、`enc_frames`、`exported` 三者增量均 >0，且 ≥1 完整帧解码通过（44 B 头 + stream CRC + zlib → 1920×1080）；状态包 ver=3/len=177/XOR 全对且仅帧间。
3. **部分达成**（有状态包、`raw_pub>0` 但 `exported=0`）：记 ⚠ 未通过，保留候选与证据，写明卡点，**不二次下载**。
4. 静默（0 B）：保留证据，按 §4 判定表定位，停；除非用户再次明确授权，否则不下载第三次。
5. `crop_geom_err=0`、`crop_short=0` 必须保持；`errors` 若增长须给原因。

**G4（收尾）**：`result-r0.md`（含布局核对、反例对照、计数表、解码结论、实际下载次数）、`lessons-r0.md`、manifest/hashes 齐备；综合测试者独立报告绑同一 manifest；父 T10 不置 done。

## 5. 预算、停止与回退

- 开发：**150 min / 70 calls**（含仿真、TD、板级）。
- TD：**3 会话 / ≤150 min**，综合 ≤3、布线 ≤2、bitgen 1、CWC 1、**下载 ≤2**、Flash 0。
- 综合测试者：45 min / 30 calls，0 次 TD 重跑、0 次下载（只复算/复解析同一冻结输入）。
- 停止：G1 红即停；G2 布线违例即停（不反复扫参数）；板级失败即停并留证据；连续 2 次工作循环无新证据 → blocked。
- 重试：同一失败命令首次 + 1 次仅有新证据/参数纠正的重试；不换关键词/ID/目录绕计数。
- 下载额度：用户已授权连续烧录；本轮记 `download_used/2`，并在 `result-r0.md` 写明**实际累计次数**（截图“剩 1 次”只作当时记录，不重置）。
- 回退：RTL 回退点 = `T10.b9-rawstore/r0/changed-src/*` + `CANDIDATE-MANIFEST-b9-rawstore-r0.json`（bit `950b6e4a…a06`、CWC `b9515f79…1cdd7`、BID `67c289a8…70a8b`）；b9 目录与复现反例不得删改。若某条修复在 G1 无法证明安全，只回退该条并保留其余与全部证据，如实降级交付，不为凑 PASS 保留未证改动。

## 6. 后续主题（本轮不做）

1. 若板级仍静默且 LED0（`hb_cnt[23]`，随 `clk_a1` 翻转）不动 → A1 复位/DDR 就绪/下载链路独立任务（需新授权）。
2. 若卡在 `E_PAY`/DDR 读等待 → 读超时看门狗 + slot 回收 + 迟到响应策略（新冻结）。
3. 导出带宽：115200 下每帧 ≈7 s（81.7 kB），提高波特/分块导出另评（不改本轮协议）。

## 7. r1 修订（2026-10-25，同包续轮，冻结）

> r0 的 W1 已完成并通过（B9-01/02/03、P1 三黄金、R2/R3；R1 与 3 连续真实帧 not_covered）。r0 的 W2 因 TD 综合 3/3、布线 2/2 用尽而 blocked；最后两份网表所用源码含已修复的 `crop_pix` 声明缺陷（1 bit），**没有有效 bit/CWC，下载 0/2**。r1 不重开任务、不改 task_id、不重跑 W1 全量；只做「用当前已修复源码重建 1 个候选 + 1 轮板级取证」。

### 7.1 r1 唯一主要目标

用 r0 已冻结并通过 P1 的 `r0/changed-src` 源码，重新综合 1 次 + 布线 1 次 + bitgen 1 + CWC 1，得到唯一有效候选；随后「先下载、后开 COM8」采 180 s，要求 `raw_pub/enc_frames/exported` 增量 >0，且至少 1 帧 44 B 头 + stream CRC + zlib 解码通过。R1/3 连续帧补测仅在板级证据落盘后可选进行，不改候选、不阻塞本轮。

### 7.2 r1 工作包（2 个正式包 + 1 个可选证据包）

| 包 | 内容 | 冻结步骤 |
|---|---|---|
| W2-r1 | 重建候选 | ① 源哈希复核（与 r0 manifest 逐项相等；`crop_pix` 为 40 bit）；② 归档 s2/s3 报告/项目/运行目录（复制/改名，不删除）；③ 一次新综合；④ 一次布线；⑤ 1 bitgen + 1 CWC；⑥ 生成 r1 manifest + artifact-hashes |
| W3-r1 | 1 轮板级 | ① 哈希/BID 复核；② COM8 关闭下 1 次 SRAM 下载；③ 释放 FTDI 后开 COM8 采 180 s；④ parse v3（≥2 包，ver/len/XOR，首末计数增量）；⑤ `exported>0` 时 decode（44 B 头 + stream CRC + zlib）；⑥ result-r1/lessons-r1/manifest 回填 |
| W1-r1-opt | 可选定向仿真（证据，不计门槛） | ① R1 丢 LAST 定向用例（复用 `tb_p1_chain` 相机驱动）；② 3 连续真实压缩帧用例；③ 结果写 `r0/sim/r1-extra/`；不得改 RTL、不得重跑 TD/板级 |

依赖：W2-r1 → G2-r1 → W3-r1 → G3-r1；W1-r1-opt 在 G3-r1 证据落盘后、预算内进行。

### 7.3 源冻结（r1 不得改 RTL）

- 冻结源：`r0/changed-src/{a1_uart_export.v,camera_a1_uart_top.v,a1_ddr_slot_store.v,a1_raw_crop.v,cam_diag_mailbox.v,a1_deflate_core.v}` + `r0/td/src/{p2_a1_board_top.v,p2_ddr_bridge.v}`。哈希以 `CANDIDATE-MANIFEST-b10-b9-fix-r0.json` 为准（exporter `ff0ce16d…`、camera top `612d42a5…`、bridge `b9e83481…`、board top `98d6c446…`；已由规划在冻结前重算复核）。
- 已核对：`camera_a1_uart_top.v` L156 为 `wire [39:0] crop_pix;`（r0 缺陷已修，P1 复测一致）。
- **r1 不允许任何 RTL/参数/SDC/引脚/端口改动**。`camera_a1_uart_top.v` 中 `// T10.b10 R1:` 注释块描述的是 r0 **已回退**的尝试，仅为历史注释，不代表本候选含 R1 功能修复；不得为了“清理注释”改文件（会改变哈希并破坏 r1 绑定）。该事实必须写入 r1 manifest 的 `changes` 与 `result-r1.md`。
- 若复核发现源哈希与 r0 manifest 不等：停止 TD，先查清差异；只有确认差异无害且重跑 P1 三黄金 + B9 定向用例通过后才可继续（预算内）。

### 7.4 W2-r1 冻结流程（1 个 TD 会话 / 60 min；综合 1、布线 1、bitgen 1、CWC 1）

1. 环境：同一 PowerShell 会话先 `. D:\fpga\ph1p100\tools\td\open_td.ps1`（T:=当前 r0/td，Y:=项目根；禁用 X:）。cwd=`...\T10.b10-b9-fix\r0\td`。
2. 预检（不改文件）：`Get-FileHash` 复核 §7.3 源；`Select-String crop_pix`；确认 `a1_board.bit`、`a1_board.cwc`、`cw/` 均不存在；确认 `a1_board_Runs` 为 r0 s3 目录、`a1_board.al` 为 r0 项目。
3. 归档（不删除）：新建 `r0/td/r0-build-evidence/`，把 s2/s3 的 `build_console_b10_s2.log`、`build_console_b10_s3.log`、`syn_gate_*.rpt`、`routed_*.rpt`、`phy_*.rpt`、`candidate_*.rpt`、`params_after.tcl`、`place_flow.status`、`route_flow.status`、`routed_netlist.v` **复制**进去；再把 `a1_board_Runs` 改名为 `a1_board_Runs_r0s3`、`a1_board.al` 改名为 `a1_board_r0.al`（单目录/单文件改名，不删除）。
4. 一次综合+布线：`td_commands_prompt.exe 01_build.tcl *> build_console_b10_r1.log`。只允许一次；失败即停，不重试、不改参数。
5. 硬门 G2-r1（全部满足才继续）：日志出现 `P2_BUILD_DONE`、`NO_BIT_FILE`；`P2_SYN_SWNS >= 0`；`P2_ROUTED_SWNS >= +0.05`、`P2_ROUTED_STNS = 0.000`、`P2_ROUTED_HWNS >= 0`、`P2_ROUTED_HTNS = 0.000`、`P2_ROUTED_VIOL_EP = 0`；资源（slice/reg/ERAM）与 b9 差异 ≤5% 且 ERAM 不增；无新增未解释 CDC/组合环。任一不满足：停，写 blocked，**不 bitgen、不下载**。
6. 一次 bitgen：`td_commands_prompt.exe 02_bitgen.tcl *> bitgen_console_b10_r1.log`；要求 `P2_BITGEN_STA_SETUP=.../0 ...`、`P2_CANDIDATE_BIT_GENERATED_NO_DOWNLOAD`，`a1_board.bit` 存在且非空。
7. 一次 CWC：`td_commands_prompt.exe 03_cwc.tcl *> cwc_console_b10_r1.log`；要求 `P2_MATCHING_CWC_EXPORTED_NO_DOWNLOAD`、`a1_board.cwc` 存在、`cw/compiled.bit` 与 `a1_board.bit` 字节相同、`a1_board_inst.bid` 存在。TD 拒绝层次化探针时按 `cwc_hier_not_available` 记录，不因此判 FAIL、不改端口。
8. 绑定：新建 `r0/mk_manifest_b10_r1.py`（从 r0 脚本派生）：输出 `CANDIDATE-MANIFEST-b10-b9-fix-r1.json` + `r0/artifact-hashes-r1.txt`；记录 `round:"r1"`、`previous_manifest` 的 SHA256、`board.download_count`、`captures_r1` 证据路径；`changes` 必须写明 camera top 仅 CMP_BASE+仿真断言、R1 注释为历史、无功能 R1 修复；bit/CWC/BID 的 SHA256 从文件重算。保留 r0 manifest 原文件不动。
9. 候选唯一性：`a1_board.bit/.cwc/.bid` 只允许这一组；旧 `*.b9-baseline-copy` 仅作回退参照，不得参与下载。

### 7.5 W3-r1 冻结流程（下载 1 次，累计 ≤2；Flash 0）

1. 前置：板卡上电、相机连接、COM8 未被占用、无 hwserver/python 监听；记录时间、端口、115200 8N1。
2. 下载前复核：`Get-FileHash a1_board.bit/.cwc/a1_board_inst.bid` 与 r1 manifest 完全一致；不一致即停，不下载。
3. 下载（COM8 必须关闭）：`td_commands_prompt.exe download_sram_b10.tcl`（cwd=r0/td；脚本内 bit 路径即 r0/td/a1_board.bit）。日志必须含 `B10_DL_OK mode=jtag(sram)`；另把 bit SHA256、BID SHA256、`B10_DL_DEVICE` 追加到 `r0/board/log-r1/download_sram_r1.log`。**只下载 1 次**；失败即停，不重试。
4. 监听：结束 hwserver/TD 对 FTDI 的占用，等待 ≥2 s，再 `python capture_com8.py --port COM8 --baud 115200 --secs 180 --outdir r0/board/captures_r1`；要求 `com8_180s.bin` 存在且 >0 B，保存 `.stats`。
5. 解析：`python parse_status_v3.py --in r0/board/captures_r1/com8_180s.bin --json r0/board/captures_r1/status_v3.json --min-packets 2`；要求 ≥2 个合法 v3 包（177 B、ver=3、len=177、XOR 全对）；记录首/末 `raw_pub/enc_frames/exported` 与 `crop_geom_err/crop_short/errors`。**增量 = 末 - 首**，三者均 >0 才满足主门。
6. 解码：`exported` 增量 >0 时 `python decode_frame.py --in .../com8_180s.bin --outdir .../decoded`；要求 ≥1 帧：`A5 5A`、ver/len 合法、`stream_len` 与实际一致、stream CRC 通过、zlib 解出 1920×1080 / 2,592,000 B；保存解码结果 json/图像与帧索引。
7. 判定：全满足 G3-r1 PASS；有状态包但三增量不全 >0 或帧未解出 → ⚠（保留候选与证据，写明卡点，不二次下载）；0 B/无包 → 停，保留证据。
8. 收尾：`result-r1.md` 写实际下载次数（1，累计 1/2）、TD 1 会话/综合 1/布线 1/bitgen 1/CWC 1、G2/G3 表、哈希、计数、解码结论；`lessons-r1.md`（如有）；manifest 回填 `board.download_count=1` 与 `captures_r1` 路径；父 T10 不置 done。

### 7.6 可选 W1-r1-opt（只在 G3-r1 证据落盘后，时间允许）

- 复用 `r0/sim/tb_p1_chain.v` 的已知良好相机驱动，复制到 `r0/sim/r1-extra/`，不改原 TB。
- R1 丢 LAST：在 LAST 拍对 CDC FIFO 施加 `fifo_wready=0`（或等效背压）→ 断言坏帧不发布、`raw_drop/abort` 计数 +1、slot 回收、下一好帧正常发布读取。
- 3 连续真实帧：同一驱动连发 3 帧，逐帧 44 B 头/长度/stream CRC/zlib + 状态包仅帧间。
- 结果写 `r0/sim/r1-extra/findings-r1-extra.md`；**不改 RTL、不重综合、不重下载**。若暴露真实缺陷，记为本候选的残余风险/下一任务输入，不据此改 r1 结论。

### 7.7 r1 预算、停止与回退

- 开发：90 min / 50 calls（含 TD、board、可选 sim、文档）。
- TD：1 会话 / 60 min；综合 1、布线 1、bitgen 1、CWC 1、下载 1（累计 ≤2）、Flash 0。
- 综合测试者：45 min / 30 calls；0 TD 重跑、0 下载、0 Flash。
- 停止：源哈希不等且未澄清；综合/布线任一硬门红；bitgen/CWC 失败；下载失败；采集 0 B/无 v3 包；三增量不全 >0（记 ⚠ 并停）；连续 2 次无新证据。任一处停都保留日志/原始流，不二次下载、不换参数重跑。
- 重试：r1 的 TD 与下载均为**单次**，无“首次+1 次重试”；只有工具/环境类失败且未消耗实质步骤时，由规划书面授权才可重试。
- 回退：r0 s2/s3 报告与旧项目归档在 `r0/td/r0-build-evidence/` 与 `a1_board_Runs_r0s3`、`a1_board_r0.al`；b9 候选与全部证据只读保留；不删旧目录、不覆盖 b9 baseline 副本。

### 7.8 r1 交付

`CANDIDATE-MANIFEST-b10-b9-fix-r1.json`、`r0/artifact-hashes-r1.txt`、`r0/td/{build_console_b10_r1.log,bitgen_console_b10_r1.log,cwc_console_b10_r1.log,syn_gate_*,routed_*,candidate_*,routed_netlist.v}`、`r0/td/{a1_board.bit,a1_board.cwc,a1_board_inst.bid}`、`r0/board/captures_r1/{com8_180s.bin,.dec,.stats,status_v3.json,decoded/**}`、`r0/board/log-r1/**`、`result-r1.md`、`lessons-r1.md`（如有）、`r0/sim/r1-extra/**`（可选）。测试者报告由独立 fpga-tester 写入 `test-reports/T10.b10-b9-fix-r1-integrated.md`。
