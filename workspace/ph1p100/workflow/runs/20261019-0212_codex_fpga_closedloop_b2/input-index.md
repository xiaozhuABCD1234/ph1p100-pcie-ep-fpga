# 本轮输入索引（2026-10-19，Codex）
本轮唯一需求原文：C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/request.md。实际宿主 Codex；原文最后一句将 OpenCode 任务改为 Codex。本轮沿用项目角色技能，不探测旧 OpenCode ID、不声称续接旧会话。

## 已采用的准确输入
| 输入 | 位置与采用版本 |
|---|---|
| 项目规则 | C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/AGENTS.md；.agents/skills/fpga-planner/SKILL.md、fpga-design-guide/SKILL.md；fpga-orchestrator/references/work-limits.md、relay-contract.md、runtime-calls.md、codex-calls.md、report-contract.md |
| 基线结论 | C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261018-1631_runA_fpga_side_readchannel/handoff.md、final-summary.md、user-summary.md；2026-10-19 finished。Tier-1 PASS、G3 partial、G4 not_run |
| 基线冻结候选 | 同基线 debug-fix3/candidate-manifest.json、debug-build2/candidate-manifest.json、board-readback/candidate-manifest.json；最后板读 integrated r1。bit bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0；CWC 8d2998b96ef1763c14a1302118235a687488297ce496692b1f6cd95d76981026 |
| 当前生产检出 | C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/upstream/ph1p100-pcie-ep-fpga；branch codex/raw10-rka1；HEAD b0282d2a8dfdf11e6e63779510fe380dfffb5e83；四项未提交修改逐项 SHA 与基线 debug-fix3 完全一致（见下表），属于该基线已有成果 |
| 未集成读回核心 | 上述生产检出 rtl/ep_side/ddr/ddr_frame_readback_checker.v（SHA256 436BE8E6BFD70FFA62B015CF393B30B2790A341B3229D4BAF6C191E1520FE9C7）；对应 sim/tb/tb_ddr_frame_readback_checker.v；来源 C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261018-1347_runA_offline_sim/ddr-readback-checker/；T11.runA-readback-checker r0 integrated PASS |
| 三算法真实RTL | C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/fpga/csi2/src/img/；权威冻结 C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261017-011744-rk-fpga-align/algo/candidate-manifest.json，SHA256 2195641AC491104549C2BDE4EC0EEC95D6519BC2B585B4576D5D4FD078E6A5F8；对应 test-reports/T09.rk-align-algo-r1-integrated.md，模块级 G0/G1/G2 PASS |
| 算法参考/入口 | C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/tools/algo/{oracle_algo.py,gen_algo_vectors.py,gen_ref_vectors.py,run_g1.py}；上述 algo/build-entry.md、source-provenance.json；parallel/algorithms/image_algorithms_ref.py 只读。旧 runner 写死旧 run，必须在新 run 使用受控副本，禁止往旧证据目录输出 |
| 生产协议与KIT | 生产检出 docs/protocol/rka1-r10f-v1/contract/、tools/bringup/{registers-plan.md,expected_rules.json,run_record.schema.json,parse_dump.py}；保持 R10F v1 与寄存器已有语义 |
| 同步电气/角色依据 | C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/docs/当前硬件_引脚电气与同步证据.md §5–6；共享 HS/VS 内部连通仍需实证，离线配置候选不是硬件同步证明 |
| 项目主源 | C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/tasks.json；workflow/README.md §5.1；README.md、CODEX_HANDOFF.md 的旧摘要按日期阅读，不覆盖最新 run 证据 |
| 工具 | D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe；D:/intelFPGA/18.1/modelsim_ase/win32aloem/vsim.exe；C:/Program Files/Python311/python.exe。本次只确认文件存在；版本由开发/测试实际命令记录 |
| 其他工作树 | C:/Users/czz/.codex/worktrees/bayer-codec-reference/FPGA创新设计赛道，HEAD 1994131589466af7713c1641d34a16d7d3931e63；只读。本轮不需要向其写入 |
| 相邻run | C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0207_runA_ddr_readback_loop 只见 request/main-log，非本轮执行输入，不续接、不覆盖 |

