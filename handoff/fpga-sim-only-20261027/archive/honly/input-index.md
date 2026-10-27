# input-index — 20261027-055621_fpga-honly-td-and-ah

本文件只登记路径、版本、哈希与采用状态，不复述报告结论。哈希由规划于 2026-10-27 06:00–06:07 只读重算。

## 0. 本轮需求与权威边界

| 项 | 值 |
|---|---|
| 用户原话/双线边界 | `workflow/runs/20261027-055621_fpga-honly-td-and-ah/request.md`（本 run 唯一需求正文） |
| 输出目录 | `D:/fpga/ph1p100/workflow/runs/20261027-055621_fpga-honly-td-and-ah` |
| 项目根 | `D:/fpga/ph1p100` |
| 根约束 | `AGENTS.md`（批量删除禁令、盘符约定、权威仓只读条款） |
| 角色规则 | `.agents/skills/fpga-orchestrator/references/{work-limits,relay-contract,report-contract,project-context}.md` |
| 本条需求形状 | 两条**独立并行线**，各自新开发/新综合测试者；不是批（无跨任务共用测试者） |

用户明确的两条线（不解释、不改写）：

- **Line A**：在 H-only r1 候选的独立副本上加 A（2-position literal 扫描 + 双符号 packer，定义以 P2 coregap model/verdict 为准）；只要 N/L 4 帧 S_ss ≤6,250,000、A1U1/zlib 逐字节不变、adapter 定向、无 stall；A 失败或增益 <100k cycles 就 kill；**0 TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK/网络**；不改 H-only r1。
- **Line B**：用 H-only r1 冻结候选做 TD 综合/PnR/STA（187.5 MHz，必要时 209.6 fallback），检查 WNS/hold/资源/CDC/关键路径（frame_top 双 CRC32、core replay）；**不改 RTL**、不 bitgen/CWC/下载/Flash/上板；只输出 TD/STA/资源报告；TD 独占，若 `20261026-2138_fpga-integrated-delivery` 在用则等待。
- 可设第 3 包 T10.ah-dual-verdict（合并两线，0 sim）。

## 1. H-only r1 冻结候选（Line A 的起点、Line B 的 DUT；**只读**）

run `20261026-231711_fpga-a-plus-h-prototype`，task `T10.ah-honly`。

| 文件 | 字节 | SHA-256（规划重算，全 64 位） | 状态 |
|---|---:|---|---|
| `T10.ah-honly/r0/changed-src/a1_deflate_core.v` | 85,192 | `8acd20b244b27ddf992432c39bffc34cf00e8394b01443571d9bdb8e3717b17b` | 与 manifest-r1 `candidate.core` 一致 |
| `T10.ah-honly/r0/changed-src/a1_frame_top.v` | 29,207 | `4afc26e246fbae4e32c5ab7e88dffb496048d10966c5ee42b290b3e71f60e30a` | 与 manifest-r1 `candidate.frame_top` 一致 |
| `T10.ah-honly/r1/manifest-r1.json` | 24,979 | `f752ae09790cbbbaa5828c5fe1b6ed786a97485b400ef374fb191191b2c1a112` | 冻结 manifest（42 artifacts + 9 refs + 14 commands） |

TB 与证据（全部只读引用；Line A 需**复制**到自己任务目录后再改）：

| 文件 | 字节 | SHA-256 前 16 | 用途 |
|---|---:|---|---|
| `T10.ah-honly/r0/changed-src/tb_ss_4run_wd.v` | 29,468 | `D86456DDDB0AAA72` | N4/L4 4 帧 TB（含被动 A1U1 监视器） |
| `T10.ah-honly/r0/changed-src/tb_ss_4run_wd_probe.v` | 33,371 | `C8C19A176A5CD7E0` | 1 帧 stage probe（含只读 tap） |
| `T10.ah-honly/r0/changed-src/tb_a1_deflate_core_8b.v` | 7,539 | `910AEA54E0D8D40A` | b6 bench 8-bit（= 冻结原版） |
| `T10.ah-honly/r0/changed-src/tb_a1_deflate_core_16b.v` | 7,692 | `91E52CF5FCB5C395` | b6 bench 16-bit（`OUT_BYTES=2`） |
| `T10.ah-honly/r1/changed-src/tb_adapter_directed.v` | 9,752 | `56066E703003A294` | adapter 定向 12 case |
| `T10.ah-honly/r0/src/*.v`（12 个冻结 DUT + `ref_b11_*` + `ref_b6_*`） | — | 见 manifest-r0/r1 references | 4 帧/probe 环境其余源 |
| `T10.ah-honly/r0/src/content/raw40_n.hex` | 5,702,400 | `E44FE7BC89AAA3AD` | N 内容（P1 自然内容） |
| `T10.ah-honly/r0/src/content/raw40_l.hex` | 5,702,400 | `E7E3C21CD2E4CC18` | L 内容（P1 低照） |

