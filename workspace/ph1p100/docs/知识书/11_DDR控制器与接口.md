# 第 11 章 DDR 控制器与接口

> 本章回答：DDR 控制器（DDR MC）到底在做什么？"训练（training）"是在练什么？`ddrmc_x32` 与我们的工程怎么接线？PAXI 与 AXI 的本质差异与迁移面是什么？为什么 IP 生成要"CLI 引导＋一次用户在场 GUI 生成"？"全链同版本纪律"防的是什么？
> 事实标记：【本项目事实】可追溯到项目文件路径；【通用原理】来自公认外部资料；【设计候选】【待验证】【未决】表示尚未实现/未板验/未拍板。速度档位与判决框架见第 10 章；帧槽/队列语义见第 12 章。

## 10 分钟速读卡

- **本质一句话**：DDR 控制器（MC）是内存的"港口调度中心＋军训教官"——它替用户逻辑安排命令顺序（调度）、把读写节拍对齐（训练）、经物理层（PHY）与颗粒打交道；用户逻辑看到的是一个"握手式访问口"，另一端是另一套时钟。
- **为什么重要**：时序余量、可用带宽、初始化能否成功，八成取决于控制器/PHY/IP 生成这三件事，而不是数据率数字本身；接口选型（原生 PAXI vs AXI）决定了后续迁移面。
- **本项目怎么用**：主线用 `ddrmc_x32`（原生 PAXI=1）；1333 候选"只换 IP"（64 文件）完成集成，项目侧 RTL/约束零改动；IP 生成固化为"CLI 引导配方＋一次用户在场 GUI Generate"，工具链走"6.2.3-forward＋6.2.2 只读"。
- **一个记忆锚**：**办公区与码头**——用户逻辑（办公区）不需要认识每一艘船（命令），但必须过一道"闸门"（用户时钟域跨域接口）；码头的排练（训练）在上电时做一次，调度（MC）则一直在做——两者都必须做对。

## 本章要回答的问题

1. DDR 控制器负责哪几件事？调度、训练、PHY 各是什么？
2. 初始化（上电到能用）要走哪些步骤？为什么脱离初始化固件"只抄 wrapper"不行？
3. 原生 PAXI 与 AXI4 的本质差异是什么？迁移到 AXI 要动哪些面？
4. "用户域时钟/跨域"在 DDR 子系统里指什么？为什么要有闸门？
5. 本项目 IP 生成工序为什么是"CLI 引导＋一次 GUI Generate"？headless 为什么不行？
6. "全链同版本纪律"具体在防什么？

## 直觉：港口调度中心与军训教官

【通用原理】DDR 颗粒只认"行/列/命令/时序"这一套低层语言，任何 SoC/FPGA 都不会让用户逻辑直接说这套语言。中间隔着两级专业分工：

- **DDR 控制器（MC）**：决定"哪个请求先走、怎么合并、什么时候刷新、读写怎么切换"——目标是**行命中率与公平性**；同时负责初始化流程（mode register 序列、校准）与训练；
- **PHY（物理层）**：负责电平、延迟、采样点——包括把数据节拍（DQS）与命令对齐的各类训练。

用户逻辑（我们的采集/显示/压缩）只面对 MC 暴露的**用户接口**：给地址、给数据、握手完成。这套接口的时钟（用户域）和颗粒时钟（CK）不是同一个——中间必须过"闸门"（跨域结构）。

## 原理：控制器三大职能与一次访问的生命周期

### 职能一：调度（scheduling）

【通用原理】MC 内部把来自多个用户的请求排队，再做三件事：**重排**（把同一行的请求放一起，提高行命中）、**仲裁**（读/写/刷新抢同一个颗粒总线，谁先谁后）、**时序检查**（每次发命令前核对 tRCD/tRP/tRAS/刷新间隔等是否满足）。所以"平均带宽够"并不自动意味着"实时请求不被饿死"——调度策略与争用才决定最坏延迟。

### 职能二：训练（training）

【通用原理】DQS 与 DQ 之间的相位随工艺/电压/温度/布线漂移，上电时必须"校准采样点"：

- **写均衡（write leveling）**：控制器发 DQS，颗粒回报时钟相位差，控制器调整各字节组的发送时刻；
- **读门/读采样（read gate/DQ training）**：控制器扫描延迟，找到能稳定读回 DQS/DQ 的窗口；
- **ODT/驱动强度校准**：按工作条件选择终端电阻与驱动（ZQ 校准）。

