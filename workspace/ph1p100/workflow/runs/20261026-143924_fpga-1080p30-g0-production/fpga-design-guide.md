# 工程设计指南（本任务冻结项）— 1080p30 G0 生产前提收口

> 只冻结本任务相关项，其余沿用 P3/P4 冻结文件与项目设计规范。旧值与新值冲突时以本文件 §1/§2 的来源为准；不得用「最终版」文件名替代证据。

## 1. 数据格式（内容 → DUT，全包一致）

| 项 | 冻结值 | 来源/说明 |
|---|---|---|
| 帧几何 | 1920×1080；RAW10 packed | P4 content-map |
| 字节率 | 1.25 B/px；2,592,000 B/帧 | 同上 |
| 行结构 | stride 2400 B；480 组/行；518,400 组/帧 | 同上 |
| 组打包 | 5 B/4 px：`b0..b3 = p0..p3[9:2]`，`b4 = {p3[1:0],p2[1:0],p1[1:0],p0[1:0]}`；40-bit 组 `{b4,b3,b2,b1,b0}` | P4 报告 §4.3；不得改位序 |
| 文本格式 | 每行一个 40-bit 组，10 位十六进制（`raw40_*.hex`），518,400 行 | `tb_ss_4run.v` `+RAW40` |
| CFA（派生内容专用） | **RGGB**，偶数行/偶数列 R，奇列 G，奇行偶列 G，奇奇 B | 仅用于内容派生与描述；DUT 只做同色预测，不改 RTL |
| 位深/范围 | 10-bit 0..1023；派生时饱和到 [0,1023]，不 dither 到 >1023 | 冻结 |
| 字节序 | 组内 b0 先；hex 行左起为 b4..b0（与 P4 `raw40` 生成器一致） | 以 P4 content-map roundtrip 0 mismatch 为准 |

## 2. 生产 pacing / 槽 / sink 语义（本包最易混淆，必须先分清）

| 语义 | P3/P4 冻结 TB | **生产 top（b11 `changed-src`）** | 本任务冻结 |
|---|---|---|---|
| 下一帧启动 | `wait_slot_free(slot)`：等目标 RAW 槽 FREE 才 drive_frame | 相机**自由跑**；SOF 时无 FREE slot → `skip_frame=1` 丢弃整帧，`raw_begin_deny/raw_deny_nofree++` | P1 沿用 TB 门控（内容锚点用）；**P2/P3 必须用自由跑 30 fps**，丢帧 >0 即生产 pacing 不成立 |
| 核启动 | TB 不干预核；核内 `in_ready` 由 `I_IDLE/frame_active` 决定 | `a1_can_start = (fstate==F_IDLE) && !a1_busy && !a1_out_valid && raw_rd_open_ready && cmp_begin_ready`（`camera_a1_uart_top.v:573-574`） | 生产核是**帧串行**；只允许「导出(k) 与 采集/压缩(k+1) 重叠」，不允许「两帧同时压缩」 |
| RAW 槽 | 2 槽 `raw_slot_st[3:0]`，TB 只读 | `a1_ddr_slot_store` 2 槽状态机 FREE/WRITE/READY/READING | slot-free 的定义 = **k+1 采集/写入不与 k 的读取/压缩互斥**，且不丢帧 |
| 导出 sink | `SINK=1`：`clk_uart`=2 GHz，`UART_DIV=1`，实测上限 2 clk_a1/B = **93.75 MB/s** | `a1_uart_export` + 115200 UART ≈ **11.52 kB/s** | 93.75 是**TB 代理上限**；生产 sink 是 P3 的**离线模型**，不得称已实现 |
| 丢帧/溢出计 | TB：`raw_drop/cmp_drop/err/wd` 必须 0 | `raw_deny_nofree`、`fifo_ovf_cnt`、`wd_fires` | 任一 >0 → 该 run `partial`/`not_proven`，不得当 G0 |

## 3. 指标定义（复用 P4 冻结口径，不另立公式）

对一次 `FRAMES=4` 全尺寸 run（事件来自 `+EVT`，统计来自 `+STAT`）：

