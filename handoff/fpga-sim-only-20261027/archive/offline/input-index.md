# 输入与所有者索引
本轮 run_id=20261027-060708_fpga-parallel-offline-delivery；实际根 D:/fpga/repos/ph1p100-pcie-ep-fpga；唯一需求 D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/request.md。规划时间 2026-10-27；所有旧 run 只读。本轮不是历史 run 的续修，不继承它们的额度/真实角色 ID。

| 类别 | 准确入口/采用方式 |
|---|---|
| 根规则/现行交接 | D:/fpga/repos/ph1p100-pcie-ep-fpga/AGENTS.md；D:/fpga/repos/ph1p100-pcie-ep-fpga/docs/PROJECT_SYNC_20261027.md |
| 工作流规则 | D:/fpga/repos/ph1p100-pcie-ep-fpga/workspace/ph1p100/.agents/skills/fpga-orchestrator/references/{work-limits,relay-contract,report-contract,project-context}.md；后者历史根仅导航，实际根以上述为准 |
| 角色 | D:/fpga/repos/ph1p100-pcie-ep-fpga/workspace/ph1p100/.agents/skills/{fpga-planner,fpga-design-guide,fpga-dev,fpga-tester}/SKILL.md |
| 本轮控制文件 | D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/{request,input-index,fpga-design-guide,dev-plan}.md；D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/dispatch.json |
| 全局历史任务板 | D:/fpga/repos/ph1p100-pcie-ep-fpga/workspace/ph1p100/workflow/tasks.json；仅作 T03/T04/T08/T10/T11 归属，不覆盖快照或旧主任务板 |
| 当前 PCIe 真正生产后端 | D:/fpga/repos/ph1p100-pcie-ep-fpga/rtl/ep_side/ddr/ddr_frame_pusher.v；D:/fpga/repos/ph1p100-pcie-ep-fpga/sim_do/tb_ddr_frame_pusher.v；本轮只读 |
| 固定 P2/P3 来源 | D:/fpga/repos/ph1p100-pcie-ep-fpga/workspace/ph1p100/fpga/csi2/src/integrated_delivery/{aplus_pcie_egress_adapter,dual_channel_capture_scheduler}.v 及各自 tb；INT.P2-r0/INT.P3-r1 manifest 与同 run test-reports 绑定，不从活动 P4 拿未冻结新变体 |
| 固定解码参考 | D:/fpga/repos/ph1p100-pcie-ep-fpga/workspace/ph1p100/tools/integrated_delivery/a1u1_decode.py；该检查器仅基础解析，严格逆变换使用下列交接包 decoder/ref，不把其 exit0 当所有 CRC/像素均通过 |
| 历史真实 B 样例 | D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/rk-a1u1-b18-20261026/{README.md,expected.json,provenance.json,SHA256SUMS,decode_sample.py,reference/a1_ref.py,reference/a1_inflate_strict.py,samples/b18_b_1080p.a1u1} |
| A+ 软件基准 | D:/fpga/repos/ph1p100-pcie-ep-fpga/tools/codec/{a1_ref.py,a1_inflate_strict.py}；固定 Huffman/LZ77/stored 参考，A1T1 record 不是 A1U1；禁止把模型结果当 FPGA/H-only 实测 |
| 已完成自由运行相关成果 | D:/fpga/repos/ph1p100-pcie-ep-fpga/workspace/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/T08.dual-local-closure/r1/mode-fix02/；用其中 candidate RTL、dual_local_closure.v、sources.f；源表中的旧绝对路径只读映射到此 checkout 快照并逐项 SHA核对 |
| 旧独立验收/边界 | D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/{candidate-binding-final.json,T08-offline-handoff01.md,delivery-index.md}；T08 r1 PASS manifest=38e0615341330aa5b8f1e0e1f9ecf4e169abbdc6bc4856912b9e4f929bdfcce3，报告=71ef63293bd253182ad23f04ac8889a29e1d7be8bc0a7cc4869dc12bb0e472aa；这些哈希是旧收口声明，开发还须重算对应快照文件，不声明规划已全量复验 |
| 活动 P4 所有者范围 | D:/fpga/ph1p100/workflow/runs/20261026-2138_fpga-integrated-delivery/dispatch.json 指向原开发第三次时序修复；D:/fpga/ph1p100/fpga/csi2/src/integrated_delivery/**、tools/integrated_delivery/** 均保护 |
| P4 仅作缺口定位 | D:/fpga/ph1p100/workflow/runs/20261026-2138_fpga-integrated-delivery/{INT.P4-protocol.md,INT.P4-shortest-steps.md}；规划读到 r2 文档，不把它当 r3 最终结果；非授予 ready=0 与槽仅 zlib 的接口缺口是本轮定位依据 |
| 活动 H-only/A+H | D:/fpga/ph1p100/workflow/runs/20261027-055621_fpga-honly-td-and-ah/{request,input-index,fpga-design-guide}.md 已存在，dispatch 在规划读取时尚未存在；不推断其完成/失败；该 run 与原 H-only 全域保护 |
| 工具 | Python C:/Program Files/Python311/python.exe；ModelSim D:/intelFPGA/18.1/modelsim_ase/win32aloem/{vlib,vlog,vsim}.exe 已发现；安装目录只读、每包独立库/日志；未运行任何仿真或 TD |
| 状态/工作树 | git worktree list：本根 main HEAD 9c624846d2313d4abf0fc89616d2e652d9ae4165；git status --short 仅 ?? workflow/（主已创建本 run）。未发现本根生产 dirty 修改，不授予覆盖其他目录权限 |

尚缺的必需输入：当前交接真实 B 帧明确 sensor_pixel_oracle_verified=false、物理相位 unknown、540 stored 回退块；它可复现传输，不能算来源/像素正确性已验证的收益图集。规划两次有界定位未找到已合格本地真实 RAW10 图集，第三包实测阶段因此受输入门槛限制。不得将 CONTENT=2/N、“自然内容”命名或合成 ramp 当实拍。

冻结方法：开发在各包 inputs/source-binding.json 登记实际采用的绝对源路径、SHA/大小/作用/原manifest与映射。所有编译文件逐项绑定；可只复制本包真正参与文件，不复制整个工作区。活动源码不可作未绑定输入；输入漂移停止并返回原规划。

