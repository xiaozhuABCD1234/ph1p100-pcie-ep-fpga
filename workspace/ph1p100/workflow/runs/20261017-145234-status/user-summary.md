目前到了**正式 RAW10/PCIe 候选已完成离线验证、等待实机联调**的阶段，完整双目系统还没有闭环。已有单A相机真实预览出图记录，但新PCIe候选尚未下载，RK也尚未用新协议实际收帧。

**FPGA侧已经做的改动：**

- 接入了带CRC/ECC、行长和帧结束检查的CSI接收链，并接到DDR和PCIe MWr后端。新增“一次授权发一帧、发完等待ACK、匹配后才释放缓冲”的控制，避免RK慢消费时覆盖数据；A/B两路缓冲释放分别管理。
- 把原8位诊断图通路升级成 **packed RAW10 → R10F帧 → DDR → PCIe**：128B帧头、原始/载荷/帧头三层CRC、尾部补零，1080p一帧DMA为2,592,768B。实现位于新的 `fpga/csi2/pcie_integration/` 集成树，旧预览工程仍保留。
- 最新完整RAW子包已于10月17日14:52取得同一候选的三维**离线PASS**；RTL仿真、综合/布线/位流完成，setup余量 **+0.115ns**。**尚未包含真实上板、RK实收或稳定性测量**。[最新判定矩阵](C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261017-011744-rk-fpga-align/verdict-matrix-T11.rk-align-raw-r0.json) · [具体改动](C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261017-011744-rk-fpga-align/raw/change-report.md)
- 另一条预览/时序主线的 **DDR1333 IP已成功生成并完成两次独立复现**，此前IP生成阻塞已解除；它还没有完成集成、综合时序、位流/CWC及板验。旧RGB565白平衡候选已有位流，但修正后的颜色与长稳仍待验证。[DDR1333最新证据](C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/docs/evidence/td2026_ddr1333_accept_20261017.json)

**FPGA侧仍待完成：** 三算法是灰度、高斯、前帧直方图均衡；目前有参考模型和部分RTL，尚未完成三种真实硬件的完整接入验收。压缩只推进当前一条 **Bayer同色预测＋有界Rice＋RAW回退**：已有软件参考和预测/Rice/打包/行组合局部RTL，但RAW选择、行头/CRC、完整帧发布及BPR1传输适配仍缺。它替代赛题JPEG/LZ77基础项的接受口径仍待确认。环境固化与冗余检查已派发，逻辑优化尚待实施；后续还要核实真实相机包几何/Bayer相位、上板、双路曝光同步以及持续吞吐。[统一任务状态](C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/tasks.json)

**RK侧需要改的内容已经整理成补丁，但尚未在RK上编译、安装或运行：**

1. 在驱动冻结版本 `a0215c5` 上，先应用[T07主补丁](C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261017-011744-rk-fpga-align/backend/patches/rka1-driver.patch)，再应用[T11 RAW10增量补丁](C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261017-011744-rk-fpga-align/raw/patches/t11-rka1-r10f-fix.patch)。**只打主补丁不够**：其中草案解析布局需由增量修正，否则会拒收正式R10F帧。
2. 驱动对齐控制与内存约定：CTRL模式A路`0x61`、B路`0x161`，探测RKA1，设置容量/session；单槽、DMA长度2,592,768B。主机槽头仍为16B结构体，数据起点偏移128B；DMA正文内部另有128B R10F帧头。
3. 接收程序按正式R10F布局严格检查长度、几何、session/seq、三CRC和640B尾零，失败拒收；补丁提供`r10f_check`。**还要把“ARM → 等held → 校验 → ACK → 再ARM”循环接入收帧程序**，目前`frame_grab`仍主要是单帧诊断工具。packed RAW10必须解包，现有PGM输出不能直接当8位灰度图。[RK增量与未闭环清单](C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261017-011744-rk-fpga-align/raw/rk-change-list.md)
4. 在真实RK内核树、工具链和Rust环境中编译、加载，再完成实收与稳定性验证。去马赛克、双目标定/校正/匹配/深度和NPU也仍待RK实施；现有PC离线工具不能算RK板端完成，队友交付约定尚待确认。

相机几何/相位尚未板证，RAW候选仍按合成/诊断口径记录。旧摘要中的“DDR1333等待GUI”“T11功能测试在途”尚未同步，本说明以较新的复现证据和14:52矩阵为准。
