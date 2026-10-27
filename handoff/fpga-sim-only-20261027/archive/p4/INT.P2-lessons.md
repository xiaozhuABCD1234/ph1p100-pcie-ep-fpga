# INT.P2 Lessons

- A+ 压缩路径 (A1U1) 与 RAW 非压缩路径 (R10F) 必须分离；R10F 解析器假设不适用于压缩。
- PCIe pusher DDR 源要求 frame_bytes 4 KiB 对齐；压缩帧尾部零填充，RK 严格解析拒绝非零尾部。
- 描述符/长度/尾拍/完成/释放贯通通过 adapter 状态机实现；held 状态需 host ACK (session,seq) 匹配才 release。
- RK 真实 PCIe 传输尚未联调，标待联调；文件回放/接口仿真不等于真实 PCIe 通过。
