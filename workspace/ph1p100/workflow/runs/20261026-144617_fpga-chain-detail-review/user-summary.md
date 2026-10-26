整链路细节审查已完成：**4个工作包均独立round0 PASS，覆盖124个细分检查点、15条接口边，形成13条优化建议。**

主要发现：

- **路径尚未真正串成一条生产链**：A+走UART，三算法与RAW PCIe属于其他分支，不能拼成“压缩PCIe已通”。
- **入口格式不一致**：4×10bit样本向量直接进入packed RAW10接口，缺少重打包。
- **完整帧裁决有漏洞**：晚CRC/FE未接入A+，末ROI行检查提前结束；取消与最后字同拍仍可能提交。
- **PAXI适配及模型有问题**：地址步长、写mask与同份原生参考不一致，旧模型没有覆盖这些错误。
- **队列/导出有接口反例**：abort可扰乱槽发布顺序；描述符ID/长度错配后仍继续发头。模块反例已核验，默认板上是否发生仍未证明。

建议按“**格式与好帧事务 → PAXI及发布/排序 → 边界、取消与恢复 → 生产持续服务**”收口。维护性上先整理重复来源、构建白名单和过时注释；CRC/Adler、FIFO/skid及行缓存尚无依据直接删。CMP容量前提、tag回绕和真实曝光同步仍需后续证据。

[全链路总报告](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/final-summary.md) · [优化顺序与最小验证](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/T11.chain-egress-review/optimization.csv) · [接口边覆盖表](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/T11.chain-egress-review/coverage.csv)

细分检查表：[输入/同步](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/T02.chain-input-review/checkpoints.csv) · [DDR/队列](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/T06.chain-storage-review/checkpoints.csv) · [算法/压缩](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/T10.chain-transform-review/checkpoints.csv) · [发布/PCIe](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/T11.chain-egress-review/checkpoints.csv)

**本次通过的是审查验收。尚未修改生产RTL、重新构建或上板，不能据此宣称这些设计问题已修复。**
