# 开发计划 — 1080p30 G0 生产前提收口（run `20261026-143924_fpga-1080p30-g0-production`）

- 1 个主要可验收目标、4 个正式包、两级（需求→工作包）；默认 BATCH_SIZE=1。**run 已收尾（finished）**：P1 r1b PASS → P2 r0/r1 PASS（`conditional`）→ P3 r0 PASS → P4 r0 PASS；run 级 headline **`G0_not_closed`**。不再开新包。
- P1 已完成 r0/r1 两轮实测：4 帧完整、可复算；自然内容 N `S_ss=7,475,240`、L `S_ss=6,986,952`，**核心吞吐是主瓶颈**。r1 的唯一 FAIL 子句 `dup=0` 是门槛语义缺陷（内容统计量），按 2026-10-26 裁决 A 改为「只记录」，P1 以 manifest-r1 转 PASS，不重跑、不占修复轮。
- **P2 已按新证据重排**：由「生产 slot-free」改为「core 吞吐 gap 闭合/方案选择」（`T10.ss-g0-prod-coregap`）；生产 slot-free 降为后续主题（不是本轮阻塞项，因为 P1 已证明 core 才是主约束）。
- 所有包只做离线仿真/模型/报告；TD/板卡/COM/JTAG/RK=0；不改生产源、旧 run、tasks.json、docs、work、.agents。

## 0. 包总表

| task_id | 问题/产物 | 实际工作树/允许写路径 | 依赖 | functional | engineering | system | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| `T10.ss-g0-prod-content` | 自然/低照内容 4 帧锚点；**已实测**；r1b 仅 gate correction | 新 run `T10.ss-g0-prod-content/**` + `%TEMP%\opencode\ss-g0-prod-content\**` | P4 基线 | 内容/4 帧/S_ss/G0/自检 | DUT 0 改、TB 白名单、独占库、manifest | 内容→DUT 字节映射、scope | G0,G1 | **ready（r1b gate correction，0 重跑）** | 派原 tester |
| `T10.ss-g0-prod-coregap` | core 吞吐 gap 量化 + go/no-go；**r0/r1 PASS，conditional** | 新 run `T10.ss-g0-prod-coregap/**` + `%TEMP%\opencode\ss-g0-prod-coregap\**` | P1 r1b PASS | 方案量化/模型校准/probe | 只读 RTL、TB 只读 tap、manifest | 187.5MHz 单核/无 TD 的时序边界 | G0,G1 | **PASS（r1 文档重绑 `803d3efb…`）** | 已完成 |
| `T10.ss-g0-prod-sink` | sink/transport headroom **模型**（0 sim）；raw band 单列 | 新 run `T10.ss-g0-prod-sink/**` + `%TEMP%\opencode\ss-g0-prod-sink\**` | P1 PASS | 速率账/模型锚点 | 模型仅 run 内、manifest | transport 边界、行为 DDR、无板级 | G0 | **PASS r0（`de8a5cff…`）** | 已完成 |
| `T10.ss-g0-prod-verdict` | 合并判定 + scope + 缺口 + 用户决策 + 恢复入口 | 新 run `T10.ss-g0-prod-verdict/**` | P1+P2-r1+P3 均 PASS | 判定与证据一致 | 哈希绑定/无新跑 | scope 不外推 | G0 | **PASS r0（`8460fb8d…`，9 artifacts）** | 已完成（run finished） |

> 包内操作是清单，不另建子任务；机械归档/哈希不建包。四个包都计入本轮上限（4）。
> **包替换记录**：原 `T10.ss-g0-prod-slotfree`（生产 slot-free）**不在本轮 4 包内**——P1 实测已证明主约束是 core 吞吐（N core_interval 7.475M vs export 3.355M；L 6.987M vs 4.313M），生产 slot-free 只能在此之上再加惩罚，不是当前瓶颈。该包降为后续主题（见 §5），由 `T10.ss-g0-prod-coregap` 替换，**没有新增第 5 包**。

## 1. P1 `T10.ss-g0-prod-content`（ready，本轮唯一派发）

**要回答**：在**不是合成 C1/comp 代理**的内容上，1080p30 的 4 帧稳态是否还能拿到可信的 `S_ss`？若不能，卡在哪（sink / 内容 / 帧完整性）？

**允许写**：`workflow/runs/20261026-143924_fpga-1080p30-g0-production/T10.ss-g0-prod-content/**` 与 `%TEMP%\opencode\ss-g0-prod-content/**`。只读：项目其余全部、`C:/Windows/Web/Screen/`（只读一次并复制入 run）。
**禁止**：改 12 个 DUT 源、r0 冻结 TB/内容源/生产源/旧 run；TD/板卡；网络；批量删除。round1 只允许**新增** `src/tb_ss_4run_wd.v`（看门狗白名单见下），不改 r0 TB。

### round1 裁决（2026-10-26，r0 FAIL 后；完整记录见 `round1-ruling.md`）

