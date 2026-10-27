# 后续 run 请求与边界 — 板级集成（先 B 后 A 单路压缩帧 PCIe 导出）

> 本文件由本 run 原规划在 INT.P4 收尾后准备，**不是**本 run 的第 5 个包，也不在本 run 派发。板级集成是同一工作线的**新 run**（新主目标、独立包数/额度/窗口），需用户显式调用 fpga-orchestrator 启动。

## 0. 用户原话（原样，2026-10-27）

> “当前 P4 完成并验收后，沿同一工作线继续板级集成。复用已通 A/B 工程，将 P4 接入真实相机、DDR 和 PCIe，补齐板级顶层、时钟复位及必要跨时钟连接、引脚约束和构建入口，完成整机 bit。下一目标是先 B 后 A 的真实单路压缩帧 PCIe 完整导出。以推进度为先，长稳和非阻塞优化后置。”

## 1. 启动前提的诚实处理（必须记录）

用户原话的条件是“P4 完成并验收后”，而 **P4 实际为 ⚠ 未通过**（无同一候选三项同过，无 route/bit）。规划选择 **(a) 在 ⚠ 下继续板级集成新 run**，理由：

1. 用户明确“以推进度为先”，期限 2026-10-27（当前已过夜，今日为最后窗口）。
2. 板级线交付的是**带真实时钟/引脚/CDC 的独立候选**，本来就必须用自己的真实顶层重新计时与签核；P4 的 G2 失败既不会被新顶层自动继承为通过，也不会因等待而消失。
3. 继续推进可以把“时序问题”和“板级集成问题”放在同一真实约束下解决，比先离线返工更快得到可演示结果。

代价与硬约束（继承本 run `dev-plan.md` §3.8(3)）：

- (a) 新 run 的计划/交接**首段**必须写“承接自 ⚠ INT.P4（G2 fail：112 端点、WNS −0.637ns；未做 route/bit）”，并把 `algo_rowwin3` 行缓冲读路径列为**已知带出风险**；
- (b) 板级 bit 必须有**自己的真实顶层 STA**（真实时钟、IO 约束），**不得**用 P4 综合数字代表板级时序，不得声称“P4 通过”或“整机时序签核”；
- (c) 若板级仍违例而为 bring-up 出 bit/下载，必须标注“**带已知时序违例的 bring-up bit**”，且需用户硬件窗口与独立冻结额度，不得写成性能/可靠性达标；
- (d) P4 的仿真证据只作“冻结 manifest 上的仿真功能通过”，不等于板上验证；
- (e) 板级 TD/板卡/下载/Flash 额度与 P4 **分开冻结**，不继承 P4 的已用或剩余计数。

## 2. 当前事实（新 run 规划可引用的已核证据）

| 项 | 事实 | 路径/哈希 |
|---|---|---|
| 功能基线 | P4 r2：functional=pass、system=pass、G2 fail（112 端点/16770、WNS −0.637ns、TNS −69.776ns） | `INT.P4-r2-manifest.json` `DFAB7F9D7FF7B7F8FB1D9B4401844F3D76102064C99FC4338192FB8A0C59B32E` |
| 时序参考（禁止作功能输入） | P4 r3：0 端点/17220、WNS +0.072ns、TNS 0、hold 0；但派生变体等价 fail（y8 383/317/3、gau 1368/1154/10、he 1116/980/44；bayer +STALL 769 vs 783） | `INT.P4-r3-manifest.json` `43EBFF3D110234A225DD2A449804BC863F47EC5D7FAE89966C970B5EA9526F1` |
| B 路基线 | b18：B 路真实 1920×1080 A1U1 帧，四 CRC + 解压通过；板级工程 `r0/td/a1_board.al` + vendor ADC/SDC + camera uisrc pin/time | `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b18-b17-b/`（只读） |
| A 路基线 | b20 r0：routed 0 违例、SWNS +0.012ns 薄裕量、`a1_board.bit`+`.cwc` 存在、board=blocked（0 下载）；有 `board_p2.adc`/`p2_board.sdc`/`01_build.tcl`/`02_bitgen.tcl`/`03_cwc.tcl` | `.../T10.b20-a-timing/r0/td/`（只读，计数不动） |
| PCIe EP 板级 | `upstream/ph1p100-pcie-ep-fpga/ph1p_pcie_ep_top.al`（EP 顶层 .al）+ `fpga/csi2/pcie_integration/constraints/ph1p_pcie_case_ep.{adc,sdc}`；参考副本在 `fpga/csi2/pcie_integration/peer-ref-2a4b253/` | 只读 |
| P1/P2/P3 | 各自冻结 manifest（`D6C524F6…`/`B5073D55…`/`9D0DEA08…`）；A1U1 样例 `79e35f28…/1357408f…/76d88910…` | 本 run 目录 |
| RK | 驱动在队友处；真实 PCIe 传输待联调 | `D:/fpga/repos/ph1p100-pcie-ep-driver`（只读） |
| 现场 | 规划收尾时（06:52）无 `pnmain`/`td_commands_prompt`；有 3 个他人 `vsim` 进程（PID 66176/49848/54572，06:45 启动；早期 46792 已退出），**不得杀**；另一活动 run `20261027-055621_fpga-honly-td-and-ah` 正并行推进 H-only TD/STA，**TD 不得共享**；FTDI/COM8 历史间歇 | — |

