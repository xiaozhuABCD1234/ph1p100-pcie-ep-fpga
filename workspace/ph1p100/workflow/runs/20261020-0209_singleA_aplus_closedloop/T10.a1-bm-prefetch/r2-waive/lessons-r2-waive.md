# T10.a1-bm-prefetch r2-waive lessons（route-only 收口）

## L1. 本包目标已达成，但布线后失效锥转移到 bm_b 地址/位置计数
- 目标锥 `bm_a ERAM clk2q → hash3 → htab 地址 → CE`：**布线后已消失**（`bm_a` 只作为终点出现）。
- 数值：hit-pipe r1 SWNS −0.577 / STNS −57.504 / 311 端点 → 本轮 **−0.421 / −23.367 / 10 端点**；HWNS +0.020、HTNS 0、资源 3,016 slice / 26 ERAM。
- 新的 10 条违约全部是：`htab_p3v ERAM clk2q → bm_b.addrb`（−0.421/−0.362/−0.359）与 `pos_reg[1] → bm_a/bm_b.addrb、w0/w1.ceb`（−0.407/−0.347/−0.332/−0.329/−0.322）。
- 结论：**"去掉一个 ERAM clk2q 直出"只解决它自己那条锥**；同一个读端口地址（`hent[49:37]` 投机读、`pos±k` 地址）会成为下一条最差路径。后续结构包应把"bm 两端口地址全部由寄存器直出"作为验收对象，而不是只盯 hash3。

## L2. TD 2026.2 的报告过滤能力（重要）
- `report_timing -from [get_pins -hierarchical {...}]` / `-from [get_cells ...]` **命令成功但过滤被忽略**：输出与未过滤 `report_timing` 逐字节相同（142,283 B，同一 SHA）。
- `-max_paths` 不可用；`report_clocks`、`report_exceptions`、`reset_run`、`report_cdc` 在该版本**不存在**。
- 因此"穷举某类起点端点的 slack"在 TD 侧**不可实现**；只能引用 `report_timing` 里的 `Report Scheme: N end point(s) per path group` 覆盖范围，并把"不可穷举"写进证据。不要声称穷举通过。

## L3. harness 坑（本轮实遇）
1. `report_* -file ../<dir>/x.rpt` 在 TD 内**打不开**（`USR-8002`）——`-file` 的上级目录不要用 `..`；先写到 `T:/`，再在 PowerShell 里归档。
2. 报告名若与被 `catch` 的失败混在一起，`catch` 返回空消息 → 看起来像"命令不支持"，实际是**文件打不开**；先排除路径再判断命令能力。
3. 布线本身只要 `import_device` + 非空 `settings.cfg` 就能起（本轮 38 s 起 place、54 s 完成 phy、1m30s 全流程），无需 `reset_run`。
4. route-only 会话与只读报告会话是两次 TD 进程：即使 route 1/1、synth 0，也要在 manifest 里如实登记"2 次调用/约 2 分钟"，不要写成 1 会话。

## L4. 回退与后续
- Routed FAIL ⇒ 保留 `r2 0b084317` 为最佳回退，无 r3。
- `df6124d4` 的 G1 全绿（33 例逐位同 r2、comp 355,261、f1080p 81,707 B/b769cc66）仍是有效功能基线，可直接作为下一个结构包的功能起点（但任何 RTL 改动都要重跑 33 例）。
- 预算：约 10 次调用、约 22 min；TD 墙钟约 2 min（route 1/1、synth 0）；未用 DeepSeek、未派生代理。