- **r0 事实**：综合测试 FAIL **仅 A3**；A1/A2/A4/A5 与 engineering/system 通过；N/L 均在 `SS_STALL frame=1 cycles=12,000,001 exported=0` 结束，无 stats；测试者独立复现首帧导出下界 N 12,440,065、L 12,901,543。实质 `G0_not_proven`，无内容造假/自检失败。
- **裁决 1（允许新 TB，仅改看门狗）**：`WD_LIMIT=12,000,000` 是 TB 活性守卫，不是 G0/生产门槛；12M 把冷启动（首帧导出）与稳态（6.25M 间隔）混为一谈。round1 允许**新 TB 副本** `src/tb_ss_4run_wd.v`（不改 r0 副本、不改 DUT），采用两段式：`WD_LIMIT_COLD=20,000,000` 锚定 `t_sof(1)`（`st_exp==0` 时），`WD_LIMIT=12,000,000` 锚定 `last_exp_t`（`st_exp>0` 时）。`SS_STALL_COLD`/`SS_STALL` 均 `B11_FULL_RESULT pass=0`、均按 `partial`。**不取消看门狗、不放宽稳态 guard、不改 DUT、不 force/deposit。**
- **裁决 2（内容类别）**：**N 与 L 都必须完成 4 帧**，不接受只做 N 或只做 L。理由：N 是自然场景主锚点；L 压缩比仅 1.2:1（最接近 raw band/sink 边界），是第二约束的唯一探针。两类各 1 次全尺寸（约 34–35M cycles / ≈2,000 s）。
- **裁决 3（G0 口径）**：4 帧未完成前一律 `G0_not_proven`；完成后按指南 §3 计算，`L_cold=t_exp(1)` 单列、不进 `S_ss`；不得把 12–13M 冷启动称作 G0 失败，也不得用 r0 的 derived≈7.48M/6.98M 代替实测。若 N 实测 `S_ss>6.25M` → `G0_not_closed`；若 L `tail_frac≥50%` → 按冻结规则 `G0_not_proven`，并必须填 `bottleneck_attribution`（core vs export）。
- **裁决 4（A3 不降级）**：不接受把 A3 改成「partial 可接受」。A3 仍要求 N/L 各 4/4；本次只修 harness，不改门槛。若 round1 仍不完整，P1 在最多 3 轮后以 `partial`/`G0_not_proven` 收口，P2/P3 保持 blocked。
- **裁决 5（勘误）**：指南 §3 的 `103.79 MB/s = 5,000,000 cycles` 改为 **4,687,500 cycles（25.0 ms）**；百分比 75.0% 不变。该勘误不影响任何 G0 判定。

### 步骤（5）

1. **内容源审计（有界）**：复核 request/input-index 已列的候选（C1、C2、comp、6 张 board PNG、`_scratch`、`C:/Windows/Web/Screen/img102.jpg`、`img105.jpg`），最多 3 次本地读取；每项分类并写 `content-audit.json`：`real_sensor_raw` 不存在（附检索命令与结果），board PNG = UI 截图，Bloom 图 = 抽象渲染；记录来源/SHA/尺寸。**不得**把 UI/合成/渲染图称自然场景。
2. **派生两类锚点**（各 4 帧、同帧重复，稳态窗口）：
   - **N**（自然）：`img102.jpg`（6400×4000 黄昏雪山湖面）→ crop/scale 1920×1080 → 声明的 gamma/线性化 → RGGB CFA → 10-bit 饱和 → packed RAW10；标 `natural_scene_image` + `proxy_not_natural_raw` + `not_sensor_raw` + `proxy_not_worst`。
   - **L**（低照）：`img105.jpg`（1920×1080 夜景星轨/栈桥）同流程；标 `low_light_natural_scene` + 同上 proxy 标签；记录暗部占比、饱和像素比、是否加噪声。
   - 产出 `raw40_n.hex`/`raw40_l.hex`（518,400 行）、`raw_n.bin`/`raw_l.bin`（2,592,000 B）、`content-map.json`（源 SHA、派生参数、逐帧 SHA/CRC、geometry、位序、CFA）。
   - 若某图复核后**不是自然场景** → 淘汰该图并降级为 `synthetic_natural_texture`（程序化 1/f+边缘+低照），标签仍 `proxy_not_natural`；**不得**为了凑「自然」改标签。
3. **字节级自检**：从 hex 反解→重打包，`mismatch=0`；`zlib.crc32(bin)` 与 DUT 导出头 `raw_crc` 一致；geometry 1920×1080/2400/518,400；每类 4 帧（同图）SHA 固定。
4. **2 次全尺寸 4 帧 run**（N、L 各 1）：冻结 `tb_ss_4run.v` 副本 + 12 DUT 源副本（逐字节核对 SHA）；`FRAMES=4, CONTENT=2, PACING=0, SINK=1, CAPTURE=0, +RAW40=<class>`；独占库/ini/日志；硬超时 2700 s。要求 `cap=enc=exported=4`、`read=518,400`、`raw_drop=cmp_drop=geom=err=dup=wd=0`、`SS_RAW_MATCH bad=0 checked=518400`、header CRC 自洽；任一不满足 → 该 run `partial`，不得 4 帧结论。
5. **计算与收口**：按设计指南 §3 从原始 log 重算 `S_ss/tail/tail_frac/sink_limited/C_ss/margin/G0`；写 `out/content-verdict.json`（每类一行 + 逐帧压缩比/字节数）、`result-r0.md`、`lessons-r0.md`、`manifest-r0.json`（含 `commands.jsonl`、`stopped_modifying=true`、`active_commands=0`）。**G25 只作参考列**。

