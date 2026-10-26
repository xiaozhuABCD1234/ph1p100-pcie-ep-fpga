# result-r0 — `T10.ss-4run-matrix`（P4 四轮稳态矩阵）

- 状态：`ready_for_test`；`stopped_modifying=true`；`active_commands=0`；`blocked=null`；`retest` 见 §6。
- 本轮只做 FPGA 侧离线仿真/模型/报告；TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK **0 次**。
- 写范围：`.../T10.ss-4run-matrix/**` 与 `%TEMP%\opencode\ss-4run\**`；未改 P1/P2/P3 冻结件、内容源、b11/b6/T08/T10、生产源、`workflow/tasks.json`、`docs`、`work`、`.agents`。

## 1. 实际动作

| # | 动作 | 证据 |
|---|---|---|
| 1 | 冻结 7 个内容源；C1/C2 `raw.bin` 预处理为 `raw40_{p1d1,rand}.hex`（518,400×40-bit） | `content/`、`out/content-map.json`（C1 SHA `9a47c79b…`、C2 `82f59317…`；round-trip mismatch 0） |
| 2 | 从 P3 冻结 TB `a565c6f2…` 派生 `src/tb_ss_4run.v`（仅 CONTENT 2/3、`+RAW40`、`SS_RAW_MATCH`、`raw_bad/raw_checked`） | `src/tb_ss_4run.v` `7f5cc294…`、`src/DIFF.md`；12 DUT 源 0 mismatch |
| 3 | 编译并跑 4 个全尺寸 4 帧 run（R1–R4） | `sim/logs/r1..r4.log`、`sim/caps/r1..r4.{stats,evt,hdr}`、`sim/commands.jsonl` |
| 4 | 分析四轮表/G0/内容/差距/负对照 | `out/runs-4.csv`、`out/four-run-table.csv`、`out/g0-verdict.json`、`out/gap-menu.csv`、`out/negative-controls.json` |
| 5 | 报告与冻结 | `four-run-report.md`、`manifest-r0.json` |

## 2. 关键结果（measured）

| run | content | pacing | `S_ss` | `L_cold` | tail | sink-limited | G0 |
|---|---|---|---:|---:|---:|---|---|
| R1 | C1 全帧 raw | slot-free | 4,677,970 | 6,449,446 | 163,506 (3.50%) | false | **`G0_feasible_for_scope`**（+33.6050%） |
| R2 | C1 全帧 raw | strict-serial | 6,449,405 | 6,449,446 | 163,506 (2.54%) | false | `G0_not_closed`（−3.0918%） |
| R3 | C2 全帧 raw | slot-free | 5,189,503 | 11,476,032 | 5,700,448 (109.85%) | **true** | `G0_not_proven`（sink-limited） |
| R4 | comp proxy | slot-free | 5,928,286 | 9,234,076 | 1,697,820 (28.64%) | false | `G0_feasible_for_scope`（+5.4268%） |

- **R4 复现 P3 R3**：`S_ss` delta **0 cycles**（band 6 cycles）；`exp_bytes=3,395,456`、`cycles=27,020,950`、`SS_VEC_MATCH bad=0 checked=518400`、header CRC `pass=true` → 新 TB 可信。
- **R1/R2 同内容同 sink**：仅 pacing 不同；`R2−R1=1,771,435 cycles`（R1 的 37.865%），是 pacing penalty 的上界（含相机串行化）。
- **R3**：实测导出 93.748 MB/s（2 `clk_a1`/B）；`S_ss` 与导出串行时间 5,189,412 cycles 几乎相等，属 sink 饱和，**不得**当 G0 证据。生产 sink 需求单列：raw band ≥77.84 MB/s（G0）/ ≥103.79 MB/s（25 ms）。
- **内容自检**：R1/R2/R3 `SS_RAW_MATCH bad=0 checked=518400`；R4 `SS_VEC_MATCH bad=0 checked=518400`；DUT 帧头 `raw_crc/xform_crc/raw_len/xform_len` 与 Python 期望逐值相等。
- **Headline**：`G0_feasible_for_scope`（C1 slot-free 全帧 raw + comp proxy）；C2 raw band `G0_not_proven`；R2 strict-serial `G0_not_closed`。G25 只作参考、不降档。