H-only r1 基准数值（**引用，不重跑**）：

| 量 | 值 | 来源 |
|---|---|---|
| N4 S_ss | 6,196,749.5（S_23 6,196,750 / S_34 6,196,749） | `test-reports/T10.ah-honly-r1-integrated.md` §2.1 |
| L4 S_ss | 5,834,940 | 同上 §2.2 |
| N frame-1 core_interval | 6,197,186（2.39089 c/B） | `T10.ah-honly/r1/out/cycles-r1.json` / `r0/out/cycles.json` |
| L frame-1 core_interval | 5,832,040（2.250015 c/B） | 同上 |
| 4 帧 header 逐字节基准 | `n-4f.frm` `b9cb5359…`、`n-4f.hdr` `c7fe281c…`、`l-4f.frm` `8aad9099…`、`l-4f.hdr` `864d2fba…` | manifest-r1 artifacts |
| b6 bench | comp 50,310 B `2601d57cd98d1fe69b2e46fe8423779a5d44bd14c00e1fe2d5faab6ff15a7c05` 304,961 cyc（≤355,261）；rand 153,766 B `54f262f2a600a3e2f12129f2937a390737d1ec8018d8f0236979e604760496dd` 161,479 cyc | `T10.ah-honly/r0/out/h-bench.json` |
| adapter | 12/12 PASS | `r1/out/adapter-directed.json` |
| 资源（仅估算） | +0 ERAM、+350..950 LUT6、+240..620 REG | `r0/out/resource-estimate.json` |

## 2. A / A+H 定义来源（P2 coregap）

| 文件 | 用途 |
|---|---|
| `workflow/runs/20261026-143924_fpga-1080p30-g0-production/T10.ss-g0-prod-coregap/r0/out/coregap-model.json` | 方案矩阵：A = 双端口 hash、2 位置/周期；仅 literals dual-issue 保守值 7,223,675；A+H 组合 6,008,078（2.3179 c/B，+4.03%）；envelope 45.0% |
| 同目录 `out/coregap-verdict.json` | `closable_at_187_5=conditional`；要求"2-position scan + 2 B/cycle replay 的隔离原型 + TD/STA + 同一 1 帧 probe cycles/B ≤2.411" |
| 同目录 `manifest-r1.json` | coregap 证据绑定（只读） |
| `.../T10.ss-g0-prod-content/r0/content/raw40_{n,l}.hex` | P1 内容原始来源（本 run 直接使用 h-only r0 的同哈希副本，见 §1） |
| `.../T10.ss-g0-prod-verdict/r0/g0-production-verdict.json` | P4 总判定（G0_not_closed，仅供背景；不作本轮门槛） |

**采用**：A 的语义采用 coregap model 的 scheme A 描述（2-position/2-symbol scan，dual hash port），实现取 **literals-only dual issue**（保守、可逐字节等价）；A+H 的目标数值只作期望，不作证据。

**未采用/不复活**：scheme B/C/D/E/F/G；b20 的 "A+" 单位置 core（`T10.b20-a-timing` 只是 abort→smem 地址修复，不是 2-position 扫描）；任何 P1–P4 旧判定改写。

## 3. b11 基线 / TD 模板 / 工具（Line B）

