# FPGA 设计指南 — 板级集成（T11.BRD.*）

冻结时间：2026-10-27 07:26 后（本 run 首次规划）。适用：本 run 全部 4 包。实现者不得自行改动本指南的冻结项；确需变更由原规划在本 run 内出具补充并登记理由。

## 0. 证明边界（先读）

- 本 run 只证明：**同一板级候选**在真实顶层/真实时钟/真实引脚约束下能构建、能出 bit、能在板上完成**单路单帧压缩帧经真实 PCIe 完整导出并被独立解码校验**（先 B 后 A）。
- 不证明：1080p30 实测、长稳、持续吞吐、双路并发、RK 驱动联调完成、HE 停顿敏感性修复、P4 在 187.5MHz 收敛。
- **承接事实**：P4 ⚠（r2 功能 pass / G2 fail 112 端点 WNS −0.637ns；r3 G2 pass 但派生变体等价 fail）。r2 与 r3 不得拼接；r3 派生文件不得进入任何编译列表。
- 仿真/文件回放 ≠ 真实 PCIe 传输；b18/b20 位流 ≠ 本交付位流；未下载的 bit 不得称为板上通过。

## 1. 板卡与器件（固定）

| 项 | 值 |
|---|---|
| 板卡 | MLK-F9P-CA05-PH1P100（米联客 F9P） |
| 器件 | `PH1P100SBG484`，speed `-3`，`PH1` family |
| 相机 | 2× IMX415（FEP-VID006-MIPI 子卡，4 lane，1.5Gbps/lane，RAW10） |
| DDR | DDR3，IP `ddr3_mc_0`（`dhi_clk`≈100MHz 用户侧，256bit AXI4，单从口） |
| PCIe | Gen2×2 EP（`pcie_ep_core` + `pcie_pll_ep`），BAR0 1MB 寄存器面 |
| 复位 | `R14` 按键 = 参考工程的 `pcie_power_on_rst`（低有效，PULLUP）。**同一引脚不得被第二个端口复用** |
| 时钟输入 | `H4` = 50MHz（SSTL135），端口名 `sys_clk` |
| 串口/灯 | `txd`=R17；`debug_led[3:0]`=E21/D21/E22/D22 |

## 2. 板级顶层（新文件，唯一顶层）

- 路径：`fpga/csi2/src/board_integration/brd_integrated_top.v`，模块 `brd_integrated_top`。
- 端口：**继承 `fpga/csi2/pcie_integration/rtl/ep_side/ph1p_pcie_ep_top.v` 的端口集合**（`sys_clk`、`pcie_power_on_rst`、`ref_pad_clk_p/n`、`pcie_rx_p/n`、`pcie_tx_p/n`、`user_int_trigger`、`txd`、`debug_led[3:0]`、`ddr_*`、`mipi_a_*`、`mipi_b_*`、`cam_a_*`、`cam_b_*`），**不新增** `sys_rst_n`/HDMI/`O_uart_txd` 等同义端口（避免同一引脚二次 assignment）。HDMI 不在本 run 范围（参考工程本身无 HDMI）。
- 内部不复用 `ph1p_pcie_ep_top` 整块做子模块（无法插入 P4）；按其结构在 `brd_integrated_top` 内例化同样的 IP/子模块，被替换的部分只有"相机写者 + 推帧源"。

## 3. 数据通路（冻结）

```
MIPI B / A 差分对
  -> rx_phy_ph1p + csi 解包 (mipi_csi2_rx_ph1p_checked, 每路一片; 40bit O_pixel_data / O_pixel_valid / O_in_line / O_in_frame / O_vsync / O_frame_good / O_frame_abort)
  -> a1_raw_crop (b18 只读复制)  ROI 1920x1080 (X0=960, Y0=540, SKIP_ROWS=37, 4K 源)
       输出 out_pix[39:0]/out_valid/out_sof/out_last/out_abort
  -> 43bit 组包 {abort,last,sof,pix[39:0]} + capture_async_fifo（格雷指针+2FF）
  -> clk_core 域：sof/eol/eof/abort 还原（eof = 第 H-1 行的 last；每帧恰好一次）
  -> integrated_delivery_top (P4 r2, 只读, 单 clk/rst_n, W=1920 H=1080 SLOT_WORDS=81085)
       b_s_* / a_s_*
  -> 原生 256bit 单拍 PAXI (ddr_aw/ar/w/r)
  -> p2_ddr_bridge (b18 只读复制) -> ddr3_mc_0 AXI4 写通道
  -> P4 desc_* -> 描述符邮箱 -> ddr_frame_pusher (参考工程只读复制)
  -> 4KB 突发 AXI4 读槽 + MWr(128B) + 独立 doorbell -> pcie_ep_engine TL 发送口
  -> PCIe Gen2x2 -> 主机/RK 内存
```

