# geometry-audit.md — T11.runC-checker-integrate（N3：几何/相位离线核对与条件回填）

- 任务：`T11.runC-checker-integrate`；run：`20261019-0207_runA_ddr_readback_loop`
- 证据源（仅限，本轮无新板测）：基线 run `20261018-1631_runA_fpga_side_readchannel` 的板证两样本
  （`board-readback/readback-record.md`、`tier-evaluation-p1fix3.md`，值经本 run `input-index.md §2.4` 转引）；
  RTL 自洽：`rtl/ep_side/ddr/cam_ddr_writer.v` L106 标定式（SKIP_ROWS+2160=帧行数）、
  `rtl/ep_side/ddr/cam_r10f_writer.v` L60—71 同口径；`rtl/ep_side/ph1p_pcie_ep_top.v` 参数
  W=1920/H=1080/X0=960/Y0=540/SKIP_ROWS=37（注释“T07 实测来源，未板证”）。

## 1. 逐项一致性（分级①：一致 → 结论，不改 RTL）

| 项 | 板证/推导 | 结论 |
|---|---|---|
| DDR_LEN_A（word5） | `2,592,768` = 633×4096（4KiB 对齐）→ P = 2,592,000 = 1920×1080×1.25 | **一致**：与 W=1920、H=1080、RAW10 packed（1.25B/px）自洽 |
| stride | 1920×1.25 = 2400 | **一致**（与 P/1080=2400 自洽） |
| frame_bytes 判定 | ceil((128+P)/4096)×4096 = 2,592,768 | **一致**（checker 长度判据与该式等价，见 checker 文件头） |
| magic/CRC 域 | word20=raw_crc、word21=payload_crc、word22=header_crc（checker 口径） | **一致**（字序与 checker 重算/判定一致，TB 已逐位验证） |

## 2. 不一致/证据不足（分级③：保持原值 + diagnostic，禁止猜测回填）

| 项 | 现状 | 证据/差异 | 处置 |
|---|---|---|---|
| 帧行数 last_lines | 板证 word7 高 16 位 = 2192；标定式 SKIP_ROWS(37)+2160 = 2197 | 差 5 行，无法凭现有板证定论（embedded/哑行口径或 SKIP_ROWS 需重标定） | **保持原值**；标 diagnostic；列入上板清单追加观察项（P4），待板证后再定 |
| SKIP_ROWS / Y0 | 37 / 540（“未板证”） | 与上一行的差异耦合 | 保持原值；diagnostic |
| Bayer 相位 | `SRC_BAYER_PHASE=2'd0` 占位 | 无相位板证（MP08 缺项） | 保持原值；diagnostic |
| 起点/镜像/OB | X0=960 / 未板证 | 无板证 | 保持原值；diagnostic |

## 3. 动作分级判定

- 分级②（可推得确定新值 → 改参数 + 重跑 G1）：**不成立**——唯一分歧（last_lines 2192 vs 2197）缺推导链，
  无法区分“口径差/embedded 行/标定错”，改任一参数都可能把正确值改错。
- 因此本轮**不修改任何几何参数**，不触发因几何的 G1 重跑；本包 G1（TB 回归）为集成改动自身的验证。
- 后续入口：MP07/08 板测（另轮/上板清单观察项）。
