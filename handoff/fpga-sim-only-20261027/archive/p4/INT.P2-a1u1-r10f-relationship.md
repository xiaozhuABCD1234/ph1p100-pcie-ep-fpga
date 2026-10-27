# INT.P2 A1U1 与 R10F 承载关系

## 结论

- **A1U1**：FPGA 压缩帧格式。44 字节头 + zlib 压缩 payload + header CRC / stream CRC。用于 A+ 压缩路径（PCIe 发送后端的 DDR 源，src_sel=0）。
- **R10F**：128 字节非压缩传输参考草案。用于 RAW10 非压缩路径（codec=0），保持已有 RAW 接收入口可用。
- 两者**分离**：R10F 解析器假设（raw_bytes <= payload_bytes、raw CRC 按载荷前缀计算）对压缩不成立，不能只改 codec_id 接通。
- A+ 输出槽接入 PCIe 后端时使用 DDR 源模式（src_sel=0），frame_bytes 为 4 KiB 对齐的传输长度（尾部零填充，RK 严格解析拒绝非零尾部）。

## RAW 接收入口

- RAW 路径（R10F）保持独立，不被本包修改。src_sel=1（ERAM 源）或独立 RAW 入口继续可用。
- 本包仅新增 A+ 压缩路径的描述符/长度/尾拍/完成/释放贯通。

## PCIe 传输约束

- frame_bytes 必须 4 KiB 对齐（pusher arm_reject 检查）。
- 门铃单 DW 4 字节对齐且独占 mailbox 页。
- held 状态需 host ACK (session,seq) 匹配才 release。
- RK 联调尚未进行，真实 PCIe 传输标待联调（不能将文件回放/接口仿真写成真实 PCIe 通过）。
