# PCIe 统一最终路径对接评估（run 20261016_2110_pcie_unified_path）

- 角色：规划者（只读评估）；日期：2026-10-16。**本步只评估：未改用户任何代码/工程，未执行外部仓库任何脚本，未改 `D:\TD` / `D:\downlaod` / 任务板 / 其他 run；唯一写入=本 run 目录。** 外部材料引用以 commit/SHA 记账。
- 需求：用户侧最终输出由 HDMI 转 PCIe，并与队友侧（PCIe 已"基本跑通"）统一最终路径；回答"哪些用户侧改以适配队友、哪些队友侧改以适应用户"，给出接口合同要点、依据与信息缺口。
- 输入：两仓库本地副本（`C:\Users\czz\AppData\Local\Temp\opencode\ref_ph1p100_fpga`、`ref_ph1p100_driver`）；上一 run `20261016_185639_td_cli_iptool` 的 input-index §6 / dev-plan §4.1 / user-summary / upgrade-review；本项目现行入口、任务板与 10-16 整合记录；Bayer 工作树（只读）。全部只读核对。

---

## 0. 结论速览

| 问题 | 结论 | 主要依据 |
|---|---|---|
| 统一到哪条数据面？ | **传输层采用队友的"EP 主动 MWr 推帧＋门铃＋mailbox"通路**（目前唯一已实现且自称已上板联调的形态）；**内容层采用用户侧 R10F 帧头＋载荷（后续 BPR1）**。用户侧"C2H 固定块"计划**不是第二条竞争数据面**：它在 TL 层与前者同族（EP 发起 Posted MWr 写主机内存），其验收要点（授权地址/容量、MPS/4KiB、尾字节、所有权、完成可见性）转为在该通路上核对/补强的清单。 | §2；其 `ddr_frame_pusher.v`（SHA `6FDB7CCD…`）、`anlogic_pci_ioctl.h`（`CC27F482…`）；用户 `c2h_fixed_pattern_tx.v`（`D31BC322…`）为抽象仿真、未接硬核 |
| 谁改得多？ | **用户侧为主**：TD 6.2.3、EP 核/约束接入、寄存器窗/推帧后端集成、帧内容成帧、主机侧解码与板测。**队友侧为参数化与确认**：1080p 帧几何、尾突发、TLP 计数位宽、驱动几何/缓冲、多路语义、RK 环境与联调支持。 | §3 拆分清单 |
| 最大不确定性 | ①队友"基本跑通"的精确边界（主机是否已实收并验证整帧）需其本人确认；②DDR IP 定案（其 800E/AXI vs 用户 1600K/PAXI）；③双路与轮换语义；④TD 6.2.3 获取与 IP 版本差。 | §7、§8 |
| 本轮新发现的复核点 | R1：推帧目标=槽像素起点（+16B），128B MWr 每个 4KB 边界各有一笔跨界（PCIe 要求 Memory Request 不跨 4KB）；R2：推帧 TLP 计数为 12 位，1080p RAW10 帧需 20,251 笔/帧，超位宽；R3：AXI 4KB 突发尾块（2,592,128/4096 不整除）。 | §5 |
| 建议下一步 | 见 §6 分级联调判据与 `dispatch.json` 的 recommended_next（**仅供以后立项，本步不派发**）。 | — |

---

## 1. 两侧现状（只读核实；外部结论按"文件内容/提交自述/用户转述"分级）

### 1.1 队友侧——FPGA 仓库（`xiaozhuABCD1234/ph1p100-pcie-ep-fpga`）

