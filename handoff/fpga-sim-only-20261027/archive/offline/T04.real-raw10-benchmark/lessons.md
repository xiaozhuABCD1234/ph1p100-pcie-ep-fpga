# T04 r0 lessons

- 触发：本地唯一明确的真实来源是b18 A1U1历史抓取，expected.json 明示sensor_pixel_oracle_verified=false。根因：传输可复现性与传感器像素正确性是不同证据。处理：有限inventory拒其进入real-summary，空集ratio=null、benchmark_result=blocked；复核入口inputs/inventory.json和local/real-benchmark/benchmark.json。
- 触发：u16大小端或高位容器直接当packed输入。处理：显式byte_order/valid_bits/right_shift，检查移位丢弃位全0和0..1023，核对独立规范化SHA；验证入口verify_controls.py的LE/BE/shift6和range/padding/wrong-endian负对照。
- 触发：未知Bayer相位仍启用phase0收益。处理：未知或非RGGB只允许00，RGGB模式必须有相位来源；odd-tail下独立flat-index逆变换覆盖10/11，避免调用编码器inverse自证。
- 触发：A1T1测试record或当前zlib槽长度被当成A1U1/DMA长度。处理：只取根encode_frame的stream/stats，按既有44B组装A1U1；dma统计明确是align(44+zlib,4096)离线布局。严格parser核对stored字节，两个回退比例分别统计，不混成一个值。
- 触发：重跑脚本覆盖冻结输出。处理：每次指定新的controls目录名，benchmark输出目录必须不存在；参考模块禁写pycache。恢复从README/schema新建r1输入，保留r0不动。
- 本次只有软件工具正反向39检查通过；没有真实收益、RTL吞吐、H-only/A+H或板级通过结论。DeepSeek只给低风险检查建议，最终实现和验证由Codex完成。