一句话：训练就是"把采样快门对准飞行中的列车"——与第 05 章 delay 训练的直觉同源，只是对象换成了 DQS/DQ。

### 职能三：初始化（上电到能用）

【通用原理】上电后要依次完成：稳定电源/CKE、复位释放、DLL/ODT 就绪、写 MR0–MR3（CL/CWL/BL/ODT 等）、ZQ 校准，然后才能受理用户访问。**在 FPGA 里的实现**常常是：控制器 IP 自带一颗 MCU + 初始化 ROM（或由 APB 配置通路驱动），配套 ROM 与配置端口是**必要依赖**——本项目文档明确："MCU/APB 初始化及校准属于必要依赖，不能仅复制 DDR wrapper"（`../RAW10灰度显示与DDR推进记录_2026-10-10.md` §4）。

### 用户接口：PAXI 与 AXI 的本质差异

【通用原理】用户接口的差异可以用"一句话+一张表"概括：**PAXI 是厂商原生握手口，AXI 是标准总线协议**。

| 维度 | 原生 PAXI（本项目主线） | AXI4（队友后端） |
|---|---|---|
| 通道与语义 | 地址/数据各自握手；一个 256bit 命令；无写响应 B、无 burst LEN 端口（当前包装） | AW/W/B/AR/R 五通道；突发长度、ID、响应齐全 |
| 地址单位 | 本板参考步长 8（每 256bit 字=8 个地址单位） | 字节地址+4KB 边界/突发对齐规则 |
| 迁移面（若主线合流 AXI） | 现状零迁移（既成事实） | **I4**（推帧读源：AXI 4KB 突发 vs PAXI 握手/仲裁）、**C3**（4KB 整数倍对齐/尾突发）、**T5**（双路+25% 余量复核）＋`ddr_frame_store` 等用户侧重做 |

（差异与迁移面依据：`../../workflow/runs/20261017_161109_decisions_compare_freeze/decision-register.md` §1.2；`../DDR1333集成与1333vs1600对比_2026-10-17.md` §8。`ddr_frame_store.v` 注释亦明确"不是标准 AXI master"。）

## 数字：`ddrmc_x32` 与本工程的关键参数

【本项目事实】主线 IP 与工程接线的已核数据（`../../workflow/runs/20261017_153201_T01_ddr1333_integration/dev-plan.md` §1）：

| 项 | 值 | 来源/说明 |
|---|---|---|
| 用户接口（原生） | 27bit 地址、256bit 数据、32bit strobe、读写地址/数据握手 | 本板包装只暴露原生接口 |
| 地址步长 | 8（每 256bit 字） | 连续脉冲的参考步长 |
| 端口集合 | 53 行，新旧 IP **完全一致**（无增删改名） | E1 接口等值断言 |
| IP 闭包 | 61 文件（1333 新 IP 与 002820 的差异集=27 个同名文件+wrapper 更名） | E1 差异核算 |
| 约束文件 | `src/adc/ddrmc_x32.adc` 与 `src/sdc/ddrmc_x32.sdc` 与旧版**逐字节相同** | 集成零改动依据 |
| 物理 CK（1333） | 50×80/3/2=**666.6667MHz ≤ 666.667MHz** | T01 §1.4 |
| 用户域时钟（1333） | PLL1_REFCLK_FREQ=166.7 → STA 实测 166.650MHz（6.001ns） | E2 报告 |
| MCU/调试时钟 | 50MHz（UART 初始化固件）；探针窗口低 8 位 F0 返回 `0x46525031` | 10-11 探针说明 |
| 初始化依赖 | MCU ROM/APB 通路必须保留；`ph1p_ddrphy_wrap` 内 `apb_pclk=cfg_clk` | 不能只抄 wrapper |

**跨域含义**：`ddr_frame_store` 被设计为**单 DDR 用户时钟域**模块（模块头注释："Single DDR-user-clock domain"）；它不接受相机域/显示域的异步信号——两侧要各自经异步 FIFO 进来（10-11 版本"CSI/显示异步 FIFO 仍待接入"，`../DDR完整帧后端实施与上板验证_2026-10-11.md` §1）。这就是"闸门"的具体形态：**域内讲握手，域间讲 FIFO**。

## 硬件实现视角：工程里的接线与工具链

### 工程接线（1333 候选与 002820 同构）

