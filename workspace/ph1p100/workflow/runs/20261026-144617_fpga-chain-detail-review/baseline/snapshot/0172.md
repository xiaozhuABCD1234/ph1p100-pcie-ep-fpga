# T08 生产 RAW 顶层同步集成仿真覆盖层

本目录是隔离仿真候选。DUT 为冻结生产 `ph1p_pcie_ep_top` 的派生覆盖层，真实 checked CSI、解包、两路 `cam_r10f_writer`、DDR 写仲裁、sync_start_ctrl/reset/SOF mailbox/pairer 和真实 `ui_i2c` 均保留。生产树、板上候选和旧 run 未写入；未调用 TD、硬件、盘符映射或删除。

## 实现与接口

新增顶层 `SYNC_ENABLE=0`、`sync_start`、`sync_abort`；关闭模式保留原配置主体（`static-audit.json` 给出精确主体比较）。几何和等待只参数化，默认仍为 W1920/H1080/X960/Y540/SKIP37、WAIT1200000。仿真使用 W8/H2/X0/Y0/SKIP0、I2C_DIV14、WAIT120、FRAME_TIMEOUT30000、PAIR_WINDOW64、I2C_TIMEOUT5000、上电32拍。控制50MHz、A包层约71.43MHz、B包层约55.56MHz、DDR模型125MHz，时钟相位不同。

`ui_cfg_imx415` 新增启用分支，`sync_i2c_config` 独占每路真实 ui_i2c；完整发送201项原寄存器表，初始化时仅覆盖3000/3002=01、30C1=0F以保持standby/stop/Hi-Z。最后一笔真实 busy 结束且所有ACK正确后才置 cfg_done，不执行自动/周期启动。同步事务仅在 valid&&ready 接收，锁存四字节，等待 busy 上升后撤请求，记录任意字节NACK，busy结束时唯一回应。全局reset撤销状态；原同步超时poison/reset逻辑未改动。

`sync_frame_gate` 对 permit 异步撤销、在各字节域两级同步释放，仅在后续真实SOF开始放行；撤销开放帧时把EOF/abort交给真实writer。有效permit同时要求控制ready和pair锁定，已ready时缺路导致清理并重新warmup。SOF测量来自门控前的真实checked接收输出。

RAW10每行10B、每帧20B，R10F头128B，DMA4096B；地址单位为字节。A双缓冲00100000/00900000，B为01100000/01900000。生产默认payload2592000B、头128B、DMA2592768B。每帧原CRC算法和头格式未改；独立Python用`zlib.crc32`重建完整头、源图案、CRC和零padding。

## 独立复跑

使用 `C:\Program Files\Python311\python.exe -X utf8`，工作区仅读本目录。综合测试者把所有输出放自己的允许写域，不能用开发专用`run_local_suite.py`写回local。

```powershell
python -X utf8 <本目录>/run_t08.py compile --build <测试允许写域>/build
python -X utf8 <本目录>/run_t08.py case --build <测试允许写域>/build --out <测试允许写域>/clean --case 0
python -X utf8 <本目录>/check_t08.py <测试允许写域>/clean --case 0
```

分别运行CASE=1（最后字节NACK及清理后恢复）、2（缺B、A半帧中止后恢复）、3（写入中全局reset后重新完整初始化和warmup）、4（显式停止/重启重新warmup）。每case独立进程、实际300s deadline和仿真cycle/time双watchdog。命令超时仅终止本命令拥有的PID树，不扫描/终止其他进程。

CASE=5额外覆盖I2C已接受、真实busy已上升且尚无响应时reset：旧会话的一笔明确取消，新会话完整重新初始化、warmup并正确发布三对帧。checker显式区分reset取消与遗漏响应，不把取消请求拼到新epoch。

角色写值反例：CASE0额外`--mutate`，使实际同步控制器的一笔30C1写值从0F变0E，真实I2C和数据通路照常运行；随后运行独立`check_t08.py --case 0`必须拒绝，命中`ordered 14 role writes and six cleanup writes`。反例的正常仿真完成不算正例PASS。

## 模型与警告边界

`vendor_env.sv`显式替代三个加密厂商IP：PLL/PCIe提供时钟、链路/总线空闲常量；DDR模型按真实AW/W/B握手存储四个4KiB槽，确定性AW/W背压，检查地址/size/burst/WLAST并保留reset前存储字节、清除自身接口队列。无PCIe主机事务/DDR读功能/物理训练证据。`MIPI_PHY_SIM_STUB`只旁路物理MIPI，对既有包层端口注入；checked判帧/解包未替换。

`sensor_i2c.sv`只观察SCL/SDA并开漏ACK/NACK，无DUT内部表访问；Python从冻结表文本核对初始化，从冻结需求常量核对同步14笔、清理6笔、两次等待和请求/引脚/应答一对一。传感器模型不模拟曝光、电气、MCLK锁定或帧生成寄存器副作用，数据源由TB在包层独立驱动。

编译1条原有RDGN警告为未改动的`pcie_ep_engine.v`冗余数字位数。精化37条告警均为明确省略的端口：TB未使用的物理输出/DDR双向脚，B配置debug输出，B writer的dbg/closedloop输出，以及CLOSEDLOOP_EN=0时未使用的cl_release输入（该输入只出现在常量条件的未选分支）。未出现目标位宽或时钟告警。前两者不消费返回数据；DDR模型通过AXI使用，不需要物理DDR脚。独立测试者应审查这些边界，不应压制或忽略新增告警。

G0/G1供本包独立综合验收；G2=not_run，G3/G4/G5按冻结计划not_applicable。未证明生产迁入、STA/资源/完整CDC、真实曝光同步、板级恢复、长稳或吞吐。回退为保持生产候选原样，保留本目录证据，无删除动作。
