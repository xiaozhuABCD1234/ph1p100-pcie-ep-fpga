# T11.rk-align-base — 逻辑冗余/优化只读勘察报告

范围：主 = 集成树 `fpga/csi2/pcie_integration/`（含 T07/T11 引入的 checked/写者/pusher 接线）与只读 STA 报告（`raw/g2/`、`backend/g2/` 的最差路径与余量）；次 = 旧主线只读备注。**本包不改任何代码**；所有条目只读取证，`file:line` 可复核。

取证时间：2026-10-17（本包运行期）；只读快照见 `env/input-snapshot.json`（36 个文件 SHA/mtime；生产输入 17 条与 `raw/candidate-manifest.json` 逐条一致）。

修订：round1（2026-10-17）按 r0 functional 报告 F1/F2 修正 S1-1 的证据子句（+5.058 的真实来源与性质）与 §0 未实例化模块计数口径，并更新两处"判定前只读"的时效措辞。round2（2026-10-17）按 r1 functional 报告 F1-r1 的要求复核本报告内绝对断言：§0「唯一」加范围、S1-1 的登记指代精确化（→ `T11.rk-align-raw-r0-engineering.md` §6 观察第 4 条）、S1-2「唯一有效清单」措辞收敛、§3「全树」与 §6「未进本工程」写明扫描范围。其余条目、分类与结论未变。

格式：`ID｜位置(file:line)｜现象｜类别｜估计收益｜风险｜验证方式｜优先级`

---

## 0. 结论摘要

- 集成树整体健康：T07/T11 已把 187.5 MHz 字节域最差的"CRC 比较→计数 enable"锥重构掉（round2），当前 T11 最差路径余量 **+0.115 ns**、67% 为布线（`raw/g2/README.md:29`）；**相机字节域余量薄**是本次勘察发现的唯一时序/资源类优化靶点（T1）。
- 已知历史项全部核对过现状（§3）：其中 3 项为**纯文档**（零重建：S1-1/S1-2/S1-3）、3 项为 **RTL 内注释/死代码**（无行为变化、但改字节需随重建：S1-4/S1-5/S1-6）、其余 3 项为**工程清单/peer 继承类**（建议仅标注或记录，不单独触发重建：S1-7/S1-8/S1-9）。
- 未发现新的**功能级**冗余/重复逻辑；未实例化模块 **6 个**（历史参照保留类，见 S1-7；口径：生产 0 实例 3 个 + 仅被未实例化模块实例化 2 个 + 仅 TB 使用 1 个），对 bit/时序 0 影响。
- 不建议项 3 条（§4）已明确"评估后不建议"，避免后续误实施。

---

## 1. 安全快速项（无行为风险）

