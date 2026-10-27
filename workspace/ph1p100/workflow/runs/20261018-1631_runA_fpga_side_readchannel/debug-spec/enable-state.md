# enable-state.md — CTRL(0x44) 复位默认与调试版最小使能（冻结，T11.runB-debug-spec）

- 依据：`rtl/ep_side/img/ep_bar_win.v` 只读复核（2026-10-18 工作树；行号 = 该版本）；使能策略按 `fpga-design-guide.md` §3；CTRL 位义与规则 R02（`expected_rules.json`）。
- 本文件只冻结“默认值与最小 debug-only 改动草案”，不实现、不构建。

## 1. RTL 复位默认（ep_bar_win.v L264-293，冻结引用）

| 位/信号 | 复位值 | 含义 | 本轮读回影响 |
|---|---|---|---|
| ctrl_enable（bit0） | 0 | 总使能 | **默认关**；未开则采集/写存链不活 |
| ctrl_trigger（bit1） | 0 | 单帧触发（下一拍自清） | 保持 0（测试图源用） |
| ctrl_pattern_r（bit3:2） | 0 | pattern；bit2 在顶层兼“传感器重触发”（电平变→XCLR 134 ms→重写寄存器表，头部 L26-28） | 保持 0（避免重触发抖动） |
| bit4 | 0 | 保留，读 0 | R02 mask `0xFFFFFE10` 必须命中 |
| ctrl_ddr_en（bit5） | 0 | 每帧自动搬 DDR3 | **默认关**；写者 seq/base/len 不会更新 |
| ctrl_push_en（bit6） | 0 | 推帧（主机面外发） | **必须保持 0** |
| ctrl_push_src（bit7） | 0 | 推帧源 | **必须保持 0** |
| ctrl_cam_ab（bit8） | 0 | 0=A 路（相机单 A） | 保持 0 |
| cam_tap_cfg / cam_tap_b_cfg | `7'b1_101110`（manual_en=1, tap=46） | A/B 路 IDELAY | 不变（沿用既有默认） |
| tx_cap_bytes / tx_session_id | 0 | 安全扩展授权 | 保持 0（不 arm TX） |
| tx_cmd_arm/ack/cancel | 0 | 单拍命令 | 保持 0 |
| push_dst/db、tx_ack_*、cfg_reject | 0 | 主机面 staging | 保持 0 |
| ptr / scratch / last_wr | 0 | 调试指针/回环 | 不变 |

## 2. 结论与最小 debug-only 改动草案

**结论：默认未开采集/写存**（`ctrl_enable=0`、`ctrl_ddr_en=0`）。若板上维持默认，读回将看到 0x0A0=0、0x0A4=0、0x0AC=0，无法取得写者基线 → 按 guide §3 走“最小 debug-only 默认开启”。

- 允许范围：**只动采集/DDR 使能域**；**禁止** TX arm、push/doorbell、任何面向主机外发的开启（bit1/2/3/6/7/8 与 TX 域全部保持 0）。
- 草案（P1 实施前先只读复核 `img_frame_src`/顶层是否确以 `ctrl_enable`/`ctrl_ddr_en` 门控；是→实施；否→不改默认并记 candidate diff 理由）：

```
// 仅 debug 构建入口置 1；生产 00_all 保持 0（默认行为不变）
localparam DEBUG_DEFAULT_EN = 1'b1;   // 命名 P1 自定，须记 candidate diff
...
// 复位分支仅 2 行（其余位保持 §1 的 0）：
ctrl_enable <= DEBUG_DEFAULT_EN;
ctrl_ddr_en <= DEBUG_DEFAULT_EN;
```

- 等效替代（若更小改动）：顶层 wrapper 复位后单拍写 CTRL 等效值（bit0+bit5）。**等效约束**：效果在复位后立即稳定；不引入主机面动作；同样记 candidate diff。
- 生产与旧候选不受影响：改动仅存在于 debug 构建入口（guide §4：不得改动 `00_all` 默认行为，保证旧 bit `e81d353b…` 可复现）。

## 3. 板上核验（P3 用）

- 字库 word8（BAR0 0x160，见 `probe-map.md` §2）= CTRL 读回字；用于核验使能实际值。
- 判据：若已实施 debug-only 默认开启 → 期望 bit0=1、bit5=1、bit4=0、bit6=0、bit7=0、[31:9]=0（R02 mask）；若未实施（P1 复核认定无需改）→ 按实际记录并在报告注明依据，不按“应为 1”判故障。
