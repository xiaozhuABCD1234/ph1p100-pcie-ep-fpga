---
name: fpga-design-guide
description: Use when this FPGA project's planner or implementer must freeze task-specific data, interface, timing, buffering and evidence conventions before module integration.
---

# FPGA 工程设计规范

替换截图规划者引用的幻灯片设计规范`dg-gray-slide-designer`。本技能由规划者/开发者按任务需要使用，不新增常驻角色，不派生代理。需求理解、拆分、依赖、范围与三维验收由规划者负责；主只传路径，不读完整指南或判断工程影响。

读取[项目入口](../fpga-orchestrator/references/project-context.md)的任务相关项、本次需求与已有设计/接口；只冻结相关项，引用原文件。纯文档配置只定配置合同、写范围和静态复核，不强制读生产源码、访问D盘、跑TD/板测。通用规范不替代实际工具报告或双方确认。旧值与新值冲突时给来源和版本，不凭“最终版”文件名决定。

## 必须明确的工程语义

| 领域 | 本任务相关时需冻结 |
|---|---|
| 像素/帧 | RAW10 packed与u16容器、宽高/stride/ROI、Bayer相位/方向、大小端、sof/eol/fe/good/abort、有效字节/bit |
| 算法 | 参考模型、signed扩位、舍入/饱和、边界、首帧/坏帧、HE旧LUT与新LUT发布、四像素同bin冲突 |
| ready/valid | 接受条件、stall保持data和sideband、同拍take/refill、复位pending撤销；CSI不可反压，溢出拒整帧并计数 |
| 压缩 | 同色x-2预测、锚点旁路、残差映射、k/escape、码长上限、位序/填充、RAW回退、长度/CRC、完整有效帧才发布 |
| 缓存 | PAXI实际单位/握手、地址/容量高位、所有权、满队列丢弃、capture_seq缺口、旧响应与新会话隔离 |
| PCIe/RK | 匹配版本IP端口、DW-valid区别于byte keep、MPS/4KiB/BE、DMA地址与容量授权、完成可见性和回收 |
| 时钟/实现 | 各时钟/复位域、CDC方案与豁免、实际约束/IP/ROM/顶层、最终STA目标、资源预算与构建入口 |
| 证明范围 | 本任务G层、输入manifest/哈希、实际命令/工具版本、DB/报告/bit/CWC对应、板测操作者与候选 |

## 当前接口接入重点

- BPR1是压缩内部封包；R10F 128B是非压缩传输参考草案。不能只改`codec_id`就接通：现有解析器的`raw_bytes <= payload_bytes`及raw CRC按载荷前缀计算的假设对压缩不成立。
- 压缩原长、内部BPR1精确长、外层传输长、DMA对齐长分别命名，写清每个CRC覆盖哪段原始或压缩字节、是否含头/填充。解码器按精确范围消费，拒绝截断和非规范尾部。
- 预览“替换旧READY”与正式传输队列的持有/丢帧语义不同，不能直接沿用预览策略推定DMA安全。
- Gray8/高斯/HE输出不是Bayer；不能不换模式就套用同色预测语义。RGB8→灰度RTL不是完整Bayer前端。
- 配对帧号和SOF差值不能代替曝光同步；HDMI显示Hz不能代替采集fps；并行STA不证明HDMI串行电气资格。

## 预算与变更

吞吐按最坏RAW回退、可变码长、DDR全部读写及突发/服务空窗算，不依赖平均压缩比。明确设计预算与实测分开。使用本项目已有双路1080p30预算时注明头/报文另计；8bit/100MHz打包原型不作双路满速证明。

改变共享协议/几何/时钟/IP时，由开发/测试给出需要复测的维度、输入变化与证据复用依据，主按清单传输，不自行判断影响；队友确认材料交用户安排，不扩大外部消息授权。遵守已选1080p60和封存/暂缓项，不因优化擅自改变用户目标；失败不通过放宽约束掩盖。只有确需新增规范时才写，避免重复建设。

指南结尾列“已冻结/待确认/不适用”和本次三类检查维度的边界；交由规划者纳入dev-plan。不得将配置值、设计预算、作者结果写成当前板实测。
