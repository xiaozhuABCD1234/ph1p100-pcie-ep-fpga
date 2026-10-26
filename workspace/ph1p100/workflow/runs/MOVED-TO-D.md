# Run 归档/移动索引（2026-10-20）

本文件记录 `workflow/runs` 下已移出或部分移出的 run，避免以后找不到。

| run | 处理 | 新位置/状态 |
|---|---|---|
| `20261018-0001_merge_raw_into_upstream` | 已归档（只移动） | `D:\anlogic\fpga_work\archive\runs\20261018-0001_merge_raw_into_upstream` |
| `20261016_124321_trial_execution` | 部分移入待删除（长路径中断） | `D:\anlogic\fpga_work\_to_delete\runs\20261016_124321_trial_execution`；C 盘原目录仍剩约 45 MB（`trial-artifacts`），未删 |
| `20261017-011744-rk-fpga-align` | 未移动（约 1.8 GB，长路径） | 仍在 `workflow\runs\20261017-011744-rk-fpga-align`；建议后续用支持长路径的工具归档 |
| `20261019-0212_codex_fpga_closedloop_b2` | 保留（近期证据） | 原位 |
| `20261018-1631_runA_fpga_side_readchannel` | 保留（基线证据） | 原位 |
| `20261019-0207_runA_ddr_readback_loop` | 保留（Track A 证据） | 原位 |
| `20261018-1347_runA_offline_sim` | 保留 | 原位 |
| `20261019-2117_runD_batch2_continue` | 保留 | 原位 |
| `20261020-0209_singleA_aplus_closedloop` | 新 run，未触碰 | 原位 |

> 说明：移动是跨盘复制+删除源目录，属于“移动”而非清理删除；所有未确认内容都在 `D:\anlogic\fpga_work\_to_delete`，可人工复核后再删。
