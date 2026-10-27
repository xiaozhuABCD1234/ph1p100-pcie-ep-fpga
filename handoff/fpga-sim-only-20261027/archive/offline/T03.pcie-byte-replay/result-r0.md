# T03.pcie-byte-replay round0 开发本地检查

状态：待独立综合测试，非整机验收。实际根 `D:/fpga/repos/ph1p100-pcie-ep-fpga`。只在本包写入；根生产和旧run均只读。唯一候选入口 `manifest-r0.json`。

本轮完成计划的五步：源绑定/责任图、真实P2+store TB、离线补头/四文件与sidecar、正负向/对齐边界检查、日志与冻结。详细责任和未实现硬件见 `byte-responsibility.md`。

本地实际结果：

- 固定P2 r0/P3 r1的四份生产输入SHA与历史manifest逐一匹配；参与本次编译的真实DUT为P2和a1_ddr_slot_store，另加本包TB，未替换为stub。
- ModelSim 10.5b编译1次，0 errors / 0 warnings；仿真进程2次（首次未加载设计，修正Windows参数路径后第二次执行）。有效仿真5630ns；1次store发布，70B zlib逐byte差异0，实际最后DDR字26B为0。
- 真实P2输出48条描述符。45个长度夹具覆盖4052..4096；其中44种（mod=0或4053..4095）按44B头参考布局多一页。夹具只有长度，不是假造压缩输出。
- P2在cap=1、stream=4096仍ARM的原始行为已记录；这是后端容量责任缺口，replay软件会拒绝容量不足，未修改P2绕过事实。
- 4个正向控制：16x4 packed RAW10三种合法flags=0/1/3，以及历史真实b18。四CRC、严格zlib EOF/无额外数据、逆变换和逐byte对照均通过；历史A1U1重建与原文件完全相同。
- 17个负向均明确reject：四CRC各自变异、版本、保留位、raw/xform长度、头/流截断、重封装后的zlib截断、extra zlib、错camera/session、容量不足、两种DMA非零尾。
- 旧基础decoder API可消费四个参考DMA文件；历史strict decoder API可消费四个精确A1U1文件。基础decoder仅兼容检查，四CRC与严格流终止由本包和历史strict decoder共同检查。

证据：`r0/compile.log`、`r0/simulation.log`（失败原始日志）、`r0/simulation-retry.log`、`r0/p2-descriptors.jsonl`、`r0/rtl-results.json`、`r0/positive-results.json`、`r0/negative-results.json`、`r0/commands.jsonl`、`execution.jsonl`、`prepare.log`、`check.log`、`check-final.log`。局部编译/仿真/回放命令均记录实际argv/cwd/rc/deadline；检查和生成子进程300s，ModelSim单命令300s、vlib60s，未超时。首次vsim rc=12，根因是ModelSim将反斜杠路径加花括号后无法打开modelsim.ini；只改本包runner将Path转成正斜杠，保留失败日志，仅重试仿真一次。早期只读命令曾遇到控制台GBK编码错误，后续统一UTF-8；没有因此改动任何输入。

冻结范围：本包所有非manifest文件以及source-binding列出的只读输入、工具版本和参数均绑定。仿真使用flags=3/W16/H4/80B RAW、70B zlib、store MODE=1/SLOT_WORDS=128/AWB=8/BASE_WORD=0；P2 SLOT_BYTES=3000000/ALIGN_BYTES=4096/session=7。内存模型不是DDR IP；后端busy/done/ACK是TB环境，不代表真实pusher或PCIe。

本地G层：G0接口/单位和绑定、G1真实小参数RTL与软件正负向、G5可复现/证据诚实已检查，正式判定留独立测试者。G2本轮TB/软件新增范围未运行；G3/G4 not_run/awaiting_hardware。TD/综合/布局布线/bit/CWC/下载/COM/JTAG/Flash/RK/安装/commit/push/外部消息均0。不存在父T03/T11完成或真实PCIe已接的声明。

回退：停止采用本包输出；生产候选从未替换，无需删除。没有使用DeepSeek：本轮的少量确定性字节转换已由短脚本直接完成，额外API往返不节省工作；没有派生代理。

执行控制备注：最初两次只读入口读取未加独立硬deadline；此后读取/搜索均使用60s自身watchdog或subprocess timeout。初期一次GBK读取失败的自有会话已自然结束并回收，未杀任何外来进程。该偏差保留供工程维度判断，不影响已保存的RTL/回放命令deadline证据。
