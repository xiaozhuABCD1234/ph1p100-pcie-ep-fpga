# T10.b13-ddr-retry — lessons（r1，2026-10-25）

只记可复用的根因/触发/修正/验证入口；r0 的算法与工具坑见 `lessons-r0.md`，不重复。

## 一、流程类

1. **"改完再 bitgen"的冻结点要含最后一次修复的哈希校验**：r0 的教训是 bitgen 早于 orphan 修复。
   r1 把这条变成机器约束——`run_build_r1.ps1` 在启动 TD 前比对 `camera_a1_uart_top.v` 的 SHA256
   （`acc1eff3…7405`），不一致直接 throw。入口：`r1/td/run_build_r1.ps1`。
   同类项目建议：**build 驱动脚本里写死"必须是哪个 RTL 哈希"，而不是靠人记**。
2. **重建不要覆盖上一轮的证据目录**：新建 `r1/td`（复制 `01/02/03 .tcl`、`.al`、`.adc`、`.sdc`、`src/**`），
   `td_env.ps1 -TdDir r1/td -Force` 把 `T:` 指过去，r0 的 bit/CWC/日志原样保留。
   代价是一次 332 文件 / 3.4 MB 的 robocopy，远小于解释"哪个 bit 是哪个 RTL 生成的"的成本。
3. **构建输入要在 `.al` 里自证**：`01_build.tcl` 把 6 个改动源（含 `p2_*.v`）从 `r0/changed-src/` 直接 add_files，
   `create_project` 重新生成的 `a1_board.al` 就带同一批 `File Path`。测试者可以只看 `.al` 判断构建绑定了哪些源，
   不必追溯 Tcl 变量。**不要**把改动源留在 `td/src/` 的副本里当唯一来源（副本容易被旧文件悄悄覆盖）。
4. **WNS 在 +0.003…+0.05 之间时，行为是可复现的**：同一 RTL 的 r0 综合 +0.246/布线 +0.003，
   r1（同源，只是加了 orphan 修复）综合 +0.205/布线 **+0.023**。说明布线 WNS 在该设计上有 ±0.02 ns 级
   会话抖动，落在门槛带内不该被当异常；但也不能拿一次 +0.023 宣称稳定，需记 `thin_margin` caveat。

## 二、板级/相机

5. **`pix_beats=0` 是可判定、可归责的独立事实**：v5 `#12 pix_beats`（`cam_mail` 位 [31:0]）与
   `#13 line_rises` 恒 0、而 `#9 clk_tgl`/`#10 pkt_tgl` 大幅增长时，CSI-2 只到包层、没解出像素。
   此时 `cap_frames=0`、A1 读通路 `ar/r=0`、`timeout/retry/giveup=0`——**协议上就证明了"本包故障未被触发"**，
   不需要靠"看起来没反应"猜测。字段顺序以 `camera_a1_uart_top.v` 的 `sts_cam` 拼接为准：
   `0 clk_tgl / 1 pkt_tgl / 2 vs_tgl / 3 pix_beats / 4 line_rises / 5 frame_rises / 6 frame_falls /
   7 last_frame_cycles / 8 roi_frames / 9 groups / 10 crop_short / 11 geom_err / 12 phystat / 13 sysstat`。
6. **`frame_rises`/`frame_falls` 增长不等于有图像**：r1 里 `vs_tgl`/`frame_rises`/`frame_falls` 都涨到 22、
   `crop_short` 也涨到 22（每帧都被裁短），而 `pix_beats` 仍是 0。**只看帧计数会误判相机正常**；
   必须同时看 `pix_beats`/`line_rises`。
7. **下载耗时不是健康指标**：同一 bit 体积，r0 184 s、r1 26.6 s，`PRG-2014 Chip validation success` 与
   `B13_DL_OK` 都正常。判断下载成功只认这两个标记 + 随后的 v5 包，不看墙钟。
8. **两个不同 bitstream 复现同一 `pix_beats=0`**，把"是不是新 bit 引入的"这条疑问直接排除，
   这是"先下载再采集、每轮都留独立 v5 原始包"的直接收益。板级故障归因时，**换 bit 复现比读代码更快**。

## 三、有效入口

- 构建：`r1/td/run_build_r1.ps1`（含 RTL 哈希 fail-closed）→ `01_build.tcl`
- 候选：`r1/td/run_bitgen_cwc_r1.ps1`（02 fail-closed STA + 03 校验 compiled 与父件一致）
- 板级：`r1/board/run_board_r1.ps1`（先 SRAM 下载成功后开 COM8；解析器用冻结的 `r0/board/parse_status_v5.py`）
- 哈希清单：`r1/artifact-hashes.txt`（含 `r0/changed-src` 10 个源 + bit/CWC/BID + compiled + 抓包）
