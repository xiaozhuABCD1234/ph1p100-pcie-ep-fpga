# input-index.md — 20261018-1347_runA_offline_sim（v2，用户追加输入 02 后更新）

本文件登记本轮需求、输入材料、基线版本与未决事项。原规划者编写；规划侧不访问硬件、不构建、不开发。

## 1. 本轮需求（用户原话与上下文）

- **用户原话 01**（`request.md`）：“OK按建议我确定可以授权，然后开始做，不过我要大概一小时后回来，这一小时你先进行模拟验证部分，后面我会和你一起进行上板以及观察等验证”
- **用户原话 02**（`user-input-02.md`，原样保存）：“将时间窗扩充到3小时，这期间我不在 / 不过其实板子是连接着的，如果有什么不需要我看现象你可以自己读什么情况的可以直接上板验证”
- 上下文（主登记）：
  - 时间窗由约 1 小时扩为 **3 小时**；期间用户不在场。
  - **可机读的板级验证可直接执行**（不需要用户目视/观察）；需要目视的（HDMI 图像、相机取景/摆位、LED 现象等）本轮不做。
  - 仍按 `user-precheck.md` §1.5 默认授权：**仅 SRAM、用当前 bit `e81d353b…2b9a`、允许重启/复位、允许 100 帧 + 10 分钟短稳；不写 Flash、不推送远端**。
  - 本轮=Run A（单 A 真实 RAW→DDR 板级闭环）的“离线模拟 + 可机读板级验证”切片；需要用户在场/目视的部分写入后续主题，不自动续做。

## 2. 输入材料清单（实际采用版本）

| # | 路径 | 用途 | 版本/哈希 |
|---|---|---|---|
| 1 | `workflow/runs/20261018-1347_runA_offline_sim/{request.md, user-input-02.md}` | 本轮用户输入 | — |
| 2 | `workflow/runs/20261018-0001_merge_raw_into_upstream/{user-precheck.md, handoff.md, dev-plan.md}` | 上板清单、冻结 SHAs、后续主题 | — |
| 3 | `workflow/runs/20261018-0001_merge_raw_into_upstream/repo-build/candidate/prj/ph1p_pcie_integration_Runs/{phy_1,best_result}/ph1p_pcie_integration.bit` | **上板候选 bit**（下载前必须复核 SHA256） | SHA256 `e81d353b284cb4e99ec86bcd7d511691cda187254f801c4832916f0000692b9a`，5,224,023 B；manifest `889d24da…93e3` |
| 4 | `upstream/ph1p100-pcie-ep-fpga`（分支 `codex/raw10-rka1`） | 工作树（本轮 P1/KIT 写此；板级包只读） | commit `ab811c8f820c3ae6601507b54ec45a74c6607855`（未推送） |
| 5 | `upstream/ph1p100-pcie-ep-fpga/doc/uart_cmd_file_pcie.txt` | **UART 命令参考**（115200/8-O-1/hex；板卡双串口取高号口；含 APB/CFG/MEMRD/MEMWR 到 EP BAR 空间示例） | 随仓 |
| 6 | `upstream/ph1p100-pcie-ep-fpga/docs/protocol/rka1-r10f-v1/contract/registers.json` | 寄存器真值来源（含 0x118 EXT_MAGIC 等新段） | 冻结镜像 |
| 7 | `upstream/ph1p100-pcie-ep-fpga/{download_sram.tcl, README.md}` | SRAM 下载入口（Linux 参考）与板卡用法 | 随仓 |
| 8 | `workflow/runs/20261017-011744-rk-fpga-align/env/{board-env-checklist.md, environment-handbook.md}` | 板测观测点/寄存器表、工具路径与规则（BW/TD/ModelSim/Python、subst、BOM） | — |
| 9 | `workflow/runs/20261018-1347_runA_offline_sim/board-selfcheck/`（B1 实测，**取代** rk-align 旧登记） | **通道实况（已更正）**：FTDI 复合设备 MI_00=WinUSB(JTAG)、MI_01=VCP=**COM8**；**COM3/COM4 为蓝牙口**；UART 命令通道架构不可用（EP top `uart rx=1'b1`，L155/L757；COM8 两次 0 字节）；B1 已 SRAM 下载成功、器件 ID=PH1P100 | bit SHA `e81d353b…2b9a`；证据 `board-selfcheck/{dev-result.md, channel-notes.md, logs/}` |
| 10 | `upstream/ph1p100-pcie-ep-fpga/sim/`、`tools/pcie_integration/{run_sim.ps1, r10f_strict.py, gen_crc32_flat.py, …}` | 仿真入口与复用工具（判定以 vsim.log；退出码不可信） | 随仓 |
| 11 | `docs/protocol/rka1-r10f-v1/artifacts/{r10f-1080p-synthetic.dma, check-1080p.json}` | 离线 CRC/长度复算素材 | 随 `SHA256SUMS` |
| 12 | 工具路径（`environment-handbook.md` 实查）：TD `D:\anlogic\TD_Release_2026.2\bin\{td_commands_prompt.exe, bw_commands_prompt.exe}`；ModelSim `D:\intelFPGA\18.1\modelsim_ase\win32aloem`；Python `C:\Program Files\Python311\python.exe` 3.11.5 | 构建/板测/仿真/脚本 | — |

