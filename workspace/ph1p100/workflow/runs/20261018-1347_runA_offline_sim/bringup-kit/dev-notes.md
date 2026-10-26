# dev-notes.md — T11.runA-bringup-kit（实现记录/口径说明）

## 1. 解析器口径

- 子命令：`regs`（寄存器 dump 判定）与 `channel`（B1/bw 会话日志证据）。退出码 0/1/2；输入非法（含空文件、非法行、非法编码、重复 offset）一律 2 且不写 record。
- 一次 record = 一个输入 + 一个时间点；同一 offset 重复即拒收，避免“同文件多采样”掩盖歧义；时间序列应产生多条 record。
- 判定语义：规则输入缺失 → BLOCKED；`when` 前置条件为假 → NOT_APPLICABLE；两者都不算 PASS。summary 只要 fail/blocked 非零即非 pass。
- `channel` 模式只证明三件事：器件 ID=PH1P100、`PRG-2014` + `-mode jtag` 下载证据、无 flash/SPI/efuse/SVF 文本；**不蕴含任何寄存器读数**。
- 文本格式：`0xOFFSET = 0xVALUE`（分隔符 `= : ,` 或空白；裸 offset 必须 3 位十六进制），值不带 `0x` 视为十进制；`#`/`;`/`//` 注释。这样时间戳行（如 `14:12:03`）不会被误承认。

## 2. 规则集（17 条）

- 身份/版本：0x040、0x118、0x11C、0x108（W1 读 0）。
- 结构保留位：0x044、0x0A8、0x0C4、0x0E8、0x114、0x0F4（掩码取自 `ep_bar_win.v` 头部位义）。
- 数据一致性：0x0AC/0x0EC=2,592,768、0x0A4/0x0E4 128B 对齐且非零、0x0C8∈[0,4]、0x0CC∈[1,2400]。
- 需要“已采集”才成立的规则带 `when`（A/B seq>0；PUSH_DONE>0），避免空板/未配置时误 FAIL；条件不成立记 NOT_APPLICABLE 而非 PASS。
- 每条规则含 `source`（contract / `ep_bar_win.v` 行号 / 指南 §2），供测试者抽验来源一致性。

## 3. 夹具与来源

- 正例分两类：①**真实日志**只读副本（B1 `05-sram-download-runa-retry.txt`；channel 用例选中的 B1 会话日志副本 `b1-real-channel.log`，两份 SHA 与源一致）；②**合成寄存器快照**（B1 为 blocked、B2 未执行，本轮不存在真实寄存器 dump，合成是唯一可行的正例形态）。
- 合成正例数值按规则构造（如 len=0x279000、base=0x10000/0x289000、PUSH_STATUS=0x1E），与真实硬件是否一致不得被引用；测试者也应按“合成”标注检查。
- 负例 6 个：magic/len/保留位/非法行/缺读数/空输入，覆盖 exit 1 与 exit 2 两类 fail-closed。

## 4. 复算与复用工具

- 文件级 CRC/长度复算用 `r10f_strict.py check`；`gen_crc32_flat.py` 是 Verilog CRC 函数生成/自检工具，**不是**文件 CRC 计算器，README 已写明。
- `r10f_strict.py --json-out` 生成的 JSON 中 `file` 字段若含 Windows 反斜杠路径，PowerShell 5.1 `ConvertFrom-Json` 会报“无法识别的转义序列”；改用 Python 逐字段比对（sha256/size/ok/header_crc_calc/payload_crc_calc/marker）。被复用工具只读、未改。
- 项目路径含中文；kit 文件全 ASCII、输出 UTF-8 无 BOM；脚本不写死绝对路径（规则文件默认相对 `__file__`）。

## 5. 待确认/留给后续

- 读通道恢复后：核对 0x120/0x124 的字节序（RTL 拼接为 good[31:24]…crc_err[7:0]）与 0x048/0x080..0x098 旧位图，再决定是否把 raw 快照升级为规则。
- 0x0CC 的 2400 上限是 1080p 假设（几何为占位）；几何变化时需按实际改规则并更新 manifest。
- 0x100/0x104 只解码不判定（未配置=0 合法）；0x0B0..0x0BC 为宿主侧配置回读，不参与自证。

## 6. 预算与过程

- ≈25 次工具调用（冻结 ≤25）；dry-run 首跑因 python 调用缺少脚本路径（`& $py` 后未加 `parse_dump.py`）失败，修正后重跑全部用例；该失败未改任何交付语义，dryrun.log 只保留最终成功轮（含每个用例的期望/实际退出码）。
