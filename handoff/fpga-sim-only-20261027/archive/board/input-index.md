# 输入索引 — 20261027-0726_fpga-board-integration

> 本轮唯一主要目标：把 P4 r2 功能核接入真实板级工程（相机 B→DDR→P4→PCIe），产出整机 bit 并完成**先 B 后 A**的真实单路压缩帧 PCIe 完整导出。长稳/吞吐/非阻塞优化后置。
> **承接自 ⚠ INT.P4**：r2 functional+system pass 但 G2 fail（112 端点 / WNS −0.637ns / TNS −69.776ns）；r3 G2 0 端点/+0.072ns 但派生变体等价 fail。功能基线只能取 r2（`DFAB7F9D…`），r3 派生变体禁止作功能输入。
> 所有"未出 bit/未上板/未真实传输"的事实不得改写为通过。

## 1. 需求与决定

| 项 | 路径 | 用法 |
|---|---|---|
| 用户原话（机械登记） | `workflow/runs/20261027-0726_fpga-board-integration/request.md` | 本轮范围与禁止 |
| 需求与边界全文 | `workflow/runs/20261026-2138_fpga-integrated-delivery/follow-on-run-request.md` | §0–§9；包结构、门槛、预算来源 |
| 上游收尾 | `.../20261026-2138_fpga-integrated-delivery/final-summary.md` | P1/P2/P3=PASS、P4=⚠、剩余主题 |
| 上游交接 | `.../20261026-2138_fpga-integrated-delivery/handoff.md` | 恢复入口、候选绑定 |
| 决策矩阵 | `.../20261026-2138_fpga-integrated-delivery/decision-matrix.md` | D4 选择 (a)：⚠ 下开板级新 run |
| 5 倍额度授权 | 本 run `request.md` L11-13、L25 | 仅本新任务；不改变包/层上限 |

## 2. 功能基线（唯一允许的 P4 输入）

| 项 | 路径 | 状态/哈希 |
|---|---|---|
| **r2 manifest（功能基线）** | `workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4-r2-manifest.json` | SHA256 `DFAB7F9D7FF7B7F8FB1D9B4401844F3D76102064C99FC4338192FB8A0C59B32E`；functional+system pass，G2 fail |
| r2 综合证据 | `.../INT.P4/td/syn_r2_run2/**`、`.../INT.P4/td/syn_flow.status` | WNS −0.637 / 112 端点 / TNS −69.776 |
| r2 集成报告 | `.../test-reports/INT.P4-r2-integrated.md` | 独立综合测试判定 |
| r3 manifest（**禁止作功能输入**） | `.../INT.P4-r3-manifest.json` | SHA256 `43EBFF3D110234A225DD2A449804BC863F47EC5D7FAE89966C970B5EA9526F1`；仅"该网表收敛"的时序参考 |
| r3 报告/教训 | `.../test-reports/INT.P4-r3-integrated.md`、`.../INT.P4/result-r3.md` | 等价破坏证据（y8 383/317/3、gau 1368/1154/10、he 1116/980/44、bayer +STALL 769 vs 783） |
| 协议/构建/步骤 | `.../INT.P4-protocol.md`、`.../INT.P4-build-entry.md`、`.../INT.P4-shortest-steps.md` | **r2 段残留 PASS 断言以 r3 报告与本 run 为准** |

**冻结禁止**：不得把 `algo_rowwin3_p4.v` / `gray8_gaussian3x3_stream_p4.v`（r3 派生变体）作为板级功能源；不得把 r2 功能证据与 r3 G2 数字拼成 PASS；不得用 b20 `a1_board.bit` 冒充本次整机 bit。

## 3. P4 r2 候选源码（只读，按 manifest 哈希绑定）

`candidate_root = fpga/csi2/src/integrated_delivery/`，全部文件与 `INT.P4-r2-manifest.json` 的 `new_files` 一致：

