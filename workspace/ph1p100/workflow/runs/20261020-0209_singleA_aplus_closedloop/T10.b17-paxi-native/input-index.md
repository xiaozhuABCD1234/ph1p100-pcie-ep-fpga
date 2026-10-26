# T10.b17-paxi-native — input-index（规划冻结，2026-10-26）

## 1. 需求与原话

- 用户本轮要求：冻结 `T10.b17-paxi-native`，按 b15 根因审计做原生 PAXI 边界适配、模型真合同、v6 诊断、重建与板级验证。
- 原话要点（保留语义，不替代用户原文）：
  1. 在**唯一 PAXI 边界**做地址转换：`{word_index[23:0],3'b000}`（AW/AR 都做）；内部槽仍保持 256-bit 字单位；范围检查。
  2. `paxi_wstrb` 按原生合同改 **0**（写整字）；模型必须实际执行 mask 语义。
  3. 单命令接纳：AW/W 与 AR 互斥（受控诊断默认）；保留参数以便后续并发对照。
  4. 更新仿真模型：检查低 3 位/越界/mask/并发；先做 8–16 个不同字写-停-读回逐字比对，再做整帧/两帧/丢 R；P1 三黄金。
  5. v6 诊断：新增 `last_issued_ar_addr`、超时锁存 AR 地址+低3位、AW/W/AR 同拍握手标记、在途状态；状态包按需扩字段（记录长度/版本）。
  6. 重建：Routed 0 违例、WNS≥+0.05（薄余量按 b13 口径）；1 bitgen + 1 CWC。
  7. 板级：先下载后开 COM8、150 s；目标 timeout/retry/giveup 归零、enc/exported 增量>0、帧四 CRC+zlib；若仍缺 R，保留 v6 失败 AR 证据并停止。
  8. 预算：开发 150 min/70 calls；TD 3 会话、综合 ≤3、布线 ≤2、bitgen 1、CWC 1、下载 1。
  9. 更新 dev-plan/handoff/user-summary/final-summary，写 dispatch。

## 2. 根因审计（本包依据）

| 文件 | SHA256 | 用途 |
|---|---|---|
| `D:/fpga/ph1p100/docs/OpenCode_b15根因审计与定位建议_2026-10-26.md` | `CF18AACC8B17DB3C91A80B55683ACC0F0D704A25E44B6A3DEB367FE52237A2BC` | 地址单位、mask、单命令、模型缺口、五组小实验 |

关键结论：

- store/bridge 发 0,1,2（256-bit 字下标）；厂商原生参考发 0,8,16（`{word_index,3'b000}`）；链路无 ×8。
- bridge `paxi_wstrb=32'hFFFF_FFFF`；厂商 `paxi_stg_cmd_gen`/mtest/`ddr_frame_store` 完整写 mask=0（mask 0 写整字）。
- 读写命令可同拍握手；原生参考单命令仲裁（`awready & arready` 共同判定）。
- 现有 b15 模型忽略 mask、按字下标直接索引；模型 PASS 不能排除真实接口错误。
- 建议顺序：先冻结原生合同并修模型 → 唯一 PAXI 边界地址转换 → 单命令对照 → 小图样读回 → 再整帧/压缩 → 若仍缺 R 锁存失败 AR 证据。

## 3. b15 基线（只读）

