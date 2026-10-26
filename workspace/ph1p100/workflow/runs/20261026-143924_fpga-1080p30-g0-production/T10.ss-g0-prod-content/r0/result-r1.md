# T10.ss-g0-prod-content r1 — 开发结果（round1：仅修 harness 看门狗，同内容 4 帧实测）

- 任务：`T10.ss-g0-prod-content`（run `20261026-143924_fpga-1080p30-g0-production`，round **1**，同一开发会话续接）
- 角色：fpga-dev（不自判验收）；**status = `partial`**：4 帧稳态**两类均已实测**，但 dev-plan A3 的冻结子句 `dup=0` 不成立（N `dup=3896`、L `dup=568`），故 A3 按字面**未满足**，需原规划裁决 `dup` 语义（见 §5）
- 每类 G0（指南 §3 机械口径）：**N = `G0_not_closed`**（S_ss 7,475,240 > 6,250,000）、**L = `G0_not_proven`**（sink_limited 61.725%）
- 包 headline：**`G0_not_proven`**（两类中较弱者 + A3 有效性待裁决）
- 修复范围：**只改 harness**——新 TB `src/tb_ss_4run_wd.v`（两段式看门狗）+ `kind=exp` 追加只读 `bytes=`；12 DUT 源、内容、门槛、G0 口径**全部未改**

## 1. 结论（回答 P1 的问题）

在**图像派生的自然场景内容**（非传感器 RAW）上，1080p30 G0 **在 TB slot-free + 93.75 MB/s sink 的冻结 scope 内不成立**，而且**卡点不是 sink、是压缩核吞吐**：

| | N（自然场景） | L（低照夜景） |
|---|---|---|
| 实测 `S_ss` | **7,475,240** cycles | **6,986,952** cycles |
| 相对 G0（6,250,000） | **+19.60%**（需 1.196×） | **+11.79%**（需 1.118×） |
| 等效 | 25.083 fps / 65.015 MB/s | 26.836 fps / 69.558 MB/s |
| `tail_frac` | 44.878%（<50%） | **61.725%（≥50% → sink_limited）** |
| `bottleneck_attribution` | **core_interval** 7,475,238 vs export_time 3,354,672（2.23×） | **core_interval** 6,986,951 vs export_time 4,312,600（1.62×） |
| 每帧压缩流 | 1,677,336 B（1.5453:1） | 2,156,300 B（1.2021:1） |
| 压缩流自身 sink 需求（33.33/25.0 ms） | 50.32 / 67.09 MB/s | 64.69 / 86.25 MB/s |

- 两类**压缩流**的 sink 需求（50–86 MB/s）**都低于**冻结 93.75 MB/s；即**即使把 sink 提到 103.79 MB/s，自然内容仍到不了 G0**——瓶颈是每帧压缩/读取的核间隔（N 7.475M、L 6.987M cycles），与 r0 的推导方向一致但现在是**实测**。
- L 的 `sink_limited=true` 按冻结规则**仍然**使 G0 = `G0_not_proven`；但报告不声称"sink 是唯一约束"：L 的 core_interval 6.987M 已 > G0 6.25M，**core-bound 才是主因**（指南 §3 要求）。
- 冷启动单列：N `L_cold=12,440,137`（=1.990×G0）、L `L_cold=12,901,615`（=2.064×G0）。**冷启动既不是 G0 失败证据也不是通过证据**，不进 `S_ss`。

## 2. A3 逐子句（N 与 L 各一次全尺寸 4 帧）

| A3 子句 | N | L |
|---|---|---|
| `t_exp(1..4)` 全非空 | **✔** 12,440,157 / 19,914,239 / 27,389,479 / 34,864,719 | **✔** 12,901,635 / 19,887,447 / 26,874,402 / 33,861,351 |
| `cap=enc=exported=4` | **✔** 4/4/4 | **✔** 4/4/4 |
| `read=518,400` | **✔** 518,400 | **✔** 518,400 |
| 有 `SS_STATS` 行 | **✔**（`stats_rows_present=true`，293 B / 292 B 实文本） | **✔** |
| `raw_drop=cmp_drop=geom=err=wd=0` | **✔** 0/0/0/0/0（实测） | **✔** |
| **`dup=0`** | **✘ dup=3896** | **✘ dup=568** |
| `SS_RAW_MATCH bad=0 checked=518400` | **✔** bad=0 checked=518400 drv_groups=2073600 | **✔** 同 |
| header CRC | **✔** `raw_crc`=内容 crc32、`header_crc`=crc32(hdr[0:40])、`raw_len=xform_len=2,592,000` | **✔** |
| 结束方式 | 正常 `$finish`（无 `SS_STALL_COLD`/`SS_STALL`/`B11_FULL_TIMEOUT`），34,866,718 cycles | 同，33,863,350 cycles |
| **A3 判定** | **frames_complete=true；A3_complete=false（唯一失败子句 `drops_all_zero`）** | 同 |

