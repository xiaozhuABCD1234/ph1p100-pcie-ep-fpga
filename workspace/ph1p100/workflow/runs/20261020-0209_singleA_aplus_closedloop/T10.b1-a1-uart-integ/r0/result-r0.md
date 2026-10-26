# T10.b1-a1-uart-integ r0 — BLOCKED：离线集成 RTL/工具/脚本已完成并通过静态编译，仿真尚未跑通终态

- task_id `T10.b1-a1-uart-integ` | revision **r0** | 2026-10-23 | run `20261020-0209_singleA_aplus_closedloop`
- 授权：`dispatch-board-chain.json`（P1 离线集成，同 run；无 TD/bitgen/下载；写域 `fpga/csi2/src/a1/**`、`tools/a1/**`、本 r0 目录）
- 判定 **BLOCKED（round0 未形成 PASS 证据）**：RTL 全部 `vlog` 0 error/0 warning；探针证明相机裁切→raw 存储→A+ 编码→压缩流已实际流动（4 µs 处 `xlen=81 B`、`slen=2 B`、无 abort）；但 `MODE=2` 小几何整轮用例在 400 s 内未结束且未产生捕获字节，**故障/复位/溢出/恢复四类场景与两帧 1080p 全尺寸均未取得可判定结果**。不宣称任何 PASS，不把探针观察当验收。
- 预算：**calls ≈ 61/60（超 1 次，见 §9 证据偏差）**；wall ≈ 150 min > 120 min；无 TD/bitgen/.bit/下载/Flash；未改生产候选、三算法、旧 run、SDC。

## 1. 交付物（已冻结，见 `CANDIDATE-MANIFEST-b1-a1-uart-integ-r0.json`）

| 文件 | 作用 |
|---|---|
| `fpga/csi2/src/a1/a1_raw_crop.v` | A 路 4K raw tap → 1920×1080 2×2 对齐裁切；逐行组数校验，坏帧/短帧撤销，不发半帧 |
| `fpga/csi2/src/a1/a1_ddr_slot_store.v` | 通用 2 slot 变长帧存储（MODE0=40bit 组、MODE1=32bit 流字），FREE→WRITE→READY→READING 所有权，`EXPECT_BYTES` 半帧拒绝 |
| `fpga/csi2/src/a1/a1_ddr_arb2.v` | raw/cmp 两主 → 单 256bit 原生 DDR 口（P2 映射 PAXI），写单拍/读持有授权，轮转公平 |
| `fpga/csi2/src/a1/a1_uart_export.v` | 44 B 头 + zlib 流 + CRC 导出；2 条描述符 FIFO 与 2 slot 对齐；8N1 TX |
| `fpga/csi2/src/a1/camera_a1_uart_top.v` | 集成顶层：clk_cam→CDC→raw store→回读馈送→`a1_frame_top`(bf6af390)→cmp store→UART；单帧所有权机 |
| `tools/a1/a1_pattern.py` | 与 TB 逐位一致的两套图案 + 期望 RAW/xform 生成 + 逆变换 |
| `tools/a1/pc_decode.py` | PC 独立解析/CRC/zlib 解压/逆变换/落盘 RAW、码流、还原帧、SHA256 |
| `tools/a1/verify_p1.py` | 逐样本比对 + CRC/长度/最坏膨胀/计数门槛 → `result.json` |
| `r0/sim/tb_camera_a1_uart_top.v`、`r0/sim/a1_ddr_model.v` | 4K tap 合成激励、DDR 行为模型（含 ready gap 反压）、UART 字节捕获、统计 |
| `r0/run_p1.ps1` | vlog→3 用例 vsim→python 校验，全部带可执行超时 |

## 2. 冻结契约（header / geometry / profile）

