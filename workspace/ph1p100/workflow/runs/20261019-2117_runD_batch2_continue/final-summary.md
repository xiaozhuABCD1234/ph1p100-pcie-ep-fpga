# final-summary.md — 20261019-2117_runD_batch2_continue

收尾时间：2026-10-19 22:0x +08:00｜原规划者｜宿主 OpenCode｜batch=2｜正式包 2 个｜两层（需求→工作包）。

## 1. 本轮目标与最终结论

**目标**：续接 Codex 0212 线，在不新增生产构建、不重置旧计数的前提下，完成单 A RAW→DDR 板级闭环入口，并把双相机同步离线原型推进到可独立验收；最后交“回来点两下”清单。

**结论**：
- **T08.codex-sync-offline：PASS round0（实际修复 0）**。独立综合测试者重编译/复跑正例 `SYNC_OFFLINE_PASS mismatch=0`、`vlog Errors:0`；负对照 `SYNC_FAIL ordered role writes tx=5` 按预期拒绝；小顶 G2 Routed、三时钟 50/187.512/187.512 MHz、SWNS +0.294 ns/STNS 0、HWNS +0.043 ns/HTNS 0、资源在器件内；T08 manifest 35/35、B01 699 项 0 漂移。纯离线，未接活动 top、未下载、无 bit/CWC。
- **T02.codex-singleA-board：FAIL（blocked/awaiting_hardware），实际修复 0、未派修复轮**。B01 候选四身份 MATCH、699 项 0 漂移、租约/日志/清单可复核；但本 run 两次只读 `read_device_id` 均 60 s 超时、0 B 日志、无 `PH1P100`、0 次 download、0 样本。G3=not_run。该 FAIL 是外部设备缺失，不是可修实现缺陷；不自动重试、不消耗 round1—3。
- **T06/T09 B01 r0 PASS 作为既成输入复用**：699 项 manifest `c7a40897…d757`、生产 6/6 已封顶；本 run 未第 7 次构建、未重跑三算法离线仿真。

## 2. 最终判定矩阵

| task_id | verdict | functional | engineering | system | G0 | G1 | G2 | G3 | G4 | G5 | 实际修复轮 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| T02.codex-singleA-board | **FAIL（blocked/awaiting_hardware）** | blocked/not_run（G3；候选/清单可复核，2 处文档缺陷已在 v2 修正） | PASS（699/身份/租约/日志/0 漂移；download not_run） | PASS（就实际动作：仅 SRAM 入口只读探测、零 Flash/CLI/GUI、0207 不覆盖；真实板级行为 not_run） | inherited PASS | inherited PASS | inherited PASS | **not_run / blocked** | not_run | N/A | 0/3（不派修复） |
| T08.codex-sync-offline | **PASS（r0）** | PASS（独立重编译/复跑、正例 0 mismatch、负对照预期拒绝、角色/24 ms/8 帧/NACK/单路/reset/配对） | PASS（小顶 G2 Routed、三时钟、WNS/TNS≥0、CDC/约束/资源、manifest 35/35、B01 699 项 0 漂移） | PASS（纯离线、未接 top、未下载、零 Flash/CLI/GUI、旧 26 项未覆盖） | PASS | PASS | PASS | N/A | N/A | N/A | 0/3 |

## 3. 统计

- 正式包：2；独立验收 PASS：1/2；首次 round0 PASS：1（T08）；FAIL-blocked：1（T02）。
- 实际修复：round1/2/3 均 0；T02 的 FAIL 属外部 blocked，不计实现修复轮；T08 无 FAIL。
- 待条件：1（T02 awaiting_hardware）；未通过：0（T02 记 blocked，不记“DUT 判坏”）。
- G 层：T08 G0/G1/G2 PASS；T02 G0/G1/G2 inherited PASS、G3 blocked、G4 not_run；两包 G5 N/A。
- 父任务：T02/T06/T11 未 done；T08 父范围（真实双路曝光同步）未 done；G4 后放。

## 4. T02 详细

### 4.1 实际做了什么

