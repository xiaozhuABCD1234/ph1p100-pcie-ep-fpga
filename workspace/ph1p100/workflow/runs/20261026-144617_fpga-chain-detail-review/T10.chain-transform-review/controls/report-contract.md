# 综合测试报告约定（现行单一综合测试者）

默认每任务只派一个与开发独立的综合测试者；同任务 FAIL 或修复影响才续原测试会话，不跨任务复用。用户明确批大小大于1时，一个综合测试者覆盖规划批全部任务，但逐任务分别判定与记账。站点路径：`OUTPUT_DIR/test-reports/<task_id>-r<round>-integrated.md`；round0 首次验收，round1—3 只计实际修复；后续轮次新建文件，保留失败报告。开发停止修改并冻结唯一 manifest 后才开始测试，测试使用同一冻结输入。

## 首行与字段

第一行必须是以下之一，全文件只出现一条该判定标题：

```text
### 判定：PASS
```

```text
### 判定：FAIL
```

PASS/FAIL 表示“本任务预先要求的门槛是否满足”。缺设备、未运行、实际失败都不能写 PASS；三维适用性与 G 层必须区分 `pass / fail / not_run / blocked / not_applicable`，不得把 not_run 或 blocked 说成 DUT 实测判坏。

报告至少写：

- task_id、dimension=integrated、round、实际工作树/候选、冻结 manifest 路径与 SHA256、工具版本。
- 本任务范围、规划冻结的 functional/engineering/system 适用项、必要 G 层与阈值；逐项结果和不适用理由（必须引用规划事先给出的理由，不能临场改不适用求 PASS）。
- 实际命令、工作目录、退出码、完成标记、非空产物与原始证据路径；没有运行的命令明确标“建议”，不能放进“实际执行”。
- 独立复现：不得只读开发自述；至少一项与开发不同的判据（第三方解码器、独立解析器、独立重建、变异负对照等），并写明该判据为何能发现目标缺陷。
- 触发条件、期望/实际、可复现缺陷、影响范围。测试者不修改生产文件；必要验证副本/变异输入独立保存在 test-reports 证据目录。
- 输入漂移检查：测试前后 manifest/关键文件哈希是否变化；证据复用须写明同输入、同参数与覆盖范围，并绑定当前 manifest 新候选。
- 真实硬件观察者/时间/位流身份；纯离线任务说明上板/G3/G4 不适用的范围。缺板窗、真实数据或工具时记 `not_run`/`blocked`+`awaiting_hardware`，不得伪造实测。
- 未测项、下一动作与回退入口。

## 返回主对话

只按[传输合同](relay-contract.md)返回：`task_id、dimension=integrated、dimension_results（三维适用性/结果/G层）、verdict、report_path、manifest_path、blocked、retest`。retest 含 required_dimensions、required_checks、report_paths、input_status（same/changed/drifted）、reuse_decision_paths。详细缺陷写报告，由原开发读取修复、原规划读取更新/收尾；主只登记元数据与首行判定，不读完整报告或判断根因/复测影响。

## 判定边界

软件或文档工作包可在自身范围三维 PASS（语义、可复现、接口兼容，G3 不适用需规划事先理由）；这不证明 RTL、真实拍摄或整机通过。测试台回放 stub、软件吞吐、旧位流照片不能分别充当真实 DUT、硬件性能或新位流板测。必要真实 DUT、最终 STA/CDC/资源与候选绑定、真实硬件恢复/稳定性/性能门槛不得因节约取消。

同任务 FAIL 且 blocked 为空、实际修复不足 3 轮：续原开发修复，重新冻结后由同一测试者复测失败/受影响项；未影响证据须明确依据并绑定当前 manifest。三轮后仍 FAIL 保留 ⚠ 未通过，由原规划决定本轮范围内独立后续任务，不强制通过必要 FPGA 验收。缺必需设备/工具/资料/用户输入或额度直接 blocked 交原规划，不空转三轮、不自动重试。

并行发现输入漂移时停止引用该次结果，登记漂移并要求重新冻结；不得用旧哈希加新日志拼成完整通过。最终 STA 失败、必要 CDC 问题、帧损坏、DMA 越界或无法证明必需门槛，三轮之后也不能强制通过。
