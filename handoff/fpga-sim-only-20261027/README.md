# 仿真与队友接手包（2026-10-27）

板卡已交给队友。本地后续只做仿真、离线分析和未验证项记录；由队友在主仓继续集成、构建和板级验证。本包没有可认证的整机 bit，没有真实 PCIe、双路同步实时或双 1080p30 通过结论，也没有把历史候选覆盖到根生产 RTL。

先看 [未验证清单及接手顺序](UNVERIFIED.md)，再按下表选取同一候选的证据。原 manifest、独立报告、日志和源码保持原字节；其中历史绝对路径及恢复授权文字只是来源记录，不能直接视作本轮执行指令。

| 证据层 | 包内入口 | 可以使用的结论 |
| --- | --- | --- |
| T03 字节/回放 r0 | [manifest](archive/offline/T03.pcie-byte-replay/manifest-r0.json)、[独立报告](archive/offline/test-reports/T03.pcie-byte-replay-r0-integrated.md)、[字节责任图](archive/offline/T03.pcie-byte-replay/byte-responsibility.md) | 离线 PASS；store 原生接口、显式环境模型及软件补头范围 |
| T08 自由运行隔离 r0 | [manifest](archive/offline/T08.freerun-isolation/manifest-r0.json)、[独立报告](archive/offline/test-reports/T08.freerun-isolation-r0-integrated.md)、[交接说明](archive/offline/T08.freerun-isolation/handoff.md) | 离线 PASS；不可反压源、丢帧/恢复及忙隔离场景；不外推到板卡 |
| T04 RAW10 工具 r0 | [manifest](archive/offline/T04.real-raw10-benchmark/manifest-r0.json)、[独立报告](archive/offline/test-reports/T04.real-raw10-benchmark-r0-integrated.md)、[结果](archive/offline/T04.real-raw10-benchmark/result-r0.md)、[输入要求](archive/offline/T04.real-raw10-benchmark/README.md) | 工具准备独立核验通过；真实收益 FAIL/外部 blocked，合格真实帧数 0、ratio=null |
| T11.BRD.P1 r0 | [manifest](archive/board/T11.BRD.P1/manifest-brd-p1-r0.json)、[开发自检](archive/board/T11.BRD.P1/result-r0.md)、[G1 日志](archive/board/T11.BRD.P1/sim/g1_scen0.log)、[filelist](archive/board/T11.BRD.P1/td/filelist.tcl) | 开发自检：帧已提交但出口未 ARM；150MHz 综合 WNS -2.273ns / 79 违例；无已确认独立验收、route 或 bit |
| H-only synthfix | [manifest](archive/honly/T10.ah-honly-synthfix/r0/manifest-r0.json)、[独立报告](archive/honly/test-reports/T10.ah-honly-synthfix-r0-integrated.md)、[交接](archive/honly/handoff.md) | 功能/性能原型通过，可综合；core d2960cfe…、frame_top 4afc26e2…，候选 provisional |
| H-only TD r1 | [manifest](archive/honly/T10.ah-honly-td/r1/manifest-r1.json)、[独立报告](archive/honly/test-reports/T10.ah-honly-td-r1-integrated.md)、[routed STA 边界](archive/honly/T10.ah-honly-td/r1/reports/routed-sta.md) | 187.5MHz **综合** WNS +0.029ns；route 导入崩溃，无 routed STA |
| A 与 P4 历史取舍 | [A 独立报告](archive/honly/test-reports/T10.ah-a-plus-h-r2-r0-integrated.md)、[P4 r2 manifest](archive/p4/INT.P4-r2-manifest.json)、[P4 r3 manifest](archive/p4/INT.P4-r3-manifest.json)、[决策表](archive/p4/decision-matrix.md) | A 本方案 kill_verified；P4 r2 功能正确/时序失败，r3 时序正但语义失败，不能采用或拼接 PASS |
| 15:00 route 请求 | [request](archive/route-request-only/request.md)、[日志](archive/route-request-only/main-log.md) | 请求/规划材料与主日志，没有可核验的 route 结果；本轮不推进 TD |

离线总索引为 [candidate-binding-final.json](archive/offline/candidate-binding-final.json)、[final-summary.md](archive/offline/final-summary.md)。T03/T04/T08 三份独立报告均保留原名及原字节。

