# 开发计划 — 板级集成（先 B 后 A 单路压缩帧 PCIe 导出）

## 0. 承接与目标

- **承接自 ⚠ INT.P4**：r2 functional+system pass、G2 fail（112 端点 / WNS −0.637ns / TNS −69.776ns）；r3 G2 0 端点 / +0.072ns 但派生变体等价 fail。功能基线 = `INT.P4-r2-manifest.json` `DFAB7F9D…`；**r3 派生变体禁止作功能输入**。
- **本轮 1 个主要可验收目标**：把 P4 r2 功能核接入真实板级工程（相机→DDR→P4→PCIe），产出**整机 bit**（含本顶层真实 STA），完成**先 B 后 A**的真实单路压缩帧 PCIe 完整导出（单帧完整、内容可校验）。长稳/非阻塞优化后置。
- 两级：需求 → 4 个工作包；BATCH_SIZE=1；每包 ≤5 项语义步骤。
- 全局任务归属 `T11`（DDR→压缩→PCIe→RK 集成），本 run 不新造第二全局任务 ID，4 包记为 `T11.BRD.P1…P4`。

## 1. 技术起点与禁止（冻结）

| 项 | 值 |
|---|---|
| 功能核 | `fpga/csi2/src/integrated_delivery/**` 的 **r2 候选**（只读，端口/单位/语义不变） |
| 板级基座 | `fpga/csi2/pcie_integration/**`（只读复制）+ b18 胶合只读复制 + b20 仅作 A 路参考/回退 |
| 顺序 | **先 B 后 A**；单路；单帧优先，再 2–3 帧短序列验证槽释放 |
| 禁止 | r3 派生文件入编译；r2 功能证据 + r3 时序数字拼 PASS；b20 `a1_board.bit` 当本交付 bit；P4 综合数字当板级时序；文件回放/仿真当真实 PCIe 传输；未出 bit/未上板写通过 |
| 相机帧率 | 1080p30 只是性能目标（相机 MCLK 12.5MHz 时 4K≈7.85fps）；本轮不改 MCLK，未达只记差距 |

## 2. 工作包总表

| task_id | 主要可观察结果 | 实际工作树 / 允许写 | 依赖 | functional | engineering | system | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| `T11.BRD.P1` | 板级集成工程 + 真实顶层 STA + 整机 bit/CWC（B 优先配置，A 路径同 bit 门控） | `OUTPUT_DIR/T11.BRD.P1/**`；`fpga/csi2/src/board_integration/**`；`tools/board_integration/**` | 无（读 r2/参考/b18/b20） | G1 顶层缩尺仿真（相机+DDR+TLP 模型，正/负对照） | G2' 真实顶层 STA/CDC/资源；G5 构建入口/引脚/哈希 | not_run（本包不下载） | G0,G1,G2',G5 | **ready** | 派新开发 |
| `T11.BRD.P2` | B 路真实相机单帧压缩经真实 PCIe 完整导出 + 主机解码校验 | `OUTPUT_DIR/T11.BRD.P2/**`（只写证据）；不改 P1 源（需改则回 P1 修复轮） | P1 | 解码/CRC/zlib/逐字节 ROI 比对 | 位流/候选绑定、下载日志 | 真实硬件单帧导出 + 身份/状态回读 + 2–3 帧槽释放 | G3,G2(bit),G5 | blocked（依赖 P1） | 待 P1 |
| `T11.BRD.P3` | A 路接入并完成同一导出（同一 bit、同一次下载） | `OUTPUT_DIR/T11.BRD.P3/**` | P1（P2 提供主机流程） | 解码判据同 P2 | STA 覆盖 A 路径（P1 已含） | 真实 A 单帧导出；无像素则 `blocked_A_no_pixels` | G3(A),G2 | blocked（依赖 P1/P2） | 待 P2 |
| `T11.BRD.P4` | 同候选交付冻结 + 独立综合测试 | `OUTPUT_DIR/T11.BRD.P4/**`、`test-reports/**` | P2（P3 可选） | 复核 | 复核 | 复核 | G5；G3 引用；G4 not_run | blocked（依赖 P2） | 待 P2 |

---

## 3. T11.BRD.P1 — 板级整机（ready）

**产物**：`brd_integrated_top.v`、板级 `.al`/tcl/约束、`manifest-brd-p1-r0.json`、`result-r0.md`、位流/CWC（条件满足时）、真实顶层 STA 报告、G1 仿真日志。