### 3.1 像素/帧语义（冻结）

- 40bit = **4 个相邻同色相 RAW10** 像素组，与 `O_pixel_data` 一致，低位在低 bit（每个 10bit 左对齐/右对齐必须与 `csi_rx_10bit_unpack_checked` 一致，按 b18 已验证接法，不得另定义）。
- ROI：`W=1920, H=1080, X0=960, Y0=540`（4K 源物理行 = SKIP_ROWS(37)+540）。每帧必须产生 `W*H/4 = 518,400` 个 40bit 拍。
- sideband：`sof` 仅帧首拍；`eol` 行末拍；`eof` **帧末拍且仅一次**；`abort` 由 CSI `O_frame_abort` 或 FIFO 丢失（sticky）产生，且必须**作为独立拍**推入 FIFO（b18 `camera_a1_uart_top.v` L305-349 的 abort_hold 模式逐字复用）。
- 帧不完整（拍数≠518400 或 EOF≠1）时 P4 内部 `int_ok_r` 守卫生效：不得 arm、不得发布、不得 export；`rel_status=1` 立即释放描述符。
- Bayer 相位按 b18 B 路已证值（读 `T10.b18-b17-b` 的 `SRC_BAYER_PHASE`/crop 参数），A 路按 b20 只读值；不得用"默认 0 占位"直接当板证结论。

### 3.2 压缩与传输长度（沿用 P2，不新定义）

