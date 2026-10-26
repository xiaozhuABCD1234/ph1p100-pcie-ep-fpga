# T07.rk-align-backend 变更报告（round0）

范围：`fpga/csi2/pcie_integration/`（新交付树）+ `tools/pcie_integration/`（runner/manifest）
+ 本 run `backend/`（候选、证据、RK 补丁树）。原 PAXI/预览/002820 工程与 peer 参考库只读未动。

## 0. 一句话

把 peer 冻结版（2a4b253）的「相机 → DDR3 → 主机 MWr 推帧」后端，改成 **一组 one-shot 安全语义**
（默认不发、ARM 才发、一帧一授权、完成后 held 等匹配 ACK、CANCEL 不截包、源缓冲发布即保护），
并把本方的 **checked CSI**（整帧 CRC/ECC/WC/行数/FE 裁决 + keep 解包）真实接进同一条链路；
用法保持 peer 的 TLP 线上格式（F0 头 / FF 载荷 / F8 单 DW 门铃 / 4DW 地址 / 128B 载荷 / 倒序字节）。

## 1. 逐文件改动（与 `source-provenance.json` 对照）

| 文件 | 类别 | 改动要点 |
|---|---|---|
| `rtl/ep_side/ddr/ddr_frame_pusher.v` | 重写（安全门） | 见 §2：RKA1 one-shot 门 + 描述符原子锁存 + ACK/HELD + CANCEL + 超时补包 + 源块 release 协议 |
| `rtl/ep_side/img/ep_bar_win.v` | 扩展 | 新增 0x100..0x11C RKA1 寄存器（合同偏移），活动期配置写拒绝（`cfg_reject`），新增只读诊断 0x120..0x12C；声明顺序修正（vlog-2730） |
| `rtl/ep_side/ddr/cam_ddr_writer.v` | 扩展 | good/abort 参与发布裁决（坏帧不发序号）；发布即保护缓冲块（`protect0/1` + `rel_tgl` CDC）；目标块被保护时整帧跳过（C_SKIP）；FIFO 条目加坏-EOF 位 |
| `rtl/ep_side/img/img_frame_src.v` | 扩展 | 新增 `hold`：one-shot claim 时冻结 fb 发生器（可证明的捕获停止点） |
| `rtl/ep_side/cam/mipi_csi2_rx_ph1p_checked.v` | 新增 | 保留 peer PHY/byte align/word align/gearbox 与握手，包层换成 `csi_rx_packet_integrity` + `csi_rx_10bit_unpack_checked`；输出 FE/good/abort 与错误/几何诊断；`MIPI_PHY_SIM_STUB` 仅供仿真旁路 serdes |
| `rtl/checked/csi_rx_packet_integrity.v`、`csi_rx_10bit_unpack_checked.v` | 引入（逐字节复制） | 来自 `fpga/csi2/src/csi`（`local_copy_unchanged`） |
| `rtl/ep_side/pcie_ep_engine.v` | 接口 | RKA1 寄存器面/诊断过路端口；`tl_tx_state` 声明提前（vlog 兼容） |
| `rtl/ep_side/ph1p_pcie_ep_top.v` | 集成 | 两路 CSI 换 checked wrapper；writer/pusher 新端口接线；`DDR_CAP_BYTES=256MB`（板载 x16/2048Mb/1CS，非 29 位总线宽）；声明顺序修正 |
| `rtl/ep_side/cam/ui_cfg_imx415.v` | 仿真兼容 | 隐式网 `iic_busy` 显式声明、`reg_index` 声明前移（TD 能过的写法 ModelSim 报错，行为不变） |
| `sim/tb/*.v`、`sim/compile_checked.f`、`sim/tb/top_elab_stubs.v` | 新增 | G1 三个 TB + 编译清单 + 厂商 IP 端口桩 |
| `tools/pcie_integration/run_sim.ps1`、`run_td.ps1`、`td/*.tcl`、`gen_manifest.py` | 新增 | ModelSim/TD 可复现入口 + 清单生成 |

未改动：`ddr_wr_arb.v`、`img_regs.v`、peer 的 `csi_rx_packet_handler.v / csi_rx_10bit_unpack.v / mipi_csi2_rx_ph1p.v`（保留在树里作对照，顶层已不实例化）、约束 `.adc/.sdc`、`al_ip/` 全部 IP 生成物。

## 2. 安全语义（与 contract/registers.json / registers 表逐一对应）

* **默认不发**：`push_en`（CTRL[6]）只是模式使能；推帧必须由 `TX_CMD(0x108).bit0 = ARM_ONE_SHOT`
  授权。CTRL=0x61 单独**一个 TLP 都不发**（本地检查 PHASE1 断言）。
  实现选择（与任务书条目的差异，如实记录）：ARM **不要求** push_en 已置位——claim 条件里含
  push_en，所以「先 ARM、后开模式」也绝不会提前发包；反过来「先开模式、后 ARM」本来就是这个流程。
  两种顺序的安全性都由「claim 同时要求 push_en 与 G_ARMED」保证。