| ID | 位置(file:line) | 现象 | 类别 | 估计收益 | 风险 | 验证方式 | 优先级 |
|---|---|---|---|---|---|---|---|
| S1-1 | `workflow/runs/20261017-011744-rk-fpga-align/raw/g2/README.md:28` | 「按时钟（SWNS）」写 `clk1 tl_clk_user 62.5 MHz +5.058`；clk1 时钟摘要行实测 **+1.141**（`raw/candidate/prj/ph1p_pcie_integration_Runs/phy_1/final_timing.rpt:54`；pr.timing 同 +1.141；place +3.194；syn gate +4.725；T07 r3 为 +0.540）。**+5.058 的真实来源**：同一份 `final_timing.rpt` 内 `Path Group: tl_clk_user → tl_clk_user` 的 SWNS（L2073-2081：`Max: SWNS 5.058ns, STNS 0.000ns, 0 Viol Endpoints, 12271 Total Endpoints`，Min Period 10.942ns = 16.000−5.058；组内最差路径 L2087 Slack=5.058、L2210 同值；pr.timing 同）——即 README 把「Path Group SWNS」**跨节误引**成「时钟摘要 clk1 行」，而非无来源的笔误（原"全库检索无 +5.058 来源"表述已在 round1 修正）。该单值问题登记于 `test-reports/T11.rk-align-raw-r0-engineering.md` §6 观察第 4 条（其 `verify_supplement.txt` §G 详载） | 文档单值笔误（跨节误引） | 可维护性/可审计（不影响任何门槛） | 零（纯文档）；`raw/` 是 T11.rk-align-raw 交付域（其 r0 已收束），修正由规划者/获授权包执行 | 分别核对时钟摘要行（L54）与 Path Group 节（L2073-2087）后重写该单值 | 安全快速（建议最先） |
| S1-2 | `workflow/runs/20261017-011744-rk-fpga-align/backend/g2/README.md:153` | §6 写「三维复测必须绑定 round2 manifest（`cde55fc8…edec`）」；T07 r3 最终清单实算 = **`68F9F4D0…4275`**（本包实算 `backend/candidate-manifest.json`，与 `raw/candidate-manifest.json` 的 `baseline_candidate.manifest_sha256` 同值）。T07 r3 已换绑，此句未随动（F5-r3） | 文档绑定句陈旧 | 可维护性（避免测试者绑错清单） | 零（纯文档）；`backend/` 属 T07 交付域，下次触碰时改绑（由规划者/获授权包） | 对照 `backend/candidate-manifest.json` 实算 SHA 重写 | 安全快速 |
| S1-3 | `workflow/runs/20261017-011744-rk-fpga-align/backend/g1/crc16_upd4.generated.v:1` | 文件头仅「由 gen_crc16_flat.py 生成（请勿手改）」，未标「早期单体中间产物、非生产文件」。README 已有就地标注（`backend/g1/README.md:71-73`）。本包复算：生产 `rtl/checked/crc16_upd4.v`（8,905 B，`20520D04…`）可由冻结生成器逐字节复现（`env/verify/`，4×20030 例 0 失配）；中间产物 3,475 B、`82551E02…`，两者不同 | 文档标注（防误引） | 可维护性 | 零（非生产文件；不在 TD 工程清单内） | 文件头加 2 行「非生产/过程留痕」；或维持 README 标注并在清单里注明 | 安全快速（低） |
| S1-4 | `fpga/csi2/pcie_integration/rtl/checked/csi_rx_packet_integrity.v:18` | 头注释 ③ 写「计数移到包尾的后一拍（**新状态 END_PEND**）」；实际无 END_PEND 状态（状态集 L39 = IDLE/HEADER/BODY/END_PACKET），实现是折进既有 END_PACKET 第一拍（L163-172）。T07 change-report §10.3 F3 已登记 | 陈旧注释 | 可维护性（消除对状态机的误读） | 零行为；改 RTL 字节 → 破坏"源↔位流"绑定，须随 opt 包重建（不可单独改） | 随 T1 同批重建：全 G1（含差分 oracle）+ G2（相机字节域 setup≥0） | 安全快速（随重建） |
| S1-5 | `fpga/csi2/pcie_integration/rtl/ep_side/cam/mipi_csi2_rx_ph1p_checked.v:217-219` | 空的 `` `ifdef MIPI_PHY_SIM_STUB / `else / `endif `` 预处理块（no-op） | 死代码（no-op 块） | 可维护性；功能/时序 0 | 零行为；改字节须随重建 | 随重建：vlog 0 错 + 全 G1 + G2 | 安全快速（随重建，低） |
| S1-6 | `fpga/csi2/pcie_integration/rtl/ep_side/ddr/cam_r10f_writer.v:44` | 头注释写「一笔 **4 字节**部分写（strb=0x0FFF0000，地址 base+64）把 0x50/0x54/0x58 写进 DDR」；实现是 **12 字节 / 3 个字**（`rw_strb = 32'h0FFF_0000` 覆盖 0x50..0x5B，见 L759-762 与 L934 地址 base+64） | 陈旧/错误注释 | 可维护性 | 零行为；改字节须随重建 | 随重建：写者 TB P1/P2 对 0x50/0x54/0x58 的冻结向量已覆盖该路径 | 安全快速（随重建，低） |
| S1-7 | `tools/pcie_integration/td/00_all.tcl:21,43,47,50,56,63` | 工程清单把**不实例化**的模块也 add_files：`img_regs.v`（0 实例，被 `ep_bar_win.v` 取代）、`mipi_csi2_rx_ph1p.v`（0 实例，被 checked 版取代）、`csi_rx_packet_handler.v`（仅被前者实例化）、`csi_rx_10bit_unpack.v`（仅被前者实例化）、`ui_imx415_reg.v`（0 实例，仅顶层注释 L1025 提及）、`cam_ddr_writer.v`（生产 0 实例；仅 `sim/tb/tb_csi_checked.v:105` 用） | 死代码（参照保留类） | 可维护性；编译时间小幅（估计 <1%，待验证） | 移出清单会改变候选输入集（需重建+三维复测）且破坏 peer 参照；`cam_ddr_writer` 仍被 TB 依赖 | 建议**不删除**：在 00_all.tcl 就地注释「参照保留、elaboration 丢弃」；如确需清理则整包重建 + 全 G1/G2 | 安全快速（仅标注） |
| S1-8 | `fpga/csi2/pcie_integration/rtl/ep_side/ph1p_pcie_ep_top.v:1005-1008`（peer 同款 `peer-ref-2a4b253/rtl/ep_side/ph1p_pcie_ep_top.v:932-935`） | 4 行注释掉的 `debug_led[4..7]` 赋值（peer 原样继承） | 陈旧注释（peer） | 可维护性（极小） | 零；改动会偏离 peer 参照 | 无（注释）；建议保留不动 | 最低（记录） |
| S1-9 | `fpga/csi2/pcie_integration/rtl/ep_side/ph1p_pcie_ep_top.v:974`（peer 同款 `peer-ref-…:901`） | 读映射 `8'd18` 取 `ltssm_debug[9]`，跳过 `[8]`（写入侧 L926/L939 会写 [8]）→ 寄存器 0x18 实际是"第 10 次跳变"，[8] 永远读不出。诊断路径，与控制无关 | 不可达映射（peer 原样继承） | 可维护性（几乎无） | 修它会改变 0x18 语义、与 peer 经验不一致，需与队友协调；不动零风险 | 如修：读 0x10..0x1C 与 `ltssm_change_cnt` 对照（待验证） | 最低（记录，不建议单方面改） |

