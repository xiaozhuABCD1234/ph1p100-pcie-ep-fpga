# fpga-design-guide.md — 20261019-2117_runD_batch2_continue

本指南只冻结本轮两个正式包相关的数据、接口、时序、缓存与证据约定；B01 的完整设计语义以 `workflow/runs/20261019-0212_codex_fpga_closedloop_b2/fpga-design-guide.md` 和两份 r0 报告为准，本文不重复、不覆盖。旧值与本文冲突时，以本文“本轮新增/冻结”段和 0212 最终 manifest 哈希为准；不得用“最终版”文件名代替哈希。

## 1. T02.codex-singleA-board（板级闭环）

### 1.1 候选身份（冻结）

| 项 | 值 |
|---|---|
| manifest | `workflow/runs/20261019-0212_codex_fpga_closedloop_b2/recovery01/B01/timing-continuation01/remaining-attempts01/candidate/manifest.json`；SHA256 `c7a40897166467f2beafb096701dba9cf836e1007d77ae03d90009d06f80d757`；699 项 |
| bit | 同目录 `current.bit`；期望 SHA256 `b68c6e183e97eb0d465db77078f5049feca3a947fac51f99633621dd99b3f9bf` |
| CWC | 同目录 `current.cwc`；期望 SHA256 `b28e3d4ee476731b118da0b12c3bad8dcca1dadfbd9b7ae4dc418c4d225a74ce` |
| BID | 同目录 `current.bid`；期望 SHA256 `4dcdc26382f6b49e7ed9b95a40a1d57c05191c0130050812a74b853c16b38f33` |
| probe map | 同目录 `probe-map.json`（40 项 enabled probes；camera/DHI/TL 域） |
| 生产构建 | 6/6 已用尽；本轮**禁止**第 7 次生产构建，禁止重跑 T06/T09 仿真代替 |

下载前逐项复算 bit/CWC/BID/manifest；任一不符即 `INPUT_CONFLICT`，不下载、不尝试“找同名文件”。

### 1.2 板级数据语义（40 项探针，完整 32 位原值）

- 身份：`cl_identity=0x434c0101`，`algo_identity=0x414c0101`。
- 两个不同 `seq` 的完整帧：`cl_words=648192`，`cl_len=2592768`，`flags[31]=1`，`flags[3:0]=15`，`flags[15:8]=0`，`fault=0`，`pass_count` 持续推进；四类 ok（magic/header_crc/payload_crc/length）全真，错误计数为 0。
- 跨域不原子：camera 源域、DHI 读回域、TL 域分别采样；同一“组”内两时刻 `T1/T2` 间隔 ≥20 s，但 camera 与 DHI 的同一时刻样本仍是独立实例，不能拼成原子快照。
- 几何：`source_geometry={last_lines[15:0], last_wc[15:0]}`（高 16 位源行数、低 16 位源 RAW 字节数）；源模式/ROI 期望 `X960/Y540/W1920/H1080/SKIP37`。必须解释实际输出合规依据，不能把源几何误当 ROI 尺寸，也不能改数字凑 PASS。
- 相位：最终候选 `PHASE=3`；物理 Bayer 相位仍未证，计数/颜色观感不能代替。无有效配置/标定/真实图样依据时保持 `unknown`。
- 坏帧/恢复：一次内部 abort 必须 `source_injected=1`，`writer_bad` 及拒发布路径成立，随后 `cl_recovery_count>=1`，且首个合法 good 帧完整通过 checker；旧 pending 帧不算恢复。内部 abort 不等于物理 CSI CRC 故障。
- 板级短窗 ≥20 s；G4 10 分钟/热/长稳/性能用户后放，本轮不测、不外推。

### 1.3 板卡/读回接口

