# 本轮输入与所有权

日期：2026-10-17。规划角色已读项目 AGENTS、fpga-planner/fpga-design-guide 和工作流合同。本 run 沿用 T03/T07/T11，不创建另一套全局任务板。

## 已实际核对的版本

| 输入 | 位置/提交 | 本轮核实与边界 |
|---|---|---|
| 用户原话 | `request.md` | 授权自行裁决适配分工、先备份、结合 FPGA 版本、RK 修改清单、必要真实板验；没有发布/Flash/外部消息授权 |
| 补充 | `user-feedback-01.md` | 用户当前已经使用 6.2.3，CLI IP Tool 可用，控制基本都通；不再将旧 CLI 不通列为本轮前置 |
| 当前项目 | 项目根，分支 `codex/ddr-timing-margin`，HEAD `ba0fca5f2c397db88059040b2ffe55c76867da31` | dirty 修改主要属上一 TD/IpTool run；不得覆盖、reset 或提交这些修改 |
| 用户 GitHub | `https://github.com/chenzhenzhong12138/fpga-stereo-vision`，origin/main=`3862a9beef2081bbd45f8bf54d7f3b4844e3b248` | `git ls-remote`、本地对象核实，远端最后提交 2026-10-15；当前本地明显更靠后，禁止用远端覆盖本地。2026-10-17恢复只读复核：远端 main 已前进到 `e5d6afd05d26a91737c2548c6d06688f48022a02`（本地对象库无此对象）；仅登记漂移，不fetch/合并，构建仍以本地 `ba0fca5f` 工作树为准 |
| 队友 FPGA | `https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-fpga`，HEAD/main=`2a4b253d9f2e56a943f1667b2a7a366824dcba34` | 2026-10-17 `git ls-remote` 与参考库 origin/main 一致；实际读取 pusher、BAR、writer、README 和树 |
| 队友 driver | `https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-driver`，HEAD/main=`a0215c5a2fcb95bfc867a4768d4831d68edf64a2` | 同上，实际读取 ioctl/frame 源码；尚未声称 RK 机器已运行这些版本 |
| 参考 Git 对象 | `C:/Users/czz/AppData/Local/Temp/opencode/ref_ph1p100_fpga` 和 `ref_ph1p100_driver` | 仅只读输入；开发将精确提交 archive 到本 run，后续不依赖 mutable temp checkout |
| 活动硬件工程/回退 | `D:/TD/work/csi2/prj/camera_rgb565_wb_20261015_002820` | 已读 input_manifest；本轮只读，不覆盖、不自动同步。备份有关源码、约束、manifest、bit/CWC，准确记录原位路径 |
| 本机 TD | `D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe`、`IpTool.exe`、`td.exe` | 文件存在，版本/实际命令标记由开发独立核验。6.2.3 用户补充优先于旧 README |
| 既有 Bayer 工作树 | `C:/Users/czz/.codex/worktrees/bayer-codec-reference/FPGA创新设计赛道`，HEAD `1994131589466af7713c1641d34a16d7d3931e63` | `git worktree list` 核实，存在未提交 codec/gaussian/C2H 内容；严格只读，不复用该角色对话，不合并覆盖 |

网页匿名访问三仓库均 404；实际 Git 凭据访问成功，不能误报仓库不存在。引用版本以 Git 对象为准。队友 README/提交的 SWNS/上板推帧成功是外部自述，不是本轮证据。

## 任务与已有材料

- 主源：`workflow/tasks.json`、`workflow/README.md`（G0—G5 与 5.1）、`CODEX_HANDOFF.md`、`README.md`。
- 现任务：T03 ready、T07 backlog、T11 backlog；父任务还未完成。T01 表中旧工具阻塞与用户补充冲突，本轮不改其独立 run 的结果，不让它阻塞 AXI 独立集成候选。
- 读过：`workflow/runs/20261016_2110_pcie_unified_path/pcie-unified-path-assessment.md` 及 `pcie-unified-path-addendum-20261017.md`；后者引用上述相同 peer HEAD，但本轮已重新核对关键源代码。
- 读过：`docs/DeepSeek独立检测与现行方案整合_2026-10-16.md`、`docs/superpowers/plans/2026-10-15-fpga-remaining-strategy.md`。
- 帧合同：`parallel/frame/frame_contract.py`、`parallel/docs/帧与元数据接口合同_2026-10-15.md`；PCIT/TLP oracle 在 `parallel/pcie/`。
- 本方 CSI：`fpga/csi2/src/csi/csi_rx_packet_handler_checked.v`、`csi_rx_packet_integrity.v`、`csi_rx_10bit_unpack_checked.v`；相机/IP 依赖由现有 `fpga/csi2/prj/camera_peer/` 与活动候选 manifest 确认。
- 本方 preview/DDR：`fpga/csi2/src/mem/` 是 PAXI，不可直接插入 peer AXI pusher。`f9p_camera_capture_core.v` 的 cap_data 是预览字节，不是完整 RAW10 接口。

## 未决而不阻塞独立工作

RK 连接/执行通道、BDF/内核/MPS/IOMMU 与实际帧接收证据未知；先形成可交给队友的补丁、参数与验证步骤，不能擅自 SSH/安装/重启别人的机器。已连接 FPGA 的实际 JTAG/UART 可用性需工具查询。双方正式 G0 签收、最终压缩规则口径不假定已经完成。

## 有界 DeepSeek 辅助

任务 `093fce48be714036ab78116c94230d1d` 只收到给定控制位/槽头片段与数值。其两个不必要执行请求已分别拒绝并真实 resume 一次；返回算术表已完成。独立审查发现它混淆 host 槽头填充与 R10F 头，给出错误 ARM 示例及无条件无跨界结论；不采用该答复作为设计或验收证据。本文和指南的数值由 Codex 按原式复核。
