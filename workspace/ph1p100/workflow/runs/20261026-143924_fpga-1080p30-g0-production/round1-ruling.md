# P1 round1 规划裁决 — `T10.ss-g0-prod-content`

- run：`20261026-143924_fpga-1080p30-g0-production`；日期：2026-10-26
- 依据：P1 r0 综合报告 `test-reports/T10.ss-g0-prod-content-r0-integrated.md`（FAIL 仅 A3；A1/A2/A4/A5、engineering、system PASS；G0=`not_proven`、G1=PASS）
- 适用：原 P1 开发 round1（同一开发会话）与原 P1 综合测试者 round1（同一测试会话）
- 本裁决**不**改 DUT、不改内容、不改 G0 门槛、不新增角色、不扩 P2/P3。

## 1. 事实认定

| 项 | 认定 |
|---|---|
| FAIL 范围 | 仅 dev-plan §1 A3「N/L 各 4 帧完整」；**不是**内容造假、不是自检失败、不是判定不诚实 |
| 停点 | 两次 run 均 `SS_STALL frame=1 cycles=12,000,001 exported=0`，无 `SS_STATS`；read N 181,202 / L 204,002 |
| 可复现性 | 测试者自有库重跑 N 逐事件逐字节一致；首帧导出下界 N 12,440,065（超 3.667%）、L 12,901,543（超 7.513%） |
| 实质结论 | 缺 4 帧实测 → `G0_not_proven`；r0 的 ≈7.48M/6.98M 只是 `derived_not_measured`，不作为 G0 证据 |

## 2. 裁决：允许 round1 新 TB（仅看门狗）

**理由**：`WD_LIMIT=12,000,000` 是 TB 活性守卫（`localparam`，`last_exp_t` 初值 0），其真实语义是「复位起 12M 内必须完成首帧导出」，把冷启动与 6.25M 稳态门槛混为一谈。修 harness **不改变**任何验收门槛或 DUT 行为，因此不构成放水。

**允许的新 TB**：`T10.ss-g0-prod-content/r0/src/tb_ss_4run_wd.v`（新文件；r0 的 `tb_ss_4run.v` 原样保留，不得覆盖）。

**白名单（逐行 diff 必须严格落在这 5 项内）**：

1. 新增 `localparam integer WD_LIMIT_COLD = 20000000;`（保留 `WD_LIMIT = 12000000`）。
2. 新增冷启动分支：`st_exp == 0 && (cycles - t_sof[1]) > WD_LIMIT_COLD` → 打印 `SS_STALL_COLD` 与 `B11_FULL_RESULT pass=0`、`$finish`。
3. 原稳态分支加条件：`st_exp > 0 && (cycles - last_exp_t) > WD_LIMIT` → `SS_STALL`（文本、行为保持）。
4. `kind=exp` 的 `SS_EVT` 行追加只读 `bytes=%0d`（取 `st_expb`），用于逐帧 `exp_bytes`；不改其他字段。
5. 仅注释/命名/上述行号附近的空行。

**禁止**：改 `drive_frame`/帧间隔/`LINE_GAP`/`FRAME_GAP`/几何/时钟/复位/`PACING`/`SINK`/`FRAMES`/`CONTENT`/`CAPTURE` 语义；改 `ss_pass` 表达式或 `drain`；改 `MAX_CYCLES` 源码值（用 `-gMAX_CYCLES=60000000`）；加其他 `$finish` 路径；`force/deposit/release` DUT 信号；改 12 个 DUT 源；覆盖 r0 的 log/caps/JSON/manifest；把 `SS_STALL_COLD`/`SS_STALL` 当完整 run。

**参数**：`-gFRAMES=4 -gCONTENT=2 -gPACING=0 -gSINK=1 -gCAPTURE=0 -gMAX_CYCLES=60000000`；同 `raw40_{n,l}.hex`（SHA 不变）；硬超时 2700 s；每类 1 次，共 2 次。

## 3. 裁决：N 与 L 都必须 4 帧

- N（自然场景）与 L（低照夜景，压缩比≈1.2:1，最接近 raw band/sink 边界）各 1 次全尺寸 4 帧；只做一类 → A3 FAIL。
- 只允许「同内容 4 帧」的稳态窗口（同图重复），不新增时域变化；该覆盖缺口继续写在报告里。

## 4. 裁决：G0 口径与冷启动

