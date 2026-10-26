# 已生成位流归档（2026-10-27）

这些是既有候选的匹配 bit/CWC/BID，本次仅同步文件，没有执行下载或新增板级验收。

| 目录 | 原候选资格 |
|---|---|
| `T10.b18-b17-b/` | B 路候选，有真实完整 1920×1080 A1U1 帧与四 CRC/解压证据；完整帧样例见根 `handoff/rk-a1u1-b18-20261026/`。不证明持续吞吐、压缩收益或双路同步。 |
| `T10.b20-a-timing/` | A 路定向时序修复，仿真与工程通过但 route WNS 仅 +0.012ns；当时 FTDI/COM8 不在，0 下载、0 采集，板级待验证。 |

每个文件的原路径、长度及 SHA-256 见 `../docs/sync-20261027-manifest.json` 的 `existing_bit_not_new_hardware_validation` 分组。原结果与全部历史限制见 `../workspace/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/` 下各自候选报告；不要混用两包 bit/CWC/BID。

当前集成候选的后续构建结果须独立绑定其 manifest；不能由这里两份旧位流继承板测通过。
