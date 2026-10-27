# 最终输入与版本索引

实际工程 `D:\fpga\ph1p100`；本run根 `workflow/runs/20261025-180900_fpga-dual-offline-closure`。本文件是清晰可读的最终导航，原冻结input-index、dev-plan、指南和manifest保持原字节；不能按活动生产树的同名文件替换最终候选。

|用途|准确相对run路径或工程路径|采用与边界|
|---|---|---|
|用户原话/两包完整前文|`request.md`|原“上述两者…使用工作流技能…闭环”和仅独立FPGA、无RK约束|
|最初冻结材料|`planning-input-manifest.json`、`inputs/task-board-at-plan.json`、`input-index.md`|历史规划快照；当前交付以两唯一candidate manifest为准|
|格式与接口|`fpga-design-guide.md`、`dev-plan.md`|R10F v1 128B紧密RAW10、256bit AXI、四RAW槽、完整描述符/释放身份、CMP侧栏及G0/G1边界|
|真实原角色|`role-ids.json`|每任务一个开发、一个唯一综合测试者；不跨任务复用|
|额外一次开发faults授权|`user-feedback-T10-retry01.md`|累计2→3一次；3/3已用完，无第4次|
|连续恢复原话|`user-feedback-continue01.md`、`user-feedback-continue02.md`、`user-feedback-continue03.md`|同run继续，旧计数/失败不清零|
|唯一只读恢复核查|`user-feedback-readonly-recovery01.md`、`readonly-recovery01/audit.json`|一次原生状态/冻结核对历史；不是自动监控权限|
|T08最终来源|`T08.dual-local-closure/r1/mode-fix02/manifest-mode-fix02.json`及source-map|manifest SHA38e06153…；实际r1修复1，原旧candidate只作历史|
|T10最终来源|`T10.dual-aplus-scheduler/cmp-stall-fix01/static-closeout02/manifest-cmp-stall-fix01.json`及source-map|manifest SHA5db2b0dd…；真实三DUT输入，CMP改动在首次独立验收前冻结|
|T10不可变core/frame|cmp-stall-fix01/candidate/a1_deflate_core.v、a1_frame_top.v|SHA6797db05…35bb、c8b24775…a65b；不是活动b11/b13源|
|独立证据与补充来源|`test-reports/T08.dual-local-closure/r1/integrated-mode-fix02/`、`test-reports/T10.dual-aplus-scheduler/r0/`|原测试者私有TB、编译来源、原日志、oracle、复用映射；无DUT源修复混入测试夹具|
|主任务板|`D:/fpga/ph1p100/workflow/tasks.json`|收口读取最新值并只追加两任务离线证据，保留并行b13/其他候选与父状态|

所有可使用的精确完整SHA与当前/历史报告区分在 `candidate-binding-final.json` 和 `final-closeout-audit.json`，产物导航在 `delivery-index.md`。本run未访问硬件、RK、外部消息或进行TD/下载/Flash；旧生产、OpenCode、D:/TD/work/csi2与其他run没有写入授权。
