# 审查收尾交接：finished，4/4独立验收

原需求request.md及原四包/batch=1范围全部完成；4包round0 PASS、实际修复0/补充0。当前dispatch只relay_to_user，不再派发。主原样转user-summary.md，详细结论由原规划写在final-summary.md；本轮没有实现生产修复。

## 唯一交付与冻结身份

最终审查候选 `T11.chain-egress-review/manifest-r0.json`，SHA256 `77c67efbcf3dd623c6d97611b8f21a1eb64784a95667be0dba2c14671ae41b92`，绑定前三包；完整入口/报告/哈希见delivery-index.json。前包与本包manifest/报告均已核对，原规划收尾核验1627次冻结条目（有跨包重叠），统一baseline不变。规划收尾文档是验收后的摘要，不追称其字节已由独立测试者验收。

|任务|manifest SHA256|独立报告SHA256|
|---|---|---|
| T02.chain-input-review | `af32567395a3083b3b5005df40cfc37857f54b133293a644782eca9d6a34b997` | `c96751cda203daf4c53a47909760f7d5b2edd3b88abdedbda0e625d67d2fb920` |
| T06.chain-storage-review | `4816a3bbe049ef65a7baf69c744f121819c9da4a83dada65682b4f30fecb56ae` | `4536629cdab2b6e9a057ee2e46a007d81039a1d74d9f191840a2a57c0156318b` |
| T10.chain-transform-review | `46f2c893722f2ac27beb83c20fd7867ac952f7cd0a7ab025b3fbfb71f0a9218f` | `7346478eb0954648b9c8db9f467caf6ed6fccfbaf68e82dfdd94622d7740b447` |
| T11.chain-egress-review | `77c67efbcf3dd623c6d97611b8f21a1eb64784a95667be0dba2c14671ae41b92` | `e96f72a6131248a1d68a4b051247c655949b50892a40821b70ed997cbeceefd4` |

真实ID：规划`/root/fpga_review_planner`；T02开发/测试=`/root/fpga_review_dev_t02`、`/root/fpga_review_tester_t02`；T06=`/root/fpga_review_dev_t06`、`/root/fpga_review_tester_t06`；T10=`/root/fpga_review_dev_t10`、`/root/fpga_review_tester_t10`；T11=`/root/fpga_review_dev_t11`、`/root/fpga_review_tester_t11`。同任务修正才续原角色，不能跨任务复用；真正ID失效才按文件恢复映射。

## 已完成、未做及回退

124检查点、15接口边、45原始记录/14展示专题和39根因或保留控制索引、13优化行。数值不等同缺陷数；跨包同根因合并且原ID保留。关键确定结论与默认配置/可达性限制见final-summary.md和各独立报告。

新G0/G1是只读审查证据；新G2–G5按事先纯文档范围不适用。没有新bit/CWC/数据库、真实图集/压缩率、STA/CDC/资源或板级吞吐结果。历史b15薄余量、未闭环、生产持续服务/曝光/RK证据缺口全保留。0 TD/RTL仿真/COM/JTAG/Flash/板卡/RK/生产改动；源码/其他活动run/全局tasks.json及父任务状态不变。无需回滚生产，旧候选/RAW兼容和历史回退原样。

额度/容量错误与用户恢复文件保留，原问题ID不改；全部实际修复与补充机会计数0。各角色初次短读deadline缺记录及辅助解析失败披露在报告，不追称过程完全无缺。当前没有blocked，finished仅指本轮审查目标。

## 精确查阅/恢复入口

只读复核：

```text
使用 fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261026-144617_fpga-chain-detail-review；本轮目标：只读核对四包已验manifest、独立报告及优化表；不重做已验工作，不实施修复，不操作硬件。
```

建议的后续单闭环（只有用户明确执行才启动，不属于本次自动续做）：

```text
使用 fpga-orchestrator 执行：依据D:\fpga\ph1p100\workflow\runs\20261026-144617_fpga-chain-detail-review已验ROOT-01，先冻结并修复唯一RAW10样本格式边界，用真实checked解包到A+输入及独立像素oracle验证；仅一个主要可验收目标，先规划隔离候选、必要G层和有限预算，保护其他活动run，不自动操作硬件。
```

其余最多3主题按原计划：b17 PAXI合同与真实读回；143924生产P1080前提；依据本审查实施正确性/接口收口后验G2及真实曝光/完整帧/恢复/稳定性。RK深度/NPU继续暂缓。不得将查阅恢复文本用于擅自扩大生产修改/硬件授权。
