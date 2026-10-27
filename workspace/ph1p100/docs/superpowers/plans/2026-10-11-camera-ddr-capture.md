# 相机DDR真实帧CRC接入计划

Spec: docs/superpowers/specs/2026-10-11-camera-ddr-capture-design.md
执行：沿用户已授权的原生持续实施；独立D盘候选隔离，不覆盖工作中的相机/DDR bit。

## Review Focus
- FIFO满后ABORT必须排在旧数据后，并先于下一START；短帧/缺LAST不能发布。
- 同步RAM预取读不可被消费者背压覆盖；Gray同步跨复位应同时归零。
- 图像最后字与CRC元数据不能混淆；源CRC和读回CRC字节序一致。
- ready丢失后不得把残流当新帧；帧切换后读取的ID要等待寄存更新。
- 派生灰度tap必须与原写口同拍同值，保持旧显示时序和像素结果。

### Task1：异步FIFO与不可反压帧打包
- [x] 先写异步时钟/背压/溢出/残帧/复位/字节序TB及stub负对照，运行出现预期失败。
- [x] 实现capture_async_fifo.v、gray_frame_pack.v，运行所有用例通过。
Interfaces：source clk/SOF/8bit valid/LAST → 258bit START/DATA/FOOTER/ABORT；公共异步复位、各域同步释放；有效数据保持到握手。

### Task2：接三帧后端与整帧CRC读回
- [x] 写行为内存端到端测试，CRC/元数据故障和无功能负对照先失败。
- [x] 实现camera_ddr_capture.v与ddr_capture_check.v，完整小帧/生产帧尺寸逐字节回归通过。
Interfaces：Task1 token→frame_begin/data/LAST/abort；store FRAME_WORDS=payload/32+1；checker使用store switch/request/return与read_frame_id，输出通过/错误计数。

### Task3：独立板级候选
- [x] 创建派生camera core/preview tap及板级顶层，不修改原活动工程；测试旁接与旧写口一致。
- [x] 合并已验证DDR初始化/MCU和相机/HDMI依赖，核查引脚、ROM、时钟/Gray约束；TD最终STA与资源合格才bitgen。
- [x] 独立审查、源码/输入/报告哈希、D盘同步和单页上板步骤。
GitHub封存：本地验收后提交/推送，实际提交号以本轮最终回复与Git历史为准。

## 执行记录
Ruling: 当前先验证相机→DDR真实帧CRC，保留ERAM显示；成本是本轮仍非DDR显示链路，但可把采集写入与显示欠载分开定位。用户已要求逐步连续推进，不新增同范围审批。


### 迭代记录（本地门槛通过，已获用户画面/LED反馈）
- 打包/异步FIFO：正向5好帧，3次abort；提前SOF丢弃旧残帧及新帧的计数从1改为2，定向断言先失败再通过。CRC常量由Python zlib参考生成。
- 整链路：518400字节生产尺寸，3好帧，检出像素/帧号/长度3类损坏，三个槽均被使用；行为模型不替代DDR控制器/电气仿真。
- 旁接：原217项显示/RAM检查和128显示像素保持，36个灰度写字节、2个LAST、3个SOF检查通过。负对照保留。
- 210222：B字节时钟被裁剪导致分组约束失败，STA拒绝；另发现丢帧计数问题。报告中寄存器实例名字不足以单独证明Gray边界错误，因为两个Q可共享PH1P Slice。
- 211456：删除不存在的B字节钟约束，采用手册文档化的Gray保持/async属性。setup -0.292ns；实际ERAM输出→消费解码→ERAM CE反馈路径成为瓶颈，hold +0.020ns。
- 212835：新增单token寄存缓冲，完整帧回归通过；setup -0.161ns，剩17个DDR域setup端点，hold +0.020ns，period +2.200ns。相机与显示域通过。子进程布线/导出完成，父进程报告未留下；沿导出DB做显式核验，不推断进程退出状态。
- 222813：综合后切换策略触发TD PRJ-8817，综合被标记过期，未完成布线；已改为综合前设置策略。
- 223607：RTL和板级/时钟约束与212835逐字节相同，仅采用官方TimingHigh物理策略，DDR域通过；只剩显示RAM读选择setup -0.010ns，hold +0.020ns，TNS -0.010/0。父进程PRJ-8806，子进程导出最终DB与报告。vendor IP不改、约束不放宽。
- 按route.qor QOR-1301和原生phys_opt帮助做一次ultra后布线优化，另存DB。首次子目录调用因IP相对路径错误中止，改回工程根目录；两次日志均保留。
- 独立代码审查（含寄存缓冲）未发现剩余Critical/Important项；物理Q/LUT/clock/skew、最终STA和上板仍由root及用户分别验收。Capture整链路ready丢失/中途复位当前仅审查；底层store/pack有对应测试，不扩大成整链路全覆盖。

- 223607追加ultra及4轮后布线优化无改善，仍-0.010ns，不bitgen。失败路径为r_sx→地址加法→RAM csb，扇出103；派生preview使用手册文档化dont_touch保留原r_raddr寄存级，不加周期。225520独立候选最终签核通过，保持属性后的217项显示检查及128像素回归已通过。

- 最终225520：setup +0.004ns、hold +0.020ns、TNS均0、period +2.200ns，bit5224033字节。重载95.39%与子进程97.08%仅时间/覆盖率头不同，原因未明确；实际17位r_raddr Q已保留。54个Q驱动、36条同位同步连接、双向4ns skew通过；其中1条单LUT本地复位AND，数值真值表/源位/复位两级来源独立核对，两个网表损坏负对照拒绝。171输入、91官方文件及D盘源码同步通过；已获用户画面及D37闪/D38亮/D39灭/D40亮反馈，HDMI仍ERAM；绿色亮点仍在像素突变区域出现。无持续计数和独立下载日志，下一实施步骤为DDR显示。

### 当前硬件门槛
- [x] 用户画面/LED预期反馈：至少一个真实灰度帧CRC与元数据校验通过。
- [ ] 持续计数、丢帧率及长期稳定性。
- [ ] DDR读出/显示FIFO/垂直消隐换帧；本计划未实现DDR显示消费者。