【本项目事实】顶层 `camera_ddr_display_top.v` 实例化 `ddrmc_display_top`（例化名 `u_ddrmc_test_top`）；其中实例化 `ddrmc_x32 u_ddrmc_x32`：`ref_clk=sys_clk50m`，保留 APB 与 ddrio 通路，**PAXI 直连**显示/采集模块 `camera_rgb565_display_guarded u_capture`，`usr_ref_type=2'b00/usr_ref_req=1'b0`；IP 以 `add_files ./vendor/ip/ddrmc_x32/ddrmc_x32.xml` 注册（fileset 带入 adc/sdc）（T01 run dev-plan §1.1）。

### IP 生成工序："CLI 引导＋一次用户在场 GUI Generate"

【本项目事实】这条路是被"试错"逼出来的：

```text
6.2.2 CLI IpTool headless：20/20 次受控尝试未跑通（边界已证实，不再重复盲试）
6.2.3 Tcl IP flow：create_ip/load_project_ips/set_property/generate_target 命令族可用；
  但 generate 卡在 <export>/.IpToolIpDataBackupDir_<comp>/<comp>_adc.log 的 staging 前置
  （≥8 次同因；该文件正常由 GUI 的 ADC check/apply 物化；CLI 无等价入口 read_adc=USR-8321）
→ 方案 A（GUI 应用步后 CLI 生成）：实测否证（不物化 adc.log）
→ 方案 B（全 GUI 生成）：成功，双复现裁定 PASS（run1/run2）
→ 固化：CLI 引导配方（私有 depot 副本、保留式清理、参数/引脚准备、绑定检查）＋ 一次用户在场 GUI Generate
```

（依据：`../../tools/td/README.md`"6.2.3 安装位置与新锚点/边界注意"节；`../../workflow/runs/20261017_161109_decisions_compare_freeze/decision-register.md` §4.1；生成证据 `../evidence/td2026_gui_bootstrap_20261017.json`、`../evidence/td2026_ddr1333_generate_20261017.json`、`../evidence/td2026_ddr1333_accept_20261017.json`；双复现镜像 `../evidence/td2026_b_run2_20261017.json`。）

为什么"headless 结构性不可行"（到当前证据为止）：卡点是**GUI 才有的 ADC 应用步**——不是权限、不是路径，而是生成器工作流里没有 CLI 等价物；这属于"如实记录的工具边界"，而不是"再试几次就好"。生成后还有一个纪律：**新闭包单源**（run1 为源、run2 仅登记镜像），避免混用造成不可追溯。

### 全链同版本纪律与证据锚

【本项目事实】"6.2.2 生成的东西用 6.2.2 构建、6.2.3 生成的东西用 6.2.3 构建"——因为两版的工具哈希、depot、行为都不同：

| 版本 | 安装/状态 | 关键锚（SHA256 前缀） |
|---|---|---|
| 6.2.2（`D:\downlaod`） | **只读遗留/历史证据锚**，不再生成新 IP | CLI `79EC5667…`、IpTool `DA9E765E…`、`ph1_100p.db` `8E7E8812…` |
| 6.2.3（`D:\anlogic\TD_Release_2026.2`） | 现役（新 IP/新候选全链同版本） | CLI `2629E474…`、td `FA2A5AC6…`、IpTool `5B0654AA…`、`ph1_100p.db` `939EC294…`、license `DC19FEE6…` |

即使两版 `DB_VERSION` 恰好同为 46207，也**不得跨版本混用 DB**；历史证据继续绑定 6.2.2、新候选绑定 6.2.3（`../../workflow/runs/20261016_185639_td_cli_iptool/upgrade-review.md` §3.1；decision-register §4）。

## 本项目实例：一次"只换 IP"的完整闭环

【本项目事实】把上面的机制串起来，就是 2026-10-17 T01 集成轮的真实路径：

