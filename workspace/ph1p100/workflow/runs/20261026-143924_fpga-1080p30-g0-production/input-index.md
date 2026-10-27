# 输入索引与事实基线 — `20261026-143924_fpga-1080p30-g0-production`

- 角色：fpga-planner；项目根 `D:/fpga/ph1p100`；输出目录 `D:/fpga/ph1p100/workflow/runs/20261026-143924_fpga-1080p30-g0-production`
- 本轮唯一主要目标：把 1080p30 G0 从「合成/代理 + TB slot-free + 93.75 MB/s sim sink」推进到**可负责的生产前提**，并给三选一 headline（`G0_feasible_for_scope` / `G0_not_closed` / `G0_not_proven`）。
- 本轮边界：只做 FPGA 侧离线仿真/模型/报告；TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK = 0；不改任何生产源、旧 run 冻结件、tasks.json、docs、work、.agents。

## 1. 需求与硬门槛（不改写、不降档）

| 项 | 冻结值 | 来源 |
|---|---|---|
| G0 per-stream 1080p30 | **77.76 MB/s = 6,250,000 cycles @187.5 MHz**（2,592,000 B×30 fps） | request.md；P4 `g0-verdict.json` `hard_gate` |
| G25（仅参考） | 97.20 MB/s / 5,000,000 cycles | 仅参考列；**不得用于降档、不得进 headline** |
| RAW 帧几何 | 1920×1080 packed RAW10，stride 2400 B，480 组/行，518,400 组/帧，2,592,000 B/帧 | P3/P4 content-map |
| RAW band 导出（含 44 B 头） | **2,594,706 B/帧**（不是 2,594,750） | P4 报告 §4.5 勘误；`runs-4.csv` |
| 生产 sink 需求 | **≥77.84 MB/s**（33.33 ms/帧，G0）/ **≥103.79 MB/s**（25.0 ms/帧，稳健） | P4 `measured_sink`；P3 G0 报告 §3 |
| 冻结 TB sink 上限 | **93.75 MB/s**（`a1_uart_export` 2 clk_a1/B 交接；`SINK=1` 只把 uart 时钟提到 2 GHz） | P4 `g0-verdict.json` |
| 加速前提 | slot-free（strict-serial −3.09%，R2−R1=1,771,435 cycles） | P4 R1/R2 |
| 单次 4 帧全尺寸墙钟 | 约 22 min（22.1 min 实测）；硬超时 2700 s | P3/P4；request.md |

## 2. 上一轮已冻结事实（只读引用，不改）

| 对象 | 路径 | 值/哈希 |
|---|---|---|
| P4 综合报告（PASS） | `workflow/runs/20261025-233401_fpga-steady-state-reverdict/test-reports/T10.ss-4run-matrix-r0-integrated.md` | headline `G0_feasible_for_scope`（scope 受限） |
| P4 manifest | `.../T10.ss-4run-matrix/r0/manifest-r0.json` | `d353c61a…6dd1`，68 artifacts |
| P4 四轮表 / 判定 / 内容图 / gap | `.../out/{four-run-table.csv,g0-verdict.json,content-map.json,gap-menu.csv}` | R1 4,677,970；R2 6,449,405；R3 5,189,503（sink_limited）；R4 5,928,286 |
| P3 G0 报告 | `.../test-reports/T10.ss-g0-closure-r2-integrated.md` | comp 代理 `S_ss=5,928,286`，93.75 sink |
| P3 manifest / TB | `.../T10.ss-g0-closure/r0/manifest-r2.json`（`3c8377a4…`）、`.../src/tb_ss_g0.v`（`a565c6f2…`） | TB 基线 |
| P4 TB | `.../T10.ss-4run-matrix/r0/src/tb_ss_4run.v` | slot-free 由 TB `wait_slot_free()` 门控 |
| P2 服务率可行性 | `workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/T10.dual-aplus-service-verdict/r0/feasibility-report.md` | 链级 75.684 MB/s（−2.67%）；raw 槽 4,147,200 B；CMP 槽 8 MiB |
| DDR 文档 | `docs/DDR1333集成与1333vs1600对比_2026-10-17.md` | DDR3-1333 x32、CK 666.67 MHz、CWL7/CL10；sustained 未上板证 |
| 任务板 | `workflow/tasks.json`（**只读**） | 父任务 T10「压缩 RTL 与 RAW 回退」；子包沿用 T10.xxx |

