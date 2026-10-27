# FPGA设计指南 — 20261026-2138_fpga-integrated-delivery

## 1. 任务范围与G层
- 本轮主目标：采集→DDR→三种硬件预处理→A+压缩/原始块回退→PCIe发送后端，同一候选可构建可验证。
- G0：接口/单位/预算/双方责任冻结（本指南）。
- G1：模型/仿真/软件：正反向、边界、恢复、反压。
- G2：构建/实现：综合、最终STA、约束覆盖、CDC/复位、资源。
- G3：上板功能：候选下载、真实数据、恢复（条件具备时）。
- G4：长稳/性能：本轮后置，仅记录差距。
- G5：集成/发布：本轮部分（接口版本、端到端一致性、材料、回退）。

## 2. 像素与帧
- 采集：RAW10 packed（5字节4像素），Sony 2×2 binning 1080p模式表为10bit ADC但12bit输出；线上RAW10按b0..b3=P0..P3[9:2]、b4={P3,P2,P1,P0低2位}。
- A+入口必须接收packed RAW10字节流；禁止把4×10bit样本向量直接送入要求packed RAW10字节的A+入口（链路审查ROOT-01）。
- 帧/ROI：默认1920×1080，X0=960，Y0=540，SKIP_ROWS=37（RTL参数，未板证；2192 vs 2197保留conflict）。
- Bayer相位：物理相位unknown；PHASE=3仅占位，不能写成已验证。
- 帧状态：sof/eol/fe/good/abort；好帧、最后写可见、取消、slot与描述符必须原子发布；只OR晚abort不能撤销已发布/已领取事务。
- 三算法输出为Y8/灰度，不是Bayer；Gray8/高斯/HE输出不能套用同色预测语义；RGB8→灰度RTL不是完整Bayer前端。必须明确模式选路。

## 3. 算法与模式
- 三种算法：Bayer→Y8灰度、高斯3x3、CDF-min前帧HE；硬件并行，明确输出选路与模式；RAW旁路保留。
- HE：换LUT/首帧/四像素同bin冲突；Signed扩位、舍入/饱和、边界、首帧/坏帧处理。
- 模式：RAW10直通、灰度、高斯、HE、RAW旁路；模式切换必须清空/同步，防止混帧。

## 4. 压缩与传输
- A+：LZ77基线+Bayer自有优化混合；输出zlib(RFC1950) fixed Huffman+stored；2行块，窗口2048；块级stored回退；最坏膨胀+0.1044%。
- 压缩原长、内部BPR1精确长、外层传输长、DMA对齐长分别命名。
- CRC：每个CRC覆盖哪段原始/压缩字节、是否含头/填充必须写清；解码器按精确范围消费，拒绝截断与非规范尾部。
- A1U1：FPGA压缩帧格式（44B头+压缩payload+CRC），与R10F非压缩传输参考草案分离。
- R10F：128B非压缩传输参考草案；现有解析器raw_bytes<=payload_bytes及raw CRC按载荷前缀计算的假设对压缩不成立，不能只改codec_id接通。
- PCIe发送后端：必须接入实际A+输出槽，贯通描述符、有效长度、尾拍、完成及释放；不能只接UART或留占位接口。
- RAW接收入口：保持已有RAW接收入口可用。

## 5. 缓存与所有权
- PAXI：冻结同版本原生合同（地址左移3位、完整写mask、同拍合法性）；行为模型必须考虑mask与原生接纳限制。
- slot/描述符：begin/abort消耗排序位，必须使用真实发布顺序与失败关闭合同；覆盖abort、stall、领取/取消、后继恢复。
- 导出器：检测ID/长度错配必须停止发送，不能继续发头；watchdog close覆盖R_AR等待态。
- capture_seq缺口、旧响应与新会话隔离。

## 6. 时钟与实现
- clk_a1 187.5MHz（A+），ddr_user，mipi_a_byte_clk，sys_clk 50MHz，pclkx1。
- 最终STA目标：clk_a1 WNS/TNS≥0，hold≥0，0违例；资源在器件内；ERAM+CWC≤300。
- CDC：单时钟域为主；双路/异步FIFO如需新增，必须单独授权与验证。
- 约束：SDC/ADC基线冻结；不得false path/multicycle/降频/seed sweep/bitgen下载 without authorization.
- 构建入口：TD用T:/Y:；仿真用P:/W:；X:保留给TD；打开TD前运行tools/td/td_env.ps1。

## 7. 双路接入
- B路优先；A路在b20有效结果后接入。
- A/B身份区分、必要调度；防止串帧、混路、覆盖。
- 先完成双路功能，精密曝光同步指标后续测量；SOF配对不等于曝光同步。
- 复用已有双路离线成果；不合并生产顶层冲突。

## 8. 交付与候选
- 同一manifest绑定所有功能；必要回归、综合布线及条件允许的短板验。
- 输出：bit、构建入口、协议说明、解码工具、真实样例、最短操作步骤。
- 候选身份：manifest SHA256、bit/CWC/BID SHA256、输入哈希、工具版本、命令与工作目录。
- 回退：保留r2/b18等历史候选与manifest。

## 9. 已冻结 / 待确认 / 不适用
- 已冻结：压缩路线、A1U1/R10F分离、三算法并行、1080p30目标、G层定义、预算5倍授权。
- 待确认：物理Bayer相位、真实RAW、RK联调、b20有效结果、板窗与下载授权、PCIe真实传输。
- 不适用：G3/G4板测在无板窗时not_run/blocked；G5部分不适用直至集成完成。纯文档/软件子包须写G2/G3不适用理由。

## 10. INT.P4 集成与构建冻结（2026-10-27）
- 同一候选：P1 `integrated_input_processing_top`（RAW10 vector→packed RAW10 pk流 + 三算法/旁路/Y8）→ A+核 `a1_frame_top`（b20 r0只读候选，packed RAW10 in→zlib流）→ A+槽存储 `a1_ddr_slot_store`（MODE=1）→ P2 `aplus_pcie_egress_adapter`（描述符/有效长度/尾拍/完成/释放）→ 后端描述符面；P3 `dual_channel_capture_scheduler` 负责A/B身份、`a_enable`门控、B优先/轮转与全字段释放匹配。
- 单一 `clk`/`rst_n` 域，目标187.5MHz（5.333ns）；本轮不新增CDC/异步FIFO。A1U1与R10F保持分离；RAW旁路与Y8语义不得混用。
- 集成顶层只允许薄胶合，不得用stub替代待实现模块；接口不匹配时记录精确端口差异并加胶合，禁止静默改P1/P2/P3语义。
- TD只在run目录`INT.P4/td/`建工程；源码绝对路径只读引用；不得写`D:/TD/work/csi2`、不得复用b20工程/计数/下载额度。启动前确认无其他TD进程。
- 本轮bitgen/CWC/下载/Flash=0：无板级集成顶层与ADC，不伪造引脚或约束；bit记not_run。b20 bit为独立历史候选，不属本次交付。
- 交付文档必须把“RTL仿真/接口仿真”与“真实PCIe传输/上板”分开写；RK联调待联调。
