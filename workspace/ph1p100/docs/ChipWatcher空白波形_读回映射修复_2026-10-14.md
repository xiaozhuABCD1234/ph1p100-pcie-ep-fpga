# ChipWatcher空白波形：补齐物理ERAM读回映射

> **后续板验通过（统计读回范围）：** 用户成功取得140836同程序的白/红/蓝原始统计，均N=518400、valid=1，证据见[测量JSON](evidence/white_balance_stats_20261014.json)。本修复已获得实际读回反馈；颜色校正则属于后续新候选，未用此结果宣称修复。以下保留故障时的原始状态。

用户在140836 RGB565位流上确认：ChipWatcher下载达到100%，HDMI实时图像正常变化；CWC1立即触发、有效标志high条件的单次触发，以及CWC3立即触发均经历Waiting for trigger→Reading data→Idle，Triggered仍为0且没有波形、没有错误弹窗。尚未取得任何白平衡统计值。

## 已定位的文件缺陷

原`camera_ddr_display.cwc`虽然有三个已启用实例、22个节点及正确时钟信息，但三个`logic_eram`只有名称和尺寸，没有任何`phy_eram`读回映射。原文件第1178、1326、1406行为自闭合节点。这是主机调试文件的真实缺陷，不能把无波形归咎于用户没有设置触发条件。

板卡官方例程`D:/TD/03_F9P_CA05_PH1P50_PH1P100/V2026/HW-MLK-F9P-CA05-PH1P100/01_start/00_for_starter/04_use_ChipWatcher/fpga_prj_Runs/phy_1/cw/compiled.cwc`第82–85行包含物理ERAM的RID、WID、数据位置和工作模式。安装目录`D:/downlaod/scripts/DefaultFlow.tcl`第224–229行在bitgen之后调用`setup_debugger -prj $prj_name`，官方例程run.log第1301–1304行记录其生成`cw/compiled.cwc`和`cw/compiled.bit`。之前单独调用`export_chipwatcher`遗漏了这一后处理步骤。

另外，`JTAG_PERSISTN="DISABLE"`不能解释为JTAG被禁用；本机`D:/downlaod/sim_release/ph1p/ph1p_phy_config.sv`第191–194行明确说明DISABLE选择配置专用IO。

## 实际修复与校验

使用原布线检查点和原bit/BID，通过TD原生`setup_debugger`生成完整配对文件，再更新原路径的CWC：

```text
D:\TD\work\csi2\prj\camera_rgb565_20261014_140836\camera_ddr_display.cwc
```

旧CWC单独保留在同项目的`_chipwatcher_legacy_20261014/camera_ddr_display.cwc`。没有删除文件，没有更改相机算法、Bayer相位或白平衡增益，也没有重新综合或布线。

| 实例 | 逻辑宽度×深度 | 修复后的物理ERAM数量 |
|---|---:|---:|
| auto_created_cwc1 | 449×1024 | 23 |
| auto_created_cwc2 | 128×1024 | 7 |
| auto_created_cwc3 | 64×1024 | 4 |

校验器逐项比对原BID的RID/WID、实例名称、逻辑和物理尺寸、数据偏移、工作模式，并要求覆盖全部逻辑数据位且无重叠。原CWC因没有物理映射被拒绝；新CWC通过；缺块、错误RID、错误偏移、缺逻辑RAM、部分深度和错误物理工作深度六类故障被拒绝。

原140836 bit与`setup_debugger`产生的compiled.bit逐字节相同，SHA256仍为`e4a3e980c4bb2305c52e6316da4164f8f1588e6bc7819edf0fb68fd8f99bbf7e`。215个冻结输入、BID和原布线DB校验不变。TD的close_project会保存项目文件，`.al`的Project Path发生规范化；该文件不能描述为逐字节未变，细节保存在修复证据JSON中。

直接使用`export_chipwatcher -add_bid`的两次恢复尝试均发生TD内部coredump，未被接受为成功；日志和dump留在D盘验证目录。随后改用官方setup_debugger流程成功。一次从含中文及反斜杠路径直接调用Tcl的尝试返回了0但实际未读取脚本，也被判为未执行；最终运行使用ASCII路径暂存的同字节脚本，并同时检查完成标记、产物及哈希。

## 下一步手动验收

1. 关闭当前ChipWatcher窗口；如询问保存临时观察设置，选否，避免将内存中的旧配置写回修复后的文件。
2. 从TD欢迎页打开ChipWatcher，选择上面原路径的CWC，点击Watch。
3. 确认Bit File仍为同目录的camera_ddr_display.bit，在本窗口下载到100%，等待相机图像恢复。
4. 选择auto_created_cwc1，在上方波形列表加入raw_a_sum、raw_b_sum、raw_c_sum、raw_d_sum、raw_sample_count、raw_stat_valid。下方触发列表留空，点击Instant Trigger一次。
5. 若有波形，按[逐步读取指南](140836白平衡原始统计_逐步读取.md)读取同一黄色游标位置的数据；若仍空白，保留完整界面和状态过程，不宣称硬件问题已经解决。

当前结论仅为文件缺陷已修复、原生生成和文件校验通过；硬件取数、Bayer相位及白平衡结果仍待实测。严重玫红和活动亮点没有因此被宣布修复。