| # | 语义步骤 | 完成判据 |
|---|---|---|
| S1 | 复制只读基座到本 run 自有目录并重写全部绝对路径：参考 PCIe EP 工程（RTL/约束/al_ip/仿真 TB 模型）、b18 的 `a1_raw_crop`/`p2_ddr_bridge`/`camera_a1_uart_top` 胶合模式/`cam_diag_mailbox`、b20 的板级 PLL/DDR shell/vendor ADC+SDC；P4 r2 以只读路径进 filelist。清点 `*.v.stale`、`src/src/**`、`peer-ref-2a4b253/**` 重复模块守卫。 | 打印并保存实际 filelist；重复模块检查 0 命中；缺失文件 0；`T:` 已用 `td_env.ps1 -Force` 指向本 run |
| S2 | **由参考顶层复制改写** `brd_integrated_top`（不是从零重写）：双 CSI 前端保留（常开）→ 每路 `a1_raw_crop`(1920×1080, X0=960, Y0=540, SKIP_ROWS=37) → 43b CDC 组包 + `capture_async_fifo` → P4 r2 核（W/H/SLOT_WORDS=1920/1080/81085）→ `p2_ddr_bridge` → DDR3 写通道；`ddr_frame_pusher` 读通道 + 新增 `brd_ddr_rd_arb`（**按 AR 事务/burst 粒度公平轮转，不得按整帧独占**）；P4 `desc_*`→描述符邮箱→pusher；pusher 状态→`brd_pcie_track`→P4 `pcie_*`；BAR 配置→`brd_cfg_shadow`；P4 状态→`0x130..0x13C`。A 路由 `a_enable`(CTRL[9]，默认 0) 门控。**删除**原 `cam_r10f_writer`/`cam_ddr_writer`/`ddr_wr_arb`/`img_frame_src` 例化（`img_frame_src` 只产生 ERAM 测试帧，板上不用；其 BAR 寄存器在 `ep_bar_win`，保持读回语义不变）。 | 端口集与指南 §2 一致；`a_enable=0` 时 A 路不产生描述符；B 路每帧 518,400 拍 + 1 次 EOF；无未驱动输入 |
| S3 | 冻结时钟/复位/CDC 与约束：新 PLL `clk_core=150.000MHz`；C1–C7 七项 CDC 逐项落地并命名；`.adc` 合成（去重 R14；未用引脚逐条列明）；`.sdc` 含 `clk_core`、生成时钟、异步组、格雷 `set_path_skew`；禁止内部 false_path/multicycle。 | CDC 清单与 RTL 实例名一一对应；`report` 未约束 IO=0 或逐条列明；SDC 差异报告（相对参考）逐行可解释 |
| S4 | G1 顶层缩尺仿真（参数化几何，如 64×48，同一 RTL 通路）：相机模型（含 embedded 小帧/坏帧）+ DDR AXI 从模型（≥2 槽）+ TLP 主机模型（重组 MWr + doorbell）+ BAR 寄存器模型。正例：单帧完整、A1U1 逐字节等于参考模型；负例：缺 EOF → 不 arm 不导出；错误 ACK → 不释放；pusher 突发与 P4 排空 AR 交替 → 无串包/无死锁。 | 0 mismatch、0 X、无死锁；每负例被正确拒绝；读仲裁覆盖"突发中不换手"与"迟到拍计数" |
| S5 | 构建与签核：`synth#1`(150MHz) → 按指南 §5 规则决定 `route` → 0 违例且 `WNS ≥ +0.003` 才 `bitgen#1 + CWC#1`；出 bit 后算 SHA256 入 manifest；不出 bit 则保存 routed/synth DB、最差路径与结论。 | 报告含总/违例端点、WNS/TNS/hold、未约束 IO、资源、时钟交互、未驱动输入；bit/CWC 哈希；或明确的"不出 bit + 原因 + 证据路径" |

**functional**：S4 全部；`cfg_mode=0`、`a_enable=0`、B 优先；A1U1 头/CRC/长度语义与 INT.P4-protocol §4 一致。
**engineering**：G2'（真实顶层 STA/CDC/资源/未约束 IO）、G5（构建入口、引脚表、位流哈希可复现）。
**system**：本包 `not_run`（不下载、不写 Flash）；理由：P1 只交付可构建候选，板上行为归 P2/P3。
**停止/回退**：TD 被他人占用→`blocked`（不共享、不杀进程）；150/125 均 `< +0.127` → 停止不布线、返回规划；`route` 后仍违例 → 不出 bit、保留 DB；同一错误修复 2 次仍复现→`blocked`。禁止改 P4 源码、禁止加 false_path/multicycle、禁止二次 bitgen。

---

## 4. T11.BRD.P2 — B 路真实单帧导出（blocked，依赖 P1）