- `t_sof(k) / t_enc(k) / t_exp(k)`：第 k 帧 SOF、commit、导出完成。
- `L_cold = t_exp(1)`（以 `t_rst` 为 0 基准；与 P4 一致）。
- `S_2 = t_exp(2)-t_exp(1)`；`S_23 = t_exp(3)-t_exp(2)`；`S_34 = t_exp(4)-t_exp(3)`；**`S_ss = (S_23+S_34)/2`**（不是三间隔均值）。
- `tail(k) = t_exp(k)-t_enc(k)`；`tail_mean = mean(tail(2..4))`；`tail_frac = tail_mean/S_ss`。
- `sink_limited = (tail_frac ≥ 0.50)`（诊断旗标；≥50% 时必须报告并说明）。**2026-10-26 澄清**：作为 G0 的 `G0_not_proven` 阻断条件，用 **sink 忙碌率** `busy = export_time / S_ss ≥ 0.95`（sink 在 ≥95% 的帧间隔内持续服务才视为 gate）；若 `busy<0.95` 且 `S_ss>6.25M`，实际瓶颈不是 sink，应判 `G0_not_closed`。不用 `export_time ≥ core_interval`：sink 背压会同时拖慢 core 的 `t_enc`。该澄清不改变 P4 四轮矩阵 R3（busy=99.998%，仍 sink_limited）与 R1/R2/R4（busy≤28.6%），仅修正 P1 自然内容 L 类（busy=61.72%）的误标。
- `C_ss = 2,592,000 × 187.5e6 / S_ss / 1e6` MB/s；`margin_G0 = 6,250,000/S_ss - 1`；`margin_G25 = 5,000,000/S_ss - 1`（**仅参考列**）。
- `G0`：`cap=enc=exported=4`、`read=518,400`、`raw_drop=cmp_drop=geom=err=wd=0`、内容自检 `bad=0`、`S_ss ≤ 6,250,000`、`sink_limited`（按上条 busy≥0.95）为 false → `G0_feasible_for_scope`；`S_ss > 6,250,000` 且 sink 未 gate → `G0_not_closed`；sink 实际 gate 或缺帧/丢帧/自检失败 → `G0_not_proven`。
  - **`dup` 不是完整性门槛（2026-10-26 裁决 A）**：`st_dup_words`（`a1_ddr_slot_store.v:280-284`）统计「相邻 256-bit 读字载荷逐位相同」，每读 +1，无地址比较/CRC/重发语义；它随内容平坦区变化（N 3,896、L 568，可由内容逐字精确预测，帧边界 0），`read=518,400`/`ar=r`/CRC 均干净。故 **`dup` 只记录、不参与 G0/A3/P2 完整性判定**；把它当门槛会使任何自然内容必然失败。若 `dup` 异常升高且伴随 `read>518,400`、`ar≠r`、CRC/自检失败，则按数据完整性问题单独调查，不能用本豁免。
  - **`ss_pass` 说明**：冻结 TB 的 `ss_pass` 表达式含 `st_dup==0`，自然内容下必然打印 `ss_pass=0`/`B11_FULL_RESULT pass=0`；**这不是任务失败**，验收以本节的显式子句为准。任何新 TB 不得把 `ss_pass` 当唯一验收旗标。
- **生产自由跑附加指标**（后续生产 pacing 包；本轮 P2 是 coregap，不是 pacing 包）：`slack(k) = t_sof(k+1) - t_exp(k)`（≥0 才不丢下一帧），报 min slack 与 `% of 6,250,000`；`SOF` 固定 6,250,000 cycles 间隔时，`S_ss` 由构造决定，**不得当作容量测量**，容量证据只能是 `slack` 与丢帧计数。
- **原始带单列**：`raw_band_cycles = 2,594,706 B × clk_per_byte`；在 93.75 MB/s = 5,189,412 cycles（27.677 ms，83.03%）；在 103.79 MB/s = **4,687,500 cycles（25.0 ms，75.0%）**。任何报告必须把 raw band tail 与 comp 流 tail 分开。
  - **勘误（2026-10-26 规划裁决）**：本指南初版把 103.79 MB/s 写成 5,000,000 cycles，算术错误（5,000,000/6,250,000=80%，且对应 26.667 ms）。正确值：25.0 ms × 187.5 MHz = **4,687,500 cycles**；按 `2,594,706 B / 25.0 ms` 反算速率为 **103.78824 MB/s**。若报告采用取整后的 103.79 MB/s，允许出现 4,687,421 cycles 的等价值，但**必须写清所用精确速率**，不得两种口径混用。P1 r0 的 `content-verdict.json.raw_band` 已按 4,687,421 登记并注明该勘误；该勘误不改变任何 G0/门槛/百分比（93.75→83.03%、103.79→75.00%）。
