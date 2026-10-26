> **当前运行：20261015_T01_timing_111134。** 103222原生零违例，但setup0.001ns不满足本轮0.3ns目标，探索归档deliverable=false。111134四项G1通过，G2正在运行；G3/G4 not_run，无硬件下载。详见[优化记录](../../../docs/RGB565时序裕量优化_2026-10-15.md)。

# T01：分层验证

## 当前：20261015_T01_rgb565_wb_002820

候选 `D:/TD/work/csi2/prj/camera_rgb565_wb_20261015_002820`，220项冻结输入，T01为awaiting_hardware。实际核心参数为960×540、phase3、R/B Q10=2400/2062、名义黑电平50。白/红/蓝统计支持R=C、B=B、两绿=A/D的候选解释；显示颜色身份仍需G3验收。乘积增加一级寄存，SOF/valid/last与下游FE/good/abort同延一拍，原始统计时序不变。入口：[白平衡闭环](../../../docs/RGB565白平衡闭环_2026-10-14.md) · [完整证据及161项原始产物](../../../docs/evidence/camera_rgb565_wb_20261015_002820.json) · [实际统计](../../../docs/evidence/white_balance_stats_20261014.json)。

| 层级 | 结果 | 范围与证据 |
|---|---|---|
| G0 | pass | 延续稳定RAW10单A、1080p60及TD/Git授权；用户要求每次交付执行工作流第5.1节。亮点暂缓，B断开，不做30Hz或硬件自动下载 |
| G1 | pass，所选范围 | 冻结实际参数数学测试、八配置矩阵、四相位默认回归及流水/打包14类用例通过；旧零级实现被负对照拒绝。补充两帧960×540全尺寸G1，1036800像素/64800字，独立zlib CRC=1da3ba2a/059b4883，3类X故障拒绝；0工具错误/告警。各项范围与路径见下文及完整证据；不外推板测或CSI/DDR/HDMI整链路仿真 |
| G2 | pass，所选范围 | 六native阶段均核验exit0、成功标记、产物及同一最终DB；setup0.000ns/hold+.020ns/period+2.200ns/TNS0且0违例端点，MIPI+.651ns，4组Gray skew最小+2.962ns。2FIFO的108Q/72函数/来源、16独立采样位、4 HDMI PAD/68并行路径审查通过；完整CWC/BID物理ERAM23/7/4片及compiled.bit逐字节一致通过 |
| G3 | not_run | 新候选bit/CWC已生成，尚未人工下载；按方案第5节做SRAM短测，白纸中性、红蓝身份、恢复与计数待验 |
| G4 | not_run | 新候选的持续运行、热态、稳定性及性能未测；活动亮点待办 |
| G5 | not_applicable | 当前为单A固定白平衡预览，未集成双路、PCIe或RK |

流水实现重新运行八配置矩阵：校准增益、单位增益、极端黑电平、0/0.5/4倍增益等，证据 `D:/TD/work/csi2/_validation/wb565_pipeline_green_20261015_002513`；四相位默认回归672采样通过，证据 `D:/TD/work/csi2/_validation/rgb565_20261015_002624_166999`。较早缺少新增端口的矩阵尝试有4条告警，未验收；本次新矩阵为0工具错误/告警。组件测试不能代替上述实际候选绑定测试或本候选G2。未变DDR等后端若引用旧回归，须先核对冻结输入哈希，并标注引用范围。

实际参数数学绑定：`D:/TD/work/csi2/_validation/wb565_candidate_20261015_002837_205820/result.json`；流水/guarded打包绑定：`D:/TD/work/csi2/_validation/wb565_pipeline_candidate_20261015_003722_458193/result.json`，14类用例、437像素、各3218次延迟/判决/统计检查、2878次打包检查、24次停顿，几何16×2。最终全尺寸采样/打包：`D:/TD/work/csi2/_validation/wb565_full_frame_20261015_005345_198402`，两帧全部采样、每字payload、原始统计与元数据一致；独立CRC不是CSI或DDR校验。

CDC检查器故障对照：`D:/TD/work/csi2/_validation/rgb565_cdc_20261015_005913_123745`，有效副本通过、4个故障副本被拒绝。仅覆盖实际映射与所列故障，不是形式化全芯片CDC证明。资源LUT16171、REG30825、ERAM77、DSP2、PLL3；覆盖率route97.99%/重导入96.79%。setup报告显示0.000ns，余量极小；保留局部时钟/HDL-7225告警、串行HDMI速率资格及热态未证明的边界。

最终绑定：bit SHA256 `4d591c31da9a71b9c261972e5089930af3e441c2096ed37736c8d2340ddd8865`；CWC `46ffa46f18d6f01f30a779a29514e824007b4999653a4b83cfe5aa17907eadb2`；所选DB `b55b9ef09ef1594612d90f33c71e3711d8fc93c2fd75cd846eae997a30823efc`。其报告、完整输入manifest、BID及原始日志哈希统一保存在[候选证据](../../../docs/evidence/camera_rgb565_wb_20261015_002820.json)。

