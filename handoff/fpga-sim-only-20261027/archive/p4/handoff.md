# 交接 — 20261026-2138_fpga-integrated-delivery（2026-10-27 06:58 冻结）

**承接自 ⚠ INT.P4（未通过）**：r2 候选 functional=pass / system=pass 但 G2 fail（**112 违例端点 / WNS −0.637ns / TNS −69.776ns**）；r3 候选 G2 通过（限定：**0 端点 / WNS +0.072ns / TNS 0**）但 functional fail（派生变体破坏 gray/高斯逐像素等价，停顿下 token 数不等）。本 run **未做 route / bitgen / CWC / 下载 / Flash**，无整机 bit，无真实 PCIe 传输，无 A 路板级结果。**不要**把 r2 功能证据与 r3 时序数字拼成 PASS，也不要把 r3 的"0 端点"写成 P4 通过。

## 1. 现在有什么（可用路径）

### 1.1 功能基线（板级集成唯一功能输入）

- 候选目录：`D:/fpga/ph1p100/fpga/csi2/src/integrated_delivery/`（集成顶层 `integrated_delivery_top.v` 及各包源；`work/`、`sim_output.txt`、`transcript` 为已登记遗留，不删）
- 冻结清单：`INT.P4-r2-manifest.json`，SHA256 `DFAB7F9D7FF7B7F8FB1D9B4401844F3D76102064C99FC4338192FB8A0C59B32E`
- 功能证据：`test-reports/INT.P4-r2-integrated.md`（functional pass、system pass；G2 fail）
- 已知风险：`algo_rowwin3` 行缓冲读路径（`u_obuf_gau/count_reg[0] → ra0 → 320 深 LUT RAM 读 mux → u_row/rb0_reg[0].d`，5.906ns；`u_front` 有同构副本）

### 1.2 时序参考（只读，不作功能输入）

- `INT.P4-r3-manifest.json`，SHA256 `43EBFF3D110234A225DD2A449804BC863F47EC5D7FAE89966C970B5EA9526F1`
- `INT.P4/td/r3_run1/**`（`syn_flow.status`：NUM_FEPS 0/17220、WNS 72ps、TNS 0；`syn_gate_area.rpt`：IO 42/286、ERAM+CWC 39/300、reg 6004、slice* 10691/71680、lut 12943、DSP 14；STA 覆盖 95.63%）
- **禁止**直接使用 `algo_rowwin3_p4.v` / `gray8_gaussian3x3_stream_p4.v` 作为板级功能源：r3 实测 y8 383/317/3、gau 1368/1154/10、he 1116/980/44 处数据差异，always-ready 仍 13 处，bayer `+STALL` 769 vs 783。

### 1.3 上游冻结包（只读复用）

- P1：`INT.P1-r1-manifest.json`（`D6C524F6…`）— RAW10 打包、好帧发布/取消、三算法+选路
- P2：`INT.P2-r0-manifest.json`（`B5073D55…`）— A+ 槽→PCIe 发送后端（描述符/长度/尾拍/完成/释放）；RK 真实传输待联调
- P3：`INT.P3-r1-manifest.json`（`9D0DEA08…`）— 双路 A/B 身份与调度；A 路仍门控
- 交付包：`INT.P4-protocol.md`、`INT.P4-build-entry.md`、`INT.P4-shortest-steps.md`、`tools/integrated_delivery/a1u1_decode.py`、`tools/integrated_delivery/evidence/**`

### 1.4 板级可复用工程（全部只读，复制到新 run 后再改路径）

| 来源 | 内容 | 状态 |
|---|---|---|
| `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b18-b17-b/`（`r0/td/`：`a1_board.al`、vendor ADC/SDC、camera uisrc pin/time） | **B 路**真实 1920×1080 A1U1 帧（四 CRC + 解压通过） | 功能基线与回退；不可改 |
| `.../T10.b20-a-timing/r0/td/`（`a1_board.al`、`a1_board.bit`+`.cwc`、`board_p2.adc`、`p2_board.sdc`、`01_build.tcl`、`02_bitgen.tcl`、`03_cwc.tcl`、`routed_*`） | **A 路**板级工程；r0 routed 0 违例、SWNS +0.012ns 薄裕量；bit+CWC 已存在 | board=blocked（0 下载）；目录/计数不可动 |
| `upstream/ph1p100-pcie-ep-fpga/ph1p_pcie_ep_top.al`（EP 顶层）+ `fpga/csi2/pcie_integration/constraints/ph1p_pcie_case_ep.{adc,sdc}`（参考副本 `fpga/csi2/pcie_integration/peer-ref-2a4b253/ph1p_pcie_ep_top.al`） | PCIe EP 顶层与引脚/时序约束 | 只读；不同路由参考实现覆盖生产同名实现 |

板级集成的组成关系（新 run 需自行冻接口）：相机前端（B=b18 / A=b20）+ DDR + **P4 集成核（r2）** + PCIe EP 后端（上表第三行）+ 板级时钟/复位/CDC + 引脚约束 + 构建入口 → 整机 bit。

## 2. 如何复现（离线，不需要板卡）