- 4 帧未完成前：`G0_not_proven`（任何类别）。
- 4 帧完成后：按 guide §3；`L_cold=t_exp(1)` 单列、不进 `S_ss`；冷启动 12–13M 既不是 G0 失败证据，也不是 G0 通过证据。
- 若 N 实测 `S_ss > 6,250,000` → `G0_not_closed`；若 `tail_frac ≥ 50%` → 按冻结规则 `G0_not_proven`，且必须填 `bottleneck_attribution`（core_interval vs export_time），不得把 core-bound 说成 sink-bound。
- G25 仍仅参考列；不得降档。

## 5. 裁决：A3 不降级

- A3 仍要求 N/L 各 `t_exp(1..4)` 非空、`cap=enc=exported=4`、`read=518400`、有 `SS_STATS` 行、`drop/dup/geom/err/wd` 实测 0、`bad=0 checked=518400`、header CRC ok。
- 以 `SS_STALL_COLD`/`SS_STALL`/`MAX_CYCLES`/硬超时结束 → 该类 `partial`，不算 4 帧。
- 若 round1 仍不完整：round2 可再修 harness（累计只剩 2 次全尺寸），或由原规划以 `partial`/`G0_not_proven` 收口；P2/P3 保持 blocked。

## 6. 元数据/指南修正清单（round1 必须落实）

| # | 对象 | 修正 |
|---|---|---|
| M1 | `out/content-verdict-r1.json` | `P1_answer` 必须与实测一致（0 帧 → not_measured；4 帧 → 真值）；不得再写「4-frame steady state is obtainable」 |
| M2 | `out/run-status-r1.json` | 用 `stats_rows_present`（有 `SS_STATS` 行才 true）替代 `stats_exists`；保留 `stats_file_created` |
| M3 | `result-r1.md` | 明确 r0 的 `P1_answer`/`stats_exists` 已被 r1 取代；r0 旧文件不改写 |
| M4 | `src/DIFF-r1.md` | 逐行 diff + 白名单 5 项 + 「仅 harness，不改 DUT/门槛」声明 |
| M5 | `manifest-r1.json` | `repair_round=1`、`previous_manifest=manifest-r0.json`（SHA `e55e7965…`）、13 源清单（12 DUT + 新 TB）、artifact 全覆盖 |
| M6 | guide §3 / dev-plan P3 | `103.79 MB/s = 4,687,500 cycles（25.0 ms）`；`5,000,000` 作废（勘误，不改百分比） |
| M7 | 报告派生值 | r0 的 7.48M/6.98M 只能标 `derived_not_measured`；`t_pub(1)` 用 1,607,996，不用 1,608,000 |

## 7. 预算（round1，不重置）

| 角色 | calls | wall | 全尺寸 vsim | vsim 墙钟 | 单次硬超时 |
|---|---:|---:|---:|---:|---:|
| 开发 round1 | ≤40 | ≤115 min | ≤2 | ≤95 min | 2700 s |
| 测试 round1 | ≤35 | ≤75 min | ≤1（N 优先） | ≤40 min | 2700 s |

- P1 累计（r0–r3）：全尺寸 ≤6（r0 用 2）、vsim 墙钟 ≤200 min（r0 用 23.3 min）、开发 calls ≤110、开发 wall ≤300 min。
- r0 已用：2 次全尺寸（1,400.5 s）+ 1 次 precheck（301.7 s，不计 4 帧）。
- **估算修正**：request 的「单次约 22 min」是 P4 ~27M-cycle run 的值；r0 实测 12M cycles ≈ 711 s（≈16.9k cycles/s），4 帧自然内容约 34–35M cycles → 约 2,000–2,100 s/次，两次约 67–70 min。故 vsim 墙钟给 95 min、开发墙钟 115 min，而不是 44 min；2700 s 单次硬超时仍保留。若一类超 2700 s → 该类 partial，不重跑同一 stall。**2700 s 是外层安全终止，不因预计偏慢而在运行中临时提高**；若确因机器负载超时，记 `timed_out` 并交原规划在 round2 决定（累计只剩 2 次全尺寸）。

## 8. 下游约束

- P1 round1 PASS 后，P2/P3 才由原规划放行；P1 PASS 不等于 G0 通过。
- 若 P1 以 `G0_not_proven` 收口，P4 headline 必须保持 `G0_not_proven`，不得用 P4/合成 C1 的 `G0_feasible_for_scope` 覆盖。
- 自然内容的实测瓶颈（压缩吞吐 ≈7.5M/frame）必须传给 P3：只把 sink 提到 103.79 不会让自然内容达到 G0；P3 的模型必须用 P1 的自然内容与 P2 的 production pacing。
