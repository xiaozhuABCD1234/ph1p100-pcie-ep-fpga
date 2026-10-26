from pathlib import Path
import json
raise SystemExit("Historical one-off migration record. Do not overwrite current RAW12 documentation.")
root=Path.cwd()
report=root/'docs/相机链路方案对照与验证_2026-10-10.md'
s=report.read_text(encoding='utf-8-sig')
s+='''
## 8. 本轮最终验证记录

2026-10-10，本机TD6.2.2.200067完成syn_pad_1→phy_pad_1→bitgen；实际产生5,224,027字节bit。**构建流程完成，STA未通过，未下载。**

| 项 | 实际结果 |
|---|---|
| ERAM | 224 / 300，74.67% |
| Slice | 3190 / 71680，4.45% |
| Setup | WNS −0.221ns，TNS −2.156ns，17个违例端点 |
| Hold | WNS +0.020ns，TNS 0 |
| STA coverage | 97.91%，不表示完整接口约束已覆盖 |
| 约束检查 | 1个无时钟定义网络（I2C scl_clk）、20个无input delay、17个无output delay、差分端接dummy node警告 |
| 负裕量域 | 相机A字节时钟−0.221ns、pclkx1−0.188ns、pclkx5−0.214ns；最差路径在预览写入地址/使能相关网络 |
| 运算回归 | 1048583项PASS |
| RAM读口回归 | 有效宽4：420周期PASS；非二次幂有效宽3：356周期PASS；各覆盖4bank |
| 源码迁移 | 60个文件/元数据同步核对；原审查副本不变，PCIe原顶层与Git HEAD及D盘一致 |

最终bit：`D:/TD/work/csi2/prj/camera_peer/fpga_prj_Runs/phy_pad_1/fpga_prj.bit`。
SHA256：`a3680dc1d3f6b5b689f6eaa6a070e6eab9a3243948c127189ceeebd048e4de08`。
完整STA：`fpga_prj_Runs/phy_pad_1/final_timing.rpt`；约束检查：`fpga_prj_Runs/phy_pad_1/fpga_prj_chk.timing`；资源：`fpga_prj_Runs/phy_pad_1/fpga_prj_phy.area`。
这些文件均在D盘子工程内，构建产物没有放入源码快照。当前源文件SHA256及原文件修改清单见[LOCAL_STATE.json](../fpga/csi2/prj/camera_peer/LOCAL_STATE.json)。

最终只变更3个上游文件：`.gitignore`增加本地证据排除；`fpga_prj.al`本地路径/TD运行信息；`cam_preview.v`上述修正。相机配置、约束和其他RTL与上游逐文件哈希一致。新增构建/测试脚本与说明另列，不冒充上游原码。

先前本轮RAM读口尝试未解决映射、两次apply_patch审批连接中断，以及归档校验中止的记录均保留。后续原生工具按正常审批创建文件并执行成功，没有待审批操作、未决worker调用或后台构建需要用户接管。
'''
report.write_text(s,encoding='utf-8')
notice='> **2026-10-10RAW10对照工程接入（最新）：** 用户报告相机链路已通，PCIe已连接。已固定上游提交2d59180并迁入D:/TD/work/csi2/prj/camera_peer，源码同步到fpga/csi2/prj/camera_peer。保留4K RAW10调试参数，修正预览平均/位宽/RAM映射；ModelSim运算1048583项及读口两种宽度均PASS。TD6.2.2已完成综合/PnR/bitgen，224ERAM、3190Slice，但setup WNS=-0.221ns，STA未通过，未下载。两路同步、CRC/完整帧、DDR、三算法、压缩和PCIe图像搬运仍未验收。近期是否沿用4K RAW10基线待用户决定。详见`docs/相机链路方案对照与验证_2026-10-10.md`。本条覆盖下方历史“未连接/无新RTL/仅骨架”的执行起点，不撤销最终RAW12接口候选或队友交付边界。'
for rel in ['CODEX_HANDOFF.md','当前必读/01_FPGA主线学习手册_由浅入深.md','当前必读/02_FPGA独立开发路线与工作包.md','当前必读/选题三_重新对齐后的方案基线.md','当前必读/选题三_研发路线与每日安排.md']:
 p=root/rel
 s=p.read_text(encoding='utf-8-sig')
 assert '2026-10-10RAW10对照工程接入（最新）' not in s
 pos=s.index('\n')
 s=s[:pos+1]+'\n'+notice+'\n'+s[pos+1:]
 if rel=='CODEX_HANDOFF.md':
  s=s.replace('| MIPI接收 | 当前器件没有编译/PnR或上板验收 |','| MIPI接收 | 用户报告相机链路已通；已迁入原工程HRIO软PHY/RAW10工程并本机构建出bit，但STA未通过，未下载新bit；当前板像素完整性待验收 |')
  s=s.replace('交接时重新查看了 `D:\\TD\\work\\csi2`：仅有目录骨架，**没有csi2.al**，也未有该主工程的build结果。','10-09交接时仅有骨架；10-10已新增 `prj/camera_peer/fpga_prj.al` 相机子工程并本机构建。根目录仍没有csi2.al，原PCIe骨架保留。当前子工程bitgen完成但STA未通过，不能把它当作整链路验收。')
 if rel=='当前必读/02_FPGA独立开发路线与工作包.md':
  marker='## 1. 开发时共同遵守的边界'
  replacement='''## 0. 从原工程成果接续的当前起点

F0连接和F2/F3出流已有用户/原工程报告，当前从预览正确性、完整帧诊断和时序收敛继续。F1读回/错误控制、F4 CRC/帧完整性没有因出流自动验收。F5—F10仍保留。不要先重做27MHz/RAW12控制工程而覆盖已调通模式；当前4K RAW10基线与最终RAW12接口分别待决定。下面F0—F10保留完整工作包定义，其中“本轮无RTL/仅骨架”是10-09历史状态，以上方最新记录为准。

''' + marker
  assert marker in s
  s=s.replace(marker,replacement,1)
 p.write_text(s,encoding='utf-8')
