# DDR显示闭环实施计划

Spec: ../specs/2026-10-12-ddr-display-design.md
执行方式：用户已授权连续原生实施；保存设计和计划后按步骤执行，工程隔离且保留已验收bit。

## Review Focus
- 新请求到来时旧DDR响应或FIFO残流不得混入新帧；由欠载恢复与换帧测试覆盖。
- 元数据不能显示成像素；2×2逐像素期望值由独立公式生成。
- START迟到不能从屏幕中间开始；用阻塞读响应覆盖。
- 无新相机帧时重复读槽，不能释放仍被显示的槽；重复/新帧测试覆盖。
- CRC只累计首次源行且涵盖全部字节；footer及数据损坏测试覆盖。

### Task 1: 消费链及真实存储集成
Files: src/mem/ddr_display_read.v, gray_display_pixels.v, camera_ddr_display.v; tb/tb_ddr_display.sv; tools/td/run_ddr_display.py。
Interfaces: DDR原生PAXI沿用后端；pixel端pclk/VS/HS/DE→注册RGB/VS/HS/DE；请求toggle/ACK，258bit token→显示FIFO。
- [x] 写独立PAXI模型/逐像素缩放期望、重复帧/换帧/欠载恢复/元数据损坏测试与零功能stub；运行预期失败。
- [x] 实现读消费者、显示FIFO/像素取数及复用capture/store的封装；全用例通过。
- [x] 生产960×540至少一完整帧与复位/ready丢失覆盖；记录日志和未覆盖项。

### Task 2: 独立板级工程
Files: tools/td/prepare_camera_ddr_display.py; 派生camera core和DDR wrapper；独立prj/camera_ddr_display_*。
- [x] 派生核心导出像素时钟/时序，以DDR RGB和同拍控制送HDMI；原ERAM读图未被选中应由综合裁剪。
- [x] 两个FIFO CDC约束、相机/DDR固定依赖及输入哈希核对；TD构建并修复实际问题。
- [x] 最终STA/skew/物理同步边界/资源核验后才bitgen；不放宽约束掩盖违例。

### Task 3: GitHub说明与用户验收
- [x] 完备README与架构/模块/命令/结果/边界/回退说明，清晰区分旧已测与新候选。
- [x] 同步D盘与仓库选定源码，归档仿真/报告/输入索引，审查并提交推送核对远端HEAD。
- [x] 输出唯一候选的SRAM操作与预期；用户验收前不称硬件闭环成功。

## 执行记录
Ruling: 按行重复读取降低首版控制复杂度，代价为显示读带宽翻倍；若实际欠载再以实测决定两行缓存/突发优化，不提前改接口。


1. 已完成stub RED、初版实现GREEN；进一步注入footer/DATA错误RLAST后真实RED，修复取消读所有权不产生rd_valid的等待死锁。最终小尺寸65536 DE周期、生产2073600像素通过；故障用例仅小尺寸，生产用例紧凑消隐。pack/tap/store回归通过。
2. 首轮002904（修复前）布线setup0.000/hold0.020，保留诊断；修复后003550 setup+0.049/hold+0.020/TNS0，四组skew通过，ERAM55，输入177/厂商91核对。
3. 原生审查两FIFO108 Q驱动/72同位链接，72所选同步FF数值AND函数；三域两级复位及请求/ACK注册源另留网表摘录。错误源位/函数副本负对照均拒绝。TD重载覆盖95.70%与子报告97.32%只头部差异，原因未解释。
4. 最终bit5224033字节，SHA256 000ffd6436ad04a1b595f8fd345215531af4c63bb156ba0c0d7b50e585d30f07；未下载。已同步新增D盘源码；无删除/自动烧录。独立只读复核确认RLAST Important和迟到START Minor均已解决，审核者未独立重跑。
5. GitHub首页补齐模块/数据流/复现/回退/证据边界；用户确认后续继续此风格。唯一候选上板步骤另文，证据索引docs/evidence/camera_ddr_display_20261012.json。

- [ ] 用户完成003550 SRAM下载并反馈动态真实图像、D37–D40及约1分钟黑帧/冻结/错位观察。此项未通过前不记硬件闭环完成。
- [ ] 依据显示欠载/CRC持续计数决定是否需行缓存/突发优化；绿色闪点单独定位。

6. 最终验证补强：旧256字节周期图案实际漏检word地址bit4清零；新高位偏移图案在x1024/y0拒绝该错误。仅TB/runner变更，生产RTL与bit不变；小尺寸和生产尺寸重新回归，日志/不可变输入加入证据索引。
