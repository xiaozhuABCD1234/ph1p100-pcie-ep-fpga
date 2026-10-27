# dev-result.md — T11.runC-sim-campaign（P3，round0 首次，纯离线仿真）

- task_id: T11.runC-sim-campaign ｜ run: 20261019-0207_runA_ddr_readback_loop ｜ 角色: fpga-dev（opencode 子代理）
- 工作树: upstream\ph1p100-pcie-ep-fpga-wt0207（branch opencode/runC-0207；HEAD b0282d2a8dfdf11e6e63779510fe380dfffb5e83；worktree-only 6 M + 4 ??—— ?? 为 P1 新增 2 文件 + 本包新增 2 TB；未 commit/未推送）
- 范围: 仅新增 sim/tb/**（2 个新 TB）；未改 RTL/约束/构建入口/既有 TB；未改 sim/compile_checked.f（两个 TB 经 run_sim.ps1 -TbFiles 编译，无需追加行）；P2 冻结件与共享树只读

## 1. 交付物（2 个新 TB，均已跑通）

| TB | 覆盖 | 结果 | 实测 |
|---|---|---|---|
| sim\tb\tb_ddr_readback_campaign.v（17,026 B） | A) 集成级 100 帧连续循环（P=64/128/256/512 参数化小帧，逐帧唯一内容精确核对 status/words/hdr/pay/smp1/smp2；第 70 帧 busy 中幽灵发布被丢弃、runs 不额外 +1、结果不被覆盖）；B) 坏帧注入 8 项检查：magic raw（0x0132/err1）、magic 隔离（0x013A/err1）、头 CRC（0x0236/err2）、载荷 CRC（0x032E/err3）、截断短帧 len=64（0x0406/err4/words=16）、长度错 P=4736（0x0406/err4/words=1024）、AXI SLVERR 第 3 拍（0x053E/err5）、坏帧序列后好帧恢复（0x003E）；最终 runs=108 一致 | *** ALL PASS *** / Errors: 0 / vlog Errors: 0（1 条既有警告 pcie_ep_engine.v RDGN，非本包引入） | 墙钟 ~5 s（含编译）；vsim Elapsed 0:00:02；sim 时间 1.2536 ms |
| sim\tb\tb_ddr_readback_1080p.v（10,159 B） | 集成级 1080p 满帧（复用 P1 场景常量：base=0x00080000、P=2,592,000、frame_bytes=2,592,768、载荷 pattern 与头字段同模块 TB；断言不改门槛）：status=0x003E、words_read=0x0009E400、hdr_crc/pay_crc 与 TB 逐字节独立 oracle 全等、smp1/smp2=word20/21、runs=1 | *** ALL PASS *** / Errors: 0 / vlog Errors: 0（同上 1 条既有警告） | 墙钟 ~24 s；vsim Elapsed 0:00:21；sim 时间 7.3053 ms |

## 2. 运行口径（逐条满足）

- 入口: tools\pcie_integration\run_sim.ps1 -Tb <tb> -OutDir <run>\sim-campaign\msim\<tb> -TbFiles tb/<tb>.v -Defines MIPI_PHY_SIM_STUB（cwd/worktree 内；日志全量落盘 vlog.log/vsim.log/commands.log/vsim_stdout.log/run.do/abs.f）
- 时限: 单 TB ≤5 min（实测 ~5 s / ~24 s）；整组 ≤15 min（两 TB 合计 ≈29 s）——满足
- 判定: vlog Errors:0 + vsim *** ALL PASS ***（两 TB 均满足）
- 哈希同源: RTL/TB 候选 9 文件 SHA256 与 P1 manifest r1（68AB235E…）逐项全等，mismatches=0（rtl-hash-check.txt）；P3 未改 RTL——无需 P1 修复轮

## 3. 绑定与 protected

- 候选新增文件: tb_ddr_readback_campaign.v sha256=e1128cdef7368ef013c349171f179844de11dbea31fd21ade903f8e732569160（blob 0f1ab480b83733039f9333b1d16267abc3f9a912）；tb_ddr_readback_1080p.v sha256=f63c1d8ec7399fc62dbcf7d8f6713dc1e2019bbba97feefdaeba6e4d5e4cce69（blob a75f5b4a39af3d54af4e73626541705c2bb9cfd7）
- 只读核对: P2 冻结 manifest 0F67D299…6919、bit 5B67A8F5…1D52、CWC 8DDA54D4…664F、P1 manifest/diff 未动（见 manifest protected_audit）
- 回退: 丢弃 run sim-campaign\** 与 worktree 两个新增 TB 文件（默认不删；如需删除按根 AGENTS 单文件操作或交用户）；RTL/约束/构建入口/既有 TB 零改动

## 4. 边界与结论

- 零 TD / 零硬件 / 零下载 / 零 Flash / 不推送 / 无 GUI 自动化；未触碰 0212 共享树与夜间实例
- 结论: P3 仿真战役三条目标（100 帧 0 误判/0 覆盖 + 坏帧 ≥5 类全拒发无假 PASS + 1080p 保持 PASS）全部达成；本包 ready_for_test，交综合测试者独立复跑/复算