| # | 语义步骤 | 完成判据 |
|---|---|---|
| S1 | 硬件窗口预检：操作员在场、JTAG/下载线、R14 复位流程、FTDI/COM8（若用）、无 Flash 操作、JTAG/下载无他人会话；冻结 bit/CWC 哈希与下载脚本。 | 预检记录（时间/操作员/工具）；缺任一 → `blocked`（0 下载） |
| S2 | **1 次** SRAM 下载；回读身份/版本/心跳/状态（`0x114`、`0x130..0x13C`、相机诊断）确认 bit 与 manifest 一致。 | 下载日志 + 寄存器 dump；bit SHA 与 manifest 相同；`link_up` 状态明确 |
| S3 | B 路配置（`CTRL` ddr_en/push_en、`0xB0..0xBC` 目标/门铃、`0x100/0x104/0x108`），触发 B 单帧：相机→ROI→P4 压缩→DDR 槽→pusher 4KB 读→MWr+doorbell。 | `desc_arm`/槽 READY/`st_done`/`0xC0` 递增可核；无 abort 粘滞 |
| S4 | 主机/RK 解码：A1U1 header/stream CRC + zlib inflate + 与相机 ROI 源像素逐字节比对；记录 `frame_bytes`/`stream_len`/帧时/错误码。 | 头 CRC、stream CRC、raw CRC 全过；inflate 字节数 = raw_len；逐字节一致；doorbell 收到 |
| S5 | 2–3 帧短序列（同一次下载）验证全字段 release 与槽复用；冻结证据（位流/下载/导出文件/解码日志/寄存器 dump）入 manifest，并列出**未证明项**（吞吐/长稳/A/RK 联调）。 | 每帧都被 ACK 释放，无槽卡死；证据哈希齐全；未证明项逐条写明 |

**functional**：S4/S5；**engineering**：bit↔manifest 绑定、下载日志、候选不漂移；**system**：G3 单帧完整导出 + 独立解码（测试者用自己的解码路径）。
**停止/回退**：无主机/RK → `awaiting_hardware`（不得用文件回放冒充）；下载失败 → 记录，不自动重试（额度 1 已用）；无像素/坏帧 → 保留证据回规划；禁止第二次 bitgen/下载。

## 5. T11.BRD.P3 — A 路接入与同一导出（blocked，依赖 P1/P2）

| # | 语义步骤 | 完成判据 |
|---|---|---|
| S1 | 同一 bit 内使能 A：`CTRL[9]=1`、`b_priority=1` 保持；核对 A 路身份/诊断（I2C cfg_done、lane、tap、vsync）。 | A 路状态字有明确读数（非全 0 或给出全 0 证据） |
| S2 | 确认 A 路径已被本顶层 STA 覆盖（P1 同一 bit）；若需第二个 bit → 超出 bitgen 额度，`blocked`（不擅自构建）。 | STA 覆盖报告引用；或 blocked 说明 |
| S3 | A 单帧：相机→P4→DDR→PCIe 导出（无第二次下载）。 | 同 P2 S3 的判据（A 身份字段正确） |
| S4 | 主机解码 + 逐字节比对（判据同 P2 S4）。 | 全 CRC/长度/内容通过 |
| S5 | 冻结 A 证据 + A/B 差异（资源/时序/引脚/帧长）；无像素时记 `blocked_A_no_pixels`，**不得**判为 B 的失败或写成 A 通过。 | 证据与诚实标注 |

**门槛**：G3(A)。不要求双路并发/同步指标。**回退**：A 无像素 → 保留证据，A 仍 pending（b20 板级结果继续 pending）。

## 6. T11.BRD.P4 — 同候选交付冻结（blocked，依赖 P2）

| # | 语义步骤 | 完成判据 |
|---|---|---|
| S1 | 冻结 manifest：源/约束/bit/CWC/TD 报告/样例/下载记录，`stopped_modifying=true`、`drift_count=0`。 | 哈希可复算；无 r3 文件；无 b20 位流混入 |
| S2 | 协议/构建入口/最短操作步骤/回退步骤与真实证据一致；清除上一候选残留 PASS 断言。 | 文档-证据逐条对应 |
| S3 | 真实样例 + 解码工具验证；回退件（b18 B、b20 A、P4 r2）与恢复文本。 | 样例可独立解码 |
| S4 | 交独立综合测试（同一测试者覆盖三维）：板级 STA 复核、bit/下载绑定、导出帧独立解码、诚实标注。 | `test-reports/T11.BRD.P4-r0-integrated.md` 唯一判定 |
| S5 | 收尾汇总/交接；RK 联调状态、吞吐/长稳差距如实列出。 | `handoff.md`/`final-summary.md`/`user-summary.md` |

---

## 7. 预算（本 run 独立冻结，不继承任何旧 run）

