# T10模型容量错误：外部阻塞与准确恢复入口

原角色 `/root/fpga_dev_dual_scheduler_180900`。主转来的真实原生错误原文：

> Agent errored: Selected model is at capacity. Please try a different model. This agent's turn failed.

本次归类API_ERROR/外部模型容量阻塞，不是DUT失败、实验超时、任务完成或实际ID失效；工具建议换模型不构成人类换模型授权。规划不自动重试、不换模型、不新建替代角色，不查询角色进度或模型状态。T08仍续原派发，未收到其返回，不推断状态。

## 本次必要只读复核

仅核对收到错误的T10 `cmp-stall-fix01/**` 已存在文件/终结回执，非周期监控；没有新仿真/编译/硬件、没有运行finish.py或改源码。读到window.json：本实现窗口21:44:26.9726768至22:44:26.9726768，工具30、compile2、case5上限，不能因容量中断重新开始60分钟。

已有result/handoff及evidence/summary、源码快照和原命令日志。日志记录新compile1、case5已结束：旧CMP真实反例、修正矩阵8帧、small nominal14帧、有效跨word负对照、full A/B2帧。开发结果文件说明24个正向帧已严格解码、长度CRC/图案一致；这只是现有局部结果，规划未重跑，也不是独立验收。原faults suite增量0，累计faults3/3；known compile5（旧4+新1）、case16（旧11+新5）。新窗口case5/5已满，后续不可再启动任何case。

尚无manifest-cmp-stall-fix01.json、execution-accounting.json和本轮最终停止/活动数返回；因此不能派首次综合测试者，也不能把开发result的“locally ready after freeze”当作实际冻结完成。当前完整本阶段工具调用计数未知，保留unknown，不能按命令行数或现有文件数量估成0。旧历史完整calls亦unknown；保持原37、恢复期已知13native/8wrapper、静态9及已有记录。

## 恢复条件与允许动作

必须有真实容量恢复条件或用户新的继续输入后，才由原规划明确一次续接，不能用wait超时触发重试、不能自动轮询容量。优先同原开发ID/同模型；只有真实ID错误才按既有文件恢复映射，容量错误本身不允许换人或模型。

若恢复时仍在22:44:26.9726768之前且原窗口工具余额足够：只完成必要静态收尾，不改RTL/TB/模型/runner，不再仿真/编译；从原上下文恢复本阶段实际计数，核对compiled-source和24帧及两个负对照已有证据，生成新真实manifest/计数/停止声明并回原规划。当前case5/5无余量，原faults3/3不变，即使compile还剩1次也没有追加编译的需要或本恢复动作授权。

若原deadline已过、工具余额不足或计数无法恢复：原规划可在原交付授权内冻结一个仅元数据收尾的有限窗口，明确新静态账并保留旧终止事实；不能继续旧实验窗口或倒填原冻结时间，不能删旧guard、重做case或伪造作者声明。任何manifest生成工具不得调用编译/仿真。具体续接前仍需外部容量条件恢复，不自动重试错误。

真实新manifest、当前source与compiled输入绑定、结束回执/停止声明和本次历史账齐备才回原规划核准首次独立round0；原独立tester预算45调用/60分钟、compile2/case20仍未使用，不挪来补作者未冻结产物。G2/3/4仍未运行，父T10不升级。

稳定问题 `T10.dual-aplus-scheduler:API_ERROR:selected-model-capacity`；此为新外部问题，不抹原CMP-stall修复问题历史或故障次数。准确文件恢复入口就是本文件，加descriptor-corrections01-plan.md、cmp-stall-fix01/window.json和现有result/source-map/evidence/commands.jsonl。
