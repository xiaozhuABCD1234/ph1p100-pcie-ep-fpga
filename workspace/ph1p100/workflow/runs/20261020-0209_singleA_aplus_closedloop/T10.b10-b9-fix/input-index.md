# T10.b10-b9-fix 输入索引

## 需求与审核
| 类型 | 路径 | 采用方式 |
|---|---|---|
| 用户本轮指令（规划冻结） | 本会话派发原话 | B9-01/02/03 修复 + R1/R2/R3 最小 TB + 离线验收 + 1 bitgen/1 CWC + 先下载后监听；不改协议/帧头/CRC/端口/SDC/引脚 |
| 审核清单 | `docs/OpenCode_b9审核建议与验证清单_2026-10-25.md` | 采纳 B9-01/02/03 结论与修法方向；R1/R2/R3 按“待验证”写最小用例；否决帧内插包 |

## 冻结候选（只读）
| 项 | 路径/值 |
|---|---|
| b9 候选根 | `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b9-rawstore/r0` |
| b9 exporter SHA256 | `dae0d47fc791fcc8993ccc7efc97c10dfef139cc684404e7a073689372561312` |
| b9 bit SHA256 / CWC / BID | `950b6e4a867cf1aa87d11c4f084607f4254a82d335f5ed10891dcf74b66a5a06` / `b9515f79…1cdd7` / `67c289a8…70a8b` |
| b9 工程结论 | Routed `SWNS +0.102 / HWNS +0.020 / 0-24754`，1 bitgen + 1 CWC；G1 全绿，G3 静默 blocked |
| 独立修复 exporter（参考，不可整文件覆盖） | `workflow/runs/20261024-221529_fpga-sim-integration-recovery/T10.a1-uart-descriptor-fix/candidate/a1_uart_export.v`（SHA `0f3ae49e…`）——只移植队列修复并适配 B9-01 仲裁 |

## 复现与证据（只读，复制进 r0/sim/repro）
| 项 | 路径 |
|---|---|
| 分析记录 | `work/b9-opencode-audit-20261025/analysis.md` |
| 机读结果 | `work/b9-opencode-audit-20261025/results.json` |
| 最小复现 TB | `work/b9-opencode-audit-20261025/tb_b9_arb_repro.sv` |
| 复现运行脚本 | `work/b9-opencode-audit-20261025/run_repro.py` |
| 状态开启/关闭日志 | `work/b9-opencode-audit-20261025/sim_sts_64.log` / `sim_sts_0.log` |

## 设计/基线源码（只读）
- `T10.b9-rawstore/r0/changed-src/{a1_uart_export,camera_a1_uart_top,a1_ddr_slot_store,a1_raw_crop,cam_diag_mailbox,a1_deflate_core}.v`
- `T10.b9-rawstore/r0/td/src/{p2_a1_board_top,p2_ddr_bridge}.v`、`td/src/camera/uisrc/01_rtl/dbg_uart.v`
- `T10.b9-rawstore/r0/sim/{tb_raw_store.v,tb_status_v3.v,tb_p1_chain.v,run_sims_b9.py,a1_ddr_model.v,p2_paxi_model.v,old_bridge/}`
- `T10.b9-rawstore/r0/board/{capture_com8.py,parse_status_v3.py,decode_frame.py}`
- `T10.b9-rawstore/{fpga-design-guide.md,handoff.md,result-r0.md,lessons-r0.md}`
- 工程约束：`tools/td/open_td.ps1`、`tools/td/PATH_CONTRACT.md`

## 已确认缺陷（本轮修）
- B9-01 状态 `sts_want` 与非空 `dq_cnt` 互锁（b9 `a1_uart_export.v` L299/L302-303/L335；已离线复现）。
- B9-02 `dq[0:1]` + 2-bit 指针越界；同拍 push/pop 对 `dq_cnt` 双赋值（L138/139/279/280/344/345）。
- B9-03 1080p 四槽重叠：RAW1 129,600–259,199 vs CMP0 131,072–212,156 / CMP1 212,157–293,241（`camera_a1_uart_top.v` L43、L112、L483）。

## 未决/边界
- 板级真实根因仍未确认（b9 下载后静默，无 v3 包）；本轮只验证“修复后是否恢复输出”，不以离线缺陷替代实测。
- DDR 真实容量未在规划阶段读取，须开发从 TD DDR IP 配置核对并写进 `result-r0.md`；`< 424,314 word` 即 blocked。
- 下载总剩余次数以实际记录为准（用户已授权连续烧录，本轮记 `download_used/2`）。