1. **派生（E1）**：从冻结基线 002820 全量复制，仅替换 **64 文件**（61 文件新 IP 闭包＋3 个 IP 日志）；wrapper 更名=1 移 1 加；范围外 156 项**逐字节零差异**；接口 53 行与 ADC/SDC 逐字节相同 → 项目侧 RTL/`timing.sdc`/顶层**零改动**（`../DDR1333集成与1333vs1600对比_2026-10-17.md` §2）。
2. **构建（E2）**：对 1333 与 1600ctl 两个候选跑 6.2.3 全链（build→route→最终 STA→bitgen）；6 个阶段全部 exit 0＋完成标记＋产物 SHA；bitgen fail-closed（STA 非负/TNS=0/skew 通过才产 bit）；**本批不含下载**（同上 §3；其后的 SRAM 下载与用户观察见 T01-F 记录）。
3. **结果**：1333 setup 0.230 vs 1600ctl 0.128（第 10 章）；两候选 bit 已条件生成，并已由 T01-F 执行 SRAM 下载观察（2026-10-17 晚；1333 经断电重上电复测工作正常、G3 口径基本达成；G4 稳定观察进行中）。
4. **已闭环（rev4）**：TMST-7700 明细枚举完成（3×`clock definition→local clocks`＋1×PLL 取整；`no_clock`/组合环/无效约束=0）——分类=既有完整性/结构风格、**无实质约束缺口、不触发升级，M5.7 已关闭**；`mipi_a_byte_clk` local 观察点转 M5.5（产物：`../TMST-7700最小调查_2026-10-17.md`、`../evidence/tmst7700_20261017.json`）。
5. **工具链冻结**（M4）：6.2.3-forward＋6.2.2 只读＋BW 1.2.3 不装＋"CLI 引导＋一次 GUI Generate"流程固化；任何 DDR MC 变体重生成一律走该流程（decision-register §4.3）。

## 与本项目方案的对应

| 结论 | 依据 |
|---|---|
| `ddrmc_x32` 接线：顶层→ddrmc_display_top→ddrmc_x32；PAXI 直连 capture；APB/ddrio/初始化依赖保留 | `../../workflow/runs/20261017_153201_T01_ddr1333_integration/dev-plan.md` §1.1 |
| 用户接口 53 行端口不变、ADC/SDC 逐字节相同 → "只换 IP"零改动可行 | 同上 §1.2/§1.3；`../DDR1333集成与1333vs1600对比_2026-10-17.md` §2 |
| 1333 物理 CK 复核 666.6667MHz≤666.667MHz；用户域 166.650MHz | 同上 §1.4；E3 §4.1 |
| IP 生成＝"CLI 引导＋一次 GUI Generate"；headless 卡 adc.log staging、A 方案否证、B 方案双复现 | `../../tools/td/README.md`；decision-register §4.1；`../evidence/td2026_gui_bootstrap_20261017.json`、`../evidence/td2026_ddr1333_generate_20261017.json` |
| 全链同版本纪律：6.2.3-forward、6.2.2 只读、不得跨版本混 DB/拼证据 | `../../workflow/runs/20261016_185639_td_cli_iptool/upgrade-review.md` §3.1/§3.3；decision-register §4 |
| 工具锚（CLI/td/IpTool/db/license）与 DB_VERSION=46207 登记 | `../../tools/td/README.md`；`../evidence/td2026_install_20261016.json` |
| PAXI 与 AXI 迁移面（I4/C3/T5）与 800E/AXI 后端锚 | decision-register §1.2/§1.3；`../DDR1333集成与1333vs1600对比_2026-10-17.md` §8 |
| TMST-7700 已调查关闭（rev4）：明细枚举无实质缺口、不触发升级；`mipi_a_byte_clk` local 转 M5.5 | decision-register M5.7；`../TMST-7700最小调查_2026-10-17.md`；`../evidence/tmst7700_20261017.json` |
| **证据边界**：以上为工具/生成/构建级证据；板级执行记录见 T01-F（早期黑屏=间歇性 DDR 校准；1333 复测工作正常；G4 稳定观察进行中，结论以 T01-F/登记为准） | `../../workflow/runs/20261017_182621_T01_board_and_tmst7700/dev-notes-F.md`；`../evidence/board_verify_ddr1333_20261017.json` |

## 决策点与判决框架

**决策点：DDR MC/IP 的工具链与生成方式怎么定？**

| 选项 | 内容 | 代价/收益 |
|---|---|---|
| A. 并行升级 6.2.3-forward＋一次 GUI Generate（当前） | 新目录并存；CLI 引导＋用户在场 GUI 生成；全链同版本 | 打通新档位与后续变体；需双版本纪律与 GUI 窗口（约 30–60min） |
| B. 仅 6.2.2 + GUI（不升级） | 沿用旧版 | 无法生成新档位 IP（命令族缺失已否证）；无自动化收益 |
| C. 全自动 headless（无需 GUI） | 追求无人生成 | **当前结构性不可行**（adc.log staging 的 GUI 等价步缺失）——如实登记，待工具/官方变化 |

