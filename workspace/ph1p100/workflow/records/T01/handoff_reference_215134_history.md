> **2026-10-14更新：** 同一215134位流已由用户确认恢复实时图，亮点仍存在。按用户要求暂缓亮点，当前先做[RGB565整屏彩色](../../../docs/RGB565完整彩色预览_方案与上板步骤_2026-10-14.md)，不再要求先完成旧四计数步骤。新LED/计数未补，以下旧记录保留其历史边界。

# T01：参考色条出图、实时图失败后的交接

状态：awaiting_hardware，等待分类计数。当前215134用户反馈参考颜色初步正常，但实时图没有；D37闪/D38灭/D39及D40亮。G3实时图fail，G4未测；身份按会话上下文关联，未独立读回。原G1/G2、bit及数据库未改。

下一步只做[ChipWatcher分类读取](../../../docs/参考色条正常但无实时图_ChipWatcher读取步骤_2026-10-13.md)：保持当前板运行，关闭BitWriter并在TD欢迎页ChipWatcher打开215134目录camera_ddr_display.cwc，点击Watch。先选auto_created_cwc2，加published_frames、passed_frames、failed_frames、protocol_errors四总线，尝试Instant Trigger，不点击下载。若必须下载/设备未识别/code mismatch，停在提示反馈原文。助手只完成离线配置导出，尚未捕获硬件值。

参考条仍可绕过载荷显示，D39聚合四类错误；D38灭只说明没有完整读回通过，不能直接认定CSI或DDR根因。published=0且protocol_errors增加可来自DDR fence失败，不能无条件只追相机。四项结果到达后再选择cwc1或cwc3，不同时改曝光、Bayer、PHY或约束。

匹配调试文件：`D:/TD/work/csi2/prj/camera_rgb332_reference_20261013_215134/camera_ddr_display.cwc`，与原bit同目录。位流仍SHA256 `5c8d3081ae5a56e8cd9c35de134ca75c7fece5f5379d33587b727d73a9ea35cd`。新[反馈/导出索引](../../../docs/evidence/rgb332_reference_board_feedback_20261013.json)和[上板记录](board-run.md)是当前入口；初始[构建索引](../../../docs/evidence/rgb332_reference_20261013.json)保留生成时状态。

222159、161550、215134和本轮CWC/导出脚本/日志保留，不删除文件、不写Flash。综合异常恢复、很小STA余量、覆盖率缺口、局部时钟告警和HDMI物理速率资格仍是边界；参考颜色正常不构成长期稳定或彩点修复证明。