| 文件 | 用途 |
|---|---|
| `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read/r0/td/a1_eng_top.v` | 块级 build-only 包装（7 路 status 折成 1 路 XOR，把 286 IO 限内）——Line B 的 wrapper 模板 |
| 同目录 `a1_small_top.sdc` | 单时钟 5.333 ns、无 false_path/multicycle 的模板 |
| 同目录 `01_build.tcl` / `route_flow.status` / `routed_timing_status.rpt` | TD 流程与报告格式模板；冻结参考：board top `clk_a1` SWNS **+0.015**、HWNS **+0.020**、0 violated endpoints |
| `T10.a1-eng-freeze/r10/td/00_all.tcl`、`r10/lessons-r10.md` | 同一 2 文件块级 syn+conditional phy 模板；r10 lessons 提到该路径族 0.016 ns 量级的改善（**规划未在 r10 报告/日志中复核到对应最终 WNS 行**，只作"同族块级裕量极薄"的定性参考，**不作基线、不作门槛**） |
| `T10.b20-a-timing/r0/result-r0.md` | 同族 core 的 routed `SWNS +0.012` 薄裕量参考（b20 目录本轮只读，不碰） |
| `tools/integrated_delivery/td/01_synth.tcl` | TD 2026.2 已验证可用的"绝对路径 + flow.status 端点统计"写法（只读参考） |
| `tools/td/td_env.ps1`、`tools/td/PATH_CONTRACT.md` | 盘符约定；`T:` 必须指向本 run 的 td 目录，`Y:`=项目根；**禁止 -Force 抢占** |
| `D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe` | TD CLI 入口（`td_commands_prompt.exe ./x.tcl`，cwd=工程目录） |
| `tools/td/README.md` | TD 6.2.3 已知坑（license 缺失时 RUN-8008 退化为 PRJ-5303/8806；scratch 目录每条新开） |

本机 TD 现状（规划实测）：`D:/anlogic/TD_Release_2026.2/bin/` 内 `td.exe` 与 `td_commands_prompt.exe` 同尺寸 123,372,304 B；`tools/td/README.md` 记录的 license 路径 `D:/downlaod/license/Anlogic.lic` **规划未验证存在**；今日 04:46 与 06:01 两次 TD 综合均正常启动（见 §4），说明当时 license 可用。

## 4. TD 租约现场（规划 2026-10-27 06:06:13 实测）

| 检查 | 结果 |
|---|---|
| TD 进程（pnmain/td/td_commands_prompt/run/tdsynth） | **0**（此刻无进程） |
| `20261026-2138_fpga-integrated-delivery/INT.P4/td/**` 最新写入 | **`INT.P4/td/r3_run1/*` = 06:04:16**（06:01:41 启动的 r3 第 1 次综合，已产出 `int_p4_gate.db` 7,389,740 B + timing/area） |
| 同 run `INT.P4-r3-manifest.json` | **不存在** → round3 仍在进行，未冻结 |
| 该 run 的 TD 配额 | round3 追加综合 3 次、终身 9 次（r0–r2 已用 6 次）；route ≤1、bitgen/CWC/download=0 |
| 该 run 最新活动（任意文件） | 06:04:16（`r3/regression` 与 `r3/sim` 亦在 06:00 前后更新） |
| `T:` 映射 | 仍指向 `T10.b20-a-timing/r0/td`（b20 已于 2026-10-26 结束，属**陈旧映射**） |
| `Y:` 映射 | → `D:\fpga\ph1p100`（正确） |
| 板卡/COM/JTAG | 本轮 0；规划未打开任何设备 |

**结论（冻结，2026-10-27 06:06）**：`20261026-2138_fpga-integrated-delivery` **正在使用 TD**（round3 综合窗口 06:01 起，尚有 2 次综合与至多 1 次布线未用）。按用户规则 **Line B 本轮等待**，不得开 TD 会话、不得抢占 `T:`、不得与该 run 共享工程/库/日志。Line A 不受影响。

**复审（2026-10-27 07:26:43，规划实测，取代上面的 06:06 结论）**：租约已空闲，理由见 `r0-ruling.md §2.1`——`INT.P4-r3-manifest.json` 于 **06:10:50** 创建（SHA `43EBFF3D…26F1`），该 run 已 `status=needs_user_input` / `run_state=closed` / `task_ids=[]`、`handoff.md` 06:53 冻结；TD 进程 0；`INT.P4/td` 最新写入 06:07:52、`INT.P4/r3` 最新 06:08:17（距复审 78 min）。→ **租约授予 `T10.ah-honly-td`**，恢复原开发会话（不新建）。

## 5. 权威仓绑定（只读）