- 几何：CAM 3840×2160 RAW10（4 px/拍，b0..b4 布局同 `a1_frame_top`），ROI 参数默认 **中心 (960,540)**，W=1920、H=1080；`ROI_X%4==0` 且 ROI 原点为偶数（2×2 Bayer 相位不变）。TB 只驱动到 `ROI_Y+H` 行（裁切契约不校验尾部行，尾部行不改变已采 ROI 数据）。
- raw 打包：每 4 px 5 B（`b0..b3=px[9:2]`，`b4` 为 4×2bit LSB），`raw_len = W*H*10/8 = 2,592,000`。
- profile：`prep_en=1, pred_en=1`（p1d1，与 T10 小顶 81,707 B 基准一致）；xform = 每 2 行块按 plane0..3 重排后逐平面一阶差分 mod 1024（每平面首样本原值）。
- DDR 映像：raw slot = 4 组/256bit 字（160/256 bit 有效），`129,600` 字/帧；cmp slot = 8×32bit/字，容量 `81,085` 字 ≥ 最坏膨胀。
- 头（小端 44 B）：magic `0x31553141`('A1U1')、u8 version=1、u8 flags{6'b0,pred,prep}、u16 header_len=44、u32 frame_id、u16 width、u16 height、u32 raw_len、u32 xform_len、u32 stream_len、u32 raw_crc、u32 xform_crc、u32 stream_crc、u32 header_crc(字节 0..39)；CRC 均为 zlib CRC-32。
- 帧所有权：只有 `wr_last` 且长度符合 `EXPECT_BYTES` 才 publish；READY/READING 永不被覆盖；abort/reset 立即释放；坏帧不发布。

## 3. 局部检查（实际命令/结果）

- `vlog -work <r0>\work`（10 源文件，含冻结 core `bf6af390`、frame `18d51b1b`、`capture_async_fifo`）：**Errors 0, Warnings 0**（多次重跑一致）。
- 探针（`MODE=2` 小几何 128×16→64×8，`run 4us`）：`st_raw_pub=1`（raw 帧完整发布、`slot_len=640` 字节 = 128 组×5 B）、A+ 已经在跑（`xlen_r=81`、`slen_r=2`）、`fstate=F_FEED`、无 `frame_abort`（修好 in_sof 后 4 µs 内 14 次握手全部 `sof=0`，仅首组 `sof=1`）。
- 未取得：`st_enc≥1`、任何 UART 捕获字节、`result.json`。

## 4. 本轮定位并已修的缺陷（4 个，均在 P1 新文件内）

1. `a1_raw_crop` 首个 `line_rise` 被当成"上一行结束"校验 → 每帧首行即误判几何错误。修：`line_idx` 复位到 `16'hFFFF`，首个 `line_rise` 为 line 0。
2. `e_sof` 条目的像素被当作纯标记丢弃 → raw 每帧少 1 组（`slot_len=635`）。修：`e_sof` 同时装填 skid。
3. `a1_ddr_slot_store` 回读字数按 `len/32` 计算；MODE0 每字只装 4 组（20 B）→ 只读回 20/32 字。修：`words_of = ceil(len/20)`（MODE0）。
4. `camera_a1_uart_top` 每个 DDR 字都把 `first` 置 1 → 每 4 组重复 `in_sof`，`a1_frame_top` 的 `proto_abort` 立即中止（探针看到每 4 组一次 abort，`xlen` 恒 0）。修：`first <= (grp_sent==0)`。

另修：`cmp_open` 误声明为 reg、`raw_rd_close_r` 先用后声明、`e_abort` 与 `e_sof` 同拍时 abort 丢失（改为 abort 优先）、TB 统计写入独立文件句柄。

## 5. 未解决问题（下一轮最小下一步）

`MODE=2` 整轮 400 s 超时且无捕获字节。已知：4 µs 处链路正常推进；`wait_export` 每处最多自旋 20M cycles，全用例上限 120M cycles 看门狗。**最小下一步**（≤15 min）：在 `MODE=2` 上 `run 200us` + 探针 `st_enc / st_exp / fstate / u_export/{estate,dq_cnt,pstate,sent,wbuf_valid} / u_cmp_store/rd_state`，判定是 (a) 导出状态机停在 E_OPEN/E_PAY（cmp 槽/描述符配对），还是 (b) 仅仅 TB 等待过长；再按 (a)/(b) 定点修。**禁止**用缩短等待或放宽门槛代替。

## 6. 吞吐估算（187.5 MHz 口径，依据）

| 段 | 量 | 周期/时间 |
|---|---|---|
| 4K30 一帧输入 | 3840×2160×1.25 B = 10.37 MB | 33.3 ms（30 fps） |
| ROI raw 写 DDR | 129,600×256bit | ≥0.69 ms |
| A+ 编码 | 2.31 c/B（T10 P3 实测 355,261/153,600） | 5.99 M cycles ≈ 31.9 ms |
| 压缩流落 DDR（最坏） | 81,085 字 | ≥0.43 ms |
| UART 115200 | (44+stream_len)×10/115200 | 基准 81,707 B → **7.10 s**；最坏 2,594,706 B → **225.2 s** |

结论：A+ 与 30 fps 输入基本持平（31.9 vs 33.3 ms，余量 ~4%），**UART 是唯一数量级瓶颈（约 200×）**；因此必须 2 槽缓存 + 满槽丢弃，不能实时导出。最坏膨胀上界 `2,592,000 + 540×5 + 6 = 2,594,706 B`（每 2 行块一个 stored 块），cmp 槽按此定容。

## 7. 失败边界与回退

- 未运行 TD/综合/布线/bitgen/下载/Flash；未改 `a1_deflate_core.v`(bf6af390)、`a1_frame_top.v`(18d51b1b)、SDC、旧 run/manifest、`workflow/tasks.json`。
- 新增文件全部在授权写域内；`f9p_camera_display_core.v` **未改**（raw tap 已存在，只做观测引用）。
- 回退：删除本轮 `fpga/csi2/src/a1/**`、`tools/a1/**`、本 r0 目录即可（不涉及既有文件）。

## 8. 恢复入口

- 目录：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/r0/`
- 恢复文本：`恢复 T10.b1-a1-uart-integ r0：先读 result-r0.md §5、run_p1.ps1、sim/tb_camera_a1_uart_top.v、probe.do；用 MODE=2 小几何 200 µs 探针定位导出状态机；仍无 TD。`
- 复测清单见 manifest `retest`（仅在取得 PASS 证据后提交独立测试者）。