**round1 执行变体（覆盖步骤 4/5 的产物命名；内容/模式不变）**：

- **不重做步骤 1–3**：直接复用 r0 的 `raw40_{n,l}.hex` / `raw_{n,l}.bin` / `content-audit.json` / `content-map.json`，SHA 必须与 r0 相同（任何变化 → 返工并说明）。
- **只新增，不改 r0 冻结件**：`src/tb_ss_4run_wd.v`（新 TB）、`src/DIFF-r1.md`（逐行 diff + 白名单）、`sim/logs/{n,l}-r1.log`、`sim/caps/{n,l}-r1.{stats,evt,hdr}`、`out/content-verdict-r1.json`、`out/run-status-r1.json`、`result-r1.md`、`lessons-r1.md`、`manifest-r1.json`（`repair_round=1`、`previous_manifest=manifest-r0.json` + `e55e7965…`）。**不得**覆盖 r0 的 log/caps/JSON/manifest/TB。
- **TB 白名单（仅这 5 项）**：① 新增 `localparam integer WD_LIMIT_COLD = 20000000;`；② 新增 `st_exp==0` 时按 `t_sof[1]` 锚定的 `SS_STALL_COLD` 分支；③ 原 `WD_LIMIT` 分支加 `st_exp>0` 条件并保留 `SS_STALL`/`pass=0`；④ `kind=exp` EVT 行追加只读 `bytes=%0d`（`st_expb`）；⑤ 注释/命名。其余逐字节不变：drive_frame/几何/时钟/复位/PACING/SINK/FRAMES/CONTENT/`ss_pass` 表达式/drain/EVT 其他字段/`MAX_CYCLES` 源码值（用 `-gMAX_CYCLES=60000000` 覆盖）。
- **运行**：同 `FRAMES=4 CONTENT=2 PACING=0 SINK=1 CAPTURE=0`、同 `raw40_{n,l}.hex`（SHA 不变）、`-gMAX_CYCLES=60000000`、硬超时 2700 s；每类 1 次，共 2 次。
- **元数据修正（r0 OBS）**：新 JSON 的 `P1_answer` 必须写「0 帧导出/稳态未测」或基于 r1 实测的真值；`run-status-r1` 用 `stats_rows_present`（有 `SS_STATS` 行才 true）替代 `stats_exists`，并保留 `stats_file_created` 原始事实。r0 旧字段不改写（保持冻结），在 `result-r1.md` 说明其已被 r1 取代。
- **派生值**：r0 `result` 的 7.48M/6.98M 只能在 `derived_not_measured` 标签下引用；r1 必须用实测 `t_exp(2..4)`；`t_pub(1)` 精确值 1,607,996（不要用 1,608,000）。

### P1 r1b 收口（2026-10-26 裁决 A；完整记录见 `r1b-ruling.md`）

- **r1 实测成立**：N `S_ss=7,475,240`（25.083 fps / 65.015 MB/s / **G0 −16.3906%**，`sink_limited=false` → `G0_not_closed`）；L `S_ss=6,986,952`（26.836 fps / 69.558 MB/s / **G0 −10.5475%**，`tail_frac=61.7249%` → `G0_not_proven`）。两类 `bottleneck_attribution=core_interval`（N 2.23× export、L 1.62×）。headline `G0_not_proven`。测试者自有库重跑 N 逐字节一致。
- **`dup` 裁决 A**：`st_dup_words` 是「相邻 256-bit 读字载荷逐位相同」的**内容统计量**（N 3,896、L 568，可由内容逐字精确预测、帧边界 0；`read=518,400`、`ar=r`、CRC/自检干净），不是重复读/重传/完整性错误。A3 改为 `raw_drop=cmp_drop=geom=err=wd=0`，`dup` 只记录；guide §3 同步。`ss_pass=0` 是 TB 表达式含 `st_dup==0` 的后果，**不是任务失败**。
- **r1b 复测**：不重跑、不改候选；由原 P1 tester 在 manifest-r1 上重评 A1–A5（8 项已过 + `dup` 记录），出 `test-reports/T10.ss-g0-prod-content-r1b-integrated.md`，PASS 绑定 `manifest-r1.json`（`e306ed42…`）。预算 ≤10 calls / ≤20 min / 0 全尺寸。
- **非阻断 OBS**：`result-r1` 的 "32 px" 应为 16 px（20 B 载荷/256-bit 字）；`content-verdict-r1.P1_answer` 的 `dup_semantics` 悬空引用；r1 未新增负对照文件——测试者已在 r1 报告 §8 自建 4 条控制（白名单反向重建、dup 内容重建、derived/measured 分离、`L_cold` 不进 `S_ss`），P4 必须引用这 4 条，不得声称「未做负对照」。
- **P1 预算收口**：全尺寸 4/6、vsim 86.1/200 min；**P1 不再重跑**。