| 文件 | 用途 |
|---|---|
| `integrated_delivery_top.v` | 唯一集成顶层（单 clk/rst_n；参数 W/H/SLOT_WORDS） |
| `integrated_input_processing_top.v` | 双消费者握手 + 帧完整性守卫 |
| `bayer_raw10_demosaic4_p4.v`、`img_algo_parallel_top_p4.v` | 时序派生（端口/语义不变），r2 的一部分 |
| `aplus_pcie_egress_adapter.v` | 描述符/有效长度/尾拍/完成/释放 |
| `dual_channel_capture_scheduler.v` | A/B 身份、`a_enable`、B 优先/轮转 |
| `frame_good_publish_cancel.v`、`raw10_sample_vector_to_packed.v` | P1 冻结件 |
| b20 只读 A+ | `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b20-a-timing/r0/changed-src/{a1_frame_top.v,a1_deflate_core.v,a1_ddr_slot_store.v,a1_ddr_arb2.v}`（哈希见 r2 manifest `readonly_a1_inputs`） |
| 算法源（只读） | `fpga/csi2/src/img/**`（10 个文件，哈希见 r2 manifest `img_sources`） |
| 解码/样例/工具 | `tools/integrated_delivery/{a1u1_decode.py,verify_integrated_sample.py,evidence/integrated_sample.a1u1}`（`79e35f28…` / RAW `1357408f…` / JSON `76d88910…`） |
| 集成仿真入口 | `tools/integrated_delivery/run_integrated_sim.ps1`、`.../td/{01_synth.tcl,02_route.tcl,integrated_core.sdc}` |
| 等价 TB | `fpga/csi2/src/integrated_delivery/tb_img_algo_equiv_p4.v`（`+SEEDMODE=0/1/2`）、`tb_integrated_delivery_top.v` |

## 4. 板级工程基座（只读）

| 项 | 路径 | 说明 |
|---|---|---|
| **EP 板级顶层（本板已跑通 4K→DDR→Gen2×2 推帧）** | `fpga/csi2/pcie_integration/rtl/ep_side/ph1p_pcie_ep_top.v` | 相机 A/B + checked CSI + DDR3 + PCIe EP + 推帧引擎，含 `u_csi_a/u_csi_b`、`u_ddr3_mc_0`、`u_ddr_wr_arb`、`u_ddr_frame_pusher` |
| 相机/CSI | `.../rtl/ep_side/cam/**`（`mipi_csi2_rx_ph1p_checked.v`、`ui_cfg_imx415.v`、`ui_i2c.v`、`rx_phy_ph1p.v` …） | 40-bit `O_pixel_data` + vsync/in_frame/in_line/frame_good/abort |
| DDR/PCIe | `.../rtl/ep_side/ddr/{ddr_frame_pusher.v,ddr_wr_arb.v,cam_r10f_writer.v,cam_ddr_writer.v}`、`.../rtl/ep_side/pcie_ep_engine.v`、`.../rtl/common/**` | 推帧 = 4KB 突发 MWr + 独立 doorbell，ARM/HELD/ACK/CANCEL |
| 约束 | `.../constraints/ph1p_pcie_case_ep.adc`、`.../constraints/ph1p_pcie_case_ep.sdc` | 本板 PCIe/camera 引脚与时钟；`R14`=`pcie_power_on_rst` |
| IP | `.../al_ip/{pcie_ep_core,pcie_pll_ep,ddr3_mc_0,ram}` | 版本匹配 IP 源与 `.adc`（DDR/PCIe 引脚由 IP 派生） |
| 仿真 TB | `.../sim/tb/{tb_ep_bar_win_rka1.v,tb_ddr_frame_pusher_rka1.v,tb_cam_r10f_writer.v,tb_ddr_wr_arb_peer.v}` | 顶层 TB 的寄存器/TLP 模型可复用 |
| 上游工程 | `upstream/ph1p100-pcie-ep-fpga/{ph1p_pcie_ep_top.al,build.tcl,create_project.tcl,download_sram.tcl,README.md}` | `.al`/tcl 参考；**`download_sram.tcl` 不得执行** |
| 构建入口 | `tools/pcie_integration/{run_sim.ps1,run_td.ps1,td/00_all.tcl,gen_manifest.py}` | 单会期 syn+phy+bit；不下载、不写 Flash |

## 5. b18 / b20 只读资产（复制到本 run 后改路径；不原地改）

