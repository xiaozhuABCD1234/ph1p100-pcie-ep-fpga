# question-board-chain.md — P3 已授权/默认确认（T10，2026-10-24）

> **状态：已授权并上电，P3 已派发 ready。** 用户原话：“该给的权限我给，该上电的我都上了，剩余按默认或者你做好判断，我也基本都是符合的，开始执行吧（我现在另一个对话想把目前文件夹里的工程全部搬运到D盘统一维护，后续生成工程文件也需要再D盘，这些都要注意，如发现工程路径出现问题，先不要停止）。”
>
> 候选：bit `d1ac8726e84f6584d49979dd223d6e8c484e559bf2a3ad3b2302972c58efc142`；CWC `37b608540f7924f60a09db5ba2b543334db1259ef69f2a1c982cf161cbc8b25c`；BID `3de68e68…f213`。
> 硬边界：仅 SRAM **1 次下载**；不写 Flash/efuse/SPI/svf；不接 PCIe/RK；不做双路/G4；失败不自动第二次下载。

## 0. 默认确认（按用户“基本符合”）
- [x] 板窗/在场：已上电并授权；A 相机已接、B 断开、BANK13 1.8V。
- [x] 镜头/曝光/场景：默认固定；ROI 中心 1920×1080、2×2 对齐；Bayer RGGB phase-0。
- [x] UART：自动检测 COM；主机 Python3 + pyserial + zlib。
- [x] 顺序：先 TPG、再真实 A 帧；失败即停。
- [x] Q9 boundary：默认接受 boundary；未补测项记录在案，不阻塞 P3。
- [x] 范围：仅 SRAM 一次下载；无 Flash/PCIe/RK/双路/G4。

## 1. 重要技术边界（规划判断）
1. **UART 波特率**：冻结 P2 bit 的 `UART_DIV=1628`、`clk_uart=187.5 MHz` → **115.172 kbaud**。P3 使用 **115200 8N1**；**921600 不支持**（会得到错误字节），如需 921600 必须新 bit/CWC，超出本次授权。
2. **TPG 进 A+ 不可用**：冻结 P2 bit 的 TPG 只驱动 HDMI 显示；A+ 输入是相机 raw tap，没有 TPG mux。**不得伪造 TPG A+ 帧**；P3 记录 `tpg_a_plus=not_available`（boundary），真实 A 帧为主证据。若必须 TPG，先停止并申请新 bit。
3. **路径**：P3 产物默认 `D:\fpga_work\20261020-0209_singleA_aplus_closedloop\P3\`；D: 不可用则回退 run 目录并记录。源树若被搬到 D:，先探测同名 run/bit，找到则切换并记录旧→新映射；找不到则用 P3 workdir 中冻结 bit/CWC/解码器继续，不因路径问题停止。

## 2. Q1–Q10 记录（默认/已确认）
### Q1 板窗与在场
已上电并授权；板卡 MLK-F9P-CA05-PH1P100 / PH1P100SBG484-3；TD/板测串行。

### Q2 硬件条件
A 相机已接；B 已断；BANK13 1.8V；供电/散热默认正常；Type-C JTAG+UART；仅 SRAM；不接 PCIe/RK/双路/G4。

### Q3 镜头/曝光/场景
默认固定；中心 1920×1080 2×2 对齐；Bayer RGGB phase-0。

### Q4 一次 SRAM 下载授权（已授权）
> 授权本轮对候选 bit `d1ac8726e84f6584d49979dd223d6e8c484e559bf2a3ad3b2302972c58efc142` 执行 **1 次 SRAM 下载**，仅用于真实 A 帧的采集→DDR→A+→保存→读回→UART 导出→PC 还原短上板验证；不写 Flash、不接 PCIe/RK、不做双路/G4；若失败不自动第二次下载，需重新申请。

### Q5 UART 导出与主机
COM 自动检测；**115200 8N1**（冻结 bit 115.172 kbaud）；Python3+pyserial+zlib；保存原始 UART 字节流、header、stream、raw、还原帧、CRC/长度/吞吐日志。

### Q6 ROI 与 Bayer
中心 1920×1080、2×2 对齐；RGGB phase-0；记录 RAW10 打包/有效区/裁切。

### Q7 测试顺序与失败边界
- TPG 进 A+：`not_available`（boundary，见 §1）。
- 真实 A 帧：一帧完整采集/压缩/保存/读回/UART/PC 解码；失败即停、保留日志、不第二次下载。
- 不发布半帧；坏帧/溢出/复位撤销。

### Q8 采样方案与保存路径
- 冻结：bit/CWC/BID、命令、帧数（真实 1 帧；TPG boundary）、ROI/profile、期望 header/CRC。
- 保存：`D:\fpga_work\20261020-0209_singleA_aplus_closedloop\P3\`（或 fallback）；含 bit/CWC 副本、下载日志、UART 原始流、header、stream.zlib、raw.bin、还原帧、CRC/长度/吞吐、路径映射。

### Q9 P1 boundary（默认接受）
未补测项记录在案，不阻塞 P3：MODE=3/4、store-only 2,594,706 B、MODE=1 缩短帧、W=8,H=3 尾块、写入中复位恢复。P3 报告必须列出未补项；不得声称已通过。

### Q10 范围确认
仅 SRAM 一次下载；不写 Flash/efuse/SPI/svf；不接 PCIe/RK；不做双路/G4；不推送、不联系队友；P2 离线 PASS 不替代 P3 板级 PASS。

## 3. P3 执行摘要
1. 建 D: P3 workdir，复制/校验 bit/CWC/manifest/PC 解码器；记录路径映射。
2. TD BitWriter **1 次 SRAM 下载**；校验 BID/bit 哈希；复位；无 Flash。
3. COM 自动检测；115200 8N1；一帧真实 A → 采集/压缩/保存/读回/UART；PC zlib+逆变换；记录 CRC/长度/吞吐。
4. TPG 进 A+ 记为 `not_available` boundary；不伪造。
5. 任一步失败即停；保留日志；不第二次下载。
6. P3 完成后派 **P4 新独立测试者**（60 min/40 calls，无 TD/下载）核验。