- **冷启动与稳态分开**：`t_exp(1)` 是冷启动延迟 `L_cold`（含首帧采集/读取/压缩/首帧导出），**不进入 `S_ss`**；`S_ss` 只用 `t_exp(2..4)` 的稳态间隔。冷启动 12–13M cycles 不构成 G0 失败证据，也不得被隐藏；报告必须单列 `L_cold` 与 `L_cold/6,250,000`。
- **瓶颈归因（必填，避免把 core-bound 误读为 sink-bound）**：每帧同时报 `core_interval(k)=t_enc(k)-t_enc(k-1)`（k≥2）与 `export_time(k)=2×bytes(k)`；`bottleneck_attribution` = 二者较大者。冻结的 `sink_limited=tail_frac≥50%` 仍是 G0 的**必要条件旗标**（为 true 即 `G0_not_proven`），但报告不得因此声称「sink 是唯一约束」——若 core_interval 更大，必须写明实际瓶颈是压缩/读取吞吐。

### 3.1 TB 看门狗语义（round1 冻结，替代 r0 的单常数）

- r0 冻结 TB 的 `WD_LIMIT = 12,000,000` 是 `localparam`，判据为 `(cycles - last_exp_t) > WD_LIMIT`，而 `last_exp_t` 初值 0；因此它实际是「**从复位起 12M cycles 内必须完成首帧导出**」，把冷启动与稳态门槛混在一起。12M **不是** G0 门槛（G0 是 6.25M 稳态间隔），也不是生产门槛。
- round1 允许在**新 TB 副本**里改为两段式看门狗（不改 DUT、不 force）：
  - `WD_LIMIT_COLD = 20,000,000`，锚点 `t_sof(1)`：`st_exp == 0 && (cycles - t_sof[1]) > WD_LIMIT_COLD` → `SS_STALL_COLD`；
  - `WD_LIMIT = 12,000,000`（保持原值），锚点 `last_exp_t`：`st_exp > 0 && (cycles - last_exp_t) > WD_LIMIT` → `SS_STALL`；
  - 两者都打印 `B11_FULL_RESULT pass=0`，都按 `partial` 处理，禁止当作 4 帧证据。
- 允许的语义是「冷启动给 20M、稳态相邻导出仍给 12M」；**不允许**取消看门狗、把冷启动预算 >20M、或把稳态 guard 放宽到 >12M。
- 20M 的依据：r0 实测/下界 N 12,440,065、L 12,901,543（从复位），按 `t_sof(1)=61` 计余量 ≥55%/64%；若真实值超过 20M，如实记 `SS_STALL_COLD` + partial，不得二次放宽。

## 4. 内容标签与证明范围（写死）

| 标签 | 含义 | 允许的使用 |
|---|---|---|
| `real_sensor_raw` | 真实 IMX415 传感器 RAW | 本轮**不存在**，不得使用 |
| `natural_scene_image` | 自然场景图像（display-referred，非传感器 RAW） | 可作为派生 Bayer 的源；必须附来源路径/SHA/派生参数 |
| `low_light_natural_scene` | 低照自然场景（夜景/长曝光） | 同上 |
| `synthetic_natural_texture` | 程序化自然统计纹理 | 仅在无自然场景源时使用 |
| `full_frame_raw_synthetic` | 合成全帧（C1/C2） | 仅作既有对照 |
| `proxy_not_natural_raw` / `not_sensor_raw` | 非真实传感器 RAW | **每个派生内容必带** |
| `proxy_not_worst` | 非最坏内容证明 | 所有内容必带（含 C2/comp） |

