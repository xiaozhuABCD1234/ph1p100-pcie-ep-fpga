# 原恢复仿真续接01：修正DUT冻结（2026-10-25）

本run仍3个正式包/上限4、1目标、两级、batch1。`T10.a1-uart-descriptor-fix` 已round0独立综合PASS，实际修复0；报告 `test-reports/T10.a1-uart-descriptor-fix-r0-integrated.md`，manifest SHA256=`fd0cb6e7f920ba136049fdadd395f029bcd9df3d58dc2d14a2312e9a0d3c33e1`。独立验证10类合法队列转换、12原ID多次回绕、queued reset后2新ID、真实UART引脚字节、四帧完整集成、旧DUT两项有效反例，三维及G0/G1 pass。G2 not_run、G3/4/5 N/A；无生产/TD/板操作。T08原PASS保持。

修正index=`T10.a1-uart-descriptor-fix/corrected-dut-index.json`：只变exporter，SHA `0f3ae49ee19cc69348024e4fbe25cd3766dfec2cd8435f34f2b117bf313ba097`，其余7RTL沿原冻结SHA。规划逐项核实并形成 `recovery-dut-binding-resume01.json`；该文件是本次恢复唯一DUT选择，不能从当前活动树/旧P2/r4/原坏exporter取同名文件。

## 原任务与历史账

续真实原开发 `/root/fpga_dev_recovery_221529`，任务仍 `T10.a1-recovery-sim`，不是新第四包。尚无综合测试者，首份正式综合仍round0；实际实现修复0。原blocked、旧manifest-r0/clean失败/计数全部保留：开发21/45calls，compile1，clean真实仿真1，设计载入前失败1，四fault各0；稳定problem `T10.a1-recovery-sim:SCOPE_CLARIFICATION:fixed-r5-descriptor-index`，原规划澄清补充机会1保留，修正输入条件已满足，不再重复询问授权。

此次是changed DUT后的原包续接/首次验收准备，不把依赖包修复算成本包的验收后实际修复，也不清零历史。旧clean前两包不复用PASS；完整case全部重跑。旧descriptor问题已定位/纠正，不为同根因重新消耗搜索/重试循环。

## 允许写域与验证

开发仅 `OUTPUT_DIR/T10.a1-recovery-sim/resume01/**`；旧任务根所有r0产物、原8RTL、已通过fix候选/manifest及规划控制只读。从旧TB/model/checker/runner复制到resume01后再修测试代码，禁止覆盖旧文件。DUT8文件仅从binding引用且全部只读，不改第二个RTL，不引入新硬件/协议/吞吐工作。

继续原四语义步骤，先验完整clean，再四类fault：

- clean W8/H2至少4个不同good帧全部完整正确，用于拒绝原第三描述符故障；再clean W32/H2校准两种中写几何，不替代fault。
- raw-midwrite-reset及encoded-midwrite-reset用W32/H2（RAW80B≥3个256bit字），独立非压缩性种子使压缩流也跨多字。注入必须外部真实AW/W已接受且未完整发布，并记录相应raw/cmp地址握手和状态；不以内部估计时刻或入口计数冒充。缺多字前置条件先修测试图案/参数，不放宽命中断言。
- bad-frame和真实FIFO/slot overflow可W8/H2；无reset故障轮核对计数增量与整帧拒绝，释放后恢复。禁止force计数或drop信号。
- reset独立epoch、不同图案，保留DDR已接受延迟响应/存储，模型不能随DUT reset清队列掩盖旧数据。≤4good输入且≥2正确完整导出、最后good FE后≤1,000,000 clk_a1、严格zlib/四CRC/零旧epoch字节/零重复读/零尾垃圾均维持原门槛；故意删除注入或旧epoch冒充恢复的负对照有效。

G0/G1必须满足，三维检查覆盖真实DUT、测试可复现/握手/CDC和reset结构、文件保护和系统边界；G2=not_run，G3/4/5本仿真N/A。TD/综合/route/bitgen/CWC/download/Flash及生产写回=0。DUT再有实际缺陷或需要第二个RTL改动，保留精确证据交原规划，不自行扩大写域。

## 本次有限预算与冻结

原开发续接每次≤45calls/60分钟；每次全量compile≤2（历史1保留，因此本次后累计≤3），每个冻结case首次+至多1次有新证据纠正。两项clean属于不同几何，不混计/拼PASS；旧clean1保持在历史。读取/搜索实际60s、每编译/单仿真实际300s+TB watchdog；单问题≤3轮有目标新问题搜索，连续2轮无进展、缺工具/权限/额度立即blocked。不能借新输入盲重试旧失败。

全部命令终止、stopped_modifying=true/active_commands=0后冻结 `resume01/manifest-resume01.json`，列8RTL、所有TB/model/checker/fixtures/runner/参数/工具/实际命令/SHA和本次binding及dispatch。明确input_status=changed。实际产物/lessons/预算在resume01内，返回retest完整失败/受影响清单。

主仅此后新派本任务**一个新综合测试者**，≤40calls/45分钟，独占test-reports库，实际重新编译及运行两种clean和全部四fault，另给独立包/源/epoch判据和有效反例，前后hash漂移0。报告 `test-reports/T10.a1-recovery-sim-r0-integrated.md`，绑定本次唯一新manifest；不得以fix包clean或旧两包充恢复证据。正常PASS或blocked均回原规划收束；同任务真实FAIL仅续原开发/该新tester，最多三轮实际修复。
