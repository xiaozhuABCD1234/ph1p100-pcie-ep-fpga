# 输入索引 — 20261026-2138_fpga-integrated-delivery

## 1. 需求与边界
- 需求原文：`D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\request.md`
- 本轮唯一主目标：把现有采集、DDR、三种硬件预处理、A+压缩/原始块回退和PCIe发送后端整合到同一套可构建、可验证的FPGA候选。B路优先；取得b20有效结果后接入A路；A路受阻时继续完成B路后续链路。
- 期限：2026-10-27 FPGA侧可演示最小功能闭环；时间优先，激进复用与集成。
- 后置：2h长稳、大规模图集/压缩率、极限吞吐优化、全面故障注入、精密同步测量、代码美化、非阻塞告警整理。
- 必须保留：数据/像素正确性、长度/CRC、基本反压与所有权、必要时序/CDC；不得放宽约束或忽略错误。

## 2. 现有成果与基线（只读引用）
- A+主run：`D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop`
  - b18：B路真实1920×1080完整A1U1帧，四CRC及解压通过；功能基线与回退。
  - b19：A路布线时序失败（route -0.098 ns/10端点）。
  - b20：A路定向时序修复包；r0已routed **0违例、SWNS +0.012（薄裕量）**、bit/CWC存在，**board=blocked（板时FTDI缺失，0下载）**；本run只读其交接/候选，不得修改其目录、计数或继承下载额度。
- 链路审查run：`D:\fpga\ph1p100\workflow\runs\20261026-144617_fpga-chain-detail-review`
  - 冻结b15；只承接最新候选仍存在的阻塞问题，不照旧报告重修已处理的PAXI。
  - 关键确定问题：RAW10样本格式重打包、好帧/取消事务、PAXI合同、所有权/导出、边界/消费者。
- 双路/同步离线：`D:\fpga\ph1p100\workflow\runs\20261024-221529_fpga-sim-integration-recovery`、`D:\fpga\ph1p100\workflow\runs\20261025-180900_fpga-dual-offline-closure`（G0/G1通过，G2 not_run，父硬件不置done）。
- 三算法RTL：`fpga/csi2/src/img/`（灰度含Bayer→Y8前端、高斯3x3、CDF-min前帧HE），T09模块级done。
- A+压缩RTL：`upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/`（`a1_frame_top.v`、`a1_deflate_core.v`）；INT.P4只读复用b20 r0 `changed-src` 修复版（含`a1_ddr_slot_store.v`/`a1_ddr_arb2.v`），哈希见dispatch只读区。
- PCIe/RK对齐：`D:\fpga\ph1p100\workflow\runs\20261017-011744-rk-fpga-align`（backend candidate manifest、rk-change-list、补丁）。
- DDR1333：`D:\fpga\ph1p100\workflow\runs\20261017_153201_T01_ddr1333_integration`（主候选已上板验证通过）。

## 3. 工程与工具入口
- 工程根：`D:\fpga\ph1p100`
- 活动TD工程：`D:\TD\work\csi2`（原地不动，只读/复制，不争抢）
- TD安装：`D:\anlogic\TD_Release_2026.2`
- 参考设计：`D:\fpga\refs`
- 盘符约定：TD用T:/Y:；仿真用P:/W:；X:保留给TD。
- TD打开前运行：`tools/td/open_td.ps1`或`tools/td/td_env.ps1`。

## 4. 保护对象（不得修改/争抢）
- b18回退件：`T10.b18-b17-b/**`及对应bit/CWC。
- b20活动目录：`T10.b20-a-timing/**`（只读）。
- 其他活动run：`20261024-221529_*`、`20261025-180900_*`、`20261026-144617_*`、`20261026-143924_*`、`20261026-231711_*`、`20261017-011744_*`。
- `workflow/tasks.json`、`docs/**`、全局配置、`D:/TD/**`、`D:/fpga/refs/**`、硬件/COM/JTAG/Flash。
- 生产B01候选`b68c6e18…f9bf`。

## 5. 采用版本与未决
- 压缩路线：LZ77基线+Bayer自有优化混合（单编码器），输出zlib(RFC1950) fixed Huffman+stored，2行块，窗口2048，块级stored回退；BPR1转拓展/可选第二模式。
- 传输：R10F 128B非压缩参考草案仍保留；A+压缩帧使用A1U1（44B头+压缩payload+CRC），与R10F分离。
- 性能目标：1080p30仍为性能目标；功能先跑通，未达帧率必须记录差距。
- 未决：物理Bayer相位、真实RAW图集、RK实际联调、A路b20板级有效结果、板窗与下载授权、集成bit（需板级集成顶层/ADC）。

## 5.1 INT.P4 追加只读输入（2026-10-27）
- P1/P2/P3冻结候选与报告：`INT.P1-r1-manifest.json`、`INT.P2-r0-manifest.json`、`INT.P3-r1-manifest.json`及各自`test-reports/*.md`。
- A+核只读：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b20-a-timing/r0/changed-src/{a1_frame_top.v,a1_deflate_core.v,a1_ddr_slot_store.v,a1_ddr_arb2.v}`（哈希绑定，见dispatch）。
- 上游A+核：`upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/*`（只读）。
- PCIe后端接口参考：`fpga/csi2/pcie_integration/rtl/ep_side/{ddr,img}/**`（只读）。
- 构建入口参考：`tools/pcie_integration/{run_td.ps1,td/01_create.tcl}`、`tools/td/PATH_CONTRACT.md`（只读）。
- 现有解码/样例：`tools/integrated_delivery/a1u1_decode.py`、`evidence/a1u1_sample.a1u1`。

## 6. 本run写入范围
- `D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\**`
- `D:\fpga\ph1p100\fpga\csi2\src\integrated_delivery\**`（新建，不触碰既有src）
- `D:\fpga\ph1p100\tools\integrated_delivery\**`（新建）
- 其他一律只读；如需修改既有生产文件，先在dev-plan记录并经规划批准。