- 派生 Bayer 流程必须记录：源图 SHA256、crop/scale、sRGB→线性（或声明的 gamma）、CFA=RGGB、10-bit 量化（含饱和策略）、打包位序、逐帧 SHA/CRC。
- 低照类必须记录：亮度映射/增益、噪声注入（若有）、暗部占比、饱和像素比；标签 `low_light_natural_scene` 而非「低照传感器」。
- **不得**把 UI 截图、抽象渲染、合成图称自然场景；**不得**由自然场景派生图推断真实传感器噪声/光学/CFA 响应。

## 5. 接口与工作目录

| 项 | 冻结 |
|---|---|
| DUT | b11 `changed-src` 12 源（`camera_a1_uart_top.v`、`a1_frame_top.v`、`a1_deflate_core.v`、`a1_ddr_slot_store.v`、`a1_raw_crop.v`、`a1_uart_export.v`、`p2_ddr_bridge.v`、`cam_diag_mailbox.v` + 必要模型源，按 P1 manifest 12 源清单）|
| TB | P1：`tb_ss_4run.v` 冻结副本（`+RAW40`、`FRAMES/CONTENT/PACING/SINK/CAPTURE` 参数）。P2/P3 允许新 TB（新 run 内），必须写逐行 diff 与白名单，不得 `force/deposit` DUT 内部信号 |
| 时钟/复位 | `clk_a1`=187.5 MHz（period 5.333 ns）；`clk_cam`/`clk_uart` 按 TB；`SINK=1` 时 `clk_uart`=2 GHz；单一 `rst_n` |
| DDR | 行为级 256-bit PAXI 单拍模型（P1/P2 沿用；P3 可加 sink 侧模型，不改 DDR 模型语义） |
| 工作目录 | 每任务 `OUTPUT_DIR/<task_id>/r0/{src,sim,out,content,logs,manifest-r0.json}`；临时 `%TEMP%\opencode\ss-g0-prod-<suffix>\{work,modelsim.ini,logs}` |
| 构建入口 | `vlib`/`vlog -sv -work work +define+SIMULATION`/`vsim -c … -do "run -all; quit -f"`；无 TD、无 make、无网络 |
| 每任务独占 | ModelSim 库、`modelsim.ini`、日志、`TEMP` 子目录；**不共享**盘符映射；并发任务不得共用库 |

## 6. 证据与报告约定

- manifest：`manifest-r0.json` 列全部 artifact（SHA256+bytes）、`write_scope`、`stopped_modifying=true`、`active_commands=0`、`verdict`、`commands.jsonl`。
- 原始证据：`sim/logs/*.log`、`sim/caps/*.{stats,evt,hdr}`、`commands.jsonl`（含 timeout/rc/完成标记）。
- 报告：`test-reports/<task_id>-r<round>-integrated.md`，首行唯一 `### 判定：PASS|FAIL`；三维结果与 G 层分列；引用本指南 §1–§4 的冻结口径。
- 数值：`S_ss` 必须能从原始 log 逐值复算；表格与 JSON 不得四舍五入到改变判定的程度；`C_ss` 保留 4 位小数。
- 负对照至少覆盖：`TB_SLOTFREE_AS_PRODUCTION`、`93_75_SINK_AS_103_79`、`SYNTHETIC_AS_NATURAL`、`3FRAMES_AS_4FRAMES`、`G25_AS_G0`、`MODEL_AS_RTL`、`AGGREGATE_AS_PERSTREAM`。
- 回退：删除/忽略本任务目录即回到 P4 冻结态；不改生产源，无需 RTL 回退。

## 7. 时间/次数冻结（本任务专属，理由：全尺寸 4 帧单次约 22 min）