- 说明：`ss_pass=0`（TB 自带 `ss_pass` 表达式含 `st_dup==0`）与 `B11_FULL_RESULT pass=0` 都是这个 `dup` 子句的后果；**不是**缺帧、丢帧或数据错误。`raw_crc`/`SS_RAW_MATCH`/`err`/`geom`/`wd` 全部干净。

## 3. 指标（实测，可逐值复算）

| 量 | N | L |
|---|---|---|
| `t_enc(1..4)` | 9,084,241 / 16,559,475 / 24,034,715 / 31,509,955 | 8,587,807 / 15,574,755 / 22,561,710 / 29,548,659 |
| `t_sof(1..4)` | 61 / 1,608,650 / 9,084,242 / 16,559,476 | 61 / 1,608,650 / 8,587,808 / 15,574,756 |
| `L_cold = t_exp(1)-t_rst`（t_rst=20） | **12,440,137**（raw t_exp(1)=12,440,157） | **12,901,615**（raw 12,901,635） |
| `L_cold/6,250,000` | **1.9904** | **2.0643** |
| `S_2 / S_23 / S_34` | 7,474,082 / 7,475,240 / 7,475,240 | 6,985,812 / 6,986,955 / 6,986,949 |
| **`S_ss=(S_23+S_34)/2`** | **7,475,240**（spread 0 cycles） | **6,986,952**（spread 6 cycles） |
| `tail(k)=t_exp-t_enc` | 3,355,916 / 3,354,764 / 3,354,764 / 3,354,764 | 4,313,828 / 4,312,692 / 4,312,692 / 4,312,692 |
| `tail_mean(2..4)` / `tail_frac` | 3,354,764 / **44.878%** | 4,312,692 / **61.725%** |
| `sink_limited`（≥50%） | **false** | **true** |
| `C_ss` | **65.0146 MB/s** | **69.5582 MB/s** |
| `fps` | 25.0828 | 26.8357 |
| `margin_G0` | **−16.391%** | **−10.548%** |
| `margin_G25`（**仅参考列**） | −33.113% | −28.438% |
| `G0` | **`G0_not_closed`** | **`G0_not_proven`** |

**逐帧 exp_bytes / 压缩比 / 导出时长 / 核间隔（A3b 必填）**

| k | N bytes | N ratio | N export_time | N core_int | N bottleneck | L bytes | L ratio | L export_time | L core_int | L bottleneck |
|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|---|
| 1 | 1,677,912 | 1.5448 | 3,355,824 | — | — | 2,156,868 | 1.2017 | 4,313,736 | — | — |
| 2 | 1,677,336 | 1.5453 | 3,354,672 | 7,475,234 | **core_interval** | 2,156,300 | 1.2021 | 4,312,600 | 6,986,948 | **core_interval** |
| 3 | 1,677,336 | 1.5453 | 3,354,672 | 7,475,240 | **core_interval** | 2,156,300 | 1.2021 | 4,312,600 | 6,986,955 | **core_interval** |
| 4 | 1,677,336 | 1.5453 | 3,354,672 | 7,475,240 | **core_interval** | 2,156,300 | 1.2021 | 4,312,600 | 6,986,949 | **core_interval** |

`export_time(k)=2×bytes(k)`（冻结 TB sink 2 clk_a1/B，93.75 MB/s）；`core_interval(k)=t_enc(k)-t_enc(k-1)`。
4 帧同图 → 每帧字节几乎恒定（k≥2 完全相同），`S_23=S_34` 精确相等，`S_ss` 无抖动（这是"同帧重复稳态窗口"的性质，**不建模时域变化**，属覆盖缺口）。

**原始带单列（与压缩流 tail 分开）**：2,594,706 B/帧；93.75 MB/s → 5,189,412 cycles（27.677 ms，83.03%）；103.79 MB/s → **4,687,500** cycles（25.000 ms，75.00%，`4,687,421` 为同一值的取整等价值）。本包未修改该冻结口径。

## 4. DUT 侧闭环与内容绑定

