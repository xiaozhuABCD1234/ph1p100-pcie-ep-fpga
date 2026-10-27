# T02 唯一 SRAM 尝试结果

当前现场原话来自 request-followup-05.md；已解除旧 current-on-site-facts 缺项，未重置预算或开启新任务。原生产候选及所有 699 项保持只读。

实际外层命令 `C:/Program Files/Python311/python.exe -B board/t02/execute-sram-once.py`（相对于本 run）；该脚本从项目根调用唯一已审阅的 `scripts/run_sram.py --execute` 一次。原冻结脚本通过全部报告和 SHA 门槛，使用临时 ASCII 映射 Z:/，调用 `D:/anlogic/TD_Release_2026.2/bin/bw.exe board/download_sram.tcl`。外层自有 wrapper PID=8832，原生 bw PID=30416。

外层启动记录 2026-10-19T20:59:43.661806+08:00；固定原生日志目录 board/sram-b01-20261019T205946；外层完成记录 2026-10-19T21:01:48.299393+08:00。原生 result.json：exit=1，timeout=true，pass=false，elapsed_seconds=121.30939936637878。原生等待上限 120 秒，后续仅终止自有 PID 树；外层未达到其 180 秒兜底期限。download.log 非空 281 字节，含实际命令/cwd、manifest SHA、OWN_PID 和终止记录；没有 B01_SRAM_DEVICE、B01_SRAM_PASS 或可判定下载成功的原文。后续只读 Get-Process 确认 8832/30416 均未运行。

没有自动启动服务、自动重试、CLI 读回、构建、更换候选、Flash 或接线/供电/传感器调整。原始日志保留原字节，其中 taskkill 的本地编码输出与 UTF-8 元数据混合；不得重写原文以改善显示。超时本身不足以判断根因是服务、设备、提示框或工具；器件身份和当前加载状态均 unknown。

下载前后全部 699 项大小与 SHA 一致，manifest SHA 保持 c7a40897166467f2beafb096701dba9cf836e1007d77ae03d90009d06f80d757。SRAM 1/1、采样组 0/3、生产 6/6、实际修复 0。G3 blocked，样本/几何/物理相位/内部 abort 后首个 good 恢复均未验证，G4 用户后放。不能对未确认下载的板卡发出新 CWC 采样指令或标 ready_for_test。

最小下一步：原规划读取本次 sram-execution.json、原生 download.log/result.json 和用户当前已有 GUI 状态；禁止本开发在 1/1 已用完的条件下自行再下。回退 pair 仍仅按原 board-entry 只读引用，未执行。停止所有自有活动并返回 blocked。