## 起始 dirty 所有者核对
根工作区 HEAD=27c596b01cd961dfa9d0850e4fbf879fe249de90，branch codex/ddr-timing-margin；已有规则、文档、工具、任务板及多个 run 修改，均保护。唯一允许的 RTL 写树是上表 production 检出，保留基线四项，不 reset/clean、不自动提交既存修改。
| 生产检出基线相对路径 | 起始 SHA256 |
|---|---|
| rtl/ep_side/img/ep_bar_win.v | 285FC9F009BD5C2481DBC25EE1C7DDD809A70B328B12DCA63C0BD59BAF581717 |
| rtl/ep_side/pcie_ep_engine.v | 4C9D2E35D181929393B55047E67CFE59D389AFE19D06032AC3EC95C9DECA9B85 |
| rtl/ep_side/ph1p_pcie_ep_top.v | 006932297DE30921295538A5A3C448001D254F0D617B7C487BF1A38B23F189A9 |
| sim/tb/tb_ep_bar_win_debug.v | 3AA3E11B49EC57652EFDC88F34C5D6E8B7A30E640CFCC2549E4B3DADC5A6355E |

## 有证据的现状与未决边界
1. 单A已接是基线已确认事实；本轮不重复访谈。不据旧 SRAM 状态推断此刻板仍通电或用户在场；新板验需操作者/时间/候选身份。
2. GUI ChipWatcher 两样本是唯一已证读回通道。基线 CLI 读回四次失败后关闭，不再试 UART、盲目 JTAG 读寄存器或 CLI CW。
3. 基线 last_lines=2192、last_wc=4830；源码 ROI W=1920,H=1080,X0=960,Y0=540,SKIP_ROWS=37，SRC_BAYER_PHASE=0 占位。几何/相位未板证；不得把 WC 转成图像宽度直接证明有效图或相位。
4. 源码顶层把 32bit good/bad/hdr/crc 的低8位拼入 word6，且采用多位两级采样，只可诊断。新控制/完整性证据须用源域相干快照/握手；低8位回绕不能直接算不单调。
5. T09 父任务当前 done 指模块级范围；本轮生产接入是该任务新局部包，不重开另一全局ID，也不把旧小顶 G2当新生产 G2。
6. T02/T06 板级仍待证，T08 双路硬件仍未做。本轮不动 T10 压缩、PCIe/RK、深度/NPU、长稳优化。
7. DeepSeek 已做一次纯文字采样模板整理（task 509a1a83f1ea4af698134f22382cf1fb，completed，1127 API tokens）；无执行请求、无项目文件访问。仅向其发送本轮相关事实。其建议经规划者改写，不作技术/验收判定。完整原建议保存在 deepseek-checklist-draft.md。

## 2026-10-19 B01 r0通过后的T02即时板验
- 当前独立报告：test-reports/T06.codex-ddr-readback-int-r0-integrated.md、test-reports/T09.codex-production-int-r0-integrated.md；r0各PASS，实际修复0。
- 当前699项冻结manifest：recovery01/B01/timing-continuation01/remaining-attempts01/candidate/manifest.json；SHA c7a40897166467f2beafb096701dba9cf836e1007d77ae03d90009d06f80d757。
- 当前board-entry与bit/CWC/DB/probe-map：同remaining-attempts01下；原样保留，不覆盖。
- 新T02：t02-board-plan.md、dispatch-t02-board-entry.json、question-t02-current-window.md、board/t02/two-capture-checklist.md、planner-state-t02-entry.json。
- 当前计数：test-reports/independent-b01/attempt-ledger.json，生产6/6；旧限制/旧report保留历史；真实板样本尚无。