* **ARM 校验**（不满足 → 错误码 6 + TX_STATUS.bit3 粘滞）：session≠0、cap≠0 且 ≥frame_bytes、
  frame_bytes>0 且 ≤MAX 且 4KiB 整数倍、dst 128B 对齐/非零/64bit 不回绕、db 4B 对齐/非零/不与传输区重叠、
  `link_up`（pl_link_up & 两个 locked）、协商 MPS 编码合法、**DDR 源**还要已发布完整帧。
* **原子锁存**：ARM 那一拍把 {dst_lo/hi, db_lo/hi, cap, session, frame_bytes, 源选择, 相机选择} 整组锁存；
  claim 时再锁 {源帧号, 源基址, 门铃值}；`frame_bytes`/源选择/相机选择在 ARM 后变化 → 本帧拒绝（错误码 9）。
* **hold/ACK**：数据 + 独立单 DW 门铃都发出才算完成 → HELD，记 held_seq（= 门铃值）/held_sess；
  期间不启动新帧（源再出帧只记错误码 8）；`ACK_RELEASE` 必须 `ACK_SEQ==held_seq && ACK_SESSION==held_sess`，
  错误 ACK 不覆盖 held 槽（错误码 11）；释放后必须重新 ARM。
* **CANCEL**：ARMED 直接放；TX 中把**已开始的包发完**（绝不截半包、不让 CPL 插进包内）、
  **不发门铃、不加成功序号**、排空后回 IDLE 并释放源块；HELD 时拆槽。
* **超时**：包内等 `tl_tx_wait` 超 `WAIT_LIMIT` 时置 flush：**先把这个包补完**再排空；
  若链路一直不恢复就停在 bounded error 状态（busy=1、无门铃、序号不加），等真实链路恢复 —— 不截半包。
* **源所有权（DDR 相机源）**：写者「发布即保护该块，直到收到该块的 release」；推帧引擎对每个发布帧
  给且只给一个 release（claim 后 ACK/CANCEL 释放，或未 claim 的 pass 立即释放），每块一根 toggle 跨域。
  ⇒ 读窗口与写窗口天然互斥，**不依赖「1ms 内推完」**：本包 TB 用 4000 拍长 stall + 期间连续出帧实测通过
  （engine 的 claim 帧块在 ACK 前 release 计数 = 0）。
  ERAM 源（fb）则在 claim 时 `fb_hold` 冻结发生器（发生器帧间 IDLE_CYCLE=1e6 拍 ≫ 拉起延迟），
  release 放开 —— 「可证明的 one-shot 捕获停止点」。
* **默认诊断**：0xC8 错误码在旧 0..4 之上新增 5..11（未 ARM/ARM 被拒/CANCEL/HELD/源不符/活动期写配置/错误 ACK）。

## 3. 线程/时钟与 CDC

| 边界 | 机制 |
|---|---|
| AXI(DDR 域 100MHz) → TL 域 62.5MHz | 原 peer 异步 FIFO（格雷码）+ 2FF 电平同步（未改） |
| cam_ddr_writer 字节域 → AXI 域 | 原 peer 异步 FIFO（34→35bit，多一个坏-EOF 位）+ 发布 toggle/ack（未改） |
| 推帧引擎 → 写者（release） | **新增**：每块一根 toggle（`rel_tgl0/1`），写者 3FF 同步 + 边沿检测清 `protect` |
| 写者 → 推帧引擎（帧号/基址） | 原 peer 发布握手（pub_tgl/pub_ack，写者侧发起），未改 |
| checked CSI 诊断计数（字节域 → TL 域） | 只读诊断：2FF 采样；**明示**只给人看不参与控制（多 bit 计数器跨域瞬时可能不一致） |
| ERAM `fb_hold` | 同一 tl 时钟域电平（无 CDC） |

## 4. 局部检查（G1 证据，命令与日志在工作目录 `backend/g1/msim/`）

> **round2（当前）**：G2 setup 达标所需的 checked 包层有界重构已完成，G1 证据在
> `backend/g1/msim/r2_*`（round2 冻结输入、默认入口、无任何 suppress 开关），含新增的差分 oracle TB：

| TB | round2 结果 |
|---|---|
| `tb_csi_integrity_diff`（新：重构版 vs 只读原源的差分） | **ALL PASS**（680 拍 0 失配；abort/计数 ≤2 拍窗口） |
| `tb_csi_checked` | **ALL PASS** |
| `tb_ddr_frame_pusher_rka1` | **ALL PASS**（20387 TLP） |
| `tb_ep_bar_win_rka1` | **ALL PASS** |
| `tb_ddr_wr_arb` | **ALL PASS** |

> **round1**：round0 的三个维度 FAIL 已修复并重跑（详见文末 §7）；证据保留在 `backend/g1/msim/r1_*`。

入口：`tools/pcie_integration/run_sim.ps1`（自动临时 subst 映射中文路径，日志落盘）。

