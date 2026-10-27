# FPGA 并行仿真结果（2026-10-24）

本轮仅推进 FPGA 侧离线验证。所有测试在本目录独立快照和 ModelSim 库执行；未改生产 RTL、活动 TD 工程、时序约束、共享盘符或任务板，没有下载/Flash/板卡操作。

## 核心结论

**最新 r5 压缩功能正确，但 P2 comp 吞吐未达到 77.76 MB/s。应优先消除匹配流水新增的周期开销，再用本轮固定向量验证。**

| 测试 | 实际结果 | 结论范围 |
|---|---|---|
| r5 单核 comp，153600 B | 374461 cycles，76.910546 MB/s@187.5 MHz；zlib/strict 0 字节差异 | 功能通过，低于现有 77.76 MB/s 目标 |
| r4 同输入/TB 配对对照 | 355261 cycles，81.067159 MB/s；输出50310 B与r5完全一致 | r5增加19200拍（+5.4045%），两版均有19200个match |
| r5 单核 random/stored，153600 B | 161479 cycles，178.351365 MB/s；32个stored块，双解码0差异 | 随机回退用例功能通过 |
| r5 集成奇数尾块8×3 | RAW30 B、码流28 B、含头UART72 B；四CRC/逐字节参考通过 | 一帧完整，尾垃圾0、重复读0 |
| r5 集成随机64×8 | RAW640 B、码流666 B、UART710 B；四CRC/逐字节参考通过；stored BTYPE0 | 一帧完整，drop/geom/err为0 |
| 双路同步原有控制回归 | SYNC_OFFLINE_PASS mismatch=0 | 启动/等待/预热/NACK/超时/缺路/中止/复位/重锁/过载/回绕 |
| 新增双路配对边界 | PAIR_BOUNDARY_PASS checks=11 | 正负窗口恰等边界、时间戳回绕、超窗拒收、消费同拍新事件保留、无重复发布、disable隔离/恢复、丢失计数 |
| 双路负对照 | 仅在隔离变体把窗口上界改为严格小于，测试于临界窗口明确失败 | 断言能抓到该错误；vsim虽exit0但日志失败，已按文本判为预期拒绝 |

吞吐由 TB 实测周期换算到187.5 MHz，不是时序签核或真实板速。相比370370周期上限，r5 comp超4091拍；需要减少至少4091拍才能达到当前77.76 MB/s目标。19200拍增加与每match新增一拍的修改一致；配对对照确认变化，未用内部逐拍跟踪证明所有额外拍的归因。

旧整帧梯度回归只有+24拍，不能代表无喂数间隙时的编码核服务率。本轮 comp 使用 BP=0/GAP=0，避免相机喂数节流掩盖编码吞吐差异。

## 已定位的检查器问题

原集成参考检查器假定奇数末行也有四平面，8×3用例因此出现Python index out of range；DUT实际已正常完整导出。只在本目录修正参考生成/逆变换对缺失平面的处理，并保留原始失败栈。RTL没有因此修改，四CRC、RAW及变换数据均重新验证。

MODE3/4在原集成TB里没有独立分支，不能只换MODE编号就宣称对应故障语义已覆盖。写入中复位恢复本轮未运行。

## 后续优先级

1. 以本轮相同comp向量约束后续A+流水修改：保持50310 B输出逐字节一致、zlib/strict零差异，周期至少回到370370以内；尽量恢复355261基线。不要以放宽性能目标代替修复。
2. 同步控制仍未接入活动生产顶层。准备实际I2C握手适配、启动/停止与A/B数据路径的集成仿真；本轮配对通过不代表真实曝光同步。
3. 用有明确注入点和判据的测试补写入中复位、坏帧/溢出恢复；不要复用无独立语义的MODE3/4空标签。

## 复现证据

- 编码核：[报告](codec-throughput/result.md)、[完整结果](codec-throughput/result.json)、[输入清单](codec-throughput/input-manifest.json)。
- 配对旧基线：[报告](codec-throughput/paired-baseline.md)、[结果](codec-throughput/paired-baseline.json)。
- 集成边界：[报告](boundaries/result.md)、[结果/输入哈希/命令](boundaries/result.json)。
- 双路：[新TB](sync/tb_sync_pair_boundaries.sv)、[正例日志](sync/tb_sync_pair_boundaries.log)、[原有回归日志](sync/tb_sync_offline.log)、[负对照](sync/negative-control.json)、[输入](sync/inputs.json)。

core r5 SHA256：29b1e3e1a66abef78c228c4189322b0139a266d43bf02827dd1ebe498cdc9828。
core r4 SHA256：d4b799612519d4cb6c32a0c0e87807be84dec711fc01e2146b054d464d1b88de。
两版 comp 输出 SHA256：2601d57cd98d1fe69b2e46fe8423779a5d44bd14c00e1fe2d5faab6ff15a7c05。

父会话独立重算两例周期/吞吐并用标准zlib复核输出、精确结束与零尾垃圾，均与子任务记录相符。以上为探索性仿真结果，不替代项目工作流的独立综合验收和板级验证。
