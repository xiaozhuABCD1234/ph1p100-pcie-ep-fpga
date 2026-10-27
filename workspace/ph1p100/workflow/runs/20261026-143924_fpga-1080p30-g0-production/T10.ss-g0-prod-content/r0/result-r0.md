# T10.ss-g0-prod-content r0 — 开发结果（P1：真实/自然/低照内容 4 帧锚点）

- 任务：`T10.ss-g0-prod-content`（run `20261026-143924_fpga-1080p30-g0-production`，本轮唯一包）
- 角色：fpga-dev（开发，不自判验收）；状态：**partial**（证据有效、复算可做，但**两次 run 都未拿到 4 帧稳态**）
- headline（本包）：**`G0_not_proven`**；N/L 两类均为 `G0_not_proven`（缺 4 帧实测，非"内容不可信"）
- 冻结输入：DUT 12 源 0 修改 + `tb_ss_4run.v` 逐字节副本；口径全部取 `fpga-design-guide.md` §1–§4

## 1. 结论（回答 P1 的问题）

在**非合成 C1/comp 代理**的内容上，本包**未能**取得可信的 4 帧 `S_ss`。卡点不是内容源、不是自检、不是 DDR/丢帧，而是：

1. **冻结 TB 的看门狗**：`tb_ss_4run.v` 的 `WD_LIMIT` 是 `localparam 12,000,000`（不可参数化覆盖）。自然内容的单帧冷启动（采集+读取+压缩+导出首帧）超过 12,000,000 cycles → `SS_STALL` + `$finish`，**没有 stats 行**。
   - N：`enc(1)=9,084,241`，首帧流长 `1,677,912 B`（DUT 导出头实测）→ 导出需 `2×1,677,912=3,355,824` cycles → 首帧导出完成时刻 ≈ **12,440,065**（超看门狗 3.7%）。
   - L：`enc(1)=8,587,807`，首帧流长 `2,156,868 B` → 导出 `4,313,736` cycles → ≈ **12,901,543**（超 7.5%）。
2. **压缩吞吐**是本包暴露的主约束，**不是**sink：自然内容每帧压缩延迟 N=7,476,241 / L=6,979,807 cycles，是 P4 合成内容基线（4,677,960 / 4,678,548）的 **1.60× / 1.49×**。
3. 结论口径：自然/低照内容的 1080p30 G0 **在本包 scope 内未证明**（`G0_not_proven`）；按实测标定的推导（§7，明确标 `derived_not_measured`）指向 N `G0_not_closed`（S_ss≈7.48M，+19.6%）、L `G0_not_proven`（sink_limited 61.8%）。**两者都离 G0 有实质缺口，不是"差一点"**。

## 2. 内容源审计（`content-audit.json`，19 个候选）

| 编号 | 对象 | 分类 | 可用 |
|---|---|---|---|
| — | 全仓库 `.raw/.dng/.cr2/.nef/.arw/.raf/.orf/.sr2` 扫描（48,013 文件，未截断） | 8 个 `.raw` 全为 `T10.a1-format-ref` 合成格式向量；**0 个相机/传感器 RAW 容器** | — |
| C1/C2 | `T10.a1-adler-smem/.../f1080p_p1d1, f1080p_rand/raw.bin` | `full_frame_raw_synthetic` | 否（仅 P4 对照） |
| C3_C7 | `work/.../codec-throughput/comp/in.hex` | `proxy_transport_stream` | 否 |
| UI01–UI06 | `runD board/t02/samples/**/*.png`（1873×851 等 6 张） | `ui_screenshot`（VNC 桌面 + TD timing analyzer 窗口） | **否（禁止当自然场景）** |
| SCR07–SCR10 | `fpga/csi2/_scratch/sony_*.png` | `test_graphic` | 否 |
| BLOOM×4 | `img100/101/103/104.jpg` | `abstract_render`（Win11 Bloom） | 否 |
| **N** | `C:/Windows/Web/Screen/img102.jpg` | `natural_scene_image`（黄昏湖面/雪坡树线/太阳/水面倒影） | **是** |
| **L** | `C:/Windows/Web/Screen/img105.jpg` | `low_light_natural_scene`（夜景长曝星轨 + 栈桥/湖面倒影） | **是** |

- **`real_sensor_raw` 不存在**（`no_real_sensor_raw: true`），P1 不声称任何真实 IMX415 RAW。
- 两张源图均为 OS 示例资产（display-referred JPEG），只读读取 + 参数复制入 run；**无网络**。

## 3. 内容派生与冻结（`content-map.json`）