### 验收门槛（综合测试按此判 PASS/FAIL）

| # | 门槛 | 判据 |
|---|---|---|
| A1 | 内容审计完整、无冒充 | 每个候选有分类；`real_sensor_raw` 明确不存在；UI/渲染/合成未标自然；派生类标签齐全 |
| A2 | 4 帧内容冻结 | 每类 2,592,000 B×4 帧、SHA/CRC、hex→bin mismatch 0、geometry 对 |
| A3 | 4 帧完整（N **和** L 各一） | 每类：`t_exp(1..4)` 全非空、`cap=enc=exported=4`、`read=518400`、有 `SS_STATS` 行、`raw_drop=cmp_drop=geom=err=wd=0`（实测）、`SS_RAW_MATCH bad=0 checked=518400`、header CRC ok。以 `SS_STALL_COLD`/`SS_STALL`/`MAX_CYCLES`/硬超时结束 → 该类 `partial`，不算 4 帧；只有一类完整 → A3 FAIL。**`dup` 只记录、不参与本门槛**（2026-10-26 裁决 A） |
| A3a | 冷启动单列 | `L_cold=t_exp(1)` 与 `L_cold/6,250,000` 必须报告；冷启动 >6.25M 不得写成 G0 失败或 G0 通过 |
| A3b | 瓶颈归因 | 每类填 `bottleneck_attribution`（`core_interval` vs `export_time`）；`sink_limited=true` 时不得声称 sink 是唯一约束 |
| A4 | 指标可复算 | 测试者独立解析 log 得到与 `content-verdict(-r1).json` **逐值相等**的 `S_ss/tail/tail_frac/sink_limited/G0`；DUT 12 源 SHA 与 P1 基线相同 |
| A5 | 判定诚实 | 每类 `G0` ∈ 三选一且与 `sink_limited`/`S_ss` 一致；写明「不得外推到传感器 RAW/全内容/最坏/板级」；G25 未进 headline |

- **FAIL 条件**：A1–A3b 任一不成立，或 A4 有不可解释差异，或 A5 出现「合成/派生当真实 RAW」「3 帧当 4 帧」「G25 当 G0」。**A3 不降级为「partial 可接受」**；r0 的 12M 看门狗问题由 round1 新 TB 修 harness，不是修门槛。
- **不因 G0 未过而 FAIL**（内容类 `G0_not_closed`/`G0_not_proven` 是合法结果）；但 4 帧未完成时 `G0` 只能是 `G0_not_proven`。
- 综合测试必须**独立重跑至少 1 个内容类**（N 优先）1 次全尺寸 4 帧（自有库/日志），并独立解析两次运行的 log；不得只读开发自述。round1 还需核 `tb_ss_4run_wd.v` 的 diff 是否**严格等于**上述 5 项白名单、r0 冻结件 SHA 是否未变。

### 预算/停止

- **r0 已用（实测）**：全尺寸 vsim 2 次（N 712.7 s + L 687.8 s = 1,400.5 s）、预检 1 次（301.7 s，标 precheck）；开发墙钟未单独冻结，按 ≤50 min 记账。
- **round1 开发**：≤40 次工具调用、墙钟 ≤115 min、全尺寸 vsim ≤2、vsim 墙钟 ≤95 min、单次硬超时 2700 s。**估算修正**：request 的「单次约 22 min」对应 P4 的 ~27M-cycle run；r0 实测 12M cycles ≈ 711 s（≈16.9k cycles/s），按 4 帧约 34–35M cycles 推算约 2,000–2,100 s/次，两次约 67–70 min，故给 95 min vsim 墙钟（不是 44 min）。
- **P1 累计（已收口）**：全尺寸 vsim 4/6（r0 2 + r1 2）、vsim 墙钟 86.1/200 min、开发 calls ≤80/110、开发 wall ≤150/300 min。**P1 不再重跑**。
- **r1b（gate correction）**：≤10 calls、≤20 min、0 全尺寸、0 TD/板卡；只由原 tester 在 manifest-r1 上重评，不占修复轮。
- **round1 综合测试（已发生）**：≤35 次、≤75 min、全尺寸重跑 1、vsim 1976.7 s、硬超时 2700 s。
- 停止：ModelSim 不可用 / 无内容源且纹理生成也失败 / 磁盘或 TEMP 不可写 / 连续 2 次无新证据 → `blocked`（带原因、最后路径、恢复入口）；`SS_STALL_COLD`/`SS_STALL`/超时/丢帧 → `partial` + `not_proven`，不空转；**同一 run 不得因同一 stall 反复重跑超过 1 次**。
- r1 已实测完成两类 4 帧，不存在「round1 两类都未完成」的路径；若未来出现新的真实缺口，按 §5 的新包处理，不在 P1 扩预算。
- 既有 B11 布线 SWNS +0.015 与板测阻塞不影响本包（无 TD/板卡）；不得引用为 G2/G4 证据。