## 3. 新 run 定义（建议）

- **建议 run_id**：`20261027-0700_fpga-board-integration`（若实际启动时刻不同，以主按启动时间创建的实际目录为准，规划在 request.md 登记）。
- **BATCH_SIZE**：1（用户未指定其他值）。
- **主要可验收目标（1 个）**：把功能正确的 P4 r2 集成交付接入真实板级工程，产出整机 bit，并完成**先 B 后 A** 的真实单路压缩帧 PCIe 完整导出（单帧完整、内容可校验）；长稳/吞吐/非阻塞优化后置。
- **正式工作包 4 个、两级、每包 ≤5 项语义步骤**：

### BRD.P1 板级顶层、时钟复位/CDC、引脚约束、构建入口与整机 bit（B 优先配置）

1. 把 b18（B）、b20（A）、`pcie_integration`（EP）参考工程**复制**到本 run 自有 TD 目录并重写全部绝对路径；保留重复模块 filelist 守卫，清点 `*.v.stale`/`src/src/**` 陷阱；参考工程原地只读。
2. 新建板级顶层：相机前端（B 优先，A 以选择/门控存在）→ **P4 r2 集成核（只读，端口/单位不变）** → DDR → PCIe EP 后端；不做功能改动，只做互联与适配。
3. 冻结时钟/复位/CDC 计划：列全所有时钟（相机字节/像素、DDR MC、PCIe refclk、核心时钟档位）、复位源/极性/释放顺序、每一处跨域连接与同步器/异步 FIFO 清单；不允许未声明的跨域组合路径。
4. 真实引脚约束（`.adc`）+ SDC：引脚表、IO 标准、时钟定义；内部路径不得 false_path/multicycle；IP 自带约束原样继承并单列；未用引脚逐个列明。
5. 构建入口（`.al`/TCL/一键脚本）+ 综合/布线/bitgen（B 配置）→ bit/CWC + **板级真实 STA**；bit 哈希入 manifest。route/bitgen 条件与额度见 §6。

**门槛**：G0 接口/时钟/CDC 冻结且可核对；G1 板级顶层端口级仿真（相机模型+DDR 模型+host/TLP 模型，不得以待实现模块充当被测）；G2' 板级 0 违例、WNS/TNS ≥ 0、hold ≥ 0、未约束 IO=0（或逐个列明未用）、资源在器件内、无未驱动 DUT 输入、CDC 清单齐全；G5' 构建入口/引脚表/位流哈希可复现。

### BRD.P2 B 路真实相机→DDR→P4 压缩→PCIe 完整导出

1. 硬件窗口准备：操作员/设备就绪（JTAG 下载顺序、R14 脉冲、COM8/FTDI 预检）；缺窗口→`awaiting_hardware`，不空转。
2. **1 次下载** B 配置 bit；身份/心跳/版本寄存器回读，确认 bit 与 manifest 一致。
3. 触发真实 B 相机 1080p 抓拍，P4 压缩一帧，经 PCIe 完整导出到主机/RK。
4. 主机端解码校验：A1U1 解码 + header/stream CRC + zlib 解压；与相机源像素/软件参考对照；记录导出字节数、帧时、错误计数。
5. 冻结板级证据（bit 哈希、下载日志、导出文件哈希、主机解码日志）到本 run manifest。

**门槛**：G3 单帧完整导出且内容校验通过；G1 主机侧独立校验（不得用开发自报）。若 RK 主机端不可用，只能记 FPGA 侧导出证据并标 `awaiting_hardware`/待联调，**不得**声称真实 PCIe 传输通过。

### BRD.P3 A 路接入与同一导出