| 仓 | 状态 |
|---|---|
| `https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-fpga` → `D:/fpga/repos/ph1p100-pcie-ep-fpga` | `main`。H-only diff **尚未迁移**；本 run **不 commit/push/fork、不改 main**。Line A 的候选只在 run 任务目录内，Line B 的 TD 工程绑定"冻结旧候选的绝对只读路径"，**不以新仓文件替代**。 |
| `https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-driver` → `D:/fpga/repos/ph1p100-pcie-ep-driver` | 本轮不涉及（0 RK/网络）。 |
| `chenzhenzhong12138/fpga-stereo-vision` | 仅编排历史，不作交付入口，不使用。 |

## 6. 保护范围（本轮任何角色不得写）

- `workflow/runs/20261026-2138_fpga-integrated-delivery/**`（含 `INT.P4/td/**`）
- `workflow/runs/20261026-231711_fpga-a-plus-h-prototype/**`（H-only 候选与报告，只读）
- `workflow/runs/20261026-144617_fpga-chain-detail-review/**`、`20261026-143924_fpga-1080p30-g0-production/**`（P1–P4 证据）
- `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b18-b17-b/**`、`T10.b19-cam-a/**`、`T10.b20-a-timing/**`
- `fpga/csi2/src/**`、`fpga/csi2/pcie_integration/**`、`upstream/**`（生产源）
- `workflow/tasks.json`、`docs/**`、`.agents/**`、`workflow/` 其他 run
- `D:/TD/**`、`D:/fpga/repos/**`、`D:/fpga/refs/**`、`D:/fpga/archive/**`
- 硬件：板卡/COM/JTAG/Flash/CWC/下载（本轮全线 0 授权）

## 7. 未决 / 待条件项

1. **TD 租约**（已于 2026-10-27 07:26 解除）：`20261026-2138_fpga-integrated-delivery` 已关（`run_state=closed`）且 r3 manifest 06:10:50 冻结；Line B 已获授权恢复。恢复轮前仍须自检"0 进程 + 20 min 静默"。
2. **新仓迁移**：H-only diff 未进 `ph1p100-pcie-ep-fpga/main`；本轮以"冻结旧候选 + 隔离 TD 工程"满足 repo binding，不新增迁移任务。
3. **license 路径**：`tools/td/README.md` 的 license 路径规划未验证；若 TD 启动报 RUN-8008，Line B 记 `blocked=TOOL_UNAVAILABLE`，不重试、不改 license。
4. **209.6 MHz 的性质**：本轮只能做"同一 netlist/同一 DB、只收紧时钟的 analysis-only"复算，**不是** 209.6 MHz 布线结果；需在报告中显式标注。
5. **Line A 关账**：kill 已成立（`r0-ruling.md §1`），待一次独立证据审计后由原规划关账；不设修复轮（剩余仿真预算 ~1,245 s，不足以再跑 N+L 4 帧）。
6. **P3 放行**：等 A 审计 + B TD 结果，条件见 `r0-ruling.md §3`。

## 8. 采用版本一览

| 主题 | 采用值 | 依据 |
|---|---|---|
| DUT | H-only r1 core/frame_top（SHA 见 §1） | manifest-r1 `f752ae09…` |
| A 定义 | 2-position/2-symbol scan，literals-only dual issue + ≤16 bit 双符号 packer | coregap-model/verdict |
| 目标时钟（Line B） | 187.5 MHz（5.333 ns），209.6 MHz 仅 analysis | 用户需求 + b11/r10 模板 |
| N/L 内容 | `raw40_n.hex` / `raw40_l.hex`（P1 自然/低照） | §1 哈希 |
| S_ss 门槛 | ≤6,250,000（N、L 各自 4 帧） | 用户需求 + P2/P4 冻结公式 |
| A 收益门槛 | N4 至少比 6,196,749.5 好 100,000 → ≤6,096,749.5 | 用户需求 |
| 逐字节等价基准 | §1 的 4 帧 frm/hdr + b6 bench + zlib | manifest-r1 |

## 9. r0 结果落地（2026-10-27 07:30，裁决见 `r0-ruling.md`）