| 包 | 全尺寸 vsim | 单次硬超时 | vsim 墙钟上限 | 角色墙钟 | 工具调用 |
|---|---:|---:|---:|---:|---:|
| P1 开发 r0 | ≤2 | 2700 s | ≤90 min | ≤120 min | ≤40 |
| P1 开发 r1 | ≤2 | 2700 s | ≤95 min | ≤115 min | ≤40 |
| P1 综合测试 r0 | ≤1 | 2700 s | ≤30 min | ≤60 min | ≤35 |
| P1 综合测试 r1 | ≤1 | 2700 s | ≤40 min | ≤75 min | ≤35 |
| **P1 综合测试 r1b（gate correction，0 重跑）** | **0** | — | **0** | **≤20 min** | **≤10** |
| **P2 开发（coregap：1 帧 stage probe ×2 + ≤1 retry）** | **≤3（1 帧）** | **1500 s** | **≤55 min** | **≤110 min** | **≤40** |
| **P2 综合测试** | **≤1（1 帧）** | **1500 s** | **≤20 min** | **≤60 min** | **≤35** |
| **P2 文档重冻 r1（0 sim，续原 P2）** | **0** | — | **0** | **dev ≤30 / tester ≤20 min** | **15 / 10** |
| **P3 开发（sink/transport 模型，0 sim）** | **0** | — | **0** | **≤25 min** | **≤20** |
| **P3 综合测试** | **0** | — | **0** | **≤20 min** | **≤20** |
| P4 开发 | 0 | — | 0 | ≤45 min | ≤25 |
| P4 综合测试 | 0 | — | 0 | ≤25 min | ≤25 |

- 预检 run 必须 ≤300 s 且标 `precheck`，不得计入 4 帧证据；P2 的 1 帧 stage probe 是**计数器探针**，不得当 4 帧稳态证据。
- 超时 / `SS_STALL` / `SS_STALL_COLD` / `B11_FULL_TIMEOUT` / 丢帧 / 自检 bad>0 → `partial`/`not_proven`，**不得**用 2/3 帧冒充 4 帧。
- **P1 累计预算（已收口）**：全尺寸 vsim 4/6（r0 2 次 + r1 2 次）、vsim 墙钟 86.1/200 min、开发 calls ≤80/110、开发 wall ≤150/300 min。P1 不再重跑；`dup` 为门槛措辞缺陷，按 r1b gate correction 处理，不占修复轮。
- P1 r1 的 `MAX_CYCLES` 用 `-gMAX_CYCLES=60000000`（参数覆盖，不改源码）；4 帧实测 34.87M/33.86M cycles，1962.4 s/1802.0 s，2700 s 未触发。
- P2/P3/P4 在 P1 r1b PASS 前保持 blocked；预算不在本表之外自动扩展。

## 8. 已冻结 / 待确认 / 不适用

- **已冻结**：几何/打包/CFA/位深；G0=77.76 MB/s/6.25M cycles；G25 仅参考；`S_ss=(S_23+S_34)/2`；`sink_limited` 门槛 50%；93.75 TB 上限；raw band 2,594,706 B；生产核帧串行 + 2 槽 + 丢帧语义；**`dup` 只记录、不作完整性门槛（裁决 A）**；内容标签；不跑 TD/板卡。
- **待确认**：自然场景图（`img102`/`img105`）作为派生源是否满足用户的「自然图像」口径（默认允许，标签从严）；**P2 r0 已判 `conditional`（A+H 6,008,078 算术闭合、包络 45.034%，非 G0 闭合），doc refreeze r1 待做**；P3 sink headroom 仅是模型，raw band ≥103.79 MB/s 仍未实现。
- **不适用（附理由）**：G2（无综合/布线/时序/资源，TD=0）；G3（无 bitgen/CWC/下载/Flash）；G4（无板级/真实接口/稳定性实测）；HDMI/UART 电气、RK/NPU、双路同步、生产 slot-free/pacing（降为后续主题）。

## 9. 三维检查边界（交 dev-plan 验收）

- **functional**：内容可信度与标签、4 帧完整性、内容自检、`S_ss/tail/sink_limited/G0` 可复算、P2 core 计数器/模型校准/方案矩阵、P3 sink 速率账。
- **engineering**：DUT 0 修改、TB 白名单/diff（P2 仅只读 tap）、独占库与 ini、manifest 覆盖、命令/超时/墙钟记账、写范围。
- **system**：core-bound 归因（N/L 的 core_interval vs export）、187.5 MHz 单核边界、无 TD/板卡的时序声明、sink 不是主约束、生产 slot-free/pacing = `not_run`（后续主题）。
- 文档/内容包不套无关硬件流程；P2 用真实 DUT 的 **1 帧 stage probe** + 校准模型（不是 4 帧稳态）；P3 为 **0-sim 模型**，不得把模型/探针说成实测 G0。
