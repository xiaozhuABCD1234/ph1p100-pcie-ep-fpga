# 最终仿真候选指南

本文件记录既有冻结合同的最终采用版本，不追加或追改已验门槛。原fpga-design-guide.md及input-index.md保持原SHA；各规划增补和最终manifest给出真实选择，candidate-binding-final.json是交付路径入口。

## 两条候选线

同步候选来自production RAW顶层ph1p_pcie_ep_top的隔离overlay，保留真实ui_i2c、checked CSI、双cam_r10f_writer与arb。14笔同步角色写、两次等待、warmup8、第9pair后ready/下一个SOF完整放行、cleanup先standby/stop再Hi-Z及reset pending隔离已验；引脚独立解码，不拿cfg_done当每笔ACK。生产默认RAW10 ROI1920×1080、packed2592000B、R10F128B头、DMA2592768B；小仿真8×2仅20B payload，DMA4096B。A/B地址以原生产字节地址合同独立，不与A+ word地址混用。

A+恢复候选是最终8RTL：core r5 `29b1e3e1...9828`、frame/crop/store/arb/FIFO原SHA，已修exporter `0f3ae49e...3ba097` 和top `5d0f9a00...10772a`。只改两项副本：descriptor 1bit索引/2bit计数集中push-pop事件，旧count满时仍拒本次新描述符；top cam holding/pending/drop、FIFO w_ready及有序abort、RAW/skid/admission优先级和直接事件统计。FIFO/crop/store/core/帧格式未改。

## 数据、握手、时钟和恢复

A1U1 44B小端头，header/stream/transform/raw四CRC；payload为精确长度zlib，不允许截断、非空unused/unconsumed或尾垃圾。4×10bit camera group=40bit；RAW store每256bit DDR字有效20B，W32/H2 RAW80B用4字；RAW_BASE0/CMP_BASE131072为256bit word地址，不能当字节。内存、read held响应只按真实握手改变。

满FIFO与源CSI不可反压按整帧拒绝，abort为独立token、无像素SOF/LAST，源stall保持、旧像素先于abort、新完整SOF后于abort；pending/abort接受同拍SOF拒到下一个fresh SOF。RAW写会话last尚在skid/未store take时abort必须撤销有效提交并真实释放槽；READY/READING不覆盖。事件按丢弃区间合并，不把cam_loss统计冒称逐帧精确数。

最终矩阵：两异步比例cam14ns/A1 5.333ns和cam3.7ns/A1 5.333ns，相位1.7/0.91ns；UART与A1同网、UART_DIV4，PREP/PRED1、HB_DIV0。clean32/中写reset W32/H2 FIFO_AW4，其余W8/H2 FIFO_AW2。中写以前置外部RAW/CMP AW/W已接受且未完整发布命中；四good最多、至少两正确恢复、最后FE后≤1000000 A1周期，实际四恢复/最大10042。原top与checker负例、直接源tap/正向变换及槽所有权独立判据拒绝错误通过。

## 工程、工作目录和证明边界

开发/测试均独占本run路径与工作库，ModelSim10.5b、Python3.11.5/zlib1.2.13；真实命令/工具SHA/参数/源映射在各manifest和独立报告。每task唯一manifest，旧r0/resume01仅历史，不与resume02拼PASS。复现不得覆盖冻结证据；原角色在新隔离证据目录重建。

三维检查按冻结离线范围均pass、G0/G1通过。G2 not_run，G3/4/5 N/A；没有真实STA/实现CDC/资源/bit绑定或板级资格。本次不改生产/约束/IP/共享盘符/板候选，TD/构建/下载/Flash为0。旧AR在reset时未完成的交错hits0，额外旧响应边界not_covered；模型保留响应不等于该前置已命中。曝光同步、电气、1080p吞吐/容量、真实压缩收益与长稳均留未来，父硬件任务不置done。
