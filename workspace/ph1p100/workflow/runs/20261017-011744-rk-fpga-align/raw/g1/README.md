# raw/g1 证据索引（T11.rk-align-raw）

判定口径见 `../change-report.md` §4；每个目录内都有 `commands.log`（实际命令/退出码）、
`vlog.log`、`vsim.log`（判定行）、`abs.f`（展开后的编译清单）。

| 目录 | TB / 入口 | 状态 | 覆盖要点 |
|---|---|---|---|
| `msim/p1_writer_v4` | `tb_cam_r10f_writer` | ALL PASS | 写者 P0..P10：复位默认；4096B 冻结向量逐字节+三 CRC；换块；坏帧四类；所有权（锁块/跳过/release）；复位隔离；FIFO 溢出；**1080p 81,024 拍 / 633+1 突发 / 尾零 / 头字段+CRC / 抽拍**（v3 = 同一输入、P10 标签修正前的运行，保留） |
| `msim/p2_e2e_v6` | `tb_t11_r10f_e2e` | ALL PASS | 全链路 E0..E4（未 ARM 0 TLP；两帧 one-shot；错/正 ACK；长 wait 持稳；held 保护+新帧拒(8)；held 未 ACK 复位隔离；新 session 全流程）；独立 TL 监视器 + host 内容模型 |
| `msim/p3_enable` | `tb_t11_csi_enable_corner` | ALL PASS | T07 遗留：`I_enable` 包尾后 1 拍撤销（abort/坏帧照常、crc 少计 1 钉住；对照与恢复相位） |
| `msim/r_t07_pusher` | `tb_ddr_frame_pusher_rka1` | ALL PASS | T07 回归：安全门/ARM 负例/one-shot/ACK/CANCEL/超时/长 stall/所有权/ERAM/**PHASE10 完整 1080p 20,256 MWr+633 突发**（20387 TLPs） |
| `msim/r_t07_diff` | `tb_csi_integrity_diff` | ALL PASS | T07 重构版 vs 只读原源差分（680 拍 0 失配） |
| `msim/r_t07_checked` | `tb_csi_checked` | ALL PASS | checked wrapper + 写者裁决/所有权（T07） |
| `msim/r_t07_bar` | `tb_ep_bar_win_rka1` | ALL PASS | 寄存器面 + RKA1 扩展 + 活动期写拒绝（T07） |
| `msim/r_t07_arb` | `tb_ddr_wr_arb` | ALL PASS | A/B AXI 写口仲裁（T07） |
| `msim/neg_m1_pack_order` | e2e + 写者 TB（隔离临时树） | **FAIL（预期）** | 可重放负对照 M1：packed 低 2bit 顺序换反；`mutation.json` 记录源 SHA 与变更；两个 TB 均拒绝 |
| `msim/p1_writer`, `msim/p2_e2e`, `msim/p2_dbg*`, `msim/dbg1` | — | 历史/调试 | 原实例的早期运行与定位过程（其中 `p2_e2e`/`p2_dbg*` 为修复前 FAIL 留痕），保留不删 |

离线工具证据：

| 文件 | 内容 |
|---|---|
| `r10f_strict_selftest.json` | `r10f_strict.py selftest`：合同验收向量复算 + 全部 frame_mutations 负例 + gen 逐字节可复现（38 项 0 失败，`CONTRACT_VECTORS_OK`） |
| `r10f_tool_consistency.json` | Rust(`rka1.rs`)↔Python 字段偏移交叉核对：25/25 一致（4 个 Python 字段 Rust 不消费：exposure/gain/时间戳，如实列出） |
| `../samples/` | `gen` 产物（small/1080p，SHA 与 `contract/artifacts/` 完全相同）+ `check-*.json` |

系统/工程/RK 相关证据：`../patches/apply-check-stat.txt`（增量补丁 apply 校验）、
`../candidate-manifest.json`（冻结清单+自检）、`../g2/`（TD 同源 DB/报告/bit）、
`../hardware-ready.md`（板测入口）。