- A1U1：44B 头（magic `A1U1`、version=1、flags{6'b0,pred,prep}、header_len=44、frame_id、W、H、raw_len、xform_len、stream_len、raw_crc、xform_crc、stream_crc、header_crc），`header_crc` 覆盖 0..39；后接 zlib 流。
- `raw_len = W*H*10/8 = 2,592,000`；`xform_len` 进 A+ 核字节；`stream_len` = zlib 字节；`frame_bytes = align_up(stream_len, 4096)` = 传输长。
- 槽内只存精确 `stream_len` 字节；`frame_bytes - stream_len` 的尾部由发送侧零填充；接收侧只按精确范围消费。
- `cfg_mode=3'd0`（raw 监视）+ `m_ready=1`：A+ 入口恒为 packed RAW10，与监视模式无关；三算法在板上**不参与**导出，但其 RTL 仍在网表中（不得裁剪，否则不再是 r2 候选）。
- `cfg_aplus_prep/pred` 默认取 b18 板级已验证值（读 `camera_a1_uart_top` 的 `a1_frame_top` 参数），并暴露 2 个 BAR 位；**记录产生可解码帧的那一组值**。

### 3.3 描述符/所有权（冻结）

- 每次接受一个捕获描述符：`camera_id/slot_id/epoch/session/capture_seq`；`capture_seq` 每接受一帧 +1；默认**每 good frame 一帧**（`trigger_mode` BAR 位=1 时改为 `user_int_trigger` 手动触发一次）。
- 一帧端到端深度 = 1（P4 冻结语义）：有 READY 槽未 ACK 时不再接纳新帧。
- host ACK（`session,seq` 全字段匹配）→ P4 `slot_release` → 内部 `rd_open` 排空 → `rd_close` → 同拍 `rel_*`。
- **未 ACK 时只能完成 1 帧**：这是顶层设计后果，不作为缺陷；板上必须显式记录（`held` 状态 + 槽占用）。

### 3.4 DDR 读通道所有权（本 run 新增的唯一仲裁）

P4 的排空读（单拍 AR）与 `ddr_frame_pusher` 的 4KB 突发读共用一个 AXI4 读通道，必须新增只读仲裁（`brd_ddr_rd_arb`）：

1. **授权粒度 = 一次 AR 事务（含其 `rlast` 突发）**，不得按整帧独占：每完成一次 burst（或 bridge 的单拍 R）即重新仲裁，公平轮转。
2. `pusher` 处于 IDLE/HELD/ARMED（未在搬数）时授权给 `p2_ddr_bridge` 的 AR；bridge 的单拍 AR 必须在一次 pusher burst 边界内被服务。
3. 定量约束：`p2_ddr_bridge` 的读超时守卫按其头文件为 70,000 `clk_core` 周期（150MHz ≈ 0.467ms）；pusher 单次 burst = 128 拍 @100MHz ≈ 1.28µs，故按 burst 轮转时 bridge 的最坏等待 ≪ 守卫值。**禁止**按"整帧独占"实现，否则 P4 排空 AR 会超时 giveup。
4. 正常流程下二者本就不重叠：P4 的排空读只在 host ACK 之后启动，而 ACK 同时使 pusher 回 IDLE。仲裁器只用于兜底与异常恢复。
5. `rvalid/rdata/rlast/rid` 必须按当前 owner 路由；非当前 owner 的迟到拍只计数、不重路由（防串包）。
6. 写通道不需要仲裁（P4 是唯一写主；`cam_r10f_writer`/`cam_ddr_writer`/`ddr_wr_arb` **不例化**）。

## 4. 时钟/复位（冻结；默认档见 §5）

| 域 | 来源 | 频率 | 使用者 |
|---|---|---|---|
| `sys_clk` | H4 | 50.000 MHz | PLL 参考、上电复位计数 |
| `cam_a_byte_clk` | PHY clock lane ÷4（`rx_phy_ph1p.u_hs_clk_div.clkdivout`） | 187.5 MHz | CSI A 解包、crop A、FIFO 写 |
| `cam_b_byte_clk` | 同上（B） | 187.5 MHz | CSI B、crop B、FIFO 写 |
| `clk_core` | 新 PLL（sys_clk 整数倍） | **150.000 MHz 默认**（6.667ns） | P4 核、crop 读侧、bridge A1 侧、描述符/状态邮箱 |
| `tl_clk_user` | `pcie_pll_ep` 输出（**不改**） | 继承参考工程 | PCIe EP 核、BAR、pusher、DMA 引擎、主机配置 |
| `usr_clk/dhi_clk` | `ddr3_mc_0` 输出（**不改**） | ≈100 MHz | DDR AXI、bridge DDR 侧、pusher 读 |
| `mclk27` 等 | PHY PLL（**不改**） | 继承 | 传感器 MCLK |

复位：`pcie_power_on_rst`（R14）→ 上电计数 → 各域"异步置位、同步释放"复位同步器；每域一个 `rst_*_n`。不得把 R14 直接当同步复位用；不得跨域共用未同步复位。

### 4.1 CDC 清单（必须逐项落地并在报告里指名实例）

| # | 从 → 到 | 结构 | 位置 |
|---|---|---|---|
| C1 | `cam_a_byte_clk` → `clk_core` | `capture_async_fifo`（43bit，格雷指针+2FF），`set_path_skew` 仅限格雷总线 | A 路 |
| C2 | `cam_b_byte_clk` → `clk_core` | 同上 | B 路 |
| C3 | `clk_core` → `usr_clk` | `p2_ddr_bridge` WF/AF/RF 三只格雷 FIFO | DDR 写/读 |
| C4 | `clk_core` → `tl_clk_user` | 描述符邮箱：字段稳定保持 + `arm` toggle（4 相）+ 2FF | `brd_desc_mbox` |
| C5 | `tl_clk_user` → `clk_core` | ACK/CANCEL 单比特 toggle + 2FF | `brd_ack_sync` |
| C6 | `tl_clk_user` → `clk_core` | pusher 状态（done/err/held）稳定保持 + toggle；多比特不得直接 2FF | `brd_pcie_track` |
| C7 | `tl_clk_user` → `clk_core` | BAR 静态配置影子（`cap/session/dst/db/push_en`）：配置更新 toggle 后整组影子采样；帧活动期主机不得改配置 | `brd_cfg_shadow` |

禁止：未列出的跨域组合路径、把 `clk_core` 当时钟 mux 的运行时选择、用 `set_false_path` 掩盖真实数据路径。允许的 `false_path` 仅限：`pcie_power_on_rst` 异步输入、`user_int_trigger` 异步按键（经同步器后使用）。

## 5. 时序策略（本 run 的核心取舍，冻结决策规则）

事实：r2 在**仅内部寄存器、单时钟 187.5MHz、42 IO** 的综合中已 WNS −0.637ns / 112 端点；板级再加入相机、DDR、PCIe 与真实 IO，187.5 不可能自愈。**因此本 run 不把"187.5MHz 收敛"当成本轮门槛**，改按 §4 的 `clk_core` 档位推进，并如实记录吞吐差距。

- 允许档位（只能取其一，SDC 同步改）：**150.000MHz（默认）**、125.000MHz、166.667MHz。禁止用非整数倍/不可综合的 PLL 比率。
- 依据：P4 为 4px/clk；1080p30 单路需 62.21 Mpx/s。150MHz → 600 Mpx/s（≈9.6×）；ROI 后瞬时组率 ≤75 组/s×10⁶（300 Mpx/s），仍有 2× 余量。125MHz 仍有 1.67×。**核时钟不是本链路瓶颈**（瓶颈是相机 MCLK 与 PCIe/软件）。
- 不修改 P4 任何源码即可完成全部档位；**禁止**为时序去改 `fpga/csi2/src/integrated_delivery/**` 或 `img/**`。
- 若确实需要结构改造（例如 r3 式 row-window 读地址寄存），只能新增 `board_integration/` 派生文件 + 用 `tb_img_algo_equiv_p4.v`（含 `+STALL` 与 always-ready）证明 token 等价，并且**本轮默认不做**（预算只允许 3 次综合/2 次布线/1 次 bitgen，没有等价修复的余量）。
- 判定规则（次序不可跳）：
  1. `synth#1` 于 150MHz：若 `WNS ≥ +0.25ns` → `route#1`；若 `+0.127…+0.25` → `route#1`（薄裕量风险已知）；若 `< +0.127` → 不布线，改 125MHz 做 `synth#2`。
  2. `route#1`（或 `synth#2` 后的 `route#2`）：**0 违例端点** 且 `WNS ≥ +0.003` 才允许 `bitgen#1 + CWC#1`；`+0.003…<+0.05` 记 `timing_caveat=thin_margin`；`< +0.003` 或仍有违例 → **不出 bit**，返回规划。
  3. `synth#3` 只用于 125MHz 的补救或一次明确的小改动；不得用同源集重跑充数。
  4. 禁止：`set_false_path`/`set_multicycle_path` 于内部路径、改 SDC 目标频率凑 PASS、用 synth 数字代表板级时序、用 r3 数字代表本顶层。
- 板级 STA 必须来自**本顶层**（真实时钟 + 真实 IO），报告须含：总端点、违例端点、WNS/TNS/Hold、未约束 IO 列表、资源（SLICE/LUT/REG/ERAM/DSP/IO）、时钟交互（CC）与组合环、未驱动 DUT 输入清单。

### 5.1 性能目标的诚实定位

- 1080p30 是**性能目标，不是本 run 门槛**。参考工程 README 实测：传感器 MCLK 12.5MHz 时 4K≈7.85fps，需把 MCLK/INCKSEL 调到 24–27MHz 才可能 30fps。**本 run 不改相机 MCLK**；若真实帧率低于 30，只记录差距与原因，不得写成达标。
- 验收只要求"单帧完整正确导出"；随后允许 2–3 帧短序列验证槽释放，不要求长稳/持续吞吐。

## 6. 寄存器/BAR 面（沿用参考工程，不重定义）

| 地址 | 用途 | 本 run 归属 |
|---|---|---|
| `0x44 CTRL` | bit5 ddr_en、bit6 push_en、bit7 push_src、bit8 A/B 取帧；**新增 bit9 `a_enable`、bit10 `trigger_mode`、bit11 `p4_desc_owner`（默认 1）** | 主机 |
| `0xB0/0xB4` | 主机目标地址 lo/hi | 主机 |
| `0xB8/0xBC` | doorbell 地址 lo/hi | 主机 |
| `0xC0/0xC4/0xC8/0xCC` | 已推帧数 / 状态 / 错误码 / MWr 数 | 推帧引擎 |
| `0x100/0x104` | cap_bytes / session_id | 主机 |
| `0x108` | TX_CMD：bit0 ARM、bit1 ACK、bit2 CANCEL | 主机 |
| `0x10C/0x110` | ACK_SEQ / ACK_SESSION | 主机 |
| `0x114` | TX_STATUS | 推帧引擎 |
| `0xD0/0xD8` | A/B 相机诊断 | 相机 |
| **新增** `0x130..0x13C` | P4 状态字：`{state,committed,slot_used,push_en}` / `{st_raw_len,st_stream_len}` / `{st_stall,st_blocks}` / `{release 计数,err 计数}` | P4 影子 |

未列出的地址不得改语义；新增地址必须写进本 run 的协议文档并在 `ep_bar_win.v` 的只读复制副本中实现（原文件只读）。

## 7. 构建入口与工程（冻结）

- 工程/构建目录：`workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/td/`（`.al` + tcl + 约束 + 源文件表）。
- 脚本入口：新建 `tools/board_integration/`（`run_td.ps1`、`td/00_all.tcl`、`td/01_synth.tcl`、`td/02_route.tcl`、`td/03_bitgen_cwc.tcl`、`gen_manifest.py`），模型照 `tools/pcie_integration/run_td.ps1`（`td_commands_prompt.exe`，单会期，`-OutDir` 指向 run 目录）。**不得**执行 `upstream/.../download_sram.tcl`。
- 路径：`.al` 与 tcl 中所有绝对路径重写到本 run；`T:` 必须用 `tools/td/td_env.ps1 -Force -TdDir <本run td>` 重指（当前 T: 指向 b20，误用会写坏 b20）。`Y:`→`D:\fpga\ph1p100`。
- 文件表守卫：不得把 `*.v.stale`、`src/src/**` 重复模块、`peer-ref-2a4b253/` 参考副本编入；同名模块只允许一个来源。每次构建前打印实际 filelist 与重复模块检查结果。
- 约束：`.adc` 由 `ph1p_pcie_case_ep.adc` + `board_p2.adc` 合成（PCIe/DDR 引脚来自 IP 的 `set_ippin_assignment`；相机/系统/串口/灯取两份并去重；`R14` 只保留 `pcie_power_on_rst` 一个端口）。`.sdc` = 参考 `ph1p_pcie_case_ep.sdc` 的时钟/异步组 + 新增 `clk_core` 与 C1/C2/C3 的格雷总线 `set_path_skew`；未约束 IO 必须为 0（或逐条列出未用）。
- 每次构建必须：源集哈希与前次不同、等价/回归仿真先通过、写清假设；不得用属性实验或同 netlist 重跑充数。
- 构建超时：单阶段 30min（synth/route 各自）、bitgen+CWC 20min、单会期 60min；到点安全终止本流程进程并保留日志。

## 8. 资源与容量预算（设计预算，不是实测）

- P4 r3 参考资源：slice 10,691/71,680、LUT 12,943、reg 6,004、ERAM 39/300、DSP 14。板级另加：2× CSI 前端、2× crop、2× 43b FIFO、DDR3 MC、PCIe EP + PLL、pusher、bridge、read arb。ERAM 预算上限 300，IO ≤286（参考工程用了约 110）。
- DDR 占用：P4 两槽 `81085` words/槽 ×32B = 2,594,720B/槽，基址 0 与 2,594,720B；**不得**与参考 `DDR_CAM_BASE0/1` 区域重叠（参考基址 1MB/9MB 会被 P4 覆盖 → 必须显式把 P4 槽区放在 0 起，并在协议里写明）。
- PCIe：MPS 128B、4KB 突发、MWr + doorbell；单帧 `frame_bytes ≤ 2,594,720`。

## 9. 证据与报告约定

- 每包一份 manifest（源 SHA256、约束 SHA、bit/CWC SHA、TD 报告、日志、样例、下载记录），`stopped_modifying=true`；测试者绑同一 manifest。
- 报告区分 `pass/fail/not_run/blocked/not_applicable`；未运行命令写"建议"，不得混入"实际执行"。
- 独立判据：导出帧必须由测试者用自己的解码路径（A1U1 header/CRC + zlib + 逐字节 ROI 比对）复核，不得只读开发自述或开发脚本输出。
- 未出 bit/未下载/未拿到真实帧时，只能写 `not_run`/`awaiting_hardware`。

## 10. 已冻结 / 待确认 / 不适用（交 dev-plan）

**已冻结**：板卡/器件；顶层端口集；数据通路；ROI 几何；43b CDC 组包；A1U1 长度/CRC 语义；描述符与 ACK 全字段匹配；DDR 读通道所有权；时钟档位与判定规则；只读输入；写范围；TD/下载额度（synth≤3/route≤2/bitgen≤1/CWC≤1/download≤1/Flash=0）。

**待确认（由本 run 证据决定，不预设）**：b18 的 `cfg_aplus_prep/pred` 与 Bayer 相位具体值；P4 槽基址与 `ddr_frame_pusher.ddr_base` 的字节/字换算实测确认；单 bit 内 A/B 双前端资源/时序；主机端（RK）接收与解码可用性；R14 按下到 PLL 锁定的上电时序。

**不适用（本轮，理由）**：1080p30 实测（相机 MCLK 限制，另开任务）；长稳/G4（用户明确后置）；双路并发（本轮单路）；HE/Gau/Y8 板上输出（`cfg_mode=0`，算法仅随网表存在）；HDMI 显示（参考工程无 HDMI，非本目标）；Flash（额度 0）。

**三维检查边界**：functional = 语义/协议/帧完整性/等价；engineering = 真实顶层 STA/CDC/资源/构建可复现/候选绑定；system = 真实板卡下载/导出/解码/身份与恢复。纯文档步骤可用 G5 与静态复核，但不得用文档 PASS 代替 RTL/板测。