- 只允许 **SRAM** JTAG 下载；零 Flash/efuse/SPI/svf；不改线、电源、相机、传感器表。
- 下载入口沿用 0212 `scripts/run_sram.py` 的 connect → `read_device_id` → `download -mode jtag` → `close` 语义；不得自动启动 hwserver，不扫描其他线缆。
- 先只读 `read_device_id`：非 `PH1P100` 或 PRG-8000 类错误 → 停，返回 `awaiting_hardware`，不执行 download。
- 单次 download 上限 **180 s**（本轮新冻结；旧 120 s 曾超时且 0 样本；180 s 仅给安全余量，不降低验收），自有进程树可安全终止；失败/超时/PRG-2014 不成功 → **不重试**，保存日志与 `sram-execution.json`。
- CLI 读回永久关闭；唯一读回路径是用户本人 TD GUI ChipWatcher + paired CWC。禁止 GUI 自动化。
- 下载成功后板上候选=本 run 唯一；旧 bit `bfafdf97…`/CWC `8d2998b9…` 只作回退，不自动重下。

### 1.4 板窗租约（与 0207 并行线协调）

下载前必须完成并落盘 `board/board-window-lease.json`：

1. 进程表：无 `td_commands_prompt`、`run_td`、`run_build`、`bw`/`download` 活跃构建/下载进程；既有 `td.exe` GUI 与 hwserver 实例不得结束。
2. 0207 记录：读 `workflow/runs/20261019-0207_runA_ddr_readback_loop/board-checklist/preload-record*.md`、`dev-result.md` 的 mtime 与结论；若其正在下载，或已成功预载且尚未消费/回退，则**不覆盖**，本 run 返回 `awaiting_board_window`。
3. 租约：记录 candidate SHA、时间、进程快照、0207 记录结论；下载后更新为“board=本 run 候选”。0207 下次恢复读到租约必须停，不得互等或互杀。
4. 有界等待=0：发现占用立即返回，不重复轮询；这与“进度优先”一致。

### 1.5 证据与清单

- 用户清单必须包含：候选绝对路径 + SHA、当前板载状态、两次点击步骤（≥20 s、16 字原值/截图/时间戳）、冻结期望值、异常分流、回退（旧 bit/CWC 或断电）、G3 tier 口径。
- 开发返回 `awaiting_user_gui` 时，manifest 只绑定 preload/清单证据；**不得**写 G3 PASS。

## 2. T08.codex-sync-offline（双相机同步离线原型）

### 2.1 接口（离线白名单）

- 控制器单时钟 `clk_ctrl`（目标 50 MHz）+ `rst_n`；最多一个在途 I2C 请求：
  - `req_valid/req_ready`、`camera_id`、16 bit `reg_addr`、8 bit `reg_data`；
  - `rsp_valid/rsp_ok`；请求受压保持全部字段；NACK/timeout 不得当成功。
- 角色/配置白名单冻结：`3003 bit0`（A=0/master，B=1/slave）、`3002` XMSTA、`30C0=2A`、`30C1` 低 4 位 HiZ=`0F`、A 主输出=`00`；`3000` 待机语义须从本地实际表核对后写入接口合同，不盲造完整 sensor 表。
- `30C1` 为 S 类：待机期间配置、退出待机反映；禁止运行中切主从/改驱动并假定即时生效。
- 本包不是完整 IMX415 驱动：同模式/SHR0/行帧周期/连续参考时钟由明确前置输入表示；仿真置真必须标 `synthetic`，不代表物理已证。

### 2.2 时序/常数

| 参数 | 冻结值/定义 |
|---|---|
| 24 ms 等待 | 50 MHz 下 1,200,000 个 `clk_ctrl` 周期；仿真可缩短等待参数，但必须验证默认常数推导/位宽并分开记录 |
| 前 8 帧 | `WARMUP_FRAMES=8`；第 9 帧边界必须由 TB 覆盖 |
| 角色顺序 | 两路先 standby/输出 HiZ → 确认 B 从角色及 HiZ → B 先退出待机并等待 ≥24 ms → 允许 A 开流；A 自身退出待机后也 ≥24 ms，跳前 8 帧 |
| SOF 源域 | 各 187.5 MHz，相互独立；多位序号用稳定总线握手/async FIFO，不用多位两级采样当原子 |
| 公共时间戳 | `clk_ctrl` 周期；32 bit 模差，有效距离 <2^31 |
| 配对窗口 | 明确参数；仿真示例值不声明硬件阈值；不得称“0 偏差=曝光同步” |

