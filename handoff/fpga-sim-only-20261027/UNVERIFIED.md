# 未验证项与队友接手顺序

此清单是“还有什么没有证据”，不是硬件执行授权。本地工作限定为仿真与分析，队友负责主仓集成、工具构建和实板推进。每次记录使用的源码 SHA、manifest、工具版本、命令、输出与未执行项，不能合并不同候选的通过结论。

## 从 T11 出口 ARM 阻塞继续

1. 先核对 [T11 原 manifest](archive/board/T11.BRD.P1/manifest-brd-p1-r0.json)、[开发结果](archive/board/T11.BRD.P1/result-r0.md)、[原 TB](archive/board/T11.BRD.P1/sim/tb_brd_g1.v)、[失败日志](archive/board/T11.BRD.P1/sim/g1_scen0.log) 与 source-map 的 drift。它是开发自检 ready_for_test；原 tester 创建失败的日志不能当独立验收。无可认证整机 bit。
2. 在新仿真目录重建同候选输入，从 `st_frames_committed=1`、`st_store_published=1`、`drain_words=124` 向 `desc_arm` 跟踪。当前 `desc_arm=0`、`st_exported=0`、槽读/MWr/doorbell=0；没有 TLP 时“0 payload mismatch”是未到达比较，不能称 payload 正确。检查 publish/ready、descriptor/capacity、frame/base/seq/session 和后端 busy/done 的时序条件，先获得最小可重复失败，再改动。
3. 保留 P4 r2 及 b20 绑定源；特别核对 r2 的两个 timing-hook 文件和 filelist guard，不引入 r3 派生语义失败版本。T11 约 70 项 filelist 的很多依赖未由 27 对象 manifest 单独冻结，现存快照不自动获得历史验收资格。**当前还不能原样复跑历史 r2**：`bayer_raw10_demosaic4_p4.v`（期望 4e108dd8…）与 `img_algo_parallel_top_p4.v`（期望 1cb8262a…）的活动源已经漂移；检查了主仓对应同步路径，也未找到相同 SHA 的副本。`inputs/board-filelist/` 中这两份现存源只作活动快照，不能用来冒充 r2。先恢复精确冻结副本，或把移植后版本作为新候选重新做语义验收。工具/文档漂移及缺失 `INT.P4/td/01_synth.tcl` 同样见 [DRIFT.md](DRIFT.md) 和 source-map。
4. ARM 修复后在仿真完成：非零且 4KiB 对齐基址、容量不足拒绝、精确字节长度、DMA 尾部、TLP payload 和 doorbell；再测 missing EOF、错误 ACK/session/epoch/slot 与 burst 读仲裁。原 missing EOF/wrong ACK 正例依赖出口路径而 not_run，不能用真空通过代替。
5. 明确模型边界：SLOT_WORDS=81920、BASE_WORD=2048、BAR 0x130..0x13C 未实现、DDR ×4 重映射仅仿真等偏差尚需评审。完成仿真后由队友重新冻结候选、独立验收，再独立补实现/实板证据。

## A1U1 与 PCIe 字节链仍有缺口

详见 [T03 字节责任图](archive/offline/T03.pcie-byte-replay/byte-responsibility.md)。已观察真实 store 在显式 TB 环境输出精确 zlib；44B A1U1 头由软件离线重建，硬件 serializer/几何与四 CRC 元数据传递未闭合。camera/session 不在 A1U1 头上，P3 的 camera/slot/epoch/session/capture_seq 到 P2/后端的完整身份承接和 ACK/release 桥没有证明。

store/P2 地址为 256bit **word**，后端 pusher 为 **byte**，需要 ×32 转换和真实 DDR 地址/容量映射。当前 P2 `align_up(zlib_bytes,4096)` 与离线参考 `align_up(44+zlib_bytes,4096)` 不同；长度边界不能混用。70B 示例仅证明 70..95B 最后写字内尾零；96..4095B 页尾未证明。软件 zero-fill 不代表硬件已写零/遮罩。真实 PCIe 收发、ACK、吞吐、DDR 和 CDC 均未验证。

## 时序与候选选择

| 候选 | 已有证据 | 保留缺口 |
| --- | --- | --- |
| P4 r2 | 功能/系统仿真正确；187.5MHz 综合 WNS -0.637ns / 112 端点 | 时序失败；综合 harness 不是板级 shell |
| P4 r3 | 综合 WNS +0.072ns / 0 端点 | 派生变体等价/语义失败，不采用，不与 r2 拼 PASS |
| T11 r0 | 150MHz 板级顶层综合 WNS -2.273ns / TNS -31.547ns / 79 端点 | 125MHz 未测；route/bit/CWC 未运行；G1 出口失败；无已确认独立验收 |
| H-only synthfix | core d2960cfe…、frame_top 4afc26e2…；原型功能通过；综合 +0.029ns | route 在 import_db → Import ChipWatcher 崩溃；无 routed setup/hold/STA/Fmax/生产吞吐 |
| A 本方案 | kill_verified | 只否决该实验方案，不能外推为所有 A+H 不可行 |
| 15:00 H-only route run | 请求/规划材料与主日志 | 无可核验 route 结果；不能据新目录名声称已解决崩溃 |

H-only 是压缩原型的 provisional 候选，不是可直接替换 T11 的整机方案。板卡位流必须绑定同一候选、约束、工具、bit/CWC/BID；当前包不提供这类整机认证。

## 真实 RAW 输入恢复条件

T04 当前合格真实样本 0，真实收益 ratio=null。至少需要一帧可追溯的传感器 packed RAW10 或 u16 原文件；有限图集至少三帧不同内容。须给设备/采集来源/使用依据、W/H/stride、ROI、打包或 u16 大小端、valid_bits=10/right_shift、Bayer 相位及规范化依据。

逐样本独立像素正确性证据必须绑定规范化 RAW SHA：method、reviewer、correctness_basis、evidence_path、evidence_sha256、normalized_raw_sha256、review_decision=qualified，并声明 sensor_pixel_oracle_verified=true。文件 SHA、round-trip、“图像看起来正常”和 content_id 文本不能代替这项证据。

packed RAW10 要求 W%4=0、stride=W*5/4；u16 要求 stride=W*2 并明确大小端/移位且不丢非零位。工具不猜行 padding、不隐式裁 ROI。相位 unknown/非 RGGB 仅 mode=00；RGGB 预处理需要可追溯相位证据。B18 的 sensor_pixel_oracle_verified=false、物理相位 unknown，只能是 historical_control。N/L、CONTENT=2、随机/ramp/常量均为合成控制。

使用 [原输入 schema](archive/offline/T04.real-raw10-benchmark/inputs/input-schema.json) 在新工作目录新建配置/输出；先完成路径适配和来源审阅，再运行测量。不要改 r0 空输入、阈值或分类来消除 blocked。此整理没有执行 portable 测量或新 RTL 仿真。
