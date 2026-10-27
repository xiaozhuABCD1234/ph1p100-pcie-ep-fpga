# 本轮工具/硬件接入事实

实际命令：PowerShell evidence/inventory.ps1，在本项目工作目录执行；退出0。读取新TD绝对二进制SHA，临时新建U:→本run/evidence/td-probe，运行 ./probe.tcl，仅查询命令注册。stdout.log横幅实查TD Release_2026.2 / build6.2.3.210850、Tcl8.6.17，11项命令REGISTERED，READ_ONLY_CLI_PROBE_OK，非空日志。U:映射在finally撤销，原subst为空。没有工程构建/IP生成/位流下载。IpTool.exe SHA=5b0654aaa44ae9340eefcdc8cac54faed7490b0643f3fa53908c5706db175cec；本轮查二进制，未重做旧DDR1333试验。

可复用既有成功：docs/evidence/td2026_ipgen_20261016.json step1_smoke_simple_ip（APB_GPIO smoke）记录IPT-1001 target generated successfully，以及同文件6.2.3 scratch端到端回归。这里仅引用其工具入口证明，非本轮重跑；旧DDR1333 staging失败只属于DDR1333具体配置，不宣称CLI/IP Tool普遍不可用。用户本轮说明已可CLI IP Tool优先保留。详见本包evidence/tool-success-reuse.json的精简摘录与源文件SHA，未发送凭据/环境内容给worker。

只读设备查询：Win32_PnPEntity筛选FPGA相关USB，发现USB Serial Converter A/B及USB Composite Device，VID0403/PID6042，均StatusOK/error0。尚未执行JTAG链扫描，不能仅凭枚举确定PH1P100器件/加载通道。Win32_SerialPort仅列COM3/COM4蓝牙链接标准串口；未打开端口、未假定板UART或RK。BW bw.exe/bw_commands_prompt.exe存在并已哈希，可供下包system只读查询后选用。没有访问任何RK主机、SSH/安装/重启或认定IP。

G2/G3/G4/G5在本备份合同包不适用，实际板验not_run。下一硬件包所需：实际链上器件和可用BW读写入口、system独占窗口/电源状态、同候选最终G2、唯一bit及匹配CWC（若含）、回退002820身份。RK实收还缺实际通道/BDF/内核/driver/MPS/IOMMU/PAGE_SIZE；缺失不阻塞离线后端包，但不能宣称DMA实收。

实际编译器：Python3.11.5、GCC13.2.0版本查询退出0。RTL仿真器：iverilog/vvp未发现；Verilator脚本存在，但原生bin版本查询返回-1073741511，Perl/MSYS入口返回127，未确认工作入口。本包不需要RTL仿真，不以文件存在报可用；下包需先补齐该条件。
