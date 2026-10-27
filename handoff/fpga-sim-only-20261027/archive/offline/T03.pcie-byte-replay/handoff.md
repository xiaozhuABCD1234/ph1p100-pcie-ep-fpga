# T03 round0 测试入口与短步骤

唯一冻结入口为本目录 `manifest-r0.json`；先核对其每个sha256。详细本地证据在 `result-r0.md`，接口缺口在 `byte-responsibility.md`。测试不得原地重跑而改写冻结的r0/work或日志。

只读检查单个样例（PowerShell）：

```powershell
& 'C:/Program Files/Python311/python.exe' 'D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/T03.pcie-byte-replay/replay.py' verify --case 'D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/T03.pcie-byte-replay/r0/synthetic-flags3' --camera 0 --session 7 --capacity 8192
```

同命令换historical-b18并用camera=1/capacity=4194304可查历史控制。将camera改为1（synthetic样例）应退出1。四个样例都有 `current-slot.bin`、`current-dma.bin`、`reconstructed.a1u1`、`replay-metadata.json`，另交 `proposed-a1u1-dma.bin` 与 `expected.raw10`。current DMA尾填充为离线假设；proposed文件含头后重新对齐，仅参考布局。metadata不扩充A1U1线上字段。

重建入口：`replay.py reconstruct --slot <exact-zlib> --metadata <对应的*-input-metadata.json> --case <新目录> --camera <0或1> --session 7 --capacity <足够容纳含头后对齐的长度>`。输出新目录必须不存在。每次执行给实际300s subprocess timeout；依赖仅Python标准库与绑定只读reference。

独立测试者建议入口（写入自己的test-reports/T03.pcie-byte-replay子目录）：

1. 解析既有44B结构，独立重算四CRC与长度；再用历史strict decoder或另写逆变换逐byte比较expected.raw10。b18是UART历史传输控制，sensor_pixel_oracle_verified=false/phase unknown，不能用于证明真实传感器像素正确。
2. 以本包绝对runner路径运行 `prepare --out <测试者新目录>`、`rtl --out <该目录>`、`check --out <该目录>`。runner仅允许本包或本任务test-reports作用域；prepare拒绝已存在目录，所有ModelSim库/ini/log都在新目录。rtl每个子命令有300s真实timeout，最多1次编译/1次有效仿真；检查生成进程外层也应设置300s timeout。源码映射由runner重建为实际checkout路径。
3. `r0/rtl-slot-read.bin` 是真实store输出；本包`reconstructed.a1u1`是离线工具输出，两者不可混称DUT带头输出。验证描述符夹具4052/4053..4096与b18长度，并注意cap=1的P2原始行为。
4. 独立变异一个头字段/CRC、额外zlib、尾零或sidecar上下文，观察非0退出或明确reject；可改变TB长度/相位生成独立证据，但不要修改冻结文件。
5. 再核对manifest/hash无漂移。三维functional/engineering/system和G0/G1/G5分别判断；G2/G3/G4按本轮计划边界记未运行。

`runner.py check` 通过API检查四个正向与17个负向；不是17个独立设备/仿真进程。历史decoder/编码参考从绑定的handoff包只读导入；不会写pycache。`prepare`创建的b18样例保留源SHA/标记，三份小图均为synthetic_control。实际RAW10样例80B可直接审查像素公式，未取用T08或新实拍数据。

外部后续：板级44B serializer、CRC/几何/身份桥、word→byte地址映射、全DMA尾零、最终容量和真实PCIe/ACK仍需原集成线接入。本包未尝试这些动作。父T03/T11不能据本包测试改为done。