> S1-4/5/6 属"行为零风险、但改的是冻结 RTL 字节"：**不得单独修改**，必须与结构项（T1）同批重建、同批冻结，否则破坏 T11 冻结输入与在途测试的绑定。

## 2. 结构项（需差分 oracle + G2 重跑）

| ID | 位置(file:line) | 现象 | 类别 | 估计收益 | 风险 | 验证方式 | 优先级 |
|---|---|---|---|---|---|---|---|
| T1 | 最差路径：`raw/candidate/prj/…/phy_1/final_timing.rpt:4004-4051`（摘要 `raw/g2/README.md:29`） | T11 最差路径 `u_csi_a/u_gear_box/O_word_out_reg[3] → u_cam_r10f_writer/f_mem_syn_65.csa[2]`：4.503 ns（cell 1.495/33%，**net 3.008/67%**）、逻辑级 4、`f_wr` 扇出 24（L4049）；clk2 +0.115 / clk3 +0.150（L55-56）。锥 = gear_box → checked 完整性/解包与写者 `push_*`/`f_wr`（`cam_r10f_writer.v:284-310`）→ ERAM 写口 | 时序瓶颈（余量薄） | 目标：把字节域 setup 余量从 +0.115 提升到 ≥ +0.3 量级（**实测为准，不承诺**） | 中：改 187.5 MHz 域数据/控制通路，语义必须差分证明；不得放宽 SDC/加 multicycle | 差分 oracle（新旧并联，随机+边界流量逐拍比对）+ 写者 TB 冻结向量（P0..P10）+ 1080p 边界 TB + e2e + **G2 重跑（门槛：cam_a/cam_b 字节域 setup ≥ 0）** | **中（opt 包核心）** |
| T1a | 手法 a：`cam_r10f_writer.v:295-310`（FIFO 写口） | 在 FIFO 写口加 **1 级流水**（寄存 `f_din` 与写选通；`wfull` 记账随实际写拍、`drop/ovf` 计数按写拍计）：把"gear_box→ERAM"拆成两段短路径 | 时序重构（本域） | 直接切最差锥；净延迟 67% 部分被隔离（预计 0.5–1.5 ns 量级，实测为准） | 中：写序列/标记顺序须逐拍不变；FIFO 满/丢弃语义必须与现版一致（写指针只由本模块推进，`wfull` 在捕获拍成立则写拍仍成立——需在差分中验证） | 同上；另用"写口流水开/关"两版并联差分（输入相同） | 中 |
| T1b | 手法 b：`cam_r10f_writer.v:208-214`（g0..g4 打包） | 把 5 字节打包（`g0..g4`，L208-214）从 187.5 MHz 域**搬到 100 MHz DDR 域**（FIFO 存原始 `cam_pix[39:0]`，DDR 侧打包）：移除字节域组合逻辑 | 时序重构（跨域重定时） | 字节域少一组位选/拼接逻辑（量级同 T1a，实测为准）；DDR 域余量充足（clk0 +0.626） | 中：FIFO 内容语义变化（原始 40bit vs 打包 40bit），打包正确性必须重新证明（负对照 M1 类） | 打包模型独立 oracle + 冻结向量 + 1080p + 差分 + G2 | 中 |
| T2 | `fpga/csi2/pcie_integration/rtl/ep_side/ph1p_pcie_ep_top.v:1552` vs `1611-1613`；`cam_r10f_writer.v:116` | A 片接 `.dbg_drop(w_camddr_drop_a)`（出口 0xDC/0xF0/0xF4），B 片**未接** `dbg_drop` → B 路丢帧/裁决快照无寄存器出口（诊断不对称，非冗余） | 可维护性/诊断缺口 | 板测定位 B 路坏帧的能力 | 低-中：需改顶层接线 + `ep_bar_win.v` 只读区寄存器面；寄存器表扩展需 RK 侧知晓（只读诊断，风险低）；必须重建 | 重建 G1/G2；板测读新寄存器与 0xE8 状态对照 | 低（opt 可选项） |
| T3 | `fpga/csi2/pcie_integration/rtl/checked/csi_rx_packet_integrity.v:83-90` | 每拍并行计算 crc16_upd1..4 四个变体后 mux 选一（crc_next）。综合会共享 XOR 公共项；round2 已用此结构达标 | 冗余计算（受控，评估项） | 若改"只算 u4 + 末拍修正"可省少量 LUT（估计 <1%，待验证），但会加深末拍逻辑或引入条件项，**可能反而伤时序** | 中：CRC 结构改动需差分 oracle + G2 | 差分 + G2（若实施） | **不建议**（见 §4） |