1. A 路前端接入（复用 b20 r0 只读候选与其 routed/引脚资产），解除 `a_enable` 门控；A/B 选择与身份寄存器生效。
2. A 配置构建（或同一 bit 的 A 模式）→ 板级 STA 必须覆盖 A 路径；条件同 BRD.P1。
3. **1 次下载** A 配置；A 相机 1080p 单帧压缩并经 PCIe 完整导出。
4. 主机解码 + 内容校验（判据同 BRD.P2）；记录 A 路真实 b20 板级有效结果，关闭 P3 的 pending 事项。
5. 证据冻结与差异记录（A 路资源/时序/引脚 vs B）。

**门槛**：G3 单帧完整导出 + 内容校验；G2' 覆盖 A 路径；不要求双路并发、不要求同步指标。

### BRD.P4 同候选交付冻结

1. 冻结 manifest（源、约束、bit/CWC 哈希、TD 报告、样例、下载记录），`stopped_modifying=true`、`drift_count=0`。
2. 协议/构建入口/最短操作步骤/回退步骤与真实证据一致（不得残留上一候选的 PASS 断言）。
3. 真实样例 + 解码工具验证；回退件（b18 B、b20 A、P4 r2）与恢复文本。
4. 交独立综合测试（同一测试者覆盖 functional/engineering/system）：板级 STA 复核、bit/下载绑定、导出帧独立校验、诚实标注。
5. 收尾汇总/交接；RK 联调状态、长稳/吞吐差距如实列出。

**门槛**：G5 全部一致；G3 已由 P2/P3 提供；G4 仍 `not_run`（用户后置）。

## 4. 技术起点（冻结）

- **功能基线 = P4 r2 候选**（`DFAB7F9D…`）：唯一 functional+system 同过的候选。
- **禁止**把 r3 的 `algo_rowwin3_p4.v` / `gray8_gaussian3x3_stream_p4.v` 作为板级功能源；r3 只能作为“该网表在 187.5MHz 内部路径收敛”的时序参考。
- **禁止**用 r3 的 G2 数字配 r2 的功能证据；禁止用 b20 `a1_board.bit` 冒充本次整机 bit。
- 时序解决顺序（按优先级，任一步骤都必须在真实约束下有证据）：
  1. 板级真实约束 STA 定位（真实时钟/引脚/CDC 下重算，不复用 P4 数字）；
  2. 在 `board_integration/` 下做**保持算法等价**的合法 retime/流水（派生文件；必须用现有等价 TB 证明 token 等价，含 always-ready 与停顿；`fpga/csi2/src/integrated_delivery/**` 保持只读）；
  3. 仍不收敛时，允许把核心时钟降到仍满足**单路 77.76MB/s 计算预算**（1920×1080×30×RAW10/8）的有限档位，记录吞吐差距，**不得**写成达标；
  4. 退路：标注“带已知时序违例的 bring-up bit”（需用户硬件窗口与独立额度）。
- B 先 A 后；单路压缩帧**完整**导出（不是双路并发、不是长稳、不是吞吐达标）；整机 bit 必须来自真实顶层 + 真实约束。
- 长稳/非阻塞告警整理/吞吐优化后置，只记差距。

## 5. 写入与保护范围（建议冻结）

- **允许写**：新 run 目录 `workflow/runs/<new_run>/**`；`fpga/csi2/src/board_integration/**`（新建板级顶层/胶合/派生 retime）；`tools/board_integration/**`（构建入口/脚本/TB）。
- **只读复用**：`fpga/csi2/src/integrated_delivery/**`（P4 r2/r3 候选）、`fpga/csi2/src/img/**`、`fpga/csi2/pcie_integration/**`、`upstream/**`、b18/b20 工程（复制到新 run 后改路径，不原地改）、`tools/td/**`、`tools/integrated_delivery/**`。
- **禁止写**：b18/b19/b20 目录与计数、其他活动 run、`workflow/tasks.json`、`docs/**`、`parallel/**`、`D:/TD/**`、`D:/fpga/refs/**`、`D:/fpga/archive/**`、`D:/fpga/repos/**`、权威两仓（不 commit/push/fork）、全局配置、Flash/硬件写保护。
- 删除：只允许一次删一个明确路径；批量删除由用户手动处理。

## 6. 预算（新 run 独立冻结，不继承本 run）