- HEAD `654ef176e983711436432e7a7d29af744754977d`（2026-10-16 18:56 +0800），完整历史 28 提交；TD 6.2.3.210850（Release_2026.2，Linux）。同为米联客 MLK-F9P（PH1P100SBG484）。
- 工程资产：`al_ip/pcie_ep_core`（`BE3A63A9…`，ipGenVersion `171484 2025/08/11`）、`al_ip/pcie_pll_ep`、`al_ip/ram`、`al_ip/ddr3_mc_0`（`4D7060F8…`：**DDR3-800E/CL6/CWL5/x16 2048Mb/×32/`PH1P_MC_AXI=1`、`PH1P_MC_PAXI=0`**、refclk 50MHz、DRC PASS）、`constraints/ph1p_pcie_case_ep.{adc,sdc}`、`rtl/ep_side/**`。
- **数据面实现（核心）**：
  - `rtl/ep_side/img/cam_fb_writer.v`：IMX415 A 路 4K 取中 640×480 写片内帧缓存（跳 4K 帧头哑行，`CAM_X0/Y0/SKIP_ROWS`）。
  - `rtl/ep_side/img/ep_bar_win.v`（`D614D28F…`）：**BAR0 寄存器窗**——0x40 MAGIC=`0x50434946`、0x44 CTRL（bit0 enable、bit4 cam_sel、bit5 ddr_en、**bit6 push_en、bit7 push_src**）、0x50/0x54 W/H、0x58 DATA_LEN、0xA0-0xAC DDR 握手、**0xB0/0xB4 推帧目标地址、0xB8/0xBC 门铃地址、0xC0 已推帧数、0xC4 状态、0xC8 错误码、0xCC 上帧 MWr 数**。
  - `rtl/ep_side/ddr/ddr_frame_writer.v`（`838D502A…`）：整帧写 DDR3，双缓冲 1MB/1.5MB、每帧 307200B、AXI4 256bit、4KB 突发。
  - `rtl/ep_side/ddr/ddr_frame_pusher.v`（`6FDB7CCD…`）：**EP 主动推帧引擎**——每 MWr=4DW 头+128B 载荷（`PAY_DW=32`），每帧 2400 笔；整拍 256bit 字节倒序；每笔间留 1 拍让路给主机 MRd 完成；尊重 `tl_tx_wait`（保持数据）；超时 0xFFFF 拍≈1.05ms；推完单独一笔门铃（单 DW，LastDWBE=0，内容=已推帧数）；错误码 1..4；**目标/门铃地址全部由主机寄存器给出，EP 不写死物理地址**。
  - `rtl/ep_side/pcie_ep_engine.v`（`451B05EC…`）：新增 `TL_TX_USER` 态与用户侧 TL 发送口（`utx_req/sel/data/valid/sop/eop`），推帧 TLP 走此口、最低优先权，与 BAR 完成包包级仲裁。
- 其提交自述的板级证据（**外部自述，本评估未复现**）：`5670a85` "寄存器窗口总线接反修复……新增三个测试台 iverilog 全通过；**板上复测推帧四条判据通过**"；`654ef17`（最新）"……**推帧仍是每帧 2400 个 MWr、错误寄存器恒为 0**，与改动前一致"；`8ab8478` DDR 顶层接入自述构建/布线/bit 通过。其 README 另自述部分 TB"本机没有仿真器，只写不跑"（与 iverilog 自述存在出入，以本人确认的清单为准）。
- 历史文档（其 HEAD 已删除，从 git 历史提取，上一 run 存于 temp）：`ref_cam_frame_pcie_verify.md`@`78656bc^`（`2B68244A…`）：**相机像素经 BAR0 PIO 读到主机的端到端实测**（Bayer 2×2 颜色序判据、帧号递增、PIO 撕裂说明、SDC 过期提示）——这是目前两仓库中最强的"真实相机→主机"实测记录，但走的是 **PIO 读**，不是推帧 DMA。

### 1.2 队友侧——驱动仓库（`xiaozhuABCD1234/ph1p100-pcie-ep-driver`）

- HEAD `ad350ca495f9b2a40c9b93f156093f4d128b6758`（2026-10-16 17:27 `fix(drv): 推帧目标从槽基址改为槽像素区起点`）。**注意：本地副本为浅克隆（`rev-list --all --count`=1），无历史**——其进展脉络与"何时实测"只能向本人确认或另行补取。
- 内核模块 RK3588：设备 `0x1edb:0xabcd`；节点 `/dev/ANLOGIC-PCI0_{control,user,frame}`；用户 BAR=BAR2；MMIO 门禁（先读 BAR0+0x40 MAGIC、单笔≤4DW、读到全 F 熔断）。
- **收帧 ABI**（`include/anlogic_pci_ioctl.h`，`CC27F482…`，驱动/用户态/FPGA 三方唯一一份）：ioctl 编号与结构体只增不改（magic `'x'`/`0x586C0C6C`）；缓冲布局=槽区 stride×slots（stride=PAGE_ALIGN(16+slot_bytes)，槽头 16B `{seq,len,flags}`）+ mailbox 64B 页（magic/seq/count/slot_bytes/slots/stride/width/height/push_dbell）；**MWr 目标=phys+stride*槽+16（槽像素区起点）**；门铃由 FPGA 写"已推帧数"，**驱动在轮询时补槽头与 mailbox.seq/count**；上限 slot≤64MB、slots≤16、wait≤600000ms；默认几何 640×480、**默认单槽**（推帧目标固定不轮换）。
- 探测即武装：写 CTRL 使能位、推帧目标=收帧缓冲 DMA 地址、门铃=mailbox 页内门铃字；`link_ctl` 提供查询/重触发/重设地址。
- 可见性：RC 设备树未标 dma-coherent → Normal-NC，FPGA MWr 落 DRAM 后 CPU/用户态直读可见；若将来改 cacheable 映射必须补 `dma_sync_single_for_cpu()`（其注释已写明）。无 MSI（Legacy 中断，收帧只轮询）。
- 用户态 Rust 五工具：`cam_grab`（PIO 抓帧，直读 sysfs resource0）、`frame_grab`（取收帧缓冲）、`link_ctl`、`pci_bar`、`pcie_check`。
- **状态表述差异（缺口 G1）**：驱动 README/源码头仍写"**真正的收帧等 FPGA 侧打通后再验**"（可能早于近期联调修复），而最新提交在修"推帧目标=槽像素区起点"——两者时间线需队友本人澄清：**主机是否已实收并验证过整帧**（帧质量/字节一致性证据）。