| 项 | N | L |
|---|---|---|
| 源 SHA256 / 尺寸 | `0e3c9c17…d7da512` / 6400×4000 | `bf83916b…c587ec3` / 1920×1080 |
| crop/scale | 中心裁 16:9 `(0,200,6400,3800)` → 6400×3600 → LANCZOS 1920×1080 | 原生 1920×1080，无裁无缩 |
| CFA / 位深 | RGGB（0,0=R）；10-bit 0..1023，饱和到 1023，无 dither | 同 |
| 传递/量化 | `code=round(sRGB8×1023/255)`（**声明保留 sRGB 传递**，不做线性化；选它因为保细节=更高熵=更难，避免乐观） | 同 |
| 噪声注入 | **无**（确定性派生） | **无** |
| 暗部占比（<5% 满量程） | 2.8642%（<10%：14.5525%） | **5.7528%**（<10%：19.0815%） |
| 饱和像素比（=1023） | 0.0000% | 0.2941% |
| 均值/标准差/max | 318.092 / 183.009 / 975 | 268.565 / 197.233 / 1023 |
| `raw_*.bin` | `18a12ecb…e9f2504`，2,592,000 B，crc32 `da799650` | `8c9c02b9…c9383720`，2,592,000 B，crc32 `2a321e2a` |
| `raw40_*.hex` | `e44fe7bc…cd7b53`，5,702,400 B，518,400 行 | `e7e3c21c…7deefa2`，5,702,400 B，518,400 行 |
| 帧数 | 4 帧（同图重复，稳态窗口） | 4 帧（同图重复） |

标签（严格按指南 §4）：N = `natural_scene_image` + `proxy_not_natural_raw` + `not_sensor_raw` + `proxy_not_worst` + `display_referred`；L 首标签为 `low_light_natural_scene`，其余相同。

> L 类**未注入传感器噪声**：真实低照 RAW 的 shot/read 噪声会使码流更难压缩，因此 L 的数值**不具备低照最坏内容证明力**（`proxy_not_worst`）。N 类为全幅下采样，不是原生分辨率裁切，也不是最坏内容。

## 4. 字节级自检（`input-verified.json`，全部 `True`）

| 检查 | N | L |
|---|---|---|
| geometry 2,592,000 B / 518,400 组 / stride 2400 | ✔ | ✔ |
| hex→bin 逐组反解回打包 `mismatch` | **0** | **0** |
| 组打包恒等式（`p→b→p`，且 `p≤1023`）`bad` | **0** | **0** |
| 反解像素 vs 派生 mosaic `mismatch`（518,400 组） | **0** | **0** |
| bin/hex SHA + crc32 与 content-map 一致 | ✔ | ✔ |

- **打包器交叉校验（非自证）**：用本包的 `bin→hex` 函数重算 P4 冻结件 `raw40_p1d1.hex`（518,400 组 / 2,592,000 B）→ **mismatch = 0**，证明位序与 P4 冻结口径逐位一致。
- **DUT 侧闭环**：两次 run 的导出头 `raw_crc` 分别等于本包 `raw_N.bin` crc32 `da799650` 与 `raw_L.bin` crc32 `2a321e2a`，`header_crc` 自洽，`raw_len=xform_len=2,592,000` → 内容→DUT 字节映射由 DUT 自己复核通过（`header_check.pass=true`）。

## 5. DUT/TB 冻结（engineering）

- 12 源副本：8 个与 b11 `changed-src` **逐字节相同**（a1_raw_crop / a1_ddr_slot_store / a1_uart_export / camera_a1_uart_top / cam_diag_mailbox / a1_frame_top / a1_deflate_core / p2_ddr_bridge），2 个与 b11 `r0/sim` 相同（p2_paxi_model_b11 / a1_ddr_model）；`a1_ddr_arb2.v`、`capture_async_fifo.v` 在 b11 内无副本，复核其上游原件（`fpga/csi2/src/a1/`、`fpga/csi2/src/mem/`）见 `out/src-origin-check.json`。**DUT 源码 0 修改。**
- `src/tb_ss_4run.v` 为 P4 冻结 TB 的**逐字节副本**（无 diff、无白名单外改动）；`+RAW40/+STAT/+EVT/+HDR`、`FRAMES=4 CONTENT=2 PACING=0 SINK=1 CAPTURE=0`。
- 每任务独占：`%TEMP%/opencode/ss-g0-prod-content/work`（自带 `vlib`/`modelsim.ini` 副本）、本 run 的 `logs/`、`sim/caps/`；无共享盘符映射；无 TD/综合/板卡/网络。

## 6. 两次全尺寸 run 的实测事实

