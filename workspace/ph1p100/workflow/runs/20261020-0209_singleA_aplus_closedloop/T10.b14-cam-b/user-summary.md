# T10.b14-cam-b — 用户摘要（派发前，2026-10-25）

## 一句话

A 路“有 MIPI 包但没像素”已经反复出现；这一包不改 A，**把输出切到 B 相机**，用同一套压缩/导出链看 B 能不能出图。你只需要回答一个问题：**第二颗相机模块是否真的插在 B 口上？**

## 为什么要试 B

- b13 板级 150 s：状态包 150 个全对，但 `pix_beats=0`、`line_rises=0`、`cap_frames=0`、`enc=0`、`exported=0`。
- 同一次采集里 MIPI 字节时钟和 CSI 包计数在涨，VSYNC 也有 2 次 → A 的前端不是完全没信号，而是“有包、无有效像素”。
- B 口在硬件上不是没做：B 的 I2C（H13/G13/G20/H20）、MIPI-B（J19/H19…L19/L20）都已分配引脚；相机核里 B 的 I2C 初始化、MIPI 复位释放、B 的 pixel/line/frame/vsync 都已经存在并且是使能的。
- 之前 B 只是**没接进 A+ 链**：核只把 A 的 tap 引出来。所以本包是“接线 + 选择”，不是“重新使能 B”。

## 这一包做什么

1. 相机核只加 B 的 tap 和 B 的诊断输出（纯 assign，A 不动）。
2. 板级顶加一个**编译期常量** `CAM_SEL=1`：把 crop 的输入时钟和 pixel/line/frame/vsync 切到 B；`CAM_SEL=0` 就回到现在的 A 路径。
3. 板级 SDC 补一条 B 字节时钟的约束（新时钟域必须被时序分析；不是放宽约束）。
4. 状态包**仍是 v5（241 B / 59 字段）**：`pix_beats/line_rises/frame_rises` 等字段现在记录“被选中的相机”，B 时就是 B 的计数；用 `cam_sysstat` 的 bit20 标记当前是 A 还是 B。
5. 仿真：用 B 的真实几何 3864×2192、ROI 972/556、1920×1080 跑通 crop→raw→A+→export；P1 三黄金逐字节不变；再测 B 时钟停振/短行等失败态。
6. 重建：Routed 0 违例；WNS 目标 ≥+0.05，薄余量按 b13 口径可接受并记 caveat；1 bitgen + 1 CWC。
7. 板级：**先确认 B 已连接**，再 1 次 SRAM 下载，然后开 COM8 150 s。

## 怎么算成功

- **B 前端**：`clk_tgl / pkt_tgl / pix_beats / line_rises / frame_rises / cap_frames` 都有增量 >0。
- **A+ 链**：`enc_frames / exported` 增量 >0，至少 1 帧 44 B 头 + 四 CRC + zlib 全过，无半帧。
- **A 不回归**：P1 三黄金逐字节一致；`CAM_SEL=0` 与 b13 的 A 连接逐线一致。
- **若 B 也无像素**：这一包仍算“完成诊断”——停止、保留 B 的 clk/pkt/lane/tap/cfg/nack/帧计数证据，写清 A/B 硬件条件，**不做第二次下载**。

## 需要你确认（唯一）

> 第二颗 IMX415 是否已物理插在 **B 口**（MIPI-B：J19/H19、J22/H22、G17/G18、J20/J21、L19/L20；B I2C/控制：H13/G13/G20/H20）？
> 请回答：**已连接 / 未连接 / 不确定**。

- 回答“已连接” → 开发做完离线/构建后可以上板。
- 回答“未连接/不确定” → 开发仍可完成离线改动、仿真和构建，但**板级 blocked、0 下载、0 COM8**；等确认后再申请板窗。

## 代价与风险

- 开发 120 min / 60 calls；TD 3 会话、综合≤3、布线≤2、bitgen 1、CWC 1、下载 1；不写 Flash。
- B 与 A 共用 IDELAY tap 46，B 眼图没单独扫过；若 B 有包无像素，下一步才是 tap 扫描（不在本包）。
- 板级注释记载 MIPI 走 FEP1B C 排、子卡 A 排侧有 100R 串联，A/B 都可能受衰减影响；这是硬件条件，本包只记录不修。
- 只选一路进 A+，A/B 核可共存；本包不做双路 A+、不做运行时切换。

## 入口

`T10.b14-cam-b/{dev-plan.md, fpga-design-guide.md, dispatch.json, handoff.md}`；基线 `T10.b13-ddr-retry/r1/**`；证据 `T10.b13-ddr-retry/r1/board/captures/status_v5.txt`。