| 项 | N | L |
|---|---|---|
| 导出头 `stream_len`（前 44 B，DUT 自写） | 1,677,912 | 2,156,868 |
| `raw_crc` vs `zlib.crc32(raw_{n,l}.bin)` | **相同**（`da799650` / `2a321e2a`） | 同 |
| `header_crc` = crc32(header[0:40]) | ✔ | ✔ |
| `SS_RAW_MATCH` | bad=0 checked=518400 | 同 |
| `exp_bytes`（4 帧累计）/ `cap_bytes` | 6,709,920 / 6,710,096（= +4×44 头） | 8,625,768 / 8,625,944 |

## 5. 关键新发现：`dup` 不是"重复读 DDR"，而是"相邻 256-bit 原始字逐位相同"

- 源码：`a1_ddr_slot_store.v:281-282`
  ```verilog
  if (rd_prev_v && (ddr_rdata === rd_prev))
      st_dup_words <= st_dup_words + 32'd1;
  ```
  即每次 DDR 读到的 256-bit 字**与上一个字逐位相同**就 +1。它是**内容统计量**（平坦区域/相邻 32 像素相同），**不是**重复地址读、不是重传、不增加 DDR 流量，也不影响数据正确性（`raw_crc`/`SS_RAW_MATCH`/`err`/`stream_crc` 全部自洽）。
- 为什么 r0/P4 没见过：合成 C1（梯度，32:1）与 C2（stored rand，1:1）都不产生相邻逐位相同的字 → `dup=0`。自然图像有大片平坦区（N 天空/水面 0.7516%，L 夜空 0.1096%）→ `dup>0`。
- 后果与边界：冻结 TB 的 `ss_pass` 表达式与 dev-plan A3 / 指南 §3 的有效性子句都含 `dup=0`，因此**该类 run 的 `ss_pass=0`、A3 按字面不满足**。本包**不自行豁免**该子句，也不改 TB 的 `ss_pass`（裁决禁止）；`dup` 是否应留在有效性门槛内，须由原规划裁决（与 r0 `WD_LIMIT` 同类：**harness/门槛假设与自然内容不兼容**，不是 DUT 缺陷、不是内容造假）。
- 对指标无影响：`S_ss/tail/tail_frac/sink_limited` 与 `dup` 无关；N 仍由 `S_ss>6.25M` 判 `G0_not_closed`，L 仍由 `sink_limited` 判 `G0_not_proven`。

## 6. 修复内容与冻结（M4/M5）

- 新 TB：`src/tb_ss_4run_wd.v`（480 行，`785c3ef1…0b79a`）。r0 的 `src/tb_ss_4run.v`（`7f5cc294…47f81`）**原样保留、未改**。
- 白名单**机械校验**（不是人眼看 diff）：`sim/run_content_r1.py verify` 用 r0 TB 原文只应用 3 处字面替换（①插入 `WD_LIMIT_COLD`、④exp 两行加 `bytes=`、②③⑤替换注释+看门狗块）得到 `canonical_r1`，与实际文件**逐字节相等** → `whitelist_ok=true`；`force/deposit/release` 出现次数 **0/0/0**。详见 `src/DIFF-r1.md`。
- 未改：`drive_frame`/帧间隔/几何/时钟/复位/`PACING`/`SINK`/`FRAMES`/`CONTENT`/`CAPTURE` 语义/`ss_pass` 表达式/drain/`MAX_CYCLES` 源码值（用 `-gMAX_CYCLES=60000000` 覆盖）/其它 EVT 字段。
- 冻结输入零漂移：12 DUT 源 SHA 与 `manifest-r0.json` 逐条相同；`raw40_{n,l}.hex`、`raw_{n,l}.bin` SHA 与 r0 `content-map.json` 相同；`manifest-r0.json` SHA 仍为 `e55e7965…9a74`。证据：`out/r1-verify.json`。
- 独立库：`%TEMP%/opencode/ss-g0-prod-content/work-r1`（r0 的 `work` 未复用、未改动）。

## 7. 元数据修正（M1/M2/M3，r0 旧文件不改写）

| # | 对象 | r0 旧值（冻结保留） | r1 新值 |
|---|---|---|---|
| M1 | `out/content-verdict-r1.json.P1_answer` | `content-verdict.json` 写"4-frame steady state is obtainable…"，与 `frames_exported=0` 矛盾（OBS-1） | 与实测一致：4 帧已实测，A3 因 `dup` 不满足，G0 按实测 S_ss/sink_limited 给出；**不再出现"obtainable"** |
| M2 | `out/run-status-r1.json` | `stats_exists=true`（0 B 文件，OBS-2） | `stats_rows_present`（有 `ss_pass=` 行才 true；本次两类 **true**）+ 保留 `stats_file_created`/`stats_bytes` |
| M3 | `result-r1.md`（本文件） | — | 明写 r0 的 `P1_answer`/`stats_exists` 已被 r1 取代；r0 的 `result-r0.md`、`content-verdict.json`、`run-status.json`、`manifest-r0.json` **一个字节都没改** |
| M6 | 指南 §3 勘误 | — | 规划已裁决：`103.79 MB/s = 4,687,500 cycles（25.0 ms）`；本包按此口径引用，百分比不变 |
| M7 | 派生值 | r0 7.48M/6.98M（`derived_not_measured`，基准 1,608,000） | r1 **实测** 7,475,240 / 6,986,952 取代；r0 推导的误差仅 −0.013% / +0.102%（用 `t_pub(1)=1,607,996` 复核），但**不再用于任何判定** |

