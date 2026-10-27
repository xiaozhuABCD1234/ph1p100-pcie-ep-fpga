# T10.b10-b9-fix 设计指南（冻结增量）

基座：`T10.b9-rawstore/fpga-design-guide.md`（**继续有效**，本文件只写增量与冲突覆盖）。冲突时以本文件为准。

## 1. 数据与协议（不变，禁止改动）

| 项 | 冻结值 |
|---|---|
| 帧头 | 44 B，`A5 5A` magic + ver/len/几何/长度/四 CRC/profile（与 b9 一致） |
| 载荷 | 连续 `stream_len` 字节压缩流，**不做任何帧内插入** |
| 状态包 | `A5 5A B1 03`、LEN=177、43×u32、XOR8 over 0..175，**只在帧间发送** |
| 帧内不变量 | 480 beat/行、4 组/256-bit 字、129,600 字/帧、2,592,000 B；`EXPECT_BYTES` 精确匹配才 publish |
| UART | 115200 8N1（`UART_DIV=434`），不改分频/协议 |
| 端口/SDC/引脚 | 不改（`p2_board.sdc` 原样使用） |

**明确否决**：帧内强插 177 B 状态包（破坏 `decode_frame.py` 的 `stream_len` 语义与 CRC/解压），本轮不采用、不评估为可选项。

## 2. 四槽 DDR 布局（本轮唯一参数改动）

- 单位：256-bit word 地址，区间**含端点**。
- `RAW_BASE = 0`；`RAW_WORDS = 129,600`；`CMP_WORDS = 81,085`。
- **`CMP_BASE = 262,144`（2^18）**，替换 b9 的 131,072。
- 区间：RAW0 0–129,599；RAW1 129,600–259,199；CMP0 262,144–343,228；CMP1 343,229–424,313。
- 断言（RTL `initial`/仿真 `$error`，综合可忽略）：
  - `CMP_BASE >= RAW_BASE + 2*RAW_WORDS`
  - `CMP_BASE + 2*CMP_WORDS <= DDR_WORDS`（`DDR_WORDS` = 从 TD DDR IP 配置核对的真实容量，写成常量并记录来源）
  - `SLOT_WORDS <= 2**AWB`（RAW `AWB=18`、CMP `AWB=17` 均满足）
- 修改点仅 `camera_a1_uart_top.v` 的 `CMP_BASE` 默认值（L43）与其唯一使用处 L483 的 `.BASE_WORD(CMP_BASE)`；`p2_a1_board_top.v` 不覆盖该参数（已核对）。若为可读性把常量提到 localparam，必须保持默认值语义不变。

## 3. 状态/帧仲裁（B9-01）冻结性质

1. `status_due = sts_tick || sts_want` 单点计算，与「开下一帧」在同一仲裁处互斥决策。
2. 状态获得帧间机会**与 `dq_cnt` 无关**；`dq_cnt>0` 不得阻塞状态。
3. tick 当拍不得出现「状态启动 + 帧出队」双动作，不得双写 TX，不得 pop 未获准的描述符。
4. `accepted_pop` = 本拍真正进入 `E_OPEN` 的那一拍；`dq_rd`/`dq_cnt` 与之同拍一致。
5. 帧头/载荷连续：最后一个 UART 字节完成前不启动下一帧或状态。
6. `sts_want` 粘滞直到被真正发送；`hb_tick`（idle 心跳）路径同样不得与状态/帧同时获准。

**不做**：帧内抢占、状态包插队到帧中间、把状态包拆块、改包格式。

## 4. 描述符队列（B9-02）冻结语义

- 深度 2，`dq[0:1]`；指针 1-bit 环绕；`dq_cnt` 由 `accepted_push`/`accepted_pop` 单点更新。
- 满队列同拍 pop → push 允许（计数保持 2）；满且无 pop → push 拒收并计数（仅 TB 层次/CWC 可观测，**不进状态包**）。
- 逐拍断言 `dq_cnt == 占用数`，指针 ∈{0,1}。

## 5. R1/R2/R3 观测口径

| ID | 必须观测 | 通过判据 |
|---|---|---|
| R1 | FIFO 满时丢 LAST；LAST 在 skid 受背压时 abort | 坏帧不发布、计数正确、slot 回 FREE、无孤儿 writer、下一好帧可发布并读回 |
| R2 | 只送 1 字后停输入；AW/W 独立背压 | `paxi_awvalid`/`paxi_wvalid` 各恰 1 次；valid 期间地址/数据稳定；不重复、不丢 |
| R3 | AR 已握手未回 R 时业务复位；旧 R 已 valid 且背压 | 旧响应不交给新会话；若无法安全覆盖则记 `not_covered` + 风险说明 |

## 6. 构建入口与工作目录

| 项 | 值 |
|---|---|
| 综合/布线/bitgen/CWC | `r0/td/{01_build.tcl,02_bitgen.tcl,03_cwc.tcl}`（由 b9 复制后改路径到 `T10.b10-b9-fix`） |
| TD 前置 | 先跑 `tools/td/open_td.ps1`；**X: 档位禁用**；T:=本任务 `td` 目录，Y:=项目根 |
| 仿真 | ModelSim + Python，入口 `r0/sim/run_sims_b10.py`（由 `run_sims_b9.py` 扩展），单次 ≤5 min 超时 |
| 下载/采集 | `r0/board/download_sram_b10.tcl` + `capture_com8.py`；**先下载、后开 COM8** |
| 候选 | `CANDIDATE-MANIFEST-b10-b9-fix-r0.json` + `r0/artifact-hashes.txt` |

## 7. 观测与探针约束

- 状态包字段**不变**（43×u32，ver=3、len=177）；新增内部计数不得进包。
- CWC 允许按层次名加探针（优先 `estate/sstate/sts_want/dq_cnt/a1_busy`、DDR AR/R 等待、业务复位电平），但**不得改顶层端口**；TD 不支持层次探测则记录并仅用现有计数器。
- bit / CWC / BID 必须与同一 manifest 绑定；不得把旧 b9 的 bit/CWC 与本轮源码混拼。

## 8. 板级顺序（已证明）

1. 确认 COM8 未被占用（监听器**不开**）。
2. `download_sram_b10.tcl` → SRAM 下载，日志记 `B10_DL_OK`、bit SHA256、BID（此时 hwserver 独占 FTDI）。
3. 关闭 hwserver 后开 COM8（115200 8N1）采集 180 s。
4. 解析：状态包 XOR/ver/len → 计数增量 → `exported>0` 时按 44 B 头 + stream CRC + zlib 解码。
5. 失败即停：不再下载、不 Flash、保留全部原始流与日志。