| 项 | 路径 | 用途 |
|---|---|---|
| b18 板级工程/构建 | `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b18-b17-b/r0/td/{a1_board.al,board_p2.adc,p2_board.sdc,01_build.tcl,02_bitgen.tcl,03_cwc.tcl,src/vendor/**}` | 板级 PLL、DDR shell、vendor ADC/SDC、文件表守卫 |
| b18 可用胶合 | `.../T10.b18-b17-b/r0/changed-src/{a1_raw_crop.v,p2_ddr_bridge.v,camera_a1_uart_top.v,cam_diag_mailbox.v,p2_a1_board_top.v}` | RAW10 ROI 裁剪、43b CDC 打包（`{abort,last,sof,pix}`）、187.5↔dhi_clk 单拍 256b 桥、诊断邮箱 |
| b18 B 路证据 | b18 报告与 `r0/board/`（B 路真实 1920×1080 A1U1，四 CRC+解压通过） | B 路 ROI/Bayer/相机配置的已证配置参照（**不是**本 run 候选） |
| b20 时序/位流 | `.../T10.b20-a-timing/r0/td/{a1_board.bit,a1_board.cwc,routed_gate_b20.json,routed_qor.rpt,routed_netlist.v}` | routed 0 违例 / SWNS +0.012 / 位流存在；**board=blocked（0 下载）** |
| b20 交接 | `.../T10.b20-a-timing/{handoff.md,final-summary.md}`、`r0/result-r0.md`、`CANDIDATE-MANIFEST-b20-a-timing-r0.json` | A 路 pending 事实与陷阱清单（`*.v.stale`、`src/src/**`、`01_build.tcl` 退出码不反映时序） |

**禁止**：修改 b18/b19/b20 目录与计数；继承其 TD/下载额度；把 b18/b20 位流当本交付位流。

## 6. 性能与几何参照（只作预算，不作实测）

- 单路 1080p30：`1920×1080×30 = 62,208,000 px/s` → RAW10 `77,760,000 B/s`。
- 本板相机：4K 源、每路 4 lane×1.5Gbps → 活跃像素瞬时 600 Mpx/s（40bit 组 150 M组/s）；ROI 1920（半幅）→ ≤300 Mpx/s / 75 M组/s。
- P4 核 4 px/clk：187.5MHz=750 Mpx/s，**150MHz=600 Mpx/s**（2× 余量），125MHz=500 Mpx/s。
- 双路离线参照（只作历史）：`workflow/runs/20261025-180900_fpga-dual-offline-closure/final-summary.md` — TB 100MHz 服务 48.46/48.66MB/s、RAW 读 11.04MB/s，均非硬件吞吐。
- DDR3 用户侧 100MHz×32B=3.2GB/s；PCIe Gen2×2 约 800MB/s 量级（未实测）。

## 7. 工具/设备/窗口

| 项 | 值 |
|---|---|
| TD | `D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe`（存在，已核） |
| 盘符 | `T:`→当前 run 的 `td` 目录（**现状 T: 指向 b20 r0/td，必须用 `tools/td/td_env.ps1 -Force` 重指，否则会写入 b20**）；`Y:`→`D:\fpga\ph1p100`（已在）；`P:`/`W:` 供仿真 |
| 路径合同 | `tools/td/PATH_CONTRACT.md`、`tools/td/td_env.ps1`、`tools/td/open_td.ps1` |
| TD 单责任 | 派发时（07:26 后）实测无 `pnmain`/`td_commands_prompt`/`vsim` 进程；并行 run `20261027-055621_fpga-honly-td-and-ah` 可能随时起 TD → 每次构建前重新预检 |
| 板卡 | MLK-F9P-CA05-PH1P100 / PH1P100SBG484 -3；2× IMX415（FEP-VID006-MIPI）；DDR3 x32；PCIe Gen2×2 EP；R14 复位脉冲；FTDI/COM8 历史间歇 |
| 主机/RK | 驱动在队友处（`D:\fpga\repos\ph1p100-pcie-ep-driver` 只读）；**真实 PCIe 传输待联调**，不得用文件回放冒充 |

## 8. 采用版本与未决事项

- 采用：P4 r2（`DFAB7F9D…`）为唯一功能源；EP 板级基座 + b18 胶同为只读复制源；b20 仅作 A 路参考与回退。
- 未决（由本 run 内证据决定，不预设通过）：
  1. P4 核在真实板级约束下的收敛时钟档（默认 150MHz，见设计指南 §5）。
  2. 单 bit 内 A/B 双前端 + 运行时 `a_enable` 是否满足资源/时序（否则 A 路记 `awaiting_hardware`，不擅自加第二次 bitgen）。
  3. 主机/RK 端是否具备真实接收与解码条件（缺则 G3 记 `awaiting_hardware`）。
  4. 板卡窗口/操作员（P2 起需要；缺则 blocked，不空转）。