| 项 | 值 | 理由 |
|---|---|---|
| 角色工具调用 | 每角色 **150** 次/次派发 | 用户 5 倍授权（`request.md`） |
| 规划 / 开发 / 综合测试时长 | 75 / 225 / 225 分钟 | 5×15 / 5×45 / 5×45 |
| 单问题搜索/读取 | ≤15 轮 | 5×3 |
| 同失败命令 | 首次 + 最多 9 次"有新证据"重试 | 5 倍 |
| 无进展循环 | 连续 10 次即停 | 5 倍 |
| **TD 综合 synth** | **≤3**（P1 专用） | r2 已知 187.5 不收敛；150/125 两级 + 1 次补救 |
| **route** | **≤2**（P1 专用） | 每轮须源集不同且仿真先过 |
| **bitgen / CWC** | **1 / 1** | 只允许一个整机候选 |
| **下载** | **1**（P2；P3 复用同一次上电/下载） | 板卡单责任窗口 |
| **Flash** | **0** | 用户冻结 |
| TD 会话 | ≤4 | synth/route/bitgen+CWC/硬件 JTAG |
| 板卡窗口 | 1 次（≤90 分钟，P2+P3 共用） | 推进度优先 |
| 单次命令超时 | 读取/搜索 60s；局部静态/仿真 5min；**顶层 G1 仿真 ≤20min/次、≤6 次**；TD synth/route 各 ≤30min；bitgen+CWC ≤20min；单会期 ≤60min | 板级顶层仿真远重于单元 TB；构建规模大于 b18/b20 |
| 每轮构建前置 | 源集哈希变化 + 仿真先过 + 假设/改动写明 | 防同 netlist 重跑 |

## 8. 写范围与保护

**允许写**：`workflow/runs/20261027-0726_fpga-board-integration/**`；`fpga/csi2/src/board_integration/**`（新建）；`tools/board_integration/**`（新建）。
**只读复用**：`fpga/csi2/src/integrated_delivery/**`、`fpga/csi2/src/img/**`、`fpga/csi2/src/mem/**`、`fpga/csi2/pcie_integration/**`、`upstream/**`、`tools/integrated_delivery/**`、`tools/pcie_integration/**`、`tools/td/**`、b18/b20 全部目录、`parallel/**`。
**禁止写**：b18/b19/b20 目录与计数、其他活动 run（含 `20261027-055621_fpga-honly-td-and-ah`）、`workflow/tasks.json`（仅规划收尾时更新）、`docs/**`、`D:/TD/**`、`D:/fpga/refs/**`、`D:/fpga/archive/**`、`D:/fpga/repos/**`（如需在权威 checkout 工作只能新增独立分支/目录，不 commit/push）、全局配置、Flash/硬件写保护。删除：一次一个明确路径；批量删除交用户。

## 9. 三维检查适用性与不适用理由

- **functional**：适用（协议/帧完整性/等价/解码）。G1 必须用真实顶层 + 真实相机/DDR/TLP 模型，不得以待实现模块充当被测。
- **engineering**：适用（真实顶层 STA、CDC 七项、资源、未约束 IO、构建可复现、候选绑定）。G2' 不得用 P4 的 187.5 数字或 r3 数字代替。
- **system**：P1 不适用（不下载）；P2/P3 适用（真实板卡/下载/导出/解码/恢复）；P4 复核。缺板窗/主机 → `not_run`/`awaiting_hardware`，不伪造。
- **G4**：全 run `not_run`（用户明确后置长稳/吞吐）。
- 纯文档步骤（P4 S2/S5）可用 G5 + 静态复核，但不得替代 RTL/板测 PASS。

## 10. 顺序、依赖与中止

`P1 → P2 → P3 → P4`，BATCH_SIZE=1，逐包派新开发/新综合测试。P1 未出 bit 时 P2/P3/P4 保持 blocked，不空转。三轮实际修复用尽仍 FAIL 保留 ⚠，由本规划在本 run 边界内决定独立后续包（不得用合批/新 run 绕限）。

## 11. 后续主题（≤3，保留原需求路径 `request.md`）

1. 1080p30 真实帧率（相机 MCLK/INCKSEL 24–27MHz 档）与持续吞吐/长稳（G4）。
2. RK/真实 PCIe 驱动联调（主机端接收、doorbell 中断、端到端吞吐）；不得用文件回放冒充。
3. P4 row-window 帧起始/停顿对齐的离线修复 + HE 停顿敏感性（`img/**` 只读，派生 + 等价 TB），为 187.5MHz 收敛提供合法路径。

## 12. 本轮下一步

派发 `T11.BRD.P1`（见 `dispatch.json`）。P1 返回后由本规划读报告更新本计划与 dispatch。
