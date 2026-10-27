# T10.b8-crop-geom 收尾摘要（规划冻结轮）

日期：2026-10-25。状态：**ready / 未执行**。本文件是规划轮的收尾记录；开发、TD、下载完成后由原规划者按实际结果覆盖更新，**当前不声称任何 PASS**。

## 1. 本轮完成

- 用 b7 的 13 个有效 v2 包（1 Hz）冻结真实几何：**2,192 行/帧**（65,760/30）、**966.0 beat/行**（63,523,629/65,760）、**3,864 px/行**（966×4）。
- 定位 crop 根因：`CAM_W=3840 → CG=960`，第 1 行 `grp_idx=966≠960` → `geom_err+1`、`active=0`，每帧恰好 1 次，`crop_groups` 永远 0。
- 冻结 ROI：源 3864×2192，ROI (972,556)，输出 1920×1080，2×2 对齐；W/H 参数化。
- 冻结验证/工程/板级门槛与预算，写 `dev-plan.md`、`fpga-design-guide.md`、`handoff.md`、`dispatch.json`。
- 未改任何生产源、未跑 TD、未下载、未写 Flash。

## 2. 交付路径

- 计划：`...\T10.b8-crop-geom\dev-plan.md`
- 指南：`...\T10.b8-crop-geom\fpga-design-guide.md`
- 交接：`...\T10.b8-crop-geom\handoff.md`
- 派发：`...\T10.b8-crop-geom\dispatch.json`
- 输入索引：`...\T10.b8-crop-geom\input-index.md`

## 3. 验收摘要（执行时逐项填实际值）

| 层 | 门槛 | 实际 |
|---|---|---|
| G1 功能 | 全尺寸 2 帧逐字节 + 真实流水 8×8 + 965/967/短帧负例 + P1 三例 | 待执行 |
| G2 工程 | Routed 0 违例、WNS ≥ +0.05、hold ≥ 0、period 0、资源在器件内 | 待执行 |
| G3 候选 | 1 bitgen + 1 CWC，compiled 逐字节相同 | 待执行 |
| G4 系统 | 1 次 SRAM 下载 + 60 s：cap_frames/raw_pub/enc_frames/exported >0；geom/short delta=0；PC 解码/CRC | 待执行 |

## 4. 风险与 not_run

- not_run：真实板级、TD、bitgen、下载均未执行；本文件不证明图像正确、不证明 A+ 硅上正确、不证明需求二/三完成。
- 风险：115200 下整帧导出可能 >60 s；b7 采集显示相机约 13 s 后停流；有源窗口偏移假设；严格 966 等宽对丢 beat 零容忍。
- 失败即停：不二次下载、不写 Flash、不换板；保留 b7 bit/CWC 作历史候选。

## 5. 下一次准确启动文本

Codex：
`$fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop；本轮目标：执行 T10.b8-crop-geom（按 dev-plan 派 fpga-dev；1 次 SRAM 下载 + 60 s COM8；失败不二次下载）`

OpenCode：
`/fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop；本轮目标：执行 T10.b8-crop-geom（按 dev-plan 派 fpga-dev；1 次 SRAM 下载 + 60 s COM8；失败不二次下载）`
