# input-index.md — 20261020-0209 规划输入与现状核对

日期：2026-10-20｜只读核对；未运行 RTL/TD、未上板、未改源码/任务板。
项目根：`D:\fpga\ph1p100`（2026-10-24 由 `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道` 迁移，旧根已不存在；嵌套副本 `workflow\workflow\` 只读不作主源，详见 `dev-plan.md §57.7`）

## 1. 实际输入（存在性已核）

| # | 路径（相对项目根） | 存在/大小 | 本轮用途 | 读取程度 |
|---:|---|---|---|---|
| 1 | `docs/planning/2026-10-20-fpga-priorities/01_OpenCode启动需求_单A_Aplus闭环.md` | 是 / 9,719 B | 完整需求（三项） | 全文 |
| 2 | `docs/planning/2026-10-20-fpga-priorities/00_进度核对与下一阶段规划.md` | 是 / 19,229 B | 进度口径、A+ 路线、包建议 | 全文 |
| 3 | `workflow/runs/20261019-0207_runA_ddr_readback_loop/next-task-and-progress.md` | 是 / 10,949 B | T10 旧任务定义/预算 | 全文 |
| 4 | `workflow/runs/20261019-0207_runA_ddr_readback_loop/compression-options.md` | 是 / 11,211 B | A+ 方案、组合 A/B/C、用户决策 §10 | §1–§10 关键段 |
| 5 | `workflow/runs/20261019-0207_runA_ddr_readback_loop/final-summary.md` | 是 / 6,869 B | Track A 板证边界 | 仅规划引用（未逐行读） |
| 6 | `workflow/runs/20261019-0212_codex_fpga_closedloop_b2/final-summary.md` | 是 / 6,982 B | B01 生产 PASS / 6/6 预算 | 仅规划引用（未逐行读） |
| 7 | `workflow/runs/20261019-2117_runD_batch2_continue/final-summary.md` | 是 / 16,824 B | 最新状态、T02 partial、板上候选 | §13 与统计/边界 |
| 8 | `workflow/runs/20261019-2117_runD_batch2_continue/test-reports/T02.codex-singleA-board-r0-recovery03-integrated.md` | 是 / 14,172 B | 六窗口字段、几何/相位 unknown | 关键段（§4.4 等） |
| 9 | `workflow/tasks.json` | 是 / 51,859 B | T10 当前 `state=ready`、depends_on T03/T04 | 只读 T10 条目 |
| 10 | `docs/planning/2026-10-17-master-plan/01_后续小任务清单.md` | 是 / 36,096 B | MP20–MP30 旧口径（被新需求覆盖） | 摘录 |
| 11 | `parallel/evidence/frame_contract_20261015/frame_64x48_packed.bin` | 是 / 3,968 B | 既有合成 R10F 合同向量（64×48） | 仅登记 |
| 12 | `parallel/evidence/frame_contract_20261015/frame_8x4_packed.bin` | 是 / 192 B | 既有合成小向量 | 仅登记 |
| 13 | `upstream/ph1p100-pcie-ep-fpga/tools/pcie_integration/r10f_strict.py` | 是 / 19,170 B | CRC/长度/打包口径参考 | 头部 |
| 14 | `upstream/ph1p100-pcie-ep-fpga/tools/pcie_integration/run_sim.ps1` | 是 / 7,088 B | ModelSim 统一入口/中文路径 subst | 头部 |
| 15 | `workflow/runs/20261020-0209_singleA_aplus_closedloop/role-rules.md` | 是 / 4,096 B | 本轮角色/边界 | 全文 |
| 16 | `workflow/runs/20261020-0209_singleA_aplus_closedloop/request.md` | 是 / 2,622 B | 用户原话存档 | 全文 |

**不存在的目录（已核实）**：`upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec`、`sim/tb/codec`、`tools/codec` 均不存在 → 本轮 A+ 为纯新增，无重复开发。

## 2. 集成基线候选

- **源码写树/基线**：`upstream/ph1p100-pcie-ep-fpga`，HEAD `b0282d2`（`T11.runB-debug-rtl: P1-fix …`）。
  - 工作树**不干净**：已修改 `rtl/ep_side/ddr/cam_r10f_writer.v`、`ddr_frame_readback_checker.v`、`img/ep_bar_win.v`、`pcie_ep_engine.v`、`ph1p_pcie_ep_top.v`、`sim/compile_checked.f`、`sim/tb/tb_ep_bar_win_debug.v`、`sim/tb/top_elab_stubs.v`；未跟踪 `constraints/ph1p_pcie_case_ep_closedloop.sdc`、`rtl/ep_side/cam/sync_offline/`、`rtl/ep_side/ddr/closedloop/`、`rtl/ep_side/debug/…closedloop.v`、`rtl/ep_side/img/algo/`、若干 TB。
  - 结论：这些是**既有工作，全部 protected**；本轮只在新目录新增，绝不编辑/覆盖。
- **生产候选（只读引用）**：B01 `bit b68c6e18…f9bf`、699 项 manifest `c7a40897…d757`、生产预算 6/6 已用尽（来自 2117 §13；本轮未复核文件，不重构建）。
- **Track A（只读引用）**：`5B67A8F5…`，真实单A RAW→DDR→板内读回；**不等于**全帧已导出 PC。
- **本轮候选**：`T10.a1-*` 新增 codec 源码集；不声称是生产候选，不拼接旧 PASS。

## 3. 已核实事实（用于冻结）

| 事实 | 值/状态 | 证据 |
|---|---|---|
| 源模式 | IMX415 4K，RAW10，4 像素组 5B | `cam_r10f_writer.v` 头注释；`csi_rx_10bit_unpack.v` |
| RAW10 打包 | `b0..b3=P0..P3[9:2]`，`b4={P3[1:0],P2[1:0],P1[1:0],P0[1:0]}` | 同上 |
| 源计数 | 2192 行 / 4830 B 每行；`source_geometry=0x089012DE` | 2117 T02 recovery03 §4.4；cwc1/cwc3 |
| ROI 参数 | `W=1920,H=1080,X0=960,Y0=540,SKIP_ROWS=37` | `ph1p_pcie_ep_top.v` 103–117（标注“未板证”） |
| ROI 物理含义 | X/Y/SKIP 无直接探针；2192 与 2160+37=2197 差 5 行未解释 | 2117 T02 §4.4；标 `conflict` |
| 物理 Bayer 相位 | **unknown**；`PHASE=3` 仅为寄存器/占位，无直接证据 | 2117 T02 |
| 真实 RAW 导出 | `raw_export=false`、`csv_export=false`；只有调试 GUI 的 6 张 PNG 转录 | T02 sample-record |
| T10 任务状态 | `ready`，depends_on T03/T04，无新 A+ 编码器成果 | `workflow/tasks.json` |
| 三算法/读回 | B01 r0 PASS（699 项、6/6）；本轮不重写 | 0212/2117 |
| T08 | 同步离线原型 PASS；未接活 top/真实双路 | 2117 |
| 板上最后记录 | T02 `B68C6E18…` SRAM（易失）；0207 位流已被覆盖 | 2117 §13 |

**推论边界**：本轮所有压缩/还原结论只用**合成向量 + 声明相位**；不得把 `089012DE` 或 ROI 默认值写成“已实测物理参数”。

## 4. 工具与环境（已核实）

| 工具 | 路径/版本 | 状态 |
|---|---|---|
| ModelSim ASE | `D:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe` | 存在（角色规则已核）；`run_sim.ps1` 需 `MSIM_BIN` |
| Python | `C:\Program Files\Python311\python.exe`，3.11.5 | 可用 |
| zlib | 1.2.13 | 可用（独立标准解码对照） |
| Verilator | `D:\MSYS2\mingw64\bin\verilator` | 存在（角色规则已核） |
| TD | `D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe` | 已找到；器件 `PH1P100SBG484 -3` |
| iverilog | — | 不可用；不作门槛 |

## 5. 只读证据与保护

- 0207/0212/2117 的 run 目录、bit/CWC/BID、manifest、测试报告：**只读**；不续派旧测试者、不补旧截图/CSV。
- `workflow/tasks.json`：规划只读；本轮不写状态；父硬件任务不因离线包 PASS 置 done。
- `docs/protocol/**`、`R10F` 合同、生产 `.al`/`build.tcl`/SDC：只读；不分配生产枚举。
- 板卡/相机/PCIe/RK/Flash：本轮不触达。

## 6. 缺失/阻塞输入（不虚构）

| 缺失项 | 影响 | 状态/恢复条件 |
|---|---|---|
| 真实 RAW 帧或片段 | 真实压缩比、真实 Bayer 结论、需求二/三 | `blocked_awaiting_hardware`；需可重复非 PCIe 导出 + 板窗 + 用户 |
| 物理 ROI X/Y/SKIP 与相位直接证据 | 真实图像合法性 | `unknown`；新功能探针或现场观测；不得猜填 |
| 非 PCIe 大块导出通道 | 整帧到 PC | 未确认；P4 只做离线契约/宿主校验器，不声称可用 |
| 板窗/相机/供电连续性 | G3/需求三 | 用户到场后另行授权；本轮零下载 |
| T03 生产压缩枚举/容器 | 生产集成 | 未签收；本轮 test-only 头，不占枚举 |