1. 环境：`D:/intelFPGA/18.1/modelsim_ase`（vsim 10.5b）、Python 3.11.5、Anlogic TD Release_2026.2（仅构建时）。
2. 编译：`test-reports/INT.P4/r3/compile.ps1`（24 核心 + 6 TB；r2 候选对应 `test-reports/INT.P4/r2/` 同名脚本）。
3. 跑集成 TB：`vsim -c -do "run -all; quit -f" tb_integrated_delivery_top +MODE=4|1 +SAMPLE=1 +EXTRA=0|1`。
4. 样例解码/校验：`python tools/integrated_delivery/a1u1_decode.py <sample> 4096`；独立 oracle 在 `test-reports/INT.P4/r3/oracle_sample_r3.py`；负对照用坏 header/坏 payload 副本。
5. 等价检查（若改集成目录内文件）：`tb_img_algo_equiv_p4 +SEEDMODE=0/1/2` 必须 0 差异；`tb_bayer_retime_check +STALL` 必须 token 数相等。**任何"只加固定延迟"的说法都要用该 TB 证明，不得只靠推理。**
6. TD 复核：只读判读 `INT.P4/td/r3_run1/**` 与 `INT.P4/td/syn_r2_run2/**`；端点数取 `flow.status`，不用打印行数。

## 3. 不得声称（硬约束）

- 不得声称 INT.P4 通过、时序已收敛、整机时序签核、上板通过、真实 PCIe/RK 传输通过、A 路上板通过、1080p30 达标、长稳/性能达标。
- 不得用 r3 的 G2 数字配 r2 的功能证据；不得用 b20 的 `a1_board.bit` 冒充本交付 bit；不得用文件回放或接口仿真冒充真实 PCIe 传输。
- 板级 bit 若来自带已知违例的网表，必须标注"**带已知时序违例的 bring-up bit**"，且需用户硬件窗口与独立冻结额度。

## 4. 下一工作线（新 run，需用户显式启动）

- 决策：**在 ⚠ 下继续板级集成**（`decision-matrix.md` D4）；完整请求见 `follow-on-run-request.md`；给用户的启动文本见 `user-question.md`。
- 建议 run_id：`20261027-0700_fpga-board-integration`（实际以主建目录时间戳为准）。
- 技术起点：r2 功能基线 + 板级真实约束 STA；**B 先 A 后**；单路压缩帧完整导出；整机 bit；长稳/非阻塞后置。
- 时序解决顺序（新 run 冻结，按此优先级）：①板级真实约束 STA 定位；②在 `integrated_delivery/` 内做**保持算法等价**的合法 retime/流水（必须用现有等价 TB 证明 token 等价，含 always-ready 与停顿）；③仍不收敛时，允许把核心时钟降到仍满足单路 77.76MB/s 计算预算的有限档位（记录吞吐差距，不得写成达标）；④退路：标注"带已知时序违例的 bring-up bit"。禁止复用 r3 派生变体。
- 新 run **不继承**本 run 的 5 倍额度（用户原话限定"这次任务"）；TD/板卡/下载/Flash 额度独立冻结。

## 5. 保护与回退

- 保护（只读，不得写/删/改计数）：`T10.b18-b17-b/**`、`T10.b19-cam-a/**`、`T10.b20-a-timing/**`、其他活动 run（含 `20261027-055621_fpga-honly-td-and-ah`）、`workflow/tasks.json`、`docs/**`、`upstream/**`、`parallel/**`、`fpga/csi2/src/img/**`、`fpga/csi2/pcie_integration/**`、`tools/td/**`、`tools/pcie_integration/**`、`D:/TD/**`、`D:/fpga/refs/**`、`D:/fpga/archive/**`、`D:/fpga/repos/**`、两仓（不 commit/push/fork）、硬件/Flash。
- 已知现场（06:52 观察）：无 `pnmain`/`td_commands_prompt`；有 **3 个他人 vsim 进程**（PID 66176/49848/54572，06:45 启动；此前 46792 已退出），**不得杀**；另一活动 run `20261027-055621_fpga-honly-td-and-ah` 正在并行推进 H-only TD/STA，**不得与它共享 TD 工程或设备**。FTDI/COM8 历史间歇，不能当稳定板窗。
- 回退：B 路回退件 = b18（真实 1080p A1U1 帧，四 CRC/解压通过）；A 路回退 = b20 r0（routed 0 违例、薄裕量、bit+CWC 在）；集成交付回退 = r2 候选（功能正确、时序不收敛）。
- 删除：只允许一次删一个明确路径的文件；批量删除须用户手动处理。

## 6. 恢复/启动文本

本 run 已收尾（`status=needs_user_input`、`run_state=closed`、`task_ids=[]`）。板级线（新 run）启动文本：

```
/fpga-orchestrator 执行：当前 P4 完成并验收后，沿同一工作线继续板级集成。复用已通 A/B 工程，将 P4 接入真实相机、DDR 和 PCIe，补齐板级顶层、时钟复位及必要跨时钟连接、引脚约束和构建入口，完成整机 bit。下一目标是先 B 后 A 的真实单路压缩帧 PCIe 完整导出。以推进度为先，长稳和非阻塞优化后置。
承接事实：P4 为 ⚠ 未通过（r2 functional+system pass 但 G2 fail 112 端点/WNS −0.637ns；r3 G2 0 端点/WNS +0.072ns 但派生变体等价 fail）。功能基线必须用 r2 候选（manifest DFAB7F9D…），禁止用 r3 派生变体作功能输入；整机 bit 必须有自己的真实顶层 STA；未出 bit/未上板的事实不得改写为通过。本轮额度：<若沿用5倍，请在此写明"沿用正常防死循环的5倍额度">；Flash=0；不动 b18/b19/b20 与其他活动 run。
需求与边界全文：D:/fpga/ph1p100/workflow/runs/20261026-2138_fpga-integrated-delivery/follow-on-run-request.md
```

恢复本 run（只读复核/追责）：`恢复：D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery；本轮目标：<目标>`
