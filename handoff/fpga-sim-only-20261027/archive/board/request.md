# 用户原始需求（显式启动新 run）

当前 P4 完成并验收后，沿同一工作线继续板级集成。复用已通 A/B 工程，将 P4 接入真实相机、DDR 和 PCIe，补齐板级顶层、时钟复位及必要跨时钟连接、引脚约束和构建入口，完成整机 bit。下一目标是先 B 后 A 的真实单路压缩帧 PCIe 完整导出。以推进度为先，长稳和非阻塞优化后置。

承接事实：P4 为 ⚠ 未通过（r2 functional+system pass 但 G2 fail 112 端点/WNS −0.637ns；r3 G2 0 端点/WNS +0.072ns 但派生变体等价 fail）。功能基线必须用 r2 候选（manifest DFAB7F9D…），禁止用 r3 派生变体作功能输入；整机 bit 必须有自己的真实顶层 STA；未出 bit/未上板的事实不得改写为通过。

沿用正常防死循环的5倍额度；Flash=0；不动 b18/b19/b20 与其他活动 run；TD/板卡/下载额度独立冻结。

需求与边界全文：D:/fpga/ph1p100/workflow/runs/20261026-2138_fpga-integrated-delivery/follow-on-run-request.md

# 用户确认

用户在 2026-10-27 07:26 的选择：⚠下开板级新run，沿用5倍额度（推荐）。即同意在 P4 ⚠ 未通过的前提下启动板级集成新 run，并沿用正常防死循环的 5 倍额度。

# 机械登记

PROJECT_ROOT=D:\fpga\ph1p100
RUN_ID=20261027-0726_fpga-board-integration
OUTPUT_DIR=D:\fpga\ph1p100\workflow\runs\20261027-0726_fpga-board-integration
上游 run：D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery（已收尾；P1/P2/P3=PASS，P4=⚠）
功能基线 manifest：D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\INT.P4-r2-manifest.json（DFAB7F9D…）
禁止：r3 派生变体（algo_rowwin3_p4.v 等）作为功能输入；把 r2 功能 PASS 与 r3 时序 PASS 拼成 P4 PASS；把 b20 bit 当本交付 bit；把文件回放/仿真写成真实 PCIe 传输。
BATCH_SIZE=1（用户未指定其他值）
按当前 AGENTS.md 及 fpga-orchestrator 技能执行；删除禁令、完整DeepSeek约束与权限边界继续有效。
用户额外授权：正常防死循环预算的5倍，仅限当前新任务；不改变任务/包/层上限。
