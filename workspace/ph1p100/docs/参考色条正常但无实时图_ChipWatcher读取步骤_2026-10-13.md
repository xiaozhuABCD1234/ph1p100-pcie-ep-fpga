> **2026-10-14后续更新：** 用户确认同一215134位流未更换，实时相机后来已恢复，活动亮点仍在。当前先按用户要求做[RGB565完整彩色](RGB565完整彩色预览_方案与上板步骤_2026-10-14.md)，不再把旧无图/LED状态当成当前现场，也不要求先完成旧计数步骤。以下保留原版本历史和操作依据。

# 215134：参考颜色正常，但没有实时相机图

## 已取得的实际反馈

用户反馈青色像浅蓝、品红像紫色，其余参考颜色正常，但没有实时图；灯态为D37闪、D38灭、D39/D40常亮。青色/品红的主观命名没有明显矛盾，参考颜色可视为初步符合预期，没有色度仪或采集帧的RGB实测。实时图功能失败，不能将该次观察写成完整链路通过。

本次按操作上下文关联215134及预期bit SHA256 `5c8d3081ae5a56e8cd9c35de134ca75c7fece5f5379d33587b727d73a9ea35cd`，没有独立下载日志或板上位流身份读回，未取得精确时长、温度和分类计数。见[追加反馈与调试文件索引](evidence/rgb332_reference_board_feedback_20261013.json)；[初始构建索引](evidence/rgb332_reference_20261013.json)的hardware=false是导出时状态，保留不改写。

| 灯态 | 对应代码含义 | 不能推出的结论 |
|---|---|---|
| D37闪 | DDR ready为真，DDR用户时钟心跳运行 | 不证明相机或DDR数据正确 |
| D38灭 | 还未锁存完整DDR读回校验通过 | 不能单独区分没有发布帧与读回失败 |
| D39亮 | failed_frames、protocol_errors、显示欠流或采集丢帧至少一类曾触发 | 不直接等于CSI CRC错误，也不能据此认定HDMI损坏 |
| D40亮 | A路配置流程完成标志 | 不证明CSI帧已完整接收 |

代码定位：实际候选`ddrmc_display_top.v:179–208`汇总错误和驱动D37–D39；`camera_ddr_display_top.v:185–209`连接相机及D40。参考条在采集未就绪时仍能显示，不能把条纹正常解释为DDR帧通过。

## 已独立核对的边界

实际候选`camera/uisrc/03_ip/vtc/uivtc.v:51,63–64`中VS仅在1084～1088行消隐期间高，DE只在1920×1080活动区高；`rgb332_display_pixels.v:47`注册VS/DE不取反。叠加模块每1920个有效像素推进一行，只有前64行覆盖。相关输入哈希和实际网表中的VS/DE直通寄存路径已核对，没有发现VS极性导致全屏覆盖的代码证据。下方默认黑色可由未armed/frame_bad产生，见`rgb332_display_pixels.v:47,63–75`；究竟是哪种原因仍待计数。

已有三个ChipWatcher，分别采样相机字节时钟、DDR用户时钟和像素时钟。已从**同一个最终数据库**导出匹配配置，未重编译、未下载，也没有改变原bit：

```text
D:\TD\work\csi2\prj\camera_rgb332_reference_20261013_215134\camera_ddr_display.cwc
```

它与原`camera_ddr_display.bit`在同一个文件夹。不要使用旧工程的Watch/Active Run去猜测本轮探针身份；离线配置绑定当前最终数据库，避开综合管理器异常的run状态歧义。配置导出成功不等于已经读取硬件。

## 第一轮只读DDR四项，不换bit

