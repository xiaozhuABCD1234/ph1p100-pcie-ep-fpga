# T11.rk-align-base — 板测环境清单（上板前确认/采集事项）

**本包不操作硬件**：不扫描 JTAG、不打开串口、不下载位流、不写 Flash。本清单只给操作者"上板前要确认什么、用什么入口、记录什么"。板测执行属 `T07.rk-align-board`（system 独占窗口）。

## 0. 前置条件（缺一不可）

1. **候选位流与 G2**：同一候选 manifest（当前 T11 冻结 `raw/candidate-manifest.json` = `AAB0CC08…6975`）下的唯一 bit；G2 达标（相机字节域 setup ≥ 0）。未达标候选不上板。
2. **硬件独占窗口**：确认没有其它人/任务正在使用该板与 JTAG；窗口开始/结束时间记录。
3. **回退位流已就位**：T07 r3 bit `0943CB36…8B0A` 或旧主线 002820 bit（见 `env/environment-handbook.md` §7），且加载方法可用。
4. **RK 侧事实**（若要做端到端实收）：设备 BDF、内核/驱动提交、`uname`、`getconf PAGE_SIZE`、PCIe MPS 协商值、DMA mask/IOMMU 状态、已打 **RKA1 + T11 增量**补丁的驱动（未打补丁的旧驱动会拒帧，fail closed 是设计）。

## 1. FPGA 单板基础观测（不需要 RK）

| 项目 | 入口/方法 | 只读探测步骤 | 记录 |
|---|---|---|---|
| JTAG 链与器件识别 | TD/BW 工具（`D:\anlogic\TD_Release_2026.2\bin\bw_commands_prompt.exe`；GUI 可用 TD） | 连接后先做**只读**链扫描/ID 读取；确认器件型号与封装与工程一致（PH1P100SBG484） | 器件 ID、链上器件数、工具版本、时间 |
| 独占窗口 | 人工确认 | 无人/无任务占用；记录窗口起止 | 起止时间、占用者 |
| SRAM 易失性加载 | 经确认的下载入口（**不写 Flash**） | 加载当前唯一 bit → 读回状态/校验（如工具支持） | bit SHA256、加载结果、失败现象 |
| 恢复步骤 | 同入口 | 测试完恢复：加载回退 bit（或按窗口约定保留当前候选） | 恢复用的 bit SHA256、时间 |
| 电源连续性 | 人工 | 记录上电/断电次数与时刻；不断电恢复后不宣称"修复" | 电源事件表 |

## 2. FPGA 板内观测点（UART / ChipWatcher / 寄存器）

**本候选无 CWC 生成物**（清单可核）→ 观测以 UART/寄存器读为主。

| 观测点 | 地址/入口 | 预期 | 记录 |
|---|---|---|---|
| BAR0 MAGIC | 0x40 | `0x50434946`（"FICP"） | 实测值 |
| RKA1 扩展存在 | 0x118/0x11C | `RKA1` / 版本（旧读 DEAD_BEEF 表示旧 bit） | 实测值 |
| TX_STATUS | 0x114 | armed/busy/held/rejected/draining 位 | 各阶段快照 |
| 推帧计数/状态/错误/最近帧 MWr 数 | 0xC0/0xC4/0xC8/0xCC | 计数单调；错误码语义（0..4 旧 + 5..11 新） | 帧数、错误码、MWr 数 |
| 授权容量/会话 | 0x100/0x104 | 活动期写被拒并置错误码 10 | 写入尝试与结果 |
| checked CSI A/B 诊断 | 0x120/0x124、0x128/0x12C | {good,bad,hdr_err,crc_err} 低 8 位 + {last_lines,last_wc} | 逐帧/周期采样 |
| R10F 写者发布握手 | 0xA0~0xAC（A）、0xE0~0xEC（B） | seq>0、base 双缓冲交替、**len=2,592,768**、status 无 err 位 | 采样值 |
| 推帧模式/源/相机选择 | 0x44 bit6/bit7/bit8 | 与预期配置一致 | 实测 |
| 原相机状态字 | 0x80..0x98 | lane_valid、cfg_done、in_frame/in_line、tap 等 | 实测 |
| 几何回填用 | 0x120..0x12C + 0xA0..0xAC | 实际 WC/行数/丢组 → 复核 W/H/X0/Y0/SKIP_ROWS/BAYER_PHASE 占位参数 | 实测 WC/行数 |
| UART | `txd` 引脚（uart 观测；接收线让位给 MIPI，板上不用串口接收） | 若接上 UART 转接：读状态输出 | 波特率/内容/时间 |

## 3. RK 侧（端到端实收需要）

| 项目 | 需采集事实 | 用途 |
|---|---|---|
| 设备 BDF | `lspci -D` 中的本卡地址 | 绑定/操作定位 |
| 内核/驱动 | `uname -a`、驱动 commit、`dmesg` 绑定日志 | 版本对应；失败定位 |
| PAGE_SIZE | `getconf PAGE_SIZE` | 槽布局（hdr_bytes=128 / dma_bytes=2,592,768 / stride=PAGE_ALIGN(128+dma_bytes)）与页对齐 |
| MPS | 协商值（与 FPGA 侧 `tl_cfg_max_payload_size` 对照） | 固定 128B 载荷的前提 |
| DMA mask / IOMMU | `dmesg`/sysfs 状态 | 地址宽度与可达性 |
| 补丁 | RKA1 + T11 增量已应用（`r10f_check` 可运行） | 严格解析拒帧是设计（fail closed） |
| 收帧 | 100 帧零 CRC 错 + 10min 短稳（G3/G4 阈值按任务书） | 端到端判定 |

## 4. 帧内容核对（RK 先严格解析，再谈像素）

- `hdr_bytes=128` 起、`dma_bytes=2,592,768` 字节；头 128B：magic "R10F"、version 1.0、format/codec=0、valid_bits=10、packing=0、width=1920/height=1080/stride=2400、raw=payload=2,592,000、**flags=2（ROI 裁减）**、session=授权值、seq=门铃值；三层 CRC；尾 640B 全 0。
- 工具：PC 侧 `tools/pcie_integration/r10f_strict.py`；RK 侧 `r10f_check`（见 `raw/rk-change-list.md`）。
- **几何/相位未板证**：W=1920/H=1080/X0=960/Y0=540/SKIP_ROWS=37/`SRC_BAYER_PHASE=0` 均为占位；一切帧内容按 **synthetic/diagnostic** 对待，不得当真实相机几何/颜色证据。板测后按实测 WC/行数回填参数并重跑 G1/G2。

## 5. 反例与恢复

1. 错误 ACK / CANCEL：held 槽不被覆盖；错误 ACK 只置 reject 粘滞位。
2. held 期间拔插/复位：旧会话响应隔离；重新 ARM 后新会话全流程。
3. 链路未起（link_up=0）：ARM 被拒是**有意行为**；记录现象，不判故障。
4. 长 wait 持稳：包内 wait 不丢拍；已开始的包补完再排空（不截半包）。
5. `push_done`（0xC0）只在"数据+门铃都发出"时 +1；timeout/CANCEL/错误不加 —— 不要把 0xC0 当"发过就好"。

## 6. 记录模板（每次板测必填）

- 操作者/时间/窗口起止；候选 manifest SHA + bit SHA256；加载方式与结果；
- 观测点读数（时间序列/计数）；异常现象与原始日志路径；
- 回退位流与恢复动作；未测项与下一步。
- 判据分级：`pass / fail / not_run / blocked / not_applicable`；不把"没测"写"通过"。