### 2.3 故障/复位

- NACK/timeout/abort/reset 走安全停止或错误状态；重复 start 不重入；单路缺失、失锁、恢复、计数回绕都要有 TB。
- 至少一个有效负对照：能拒绝旧/变异行为，且是“预期失败”而非编译错误；负对照只改隔离副本。
- 复位期间不得输出“成功”或半配置状态；恢复后重新走完整顺序。

### 2.4 时钟/CDC/实现

- 三个实际时钟：`clk_ctrl` 50 MHz、camera A SOF 187.5 MHz、camera B SOF 187.5 MHz（仿真/小顶约束均要落点）。
- 所有跨域事件必须经合法 CDC（握手或 async FIFO）；记录 CDC 边界、同步延迟、约束落点；禁止宽泛 false_path 豁免。
- 离线小顶必须实际保留控制与 CDC 逻辑，不能被综合优化成常量/未用；50/187.5 MHz 不降。
- 小顶 G2 一次 TD 综合 ≤25 min：Routed、setup/hold WNS≥0、TNS=0、各适用时钟组 0 违例、资源≤器件；不生成可下载声明、不接活动 top、不下载。
- 若 TD 被占用/失败：记录 `blocked`，G2 `not_run/fail` 如实登记，不以 G1 冒充 G2；不重试、不等待、不改门槛。

### 2.5 写范围/保护（T08）

- 允许：`upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/cam/sync_offline/**`（新建/修改既有 T08 文件）、`sim/tb/tb_sync_offline*.v|sv`（新建/修改）、本 run `sync-offline/**`（脚本、小顶、SDC、Tcl、日志、g1/g2、manifest）。
- 保护：B01 699 项、活动 top、`sim/compile_checked.f`、原 I2C/寄存器表、生产约束/IP/ADC、旧 run/证据、`workflow/tasks.json`。
- 不 commit/push；新文件 worktree-only 冻结即可。改前/改后分别对 B01 699 项复算，0 漂移。

## 3. 通用证据约定

- 每包一个唯一 manifest（路径+SHA+条目数），所有新文件/日志可复算 SHA256；报告必须绑定当前 manifest，不能拼不同输入 PASS。
- 实际命令、cwd、退出码、完成标记、非空产物、工具版本（ModelSim 10.5b/Intel 18.1 ASE、TD 2026.2、Python 3.11）必须记录；未执行命令标“建议”，不写成已执行。
- 失败保留原始日志；测试者不改冻结候选，不在生产树做实验；负对照/变异只在隔离副本。
- G 层口径：T02 G0/G1/G2 继承 B01 同 manifest；G3 新板证；G4 not_run。T08 G0/G1/G2 本轮；G3/G4 not_applicable（未接硬件）；G5 not_applicable（不推送）。

## 4. 已冻结 / 待确认 / 不适用

- **已冻结**：T02 候选身份与期望值；T08 接口/常数/时钟/写范围；板窗租约与下载安全边界；两包 G 层与阈值。
- **待确认（运行中解决，不阻塞派发）**：板当前电源/USB/5555 状态（机械检查）；0207 是否同时抢窗（租约检查）；T08 小顶 TD 可用性（有界尝试）；用户点击时间（清单后置）。
- **不适用**：T02 G4 长稳/优化（用户后放）；T08 真实双路曝光同步/电气/寄存器读回（离线原型不接硬件）；PCIe/RK/压缩/Flash/推送（本轮明确不做）。