- 复算 B01 manifest 699 项 `c7a40897…d757`、bit `b68c6e18…f9bf`、CWC `b28e3d4e…4ce`、BID `4dcdc263…8f33`、probe map `96eb210b…888a`；B01 两 r0 PASS 报告同 manifest；生产 6/6 无第 7 次。
- 板窗机械检查 + 租约：`board/board-window-lease.json`（SHA `417cbe35…bf`，21:27）记录无活跃 TD 构建/下载、`td.exe` 45416 与 `hwserver.exe` 45596 未触碰、窗口释放。
- 0207 并行线读取：`preload-record-v4.md`（21:23）`PRG-8000 transfer failed`、0 download、`awaiting_user_gui`、未持有窗口；本 run 未覆盖。
- 只读 `read_device_id` 两次：21:28:07 起 60.0 s 超时；21:29:29 起 60.752 s 超时；日志 0 B；`probe-result.json` `ph1p100_seen=false`、`device_id=null`。第 2 次仅纠正第 1 次脚本写法，不是 download 重试。
- **0 次 download、0 样本、板上加载状态 unknown**；未执行 `sram-execution.json`/download 日志/成功标记。

### 4.2 证据

- `board/sram/20261019_213000/probe-result.json`（SHA `665358cc…8c15`）
- `board/sram/20261019_213000/read_id.tcl`（SHA `fb932c08…ee1a`）、`read_id*.log`/`.err.log`
- `board/board-window-lease.json`、`board/t02/candidate-manifest.json`（T02 manifest `485b2346…4598`，`acceptance_status=blocked_awaiting_hardware`）
- `test-reports/T02.codex-singleA-board-r0-integrated.md`

### 4.3 问题对象（原样保留）

- `problem_id`: `T02.codex-singleA-board:DEVICE_MISSING:read_device_id_timeout`
- `reason_code`: `DEVICE_MISSING`；`new_information=true`
- `evidence_path`: `workflow/runs/20261019-2117_runD_batch2_continue/board/sram/20261019_213000/probe-result.json`
- `requested_action`: 现场检查电源/指示灯（DDR 校准完成）、USB/JTAG 线是否插在板卡口并插稳、必要时换线/换口；新授权轮次重做机械检查+只读 `read_device_id`（≤60 s）+一次 ≤180 s SRAM download；仍禁止 Flash/CLI readback/GUI 自动化。
- `resume_input_path`: `board/t02/board-checklist-final.md` 与 `board/board-window-lease.json`

### 4.4 上板清单 v2

- 最终入口：`board/t02/board-checklist-final.md`（v2，not ready to click；先物理检查/新授权下载）。
- 已覆盖：候选绝对路径+四 SHA、当前板载 unknown、0207 不覆盖、回退旧 bit/CWC；两次 Instant Trigger ≥20 s、16 字/40 探针入口（链接 0212 `probe-reference.md`）、camera/DHI 分域不拼原子；冻结期望值；几何/ROI/PHASE=3、内部 abort+恢复、短窗；异常分流（身份/窗口/超时/校准/点击失败）与恢复入口。
- 已修正 v1 两处文档缺陷：`cl_words`/`cl_len` 前缀；补 16 字/40 探针链接。v1 保留为冻结证据，不覆盖（v1 SHA `41a70391…b2ed`）。

## 5. T08 详细

### 5.1 结果

- 修复 `sync_offline_top.v` 两处非法空位置连接 `()` → named `.src_busy()`；before `c99a443e…53d7` / after `ec76d0e5…bd0d`。
- 正例：`vlog Errors:0/Warnings:0`，`SYNC_OFFLINE_PASS mismatch=0`，覆盖 prereq/hold/busy/order/wait/warmup/nack/timeout/missing/abort/reset/relock/overrun/wrap；TB 冻结 SHA `dd03c079…09c1`。
- 负对照：隔离副本 `30C1 0F→00`，`SYNC_FAIL ordered role writes tx=5` 预期拒绝，编译 0 错误。
- G2：TD Release_2026.2，PH1P100SBG484 speed3，Routed；50.000/187.512/187.512 MHz；SWNS 0.294/STNS 0、HWNS 0.043/HTNS 0；872 slices、752 LUT6、964 regs、81 IO；CDC 用 toggle-handshake+2FF，SDC 仅 `rst_n` false path；无宽泛豁免。无 bit/CWC（独立小顶无 ADC 引脚）。
- manifest：`sync-offline/manifest.json` SHA `3e513628…8775`，35/35 artifacts+4/4 reference inputs；B01 699 项 0 漂移；旧 26 项 manifest `94FF1150…DF06A` 只读未覆盖。