## 2. P2 `T10.ss-g0-prod-coregap`（**r0 PASS；`conditional`；doc refreeze r1 待做（0 sim）**）

> **r0 结论**：探针 N 7,476,245 / L 6,979,811（与 P1 r1 帧 1 0.000%）；模型 LOO ≤5%；8 行矩阵；A+H 6,008,078（2.3179 c/B，+4.027%）是唯一 187.5 MHz 算术闭合，包络 **45.034%** → `conditional`；仅提时钟 224.3 MHz 仅 0.006% 算术余量（b11 WNS +0.015@187.5，不可信）；双核 per-stream 不变。headline 仍 **`G0_not_closed`**，不证明 G0 闭合。
> **重冻要求（`p2-obs-ruling.md` §2）**：同一 P2 开发/测试者、0 sim、manifest-r1；只修 R1–R9（DIFF-probe.raw 54 行、H note、assumptions c_ab、C1 物理口径、B/C assumed、参照物、OBS-5 登记、P1 70 artifacts 更正）。不改模型算术/矩阵/`conditional`/G0。**必须在 P4 开始前完成**。

> **放行依据**：P1 r1b 综合报告 `test-reports/T10.ss-g0-prod-content-r1b-integrated.md`（PASS，manifest-r1 `e306ed42…`，N `G0_not_closed` −16.3906%、L `G0_not_proven` −10.5475%，G1 PASS）。P2 用**新开发 + 新测试者**，不复用 P1。

**要回答**：P1 实测每帧 core_interval N=7,475,240、L=6,986,952 cycles（G0 需 6,250,000，缺 16.39%/10.55%）。在 **187.5 MHz、单核、PH1P100（ERAM ≤300、LUT6 ≤71,680）** 边界内，当前 b11 core 的哪些改造能闭合该缺口？哪些只是把代价转移到时序/资源？给 **go/no-go**，不做 TD/板卡、不改生产 RTL。

**允许写**：`T10.ss-g0-prod-coregap/**` + `%TEMP%\opencode\ss-g0-prod-coregap/**`。只读：b11 `changed-src`、P1 冻结内容/报告、P2 可行性报告。
**禁止**：改生产 core/top、TD/综合/布线/bitgen/CWC/板卡、网络、批量删除；不得把模型/估算写成实测。

### 步骤（5）

1. **冻结输入与模型骨架**：读 `a1_deflate_core.v`（3-byte hash 1024 entries、`MAX_MATCH=258`、`MAX_DIST=2048`、`MAX_BLOCK=4800`、单候选）、`a1_frame_top.v` 的 256-bit→8-bit 喂入、P1 r1 指标与压缩比。定义 `cycles/B`、`symbols/B`、`extension share`、`per-symbol overhead` 四个量，写 `model/coregap_model.py` 骨架与假设清单（每条标 `measured`/`derived`/`assumed`）。
2. **1 帧 stage probe（run 内新 TB，只读 tap）**：复制 12 DUT 源 + r1 TB；仅加只读层次引用/`CORE_STAGE` 打印：`dut.u_a1.u_core.stat_{blocks,fixed,stored,literals,matches,cand_aborts,stall,max_match,max_dist}` 与 `core_interval`；`FRAMES=1 CONTENT=2 PACING=0 SINK=1 CAPTURE=0`，N/L 各 1 次全尺寸（每次约 700–750 s，硬超时 1500 s）；不改 DUT、不 force、不改 drive/几何/时钟/`ss_pass`；写逐行 diff + 白名单。探针周期必须与 r1 帧 1 的 `t_enc(1)-t_pub(1)`（N 7,476,245 / L 6,979,811）在 ±2% 内，否则探针无效。
3. **模型校准**：用 N/L 探针计数器 + 冻结 comp 锚点（355,261 cycles/153,600 B = 81.067 MB/s）+ C1 `S_ss=4,677,970` 拟合每符号/每字节/扩展成本；要求对 N/L/C1/comp 的预测残差 ≤5%，并做 leave-one-out 交叉验证；不达标 → `blocked`，不得猜。
4. **方案矩阵（≥6 行，全部标证据类型/置信度）**：
   - A `2-symbol/2-position` 匹配/扫描引擎（每周期处理 2 个位置或 2 个符号）；
   - B hash 1024→4096/8192（更多候选/更长匹配，减少 symbols/B）；
   - C 窗口 2048→8192（提高匹配率，ERAM/比较器代价）；
   - D 深流水/重定时以支撑 200/209.6/224.3 MHz（分别对应 L、N、N+余量）；
   - E 仅提时钟（209.6/224.3 MHz，不改 RTL）；
   - F 双核（per-stream 分摊）；
   - G 换算法/换核（超出本轮，只作对照）。
   每行给：所需 cycles/B、N/L 预期闭合比例、ERAM/LUT/REG 增量估算、对照 b11 Routed `WNS=+0.015@187.5` 的时序风险、置信度、单独是否足够（yes/no/only-in-combination）。
