# T06链路存储审查派发补充

本文件只把原dev-plan的T06包置为下一可执行项，不新增任务或语义步骤。依赖T02.chain-input-review已独立round0 PASS，实际修复0；其PASS指审查完整性和结论可靠，不表示设计已修好或硬件已过。

新开发只执行原T06的5步，写本run/T06.chain-storage-review/**；冻结后由一个新的综合测试者验收。本包新角色，不复用T02开发/测试者。保持batch=1和30次工具/45分钟，读搜60秒、静态/微仿真300秒真实deadline；硬件/TD/其他活动run全部保护。

## 必须消费的相邻契约

- T02-F01已确认样本lane向量与packed RAW10直连不等价。T06只跟踪其store/feeder字节保真及格式边界，不实施重打包修复，也不把错误格式导致的编码数据解释为DDR读错。
- T02-F02/F03已确认CSI晚裁决未接入A+，crop最后ROI样本置done还留源行后缀。T06须检查slot是否过早READY/可编码、最终写是否可见、坏帧/晚abort是否有资格撤销，以及完整帧发布/所有权保护；不能建议只OR晚abort而忽略已被消费者领取的帧。
- T02-F04区分capture序号与admission序号；结合满队列、retry/purge/reset核对序号/epoch与旧响应隔离。T02-F06的本域复位/PHY恢复缺口仍保留，不把FIFO自带复位同步当整个bridge/store已签核。
- b15原生PAXI地址/mask/读写接纳差异、响应/purge、Gray约束与模型资格仍按统一baseline审查。b17和1080p30活动线的新改动不并入此快照，不重复其实现/四帧长仿真。

## 证据和控制版本

只读引用T02 manifest-r0.json（SHA256 `af32567395a3083b3b5005df40cfc37857f54b133293a644782eca9d6a34b997`）及对应独立报告（SHA256 `c96751cda203daf4c53a47909760f7d5b2edd3b88abdedbda0e625d67d2fb920`）、review/findings/source-map。T02补冻13项相机依赖可只读引用；补充其他必要源须在本包另冻SHA与复制前后一致性，不改统一baseline。

已验包的controls/**保存当时原需求/计划/派发副本。原规划为下一包更新当前dispatch/handoff是合法状态流转，不能据此重写旧manifest或认为旧候选冻结文件漂移。T06应冻结自己开始时的控制副本，并在本包测试期间保持输入不变；引用T02旧报告只覆盖其原冻结候选。

原计划的所有T06验收项不变：逐检查点完整覆盖，确定性结论有冻结源码/触发依据，至少1个可复查离线见证，独立测试使用不同判据；结果可为confirmed_issue/evidence_gap等，审查PASS不关闭父T06或整链路。后续T10/T11仍待依赖PASS后原规划派发。