1. 保持当前板运行、HDMI和A相机连接，B仍断开。不重烧、不复位、不依赖冷却后重启。
2. 关闭BitWriter窗口以释放调试连接；这一步不下载文件。TD使用`File → Close Project`关闭当前软件工程，回到欢迎页，板上SRAM程序保持运行。
3. 欢迎页的`Work With a Tool`区域点击 **ChipWatcher**，在弹出的文件选择框打开上面的`camera_ddr_display.cwc`。这是离线打开调试配置，不是打开`.al`工程。
4. 点击ChipWatcher界面上方的 **Watch**。预期出现三个实例标签：`auto_created_cwc1`、`auto_created_cwc2`、`auto_created_cwc3`。上方的Bit File应指向215134目录的`camera_ddr_display.bit`。
5. 当前已按上下文加载同一个bit，**先不点下载按钮**。先选择`auto_created_cwc2`标签；若工具要求下载、设备未识别、报告code mismatch或bit不存在，停在该提示，反馈原文，不自行重新综合或重烧。能否直接附着当前程序尚未在此机器验证。
6. 在波形区域点击 **Add Signals**，选入四条总线：

   ```text
   u_ddrmc_test_top/published_frames[31:0]
   u_ddrmc_test_top/passed_frames[31:0]
   u_ddrmc_test_top/failed_frames[31:0]
   u_ddrmc_test_top/protocol_errors[31:0]
   ```

7. 在总线名称处右键，将Radix改为 **Unsigned Decimal**（无该选项时用Hex并保留0x前缀）。点击工具栏 **Instant Trigger**，即立即触发，先不用设置触发条件，也不用连续触发。
8. 观察Value列，必要时在波形内点选一个采样位置使Value bar落到有效样本。记录四个数；相隔约几秒再点一次Instant Trigger，记录第二组，帮助判断是否还在增长。1024个DDR时钟样本的短窗口不直接用于计算相机fps。
9. 使用`File → Save As`将本次已采到的波形另存，例如`D:/TD/work/csi2/_validation/reference_ddr_first.cwc`，不要覆盖作为打开入口的`camera_ddr_display.cwc`。支持导出CSV时也可另存CSV；原始计数和报错文本即可先反馈，不要求一次操作完三个时钟域。

| 项目 | 第一次 | 第二次 |
|---|---|---|
| published_frames | 待读取 | 待读取 |
| passed_frames | 待读取 | 待读取 |
| failed_frames | 待读取 | 待读取 |
| protocol_errors | 待读取 | 待读取 |

首个反馈重点是这四个数，或卡住步骤的准确提示。尚未取得它们之前，不同时调整曝光、增益、Bayer相位、PHY tap或DDR约束。

## 根据结果再选下一步

- published始终为0且protocol_errors增加：优先检查DDR提交/协议。`ddr_frame_store.v:105–112`的写后fence回读若RLAST或末字比较失败，会先增加protocol_errors而不发布帧，因此不能一律归因相机。
- published始终为0且protocol_errors为0：下一轮在cwc1看good/bad、CRC/header/timeout、last_wc/last_lines和capture_drops，同时保留DDR写等待/无响应的可能；不能仅凭未发布认定CSI失败。
- published增长但failed增长、passed为0：先追踪DDR读回验证失败；不能立刻归因CSI或HDMI。
- published增长而passed/failed都不动：继续查读回请求/响应与显示启动握手，不以配置完成替代数据流。
- passed增长但没有实时图：再看cwc3的shown_frames和underflow_frames，以及显示端消费；当前D38灭的观察不支持提前走这条分支。

三个实例独立时钟采样，不能把不同时间的数当作同一原子快照。分类计数说明故障边界，温度/额定速率/彩点根因仍需另行证据。

## 工具与原文定位

本机`D:/downlaod/doc/SWUG/SWUG111_Debug_Tools_User_Guide.pdf`：物理页55（印刷页51）示欢迎页ChipWatcher打开`.cwc`；物理页58–59（印刷页54–55）说明离线配置与bit同目录、Watch观测；物理页40（印刷页36）定义Instant Trigger和Add Signals；物理页47（印刷页43）说明Value bar/Value列。已核对原文及打开界面图，没有复制厂商整页到Git。

原生CLI查询已确认注册`read_cwc_*`、`rdbk_cwc_data`等函数，但未从可用帮助/命令手册取得其参数签名；未猜参数执行硬件调用。当前CLI仅完成匹配配置导出，现场计数尚未读取。导出脚本、命令退出码、配置及bit/DB哈希在[本次追加索引](evidence/rgb332_reference_board_feedback_20261013.json)，不冒充上板取数成功。