5. **go/no-go 与收口**：按冻结规则给 `closable_at_187_5`：
   - `yes`：存在单方案或组合，估算 N `cycles/B ≤2.411`（L 自动满足），资源 ≤300 ERAM 且 LUT6 ≤71,680，**不需提时钟**（187.5 MHz 可布），模型不确定度 ≤10%；
   - `conditional`：只有叠加时钟提升（≥200 MHz，需重流水）或资源逼近上限（>270 ERAM）才达到，或模型不确定度 >10%；需原型 + TD 才能判定；
   - `no`：即使 224.3 MHz + 最优资源方案也达不到 2.411，或必须换核/换算法。
   写推荐路径与下一步所需证据（原型 + TD + 板级）；写 `out/coregap-verdict.json`、`result-r0.md`、`lessons-r0.md`、`manifest-r0.json`。**不实施 RTL 改动、不跑 TD**；若结论是 no，明确 `G0_not_closed` 与用户决策项（换核/加时钟/接受 not_closed；降档需用户另行决定，本计划不主推）。

### 验收门槛

| # | 门槛 | 判据 |
|---|---|---|
| E1 | 输入冻结/DUT 0 改 | 12 DUT 源与 P1 基线逐字节相同；TB 仅只读 tap + `CORE_STAGE`，diff 在白名单内；无 `force/deposit`；无 TD/板卡 |
| E2 | stage probe 有效 | N/L 各 1 帧完整；9 个 core 计数器有值；探针周期 vs r1 帧 1 ±2%；否则探针无效、不得用于模型 |
| E3 | 模型可校准 | N/L/C1/comp 四点残差 ≤5%，leave-one-out 通过；每个系数标 `measured/derived/assumed` |
| E4 | 方案矩阵可决策 | ≥6 行；每行有 cycles/B、闭合比例、资源/时序风险、置信度、单独是否足够；算术可复算 |
| E5 | go/no-go 明确 | 三选一 + 数值依据 + 所需下一证据；不得把模型说成 TD/实测；不得声称 G0 已闭合 |

- **FAIL/blocked**：E1/E2 不成立 → `blocked`（探针/输入问题）；E3 不达标 → `blocked`（模型不可校准），不得用猜测矩阵；E4/E5 不成立 → FAIL。**不因结论是 no 而 FAIL**（no 是合法结论）。
- 预算：开发 ≤40 calls、≤110 min、1 帧全尺寸 **≤3（2 次证据探针 + 最多 1 次 harness-only 重试；第 3 次不得作为新证据）**、vsim 墙钟 ≤55 min、单次硬超时 1500 s；测试 ≤35 calls、≤60 min、probe 重跑 ≤1、vsim ≤20 min。新开发/新测试者，**不复用 P1**。

### 规划先验（不是证据，P2 必须证实/推翻）

- 核心在 comp 锚点可达 **2.313 cycles/B**（81.067 MB/s），说明 2.411 cycles/B 的 G0 目标不是结构性不可达；但自然内容实测 **2.884 cycles/B**（N），差的 0.47 cycles/B 是内容相关的符号/扫描开销。
- b11 Routed `WNS=+0.015 ns @187.5 MHz` 意味着当前关键路径约 5.318 ns（≈188.0 MHz）；**仅提时钟到 209.6/224.3 MHz 不可信**，必须先做结构性流水。
- 双核不提高 per-stream（P2 可行性报告：per-stream 链级 75.684 MB/s，双核仍同值），且 ERAM 231–289/300、双核时序 `unproven`；F 行预期 no。
- 因此规划先验倾向：**`conditional` 或 `no`**——单靠参数/时钟不够，需要 2-symbol/更宽扫描 + 更大 htab 的结构性改造，且必须由专门实现 + TD 证明；本轮不实施。

## 3. P3 `T10.ss-g0-prod-sink`（**PASS r0（`de8a5cff…`，5 artifacts，0 sim）**；sink headroom 模型）

> **验收事实**：测试者独立从 P1 原始 EVT 差分复算 comp B/帧 N 1,677,336 / L 2,156,300；33.33 ms 需求 50.32/64.69、25.0 ms 需求 67.09/86.25，均 <93.75（最紧 L@25 ms 占 92.0%）；raw band 93.75→5,189,412 cycles/83.03%，103.79→4,687,500/75.0%，25 ms 缺口 +10.707%；生产 sink ≥103.79 未证；G0 headline 不变。7 项 OBS 均非阻断（P4 引用时以报告 §7 为准）。

> **放行依据**：P1 r1b PASS（manifest-r1 `e306ed42…`）+ P2 r0 PASS（`conditional`，headline `G0_not_closed`）。P3 只读 P1 实测字节与 P2 结论，不绑定 P2 候选算术；0 sim/0 TD/0 板卡。

**要回答**：在 P1 的实测码流下，冻结 93.75 MB/s sink 是否是约束？raw band 的 ≥103.79 MB/s 生产需求还差多少、是否影响本内容路径？

**允许写**：`T10.ss-g0-prod-sink/**` + `%TEMP%\opencode\ss-g0-prod-sink/**`。只读 P1/P2 冻结件。**0 次 vsim/TD/板卡。**