## 3. 生产路径审计（本轮新增事实，规划已亲自核对源码）

生产 top = `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read/r0/changed-src/`（`camera_a1_uart_top.v` 41,313 B 等 9 文件），b11 板测线归 OpenCode，本轮**只读复制**。

| 事实 | 证据（文件:行） | 对本轮的含义 |
|---|---|---|
| 帧启动门控 `a1_can_start = (fstate==F_IDLE) && !a1_busy && !a1_out_valid && raw_rd_open_ready && cmp_begin_ready` | `camera_a1_uart_top.v:573-574` | 生产 top 的**核是帧串行**：上一帧 commit（`a1_commit`，F_END）后才起下一帧；导出可与下一帧压缩重叠（cmp store 异步）。 |
| 相机端自由跑；SOF 时无 FREE slot 则**整帧丢弃**：`skip_frame=1`、`raw_begin_deny++`、`raw_deny_nofree++` | 同文件 `:431-447` | 生产 pacing 不是「等槽」，而是「满了丢帧」。P4 的 TB `wait_slot_free()` 是**理想化代理**，不等于生产行为。 |
| 2 槽 DDR ping-pong：FREE→WRITE→READY→READING→FREE；`wr_begin_ready = ddr_ready && !wr_active && free_valid` | `a1_ddr_slot_store.v:7-11,119-121,146,256-296` | slot-free 只解决 RAW 槽并发；**压缩核仍单实例**。 |
| 相机 FIFO 溢出计数 `fifo_ovf_cnt`；`fifo_ready` 在 store 不可写时保持/丢弃 | `camera_a1_uart_top.v:310-345,384-400` | 丢帧/溢出必须进 P2 判据（>0 即 production pacing 不成立）。 |
| 生产导出 = `a1_uart_export` → 115200 UART（约 **11.52 kB/s**） | 同文件 `:769-812` | 生产真实 sink 远低于 G0；P3 只能做**离线 sink/packer 模型**，不是生产已实现。 |
| b11 集成两帧：`enc=2 exported=2 read=259200 dup=0 err=0`；板测 `device not found`，未下载 | `T10.b11-aplus-read/r0/result-r0.md` §2/§4；`sim/tb_b11_full.v` | 生产 top 有 2 帧功能证据，**无 4 帧稳态、无生产 sink、无板级**。 |
| b11 布线 SWNS +0.015 ns（<0.05 门槛） | 同上 §3 | 与时序相关的结论本轮不碰；G2 仍不适用（不跑 TD）。 |

## 4. 内容源审计（规划已实测，P1 复算并要求复核）