## 3. 已知项现状核对（不得照抄旧结论——以下均为本包实读）

| 已知项（来源） | 本包实读现状 | 判定 |
|---|---|---|
| `csi_rx_packet_integrity.v` END_PACKET 死分支（T07 change-report §8.5） | **仍在**：同一 case 两段 `END_PACKET:`（首段 L165-172，第二段 L176；L171 已含 `if(!I_data_valid)state<=IDLE;`）；第二段不可达（Verilog 首项命中）；L173-175 是其陈旧注释 | 现状=死代码+陈旧注释（S1-4 同文件、建议同批） |
| 同文件头注释"新状态 END_PEND"（§10.3 F3） | **仍在**（L18）；文件无 END_PEND 状态（L39） | 现状=陈旧注释（S1-4） |
| `raw/g2/README.md` §2 clk1 单值笔误 | **仍在**：L28 写 +5.058（= Path Group `tl_clk_user→tl_clk_user` 的 SWNS 跨节误引，final_timing.rpt L2081）；clk1 时钟摘要行实测 +1.141（L54） | 现状=文档错误（S1-1，round1 已修正证据表述） |
| `backend/g2/README.md` §6 旧 manifest 绑定句（F5-r3） | **仍在**：L153 写 round2 `cde55fc8…edec`；实算 r3 = `68F9F4D0…4275` | 现状=文档陈旧（S1-2） |
| `backend/g1/crc16_upd4.generated.v` 中间产物标注（F4） | README 标注**在**（`backend/g1/README.md:71-73`）；文件头**无**"非生产"字样；本包复算生产文件可由冻结生成器逐字节复现（`env/verify/gen_selfcheck.txt`） | 现状=README 已标、文件头可加（S1-3） |
| 相机字节域余量薄（+0.115 ns、67% 布线） | **仍在**：final_timing.rpt L4004-4051（Slack 0.115 / net 67% / `f_wr` 扇出 24）；clk2/clk3 = +0.115/+0.150 | 现状=结构靶点（T1） |