- **5 倍额度不自动继承**：用户 2026-10-26 原话“同时我给这次任务开正常防死循环的5倍额度”已在 `request.md` 机械登记为**仅限当前任务**。新 run 若沿用，需用户在启动文本中明确写出（例如“沿用正常防死循环的5倍额度”）；否则按默认有界预算执行（30 次工具调用/派发、规划 15 分钟、开发/综合测试各 45 分钟、单问题 3 轮读取、同失败命令首次+1 次）。
- 若用户重新授权 5 倍：150 次调用、规划 75 分钟、开发/测试 225 分钟、单问题 15 轮、同失败命令首次+9 次、无进展 10 循环。
- **TD/构建额度（规划冻结，独立计数）**：整机全流程构建（synth+route+bitgen）≤3 轮（B、A、1 次修复余量）；synth ≤5；route ≤3；bitgen ≤3；CWC ≤3；**下载 ≤3**（B 1 + A 1 + 1 余量）；**Flash=0**。每轮构建必须：源集哈希与上轮不同、该源集等价/回归仿真先通过、写明假设与改动；不得用属性实验或同 netlist 重跑充数。
- 板级 STA 门槛：WNS ≥ +0.05ns 为正常；+0.003…<+0.05ns 为**薄裕量候选**（可出 bit，必须标注）；< 0 或仍有违例端点 → 不出 bit，除非用户明确同意“带已知时序违例的 bring-up bit”并单列风险。
- 单次命令超时：读取/搜索 60s、局部静态/仿真 5min、FPGA 构建 30min；到点安全终止本流程进程并保留日志。

## 7. 启动条件（硬）

1. 用户显式调用 `/fpga-orchestrator 执行：<本文 §0 原话 + §8 启动文本>`；新 run 建独立目录、独立额度。
2. **TD/板卡单责任流程**：启动前确认无其他 `pnmain`/TD 活动；发现他人 TD 活动→`blocked`，不共享。当前有并行活动 run `20261027-055621_fpga-honly-td-and-ah`（H-only TD/STA）与 3 个他人 `vsim` 进程（PID 66176/49848/54572），均不得杀、不得共享其 TD 工程/设备；若它正在 TD，本 run 必须等窗口或返回 `blocked`。
3. 不修改 b18/b19/b20 工程、目录与计数；复制后重写路径，注意绝对路径、`*.v.stale`、`src/src/**` 与重复模块守卫。
4. 板卡窗口需用户/操作员（R14 脉冲、COM8、FTDI 预检）；缺窗口时离线包（P1/P4 的离线部分）继续，板级实跑标 `awaiting_hardware`，不空转、不伪造。
5. 主机端：RK 在队友处；缺主机/RK 时只做 FPGA 侧导出证据并标待联调，不用文件回放冒充。
6. 不写 Flash；下载只能在冻结额度与硬件窗口/操作员流程下进行（不自动、不并发），且每次下载前后冻结 bit 哈希与下载日志；不 commit/push/fork 两仓；如需落仓由用户另行显式授权并核对 `REPOSITORIES.md`。
7. 首段诚实标注（§1 的 a–e）必须出现在新 run 的 request/dev-plan/handoff。

## 8. 给用户的启动文本

```
/fpga-orchestrator 执行：当前 P4 完成并验收后，沿同一工作线继续板级集成。复用已通 A/B 工程，将 P4 接入真实相机、DDR 和 PCIe，补齐板级顶层、时钟复位及必要跨时钟连接、引脚约束和构建入口，完成整机 bit。下一目标是先 B 后 A 的真实单路压缩帧 PCIe 完整导出。以推进度为先，长稳和非阻塞优化后置。
承接事实：P4 为 ⚠ 未通过（r2 functional+system pass 但 G2 fail 112 端点/WNS −0.637ns；r3 G2 0 端点/WNS +0.072ns 但派生变体等价 fail）。功能基线必须用 r2 候选（manifest DFAB7F9D…），禁止用 r3 派生变体作功能输入；整机 bit 必须有自己的真实顶层 STA；未出 bit/未上板的事实不得改写为通过。
<若沿用5倍额度，请写：沿用正常防死循环的5倍额度。>
Flash=0；不动 b18/b19/b20 与其他活动 run；TD/板卡/下载额度独立冻结。
需求与边界全文：D:/fpga/ph1p100/workflow/runs/20261026-2138_fpga-integrated-delivery/follow-on-run-request.md
```

## 9. 若用户不选择继续（替代路径）

用户可改为先离线修 `algo_rowwin3` 的**帧起始/flush/gap 对齐**（保持 `img/**` 只读、只改派生文件），用测试者控制 TB 作“非延迟伪差”判据，等价通过后再消耗 1 次新综合。该路径**不会**推进板级进度，且今日期限内的可演示结果更少；本规划推荐先走板级线（§1）。
