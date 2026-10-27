# 交接与恢复入口
本轮结果：T03字节/回放、T08自由运行隔离均round0独立PASS；T04工具准备独立核验通过，真实收益因缺合格实拍输入为round0 FAIL/blocked。实际修复均0，原始失败/负对照/执行偏差保留。没有整机或真实PCIe/双路实时PASS。

## 可直接交接的成果
| 内容 | 入口 |
|---|---|
| 字节责任图/当前硬件缺口 | [byte-responsibility.md](D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/T03.pcie-byte-replay/byte-responsibility.md) |
| 字节/回放独立包与安全复现说明 | [T03 handoff](D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/T03.pcie-byte-replay/handoff.md) |
| 不可反压双路源、6主题/长忙、丢帧与恢复 | [T08 handoff](D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/T08.freerun-isolation/handoff.md) |
| RAW10/u16基准工具、输入格式与恢复 | [T04 README](D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/T04.real-raw10-benchmark/README.md) |
| 三包完整结果/证明边界 | [final-summary.md](D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/final-summary.md) |
| 唯一manifest/报告完整SHA与真实角色 | [candidate-binding-final.json](D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/candidate-binding-final.json) |
| 精确数据缺项 | [questions-real-raw10.md](D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/questions-real-raw10.md) |

三个manifest分别位于各包manifest-r0.json，三份独立报告分别为test-reports/<task_id>-r0-integrated.md；前两PASS、第三FAIL/外部blocked。完整报告和复现入口绑定同候选，禁止跨候选拼PASS。

## 当前需要的数据
先给至少1帧来源可核的传感器packed RAW10或u16原文件路径；有限图集统计需至少3帧不同画面。附采集设备/来源/使用依据、W/H/stride、打包方式或u16大小端/10bit/移位、ROI和相位记录，以及已有的独立像素正确性检查/原始对照证据路径。机器SHA/输入JSON由恢复流程生成，用户无需手工填表。相位unknown只允许00，RGGB预处理收益须有相位/规范化依据。若正确性证据不足先明确缺项，不能因“看起来像图”或round-trip成功自证。
当前b18明确sensor_pixel_oracle_verified=false；不能作为新真实图集合格帧。来源不明、N/L/CONTENT=2、生成的常量/随机/ramp均不计真实收益。

## 准确恢复文本
有新真实数据/来源说明后使用：

```text
$fpga-orchestrator 恢复：D:\fpga\repos\ph1p100-pcie-ep-fpga\workflow\runs\20261027-060708_fpga-parallel-offline-delivery；仅恢复T04.real-raw10-benchmark真实RAW10收益测量。新输入：<至少1帧准确路径；有限图集至少3幅不同画面>；格式/来源/像素正确性证据：<准确路径或说明>。保留T03/T08离线PASS、T04 r0外部blocked及全部计数；不改r0冻结输入、不扩大到TD/板卡/RK。
```

原规划 /root/fpga_plan_parallel_delivery 核对真实新增条件，先写新的恢复dispatch，再续原T04开发 /root/fpga_dev_real_raw10_benchmark。原唯一测试者 /root/fpga_test_real_raw10_benchmark 在新manifest冻结后继续同任务验收；仅新增真实输入不自动重复整个工具suite，原测试者明确受影响检查/证据复用依据。新增来源审阅、真实往返、独立回退/总字节比与新manifest前后哈希必测。缺条件不进入修复轮。
新配置/新输出使用未存在的T04.real-raw10-benchmark/recovery01/或原规划另冻新路径，r0所有文件/manifest/共同规则输入保持不变。30工具/45min/6 runner/300s等预算在新派发前按原规则有限冻结，不在角色内自行扩额。真实数据接入不是把外部blocked算作实际修复；若实际实现FAIL，round1—3至多三轮，仍续原开发/原tester、不重置账。ID失效以真实工具错误登记旧/新映射，不假称resume。
T03原dev/tester分别 /root/fpga_dev_pcie_byte_replay、/root/fpga_test_pcie_byte_replay；T08原dev/tester /root/fpga_dev_freerun_isolation、/root/fpga_test_freerun_isolation。无需因T04新数据重跑前两包，除非共同绑定源码/接口确实变化并由责任角色列影响。

## 复现与冻结保护
不要原地执行会往冻结包local/work写文件的默认runner，也不要覆盖旧输出。只读采用冻结源，在自己获准的新目录创建库/日志/输出，先给源SHA绑定。T04的HERE输出限制与ROOT绑定须按工具验证报告的可审计环境重定向方式处理；只改输出环境不能改算法/输入门/统计阈值。测试证据域独立，不能改候选。
本次final dispatch仅relay_to_user，不会再派角色。旧dispatch/plan/guide/index都被manifest引用，保持字节稳定；最终控制新增dispatch-final-blocked.json，不修改原dispatch.json。全局任务板、旧P4/H-only/A+H、根生产/约束/IP、RK和设备保持原状。
本轮未产出新bit/CWC/最终DB/STA/资源/硬件吞吐，相关项not_run。最终G2/3/4与真实PCIe、曝光同步、双1080p30资格属于后续原集成线，不自动执行。回退=停止引用这三个隔离离线包，无生产替换，无需删除。禁止批量删除仍有效。

