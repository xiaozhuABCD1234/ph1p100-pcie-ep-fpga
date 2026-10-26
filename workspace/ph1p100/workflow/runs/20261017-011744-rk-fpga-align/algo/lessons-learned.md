# T09.rk-align-algo — lessons learned（可复用根因/触发/修正/验证入口）

1. **打包方向必须与项目既有 unpack 对齐**：`csi_rx_10bit_unpack_checked.v` 输出
   lane0=[9:0]（首像素在低位）。窗口装配按 MSB-first 假设会**逐样本全错**。
   验证入口：`run_g1.py --case core`（第 1 帧即出现 lane 级 mismatch）。
2. **去马赛克与 Y8 高斯的边界规则不同**：前者"保 CFA 奇偶 clamp"（列 0 的左邻取列 1），
   后者 plain replicate（取中心列）。同一行窗口模块用 `PARITY_CLAMP` 参数区分；
   混用只在边界像素暴露（16x5/20x2 边界用例可捕获）。
3. **同步 RAM 读在"不规则事件"下要持地址**：读取器寄存器随事件前进，事件间读数据会被
   下一次"推测读"覆盖。做法：事件拍发地址、事件间保持（algo_rowwin3 的 cpa/upa 保持）。
   触发条件：帧内 GAP/停顿（连续事件时不暴露）。
4. **共享单流的分发必须"全接收或全停顿"**：`s_valid` 只门控单分支会导致其他消费者丢拍；
   `w_valid || w_abort` 式推入会把 held 标记反复写入 FIFO。做法：全局
   `xfer = valid && (all consumers ready)`，FIFO push = `w_valid && !full`。
5. **FIFO 指针宽度与条目位宽要和 DEPTH/字段严格一致**：AW=4/DEPTH=8 越界读；36bit 条目
   声明 37bit 会把 abort 位零扩展掉（标记变数据）。自检：越界/标记丢失只在特定时序暴露，
   用端口级 trace 定位最快。
6. **仿真容忍、综合不放过的多驱动**：`ab_pend` 在两个 always 驱动 → ModelSim 无警告、
   TD 报 `HDL-8007 constantly driven from multiple places`。教训：**尽早跑 TD 综合**，
   它是免费的 lint。
7. **上电确定态**：直方图 bank 等大 RAM 在仿真里是 X；必须复位后显式清零（HE 的
   ST_CLEAR 入口），否则首帧计数 X 会一路污染 LUT。FPGA 实际上电为 0，但仿真与
   X 传播验证必须显式建模。
8. **TB/向量侧**：cfg 握手要在断言 valid **之前**确认 ready（否则 latch 已发生而 ready
   已拉低）；跨几何组的 DRAIN 屏障要在复位前把上一组输出全部消费；检查器段指针在
   段关闭时归零；`12'd4096` 会 12bit 截断为 0（高度上界判断写成 2048 才正确）。
9. **负对照要选能区分行为的图案**：常量帧下 HE 的 den=0→恒等 LUT，会**掩盖**同 bin 丢计数
   缺陷；需"长同值 runs + 后续帧"才能暴露。`run_g1.py` 的 he_samebin 变异即按此设计。
10. **中文路径**：ModelSim/TD 都需要临时 subst（脚本 finally 撤销）；TD 的 `report_timing`
    在未 import netlist 时会报 `USR-8001 Cannot find top model`——那是报告命令的已知现象，
    不是流程失败，判定读 run 目录内 TD 自己生成的时间报告。
11. **帧中止标记（abort marker）必须与状态无关地向下游转发**：分支若只在 ACTIVE 才产生
    `prod_abort`，则"前帧已正常结束、本帧在首个输出行前就被中止"时标记在 IDLE 被静默丢弃，
    下游检查器停在 prefix 段并把下一帧数据当本帧消费（现象：branch1/2 逐样本错、branch0 正确）。
    修正：`marker_evt = accept && s_abort` 恒产生输出标记；`abort_evt`（状态复位/计数）才状态门控。
12. **标记条目必须携带"干净"的 sideband**：中止标记若沿用上一生产拍的 stale `sof/eol/eof`，
    下游会把它当帧重启（`abort_restart`），产生**第二个**伪标记。修正：标记拍把
    `p_sof/p_eol/p_eof` 显式清 0（demosaic/Gaussian/HE 三处）。
13. **TB 的 `reg x = 0;` 与 `always @*` 组合驱动是竞态**：初始化值在 time 0 可能后于 always
    的首次求值，而块只在 `stall_cnt` 变化时重触发 → `m_ready` 永远卡 0 → 驱动侧
    `while (!s_ready)` 死等（gray 模块 TB 首向量超时根因）。做法：初始化值与 always 首值一致。
14. **检查器采样沿必须与被测采样沿一致**：TB 在 negedge 比较、DUT 在 posedge 消费，
    驱动在同一 negedge 更新 ready 时，检查器读到更新前的 ready → 少计一拍、数据全错位
    （gauss 模块 TB 的"整体移一位"现象）。做法：模块级 TB 检查器统一 posedge 采样。
15. **变异负对照的判定不能用退出码**：TB 以 `$finish` 结束，ModelSim 退出码恒 0；
    判据应为"无 PASS 标记 + 出现指定 mismatch + 无仿真错误"。另：变异锚点文本会随 RTL
    修复漂移，锚点必须与当前源码逐字一致（否则 assert 失败、report 缺失）。
16. **Fmax 修复用"有界流水"而非改时钟前提**：HE 的最差路径是 ERAM clk2q → 32bit 减 →
    DSP 乘 → 32bit 加 → rem，以及 4-bank 和 → 32bit 累加 → cdf_min。做法：把 ERAM 输出
    再寄存一级、差值/乘/加各占一拍（相位 0..4）、4-bank 和先寄存（合并顺延一个地址）、
    除法用预移位的 `den_s`（寄存器）替代 `den32 << i_r` 变量移位。功能由 core 全量逐样本
    复验（含 LUT 读回哈希），语义不变。
17. **"每拍刷新"的判定位在状态时长变化时会自毁**：`if (en) good_d <= good_evt;` 让
    good_d 只在 eof 拍为 1、其余拍被清 0；ST_FW 从 1 拍改成 2 拍后，决策发生在第二拍，
    读到的是已被清 0 的 good_d → 所有好帧都走 CLEAR、LUT 永不生成（现象：LUT 回读全 X、
    分支输出恒等）。做法：帧末判定只在 eof/abort 拍**锁存一次**（`good_d <= good_evt`
    放在 eof 分支内）。教训：把"事件锁存"写成"电平刷新"是隐藏的时序耦合。
18. **TB 的期望队列/环形缓冲索引必须回绕**：`eq_w = eq_w + 1` 不取模会让写入越过数组
    上界（X）——现象是"exp 全 X"而 RTL 输出正确。做法：`(eq_w + 1) & (DEPTH-1)`；
    同时检查器的采样沿与 DUT 一致（见第 14 条）。
19. **同一状态机的多周期化要重新审视其"旁路"寄存器**：HE 直方图写数据寄存后，RAM 读
    会漏掉最近两拍写（原来只漏一拍），bypass 必须相应改为"两拍同 bin 补偿"
    （`base + 1 + [bin(c-1)==bin(c)] + [bin(c-2)==bin(c)]`）；只改流水不改补偿会静默丢计数。