p=root/'README.md'
s=p.read_text(encoding='utf-8-sig')
start=s.index('2026-10-10 首次归档：')
end=s.index('## 阅读入口',start)
s=s[:start]+'''2026-10-10 更新：

- 用户报告相机链路已通、PCIe已连接；像素完整性、曝光同步、DMA和吞吐仍待记录。
- 已迁入原工程固定版本相机工程至D:/TD/work/csi2/prj/camera_peer，并同步源码至`fpga/csi2/prj/camera_peer/`。原PCIe骨架保留。
- 修正预览像素平均、地址位宽和RAM映射；ModelSim运算1048583项、读口两种几何回归PASS。
- TD6.2.2完成综合/PnR/bitgen：224ERAM、3190Slice；setup WNS=-0.221ns，**STA未通过，未下载**。
- RAW10对照工程是HRIO软PHY、4K RAW10、A路灰度HDMI；DDR、三算法、压缩和PCIe图像发送仍需实现。当前格式与此前RAW12基线差异待决定。

细节、代码定位与验证边界见[接入及差异核验](docs/相机链路方案对照与验证_2026-10-10.md)，子工程用法见[本地说明](fpga/csi2/prj/camera_peer/LOCAL_NOTES.md)。

''' + s[end:]
s=s.replace('| `fpga/csi2/` | 正式 FPGA 工程骨架快照 |','| `fpga/csi2/` | PCIe骨架及已迁入相机子工程源码快照 |').replace('| `tools/td/` | TD CLI 只读验证脚本 |','| `tools/td/` | TD自检、源码迁入/同步、构建、ModelSim回归与RAM最小实验脚本 |')
s=s.replace('仓库保存的是 `D:\\TD\\work\\csi2` 的首次源码快照','仓库保存的是 `D:\\TD\\work\\csi2` 的选定源码快照（含camera_peer子工程）')
p.write_text(s,encoding='utf-8')
print('Updated report, handoff, baseline, teaching/route entries and README')