| 路径 | 说明/关键哈希 |
|---|---|
| `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b15-ddr-pace/result-r0.md` | b15 结果：sim/build 过，板级 H4_UNRESOLVED；SHA256 `6A07DFDE14E5FE670D7C81676A9DC3426F482FF1547B87CAE95AAA524BFBFBB4` |
| `.../T10.b15-ddr-pace/handoff.md` | b15 交接；SHA256 `D177DE6041E3F7BE128464217D7A53B6F5D7723534C26683800350772C4BE32C` |
| `.../T10.b15-ddr-pace/r0/changed-src/**` | 11 文件源集；bridge `EB9DF41F9404E40CD31DBF12BC65F29ED965A9FC6C2E604F027AA9AD158954E3` |
| `.../T10.b15-ddr-pace/r0/td/**` | 构建模板（01/02/03 Tcl、ADC、SDC、bit/CWC、STA、Routed 报告） |
| `.../T10.b15-ddr-pace/r0/sim/**` | 仿真模板（`tb_b15_chain.sv`、`p2_paxi_model_b15.v`、`run_b15.py`、caps、cases） |
| `.../T10.b15-ddr-pace/r0/sim/caps/micro8x2.dec` | P1 golden，SHA256 `FA513A2B5A7F268BE9F29D62AEA6C44AAAB796D0F23256B0E1049F50ACCEEDEF` |
| `.../T10.b15-ddr-pace/r0/sim/caps/mid64x8.dec` | P1 golden，SHA256 `EE61E6200D9ABCA66C5A74A0CBBD9DDE982F1D4652647F8B0D67E5964F3E9789` |
| `.../T10.b15-ddr-pace/r0/sim/caps/full_grad.dec` | P1 golden，SHA256 `B992A8AD74063545CFEBB67E59EFC83B4136133A0C19479A18C05C343D48ADA9` |
| `.../T10.b15-ddr-pace/r0/board/**` | 板级模板（parser/capture/gate/download） |
| `.../T10.b15-ddr-pace/r0/board/captures/status_v5.txt` | b15 151 包；`timeout/retry/giveup` +13,500/+9,000/+4,500；`enc/exported=0`；`ar-r=13,740` |

## 4. 源文件（11 文件，b15 r0 逐字节）

| 文件 | SHA256 | 本包角色 |
|---|---|---|
| `p2_ddr_bridge.v` | `EB9DF41F…954E3` | 功能修改（地址/mask/仲裁/v6） |
| `camera_a1_uart_top.v` | `ACC1EFF3…7405` | 诊断修改（dbg 512、sts_ext 768） |
| `p2_a1_board_top.v` | `48881D57…561B` | 诊断修改（dbg_bridge 512） |
| `a1_uart_export.v` | `F8F9E4E3…6B61` | 诊断修改（v6 273 B/67） |
| `f9p_camera_display_core.v` | `C9DE0D9C…5089` | 逐字节不变 |
| `a1_ddr_slot_store.v` | `6C619CF9…EFE9` | 逐字节不变 |
| `a1_ddr_arb2.v` | `B84019BD…D6BA` | 逐字节不变 |
| `a1_frame_top.v` | `0064607A…7109` | 逐字节不变 |
| `a1_deflate_core.v` | `A91C2ED8…1B3E` | 逐字节不变 |
| `a1_raw_crop.v` | `33A6FEE7…D72D` | 逐字节不变 |
| `cam_diag_mailbox.v` | `352AF7C8…7278` | 逐字节不变（实例 W 256→512） |

完整哈希见 `fpga-design-guide.md` §7。

## 5. 工程/工具/参考

| 项 | 路径/值 |
|---|---|
| 项目根 | `D:/fpga/ph1p100` |
| 构建模板 | `T10.b15-ddr-pace/r0/td/**` |
| 仿真工具 | ModelSim ASE 10.5b `D:\intelFPGA\18.1\modelsim_ase\win32aloem` |
| TD | `D:\anlogic\TD_Release_2026.2`；先 `tools/td/open_td.ps1` / `td_env.ps1` |
| 板级 | FTDI `VID_0403&PID_6042`，COM8，115200 8N1 |
| 路径合同 | `P:`/`Y:`=项目根，`W:`=r0/sim，`T:`=r0/td；`X:` 不映射项目根 |
| 厂商参考 | b15 `r0/td/src/vendor/rtl/mtest/paxi_stg_cmd_gen.v`、`ph1p_ddrmc_mtest.v`；`fpga/csi2/src/mem/ddr_frame_store.v` |
| 既有原生 store | `D:/fpga/ph1p100/fpga/csi2/src/mem/ddr_frame_store.v`（地址步长/ mask 0 注释） |
| 审计小实验 | `D:/fpga/ph1p100/work/b15-contract-audit-20261026-022046/**`（只读参考，不修改） |

## 6. 已冻结/未决

- 已冻结：三项合同、v6 273 B/67 字段、仿真矩阵、构建/板级门槛、预算。
- 未决（实现细节，不阻塞）：v6 诊断在 512-bit mailbox 下的具体寄存器化方式；若 WNS 落入 thin margin，是否需 1 次等价流水修正（不改字段）。
- 外部条件：FTDI/板卡是否在位。**不在位 = board blocked**，不是 FAIL，不需要用户回答。
- `workflow/tasks.json` 本冻结未改；父 T10 仍 blocked/not done；离线/构建完成也不把 T10 置 done。