### 5.2 证据

- `sync-offline/manifest.json`、`sync-offline/g1/positive-r2-final/`、`sync-offline/g1/negative-r1/`、`sync-offline/g2/td-work4/`
- `test-reports/T08.codex-sync-offline-r0-integrated.md`、`test-reports/_rerun/T08-r0/`
- `handoff.md` 记录恢复与保护。

## 6. 并行线协调（CR-20261019-2117-01 已执行）

- 写树隔离：本 run T08 写 0212 生产树的 T08 新文件；T02 不写生产树；0207 写 `wt0207`；两线候选/证据不合并。
- 板窗租约：下载前读 0207 最新 preload/dev-result；本 run 发现 0207 未持有窗口（0 download、PRG-8000、awaiting），本 run 写租约后尝试只读探测；探测未取得器件，未 download，租约释放，不阻塞 0207。
- T08 纯离线：ModelSim+独立小顶 TD，不等待板窗/用户点击；未与 SRAM 下载并发。
- 结论：**互不堵塞安排已执行**；本 run 没有覆盖 0207 候选/文件，0207 也没有被本 run 阻塞。

## 7. 过程偏差登记（观察项，不改变判定、不扩预算）

1. **T02 calls 26/20**：超出冻结 dev 预算 6 次，主要用于两次只读探测与证据落盘；batch 总计仍在 55 次内。登记为过程偏差；后续恢复不得沿用超用值，须重新冻结。
2. **T08 正例编译 3 次 vs 计划 2 次**：第 1 次 TB 故意 timeout 场景触发 scoreboard 顺序检查；第 2 次修正 TB 后 PASS；第 3 次因 21:39:29 外部改写 TB（恢复为未修复版 `bc99c72…`）而重放修复并复验。第 3 次由外部输入变化触发，未放宽 RTL/阈值；测试者用冻结副本 `dd03c079…` 独立复验。
3. **T08 TD 会话 4 次 vs 计划 1 次**：第 1 次 `add_files` 空路径；第 2 次 `.v` 载体使用 SV `.*` 被拒；第 3 次 bitgen 因未约束 IO 中止；第 4 次完成 route。最终有效 G2 来自第 4 次，总 route/place ≈32 s，未改时序/约束门槛、未为 G2 改 RTL；测试者核同一 DB/报告。
4. **T02 manifest 时间戳**：`generated_at=21:32` vs mtime 21:35:27；哈希一致，属元数据差异，未改冻结件；v2 清单已注明。
5. **T02 清单 v1 文档缺陷**：`words`/`len` 缺 `cl_` 前缀、未链接 16 字名单；v2 已修正并补链接；v1 冻结身份保留。

以上偏差不构成验收门槛放宽；T08 PASS 依据最终有效 DB+独立复跑，T02 blocked 依据实际无器件，不因偏差改判。

## 8. 安全与写范围

- 全程仅 SRAM 入口；**0 download、0 Flash/efuse/SPI/svf、0 CLI 读回、0 GUI 自动化、0 commit/push、0 批量删除、0 杀他人进程**。
- 写入：本 run `board/**`、`sync-offline/**`、`test-reports/**`（测试者）、规划文件；生产树仅 T08 新文件（`rtl/ep_side/cam/sync_offline/**`、`sim/tb/tb_sync_offline*.sv`）。
- 未写：B01 699 项/bit/CWC/BID/报告、0212 旧 run 既有文件、0207 run/wt0207、活动 top、`sim/compile_checked.f`、I2C/寄存器表、生产约束/IP/ADC、`workflow/tasks.json`、TD 安装目录。

## 9. 未完成/未测边界