## 3. 有效性/计数

- 4 run 均 `cap=4 enc=4 exported=4 read=518400`、`raw_drop=cmp_drop=dup=geom=err=wd=0`、`ss_pass=1`、`B11_FULL_RESULT pass=1`。
- R1/R3/R4 V4 为 true、`capacity_is_lower_bound=false`；R2 为 strict-serial by construction（V4 不适用）。
- `header_pass=true`、`header_crc_ok=true`（4/4）。

## 4. 预算

| 项 | 实际 | 冻结上限 |
|---|---:|---:|
| 全尺寸 vsim 次数 | 4（R1–R4） | ≤5 |
| 单次最长 | 1,383.6 s（R3） | 2,700 s |
| 全尺寸 vsim 总墙钟 | 4,741.5 s（79.0 min） | ≤7,200 s（120 min） |
| 预检（非全尺寸，2M cycles） | 86 s | 不计入全尺寸 |
| 开发 calls | 本会话预算内 | ≤45 |

- 未重试、未重跑任何全尺寸 run；1 次重试额度未用。分析脚本的一个 `header_check` 键名错误在首次解析 R1 后修复，只影响后处理，仿真数据/日志未改、未重跑。

## 5. 未做/边界

- 自然图像/低照/噪声/最坏内容：未做；C1/C2 是 `full_frame_raw_synthetic`，comp 是 `proxy_not_worst`。
- 生产 sink（≥103.79 MB/s）/PCIe/真实 115200：未做；93.75 MB/s 是冻结 TB 上限，**不能**当 ≥103.79。
- DDR sustained/MC/刷新/争用：未做；行为级 256-bit PAXI。
- TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK：0。
- 双核/共享 PAXI/Routed 时序：未证。

## 6. 写范围偏差（唯一一项，已披露）

- 预检前为核对 comp hex 的 SHA/CRC，曾在 `C:\Users\czz\AppData\Local\Temp\opencode\dbg_comp.py` 写入 1 个约 1 KB 的只读调试脚本；该文件不含项目源码/秘密，不参与任何证据。尝试删除时被环境权限拒绝（`Permission denied`），因此保留并在此披露。除此之外，写入均在 `.../T10.ss-4run-matrix/**` 与 `%TEMP%\opencode\ss-4run\**`。

## 7. 复测清单（供综合测试者）

- `required_dimensions`: integrated（functional/engineering/system）
- `required_checks`:
  1. 4 run 计数/无丢帧/事件单调/`S_ss` 可独立复算；
  2. R1/R2 同 C1 同 sink；R2−R1 pacing penalty 与 R2 G0_not_closed；
  3. R3 `sink_limited=true`、tail>50%、不判 G0；生产 sink ≥77.84/103.79 单列；
  4. R4 复现 P3 R3 `5,928,286`（±0.5%）与同 run `SS_VEC_MATCH bad=0`；
  5. R1/R2/R3 `SS_RAW_MATCH bad=0 checked=518400`；header raw/xform CRC；
  6. 8 个负对照全部拒绝；G25 未用于降档；无 aggregate 2C；
  7. DUT 0 修改、白名单 diff、输入 SHA 0 mismatch、写范围、预算、0 TD/板卡。
- `report_paths`: `four-run-report.md`、`out/*`、`sim/caps/*`、`sim/logs/*`
- `input_status`: `same`（P1/P2/P3/内容源 SHA 已复算，0 mismatch）
- `reuse_decision_paths`: `input-verified.json`、`manifest-r0.json`
