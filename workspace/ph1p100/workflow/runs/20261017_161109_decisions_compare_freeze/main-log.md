# main-log — run 20261017_161109_decisions_compare_freeze

- 261017 1611 初始化run。PROJECT_ROOT=`C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道`；OUTPUT_DIR=`workflow\runs\20261017_161109_decisions_compare_freeze`；SCRIPT_FILE=requirement.md（用户原话+候选清单+冻结语义）；BATCH_SIZE=1；所有者=用户。阶段：规划派发。
- 261017 1611 背景：用户要求对现存决策差异做对比裁决并冻结（重开触发=出问题/优化窗口/新证据）。并行在研：集成 run E1 派生（ses_eb725571fffetnb0hW1sGdXUWb）进行中；本任务只读、不干扰。
- 261017 1611 派规划者执行决策对比与冻结登记（PLANNER_D ID=ses_eb7156decffeG9nZxjZAeMV8mk，后台）。
- 261017 1617 用户新增显示目标（原话："还有显示目标我现在看来可以下一步尝试到达4Kp30，也写进来吧"）。处理：写入 requirement 附录2；并入登记第 3 项（显示目标与资格）按用户既定方向（当前 1080p60 基线 → 下一里程碑 4Kp30 尝试）。待 PLANNER_D 返回后补发续接修订（若其本轮未含）。
- 261017 1625 决策登记完成（PLANNER_D=ses_eb7156decffeG9nZxjZAeMV8mk）：`decision-register.md`（FD82CE89…）+ `user-summary.md`（127DA65F…）。要点：M1a DDR 主线默认 **1333** 待 E2 裁定；M1b PCIe 后端轨道 **维持 800E/AXI**（rk-fpga-align 候选已按此构建）；M1c 全局单一定案延后至组合窗口；M2 统一路径=我方 csi2 主线+引入队友后端、HDMI 留调试出口；M2a–e 接口子项冻结（双路单引擎+轮换默认/RAW10 保持/帧长 2,592,768/128B 对齐必修/bit4 以新 FPGA 为准）；M3 显示维持 1080p60（降档=触发式备选）；M4 工具链 6.2.3-forward、BW 不装、IP 生成流程固化；M5 悬置项处置。需用户：①频点终选（E2 后）②BW 确认 ③官方速率问题单（可选）④主线追认 ⑤联调窗口。时点修正：E2 实为未开始；后端候选已选 800E/AXI。
- 261017 1625 用户 4K30 显示目标补丁：派 PLANNER_D 续接修订 M3（依据 requirement 附录2）。
- 261017 1630 M3 修订完成（4K30 补丁）：`decision-register.md`（4DC44C4D…，新增 §3.4 影响面 + §10 修订记录 rev1）、`user-summary.md`（AF75B9C5…）。M1/M2/M4/M5 未动。M3 正式版="1080p60 工作基线保留 → 下一里程碑 4Kp30 显示输出尝试"；影响面≈297MHz/2.97Gbps per lane（HDMI 1.4 340MHz 内）、DDR 读侧≈0.5GB/s 无压力、742.5MHz 资格议题升为关键前置。
- 261017 1828 用户指示"决策登记一下"（对上一条授权的登记诉求）：派 PLANNER_D 续接登记 **rev3**——①上板验证已授权并启动（用户在场；SRAM 纪律；board run 工作包 F）②TMST-7700 调查已启动（M5.7 更新为"调查中"）③0.300ns 优化窗口/4Kp30 立项/登记同步 docs = 触发式未排期。
- 261017 2025 派 PLANNER_D 续接登记 **rev5**（依据 board run 证据与三份测试报告）：上板验证=完成/通过（图像+颜色目视 G3 基本达成、短窗稳定）；间歇性 DDR 校准=观察项（含处置与重开条件）；1600ctl 对照=用户明确不做（关闭）；ChipWatcher 计数升级=触发式可选。