### 1.3 用户侧（本项目）

- FPGA（`fpga/csi2/`，主线工作树 `codex/ddr-timing-margin`）：单 A 4K30 RAW10 接收（几何/计数/长稳待补）、RGB565 预览经 DDR→HDMI；`src/pcie_top.v` **仅占位**（收发绑零、未接硬核）；工作树新增 `src/pcie/c2h_fixed_pattern_tx.v`（`D31BC322…`，"抽象 ready/valid 单任务固定图案 MWr"仿真合同，**明确不接 PCIe IP**；证据 `c2h_fixed_pattern_20261015.json` 仿真通过）；`src/mem/ddr_frame_store.v` 用**原生 PH1P PAXI**（非标准 AXI）；现役 DDR IP=**1600K、PAXI=1/AXI=0**（002820 冻结工程 `Design.xml` 实测读取）；DDR1333 候选 blocked（升级/GUI 解）。
- 接口工作：`docs/PCIe固定块C2H_接口核对与下一步_2026-10-15.md`（`B3DD7B68…`）——官方 EP 引擎/TL 端口逐条核对（256bit 数据、8bit DW-valid≠byte keep、wait/credits96bit 未文档化、BDF 写死等）+ 最小所有权契约 + 包 A/B/C 计划；`parallel/docs/帧与元数据接口合同_2026-10-15.md`（`9D1D2988…`）——R10F 128B 小端帧头与 CRC32 定义、RAW10 packed stride=width/4*5、非压缩语义（双方未冻结）；`parallel/pcie/first_test_data.py`——**PCIT 32B 块头**固定测试块生成/校验（联调首件）；`tlp_pack_ref.py`/`run_e2e_soft_path.py`——MPS/4KiB/BE 分包 oracle 与软件重组。
- 工具链：TD 6.2.2.200067；用户本轮决定升 6.2.3 对齐队友。升级审核 `upgrade-review.md` 结论：**取决于条件（大概率能解决、4 条件未闭环）；GUI（190248 包）为确定性保底**；决策点含获取渠道/并行安装/双版本纪律。
- RK 侧：PC 离线解码/立体/深度参考齐备（`parallel/rk/frame_decode.c`、`ingest_raw.py` 等）；**RK 执行者/环境/交付未确认**（T05 blocked、T07/T11 依赖 T03）。
- 任务板：T03（接口/压缩封装，ready，`owner_confirmed:false`）、T07（PCIe 固定数据 C2H DMA，backlog，依赖 T03）、T11（DDR→压缩→PCIe→RK 集成，backlog）。

### 1.4 可确认的"共同基础"