### 步骤（4）

1. 冻结三档账：comp 流 N 1,677,336 B/帧（1.5453:1）、L 2,156,300 B/帧（1.2021:1）；raw band 2,594,706 B/帧；速率 93.75 / 103.79 / 187.5 MB/s 对应 cycles/ms/%G0（93.75→5,189,412/27.677 ms/83.03%；103.79→4,687,500/25.0 ms/75.0%；187.5→2,594,706/13.84 ms/41.5%）。
2. 由实测字节算 comp 流的 sink 需求：33.33 ms → N 50.32 / L 64.69 MB/s；25.0 ms → N 67.09 / L 86.25 MB/s。结论：**两者都 <93.75**，冻结 sink 对实测 comp 路径有余量；sink 不是 P1 的瓶颈。
3. raw band 单列：≥77.84 MB/s（33.33 ms，G0）在 93.75 下可满足；≥103.79 MB/s（25.0 ms，25% 余量）**未实现/未证**，且只对 RAW fallback（stored）路径有意义；不得把 93.75 说成 103.79，也不得把 raw band 需求套到 comp 流。
4. `result-r0.md` 三级边界（模型/生产实现/板级）+ 负对照 `93_75_SINK_AS_103_79`、`RAW_BAND_AS_COMP_STREAM`、`MODEL_AS_RTL`；manifest 冻结。

### 验收门槛

- C1 三档账与 comp 需求算术可复算；C2 明确 93.75 对实测 comp 有余量、对 raw band 25 ms 不足；C3 不声称生产 sink 已实现/已证；C4 0 sim/0 TD/0 板卡；C5 结论不改变 G0（sink 不是 P1 的约束）。不达标 → FAIL；不得用旧 P3 的 4 帧 sink run 冒充。

## 4. P4 `T10.ss-g0-prod-verdict`（**PASS r0（`8460fb8d…`，9 artifacts，0 sim）；run 级 headline `G0_not_closed`**）

> **放行依据**：P1 r1b `e306ed42…` + P2-r1 `803d3efb…` + P3 r0 `de8a5cff…` 均 PASS。
> **headline 口径**：`G0_not_closed`。`sink_limited` 澄清（`p4-release-ruling.md` §2 / guide §3）：`tail_frac≥50%` 只是诊断旗标；只有 sink 忙碌率 `busy=export_time/S_ss ≥ 0.95` 才阻断为 `G0_not_proven`。P1 L 类 busy=4,312,600/6,986,952=61.72% → 实际 core-bound → `G0_not_closed`（−10.5475%），N busy=44.88% 同类（−16.3906%）。P1/P3 报告里的 `G0_not_proven` headline 在 run 级被本澄清修正（P2 headline 已是 `G0_not_closed`），**数值/证据不变、不重写原报告**；P4 必须显式说明。
> **必写六条**：见 §4 步骤 3 与 `p4-release-ruling.md` §3.1（core+187.5 不能闭合；A+H 6,008,078/2.3179/+4.027% 仅算术、包络 45.034%→conditional；仅提时钟不可行；双核不提 per-stream；P3 93.75 够 comp、raw band 未证；用户不降档、需决定 core 改版/换核/接受边界）。

**要回答**：合并 P1 内容实测、P2 core gap go/no-go、P3 sink headroom，本轮 G0 headline 与 scope 是什么，用户需要决定什么？

### 步骤（5）

1. 收集 P1 r1b、**P2-r1**、P3 的 manifest/报告/JSON，逐项复算 SHA，列「证据→结论」绑定表；P2 必须绑 r1（`manifest-r1`），不得用 r0 的旧 DIFF/C1 数字。
2. 合并表：N/L 的 `S_ss/L_cold/tail/sink_limited/bottleneck/G0`；P2 的 `closable_at_187_5`、A+H 6,008,078（2.3179 c/B，+4.027%）、包络 45.034%、单 H −0.17%、时钟/双核行；P3 的 comp/raw band 账；G25 单列 ref。
3. 判定：**`G0_not_closed`**（N 7,475,240、L 6,986,952 均 >6.25M，core-bound）。**必须显式写 `sink_limited` 澄清**：L 的 `tail_frac=61.7249%` 只是诊断旗标，sink 忙碌率 `busy=4,312,600/6,986,952=61.72% <0.95`，sink 未 gate → L 按澄清判 `G0_not_closed`（−10.5475%），不是 `not_proven`；N busy=44.88% 同类。P1/P3 报告的 `G0_not_proven` headline 在 run 级被修正（P2 headline 已是 `G0_not_closed`）、数值/证据不变、不重写原报告。必须写清六条：① 当前 core+187.5 MHz 不能闭合自然内容（N −16.3906%、L −10.5475%）；② A+H 是唯一 187.5 MHz 算术闭合但包络 45.034% → `conditional`，**不是 G0 闭合、不得写 feasible**；③ 仅提时钟 209.6/224.3 MHz 不在 b11 时序能力内（WNS +0.015@187.5 ≈188.0 MHz；224.3 仅 0.006% 算术余量）；④ 双核不提高 per-stream；⑤ P3：93.75 对实测 comp 有余量、raw band ≥103.79 未证；⑥ 用户坚持 1080p30、不降档，需要决定：投入 core 结构改版（A+H，原型+TD+板级）／换核或换算法／接受其他边界。**降档需用户明确，P4 不主推。**
4. scope tuple = {content: 自然场景派生 Bayer（非传感器 RAW）；pacing: TB `wait_slot_free`；sink: 93.75 TB 代理；DDR: 行为 256-bit PAXI；core/clock: 单核 187.5 MHz；stream: 单路}；写剩余缺口、风险、回退与下一次准确启动/恢复文本。
5. 产出 `g0-production-verdict.json` + `result-r0.md` + `handoff.md` + `final-summary.md` + `user-summary.md`（P4 起草；P4 PASS 后原规划复核并正式收尾）+ `manifest-r0.json`。

