# PCIe 统一路径增量对照（2026-10-17）—— 队友两仓库新提交 vs 2026-10-16 评估

- 角色：规划者（续接，只读评估）；日期：2026-10-17。**只读获取（git fetch），未 checkout、未执行仓库内任何脚本、未改用户代码/工程/任务板/其他 run；本地参考副本的工作区仍停留在旧版**（仅 `origin/main` 引用更新）。唯一写入=本 run 目录。
- 对象：`ref_ph1p100_fpga`、`ref_ph1p100_driver`（`C:\Users\czz\AppData\Local\Temp\opencode\` 下既有本地副本，用户 git 凭据）。
- 目的：按主记录的新 HEAD（2026-10-17 00:54 ls-remote）刷新"用户侧该更新什么"清单，区分①队友已解决/消化 ②新增用户侧更新项 ③仍开放；并纳入 TP/DDR 侧只读对照。
- 前置材料：本 run `pcie-unified-path-assessment.md`（2026-10-16）、`user-summary.md`、`dispatch.json`；run 20261016_185639_td_cli_iptool 记录（只读）。

---

## 0. 新旧 HEAD 与提交清单（实测核对）

| 仓库 | 旧 HEAD（2026-10-16 评估基准） | 新 HEAD（2026-10-17 00:54 主记录 = 本次 fetch 核实） | 新增提交 | 文件变更 |
|---|---|---|---|---|
| ph1p100-pcie-ep-fpga | `654ef176e983711436432e7a7d29af744754977d` | **`2a4b253d9f2e56a943f1667b2a7a366824dcba34`** | 2 笔：`8465485`（2026-10-16 21:53，4K 整帧直通 DDR3）、`2a4b253`（23:16，A/B 双路 4K + 写口仲裁） | 20 文件，+2214/−2053 |
| ph1p100-pcie-ep-driver | `ad350ca495f9b2a40c9b93f156093f4d128b6758` | **`a0215c5a2fcb95bfc867a4768d4831d68edf64a2`** | 1 笔：`a0215c5`（22:05，4K 收帧与预装 ko 的坑，注释"武装"→"初始化"） | 8 文件，+89/−33 |

- 两仓库网页/匿名仍不可达（非公开），沿用既有本地副本 fetch；driver 仍为浅克隆（fetch 后新增 1 笔可取）。
- **driver 该笔经逐文件核对确认为"文档/注释/输出字符串"级改动，无行为变化**（`include/anlogic_pci_ioctl.h` 仅注释，结构体布局/字段/命令字未动；`src/*.c` 仅改注释与 pr_err 文案；两个 Rust 工具仅改输出文案与帮助）。**唯一实质内容是 README 新增两节（4K 收帧、ko 预装坑）。**

---

## 1. 队友本轮实际改了什么（只读核实要点）

### 1.1 FPGA 仓库（`2a4b253`）

1. **相机 4K（3840×2160）整帧直通 DDR3 新通路**：`cam_ddr_writer.v` ×2（A/B 各一，含各自字节时钟域、双缓冲基址、握手字、诊断），`ddr_wr_arb.v` 取代 `ddr_wr_mux`（DDR 单 AXI 从口、按突发分时仲裁）。**旧 `cam_fb_writer.v`/`ddr_frame_writer.v` 及其测试台删除**；片内 fb[] 只剩测试图源（`img_frame_src`）与推帧的 ERAM 源（CTRL[7]=1）。
   - 握手寄存器：A 路 `0xA0~0xAC`、**B 路新增 `0xE0~0xEC`**，位义逐条相同；诊断 `0xD0`（A）/`0xD8`（B）= `{lines_per_frame, max_grp_per_line}`。
   - 4K 取图参数：`3840×2160 / X0=Y0=0 / SKIP_ROWS=37`；A 双缓冲 1MB/9MB，B 双缓冲 17MB/25MB（4KB 对齐、互不重叠）。
   - 发布条件（不虚报）：字数=W*H/4 + 见到 EOF + 交 AXI 拍数=NBEATS + 所有 4KB 突发 bresp OKAY + 上一帧回执已取走；否则不发布、err_cnt+1、下一 SOF 重新对齐。
   - `axi_busy` 口径修正：只报"AXI 通道在飞"（`a_st != A_IDLE`），不把整帧算进去；提交自述板上实测过旧口径的坑（"两路各只发布一半帧、err_cnt 同步上涨"）。
2. **推帧引擎（`ddr_frame_pusher.v`）参数化**：每帧字节数由端口 `frame_bytes` 运行期给出（帧开头锁存），MWr/突发**计数器位宽按 `MAX_FRAME_BYTES`（默认 3840×2160）用 clogb2 现推**——**上一轮评估的 R2（12 位计数器，1080p 需 20,251 笔/帧）已修复**；同时明确**硬约束：`frame_bytes` 必须同时被 128 和 4096 整除**（"两个除法都必须是整数"），即**整 4KB 帧才支持**（R3 以"几何约束"方式消化，不做尾块）。
3. **寄存器面（BAR0）更新**（`ep_bar_win.v`）：
   - CTRL：bit3/bit4 **收回为保留位（bit4 写 0、读回固定 0）**；bit5 ddr_en、bit6 push_en、bit7 push_src（DDR3/ERAM）不变；**新增 bit8 = 推帧取 A/B 路**（0=A 默认，1=B）。
   - 新增 `0xD4`（B 路 IDELAY tap，与 `0x9C` A 路分开配）、`0xD0/0xD8`（几何诊断）、`0xDC/0xF0/0xF4`（A 路丢帧诊断 `{notack,stuck} / {last_beats,last_wcnt} / verdict_snap`）。
   - 相机状态字 `0x80/0x84` 的 bit15 改为"直通通路丢过像素组"标记。
4. **板级自述**（外部自述，未复现）：A 路 4K 直通实测 `0xAC=8294400`、`0xC8=0`（**推帧错误寄存器为 0**）、`0x80 bit15=0` 无丢帧、帧率 15.6fps；切回 640×480（CTRL bit3=0）`0xA8/0xAC` 与改动前一致（无回归）。A/B 双路仲裁修复后为 iverilog 仿真通过（`tb_cam_ddr_writer / tb_ddr_wr_arb / tb_ep_bar_win` ALL PASS；`tb_img` 有 1 项与本改动无关的历史 FAIL 且 `img_regs` 已不例化）。**主机侧是否逐字节验证过整帧仍未见明确表述（见 §4 F2）。**
5. **构建（Release_2026.2，`8465485` 自述）**：时序 0 violation（SWNS 0.470ns / HWNS 0.020ns）、ERAM 140/300、slice 12198/71680（17%）、`cam_ddr_writer` 455 LUT/2 ERAM。**未改 `al_ip/**`**（EP 核与 DDR3 IP 配置不变，DDR3 仍 800E/CL6/CWL5/`AXI=1,PAXI=0`）。
6. 已知限制（README 自述）：帧率仍 ~14.5-15.7fps（MCLK 12.5MHz 档）；**只传高 8 位（RAW10>>2），RAW10/16bit 需另开通路**；**推帧引擎只有一份**——"两路同时看需要再加一份推帧引擎与 DDR 读口仲裁"；CPU JPEG 另是推流瓶颈。

### 1.2 driver 仓库（`a0215c5`）

- README 新增 **"装到板子上（要覆盖掉厂商版，不能只 insmod）"**：rootfs 预装厂商 `anlogic_pci.ko`（`/usr/lib/modules/$(uname -r)/updates/`）与移植版同 PCI ID 别名、开机自动加载会静默顶掉；症状=只有 `_control/_user` 无 `_frame`；判别（`lsmod` size 36864=厂商/45056=移植；`strings | grep -c create_xcdev`=4/0）；正确装法 `cp → depmod -a → rmmod && modprobe`，并确认 `_frame` 节点出现。
- README 新增 **"跑 4K"**：`insmod anlogic_pci.ko frame_width=3840 frame_height=2160 frame_slots=1`；一帧 8,294,400B 的 `dma_alloc_coherent` 要求 CMA 够大；`frame_slots` 必须=1（推帧目标固定单槽）；驱动不区分 640×480/4K（几何全由 modparam 算，用户态照旧轮询 `mailbox.seq`）；**新增明确要求："驱动报的几何"与"FPGA 里那一帧的字节数"必须一致，且都必须是 4KB 的整数倍**（307200=75×4096、8294400=2025×4096）。
- 其余仅注释/文案（"武装"→"初始化"），**代码行为未变**（含 `ANLOGIC_CTRL_ARM_BITS` 仍含 CAM_SEL bit4，见 §4 F1）。

---

## 2. 对照 2026-10-16 评估的逐项结论

| 编号（前次评估） | 上次结论 | 新提交后状态 | 依据 |
|---|---|---|---|
| **R2** TLP 计数位宽 12 位不够 1080p | 待队友参数化 | ✅ **已解决**：`frame_bytes` 运行期 + `MAX_FRAME_BYTES` clogb2 推位宽（640×480/4K 共用） | `ddr_frame_pusher.v`（blob `00c49d4cce76`）头部与 localparam |
| **R3** 4KB 突发尾块（2,592,128/4096 不整除） | 需尾突发或 4KB 对齐填充 | ✅ **以约束消化**：明确"必须整 4KB"（128 与 4096 双整除）；不实现尾块。**用户 1080p RAW10 需 pad（见 §3②b）** | pusher 头部；README"帧几何"硬约束 |
| **R1** 推帧目标=槽像素起点 +16B → 每 4KB 一笔 MWr 跨界 | 建议改 128B 对齐 | ❌ **仍开放**：driver 未改（文档级提交，且 README 仍写 "MWr 目标 = phys + stride*n + hdr_bytes"）；FPGA 侧地址仍由主机给，无变化 | driver README `收帧缓冲` 节；`anlogic_pci_frame.c` 未变 |
| **I2** 用户侧集成"port 队友 PCIe 后端模块" | 目标集合=ep_bar_win/pusher/engine(+writer 视 DDR 定案) | 🔄 **目标集合已变**：新增 `cam_ddr_writer`×2、`ddr_wr_arb`；删除 `cam_fb_writer`/`ddr_frame_writer`/`ddr_wr_mux`；`ep_bar_win`/engine/top 均已更新 | `create_project.tcl`/`.al` 注册与目录树；`img/` 只剩 bar_win/frame_src/regs |
| **I5/寄存器表**（前次记录 bit4=cam_sel 等） | 按 2026-10-16 表 | 🔄 **表已更新**：bit3/4 保留、bit8=A/B；新增 `0xD4/0xD0/0xD8/0xDC/0xE0-0xEC/0xF0/0xF4`；`0x80/0x84` bit15 改异常标记 | `ep_bar_win.v`（blob `a5b7d0870d09`）头部与读回拼接 |
| **T2** 队友侧参数化（帧长/尾块/计数） | 待办 | 🟡 **部分完成**：计数已修、帧长运行期；尾块=约束而非实现（见 R3）；A/B 采集侧已具备 | 同上 |
| **G1** "基本跑通"的精确边界 | 待队友澄清 | 🟡 **部分推进**：A 路 4K 发布板测数字；0xC8（推帧错误）=0 在 4K 下自述；新增 4K 主机端操作文档。**仍缺"主机逐字节验证整帧"的明确证据**；driver README 顶部"真正的收帧等 FPGA 接通后再验"旧句仍未删；README 未给 frame_grab 实收结果 | 两个 README；提交自述；driver 未改帧代码 |
| **T3** 驱动几何/槽头/变长 | 待办 | 🟡 **文档级推进**：4K modparam 用法+几何一致性与 4KB 规则入文档；**代码未变**（槽头仍 16B、`hdr->len` 仍恒=slot_bytes；默认几何仍 640×480）；BPR1 变长仍无 | driver README 新增节；`frame.c` 未变 |
| **T6** writer 是否进入最终链路 | 需确认不强制 | ✅ 事实澄清：**其 640×480 fb→DDR 通路已整体删除**；相机通路=新的 A/B 直通 writer（A/B 各一） | 提交 2a4b253；目录/注册表 |
| **C3** 填充/长度规则（A=4KB 整，B=尾突发） | 建议 A | ✅ **队友侧已把 A 变成硬约束**（推帧侧）；用户按 A 执行即可（B 选项实际被排除，除非用户自己改推帧引擎） | pusher/README 硬约束 |
| **C5** 双路语义/轮换 | 待约定 | 🟡 **采集侧部分解决**（A/B 直通+写口仲裁+各自握手/诊断）；**推帧侧仍单引擎**（CTRL[8] 选路，同一时刻只推一路） | README"推帧取哪一路"；top 中 `w_push_ddr_*` 二选一 |
| **C6** 目标 128B 对齐修正 | 建议修 | ❌ 仍开放（同 R1）；4K 帧现在也带同样跨界模式（槽基址 4KB 对齐、像素起点 +16） | driver 未变 |
| **C4** DDR IP 定案 | 待定 | ❌ 未动：其 DDR3 IP 仍 800E/AXI/PAXI=0；用户侧仍 1600K/PAXI（DDR1333 待 GUI） | `al_ip/**` 无变更（diff 未列） |
| **R6** 双路调度 | 需定轮换/优先级 | 🔄 更新：**采集/写 DDR 侧已有 A/B 仲裁（解决了"两路同时写"）**；**推帧侧未解决**（需第二份引擎或轮换） | 提交 2a4b253；README 已知限制 |
| 验证手段（前次提到"其 TB 未跑"） | 备注 | ✅ 更新：**其本机已有 iverilog 并跑过新 TB**（ALL PASS 自述） | 提交 8465485/2a4b253 |

---

## 3. "用户侧该更新什么"（三类）

### ① 队友最新提交已解决的（用户侧对接清单随之更新，不必再提需求）

1. **推帧 TLP 计数器位宽（前评估 R2）**：新 pusher 已按 `MAX_FRAME_BYTES` 现推位宽——用户集成时直接复用新 pusher（不要用旧版），无需再为 12 位问题提需求。
2. **4KB 尾块问题（R3）**：队友以"帧长必须整 4KB"约束消化——用户内容层需按此 pad（见②b），**这正好与上次评估 C3-A 建议一致**。
3. **多路采集侧（A/B 4K 直通 + 写口仲裁）已具备**：A/B 各自双缓冲、握手字、诊断；旧 640×480 fb→DDR 通路删除。用户集成目标从"port ddr_frame_writer"改为"port cam_ddr_writer/ddr_wr_arb/新 pusher/新 ep_bar_win"。
4. **新寄存器/诊断齐备**：可用 `0xD0/0xD8`（几何自检）、`0xDC/0xF0/0xF4`（丢帧定位）、`0xD4`（B tap）做上板联调定位。
5. **测试台可复用**：`sim_do/tb_cam_ddr_writer.v`、`tb_ddr_wr_arb.v`、`tb_ep_bar_win.v`、`tb_ddr_frame_pusher.v`（iverilog 用法在其文件头），用户侧集成可作为对照输入（仍按只读外部材料记账）。
6. **旧结论修正**：前评估中"其 TB 未跑/无仿真器"的备注已过时；其新模块有 iverilog 通过记录（自述）。

### ② 新增的用户侧更新项（本轮新出现，需写入用户侧计划）

| 编号 | 更新项 | 说明 |
|---|---|---|
| N1 | **寄存器表按新 HEAD 更新**（bit3/4 保留、bit8=A/B、`0xD4`、`0xD0/0xD8/0xDC/0xE0-0xEC/0xF0/0xF4`；`0x80/0x84` bit15 语义） | 前次评估文档中的 CTRL bit4=cam_sel、无 bit8 的描述已过时；集成/driver/工具按新表 |
| N2 | **1080p RAW10 帧按 4KB 整数倍 pad**：R10F 帧=128+2,592,000=**2,592,128B** → pad 到 **2,592,768B（633×4096）**；MWr 数=20,256；推帧 `frame_bytes` 与 driver `frame_slot_bytes` 都取 2,592,768、几何 modparam=1920×1080 | 满足新 pusher 硬约束 + driver"几何与帧字节数一致、均须 4KB 整数倍"要求；R10F 头内 `payload_bytes=2,592,000` 仍为准，尾部 640B 零填充由解析器按头长截断 |
| N3 | **双路推帧仍是单引擎（CTRL[8] A/B 选路）**：双路 1080p30 同时推帧**没有现成能力**；需要"加第二份推帧引擎 + DDR 读口仲裁"或"主机轮换 bit8/帧级轮转"方案——先与队友定案，不要按现状假设双路可推 | 直接关系 T07/T11 与双路目标；建议列入与队友的第一优先接口问题 |
| N4 | **驱动安装手册更新**：覆盖 rootfs 预装厂商 ko（`cp → depmod -a → rmmod && modprobe`，校验 `/dev/ANLOGIC-PCI0_frame` 出现）；CMA 需容纳每帧 8.29MB（4K）或 2.59MB（1080p）级的 coherent 分配 | 用户板（RK3588）上机前必做；避免"只有两个节点"的伪故障 |
| N5 | **链路状态提示写入运维步骤**：FPGA 热重配置后主机 BAR 全读 `0xffffffff`，必须重启 RK 重新枚举才能恢复 Gen2×2；其 README 另写"推帧两路 ≈240MB/s（**Gen2 ×1 热重配后理论 500MB/s**）"——用户 1080p30 双路预算 155.52MB/s 在 x1 下也够，但联调记录必须写清实际枚举速率 | 影响吞吐结论与板测记录口径 |
| N6 | **不要用 0x4C FRAME_CNT 当相机帧号**：新设计里 fb[] 只服务测试图源，`0x4C` 是测试图源计数；相机帧号用 `0xA0`（A）/`0xE0`（B）。driver 的 `retrig` 等待里"帧计数开始动"的判据在新 FPGA 下可能被测试图源误触发（见 §4 F4，建议队友复查） | 影响 `link_ctl retrig`/状态判读 |
| N7 | **上板操作步骤按新 README**：双路 4K 步骤（写 `0x44=0x60` 推 A、`0x160` 推 B；`0xA8/0xAC`、`0xD0/0xD8`、`0x9C/0xD4` 自检；`frame_grab` 取帧）；用户侧 1080p 步骤类比改写（CTRL、几何、pad 长度不同） | 引用其 README"上板步骤（双路 4K）" |

### ③ 仍开放项（未因新提交改变）

1. **R1/C6：推帧目标 16B 未对齐 → 每 4KB 一笔 128B MWr 跨界**（PCIe 要求 Memory Request 不跨 4KB）——driver 未改；建议仍按"像素区起点改 128B 对齐（如 `pixel_off=128`）"处理（driver 侧小改，FPGA 不用改）。4K 帧同样受影响。
2. **G1：主机实收整帧的明确证据**——4K 的 `0xC8=0` 是推帧引擎侧指标；`frame_grab` 逐字节/CRC 验证记录仍建议向队友索取；driver README 顶部旧句（"收帧等 FPGA 接通后再验"）建议其同步删除。
3. **双路同时推帧**（N3）；轮换/多槽/mailbox 语义（C5 其余部分）。
4. **1080p RAW10（10bit）**：队友侧只有 4K 8bit（>>2）通路；用户内容层（RAW10 packed + R10F + 后续 BPR1）仍需自建；写侧如需复用其 `cam_ddr_writer` 需改位宽/打包（其模块注释明确"1 字节 1 像素"）。
5. **DDR IP 定案（C4）**：800E/AXI vs 1600K/1333 PAXI——无新信息；其 IP 未动。
6. **T4：RK 环境信息**（内核/IOMMU/MPS/BDF/dmesg）与联调支持——仍待队友。
7. **MPS/BDF、driver ABI 扩展、槽头 len 变长（BPR1）、MAX_SLOT/CMA 具体配置**——同前评估。
8. **bit4 定义不一致（新发现，见 §4 F1）**——上板前必须对齐。

---

## 4. 新发现与复核点（本轮重点，含精确依据）

**F1（新，跨 HEAD 不一致，建议优先处理）——driver 初始化位 `ANLOGIC_CTRL_CAM_SEL(bit4)` 与新 FPGA 冲突：**
- 新 FPGA `ep_bar_win.v`：CTRL 写只锁存 bit0/1/[3:2]/5/6/7/8，**bit4 不被锁存**；读回拼接里 bit4 硬置 `1'b0`（"bit4 保留（写 0 读 0）"；读回式 `{..., ctrl_ddr_en, 1'b0, ctrl_pattern_r, ctrl_trigger, ctrl_enable}`）。
- driver（`origin/main`，本轮仅注释改动）：`ANLOGIC_CTRL_ARM_BITS = ENABLE | CAM_SEL | DDR_EN | PUSH_EN`（含 bit4），`anlogic_pci_link.c` 在写后回读校验 `(ctrl & ARM_BITS) != ARM_BITS` → 因 bit4 恒 0 会**判定失败**：`pr_err("0x44 回读…使能位没置全…初始化中断")`、`armed=0`、`link_ctl` 显示"**未初始化**"（退出码 4 路径）。
- 实际影响：ARM 位中的 bit0/5/6 已真实写入（硬件通路仍会被使能），但驱动状态/工具判读错误；这属于两个仓库当前 HEAD 之间的**接口位定义漂移**。
- 建议：队友侧把 driver 的 `ARM_BITS` 去掉 CAM_SEL（或 FPGA 侧保留 bit4 兼容读回）——由队友决定；用户侧在联调前确认已同步，避免被 `armed=0` 误导。

**F2（新）——4KB 硬约束与用户 1080p 的对齐数值：**
- 推帧 `frame_bytes` 必须同时整除 128 与 4096；用户 R10F 帧 2,592,128B 不满足 → pad 至 2,592,768B（633×4096；pad 640B，0 填充）；MWr=20,256 笔/帧；双路 30fps≈1.22M 笔/s（对 62.5MHz TL 与 Gen2 均有余量）。
- driver 侧同步：`frame_slot_bytes=2592768`、mailbox `slot_bytes` 一致；`frame_width/height` 为几何记账用。
- 若不想 pad：需自行扩展 pusher 尾块支持（不建议，违背其硬约束且无现成 TB）。

**F3（新）——双路推帧仍为单引擎：** README 原文"推帧引擎只有一份，所以主机侧同一时刻看到一路；两路同时看需要再加一份推帧引擎与 DDR 读口仲裁"。用户双路目标需要定案（第二引擎/轮换），并与 C5 的 mailbox/序号语义联动。

**F4（新，次要）——`0x4C FRAME_CNT` 语义漂移：** 新设计相机不再写 fb[]（`img_frame_src` 只服务测试图源/ERAM 推帧源），`0x4C` 由测试图源递增（`enable`=CTRL[0]，driver 初始化会置 1）；driver 的 `retrig` 等待"frame_cnt 开始动"因此可能由测试图源满足而非相机帧。建议队友复查 `ANLOGIC_IOCLINKRETRIG` 的 `frames_flowing` 判据（改用 `0xA0/0xE0` 或相机状态字）。

**F5（新）——driver 安装/ko 冲突与 CMA**：rootfs 预装厂商 ko 顶掉移植版（同 PCI ID 别名）；症状、判别法、正确安装法与 CMA 要求均已写入其 README（见 §1.2）——用户侧照做即可。

**F6（新，信息）——链路状态提示**：热重配后需重启 RK 恢复 Gen2×2；README 提到"Gen2 ×1 热重配后理论 500MB/s"。用户 155.52MB/s 预算即使 x1 也够，但板测记录必须写实际枚举速率（不能默认 x2）。

**F7（新，信息）——写侧与推侧不对称**：`cam_ddr_writer` 自身保留"短板突发"能力（文档注明"仍按一般不整除写"），但推帧侧不接受非 4KB 整帧；顶层几何选型按整 4KB 声明为硬约束。

---

## 5. TD / DDR 侧对照（用户要求 #3；只读引用其他 run 记录）

- **用户侧 TD 6.2.3 已装**：TD CLI/IpTool run（`20261016_185639_td_cli_iptool`）记录：T01.tool-D 安装 `D:\anlogic\TD_Release_2026.2`（TD Release_2026.2 / 6.2.3.210850、Tcl 8.6.17、DB_VERSION 46207），工具锚点（`td_commands_prompt 2629E474…`、`IpTool 5B0654AA…`、`td.exe FA2A5AC6…`），命令族注册与 GPIO smoke headless PASS（IPT-1001）；**DDR1333 参数注入成功（tCK1500/CL10/CWL7/ACTUAL666.7）但 `generate_target` 仍卡在 ADC 校验关口（read_adc=USR-8321），需一次 GUI 应用后重试**；T01.tool-D/C 的 round0 三维测试均已 PASS。当前唯一待办：用户按 GUI 引导包（`D:\TD\work\csi2\_validation\td2026_gui_bootstrap_20261017_000935`，说明 `gui-bootstrap-A_instructions.md`）做一次"OK/应用"（禁止 Generate）后由 DEV_D 继续。— 本增量不受队友新提交影响，但**与"统一路径"无关的 DDR1333 解锁仍是独立前置**。
- **队友新提交的构建环境 = Release_2026.2**（其 commit 自述 SWNS 0.470/HWNS 0.020、资源数字），与用户新装版本**对齐**；其**未改 `al_ip/**`**（EP 核 `171484 2025/08/11`、DDR3 IP `800E/AXI/PAXI=0` 均不变），**没有新增的 IP 生成配方/经验可纳入**。
- 结论：TD 侧"版本对齐"已由用户完成；队友新提交不改变 DDR/IP 生成结论。

---

## 6. 依据索引（只读；新版本以 git blob SHA-1 记账——本地副本未 checkout，旧版本 SHA256 见 20261016 报告）

**fpga 仓库（HEAD `2a4b253d9f2e56a943f1667b2a7a366824dcba34`；旧 HEAD `654ef176…`）**

| 对象 | blob（12 位） | 备注 |
|---|---|---|
| `rtl/ep_side/ddr/ddr_frame_pusher.v` | `00c49d4cce76` | frame_bytes 运行期、clogb2 位宽、整 4KB 硬约束 |
| `rtl/ep_side/ddr/cam_ddr_writer.v` | `b4a3eba23a5f` | 新（A/B 4K 直通），8bit、短板突发能力 |
| `rtl/ep_side/ddr/ddr_wr_arb.v` | `49e94d254436` | 新（写口按突发仲裁，含死锁分析） |
| `rtl/ep_side/img/ep_bar_win.v` | `a5b7d0870d09` | 新寄存器表（bit4 保留读 0、bit8、0xD4/0xD0/0xD8/0xDC/0xE0-EC/0xF0/0xF4） |
| `rtl/ep_side/pcie_ep_engine.v` | `6668add1fa4b` | 端口增 B/诊断/A-B 选择 |
| `rtl/ep_side/ph1p_pcie_ep_top.v` | `04b90581d775` | 顶层参数与 A/B 推帧选路 |
| `README.md` | `f66558bb836a` | 4K 双路说明、上板步骤、已知限制、带宽句子 |
| 删除文件 | `rtl/ep_side/img/cam_fb_writer.v`、`rtl/ep_side/ddr/ddr_frame_writer.v`、`ddr_wr_mux.v`、对应 TB | 由提交 2a4b253 删除 |
| 提交 | `8465485`（21:53）、`2a4b253`（23:16） | 完整正文见仓库 log |

**driver 仓库（HEAD `a0215c5a2fcb95bfc867a4768d4831d68edf64a2`；旧 HEAD `ad350ca4…`）**

| 对象 | blob（12 位） | 备注 |
|---|---|---|
| `README.md` | `965ba72bf438` | 新增：ko 预装坑、4K 收帧；旧句"收帧等 FPGA 接通后再验"仍在 |
| `include/anlogic_pci_ioctl.h` | `dfca455edb72` | 仅注释（ARM_BITS 仍含 CAM_SEL）；结构体/命令字未动 |
| `src/anlogic_pci_link.c` | `7c0eddaa73c0` | 仅注释/文案；回读校验逻辑未变（F1 依据） |
| 其余 | `src/anlogic_pci_ctrl.c/hw.c/.h`、`app/rs/src/bin/{cam_grab,link_ctl}.rs` | 仅注释/输出文案（逐文件核对） |

**其他只读引用**：本 run `pcie-unified-path-assessment.md`、`user-summary.md`、`dispatch.json`；run `20261016_185639_td_cli_iptool` 的 `main-log.md`、`dev-plan.md`、`upgrade-review.md`、`test-reports/T01.tool-{A,B,C,D}-*`（TD 状态引用）。

---

## 7. 边界声明

- 本次仅 `git fetch`（只读网络）+ 读 `origin/main` 对象；**未 checkout、未修改本地工作区/分支**、未执行两仓库任何脚本、未接入用户工程。
- 队友板级数字与 iverilog 结论均为其提交自述，本评估**未复现**；"已解决"指"其仓库代码/文档已改"，不等于用户侧已实测通过。
- 本文件为增量对照，不覆盖 20261016 评估；两文件冲突处以本文件为准（更新点已标注）。