| 项 | N | L |
|---|---|---|
| 命令 rc / 墙钟 | 0 / **712.7 s** | 0 / **687.8 s** |
| 终止原因 | `SS_STALL frame=1 cycles=12,000,001 read=181,202 enc=1 exported=0` | 同，`read=204,002` |
| stats 行 | **无**（`$finish` 在 stats 落盘前） | **无** |
| `t_rst / sof(1) / pub(1) / cam_end(1)` | 20 / 61 / 1,607,996 / 1,608,249 | 同（逐周期一致） |
| `sof(2)/pub(2)/cam_end(2)` | 1,608,650 / 3,216,585 / 3,216,838 | 同 |
| `read(1)`（129,600 words 读完） | 9,042,756 | 8,543,950 |
| `enc(1)` | 9,084,241 | 8,587,807 |
| `pub(3)/cam_end(3)` | 10,692,177 / 10,692,430 | 10,195,743 / 10,195,996 |
| `SS_RAW_MATCH` | `bad=0 checked=518400 drv_groups=518400` | 同 |
| 导出头 `stream_len`（首帧流长，实测） | **1,677,912 B** | **2,156,868 B** |
| 导出头 `raw_crc` vs 内容 bin crc32 | 3,665,401,424 = `da799650` ✔ | 707,927,594 = `2a321e2a` ✔ |
| 压缩比（2,592,000/stream_len） | 1.545 : 1 | 1.202 : 1 |
| 单帧压缩延迟（`enc(1)-1,608,000`） | **7,476,241** | **6,979,807** |
| raw_drop / cmp_drop / geom / err / dup / wd | 0（`pub` 计数 3/4 前均正常，无丢帧标志） | 同 |

- 两次 run 的 `sof/pub/cam_end` 时刻与 P4 四条 run **逐周期相同**（1,607,996 / 3,216,585），说明 TB 采集/pacing 未变、行为确定。
- 预检（1 帧，`precheck`，**不计 4 帧证据**）：300 s 上限触发 `rc=124`（记录 301.7 s，含 taskkill 收尾）；被 kill 前已打印 `SS_RAW_MATCH bad=0 checked=518400`，证明内容加载/驱动通路正确。**缺陷如实记录**：该次硬 kill 未回收 `vsim/vish`，run N 开始前检测到残留进程（N 结束前自行退出），L 前已确认清零；仿真周期数与 CPU 竞争无关（两次 run 前段事件逐周期一致），但 N 的 712.7 s 墙钟可能含竞争。
- **进程收尾（冻结前）**：L 结束后另有 4 个空闲 ModelSim 包装进程（`vsim`/`vish`，15:33:51 启动，CPU≤1.2 s，已无仿真活动）残留，已在冻结 `manifest-r0.json` **之前**全部终止（此后 `Get-Process vsim,vish` = 0）；终止前后 `logs/*.log` 的字节数与 mtime 均未变化（n.log 15:23:17 / 7,170 B，l.log 15:38:21 / 7,170 B），故 `active_commands=0` 与 manifest 哈希均未被污染。

## 7. 指标（官方不可计算；推导值单列，`derived_not_measured`）

`S_ss/tail/tail_frac/sink_limited` 需要 `t_exp(1..4)`，本包**没有** → 官方口径只能给：

```
N: S_ss = n/a, tail = n/a, sink_limited = n/a, G0 = G0_not_proven  (4/4 未达成)
L: S_ss = n/a, tail = n/a, sink_limited = n/a, G0 = G0_not_proven  (4/4 未达成)
```

推导（**不是实测，不得当 G0 证据**）：P4 r1 的 `enc(1)-1,608,000 = 4,677,960` 与其实测 `S_ss=4,677,970` 相差 10 cycles（0.0002%），说明本 TB 下"首帧压缩延迟 ≈ 稳态间隔"。据此：

| 量（推导） | N | L |
|---|---|---|
| 首帧导出时长 `2×stream_len` | 3,355,824 | 4,313,736 |
| 推导 `t_exp(1)` | ≈12,440,065 | ≈12,901,543 |
| 推导 `S_ss` | ≈7,476,241（G0 **+19.62%**） | ≈6,979,807（G0 **+11.68%**） |
| 推导 `tail_frac` | 44.88%（<50%） | **61.80%（≥50% → sink_limited）** |
| 推导判定 | `G0_not_closed`（S_ss>6.25M） | `G0_not_proven`（sink_limited） |
| 压缩流 sink 需求（33.3 ms / 25.0 ms） | 50.34 / 67.12 MB/s | 64.71 / 86.27 MB/s |

**原始带单列（指南 §3，按字节与 187.5 MHz 独立算）**：2,594,706 B/帧；93.75 MB/s → 5,189,412 cycles（27.677 ms，G0 的 83.03%）；103.79 MB/s → **4,687,421** cycles（25.000 ms，75.00%）。
> 勘误提示（只记录、未改冻结值）：指南 §3 写"103.79 MB/s = 5,000,000 cycles"，按字节/时钟应为 4,687,500 cycles（2,594,706÷103.79e6=25.0 ms）；两个百分比（83.03%/75.00%）不受影响。请 P3 复核该处，本包未修改任何冻结口径。

