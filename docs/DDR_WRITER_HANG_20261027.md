# 收帧写者卡死定位（2026-10-27 板测，第二轮）

## 本轮结论速览

1. 板子现在稳定配置：**A 路 15.6 fps 持续出帧、B 路空闲但状态干净**（不再空转抢带宽）。
2. 落地了两条 RTL 改动：**帧级轮转**（一次只 arm 一路写者）+ **连续坏帧自愈**。
3. 已证伪两条假设：把 FS 包头的 `header_ok` 从 vsync 判据里去掉会**把两路都打死**；
   把 `in_frame` 上升沿当 SOF 用同样会打死 A 路（同帧多 SOF）。
4. B 路"出不了帧"的根因仍未定死：写者停 `S_SYNC`（等 SOF），而它所在相机域明明在数
   到 2192 行/966 组，CSI 诊断 good 在涨、crc/hdr 错为 0。

## 板测事实（保留证据）

| 观察 | 数值 |
| --- | --- |
| 两路同时 armed（改动前） | 一路 15.6 fps，另一路 0；卡死那路 `wcnt=1023`（=FIFO 满）、`beats=81024`（整帧补零）、`verdict=0x07`、`busy=100%` |
| 卡死那路的 AXI 状态 | 采样 200 次：`A_AW` 92 / `A_W` 108 / `A_B` 0 —— 永远不完成一次突发 |
| 仲裁采样 | grant A:80 / B:70（在轮转），busy_a 74/150、busy_b 134/150 |
| 重新 arm（`CTRL[5]` 关一次再开） | 卡死那路立刻整帧写满（`wcnt=518400`、`verdict=0x20`、15.7 fps），但**另一路随后卡死** |
| 帧级轮转后 | A 路 15.6 fps 稳定 60 s+，B 路 `verdict=0x00`、不再抢带宽 |
| A 路帧校验 | `r10f_strict.py check` → **R10F_STRICT_OK**，sha256 `ae7b295295b021f15e5b2f9a2d0c427a2c6c27c15cfe292649a6dd538daa5edd` |

## 改动 1：帧级轮转（`ph1p_pcie_ep_top.v`）

```
w_cam_ddr_want_a = img_ddr_en & ~cam_tx_owner
w_cam_ddr_want_b = img_ddr_en &  cam_tx_owner
```

`cam_tx_owner` 在「当前持有方刚发布一帧」时翻转；另有 `CAM_TX_WATCHDOG`（≈0.48 s）
兜底换手，保证任何一路卡死都不会把另一路饿死。没被 arm 的那一路走设计里已有的
skip 路径（跳过不写），不会卡。

## 改动 2：连续坏帧自愈（`cam_r10f_writer.v`）

同一片写者连续 8 帧判定坏 → 拉 255 拍 `self_flush`：
ddr 域清读指针、流状态机回 `S_SYNC`；cam 域（2 级同步后）清写指针并让
`frame_armed` 掉下来，等下一条 SOF 重新对齐。被扔掉的那一帧本来就是坏帧，
不会发布给主机。

## 已证伪

- **FS 包头校验门（`csi_rx_packet_integrity.v:100` 去掉 `header_ok`）**：两路都变成
  0 帧（`verdict` 在 0x5/0x7 之间跳）——没有 `header_ok` 时 `dt` 不可信，会冒出假 vsync。
  已把该行恢复原判据，并在注释里记下这次板测结果。
- **`in_frame` 上升沿当 SOF**：A 路也从 15.6 fps 掉到 0，说明同一帧会出多个 SOF。

## 下一步（给下一轮）

1. B 路写者停在 `S_SYNC` 等 SOF，但相机域有行/组计数 → 直接抓 `w_b_vsync` 与
   `push_sof` / `arm_c[1]`（用 `ph1p_pcie_ep_top_dbg` + ChipWatcher，探针字库已在
   0x140..0x160）。三种可能：`w_b_vsync` 不出脉冲 / `arm_c[1]` 恒 0 / `f_wr` 被
   `wfull` 卡住。第三种可以用「在 `f_wr` 被卡 ≥1 帧周期时强制清双侧指针」验证。
2. 若确认是 `wfull` 卡住：说明还有第三条指针失配路径（本轮只对齐了
   `rst_cam_all` 与 `rst_ddr`），需要在 `wptr` 侧加同样的自愈。
3. 两路并发卡死（`ddr_wr_arb` 与写者 `A_AW/A_W` 的交互）仍未定论，子智能体的静态
   分析结论见本轮报告。
