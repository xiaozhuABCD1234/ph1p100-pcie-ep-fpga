# 辅助建议留档
DeepSeek task_id=509a1a83f1ea4af698134f22382cf1fb；status=completed；1轮；usage=1127 API tokens。纯文本整理，无pending call_id、无执行操作、无项目访问。未向其发送源码、凭据、环境或聊天历史。Codex规划者保留验收与技术决策。

原建议：
回来点两下（采样凭条）
填写项：真实候选 bit、CWC、manifest 由开发填写，不得沿用基线或留空。
上板范围：仅 SRAM 运行。不接 PCIe、不接 RK。不改线、电源、相机，不写 Flash。
操作：GUI ChipWatcher 两次 Instant Trigger，间隔 ≥20 秒。每次导出原始样本和截图，文件名带序号与时间。
读回：读回 CLI 已关闭，本轮不用 CLI 读回。
判读：两样本只证明本次短窗口结果，不证明 10 分钟长稳。RAW→DDR 校验、几何、坏帧证据未完成前不得写 PASS。
停止条件：遇身份或候选不匹配（bit/CWC/manifest 与开发所填不一致）立即停止并反馈，不继续采样。
本轮 batch=2，进度优先。

规划审查：建议只作短窗操作文字。增加完整候选身份、现场窗口与CRC/几何/坏帧各门槛；两次点击不是PASS的充分条件。正式清单由开发基于最终新候选填写并由综合测试核验，见board/回来点两下.md。