### 验收门槛

- D1 每个 headline 字段可追到 P1 r1b / P2-r1 / P3 的具体 JSON/行；D2 headline=`G0_not_closed`；D3 six statements 齐全且数值/来源正确；D4 G25 仅参考、不降档；D5 无新增长跑/拼贴；D6 `dup` 只记录、`ss_pass=0` 不当失败；**D7 P2 必须绑 r1（非 r0）**；**D8 不得出现 "G0 closed/feasible" 或把 A+H 写成已实现**；**D9 `sink_limited` 澄清与 L 重分类被显式写明**；**D10 0 sim/0 TD/0 板卡、写范围合规、候选哈希稳定**。

## 5. 依赖、放行、轮数与后续主题

- 顺序：P1 r1b → P2 r0（PASS，`conditional`）→ P3（PASS r0）→ P2 文档重冻 r1（PASS）→ **P4（PASS r0）**；全部收口，不预 spawn、不再开包。
- P2/P3/P4 用**新开发 + 新综合测试者**，不复用 P1；**P2-r1 是例外**：docs-only，续原 P2 开发/测试者。同包 FAIL 才续原开发/原测试，round0 首次验收，最多 3 轮实际修复。
- 预算：P3 dev 17/16 min、tester 49 calls（超 20，已披露，0 sim）；P2-r1 dev/tester 0 sim；**P4 dev ≤25 calls/45 min、tester ≤25/25 min（0 sim）**。P2 累计 ≤70 calls/≤130 min，理由见 `p2-obs-ruling.md` §2。
- 退役包：`T10.ss-g0-prod-slotfree` 不在本轮 4 包内（替换为 coregap）；生产 slot-free/pacing 作为后续主题，待 core 吞吐方案确定后再做，避免在已知主约束之外先做次要项。
- 后续主题（本轮不做，最多 3 条）：① core 结构性改造（2-symbol/更宽扫描/htab/流水）+ 原型 + TD/STA + 板级；② 生产 slot-free/pacing + 生产 sink RTL/PCIe + 板级持续带宽；③ 真实 IMX415 RAW 语料 + 低照噪声 + 最坏内容。
- 用户决策（P2/P4 会给量化依据）：换核/改算法、提时钟（需重流水 + TD）、接受 `G0_not_closed`；**降档需用户明确，不由本轮主推**。

## 6. 收尾（2026-10-26，run finished）

- **四包全 PASS**：P1 r1b `e306ed42…`（70）、P2 r1 `803d3efb…`（49）、P3 r0 `de8a5cff…`（5）、P4 r0 `8460fb8d…`（9）；上游 124 artifacts 绑定 0 mismatch。
- **run 级 headline：`G0_not_closed`**。N 7,475,240（−16.3906%）、L 6,986,952（−10.5475%），core-bound；`sink_limited` 澄清为 `busy≥0.95` 才阻断，L busy 61.72% → `not_closed`。
- **A+H 仅 conditional**（6,008,078 / 2.3179 c/B / +4.027%，包络 45.034%）；单 H −0.17%；仅提时钟（≈188 MHz 能力）不可行；双核不提 per-stream；P3 的 93.75 够 comp、raw band ≥103.79 未证。
- **过程**：P1 r0 看门狗 → r1 harness；r1 `dup` → r1b gate correction（0 重跑）；P2 r0 → r1 文档重冻（0 sim，r0 文档被原地覆盖 OBS-8）；P3/P4 0 sim。超预算（P2 dev 49、P3 tester 49、P4 dev 31）已登记，未改判定。
- **收尾文件**：`handoff.md`、`final-summary.md`、`user-summary.md`；P4 报告 `test-reports/T10.ss-g0-prod-verdict-r0-integrated.md`。
- **下一步（不得说 G0 已闭）**：新 run 做 A+H 独立 RTL 原型（需 TD/时序/资源，本轮未授权），或用真实传感器 RAW 复核 N/L；文本见 `final-summary.md` §8 / `handoff.md` §5。
- 未改 `workflow/tasks.json`、P1–P4 候选/报告、生产源、旧 run；0 TD/板卡/网络。