每次交付必须按[第5.1节](../../README.md)核对实际输入/参数/测试绑定、相关红绿测试、native退出码+成功标记+实际产物、同一最终数据库的报告和位流哈希、完整CWC/BID物理ERAM覆盖及配对bit一致性、独立审阅和主助手对最终文件的复核。G2/G3/G4未通过时不填pass；旧140836时序报告不替代新候选报告。

## 历史：233658白平衡组合路径候选

`D:/TD/work/csi2/prj/camera_rgb565_wb_20261014_233658`冻结218项输入，实际绑定算术/原始统计G1通过；结果 `D:/TD/work/csi2/_validation/wb565_candidate_20261014_235250_085979/result.json`。独立八配置G1旧记录保留于 `wb565_blacklevel_green_20261014_01` / `wb565_blacklevel_red_20261014_01`。

该候选G2为fail：setup=-1.849ns、setup TNS=-24.474ns。关键路径经BRAM读出、未寄存的白平衡乘法/幅值/钳位到out_data；另有DDR ready/init到last_word CE的setup=-0.418ns。未生成bit、未下载。完整定位与哈希见[失败证据](../../../docs/evidence/rgb565_wb_failed_233658/record.json)，不能以退出码或G1通过提升为可上板候选。

原native_route accepted=false同时包含缺少独立DRC报告文件的检查问题；TD实际将DRC输出到控制台。此项已与真实负时序分开记录，不能把负时序解释为单纯日志门禁误报。新输入使用002820重新冻结，不覆写233658原始日志。

## 140836：后续实际板验校正

用户确认140836位流身份后观察实时相机可变化，但画面严重玫红，因此颜色G3为fail。修复CWC物理ERAM映射后，用户实际成功读回白/红/蓝三组统计，因此ChipWatcher统计读回G3在该范围为pass。两者证据见[颜色反馈](../../../docs/evidence/rgb565_magenta_feedback_20261014.json)、[原始统计](../../../docs/evidence/white_balance_stats_20261014.json)及[读回修复](../../../docs/ChipWatcher空白波形_读回映射修复_2026-10-14.md)。未独立硬件读取位流身份；沿用用户确认与同程序操作记录。

191348相位候选的布线由助手按当时用户暂停要求停止，未生成新bit；保留历史，不计为技术失败或当前暂停。本轮采用新的002820候选。

## 历史：20261014_T01_rgb565_140836交付前快照

以下保留首次交付时的验证记录；其中G3 not_run已由上面的真实反馈更新，不再表示当前现场。

当前候选：`D:/TD/work/csi2/prj/camera_rgb565_20261014_140836`，215项冻结输入。单A RAW10 4K30，960×540 RGB565经DDR放大1080p60，B断开；RAW12封存、30Hz停止。G1及所选G2已通过，G3/G4未执行。

入口：[方案与详细上板操作](../../../docs/RGB565完整彩色预览_方案与上板步骤_2026-10-14.md) · [完整证据](../../../docs/evidence/rgb565_20261014.json) · [run-record](run-record.json)。位流SHA256 `e4a3e980c4bb2305c52e6316da4164f8f1588e6bc7819edf0fb68fd8f99bbf7e`。

215134原位流后来由用户确认恢复实时相机，活动亮点仍在；[新恢复记录](../../../docs/evidence/rgb332_reference_recovery_20261014.json)与旧无图记录并存。当前先完成真实颜色，亮点排查按用户要求暂缓，不能标记根因已解决。

| 层级 | 结果 | 范围 |
|---|---|---|
| G0 | pass | 已有持续调试、TD CLI、GitHub封存授权；优先完整彩色 |
| G1 | pass | 四相位672采样/统计FE门控、14类guarded故障；紧凑DDR65536像素和完整2073600像素、独立zlib CRC；RGB332精度、提前统计、地址别名负对照被拒绝 |
| G2 | pass，所选范围 | 六native阶段exit0；setup+.003ns/hold+.020ns/period+2.200ns/TNS0；4组skew；108Q/72函数/来源，4故障副本拒绝；16独立采样位，4PAD/68并行路径 |
| G3 | not_run | 尚未下载此新位流，真实颜色/灯态/计数未知 |
| G4 | not_run | 持续时间、温度、稳定性及性能未测 |
| G5 | not_applicable | 本轮为单A彩色预览，整机链路尚未集成 |

route98.00%/重导入96.79%覆盖率、3ps余量、局部时钟/HDL-7225告警、串行HDMI速率资格冲突保留。真实Bayer相位、白平衡、Gamma及颜色矩阵未校准。G1早期bench编译失败和负对照初版工具Fatal均保留，没有计作通过。实际最终各G1成功/预期失败记录为0工具errors/0warnings。
