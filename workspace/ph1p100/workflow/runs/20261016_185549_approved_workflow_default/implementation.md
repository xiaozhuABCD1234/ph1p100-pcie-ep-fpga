# DEFAULT-RELAY-V2 开发交付

状态：ready_for_test，round0。本次仅把用户已批准的《主对话仅作传输》逻辑同步为项目默认配置，没有重新设计或执行完整流程。

## 实际修改

共16个候选文件：根AGENTS的默认工作流段、七个项目SKILL、四个主技能引用（含新增relay-contract）、四份workflow角色说明。逐文件差异在`configuration.diff`，原文件备份与SHA在`baseline/`及`baseline-index.json`。原有dirty修改保留。

| 批准要求 | 实现位置 |
|---|---|
| 主只原样传输，不读完整计划/材料/源码/报告，不选题拆分/技术判断/技术总结 | 根AGENTS、orchestrator、四份说明，relay-contract规定可读元数据 |
| 规划理解拆分、依赖顺序范围验收、工具设备停止回退、简短派发 | planner、design-guide、dispatch合同 |
| 默认每任务新DEV/三TEST，同任务FAIL续原ID，用户明确大于1才合批 | 根入口、主/开发/三测试技能、说明与调用/报告合同 |
| 开发停止修改、同manifest三维并行，适用G层预先限定 | dev、三测试、report-contract、传输合同 |
| round0首次验收、最多三轮实际修复、外部缺条件直接交规划 | 主/规划/开发/测试技能及固定分支表 |
| 复测影响/证据复用由开发测试给清单，主不拼不同输入PASS | relay-contract及各角色，范围验收/实现/复现报告按原角色归属 |
| 用户反馈原话、无效长返回交原角色、原规划更新和收尾/主原样转发 | root、planner、dev、tester、四份说明 |
| 实际工具schema、fork_turns none、直接collaboration、真实ID、失效恢复、不递归/不扩权 | codex-calls、relay-contract、默认入口与角色技能 |

原FPGA数据/接口/时序/CDC/bit-CWC/板测门槛保留。工作流README的G0—G5合同逐字未变，5.1除第6条角色归属外逐字未变。根AGENTS工作流标题前的删除禁令和完整DeepSeek块按字节保持一致。AI协作文档第2、6节的DeepSeek/执行边界逐字保留。

## 局部静态检查

实际工作目录：本项目根。Python 3.11.5。实际执行：

```text
python workflow/runs/20261016_185549_approved_workflow_default/static-check.py
exit_code=0
{"checks": 27, "failed_checks": [], "candidate_files": 16, "local_links": 72, "protected_files": 8}
```

结果文件为`static-check-results.json`：七SKILL frontmatter/name/description、UTF-8及代码围栏、本地链接、两个工具JSON示例、根保护前缀、既有dirty保护文件哈希、硬件G层/5.1边界和候选清单检查均满足本次局部检查。保护文件包括tasks.json、根README/CODEX_HANDOFF、既有生产接口文档等8项；未读取生产源码或硬件工程。`rg`的冲突检索由开发人工审阅，命中均为明确禁止/历史对照或恢复边界，无保留的主职责回流。

这些是开发自查，不替代三个独立角色的静态判定。检查脚本只读取配置并将结果/差异写入当前run，不是调度器或完整流程运行器。

## 有界辅助

DeepSeek只接收旧句摘录与批准规则，做最多12项纯文本冲突定位。任务ID为`7716c59a150240f7bbc31abb1370902c`。其额外目录读取提案被拒绝；pending call_id通过resume恰好回传一次真实拒绝后完成。未执行worker命令或补丁。开发独立核对其提案；“所有FAIL一律交规划”和“批准批复测等于跨任务复用”两条过度简化未采用。辅助记录在`deepseek-text-audit.json`，不构成三维验收。

## 冻结、边界与回退

实际候选、支持文件及SHA见`candidate-manifest.json`，三测试输入见`test-dispatch.json`和各维度input文件。冻结后开发停止修改，等待主派发三测试。G0配置合同/G1静态一致性适用；G2—G5硬件/整机不适用（只改文档配置）。本run未单独新增工程指南，任务相关配置合同/写范围/静态验收已由规划写在dev-plan，未补造硬件参数。

未运行：旧试任务、完整流程或压力情境、实际新聊天创建、生产RTL/模型测试、TD构建、下载/Flash/板测/长稳、提交/push/发布。未改生产工程、tasks.json、旧run/历史证据、D盘、其他聊天/工作树、全局配置；没有删除文件。

回退材料是当前run的逐文件baseline和configuration.diff；如需回退，只处理本轮明确配置文件差异，并先核对后续改动。不自动reset/clean、覆盖无关修改或清理目录。根AGENTS只回退工作流段，保护前缀不动。