## 3. 授权与红线（本轮）

- 已授权：读取项目内材料；本 run 内**可机读的板级验证**（JTAG/BW SRAM 下载当前 bit、UART/寄存器读取、计数与日志记录）；P1/KIT 按 dev-plan 允许路径新增文件并本地 commit（不推送）；run 目录写证据。
- **板卡安全边界**：仅 SRAM，绝不写 Flash；物理断电/上电由用户执行（agent 只用 JTAG 重下同 bit 复位）；不改线缆/跳线/相机摆位/电源；单次下载 ≤5 min；连续采集 ≤10 分钟短稳/本轮；不得以目视现象（LED/HDMI/取景）作判据。
- 未授权（本轮不做）：写 Flash；推送任何远端；修改/推送 RK 原仓；对外发布/发消息；删除既有证据；批量删除；网络使用（除本机既有工具）。
- protected（逐字节不动）：`repo-merge/`、`repo-build/`、`rk-package/`、上一 run 全部、`workflow/tasks.json`、上游仓既有 `rtl/`/`constraints/`/`sim/tb/*`/`docs/protocol/**`、bit `e81d353b…`。

## 4. 基线配对（禁止混拼）

FPGA commit `ab811c8f…855` ↔ bit `e81d353b…2b9a` ↔ RK 合并补丁（driver 基线 `a0215c5a…64a2`）↔ 协议镜像 `docs/protocol/rka1-r10f-v1/`。本轮**不重建 bit**（不集成、不构建）；旧 bit/旧候选只作来源/回退。

## 5. 未决事项（处理方式）

1. **寄存器/内存读取通道（已实测：当前不可用）**：①UART——架构不可用（EP top uart rx 固定 1；COM8 0 字节；`doc/uart_cmd_file_pcie.txt` 命令面对本 bit 不适用）；②BW/JTAG——下载与器件 ID 可用，但用户寄存器读命令 `JTAG_REG_ACCESS`/`JTAG_AXIS_APB_ACCESS` 语义未证实（未盲试）；③RK/PC PCIe 主机——本轮不可用（驱动未编译/无主机）；④CWC 调试核——当前候选无 CWC 产物。
   **处理**：B1 已按 blocked 接受（证据 `board-selfcheck/`）；恢复选项四选一见 `dev-plan.md` §9 与 `question-01.md`（用户回来决策）；KIT 将做 JTAG 语义的**文档级**初核（不触硬件）。
2. **相机是否已接（单 A）**：读通道缺失后**不能机读判定**，改为用户现场确认（question-01）。
3. **checker 集成/新候选重建**：本轮不做（保持当前 bit）；列入后续主题。
4. **真实几何/相位回填 + G1/G2 重跑**：需上板读数；属本轮采集后的条件项，以本轮实测为准。