- **权衡维度**：能否生成目标档位；可复现性（双复现/单源纪律）；对冻结证据链的影响（锚点保留）；用户在场成本；风险（新工具未知缺陷）。
- **当前选择**：A（M4 冻结）。理由：B 无法达成目标；C 已被多重实验否证；A 已两次复现成功且保持 6.2.2 只读。
- **何时应重开**：① 6.2.3 全链暴露工具缺陷/不可复现；② TD 新版修复 adc.log/headless 流程（可重新评估 C）；③ 需要 BW 新功能（用户决策是否安装）；④ 官方工具链变更或队友 IP 版本漂移（重对齐）。

## 常见误区

- **"控制器只是根'导线'"**：调度、训练、刷新编排、仲裁都在 MC 里；它们决定最坏延迟与稳定性。**正确做法**：把 MC/PHY 当"有策略的子系统"评估，而不是透明通道。
- **"换个 IP = 改个文件"**：本项目能做到"只换 IP 零改动"，前提是**接口 53 行不变、ADC/SDC 逐字节相同、wrapper 例化名保持**；任何一项破了都要动项目侧与约束。**正确做法**：替换前逐项核对接口/约束/例化名。
- **"PAXI 和 AXI 差不多，改改就能换"**：两者在突发语义、响应通道、地址单位与对齐规则上都不同；用户侧（如 `ddr_frame_store`）与 4KB 对齐/尾突发都有迁移面。**正确做法**：按 I4/C3/T5 的清单评估迁移，而不是"改接口名"。
- **"CLI 跑不通就是没找对姿势"**：6.2.2/6.2.3 的失败已被系统化记录（20/20、≥8 次同因），卡点是 GUI 专属步骤。**正确做法**：尊重"边界证据"，改走已固化的引导流程，不重复盲试。
- **"版本混用没关系，反正 DB_VERSION 一样"**：不同版本的 depot/行为/哈希都可能不同，跨版本拼接会污染证据链。**正确做法**：同候选全链同版本；跨版本引用显式标注。

## 自测题

<details><summary>1. DDR 控制器的三大职能是什么？</summary>

调度（重排/仲裁/时序检查，提高行命中并保证公平）、训练（写均衡/读训练/ODT 与驱动校准）、初始化（电源/复位/MR 写入/ZQ 校准后才能受理访问）；PHY 负责电平与采样。
</details>

<details><summary>2. 为什么"只复制 DDR wrapper"不可行？</summary>

初始化与校准依赖 MCU/APB 通路与初始化 ROM（官方例程的 mtest/ROM 是必要依赖）；脱离它们，颗粒无法被正确初始化。本项目文档将其列为硬依赖并在探针工程中保留。
</details>

<details><summary>3. 原生 PAXI 与 AXI4 的"本质差异"用一句话说？</summary>

PAXI 是厂商原生握手口（当前包装：单 256bit 命令、步长 8、无 B/burst LEN 端口）；AXI4 是标准五通道总线（含突发长度/ID/响应）。迁移不是改名，而是接口语义、对齐与用户侧逻辑的整体适配。
</details>

<details><summary>4. 为什么 IP 生成要走"CLI 引导＋一次 GUI Generate"？</summary>

6.2.2 CLI headless 20/20 失败（边界证实）；6.2.3 Tcl flow 命令族可用但 `generate_target` 卡在 `<comp>_adc.log` staging——该文件由 GUI 的 ADC check/apply 物化，CLI 无等价入口（USR-8321）。方案 A 否证、方案 B 成功并双复现，故固化为"CLI 准备＋一次 GUI 生成"。
</details>

<details><summary>5. "全链同版本纪律"具体防什么？</summary>

防"工具版本因素"混入结论：不同版本的 depot/行为/DB 与哈希不同，跨版本拼接会让对比与证据链不可归因。纪律=新候选全链同版本（6.2.3-forward）、旧证据锚（6.2.2）只读保留、跨版本引用显式标注。
</details>

<details><summary>6. 1333 候选的"接口等值"包含哪些可核对项？</summary>

53 行端口集合完全一致；IP 内部例化名保持（`ph1p_ddrmc_wrapper`/`ph1p_ddrmc_top`）；`src/adc` 与 `src/sdc` 与 002820 逐字节相同；范围外 156 项逐字节零差异（故项目侧 RTL/约束零改动）。
</details>