## 8. 判定与范围（不外推）

- 每类 `G0 ∈ {G0_feasible_for_scope, G0_not_closed, G0_not_proven}`：**N = `G0_not_proven`，L = `G0_not_proven`**；包 headline = **`G0_not_proven`**。
- scope（每类均写死）：content = 图像派生 Bayer（**非传感器 RAW**）；pacing = TB `wait_slot_free`（**非生产自由跑**）；sink = 冻结 **93.75 MB/s** TB 代理（**非生产 sink**）；DDR = 行为级 256-bit PAXI 模型；core = 单 a1 @187.5 MHz；stream = 单路。
- G25（5,000,000 / 97.20 MB/s）**仅参考列**，未进 headline、未用于降档。
- **本包不证明**：真实传感器 RAW、全内容/最坏内容、生产 free-run pacing、生产 sink ≥103.79 MB/s、真实 DDR/PAXI sustained、PCIe/UART transport、板级、双路、RK/NPU、192.642 MHz、资源/时序（无 TD）。

## 9. 负对照（`out/negative-controls.json`，全部成立）

`TB_SLOTFREE_AS_PRODUCTION`、`93_75_SINK_AS_103_79`、`SYNTHETIC_OR_DERIVED_AS_REAL_SENSOR_RAW`、`3FRAMES_AS_4FRAMES`（0 帧不得当 4 帧；两类均如实 `G0_not_proven`）、`G25_AS_G0`、`MODEL_AS_RTL`、`AGGREGATE_AS_PERSTREAM`、`UI_SCREENSHOT_AS_NATURAL`。

## 10. 预算记账（`sim/commands.jsonl`）

| 项 | 实测 | 上限 |
|---|---|---|
| 全尺寸 4 帧 vsim | **2**（N 712.7 s + L 687.8 s = 1,400.5 s ≈ 23.3 min） | ≤2 次 / ≤90 min |
| 预检 vsim | 1 次，301.7 s（cap 300 s，含 kill 收尾，`rc=124`） | ≤300 s，标 precheck |
| 单次硬超时 | 2700 s（两次均未触发） | 2700 s |
| TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK | **0** | 0 |
| 网络 | **0** | 0 |
| 墙钟（角色） | 约 65 min | ≤120 min |

## 11. 恢复入口与下一步（交原规划决定，本包不越界）

- 回退：删除/忽略 `T10.ss-g0-prod-content/**` 即回到 P4 冻结态；生产源与旧 run 未改。
- 若要拿到自然内容的 4 帧稳态，**必须换 TB**（P1 冻结 TB 不允许改 `WD_LIMIT`）：把 `WD_LIMIT` 提到 ≥ 20,000,000（或把看门狗改成"首帧 SOF 起算"），其余保持 P4 口径；这属于 P2/P3 允许的"新 TB + 逐行 diff + 白名单"范围，**不是 P1 可自行放宽的项**。
- 或（成本更低、信息量等价）：保持冻结 TB，改测 **1 帧 + 首帧压缩延迟**作为 S_ss 估计器（本包已验证 r1 中该估计器误差 0.0002%），但必须标 `estimate_not_steady`，不得当 4 帧证据。
- 对 P3 的直接影响：自然内容的压缩流只有 1.68/2.16 MB/帧，**压缩流**的 sink 需求 50.3–86.3 MB/s 已低于 93.75 上限；真正的瓶颈是**压缩吞吐**（≈7.5M cycles/帧）。P3 若只把 sink 提到 103.79 MB/s 而不动压缩核，自然内容仍到不了 G0。

## 12. 复现命令

```powershell
$dst='D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\T10.ss-g0-prod-content\r0'
python "$dst\sim\run_content.py" audit      # content-audit.json
python "$dst\sim\run_content.py" prep       # content/*.bin,*.hex, content-map.json
python "$dst\sim\run_content.py" verify     # input-verified.json（hex↔bin / 打包恒等式 / mosaic / P4 交叉校验 / 源 SHA）
python "$dst\sim\run_content.py" compile    # 独占 %TEMP%/opencode/ss-g0-prod-content/work
python "$dst\sim\run_content.py" precheck   # 1 帧，≤300 s，precheck 标记
python "$dst\sim\run_content.py" run n      # FRAMES=4 CONTENT=2 PACING=0 SINK=1 CAPTURE=0
python "$dst\sim\run_content.py" run l
python "$dst\sim\run_content.py" analyze    # out/content-verdict.json / runs.json / content-table.csv
python "$dst\sim\run_content.py" manifest   # manifest-r0.json
```