- T02：无 `PH1P100`、无 download、无两样本；G3 未判；几何/物理 Bayer 相位/内部 abort 恢复/短窗均未实测；G4 后放。
- T08：仅离线原型；未接活动 top、无真实双路主从/电气/寄存器读回/曝光同步；无 bit/CWC；G3/G4 N/A。
- T06/T11 父任务、PCIe/RK、压缩、G4 长稳/性能均未 done/未测。

## 10. 下一入口

- 用户先按 `user-summary.md` 做物理检查；再由新的明确授权轮次按 `board/t02/board-checklist-final.md` §0—§3 重做板窗检查/只读 ID/一次 ≤180 s SRAM 下载；成功后按 §4 取两样本，判 G3。
- 精确恢复示例见 `handoff.md` 末段与清单 §8；不自动恢复、不重置旧计数、不扩大预算。

## 11. 2026-10-20 00:xx 补记：T02 recovery01 FAIL/blocked → 一次有界补证

- `test-reports/T02.codex-singleA-board-r0-recovery01-integrated.md`：**FAIL（blocked，EVIDENCE_INSUFFICIENT，非 DUT 实现失败）**；functional=PARTIAL、engineering=PASS、system=FAIL/blocked；G3=**partial/blocked**；problem=`T02.codex-singleA-board:REPRO_DETAIL:sample-provenance`。原 G3 not_run 记录保留，不覆盖、不改写。
- 六窗口字段（`cl_words=648192`、`cl_len=2592768`、`flags=8000000F`、`fault/fail=0`、两个不同 seq、pass/writer_good/source_good/algo complete 递增、`source_geometry=089012DE`、abort/recovery 计数与 RTL 语义相容）总体与冻结值一致；但证据仅为聊天截图主转录，无原图/CSV/原始导出、无操作者/接线/供电连续性，ROI X/Y/SKIP/相位无直接证据。
- **裁定 A**：一次有界补证。用户把 6 张原图按 `user-action-samples.md` 命名存到 `board/t02/samples/T1/`、`T2/`，回三句话（操作者、接线/供电连续性、已存好）；不重下载、不重拍。开发续原 batch session `ses_eaba8efb1ffe7iWxJYBv40A2fQ` 只登记/绑定，新建 `manifest-samples-02.json`（不覆盖旧 manifest）；原 tester 出 `T02.codex-singleA-board-r0-recovery02-integrated.md`。若仍 partial，按 B 收尾，不再自动补证。
- **计数**：recovery01 FAIL/blocked 不计实现修复轮，actual repair rounds 仍 0；T08 PASS r0 不受影响；T02/父任务未 done。
- 当前 `dispatch.json`：`status=needs_user_input`、`next_action=relay_to_user`、`user_summary_path=user-action-samples.md`；用户回传后 dev 绑定 → tester recovery02。

## 12. 2026-10-20 00:xx 补记：recovery02 FAIL/blocked → 最后一次命名修正

- `test-reports/T02.codex-singleA-board-r0-recovery02-integrated.md`：**FAIL（blocked，INPUT_CONFLICT + EVIDENCE_INSUFFICIENT，非 DUT 实现失败）**；functional=PARTIAL、engineering=FAIL、system=FAIL/blocked；G3=**partial/blocked**；problem=`T02.codex-singleA-board:INPUT_CONFLICT:t2-cwc2-cwc3-image-swap`。
- 关键问题：6 图数值与转录一致，但 T2 的 `cwc2_dhi_...235228.png` 实际是 cwc3 TL/23:53:10，`cwc3_tl_...235310.png` 实际是 cwc2 DHI/23:52:28，两图内容互换；manifest-samples-02 实例映射错误、`user_statement` 编码损坏、sample-record 仍写“未落盘/未提供”。
- **裁定 A（最后一次有界修正）**：用户按 `user-action-rename.md` 三步互换两张 T2 PNG 文件名；不重拍/不重下载；开发重冻 `sample-record-v3` + `manifest-samples-03`（修正编码/陈旧字段，不覆盖旧文件）；原 tester 出 `T02.codex-singleA-board-r0-recovery03-integrated.md`。
- **判定边界**：命名修正只消除 INPUT_CONFLICT，不自动升 PASS；操作者/接线/供电仍口述、无 CSV/事件条带、ROI X/Y/SKIP/PHASE 无直接证据 → G3 至多 **partial**。若 recovery03 仍 partial，立即按 B 收尾，不再补证、不开 recovery04。
- **计数**：recovery01/02/03 均为证据轮；actual repair rounds 仍 **0**；T08 PASS r0 不受影响；T02/父任务不 done。
- 当前 `dispatch.json`：`status=needs_user_input`、`next_action=relay_to_user`、`user_summary_path=user-action-rename.md`。