| task | r0 结果 | 关键数字 / 证据 |
|---|---|---|
| `T10.ah-a-plus-h-r2` | **kill（A not adopted）**，规划已复核 70/70 artifacts 哈希一致；待一次独立 kill 证据审计 | A core `f3ee798f…33adc`（89,053 B），frame_top **未改** `4afc26e2…`；N4 S_ss **6,104,484.5**（增益 **92,265 < 100k**）；L4 **5,700,538.5**；4/4 `.frm`/`.hdr` SHA 全不等（`n-4f.frm 7d6c6d05…`、`l-4f.frm 7565dc64…`）；头字节 36..43 = `x`；bench 8b/16b comp/rand 与 adapter 12/12 通过；manifest 70 artifacts / 7 refs / 19 commands / 9 vsim；previous `f752ae09…` |
| `T10.ah-honly-td` | r0 准备完成（`blocked`，DEVICE_MISSING），TD 租约已于 07:26 授予，待恢复 | 0 TD 调用、0 盘符映射；1 次 `vlog` 0 error/0 warning；DUT SHA 未变；scaffold `r0/td/{a1_ah_eng_top.v,a1_ah_small_top.sdc,01_synth.tcl,02_route.tcl,03_2096_analysis.tcl}` 已就绪 |
| `T10.ah-dual-verdict` | blocked | 待 A 审计 + B TD 结果 |

## 10. r1 → 收尾状态（2026-10-27 10:10，裁决见 `r1-ruling.md`/`r2-ruling.md`/`dual-verdict.md`）

| task | 状态 | 事实 |
|---|---|---|
| `T10.ah-a-plus-h-r2` | **closed：kill_verified / not adopted** | 审计报告 `test-reports/T10.ah-a-plus-h-r2-r0-integrated.md`（首行 PASS，语义=kill_verified）；manifest `59805d90…`；两条 kill 理由各自独立成立；D1–D8 偏差不影响 kill；**无后续动作** |
| `T10.ah-honly-td` | r0 **FAIL（不可综合）**；r1 **blocked = TOOL_UNAVAILABLE，not_evaluated** | r0 综合 6.49 s 被 TD 拒绝：`HDL-8007 cmem_lo[15]` 多驱动（L673 / L964），无 gate DB/时序/面积/`flow.status`；manifest 34。**r1**：synth **成功**（WNS +0.029 ns、TNS 0、0/4,969 端点、coverage 97.06%、Period 2.533、IO 121/286、slice 3,337/71,680、reg 1,663、ERAM 27、DSP 0；gate Fmax 上界 188.537 MHz），**route 2/2 在 `import_db→Import ChipWatcher` coredump**（placement 之前，两个 minidump），无 routed DB/STA/QoR/CDC，209.6 not_run；manifest r1 `8325f230…`（83/83） |
| `T10.ah-honly-synthfix`（第 2 包） | **closed（PASS）** | manifest `034777c5…`（75/75 规划已复算）；core `d2960cfe…`（85,221 B）、frame_top `4afc26e2…` 未变；N4 6,196,749.5 / L4 5,834,940 精确；4/4 `.frm/.hdr`（及 `.evt/.stats`）整文件 SHA 相同；bench/adapter/独立 8b comp 304,961 cyc；diff 仅白名单两处；0 TD |
| `T10.ah-dual-verdict` | **closed（`dual-verdict.md`）** | A 不采用 + H-only prototype gate 通过 + synth 正余量 + routed 未评估；0 sim / 0 TD |

规划侧静态复核（仅体量评估，TD 为权威）：`_planner_scan_multidriver.py` → core 内**只有** `cmem_lo` / `cmem_lo_pend` / `cmem_lo_addr` 跨块驱动（块首 673 与 964），`a1_frame_top.v` 零跨块驱动。TD 原始日志：`T10.ah-honly-td/r0/td/run-syn1/a1_ah_Runs/syn_1/run.log` L112–113。

TD 配额（liquid）：lifetime 启动 ≤3（已用 1，r1 用第 2 次）；综合结果配额 r1 = 1；route ≤2；analysis ≤1；bitgen 0。

**TD 租约 v2（2026-10-27 09:30，holder-agnostic）**：存在第二个活跃 TD 竞争者 `20261027-0726_fpga-board-integration`（其 `T11.BRD.P1/td` 08:15–08:18 已跑过综合、持有 `T:` 与 synth 2/route 2/bitgen 1 余额）。判定空闲依据：0 TD 进程；`INT.P4/td` 06:07:52（198 min）、`INT.P4/r3` 06:08:17（198 min）、`T11.BRD.P1/td` 08:18:30（68 min）三处静默均 >20 min。详见 `r2-ruling.md §2`（含残余风险与冲突处置）。
