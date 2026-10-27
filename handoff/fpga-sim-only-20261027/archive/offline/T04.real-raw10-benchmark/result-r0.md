# T04 r0：blocked（真实输入缺失；工具准备已交付）

task_id=T04.real-raw10-benchmark；实际根为 D:/fpga/repos/ph1p100-pcie-ep-fpga；派发绑定本run的 dispatch-t04-ready.json。只写本包；停止修改后冻结 manifest-r0.json，测试命令均已退出。未修改生产RTL/tools/constraints/al_ip/workspace/handoff、旧活动run、RK或run控制文件；未使用TD、硬件、安装、图集下载、COM/JTAG/Flash、commit/push或外部消息。

`benchmark_result=blocked`、`real_sample_count=0`、`qualified_real_count=0`、`ratio=null`、`real_summary=null`。缺少合格实拍RAW10和逐样本独立像素正确性证据。不存在真实收益PASS；没有申请真实收益综合测试。本包仅完成输入门、软件工具、合成正反向控制和准确缺项清单。

## 有限inventory与来源门

只枚举input-index中交接包根、其samples和根tools/codec的直接文件，并绑定19项真实采用的规则/派发/模型/历史证据SHA；没有全盘扫描或联网取图。b18来源是历史真实FPGA UART抓取，但其expected明确sensor_pixel_oracle_verified=false、phase unknown，540 stored块不能证明源像素正确。作为历史来源登记、排除real-summary；本轮未重跑其解码。N/L、CONTENT=2和所有生成控制均不作实拍。准确表在inputs/inventory.json，源绑定在inputs/source-binding.json。

## 软件与统计口径

输入schema支持packed RAW10、显式大小端/移位的u16，严格W/H/stride/ROI/10bit范围/原始与规范化SHA；未知相位仅00。真实类别需来源/设备/采集/格式/许可和独立像素正确性证据及其绑定SHA；代码检查声明一致性，真实性仍由原规划/独立测试复核。

只读根tools/codec/a1_ref.py的encode_frame stream/stats，未把A1T1 record当A1U1。严格DEFLATE使用根a1_inflate_strict加Python zlib交叉校验，独立flat-index scatter逆变换不调用a1_ref.inverse_frame。A1U1四CRC与几何/长度核验，逐byte等输入。每帧CSV/JSON包括raw/zlib/A1U1/dma长度、44B头/对齐开销、三种raw/bytes比率、stored_blocks/block_count和stored_raw_bytes/raw_bytes两个回退比例。汇总总字节比，每次只有一个明确模式；dma是align(44+zlib,4096)离线参考布局，不是当前硬件描述符。

## 实际本地检查

Python版本与可执行路径见inputs/runtime.json。每个命令的cwd、rc、标记和日志见execution-r0.json；局部脚本实际WaitForExit deadline=300s，后续读搜job deadline=60s，仅有权终止自身进程。共6个Python runner进程（含最初RED和最终freezer），没有超时。

初始RED rc=1（尚无benchmark模块）；实现后工具控制rc=0，最终脚本以新输出名重跑rc=0、`TOOL_CONTROLS_PASS checks=39`。39项包括已知MIPI字节组、packed与u16 LE/BE+shift6相等、00/10/11、奇数尾行、fixed/stored、严格解码CRC/截断/extra zlib、缺字段/坏SHA/几何/ROI/范围/位padding/错字节序、未知相位拒绝、合成重标签拒绝、历史分类排除、零真实summary。historical分类控制使用生成payload，只检验分类，不冒充b18复测。

真实空输入CLI已实际运行：`python.exe -B benchmark.py --config inputs/real-inputs.json --output local/real-benchmark`，rc=3，输出blocked/0/null。该返回码是预期缺输入，不是通过。合成对照结果位于local/controls-final-result.json与local/controls-final各模式结果，真实空CSV仅表头。无需安装第三方依赖。

G0/G1/G5只在软件工具准备范围有本地证据，真实收益所需G1/G5为blocked；没有独立综合验收判定。G2纯软件不适用；G3/G4 not_run（无硬件授权，不升级父任务）。没有测真实图像收益、真实PCIe、RTL资源/STA/CDC/吞吐或H/AH收益。

## 恢复与回退

blocked-r0.json给出稳定problem_id和最小缺项。准确恢复入口README.md、inputs/input-schema.json及当前派发；原规划提供至少一幅的准确原始路径、格式/来源与独立像素正确性证据。一幅只报告单样本，至少三幅不同内容才形成有限图集。新配置/新结果目录由原规划授权后续此角色；不修改r0冻结件，不空转取图，不自行申请真实收益PASS。原规划可另决定有限工具核验。

回退是停止引用本新离线包；没有生产修改需要回滚。所有失败RED与成功工具日志均保留。主只传输本报告路径和blocked元数据。