## 13. 2026-10-20 最终收尾：recovery03 → 按 B 接受 partial

### 13.1 最终判定

| task_id | verdict | functional | engineering | system | G0 | G1 | G2 | G3 | G4 | G5 | 实际修复轮 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| T02.codex-singleA-board | **FAIL（partial，按 B 收尾）** | **PASS**（6/6 原图逐项匹配；身份/长度/words/flags/fault/fail/pass/writer_good/seq/source_good/algo_complete/overflow/geometry/CRC/word0–8 一致；abort/recovery 与 RTL 语义相符） | **PASS**（B01 699/SHA/bit/CWC/BID/probe map 0 漂移；samples-03 21/21；T2 cwc2/cwc3 已修正、无 TEMP；sample-record 编码/陈旧字段已修） | **PARTIAL**（操作者未具名、接线/供电仅口述、无 CSV/原始导出/独立观察；ROI X/Y/SKIP 与物理 Bayer 相位无直接探针） | inherited PASS | inherited PASS | inherited PASS | **partial** | not_run | N/A | 0 |
| T08.codex-sync-offline | **PASS r0** | PASS | PASS（G2 Routed、三时钟、WNS/TNS≥0、资源、35/35） | PASS（纯离线、未接 top、未下载） | PASS | PASS | PASS | N/A | N/A | N/A | 0 |

- 报告：`test-reports/T02.codex-singleA-board-r0-recovery03-integrated.md`；`manifest-samples-03.json` SHA `cba3256f…1468`，21/21 artifacts；6 图 T2 cwc2=`424E2F09…`/87,607 B、T2 cwc3=`680BFC05…`/62,433 B。
- **计数**：recovery01/02/03 均为证据轮，**不计实现修复轮**；T02 actual repair rounds 仍 **0**；T08 PASS r0 不受影响；T02/T06/T11 父任务未 done。

### 13.2 统计与执行账

- 正式包 2；独立验收 PASS 1/2；T02 为 FAIL/partial，T08 为 PASS r0；首次 round0 PASS 1；实际修复 round1—3 均 0；证据轮 3。
- T02：下载 **1 次成功**（`PRG-2014 Chip validation success: PH1P100`、100%、29.63 s result / 29.43 s checklist、post `read_device_id=PH1P100`）；读 ID 成功；6 图落盘；T1/T2 间隔 104/57/71 s。
- T08：离线 PASS r0；manifest `3e513628…8775` 35/35；G2 Routed 50/187.512/187.512 MHz。
- 全程：0 Flash/efuse/SPI/svf、0 push、0 PCIe/RK、0 批量删除、0 杀他人进程。

### 13.3 收尾边界与恢复入口

- **不再要求用户补 CSV/截图/操作者；不再派 tester；本 run 结束。** B 边界：T02 G3=partial，证据限制为系统观察/ROI 位置/物理相位，不是数值错或候选漂移。
- 板上为 T02 候选 `b68c6e18…f9bf`（SRAM 易失；断电需重下）；0207 候选已被覆盖，0207 需另轮重下。
- 回退：旧 bit `bfafdf97…`/CWC `8d2998b9…`（基线 `debug-fix3`）；只作入口，不自动执行，不写 Flash。
- 若未来要争取完整 G3 PASS，只能由用户明确新授权的新轮次补独立操作者/电源/接线记录、CSV/事件条带、ROI X/Y/SKIP 与物理相位直接证据；不得复用本轮 partial 冒充 PASS。
- `dispatch.json` 最终：`status=finished`、`needs_user_input=false`、`user_summary_path=user-summary.md`。