## 8. 预算记账（`sim/commands-r1.jsonl`）

| 项 | round1 实测 | 上限 |
|---|---|---|
| 全尺寸 4 帧 vsim | **2**（N 1,962.4 s + L 1,802.0 s = 3,764.4 s = 62.7 min） | ≤2 次 / ≤95 min |
| 单次硬超时 | 2700 s（均未触发；最慢 1,962.4 s，余量 27%） | 2700 s |
| P1 累计全尺寸 | **4**（r0 2 + r1 2） | ≤6 |
| P1 累计 vsim 墙钟 | **86.1 min**（r0 1,400.5 s + r1 3,764.4 s = 5,164.9 s） | ≤200 min |
| 预检 | 0（本轮不需要，r0 已证内容通路） | ≤300 s |
| TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK/网络 | **0** | 0 |

## 9. 判定、范围与不外推

- 每类 `G0`：**N = `G0_not_closed`**（S_ss 7,475,240 > 6,250,000，缺口 1,225,240 cycles / +19.60%）；**L = `G0_not_proven`**（`tail_frac` 61.725% ≥ 50%，冻结规则）。
- 包 headline：**`G0_not_proven`**（较弱者；且 A3 `dup` 子句待裁决）。**P1 不因 G0 未过而 FAIL**，但 A3 按字面未满足，故本包 status = `partial`，不自称 PASS。
- scope（每类写死，`G0_scope` 字段）：content = 图像派生 Bayer（**非传感器 RAW**）；pacing = TB `wait_slot_free`（**非生产自由跑**）；sink = 冻结 93.75 MB/s TB 代理；DDR = 行为级 256-bit PAXI 模型；core = 单 a1 @187.5 MHz；stream = 单路。
- G25 仅在 `margin_G25_pct_ref`，**未进 headline、未用于降档**。
- **不证明**：真实传感器 RAW、全内容/最坏内容、生产 free-run pacing、生产 sink ≥103.79 MB/s、真实 DDR/PAXI sustained、PCIe/UART transport、板级、双路、RK/NPU、192.642 MHz、资源/时序（无 TD）。

## 10. 下一步（交原规划；本包不越界）

1. **裁决 `dup` 语义**：`st_dup_words` = 相邻 256-bit 原字逐位相同（`a1_ddr_slot_store.v:281-282`），是内容统计量而非重复读。若认可，则 A3 的有效性子句应改为 `raw_drop=cmp_drop=geom=err=wd=0` + `dup` 只作记录（不改 G0 门槛、不改 TB `ss_pass` 以外的任何东西）；若不认可，需在 round2 用新 TB 把 `dup` 从 `ss_pass` 中移除并写白名单 diff——二者都是 harness 层面，不改 DUT/内容/门槛。
2. **P3 的输入**：自然内容的瓶颈是核间隔（N 7.475M / L 6.987M cycles），**不是** sink；L 的 `tail_frac` 61.7% 说明 93.75 MB/s 也已不够快，但把 sink 提到 103.79 只能把 L 的 tail 从 4.313M 降到约 3.9M，L 的 core_interval 6.987M 仍然超 G0。P3 必须用 P1 的 N/L 内容 + P2 的 pacing 才能给出生产口径结论。
3. r0 的 `result-r0.md`/`content-verdict.json`/`run-status.json` 保持冻结，`P4` 合并只允许引用 r1 的实测值与本文件的 §5/§7 说明。

## 11. 复现命令

```powershell
$dst='D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\T10.ss-g0-prod-content\r0'
python "$dst\sim\run_content_r1.py" verify     # 白名单机械校验 + r0 零漂移
python "$dst\sim\run_content_r1.py" compile    # 独占 work-r1
python "$dst\sim\run_content_r1.py" run n      # 1962.4 s, rc=0
python "$dst\sim\run_content_r1.py" run l      # 1802.0 s, rc=0
python "$dst\sim\run_content_r1.py" analyze
python "$dst\sim\run_content_r1.py" manifest
```