| 候选 | 事实 | 分类/可用性 |
|---|---|---|
| `.../T10.a1-adler-smem/r0/p3/cases/f1080p_p1d1/raw.bin`（2,592,000 B，`061b0dfc…`） | C1 合成全帧（grad），P4 已用 | `full_frame_raw_synthetic` / `proxy_not_natural` / `proxy_not_worst` |
| `.../f1080p_rand/raw.bin`（`8fe204b7…`） | C2 合成 stored rand | 同上；**不是全内容最坏证明** |
| `work/parallel-sim-20261024-2204/codec-throughput/comp/in.hex` | comp 代理（848,864 B/帧流） | `proxy_not_natural` / `proxy_not_worst` |
| **真实传感器 RAW** | 全仓库检索 `*.raw/*.bin/*.dng/*.cr2/*.nef/*.arw` + 图像文件：**未发现任何真实 IMX415 RAW 帧** | **不存在**；P1 只能写 `no_real_sensor_raw`（附检索证据） |
| `.../20261019-2117_runD_batch2_continue/board/t02/samples/T{1,2}/*.png`（6 张，T1/T2 cwc1-3） | 规划已查看 T1_cwc1：实为 **Ubuntu VNC + TD timing analyzer 窗口截图**（1873×851 RGBA），非场景照 | **禁止**当自然内容；`ui_screenshot` |
| `fpga/csi2/_scratch/sony_*.png` | 834×1179 / 893×1263 图形/测试图 | 不作为自然内容 |
| `C:/Windows/Web/Screen/img102.jpg` | 6400×4000 RGB；规划已查看：**黄昏雪山湖面自然场景**（树线/雪面/水面/天空渐变） | 可用作 **N：自然场景（display-referred）**；需标 `natural_scene_image` + `proxy_not_natural_raw` |
| `C:/Windows/Web/Screen/img105.jpg` | 1920×1080 RGB；规划已查看：**夜景长曝光星轨/栈桥**（大面积暗部 + 细密星轨纹理） | 可用作 **L：低照自然场景**；需标 `low_light_natural_scene` + `proxy_not_natural_raw` |
| `C:/Windows/Web/Screen/img100/101/103/104.jpg` | img100 已查看：Win11 Bloom 抽象渲染（非自然场景） | **排除**（非自然场景） |

- 结论：**无真实传感器 RAW**；可用锚点是「自然场景图像派生 Bayer」（Microsoft 本地示例资产，只读一次并复制入 run）；若 P1 复核发现某图非自然场景 → 该图淘汰，退回「合成自然纹理」并保留 `proxy_not_natural` 标签，**不得**称真实 RAW。
- 图像来源是 OS 示例资产：copy 入 run、记录 SHA256 + 来源路径 + 派生参数；这是**只读外部读取**，不是外部写入或网络访问。

## 5. 工具与环境（已核实）

| 项 | 值 |
|---|---|
| Python | 3.11.5；numpy 2.4.6；PIL 12.3.0 |
| 仿真 | ModelSim ASE 10.5b `D:\intelFPGA\18.1\modelsim_ase\win32aloem`（`vsim.exe` 存在） |
| 盘符 | 仿真用 `P:`=项目根、`W:`=run 目录；`X:` 保留给 TD（本轮不用）；**不共享盘符映射** |
| 网络 | 不使用；不下载内容、不调用外部 API |
| 临时区 | `C:\Users\czz\AppData\Local\Temp\opencode\ss-g0-prod-<suffix>\**`（每任务独占库/ini/日志） |

## 6. 采用版本与未决事项

- 采用：P4（`d353c61a…`）为基线事实；P3 TB `a565c6f2…` 与 P4 TB 为仿真基线；生产 top 以 b11 `changed-src` 当前字节为准（复制后逐字节核对）。
- 未决（不阻塞本轮，已给默认策略）：
  1. 自然场景图（`C:/Windows/Web/Screen/img102/img105.jpg`）作为**派生 Bayer 的图像源**是否可接受：默认可用，必须标 `natural_scene_image`/`low_light_natural_scene` 且**不得称真实传感器 RAW**；如用户反对，后续改合成自然纹理，结论口径不变。
  2. 生产高速 sink（≥103.79 MB/s）本轮只做**离线模型**（不是 PCIe IP、不是板级、不是真实 DDR 持续）；模型结论不得升格为系统级 `feasible`。
  3. 生产 slot-free 是否需要 RTL 改动：由 P2 用「自由跑 30 fps + 2 槽不丢帧」判定；需要改动时只在新 run 做隔离候选，**不改生产源**。

## 7. 本轮不证明（写死在所有报告）

自然传感器 RAW、全内容/最坏内容、真实 DDR/PAXI sustained、真实 PCIe/UART sink、双路、板级/bit/Flash/COM/JTAG、RK 软件与 NPU、192.642 MHz 时钟、资源/时序（无 TD）。离线子包 PASS 不把父任务 T10 置 done。
