# T02 preflight lessons

同一冻结候选的离线双 PASS 只提供 SRAM 入口资格。板测还依赖本次现场、下载原文和本次 camera/DHI 样本，旧“在场”回复不能证明当前供电/单 A/JTAG 独占。

大 probe-map 包含逐 bit nets，应解析后输出精确 name/clock/instance/width，避免完整打印 1280 位细节淹没下载入口和验收合同。解析只生成本任务参考文件，不改冻结输入。

用户依赖尚未满足时完成可审查预检后主动停止。部分证据 manifest 必须显式 ready_for_test=false；不能让准备文档被当作 G3 通过。

本次唯一 SRAM 入口在 120 秒实际期限内未给出器件身份/完成原文，已终止自有 PID 树。无原文时只报告 timeout 和加载状态 unknown；不要猜测服务未启动或设备故障，不自动起 server、不重试、不要求用户在状态未确认时触发采样。已有 SRAM 授权不等于可突破本轮 1 次上限。
