# T03 字节与责任（round0，离线证据）

采用源及 SHA 见 `r0/source-binding.json`；P2 r0 / P3 r1 的四个 production_inputs 已逐一与原 manifest 匹配。没有读取 T08 实现或活动 P4 RTL。仅引用活动 P4 协议作为缺口文档，不继承其任何构建/板测结论。

```
软件确定性 RAW10 oracle (16x4，80B；非相机输入)
    -> 只读 a1_ref 编码的精确 zlib（flags=3 时70B）
    -> TB 32bit data/keep，显式环境激励
    -> 真实 a1_ddr_slot_store MODE=1
    -> 原生256bit DDR接口 + TB内存模型
    -> 真实store顺序读口 -> rtl-slot-read.bin（70B，0差异）
                       -> 最后一字的26B零（仅证明到96B）

真实store rd_len_bytes=70 -> 真实P2 slot_stream_len
    -> o_stream_len=70；o_frame_bytes=4096；o_cam_sel=0
    -> [missing：板级寄存器/源事件/字地址转换/元数据桥]
    -> 根生产ddr_frame_pusher（仅静态查阅，未实例化）
    -> [missing：真实PCIe发送、接收和ACK]

精确zlib + 显式metadata -> 本包离线replay.py补44B既有A1U1头
    -> reconstructed.a1u1 -> 严格DEFLATE + inverse + 4CRC
    -> proposed-a1u1-dma.bin（离线参考，含头后重新4096对齐）
```

| 项目 | 绑定源与观察 | 当前责任与缺口 |
|---|---|---|
| 槽内字节 | store MODE=1，`wsh/pack_n` 按32bit低地址先；`rd_len_bytes` 只计 keep 对应字节 | 槽只存所输入的精确zlib。本次真实store输出70B开头为`78 9c`，没有`A1U1`头。编码器是软件环境；没有模拟真实传感器或RTL压缩核。 |
| raw/xform/stream CRC、W/H、prep/pred | P2/store/P3均没有完整A1U1元数据集合；P2没有CRC或几何端口 | 上游压缩生产者应提供并锁定这些元数据；从生产者到serializer的硬件传递 **missing**。本包由确定性输入/历史头恢复，并用strict inverse独立校验。没有宣称硬件已经保留这些字段。 |
| camera/slot/epoch/session/capture_seq | P3保存完整身份并全字段release匹配；P2仅有slot_id/stream_len/base_word和host session，`o_cam_sel<=0` | P3到P2/后端的身份承接 **missing**。A1U1头不含camera/session；本包sidecar的camera/session来自显式离线上下文，不能由文件头认证来源。historical-b18的camera=B来自历史候选证据；session=7/epoch=1/slot=0为离线选择。 |
| 44B头 | P2只有描述符端口，无payload或元数据serializer | 硬件补头 **missing**；本轮只有`replay.py`离线补头，不修改外部协议或RK。 |
| 当前DMA长度 | P2 `align_up(slot_stream_len,4096)` | `current-dma.bin`按此长度。`o_stream_len`注释虽提A1U1，实际代码单位是输入zlib字节。 |
| proposed DMA长度 | 离线工具`align_up(44+zlib_bytes,4096)` | 与当前描述符不同的参考布局，**未接PCIe**。mod4096=0或4053..4095时多4096B；4052为不增加的对照。 |
| 尾零 | 真实store本次最后256bit写字的未用字节为0；没有从最后字到DMA页尾的写零/遮罩端口 | 70..95B本次实际观察为0；96..4095B无证明。`current-dma.bin`明确使用离线zero-fill模型。根pusher没有精确stream_len输入，不能据P2注释推断其会产生zlib尾零。 |
| 容量 | P2 desc_ok只检查cap非0，不比较aligned frame；真实日志含cap=1仍ARM/frame=4096 | 最终容量校验由根pusher `arm_reject` 检查`cap_bytes<frame_bytes`，但连接未验证。本包replay严格拒绝容量不足；P2边界行为原样保留，没有在TB代修。 |
| 地址单位 | P2 `slot_base_word`/store原生地址为256bit word；根pusher `ddr_base`及AXI地址为byte | word→byte（×32）、源序号/就绪、槽基址及真实DDR容量映射 **missing**。不能直接将word地址当byte接线。TB使用BASE_WORD=0/显式内存模型，不证明板级地址合法。 |
| ACK/释放 | P2锁完成时held_seq/held_sess，匹配非0session/seq才slot_release；P3另做完整身份release | TB中后端done/held_seq/session是环境激励，48次错误session均不释放、正确ACK均释放。真实后端ACK与P3全身份release桥 **missing**。 |
| 时钟与模型 | 真实P2同步低有效复位，真实store同步低有效复位，TB单100MHz时钟 | 无RTL改动/CDC/约束改动；原生DDR内存与后端状态均为显式环境模型。不能外推时序、吞吐、真实DDR/PCIe或1080p30。 |

根生产后端静态依据：`rtl/ep_side/ddr/ddr_frame_pusher.v` 160/163–165/197行的frame/base/status/capacity接口，397–403行claim字节地址检查，594–604行ARM容量/对齐检查。未编译/运行此后端，不将其静态约束称为本次实测。

四种长度分别为 `raw_bytes`、`zlib_bytes`、`a1u1_bytes=44+zlib_bytes`、`dma_bytes=align(content_bytes,4096)`。本包所有样例均同时给出当前/参考两种DMA长度；不把A1T1编码器测试record当成A1U1。
