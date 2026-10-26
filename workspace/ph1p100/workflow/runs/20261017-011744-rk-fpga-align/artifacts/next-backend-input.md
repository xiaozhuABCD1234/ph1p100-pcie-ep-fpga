# T07.rk-align-backend的固定输入

本文件仅提供下一包输入，不在本包执行。允许新目录由规划dev-plan/dispatch重新确定；旧源码、D盘工程和peer参考均只读。以references/provenance.json的168个FPGA文件与24个driver文件为准，匹配生成IP不可从别的PCIe版本拼接。

模块/IP/约束入口：peer `create_project.tcl`逐条add_files包含EP top/engine/int_handle、img BAR/regs/frame_src、cam前端、ddr_frame_pusher/cam_ddr_writer/ddr_wr_arb、uart/ubus、constraints .adc/.sdc和al_ip下pcie_ep_core、pcie_pll_ep、ram、ddr3_mc_0四个xml及全量引用内容。具体清单见`artifacts/backend-input-files.json`（仅静态解析，未运行peer脚本）。DDR当前参数DDR3-800E、PH1P_REF_CLK50、AXI地址29位/数据256位、PAXI0；实际板内DDR容量必须从匹配IP配置/器件证据确定，不以29位总线宽当容量授权。独立candidate使用这个后端，不把旧PAXI接口套上AXI。

本方checked接入不能只复制文件：保持peer PHY/byte align/word align/gearbox，输出I_clock/I_reset_n/I_enable/I_data[31:0]/I_data_valid连到csi_rx_packet_integrity，正确设置VC/RAW10 DT/实际WC与行数。其O_payload_out[31:0]/O_payload_keep[3:0]/O_payload_valid及O_in_line送csi_rx_10bit_unpack_checked，I_clock/I_reset_n/I_enable在同域；O_data_out[39:0]四个10bit样本和O_dout_valid送新增RAW10 packer/ROI/DDR完整帧控制。O_vsync_out/O_in_frame与O_frame_end/O_frame_good/O_frame_abort、错误计数/last_wc/last_lines必须接入帧裁决及诊断。旧csi_rx_packet_handler_checked只做头/WC包装而没有CRC整帧good/abort端口，不能将其单独接上就声称完整性合格。三个本方文件冻结于references/local-inputs；当前f9p_camera_capture_core cap_data是预览字节，不能作为RAW10正式源。

像素为speculative直到selected FE且完整WC/行数/CRC/ECC/超时通过；延迟后的4px valid与SOF/EOL/EOF裁决要逐拍配齐，尾组在unpacker流水排尽后才能确认complete。CSI不可反压，FIFO满/abort拒整帧而不是发布残片。source ownership为writing→complete→held_for_tx→released；两路每次各自缓冲持有，不依赖peer固定双缓冲轮换窗口。source descriptor（camera/session/seq/base/dma_bytes/CRC）必须原子跨域并锁存。Gray8 peer W*H不能代替RAW10 packed。

后端必修的已知风险与源码：pusher `references/peer-fpga-2a4b253/rtl/ep_side/ddr/ddr_frame_pusher.v:648`的超时只标flush，必须审查开放TLP期间持续stall与CPL仲裁（帧长timeout不能截半包）；`references/peer-fpga-2a4b253/rtl/ep_side/ddr/ddr_frame_pusher.v:483`持续新seq启动未有容量/ACK授权；`references/peer-fpga-2a4b253/rtl/ep_side/ddr/ddr_frame_pusher.v:681`已有dst64/doorbell锁存应保留并补齐授权/会话/cap/长度/源base；`references/peer-fpga-2a4b253/rtl/ep_side/ddr/ddr_frame_pusher.v:834`会截高位，必须先拒绝非法高位及溢出；`references/peer-fpga-2a4b253/rtl/ep_side/ddr/ddr_frame_pusher.v:780`source FIFO排空必须有源故障/取消恢复边界，不允许旧会话响应污染下一次。4DW地址高32为0时的格式选择与RC/MPS需按规范处理，不能把peer注释当可发布资格；DW-valid=F0头、FF数据、F8单DW门铃，绝不是byte keep，字节序与BE由TLP oracle独立核对。

registers.json提出0x100..11C容量/session/one-shot/ACK扩展，当前NOT IMPLEMENTED。原0xD0..F4已有诊断，不能占用冲突。下一包须同步扩展BAR及RK匹配补丁，默认cap/session/armed=0，旧驱动0x71和原+16必须负例失败。CPU已分配DMA地址/大小、source DDR容量、门铃边界、MPS128与4KiB都检查。模式CTRL=0x61不能隐式授予持续DMA。

构建：使用D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe，版本实查6.2.3.210850/Tcl8.6.17。peer create_project.tcl会直接reset/launch，因此只作审查输入；在新candidate复制且改为明确分阶段脚本后才运行，禁止执行download_sram.tcl。TD cwd/./正斜杠为约定。中文长路径用未占用subst盘符映射本run/candidate，记录目标、命令与撤销；实际所有写入仍在项目。只用新映射，不触D盘旧工程。G2最终setup>=0/hold>=0/TNS0、约束/CDC/资源/引脚/IP及同DB报告bit哈希齐备后，另包system独占SRAM板测。

peer TB参考调用（本包未跑）：在隔离副本sim_do目录按include路径修正调用iverilog -g2012 -o <本包输出>/pusher.vvp tb_ddr_frame_pusher.v ../rtl/ep_side/ddr/ddr_frame_pusher.v，再vvp并要求ALL PASS；writer/arb/BAR测试台同理。peer TB头部声称只写不跑不能当已验证；它的旧+16/小几何/无ACK覆盖要新增负例和实际128B/完整1080p边界。当前PATH未发现iverilog/vvp，verilator脚本与gcc存在，工具实启结果见tool-inventory：原生Verilator返回-1073741511，Perl/MSYS脚本入口127，未确认可用仿真器；工具缺口应交规划补条件而非绕过验证。并列使用本方parallel/pcie的PCIT/TLP oracle（下一包按依赖精确列入manifest）。

硬件：只枚举发现FTDI VID0403/PID6042双通道，尚未JTAG扫描确认器件；COM3/4为蓝牙，不能当板UART/RK。BW CLI存在但未执行加载；无RK地址/BDF/控制通道。system后续先识别连接/回退bit/独占窗口，再同候选G2与唯一bit执行已授权SRAM；Flash、未知远程主机操作不授权。