- 同一块板（MLK-F9P，PH1P100SBG484）+ 同一厂商例程谱系：用户本机即有官方 `D:\TD\work\peripheral\12_pcie_gen2x2\`（其接口核对 E1-E9 逐行引用）；队友仓库为其演化版。
- 同一 DDR IP 家族（`MIS_DDRF6F1D0P0` 1.2）但配置不同（800E/AXI vs 1600K/PAXI）；同一 IMX415 相机；用户=EP、RK=RC 的角色分工两边一致。

---

## 2. 数据面路线评估：统一到哪条、怎么切

### 2.1 两条路线的本质对比

| 维度 | 队友：寄存器/帧推式（已实现） | 用户：C2H 固定块计划（合同/仿真） |
|---|---|---|
| TL 层机制 | EP 主动 MWr（Posted）连续写主机 DMA 缓冲 | 同族：EP 主动 MWr 写主机授权缓冲 |
| 成帧 | 整帧直推，无块头；帧=固定 W×H 字节 | 32B PCIT 块头（联调）；生产帧=R10F 128B 头+载荷（后续 BPR1） |
| 目标地址 | 主机经 0xB0/0xB4 给；固定不轮换（槽 0） | 主机给授权地址+容量；FPGA 校验 |
| 分包 | 每 MWr 128B（PAY_DW=32），4KB AXI 突发读源 | 按 MPS/4KiB 切分；尾字节/BE 规则 |
| 完成通知 | 数据后单笔门铃（已推帧数）；Posted 不超越；驱动补齐 seq/槽头 | "DONE=提交到 TL"；主机可见完成与 ACK/回收待定义 |
| 验证等级 | **板级：2400 MWr/帧、错误 0（自述）**；主机实收待确认 | **仿真合同通过（不接硬核）**；硬核/credit/时序未验 |
| 缓冲所有权 | 单槽固定；未定义 ACK/回收 | 未回收前不得复用（设计提案） |

### 2.2 裁决与拆分方式

1. **统一到"MWr 推帧"传输层**：它把最贵的不确定性（EP 核/IP/链路/寄存器窗/TL 用户口/字节序/反压）已经落成可上板代码，用户侧自建第二条 C2H 通路没有额外收益。
2. **内容层保留用户侧资产**：R10F 帧头（+CRC）与后续 BPR1 由用户侧生成，传输对其**完全不透明**（pusher 只搬字节）→ 无需队友理解压缩格式，队友也无需改 TLP 构造。
3. **用户的固定块计划并入该通路作为首件**：`first_test_data.py` 的 PCIT 块（32B 头+载荷、CRC/序号）可直接作为推帧源数据（1KB 级），在统一通路上完成"双方各验一遍"的老目标；不需要另建 C2H 硬核支路。
4. **用户 C2H 合同必要项转核对清单**（不丢弃）：
   - 授权地址/容量：队友通路已要求"主机给地址、EP 不写死"；**补**容量/长度语义（定长槽 or 长度寄存器）。
   - MPS/4KiB：128B/笔恒不跨 4KB **仅当目标地址 128B 对齐**——当前 +16B 不满足（见 §5 R1）。
   - DW-valid：沿用队友已验证的 TL 用法，但"255:224 放 DW0""字节序"仍须以 PCIT 全链路字节对照实测固化。
   - 完成可见性：先按"门铃=完成标记；主机轮询 mailbox.seq；单槽不复用，回收语义后置"冻结首版。
   - 所有权/回收/取消：双路与多槽同批（C5）。
5. **不采用的形态**：不在用户侧另建第二条 C2H 仿真/硬核支路；不改用户相机/CSI/压缩前端去迁就传输；不因统一而移除 HDMI 调试出口；本期不引入 MSI/中断（轮询已够）。

---

## 3. 拆分清单（"用户侧改 / 队友侧改 / 双方约定"）

### 3.1 用户侧改（适配队友）

| 编号 | 内容 | 依据/说明 | 前置 |
|---|---|---|---|
| I1 | 完成 TD 6.2.3 升级/并行安装；核对队友 EP 核/PLL IP 在本机（Windows）重建或直接复用其 IP 文件（版本 `171484 2025/08/11`；DDR IP 版本 `208212 2026/08/14` 待核） | 用户本轮决定；upgrade-review §7 决策点 1/2/4 | 安装包获取 |
| I2 | **FPGA 后端集成**：以用户 csi2 为最终工程主线，逐模块引入队友的 PCIe 后端——EP core/PLL、`constraints/ph1p_pcie_case_ep.*`、`pcie_ep_engine` 的 `TL_TX_USER` 改动、`ep_bar_win` 寄存器窗、`ddr_frame_pusher`（及按 C4 决定的 DDR 写侧）；保留用户相机/CSI/帧缓存/多算法/压缩前端 | 队友模块均为相对独立的文件（pusher/writer/bar_win 无相机依赖） | I1；C4、C7 |
| I3 | **帧内容成帧**：R10F 128B 头+RAW10 packed 载荷写入 DDR 帧区（1920×1080：stride 2400B/行、`raw_bytes=2,592,000`、帧=2,592,128B）；填充/长度规则按 C2/C3 冻结；CRC32 沿用现有 `crc_byte`（与合同逐位一致） | 合同：`9D1D2988…`；CRC 一致性已静态核对 | C2/C3 |
| I4 | 推帧数据源适配：若 C4 保留用户 DDR（PAXI 1600K/1333），把 pusher 的"读源"从 AXI 4KB 突发移植为 PAXI 读（握手/字节序/仲裁照其注释语义）；若 C4 改用队友 DDR（800E/AXI），则把用户写帧侧接到 AXI/AXI writer | 用户 `ddr_frame_store.v` 为原生 PAXI（注释明示非标准 AXI）；队友 writer/pusher 为 AXI4 256bit | C4；I2 |
| I5 | 参数化与修缺（与队友分工见 C7）：1080p 帧几何、尾突发、TLP 计数位宽、DDR 帧基址≥2×2.6MB 且 4KB 对齐、多目标/轮换（若双路归 FPGA） | §5 R2/R3/R6 | C3/C5/C7 |
| I6 | **主机侧集成**：RK 上使用队友驱动；自备 R10F 解析（移植 `frame_decode.c` 思路）、后续 BPR1 解码、立体/深度/NPU 链路；联调脚本与证据按 `workflow/README.md` 5.1 留痕 | 用户侧职责范围 | 队友 T3/T4 |
| I7 | 板测：L0-L6 分级判据（§6）在统一候选上执行；HDMI 保留为调试出口；唯一上板入口与回退版本按流程 5.1 第 7 条 | 流程要求 | I1-I5 |

### 3.2 队友侧改（适应用户）

| 编号 | 内容 | 依据/说明 |
|---|---|---|
| T1 | **澄清并更新"基本跑通"的证据边界**：链路/BAR/PIO/DDR/推帧/主机实收各自到什么程度；提供实测日志（含 `frame_grab` 收帧输出/校验）；修正 README 中"真正的收帧等 FPGA 接通后再验"的过期表述 | §1.2 缺口 G1；用户转述与文件文本存在差异 |
| T2 | 推帧/搬运**参数化**：帧长按 W×H（或长度寄存器）而非编译期整除；非 4KB 倍数帧的**尾突发**处理；**TLP 计数加宽**（12 位→1080p 需 20,251 笔/帧）；DDR 帧基址间距与 4KB 对齐 | §5 R2/R3；`ddr_frame_pusher.v` `reg [11:0] tlp`/`NTLP_M1 [11:0]`、`NBURST=NBEATS/BURST_BEATS` 整除假设 |
| T3 | 驱动：确认/支持 1080p RAW10 帧几何与 2.59MB 槽（`frame_slot_bytes` modparam 已有，上限 64MB）；**槽头 `len` 语义**（当前恒=slot_bytes；BPR1 变长后需"实际长度"或继续定长填充）；`ANLOGIC_IOCFRAME*`/LINK*/PUSHCFG 按"只增不改"扩展（若双路需要） | `anlogic_pci_frame.c`（`57C24BF8…`）、ioctl 头 |
| T4 | 提供 RK 联调环境信息与操作支持：内核 release/源码、IOMMU、CMA 规模、MPS、实际 BDF、dmesg；能否承担板端联调 | 用户接口核对 §"向队友一次索取的精确信息"1-4 |
| T5 | 若 C4 定为队友 DDR（800E/AXI）：确认双路+25%预算下的余量结论（计算上够，需实测）；若保留用户 DDR/PAXI：确认其 pusher 只搬内容、不绑定其 DDR 用法 | C4 |
| T6 | 可选：`cam_fb_writer`/`ddr_frame_writer` 确认**不强制进入最终链路**（用户已有等效或更强前端与 DDR 通路），保留为参考 | I2；避免重复建设 |
| T7 | 共享改动（pusher/驱动参数化）明确在哪个仓库、由谁改、如何回流给用户（C7） | 两仓库当前只有队友提交权 |

### 3.3 双方约定（共同冻结，缺一不进入板级联调）

| 编号 | 约定项 | 内容要点 |
|---|---|---|
| C1 | 传输合同 | EP→主机 MWr；目标/门铃地址经 0xB0-0xBC；"单帧在途"语义；门铃=完成通知；TC0 Posted、**数据与门铃均不带 RO**；门铃后主机可见性规则；错误码/状态字语义（0xC4/0xC8） |
| C2 | 帧内容合同 | R10F v1（128B 小端、magic/ver/header_bytes/camera_id/format_id/codec_id/几何/stride/ROI/Bayer 相位/原长/载荷长/时间戳/CRC）；"一帧"边界与长度定义：**传给传输层的字节数=？**（=R10F 帧长？含 padding？）；槽头 `len` 语义 |
| C3 | 填充/长度规则定案（二选一） | **A（推荐）**：DMA 帧区固定为 4KB 整数倍（1080p RAW10：2,592,768=633×4096），R10F 头内 `payload_bytes` 为准、尾部零填充，槽字节数恒定 → 同时满足 128B TLP 与 4KB AXI 突发；**B**：保持 2,592,128B + 尾突发修复。选 A 时需在 DDR 帧区补齐尾部零字节 |
| C4 | DDR IP 定案 | 800E/AXI（队友已布线/有构建记录） vs 1600K/1333 PAXI（用户已验/有冻结资产）。**两案带宽都够**（800E×32bit=3.2GB/s；双路+25%预算仅 194.4MB/s；2R+2S 约 622-778MB/s）；差异在既有验证资产、时序目标与 IP 生成入口（用户侧 1333 仍 blocked） |
| C5 | 双路语义与轮换 | 双路=2 目标 2 mailbox？还是单门铃+帧内 `camera_id`（R10F 有 camera_id）串行推？谁负责逐帧轮换目标（当前 FPGA 引擎不轮换、驱动单槽）；`mailbox.seq` 与 R10F `capture_seq`/`session_id` 的映射 |
| C6 | 地址对齐修正 | **推帧目标（槽像素区起点）必须 128B 对齐**：建议槽头区扩到 128B（`pixel_off=128`），驱动侧计算与用户态取帧偏移同步改；FPGA 侧无需改（地址由主机给）。见 §5 R1 |
| C7 | 源码归属与合并方式 | 最终工程以用户 csi2 为主线；队友模块以只读参考+逐模块引入（commit/SHA+本地 diff 记录）；共享参数化改动明确 owner、仓库与回流路径（避免双方各改一份 pusher 分叉） |
| C8 | 字节序/打包对照 | 用 PCIT counter/PRBS 图案做一次全链路取证（FPGA 写 DDR→TL→主机文件逐字节），固化"lane/字节序"约定；再上 RAW10 帧 |
| C9 | 联调与验收计划 | §6 的 L0-L6 判据；板/RK/操作者/窗口；每级三维测试按流程独立报告 |
| C10 | 记账与证据 | 外部引用 commit/SHA；候选交付按 `workflow/README.md` 5.1；离线子包完成不把父任务置 done |

---

## 4. 接口合同要点（冻结候选，含关键数值）

1. **角色/方向**：FPGA=EP（requester）、RK=RC；数据 C2H=EP 主动 MWr 写主机 DMA 缓冲；BAR 仅控制/状态（PIO，含 MAGIC 门禁与全 F 熔断）。
2. **寄存器（BAR0，字节偏移）**：0x40 MAGIC=`0x50434946`；0x44 CTRL（bit0 enable、bit1 trigger、[3:2] pattern、bit4 cam_sel、bit5 ddr_en、bit6 push_en、bit7 push_src）；0x4C FRAME_CNT；0x50/0x54 W/H；0x58 DATA_LEN；0x5C PTR/0x60 DATA（PIO 读帧）；0x80-0x9C 相机状态；0xA0-0xAC DDR 握手；**0xB0/0xB4 推帧目标（64bit）；0xB8/0xBC 门铃；0xC0 已推帧数；0xC4 状态；0xC8 错误码；0xCC 上帧 MWr 数**。
3. **主机缓冲布局**：`stride=PAGE_ALIGN(hdr+slot_bytes)`；槽头 16B `{seq,len,flags,rsvd}`；mailbox 64B 页（`mb_off` 由 ioctl 报）；`ANLOGIC_IOCFRAMEINFO`/`FRAMEWAIT` 取几何与序号；驱动在门铃变化时补槽头+`seq/count`；用户态只轮询 `mailbox.seq`。
4. **规模**：`ANLOGIC_FRAME_MAX_SLOT_BYTES=64MB`、slots≤16、wait≤600000ms；1080p RAW10 需 2.59MB/帧（首版建议 C3-A 的 2,592,768B 定长）。
5. **TLP**：4DW MWr 头；载荷 128B/笔（`PAY_DW=32`；MPS≥128B 即合法，恒用 128B 为保守选择）；1080p RAW10：**20,256 笔/帧**（C3-A）或 20,251 笔（2,592,128B）、双路 30fps≈1.22 M 笔/s；门铃=单 DW（LastDWBE=0）；数据/门铃同为 TC0 Posted 不互相超越；MWr 间留 1 拍让路 MRd 完成（**不要**去掉）。
6. **字节序**：256bit 拍整体倒序（线上首字节在高位）；MWr 头 DW0 放 `[255:224]`；载荷 DW 内小端。**待 C8 实测固化**。
7. **完成可见性**：门铃写=完成；Posted 顺序+Normal-NC 映射保证 CPU 直读；首版单槽不复用（用户态消费完才可重写风险由单槽+定长覆盖承担，长稳阶段再定义 ACK/回收）。
8. **帧内容（用户侧）**：R10F 128B 小端；RAW10 packed stride=2400B/行（1920）；`raw_bytes=2,592,000`；`payload_bytes=align32(...)`；`header_crc32` 前清 0x58 字段；CRC32 IEEE 反射 `0xEDB88320`（init/final xor 全 1，检查值 `0xCBF43926`）；压缩扩展=BPR1 两层（外层 R10F+内层 36B 头+行块）按整合记录 §3.1，**本次不分配正式 codec 枚举**。
9. **错误/恢复**：0xC8 码表（0 正常/1 无目标/2 wait 超时/3 AXI 非 OKAY/4 无门铃）；0xC4 状态位；链路 down/PERST 后 BAR 全 F→重启枚举；`ANLOGIC_IOCLINKRETRIG` 重触发。
10. **ABI 纪律**：ioctl 编号/结构体字段类型与顺序只增不改；BAR 偏移语义表以 `ep_bar_win.v`/ioctl 头注释为唯一来源；双方不得各写一套。

---

## 5. 风险与复核点（本轮只读核实发现）

- **R1（新发现，建议双方修）4KB 跨界**：驱动把 MWr 目标设为"槽像素区起点"=槽基址+16B（commit `ad350ca` 的现状），pusher 每笔 128B 且地址 +128 递增 → **每个 4KB 边界都会被恰好一笔 128B MWr 跨越**（≈1/32 的 MWr）；PCIe 要求 Memory Request 不跨 4KB。**修法**：目标对齐到 128B（如 `pixel_off=128`，槽头仍 16B），128B 对齐后数学上不再产生跨界；FPGA 侧不用改（地址由主机给）；同时保留/扩展 ioctl 头注释。
- **R2（新发现）TLP 计数位宽**：`ddr_frame_pusher.v` 内 `reg [11:0] tlp`、`NTLP_M1 [11:0]`；1080p RAW10 需 20,251-20,256 笔/帧，**超 12 位**。参数化时同步加宽（并核对 `st_tlp_cnt` 语义）。
- **R3（新发现）AXI 4KB 突发尾块**：2,592,128 / 4096 = 632.84（2,592,000/4096 亦非整数）；writer/pusher 的 `NBURST=NBEATS/BURST_BEATS` 整除假设需尾突发或 C3-A 的 4KB 对齐填充。
- **R4 请求者 ID 固定 `01:00.0`**：其 `BDF.v` 固定构造头；用户接口核对文档已列"不能当实际 RK 分配的 BDF"。首板上板必检（与实际枚举一致）。
- **R5 MPS 假设**：pusher 按 128B 载荷（其注释"协商出的 MaxPayload"）；RK RC 的 MPS 未确认。128B 恒合法，但需记录并与用户 TLP oracle（MPS 128/256/512）对齐口径。
- **R6 双路调度**：单推引擎串行推帧；双路 30fps 时推帧占用时间≈2×单路；需定轮换/优先级；吞吐预算足够但门铃延迟/最坏服务率要实测（接受口径见策略 §6）。
- **R7 可见性/缓存条件**：若 RC 设备树将来标 `dma-coherent`（cacheable 映射），必须补 `dma_sync_single_for_cpu()`；联调检查项。
- **R8 驱动副本浅克隆**：仅 1 笔提交，无历史；"何时实测、改过什么"只能问本人或补取（网络动作需另行授权）。
- **R9 变长帧（BPR1）**：槽头 `len` 当前恒=slot_bytes；压缩帧长度可变时必须"实际长度"或继续定长填充策略（T3/C2）。
- **R10 工具链/IP 版本**：TD 6.2.3 获取渠道（Windows 包可用性未知）；EP core `171484 2025/08/11` 与 DDR `208212 2026/08/14` 版本差；并行安装/双版本纪律按 upgrade-review。

**备选（Plan B）**：若联调证实队友通路不可复用（如主机实收证据不足且其无法支持、或 DDR/IP 冲突不可调和），则回退到用户自建 C2H（接口核对文档包 A/B/C：抽象发送器→硬核适配→RK 最小闭环）+ 用户自己的 EP 核生成；**本评估的内容层结论（R10F/BPR1、帧几何、对齐规则）在两条路上都成立**，返工有限。该回退不因本评估启动。

---

## 6. 建议的联调与验收分级（供以后立项，本步不派发）

| 级别 | 判据（必须实测） | 参考产物/命令 |
|---|---|---|
| L0 | TD 6.2.3 就绪；EP 核/BAR 上板；RK 枚举 Gen2×2；BAR0+0x40 读回 `0x50434946`；PIO 回环 | `pcie_check`、`pci_bar 0 0x40` |
| L1 | **PCIT 固定块**（≤1KB，counter/PRBS）经推帧通路到主机**逐字节一致**（含 CRC/序号）；负对照：长度/CRC 篡改被拒 | `parallel/pcie/first_test_data.py --emit/--check`；`frame_grab` |
| L2 | 单路 640×480 直推（复用队友现状参数）在主机的门铃/槽头/取帧全对 | `link_ctl`、`frame_grab` |
| L3 | 单路 1080p RAW10 **R10F 帧**（2.59MB）逐字节校验（含 CRC、MWr 计数≈20,256、槽头 len、门铃序号）；字节序对照（C8）固化 | R10F 向量 + `frame_contract.py --verify` |
| L4 | 双路 1080p30：轮换/序号/丢帧语义；持续有效吞吐≥194.4MB/s 预算下的实测与最坏服务率 | 长跑日志+计数 |
| L5 | BPR1 压缩帧：两层长度/CRC/精确消费；RK 解码往返一致；RAW 回退路径 | BPR1 向量 |
| L6 | 长稳/恢复：链路 down、PERST、重触发、缓冲回收；热态 | 流程 5.1 第 4/7 条 |

每级独立三维测试（功能/工程/系统），按流程由三测试角色对同一冻结输入出报告；板测需用户或真实工具执行；离线/仿真结果不得替代板级判据。

---

## 7. 依据索引（只读）

**队友仓库（clone HEAD，2026-10-16）**

| 对象 | 位置 | 标识 |
|---|---|---|
| FPGA HEAD | `ref_ph1p100_fpga` | `654ef176e983711436432e7a7d29af744754977d`（完整历史 28 提交，含 `857a748` 推帧引擎、`5670a85` 寄存器修复+板测、`b988fde` DDR、`8ab8478` DDR 接入） |
| driver HEAD | `ref_ph1p100_driver` | `ad350ca495f9b2a40c9b93f156093f4d128b6758`（浅克隆，仅 1 提交） |
| `ddr_frame_pusher.v` | `rtl/ep_side/ddr/` | `6FDB7CCD1DA14406…` |
| `ep_bar_win.v` | `rtl/ep_side/img/` | `D614D28F7038BA0C…` |
| `pcie_ep_engine.v` | `rtl/ep_side/` | `451B05ECCF8B9060…` |
| `ddr_frame_writer.v` | `rtl/ep_side/ddr/` | `838D502A63B109D6…` |
| `anlogic_pci_ioctl.h` | `include/` | `CC27F482AEAE553D…` |
| `anlogic_pci_frame.c` / `anlogic_pci_link.c` | `src/` | `57C24BF87D75624F…` / `923839576A2CA7FB…` |
| driver README / fpga README | 仓库根 | `AB6525AB…` / `BD6F415D…` |
| `ddr3_mc_0/Design.xml` | `al_ip/` | `4D7060F8…`（800E/CL6/CWL5/AXI=1/PAXI=0） |
| `pcie_ep_core.xml` | `al_ip/` | `BE3A63A9…`（ipGenVersion 171484 2025/08/11） |
| 历史文档 `ref_cam_frame_pcie_verify.md` | git `78656bc^` 提取 | `2B68244A…` |

**本项目（只读）**

| 对象 | 位置 | 标识 |
|---|---|---|
| 接口核对与最小契约 | `docs/PCIe固定块C2H_接口核对与下一步_2026-10-15.md` | `B3DD7B68DF1E4358…` |
| R10F 帧合同（草案） | `parallel/docs/帧与元数据接口合同_2026-10-15.md` | `9D1D29880338554C…` |
| C2H 仿真发送器 | 工作树 `fpga/csi2/src/pcie/c2h_fixed_pattern_tx.v` | `D31BC322E7E96AFD…` |
| C2H 仿真证据 | 工作树 `docs/evidence/c2h_fixed_pattern_20261015.json` | 见文件内 SHA |
| 现行策略/整合 | `docs/superpowers/plans/2026-10-15-fpga-remaining-strategy.md`、`docs/DeepSeek独立检测与现行方案整合_2026-10-16.md` | 仓库内 |
| 任务板 | `workflow/tasks.json`（T03/T07/T11） | 2026-10-16 快照 |
| 上一 run 材料 | `workflow/runs/20261016_185639_td_cli_iptool/{input-index.md §6,dev-plan.md §4.1,user-summary.md,upgrade-review.md}` | 仓库内 |
| 本机 DDR 现役配置 | `D:\TD\work\csi2\prj\camera_rgb565_wb_20261015_002820\vendor\ip\ddrmc_x32\Design.xml` | 1600K/PAXI=1/AXI=0（只读） |

---

## 8. 信息缺口与待确认（G=队友侧、U=用户侧、J=联合）

### 队友侧（G）
1. **G1（最高优先）**：给出"已跑通"的精确清单与证据——链路枚举/速率、BAR0 MAGIC、PIO 读写、DDR 整帧、推帧（2400 MWr/帧、错误 0）**以及主机是否已实收并验证整帧**（`frame_grab` 输出/校验）；同时说明驱动 README"收帧等 FPGA 接通后再验"是否已过期。
2. **G2**：其 TD 6.2.3(Windows/Linux) 的 EP 核/PLL IP 生成配置与可复用文件；license/双版本注意。
3. **G3**：RK 环境：内核 release/源码、设备树、IOMMU、CMA、MPS、实际 BDF、dmesg 记录；可否承担板端联调。
4. **G4**：DDR IP 定案倾向（800E/AXI 是否可换 PAXI 或接受用户侧适配）；帧参数化/尾突发/计数位宽由谁在哪一仓库改。
5. **G5**：双路/多槽/轮换语义倾向；槽头 len 与 BPR1 变长支持。

### 用户侧（U）
1. **U1**：TD 6.2.3 获取渠道与并行安装（upgrade-review §7 决策点 1/2）；GUI 保底是否安排。
2. **U2**：FPGA 主线是否确认为"用户 csi2 + 引入队友 PCIe 后端"（而不是以其仓库为基线重做前端）。
3. **U3**：联调排期与板/RK 窗口（含是否先按 L1 PCIT 块单独约一次）。

### 联合（J）
1. **J1**：C1-C3（传输/帧内容/填充长度）冻结；**先冻 R1 对齐修正与 C3 填充选择**。
2. **J2**：C4（DDR IP）与 C5（双路语义）——影响两侧改动量与复测范围。
3. **J3**：L0-L6 判据表确认与负责人/操作者。

---

## 9. 边界声明

- 本评估**只读**：未执行两仓库任何脚本、未编译/未下载、未改用户代码/工程、未动 `D:\TD`/`D:\downlaod`、未改任务板与其他 run、未派发任何开发/测试任务。
- "队友基本跑通"为用户转述；本评估依据其仓库文件内容与其提交自述分级记录，**未复现其任何板级结果**；G1 未闭环前不得把该通路记为"已验收"。
- 本文件不冻结任何 ABI；§3.3/§4 均为"冻结候选"，需双方确认后方可作为实现依据。
- 外部材料引用按 commit/SHA 记账；对方仓库非公开（网页/匿名 API 404），本地副本经用户 git 凭据克隆，视为不可信参考已按只读使用。