补充核对（本包新增）：
- `backend/g1/crc16_upd4.generated.v` = 3,475 B、SHA `82551E02…`（与生产 `20520D04…`/8,905 B 不同，确非副本）。
- 生产 `rtl/checked/crc16_upd4.v` 与 `rtl/ep_side/ddr/crc32_upd4.v` 均可由冻结生成器**逐字节复现**（自检 4×20030 / 4×20040 例 0 失配；`env/verify/`）。
- 未实例化模块清单（S1-7）由集成树 `fpga/csi2/pcie_integration/`（排除 `peer-ref-2a4b253/` 参照）实例化扫描得出：`img_regs`、`mipi_csi2_rx_ph1p`、`csi_rx_packet_handler`（仅被前者）、`csi_rx_10bit_unpack`（仅被前者）、`ui_imx415_reg`、`cam_ddr_writer`（仅 TB）。

## 4. 评估后"不建议"项（明确记录，避免误实施）

| ID | 内容 | 不建议理由 |
|---|---|---|
| N1 | 给 `csi_rx_packet_integrity` 的 CRC 递推"加流水/加寄存器" | T07 round2 §3.4 已论证：CRC 逐拍递推回喂同一寄存器，插流水不解决递推路径；且字节域不可反压 |
| N2 | 放宽 SDC / `set_multicycle_path` / `set_max_delay` | 逐拍递推数据通路上放宽约束会引入功能风险；T07/T11 明令禁止，判据不变 |
| N3 | 删除未实例化模块 / 把 B 路 `dbg_drop` 简单悬空"清理" | 参照保留是 T07/T11 的冻结决策；删除改变候选输入集且破坏 peer 差分参照；B 路诊断缺口应作为"新增出口"而非"删除接线"处理（T2） |

## 5. 建议实施顺序（供 T11.rk-align-opt 规划）

1. **先做纯文档项**（S1-1/2/3）：零重建、零行为风险。注意 `raw/`、`backend/` 是 T11/T07 交付域——T11.rk-align-raw r0 已收束（三维 PASS）；修正由规划者/opt 包在其 write_scope 内执行（本包不改）。
2. **结构项 T1（T1a/T1b 二选一或组合）** + 同批 RTL 注释/死代码清理（S1-4/5/6）：一次重建、一次冻结；验证 = 差分 oracle + 全量 G1 + G2（相机字节域 setup ≥ 0 为回归门槛，**不得**用平均/其它域余量替代）。
3. **可选 T2**（B 路诊断出口）：若板测计划需要 B 路坏帧定位再排；否则留待下一轮。
4. **S1-7/S1-8/S1-9** 仅标注，不单独触发重建。

每项的最小验证集：
- 纯文档（S1-1/2/3）：对照原始报告/清单实算值复核即可（无需 G1/G2）。
- RTL 注释/死代码（S1-4/5/6）：与结构项同批 → 全 G1 + G2；对 S1-4 额外跑差分 oracle（它就在差分覆盖内）。
- T1a：差分（新旧并联）+ 写者 TB + 1080p + e2e + G2；另加"写口流水开/关"对照。
- T1b：打包 oracle（含 M1 反序负对照）+ 冻结向量 + 1080p + e2e + G2。
- T2：重建 G1/G2 + 板测读寄存器。

## 6. 边界与免责

- 本包（round0 勘察）**未运行**任何 TD 构建/verilator；round1 仅为验证手册示例可执行性跑了 1 次写者 TB（`tb_cam_r10f_writer`，`ALL PASS` / `Errors: 0`，见 `change-report.md` §R1）；round2 仅文档修正（无仿真/构建）；未下载、未写 Flash、未操作硬件；未修改 `fpga/csi2/pcie_integration/`、`tools/pcie_integration/`、`raw/`、`backend/` 中任何文件（`env/input-snapshot.json` 的 17 条生产输入 SHA 与冻结 manifest 逐条一致）。
- 估算收益为"量级判断"，**不是实测**；一切结论以 opt 包实际 G1/G2 为准。
- 未覆盖：旧主线（`fpga/csi2/src/`）与 peer 参考库（`peer-ref-2a4b253/`、`references/`）未做逐文件冗余扫描（只读参照用途）；`rtl/rc_side/**` 未进 TD 工程清单（`00_all.tcl`），本包不扫。
