# 原两项仿真目标已完成

日期2026-10-25；run=`20261024-221529_fpga-sim-integration-recovery`；runtime=Codex；batch1。四正式包均首次独立综合round0 PASS，实际验收后实现修复轮数均0。本轮finished，不再自动派发。两个为完成恢复验证而发现的RTL问题已在本run隔离副本修正，不表示生产树已迁入。

## 逐包结果与唯一候选

|task_id|本包实际完成|唯一manifest SHA256|独立报告|
|---|---|---|---|
|T08.sync-production-sim|真实生产RAW顶层派生overlay，I2C接管/14笔顺序/两路完整数据、NACK/缺路/reset/重启|`6d9d980566997b74945066a8b015308962dcb58cd525ce868ef5837a0b482838`|`test-reports/T08.sync-production-sim-r0-integrated.md`|
|T10.a1-uart-descriptor-fix|两项描述符索引模2回绕、同拍push/pop计数；12原ID多次回绕/queued reset/4帧真实管道|`fd0cb6e7f920ba136049fdadd395f029bcd9df3d58dc2d14a2312e9a0d3c33e1`|`test-reports/T10.a1-uart-descriptor-fix-r0-integrated.md`|
|T10.a1-abort-cdc-fix|abort-only可靠跨FIFO、满时保持/整帧拒绝、目的RAW/skid/slot释放与复位边界|`db84411dfdcf979b1fc5f6a25e11812f90f0834896a8b76787b85cd434fa5dcd`|`test-reports/T10.a1-abort-cdc-fix-r0-integrated.md`|
|T10.a1-recovery-sim|组合修正DUT在原任务中完整重跑两比例20项恢复矩阵，首次独立验收|`628579eae2b6b2c1afc66a477799960a6b180b213e848bdbc0e1e955437d82e1`|`test-reports/T10.a1-recovery-sim-r0-integrated.md`|

各manifest准确路径、报告及候选文件SHA见 `candidate-binding-final.json`、`delivery-index.md`。T08与A+恢复是两条不同源码线，每任务有自己的唯一候选，不能拼成一个整机硬件候选。A+最终组合为top SHA=`5d0f9a001747168db39e07a10cfa417a25be797ae4013d07c3990d623310772a`、exporter SHA=`0f3ae49ee19cc69348024e4fbe25cd3766dfec2cd8435f34f2b117bf313ba097`及原六项SHA，绑定 `recovery-dut-binding-resume02.json`。

## 实际证据与判据

双路：独立重新编译真实 `ph1p_pcie_ep_top`，clean/NACK/missing/global-reset/restart/pending-reset六场景各一实跑；每路至少连续3帧正确，重启前后各3。引脚独立I2C解析、响应camera关联、源帧反推、独立逐bit CRC及角色写值/A-B身份反例通过。候选/规划/工具/保护输入前后零漂移。MIPI物理/DDR/PCIe环境为明确模型，不能外推电气/曝光。

恢复：测试者重新编译当前8RTL和原top负例两个独占库，二十正例=两异步比例×十场景：clean、clean32、raw/encoded中写reset、bad-frame、overflow、full-abort、pending-reset、sof-abort、last-skid-abort。cam/A1周期为14ns/5.333ns和3.7ns/5.333ns，UART同A1。每case最多送4good，实际均恢复4完整正确包，最大最后FE后10,042 A1周期，门槛≤1,000,000且≥2包。合计88包=80当次good/恢复包+8明确单列合法前缀，未把前缀算恢复或错误帧。

每包44B头、长度、四CRC、严格zlib EOF/no unused_data/no unconsumed_tail、直接相机tap的源字节/正向变换、唯一ID/epoch/零重复/零尾垃圾均通过。独立观察器另检查外部AW/W属于WRITING槽、AR属于READING槽及真实终态FREE；不是仅见abort脉冲就称槽已释放。原top成功载入后命中目标 `ABORT_ONLY_LOST_OR_SLOT_NOT_RELEASED`，17个checker负例全部拒绝。最终验收855个保护文件并集零漂移；规划最终复核四包合并保护输入，独立于测试者计数，结果见closeout-audit.json。

真实RTL输入用合成小图案，未采集真实相机新样例。W8/H2 RAW20B，正常示例stream29B+44B头=73B；W32/H2 RAW80B，RAW store每DDR字有效20B，共4字，压缩长度按实际包头核对。这里不以小图案计算真实图压缩收益；无本轮1080p容量/平均压缩比/持续带宽/资源/STA实测。旧77.76MB/s comp缺口仍属原探索记录，不因本轮PASS解除。

## G层与未完成边界

各包functional/engineering/system按冻结离线范围均pass，必要G0/G1通过。G2统一not_run；本轮没有实现数据库/STA/实现级CDC/资源/可下载候选绑定。G3/G4/G5本离线包N/A，不表示父硬件任务这些层已通过。父T08/T10硬件状态保持原样，不置done。

四个外部AW/W中写reset触发时pending=0、rvalid=0。模型确实保留已接受延迟AR/R，但**“reset瞬间仍有旧AR未完成”hits0、not_covered**。不宣称所有复位交错均已证明。也未验证全1080p、真实DDR/PHY、生产迁入、真实曝光同步、板级恢复、长稳、吞吐或发布。本轮TD/综合/route/bitgen/CWC/download/Flash/生产写回均0，板上候选不变。

## 历史、预算和过程偏差

原r0描述符第三次索引越界失败、resume01 abort丢失失败及旧manifest全部保留，不拼不同DUT的局部成功。旧descriptor问题补充机会1、abort问题0；所有实现修复轮0。依赖包初次开发修正不伪装成原恢复任务的验收后修复轮。

原恢复开发累计60calls、4全量compile、27实跑（7clean、19fault、1旧top负例）、设计载入前失败1。最终resume02新增18calls、2compile、20正例+1负例、17checker变异，无仿真重试。综合测试者在真实quota中断前9calls/0compile/0sim，用户反馈02及条件变化后续原ID新增20calls，累计29；本次2compile、20正例、1旧top、17变异、无仿真重试。两次quota中断/恢复不清零任何账，也不计实现修复。完整原账与各依赖包账在 `budget-ledger-final.json` 的原文件索引。

过程偏差如实保留：若干角色最初快速只读没有显式60s包装，后续读搜和编译/仿真有真实deadline；第四包开发有TB-only重编译、注入时刻/旧例监视器纠正和最终同TB重跑；最终测试者可选历史提交解析器两次因不适用断言失败后停止，旧top退出码评价和full-abort额外计数假设分别按真实证据纠正。它们未改变DUT/冻结刺激/必须门槛；最终独立运行时槽与直接源字节判据、全部必需矩阵和有效负例满足验收。原失败日志/无效附加检查的处置全部留在独立报告，不能列为已通过检查。

## 交付、回退与后续

生产/旧run/原输入/TD/板候选/共享盘符/其他工作树未改，未删除文件或目录。修正仅在本run两个candidate文件，T08也仅隔离overlay；回退为停止采用这些仿真副本，无需恢复生产或硬件。原冻结指南/输入索引保持哈希不变；最终指南/交付索引另写final版本。

本轮4/4已收束，不自动开第五包。剩余主题最多3项，仅作未来入口：①旧AR未完成时reset等额外交错；②生产迁入完整G2/CDC/资源及真实曝光/板级恢复/长稳资格；③既有A+吞吐缺口。另有新用户目标时再有界规划，不借本run自动扩展。