## 先核对包，再复跑

在仓库根目录运行，最低 Python 3.9（使用 `Path.is_relative_to`），只用标准库；读取本包，不写原冻结目录：

```powershell
python -B handoff/fpga-sim-only-20261027/verify_handoff.py
```

`PACKAGE_INTEGRITY PASS` 只表示本包包含的文件 SHA/大小匹配 [source-map.json](source-map.json)。它不表示原 manifest 的所有大输出都已入包，也不表示便携仿真、TD 或板测已重新运行。`manifest_bindings` 中的 drift/missing 是历史引用相对当前源的事实，不能忽略或补造通过。

| 可复跑性 | 做法与限制 |
| --- | --- |
| 直接运行 | 上述包完整性校验可在任意具有 Python 3 的环境执行。现有 [B18 解码交接](../rk-a1u1-b18-20261026/README.md) 保留真实历史样例、严格解码器及 expected/provenance；按其说明从该包目录使用相对路径，输出放新目录。此整理没有重跑解码。 |
| 已带工具、仍需路径适配 | `archive/offline` 中的 T03 replay/runner、T04 benchmark/controls 和 T08 runner 原样保留；历史 ROOT/HERE、绝对源清单、输出限制和 ModelSim 安装路径不能在新目录盲跑。先用 source-map 找 `inputs/<候选>/...` 的匹配副本，复制到新工作目录，记录适配差异/输入 SHA，再运行；不在 archive 中生成 local/work、日志或向量。 |
| 需专有仿真器 | T03/T08、T11 G1 及 H-only TB 的 RTL 仿真需要 ModelSim/兼容环境与明确 vendor 模型。已带小型源码、TB、脚本/约束和原日志，编译库/波形未入包。没有宣称迁移后的 portable 仿真已经通过。 |
| 由队友构建与验证 | T11 filelist、约束、H-only 综合/route 脚本是构建参考，IP 生成依赖及数据库不收编；只能由队友在新输出目录核对工具/IP/时钟/约束后构建。本地此次未执行 TD、综合、route、位流、JTAG、COM 或硬件操作。 |

`inputs/board-filelist/` 保存解析原 filelist 得到的来源快照；是否属于 r0 的已冻结输入，应同时核对 `manifest_bindings`。同名源可能属于不同候选，禁止按文件名互换。P4 r2 必需的 `algo_rowwin3_p4.v`、`gray8_gaussian3x3_stream_p4.v` 取自 r2-timing-experiment，分别绑定 F3F345ED… / 158AAE4D…；生产 integrated_delivery 同名 r3 派生副本不允许替代。r2 原 manifest 对其“未编译”的历史描述与 T11 实际补依赖使用是不同阶段，不能把 T11 依赖映射反写进 r2 manifest。

## 来源与排除

[source-map.json](source-map.json) 对每个包含项给出原实际路径、包内相对路径、SHA256、用途/状态；对未包含项记录原因。`manifest_bindings` 逐条保留原候选期望 SHA、当前观察 SHA、match/drift/missing 与匹配副本位置。源 SHA 不匹配时不认作原冻结候选；活动源快照仅辅助后续排查。

具体差异见 [DRIFT.md](DRIFT.md)。根 AGENTS/PROJECT_SYNC 的漂移来自本轮用户规则与阶段说明更新，应与生产 RTL 语义漂移区分；其原字节已从提交 `9c624846` 的 Git blob 精确恢复到 `historical-policy/`，SHA 与 T03/T04 原引用匹配，来源见 source-map。P4 r2 活动源/工具/文档不匹配时，仅采用有精确 SHA 的既有冻结副本；未恢复项必须保留缺口。原文件存在但属于被排除的大输出时，清单明确未重新哈希/未包含，不能与“文件不存在”混为一谈。

没有收编 work 库、数据库、qpg/qdb/qtl、wlf、pycache、minidump、bit/CWC 或重复大向量。B18 大真实样例复用同仓既有交接包；T03 小样例标 synthetic，T04 对照标 synthetic_control，B18 标 historical_control，均不能混作合格新实拍收益。保留的小型 N/L 数据也是原型控制，不是真实传感器输入。收集脚本只为追溯，本次未重新生成任何冻结 manifest/报告。