| TB | 覆盖 | 结果 |
|---|---|---|
| `tb_ddr_frame_pusher_rka1` | 默认不发/ARM 拒绝矩阵/one-shot+held+ACK/三种 CANCEL/release 协议/长 stall+多帧/超时不截包/FE 前后/ERAM+fb_hold/**完整 1080p 长度（20256 MWr + 633 突发）** + 独立 TL 记分板（F0/FF/F8、4DW、BE、字节序、地址递增、门铃在前） | **ALL PASS**（20257 TLP） |
| `tb_ep_bar_win_rka1` | 旧寄存器表回归 + RKA1 0x100..0x11C + TX_CMD 单 bit/多 bit/未知 bit + 活动期配置写拒绝 + 诊断 + 未实现偏移 DEAD_BEEF | **ALL PASS** |
| `tb_csi_checked` | 真实 checked wrapper + integrity/unpack：好帧发布且 DDR 逐字节=独立像素模型；CRC 坏/行长不符/无 FE → 不发布；FE 排尽无假包头；缓冲区所有权保护（跳过→计数→release 后可写） | **ALL PASS** |
| 顶层例化/精化 | `compile_checked.f` 含 `ph1p_pcie_ep_top` 与全部生产 RTL（IP 用端口桩） | 编译 0 错（真实 IP 精化由 TD syn_1 覆盖，见 G2） |

**独立 oracle**：TL 监视器、像素模型、ECC/CRC 都在 TB 内独立实现（不调用 DUT 的 helper）。

## 5. 未测边界与已知限制（不当作已验证）

* 相机真实几何/相位、RAW10 正式打包、R10F 头/CRC 与 1080p ROI **不在本包**（T11）。
* 本包推帧源是「DDR 灰度/Bayer8 诊断帧」或 ERAM 合成帧；**不声称真实相机 RAW10 已跑通**。
* PHY（serdes 原语）与 IP 行为：仿真只到包层输入；完整路径由 TD 综合/STA + 后续板测覆盖。
* MPS/IOMMU/BDF/PAGE_SIZE 等 RK 侧事实未知；ARM 在链路未起（link_up=0）时被拒是**有意行为**。
* `pcie_ep_engine` 的既有 x3 断言在 CANCEL 深排空时可能触发（peer 自身缺陷，见 `hardware-ready.md` 已知限制）。
* 诊断计数跨域采样不做握手（只读、人看）。

## 7. round1 修复（对 round0 三维 FAIL）

### 7.1 F2（functional/engineering/system 共同缺陷）：冻结候选编译阻塞

* 根因：`cam_ddr_writer.v` 同时存在两处 `reg p_skip_frm;`（405 行 ddr 域声明区与 536 行保护块），
  TD 只当警告并把后者忽略，ModelSim `vlog` 直接报 vlog-2388 中止 ⇒ 四个 TB 全部编译失败。
* 修法：删除 536 行那一处（保留 405 行声明）；语义不变。
* 验证：默认入口（`tools/pcie_integration/run_sim.ps1` + `sim/compile_checked.f`，**无 suppress**）
  重跑四个 TB：全部 `ALL PASS`，`vlog Errors: 0`（`backend/g1/msim/r1_*/`）。
* 证据时间绑定：round1 四个 run 的 `vlog/vsim.log` 时间戳全部晚于本轮所有 RTL 末次修改；
  另在 manifest 自检里逐条复算（`backend/manifest-selfcheck.json`）。

### 7.2 F1（system FAIL）：跨源 release/ownership 契约

* 根因（两条，均在 round0 的 pusher↔writer 契约里）：
  1. pusher 的 `par_valid/par_now` 只拿 **A 路基址**去比对 `ddr_base`；B 路帧（0x0110_0000/0x0190_0000）
     永远 `par_valid=0` ⇒ B 路发布块拿不到任何 release，且 `claimed_par` 被错算；
  2. 两根 release toggle 被 A/B 两片 writer **共享**，A 路的 release 会顺带清掉 B 路同索引块的保护位。
* 修法：
  1. pusher 新增 `BASE0B/BASE1B` 参数，`par_base0/1 = cam_sel_live ? B 对 : A 对`（相机感知）；
     claim 时把 `claimed_cam` 与 `claimed_par` 一起锁存，release 一律按锁存值选块；
  2. release 拆成**两对** toggle：`rel_tgl0/1` → A 片 writer，`rel_tgl2/3` → B 片 writer
     （顶层分别接线；两片 writer 各自的 `protect0/1` 不再被对方的事件清掉）。
* 验证（`tb_ddr_frame_pusher_rka1` 新增两相，默认入口）：
  * PHASE11（B 路）：ARM→claim→整帧→held 期间 B toggle 计数为 0（无提前释放）→匹配 ACK 后 B 恰好 +1，
    A 的 toggle 一个都没动；
  * PHASE12（A/B 交叉）：B 帧 held 期间连续做 A 路发布/pass 释放，B 的 toggle 计数不变；
    随后 B 匹配 ACK 恰好 +1，A 的计数不变。
  两相均 PASS ⇒ round0 system 报告里 `rel0_cnt=0/rel1_cnt=0` 的 B 路现象已消除。
* **给 system 复测者的接口变更提示（重要）**：pusher 现在有 **4 根 release 输出**
  （`rel_tgl0/1` 仍是 A 路，新增 `rel_tgl2/3` 是 B 路），并新增两个**参数**
  `BASE0B/BASE1B`（默认 0x0110_0000/0x0190_0000，与顶层一致）。
  round0 的探针 `test-reports/system-r0-evidence-t07/tb_t07_src_release_probe.v` 只接了
  `rel_tgl0/1` ⇒ 在 round1 上会"看起来 B 路仍然零 release"（其实是从 `rel_tgl2/3` 输出）。
  复测时请把 `rel_tgl2/rel_tgl3` 也接出来并计数（期望：B 路 claim→ACK 后 B 对 toggle 恰好 +1、
  A 对不动；A 路对照仍为 2 次）。

### 7.3 F3（三维共同登记）：manifest 冻结后被追写

* 现象：`backend/candidate/prj/commands.log` 在 manifest 生成 67 s 后被追加 22 B（运行器迟到退出记录），
  导致 240 条里 1 条不匹配。
* 修法（工具侧，不改判据）：`gen_manifest.py` 从 round1 起
  **排除易变日志**（`commands.log / td_*.log / *.logw / abs.f / run.do / vsim_stdout.log`，
  理由与规则写进 manifest 的 `volatile_excluded`），并新增**自检**：生成后逐条复算并输出
  `manifest-selfcheck.json`（本轮结果见该文件；期望 0 不一致）。
  候选身份仍由 bit/DB/报告/稳定日志承担（没有被"排除掉证据"）。

### 7.4 G2（engineering FAIL）：setup 时序 —— **必须由规划者决策，本轮记 blocked**

* 现状（round0 实测，round1 在修复 F1/F2 后重建，见 `g2/README.md` §3）：违例**全部**在
  `cam_a_byte_clk`/`cam_b_byte_clk`（187.5 MHz，SDC 约束不变），最差路径在本包引入的
  `csi_rx_packet_integrity`（`consumed`→keep/CRC 组合链，逻辑级 9、其中 52% 是布线延迟）。
  100 MHz/62.5 MHz 主域与 hold 全部正裕量。
* 为什么不是"一次有界修复"：该模块每拍必须吃满 4 字节（**CSI 不可反压**，插不进流水气泡），
  CRC 是**逐拍递推**（`crc_next = f(crc, 4B)`）——要么做 CRC 的代数/交织改造（2 路交错 + 末帧合并），
  要么把整行缓冲到 ERAM 再在慢域做检查（架构改动），要么改变 187.5 MHz/每拍 4 字节这条前提。
  三者都超出"修复"范围：会改动并需重新验证**本方冻结的 checked 源**（`fpga/csi2/src/csi`），
  且第二三种涉及范围/几何前提。按本轮指令「不得擅自放宽 187.5 MHz 前提或判据；若必须由规划者决策则 blocked」，
  本轮**不擅自改判据、不做未验证的重构**，把 G2 交原规划者决策（选项与证据见 `g2/README.md` §3）。
* 本轮已做：在**不放松任何时序目标**的前提下重建了 G2 候选（新 bit/DB/报告与 round1 输入同源），
  并把实测数字、违例分布、最差路径与三种可选方向一并留在 `g2/README.md`。

## 8. round2 修复（G2 时序：checked 完整性链的**本域**有界重构）

规划决策（dev-plan 文末『T07 修复轮记账与 G2 决策』）：不改相机链路速率/T11 前提，先做本域有界重构。
禁止项照做：**未**放宽 SDC、**未**加 multicycle/max_delay、**未**改 187.5 MHz、**未**改
`fpga/csi2/src/csi` 原源、**未**改 wrapper 对外接口或顶层连线。

### 8.1 改了什么（只在 `rtl/checked/csi_rx_packet_integrity.v` + 新生成文件）

| 手法 | 之前 | 之后 |
|---|---|---|
| ①② 字节级译码 | `consumed`(17bit) + 4 组 17bit 比较器（`< wc` / `== wc` / `== wc+1`）决定 keep / CRC 取字节 / 包尾 | `tail`=还需处理到包尾的字节数；`tail≤7` 时只按低 3 位译码（keep 4 值 + 两个 CRC 字节索引 3bit 小减 + 包尾 `tail≤4`） |
| ② CRC 递推 | 4× `crc_byte` 串行展开（8 次移位+条件异或 ×4） | `crc16_upd1..4` **扁平 XOR 树**（GF(2) 线性化，`rtl/checked/crc16_upd4.v` 由 `tools/pcie_integration/gen_crc16_flat.py` 生成，脚本对 4 个变体各 20030 例随机/边界自检 0 失配），按本拍**实际有效字节数**选择 |
| ③ CRC 比较/计数 | 包尾同拍：`crc_next != received_next` → CRC/坏帧计数器 enable + frame_bad + abort | 包尾同拍只寄存 1 bit `crc_bad_q`；计数/坏帧/abort 在紧随的 `END_PACKET` 第一拍做（状态序列与 round1 完全一致，不新增状态、IDLE/HEADER 相位不漂移） |
| 超时判定 | `frame_age >= FRAME_TIMEOUT_CYCLES-1`、`idle_cycles >= PACKET_IDLE_CYCLES-1` | 对常量**相等**比较（同宽下浅得多） |

数据流语义不变：`O_payload_out/valid/keep` 与像素流**逐拍对齐**（差分 TB 断言 0 失配）；
`O_packet_done`/`O_in_line`/`O_vsync_out`/`O_in_frame`/`O_frame_end`/`O_frame_good` 逐拍一致；
`O_frame_abort` 最多滞后 1 拍、`O_crc_errors`/`O_bad_frames` 最多滞后 1 拍（都远早于本帧 FE 的发布裁决，
差分 TB 用「ref 抬起的当拍或之后 2 拍内」窗口核对；**诊断计数滞后 1 拍已在 g2/README 记录**）。

### 8.2 怎么证明等价（差分 oracle）

新 TB `sim/tb/tb_csi_integrity_diff.v`：同激励喂 **round2 重构版**（生产路径）与
**round1 版**（`sim/tb/csi_rx_packet_integrity_ref.v` = 只读原源 `fpga/csi2/src/csi/csi_rx_packet_integrity.v`
的重命名**副本**，SHA 记在文件头）。覆盖：完整好帧、坏 CRC、WC 边界（5/10/15/78/80）、
行长/WC 与 IMAGE_WC 不符、包内 idle 超时、帧中途停住（帧超时）、坏 ECC/未知 DT/非选中 VC/FE 无帧、
FS 打断（abort）后恢复、复位后恢复、200 个随机包（随机空隙/长度/坏 CRC/WC）。
判定：payload/握手/FE/good **逐拍相同**（680 拍有效载荷 0 失配）；abort/计数器 ≤2 拍窗口 + 静默点全量一致。
结果：**ALL PASS**（`backend/g1/msim/r2_tb_csi_integrity_diff/`）。

> 差分过程抓到并修掉了两个真实缺陷（都是重构引入、被 oracle 拒绝）：
> ① 扁平 CRC 最初固定按 4 字节推进 → keep 不足 4 字节的拍会把补零也喂进 CRC（与 round1 的最小 WC 包不符）；
> ② 最初新增了 `END_PENDING` 状态做计数 → 状态序列比 round1 多 1 拍，IDLE/HEADER 相位漂移，
> 背靠背包头会被 IDLE 吞掉。两处都改为「按实际字节数推进」与「END_PACKET 第一拍做计数」后归零。

### 8.3 G1 重跑（round2 冻结输入，默认入口、无 suppress）

| TB | 结果 |
|---|---|
| `tb_csi_integrity_diff`（新） | **ALL PASS**（见 §8.2） |
| `tb_csi_checked`（真 wrapper+写者裁决/所有权） | **ALL PASS** |
| `tb_ddr_frame_pusher_rka1`（安全门+A/B release+1080p 边界） | **ALL PASS**（20387 TLP） |
| `tb_ep_bar_win_rka1` / `tb_ddr_wr_arb` | **ALL PASS** |

日志：`backend/g1/msim/r2_*`（`vlog Errors: 0` + `vsim ALL PASS`，时间戳晚于本轮 RTL 末次修改）。


### 8.4 G2 重建（round2，单会话 `00_all`；按派发"最多两次"记账，**第 1 次即达标**）

| 项 | round1（F1/F2 修复后） | round2（本轮重构后） |
|---|---|---|
| SWNS / STNS | −2.507 ns / −300.004 ns（181 端点） | **+0.107 ns / 0.000 ns（0 端点）** |
| 最差路径 | `…mux153…clk → O_crc_errors_reg[0].ic`，逻辑级 10、61% 布线、7.710 ns | `u_csi_a/u_gear_box/r_byte_buffer_reg[55] → O_bad_frames_reg[30].cea`，逻辑级 6、54% 布线、4.982 ns |
| clk2/clk3（187.5 MHz 字节域） | −2.503 / −2.507 | **+0.107 / +0.130**（R-Period 5.225/5.202 ns） |
| hold | +0.020 | +0.020（HWNS） |
| 资源 | LUT6 19.45% / ERAM 134/300 | LUT6 19.13% / ERAM 134/300 |
| `TMST-7700` SEVERE | 5 | **5**（更正：见 §10.2——即 chk.timing 的 2 无根时钟网 + 3 local clock，与 round0 同类且已逐项解释；本表 round2 一度误记为 0） |
| bit SHA | `3F2E48E8…B977`（负裕量，留痕） | **`0943CB36…8B0A`**（5,224,023 B，与 `best_result/` 同 SHA） |

命令与完成标记：`run_td.ps1 -Stage 00_all`（syn 05:55:01–05:57:24 + phy 05:57:25–06:03:43；
`PRJ-1406`/`PRJ-1424`/`T07_ALL_DONE`）。STA head：`Generated Sat Oct 17 06:03:23 2026`、**Routed**、
Both corners、CRPR on。逐项解释与余量节制见 `g2/README.md` §3.5/§3.6/§5。

### 8.5 round2 的两处如实登记（不构成判据放宽）

1. **余量薄**：+0.107 ns，worst path 54% 是布线、该域跨两片 CSI + 两片 writer。本包**不做** ECO/重综合
   （保持"源↔位流"绑定），后续任何改动都应把"相机字节域 setup ≥ 0"当回归门槛（`g2/README.md` §3.6）。
2. **`END_PACKET` 留了一段不可达旧行**（同一 case 里两段 `END_PACKET:`）：本轮把 CRC 计数折进既有状态时留下的死代码。
   功能上按 Verilog 标准**首项命中**执行，两段共有动作相同；TD 的门级/布线 STA 报告里存在 `crc_bad_q_reg` 端点路径
   → 说明综合器保留了首项（实际生效）逻辑；ModelSim 编译 0 错、差分 oracle 与 4 个 G1 TB 全 PASS。
   改掉它要重综合（换位流、重跑 G2），按"停止修改后冻结"的纪律**不改**，如实登记。

### 8.6 其余交接修正（来自三份报告的次要项）


* `build-entry.md`：明确 01/02/03 分阶段脚本**仅作参考**（TD 分阶段会丢 `device_name/package_name`），
  实际入口是单会话 `00_all`；补充 peer arb TB 的**模块名是 `tb_ddr_wr_arb`**（文件名是 `tb_ddr_wr_arb_peer.v`）。
* `g2/README.md`：更正 C-Period/R-Period 表述（C=5.332 ns 是约束、R=7.676 ns 是实际达成），
  并逐项说明约束/DRC 告警（无根时钟/局部时钟/无 IO delay/`sys_clk_dup_1`/`STA coverage`）。
* `change-report.md`：注明 `ui_cfg_imx415.v` 的 `ic_busy` 无驱动（peer 原样继承，仅接调试位）
  与 `ui_i2c.v` 的初值告警同为 peer 原样，非本包引入。
* `backend/backend-patch-in-rk-driver-src.patch`：是 `patches/rka1-driver.patch` 的重复副本（SHA 相同），
  不属候选输入；已在 `source-provenance.json` 说明归属。

## 9. 回退与边界

* 全部改动都在新目录：删/换 `fpga/csi2/pcie_integration/` 与 `tools/pcie_integration/` 即回到起点；
  旧主线、peer 参考库、D 盘工程与 002820 候选**未被修改**（回退到旧 bit 仍然可用，见 `hardware-ready.md`）。
* RK 侧：`backend/patches/rka1-driver.patch` 对精确 peer 快照 `git apply -p1` 通过；
  `git apply -R -p1` 可逆；不应用补丁时旧驱动**不能**驱动本候选（fail closed 是设计）。
* 本包不操作硬件、不下载、不写 Flash；位流的板测/发布资格由后续 system 任务与用户决定。
* **round2 收口状态**：G2 达标（§8.4），两处如实登记见 §8.5；round0/round1 的失败证据（三维报告、
  round0/round1 的负裕量数字与旧 bit SHA）保留在 `../test-reports/`、`g2/README.md` §3.1/§3.2 与本节，
  不删除、不覆盖；本轮停止修改之后**不再**有 RTL/约束/TB 变更（manifest 复算可证）。

## 10. round3 修复（仅工具/文档；RTL/SDC/约束/bit/DB 与测试输入一律未改）

### 10.1 F1（functional r2 的 FAIL 主缺陷）：默认入口在文档化调用下中止 —— 已修复

**缺陷**（`test-reports/T07.rk-align-backend-r2-functional.md` §2；engineering r2 F1 同）：冻结的
`tools/pcie_integration/run_sim.ps1`（UTF-8 **无 BOM** + LF + 中文注释）在 `powershell -File` + PS 5.1
（ACP=936）下被按 ANSI 解码：.NET CP936 会把"行尾悬挂的首字节 + LF"并吞成一个字符 → 源 144 行在 PS 视图里
只剩 136 行（`run_td.ps1` 81→76）；被吞的一处正好把源 L123 `$doPath = Join-Path …` 并进上一行中文注释 ⇒
`$doPath` 未定义 → `WriteAllLines($null)` 抛"空路径名是非法的" → 在 vsim 之前中止；`-File` 下进程
**exit 0**（判据必须是产物：`run.do`/`vsim.log`/完成标记）。

**本机复现（入口负对照，证据 `backend/g1/msim/r3_entry_before_fix/`）**：文档化命令
`powershell -ExecutionPolicy Bypass -File tools/pcie_integration/run_sim.ps1 -Tb tb_csi_integrity_diff -OutDir … -TbFiles tb/tb_csi_integrity_diff.v`
→ `vlog.log` 有（Errors: 0）、**无 `run.do`、无 `vsim.log`**、stderr 一条 `WriteAllLines … 空路径名是非法的`、
进程 exit 0；PS 解码实测 `Get-Content` 136/76 行 vs `.NET ReadAllLines` 144/81 行（`decode_view.txt`）。

**修复（最小、可逐字节复核）**：给两个 `.ps1` **前置 UTF-8 BOM**（`EF BB BF`），内容**逐字节不变**：
* `run_sim.ps1` 6436→6439 B，SHA `33399210…` → **`204d17067989c1af…`**
* `run_td.ps1` 3446→3449 B，SHA `760c5524…` → **`9b8492fcae97a563…`**
* 修后 PS 5.1 视图恢复 144/81 行、`$doPath`/`$tclDst` 语句完整（`decode_view.txt`）。
未采用"CRLF 化 / 注释纯 ASCII"（等价可选方案，但改动面更大、不便逐字节复核）；`.tcl`（TD 的 Tcl 按字节
解析、不按 ANSI 解码）与 `.py`（Python 3 源码默认 UTF-8）确认**不受**该缺陷影响，未改。

**修复后本机实测（文档化默认命令原样；证据 `backend/g1/msim/r3_*/`）**：五个 TB 全部
`vlog Errors: 0` + `run.do`/`vsim.log` 齐备 + `cmd /c vsim …` / `vsim exit=0` + `ALL PASS`
（差分 TB `680 拍 0 失配`；pusher 20387 TLP），时间 06:50:10–06:50:30。
**oracle 负对照**（项目外隔离树注入 M1 = `crc_next` 固定 4 字节推进，用修复后的默认入口平台复跑）：
`FAIL: 507 mismatches`（与 functional r2 §5 的 M1 同值）；证据 `backend/g1/msim/r3_neg_m1/`
（原始运行日志；其中 `mutation.json` 因原实例中断未落盘——新修复实例的完整复跑见 §10.5 / `r3v_neg_m1/`）。

**诚实补记（functional §2 假设①的答案）**：round0–round2 开发侧的实际调用**不是**文档里的
`-File <冻结脚本>` 原样形式，而是"`Get-Content -Raw` 读正文 → `Set-Content -Encoding UTF8` 写 `%TEMP%`
副本 → `-File` 跑副本"（PS 5.1 的 `Set-Content -Encoding UTF8` 会写 BOM，所以副本可用）。
即可运行性来自这个**未记录在案的副本路径**，冻结字节在文档化命令下确实不可运行。本轮把 BOM 固化进
冻结脚本，**文档命令 = 实跑命令**，不再需要任何 launcher/副本；命令记录以 `actual-commands.json`
round3 为准。

### 10.2 F2（文档数字）：round2 `TMST-7700` SEVERE 记错 —— 已更正为 5

实物证据：`backend/candidate/prj/ph1p_pcie_integration_Runs/phy_1/run.log`
L1104（place 阶段）`DRC TMST-7700 CRITICAL-WARNING: 2 SEVERE timing constraint issue(s)`、
L1796（post-route/final）`… 5 SEVERE …`。这 5 项 = `chk.timing` 的 **2 无根时钟网**（`pcie_pll_locked`、
`tl_clk_user_ce_n`，被误当候选时钟网）+ **3 local clock**（cam_a/cam_b 字节时钟、`sys_clk_dup_1`），
与 round0/round1 同类、逐项解释见 `g2/README.md` §5；**不是** setup 违例的另一种说法。
更正位置：本报告 §8.4 表、`g2/README.md` §3.5 表与 §5 表（原记 0 的出处）；其余数字不受影响
（SWNS/STNS/HWNS/资源/bit SHA 均已被 engineering r2 逐项实读一致）。
方法教训：原判据用"grep `*.timing` 里的字面量 `TMST-7700`"推断计数——DRC 告警在 `run.log`，
`*.timing` 不含该字面量；以后数字类结论一律实读**原始 run.log/报告**并留行号。

### 10.3 未修项与残余登记（如实，均不影响判据）

* **F3（engineering r2）**：`rtl/checked/csi_rx_packet_integrity.v` 头注释仍写"新状态 END_PEND"（实际无该状态）。
  **本轮不改**：改注释即改生产 RTL 字节 → 破坏"源↔位流"绑定（需重综合/重跑 G2），不在本任务 round3 授权范围；
  下次触碰该文件时一并修正（engineering 亦建议"随下次触碰修正即可"）。
* **F4（engineering r2）**：`backend/g1/crc16_upd4.generated.v` 是早期单体变体中间产物（非冻结生产文件
  `rtl/checked/crc16_upd4.v` 的副本）——已在 `g1/README.md` 就地标注（不删，保留可核）。
* **functional r2 §6.1（覆盖缺口）**：差分 TB 未覆盖"`I_enable` 在包尾后 1 拍内撤销"的角落——该拍计数在
  `END_PACKET` 首拍被 `!I_enable` 分支清掉，`crc_errors` 可能少计 1（round1 在同拍计数）。已知影响面：
  **仅诊断计数**、控制路径（abort）仍经 disable 分支生效、窗口极窄（需恰好在该拍撤销 enable）。
  **本轮不改 TB/RTL**（TB 不变才能复用 functional 的差分负对照 M1/M2 证据）；登记为 T11/后续任务增补用例
  （`lessons-learned.md` §8 同记）。
* **engineering 观察 2**：仓库根未跟踪文件 `run2.do`（19 B，06:27:20）不在本包候选范围（不属任何 manifest 条目），
  归属由原规划确认后处置；本包不动。

### 10.4 round3 的变更范围（机械证明：tool-only）

对 round3 manifest 的 232 条逐条比对 r2 冻结时刻（06:04:56）之后的写入：**恰好 3 个文件**，全部是
`build_scripts`——`run_sim.ps1`、`run_td.ps1`（BOM 修复）、`gen_manifest.py`（round3 文案 + `rtl/checked/`
下新生成文件的来源判定小修）。production_inputs 153 / test_inputs 8 / rk_patch_inputs 28 / build_artifacts 35
**零变化**（生产 RTL `50b4c77b…`、bit `0943cb36…8b0a` 逐字节不变）。
⇒ 满足 engineering r2 §10 的复用条件（"仅 tool/doc 修复且不改 RTL/约束/bit"），其 G2 判定可复用；
functional 需按默认入口原样复跑全量（本包 r3_* 提供新证据，仍需独立复跑）；system 需绑定新 manifest。

## 10.5 交接补记（新修复实例执行；原实例上游请求超限失效）

round3 的修复与证据由原实例完成至近尾声（BOM 修复、`r3_*` 证据、F2 更正、manifest/文档/dev-result 均已生成）后会话中断。
主按"实际可续性核对"重建**新修复实例**接续（不假称续接原会话；write_scope 与原任务一致）。新实例只做
"只读复核 + 补齐证据 + 文档记账"，**未再触碰任何冻结输入**：

1. **逐项复核原实例产物，结论全部成立**：两个 `.ps1` 的 BOM 与 SHA（`204d1706…`/`9b8492fc…`）实读一致；
   `r3_*` 五个 TB 日志（`vlog Errors: 0` + `cmd /c vsim` + `vsim exit=0` + `ALL PASS`）实读一致；
   `r3_entry_before_fix/`（修复前中止留痕）与 `r3_neg_m1/`（`FAIL: 507 mismatches`）实读一致；
   manifest 232 条独立复算 0 失配、候选三树 0 晚写；bit `0943CB36…8B0A` 重算一致。
2. **独立复跑（文档化默认命令原样；新证据 `backend/g1/msim/r3v_*`）**：五个 TB 全部 `vlog Errors: 0` +
   `run.do`/`vsim.log` 齐备 + `vsim exit=0` + `ALL PASS`（差分 `680 拍 0 失配`；pusher 20387 TLP；
   时间 07:10:26–07:10:47）——与 `r3_*` 完全一致。
3. **负对照复跑**：
   * `r3v_neg_m1/`：隔离树（`%TEMP%/opencode/r3negv`，新建）重注入 M1（shadow SHA `e0e08a86…` 与原 run
     完全相同）→ `FAIL: 507 mismatches`；本目录含**完整 `mutation.json`**（frozen `50b4c77b…` 未动）。
   * `r3v_entry_before_fix/`：以"冻结件去除 BOM 的**逐字节副本**"（＝修复前字节；SHA
     `33399210c389818a…`/`760c5524c3dddf16…`，与 r2 记录前缀吻合——完整值由本目录 `decode_view.txt` 固化）
     按文档化命令形式复跑：`vlog Errors: 0` 后 `无 run.do/vsim.log`、stderr `WriteAllLines…空路径名是非法的`
     （PS 视图 L116）、exit 0——修复前失败签名 100% 复现；`r3v_entry_ast.txt` 佐证（frozen→`$doPath`/`$tclDst`
     赋值语句=1，no-BOM→0；PS 视图 144→136 / 81→76 行）。
4. **补齐原实例中断未落盘的产物**：入口 AST 语义证据即上述 `r3v_entry_ast.txt`。另发现：原实例在
   `r3_entry_before_fix/entry_ast_check.ps1` 里写的校验脚本**自身**是"UTF-8 无 BOM + LF + 中文注释"，
   被同一缺陷击中（`$PSScriptRoot` 赋值被并进注释 → `null`），运行即失败、未产出任何文件——失败留痕在
   `r3v_entry_before_fix/old_ast_script_attempt.txt`；新实例用纯 ASCII 等价脚本完成该检查。
5. **manifest/自检**：按 `gen_manifest.py` 重生成一次（07:14）——输出与 06:51 冻结**逐字节相同**：
   `68f9f4d05dd219cf4f66009a5bed1bdd6c1dcc7e1a4a386a8974725b733a4275`，自检 232/0。即本轮脚本"新 SHA"
   保持不变，三轮测试仍绑定同一 manifest。
6. **冻结边界**：RTL/SDC/约束/bit/DB/测试输入零变化；本补记新增内容全在 `backend/g1/msim/r3v_*` 与本
   `backend/*.md|json`（均不在 manifest 条目内）。`r3_*` 原证据保留未动，`r3v_*` 与之并存。