## 延伸资源

| 标题 | 类型 | 语言 | 体量 | 推荐理由 | 链接 | 核验状态 | 备用检索词 |
|---|---|---|---|---|---|---|---|
| AMBA Specifications（Arm 官网） | 文档 | 英文 | 一页 | AXI 等 AMBA 规范的官方入口与版本体系 | [arm.com](https://www.arm.com/architecture/system-architectures/amba/amba-specifications) | 在线核验通过 2026-10-17 | AMBA specifications Arm |
| Memory controller（维基百科，英文） | 文档 | 英文 | 约 4 千字 | 控制器职责/DRAM 刷新/DDR 控制器差异的概览 | [en.wikipedia](https://en.wikipedia.org/wiki/Memory_controller) | 在线核验通过 2026-10-17 | Memory controller Wikipedia |
| 内存控制器（维基百科，中文） | 文档 | 中文 | 约 2 千字 | 中文速览：控制器在做什么、双通道/FB-DIMM | [zh.wikipedia](https://zh.wikipedia.org/wiki/内存控制器) | 在线核验通过 2026-10-17 | 内存控制器 维基 |
| 例解 ZYNQ 系统中用到的 AXI4 协议（B站，小梅哥FPGA） | 视频 | 中文 | 约 1 小时 46 分 | 从信号到时序、配 ILA 实测讲解 AXI4 | [bilibili](https://www.bilibili.com/video/BV18r421p7Ck/) | 在线核验通过 2026-10-17 | 小梅哥 AXI4 ZYNQ 例解 |
| 米联客 AXI4 总线编程入门专题：01 初识 AXI4 总线 | 视频 | 中文 | 约 24 分钟（需登录观看） | 系列课程第一讲，从总线规格到 FDMA 实战 | [uisrc.com](https://www.uisrc.com/lesson-621.html) | 在线核验通过 2026-10-17 | 米联客 AXI4 总线 初识 |

> 核验说明：5 条均以实际网络请求核验（2026-10-17）；米联客课程页可访问、视频播放需登录（已在体量栏注明）。未采用候选（AMD UG586 文档页为动态壳页、Arm AXI 规范页直取未能取到正文）记录见 `../../workflow/runs/20261017_162355_fpga_knowledge_book/link-check-KB3.json`。

## 术语增量

| 术语（中英） | 一句白话 | 首次出现章号 |
|---|---|---|
| DDR 控制器（MC） | 负责 DDR 调度/初始化/训练的硬件模块 | 11 |
| PHY | 物理层：电平、延迟、采样与训练的执行者 | 11 |
| 写均衡（write leveling） | 对齐 DQS 与颗粒时钟相位的训练 | 11 |
| 读训练（read gate/DQ training） | 扫描延迟找到稳定读取窗口的训练 | 11 |
| ODT/ZQ 校准 | 终端电阻与驱动强度的校准机制 | 11 |
| 模式寄存器（MR0–MR3） | 初始化时写入 CL/CWL/ODT 等配置的寄存器 | 11 |
| 用户域时钟 | MC 提供给用户逻辑的接口时钟（≠CK） | 11 |
| IP 闭包（closure） | 一个 IP 生成产物包含的全部文件集合 | 11 |
| wrapper 更名（1 移 1 加） | 派生时旧包装不复制、新包装写入的等值替换手法 | 11 |
| 双复现 | 同一流程独立执行两次得到一致结论的验证方式 | 11 |
| 6.2.3-forward | 新候选全链用 TD 6.2.3 的纪律 | 11 |
| DB_VERSION | 工具数据库格式版本（跨版本不得混用） | 11 |

## 版本记录

| 版本 | 日期 | 变更 |
|---|---|---|
| 初稿 r0 | 2026-10-17 | KB3 首版：以"港口调度中心＋军训教官"组织 MC/训练/初始化；含 ddrmc_x32 接线与参数、PAXI vs AXI 与迁移面、IP 生成工序（CLI 引导＋GUI Generate）与全链同版本纪律；外部资源 5 条全部在线核验。 |
| 修订 r1 | 2026-10-17 | KB3 修复轮（r0 测试 D1/F1/F2）：TMST-7700 改为 rev4 口径（明细枚举完成、M5.7 已关闭、无实质缺口；观察点转 M5.5）；E2"未下载"改为"本批不含下载"并补 T01-F 下载/复测事实；证据边界同步；未改其余事实与数字。 |
