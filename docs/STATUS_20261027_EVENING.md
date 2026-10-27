# 2026-10-27 晚班状态：T11 r1/r2 与 export r0–r0g

本页只记录 2026-10-27 晚间冻结的仿真/静态证据，**不改变**旧 run、旧 manifest、旧报告和板级结论。当前本机边界仍是：只做仿真、软件/字节检查、接口核对和证据整理；TD 构建、STA、bitgen、下载、Flash、RK/FPGA 实机联调由持板队友执行。

## 1. 一句话结论

- **T11.BRD.P1 r2**：64×48 缩尺 G1 开发自检 PASS，r1 的 `TB_CAM_STIMULUS_WIDTH` FAIL 已修；但 r2 包里的板级 ACK 跨域切片仍是旧版，且完整帧路径还有字节序/地址单位冲突。**r2 不是最终构建候选，不要按它出最终 bit。**
- **T11.export-arm-sim r0g**：最新状态 **blocked**。T03 70 B oracle 已逐字节复现（store 侧 LSB-first 正确）；但 pusher 的 32 B beat 解包为 MSB-first，导出载荷逆序；同时存在 `×32` / `×128` 地址单位冲突。修复点落在本轮禁止位置（b20 store / 参考 pusher），需用户或规划裁定。
- **下一步**：先裁定 A1U1 在 256-bit DDR beat 内的字节序和地址单位，再做 r3 最小合并、重跑 r2 G1 + export TB、重新冻结。裁定前不要把 r2 当作可上板候选。

## 2. 证据入口

| 内容 | 路径 |
|---|---|
| r2 开发结果 | `workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/result-r2.md` |
| r2 冻结清单 | `.../r2/manifest-brd-p1-r2.json` |
| r2 队友包 | `handoff/brd-p1-r2-20261027/README.md` |
| r1 队友包（r2 filelist 解析依赖） | `handoff/brd-p1-r1-20261027/` |
| export 最新阻塞 | `workflow/runs/20261027-1604_fpga-sim-baseline-export/T11.export-arm-sim/result-r0g.md` |
| export 冻结清单 | `.../T11.export-arm-sim/manifest-r0g.json` |
| T03 oracle 复现 | `.../T11.export-arm-sim/t03oracle/03.log`、`rtl-slot-read.bin` |
| 字节序反证 | `.../T11.export-arm-sim/sim/logs/r2-seg_*.log` |

## 3. 已知事实与边界

1. **r2 的 G1 只到 64×48 缩尺链路**：3 个旁路正例解压 RAW 与独立模型逐字节相同，150 项检查 0 失败；PREP=1/PRED=1 用 zlib/长度/Adler/CRC 判据。它不是 1080p、真实 DDR/PCIe、双路或长稳证据。
2. **r2 的 G1 没有覆盖板级 ACK 跨域真实路径**：export r0d 的 ACK 切片修复（`brd_cdc_mailboxes.v` 的 `out_bus[63:32]` / `out_bus[31:0]` 对调）仍在独立工作副本，未并入 r2 包。
3. **r0d 的两帧全帧导出 PASS 已被 r0g 降级**：r0g 证明 T03 store 侧正确，但 pusher 的 beat 解包顺序与 store 相反，完整载荷未逐字节通过；F4/F6 仍 fail，SCEN=3/neg_both/E4 为 not_run。
4. **r0g 的阻塞不是“再跑一次就能过”**：它需要先定 A1U1 的 beat 字节序和地址单位。不能在 TB 模型里加字节交换来掩盖接缝。
5. **没有 TD 综合/布线/STA/bitgen/CWC/下载/Flash**：本页所有内容都是仿真/静态证据；G2/G3/G4 为 `not_run`。

## 4. 裁定后本地 r3 的最小工作

1. 按裁定结果，在 r2 基础上做**最小 diff**：只取 export r0d/r0g 已定位的修复；保留 r1 的 C8/C9 2FF 和既有 CDC 结构；不要整文件覆盖 export 工作副本。
2. 同时跑两套回归：r2 的 6 场景 G1 + export 的两帧/反压/ACK TB；任何一套失败都不能冻结 r3。
3. 重新生成 manifest、result、handoff；在 README 明确“r3 只解决哪些问题、哪些仍未验证”。
4. 队友构建 r3 前，先跑 `handoff/brd-p1-r3-.../build/check_filelist.py`，再 `gen_al.py`，再 `01_synth → 02_route → 03_bitgen`。r2 包只保留为审计/回退输入，不作为最终构建对象。

## 5. 对队友的口径

- 可以先用 `artifacts/T10.b18-b17-b/a1_board.bit` 和 `handoff/rk-a1u1-b18-20261026/` 验证 RK/驱动/解码栈；这是已知好锚点。
- 不要用 r2 出最终 bit；不要在现场改 RTL；不要用 r0d 的局部 PASS 覆盖 r0g 的 blocked。
- 等 r3 包和裁定结论到位后，再按 S0–S7 联调主线推进。
