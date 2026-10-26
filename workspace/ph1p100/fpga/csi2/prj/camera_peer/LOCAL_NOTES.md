# 本地接入说明

> **2026-10-11 当前候选：** 主工程已接原生DDRX5与1080p60显示时钟，保持4K30 RAW10、27MHz MCLK和960×540灰度。phy_display60_20261011_174231最终STA setup +0.008ns/hold +0.020ns，生成raw10_891_gray_1080p60_20261011_174231.bit，真实相机版等待反馈；DDR未接。独立1080p60条纹已获用户成功反馈。新CLI入口为仓库tools/td/build_raw10_display60.tcl，从D盘工程目录执行；下方旧bit状态仅历史。

源自上游提交2d59180c38e7b7be6ac992c05c42eef12ce2811b，原README记录固定来源版本，最新状态以本文件和项目docs差异报告为准。

工作目录是D:/TD/work/csi2/prj/camera_peer，仓库fpga/csi2/prj/camera_peer仅源码快照。打开本机D盘fpga_prj.al。另一个路径/机器需要先调整.al中Project Path；源文件采用相对路径。没有自动同步。

较早检查点修改cam_preview.v行为：水平缩位、垂直进位、clog2b、完整RAM地址空间与同步读口/bram属性；图像仍960x540，输入仍4K RAW10，未改相机/引脚/tap。原PCIe骨架未覆盖。测试平台未纳入综合工程。

本机构建syn_pad_1/phy_pad_1已产生bit，但setup WNS=-0.221ns，STA没有通过；不要把它作为验收bit。详细警告及后续路线见仓库docs/相机链路方案对照与验证_2026-10-10.md。未下载或烧录。

原gen_ip.tcl是旧实验，不执行；download_sram.tcl为原Linux路径，不执行。build_padded.tcl用于本次新run，重复执行已有同名run会报错；未来构建应明确新run名，保留证据，不reset或批量删除。

原样审查副本在D:/TD/work/_peer_f9p_review_20261010。UPSTREAM_MANIFEST.json记录原文件SHA256；LOCAL_STATE.json记录当前源码、bit、验证摘要和修改清单。D盘_sim、_evidence、_probe和fpga_prj_Runs保留实际日志，源码快照不含大体积构建产物。

2026-10-10最新：RAW10作为主线、先灰度显示与DDR；RAW12解包模块封存。新修复帧重启/行相位、两拍DE、HS/VS及HDMI包装控制对齐，移除PLL时钟互斥误约束。新数学/行帧/包装测试通过，syn_seq_20261010_203628/phy_seq_20261010_203628完成route但STA失败：setup WNS=-0.515ns、28端点、224ERAM、3172Slice；本轮没有bitgen/下载。DDR尚未接入。用户批准下一步891Mbps/27MHz/4K30 RAW10及1080p30 HDMI，尚未修改模式。详见仓库docs/RAW10灰度显示与DDR推进记录_2026-10-10.md。
