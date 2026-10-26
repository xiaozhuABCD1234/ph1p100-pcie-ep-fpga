# T02 精确恢复入口：离线预检已完成，等待当前现场事实

**2026-10-19 后续状态覆盖：当前现场回复已收到，唯一 SRAM 尝试已超时并停止，下载 1/1 已用完。下文是执行前保存的历史步骤，不得按其中命令再次下载。当前唯一恢复入口改为 `development-result.json`、`sram-attempt-notes.md` 和 `question-sram-timeout.md`；加载状态 unknown，暂停采样，交原规划处理。**

开发角色 `/root/fpga_dev_singlea_board`。当前尚未执行 SRAM；下载计数 0/1，采样组 0/3，生产 6/6，实际修复 0。699 项逐项大小/SHA 核对无漂移，两个指定 integrated 报告分别为 B01 r0 PASS；这仅满足离线入口，不证明板级通过。`preflight.json`、`b01-input-audit.json`、`dry-validation.json` 保存实际证据。

## 当前缺项

主应把用户对 `question-t02-current-window.md` 的真实原话保存路径交给本开发角色。需当前用户能操作板卡/ChipWatcher、单相机 A 保持原接线并正常供电、JTAG 无其他任务占用。旧在场回复不代替当前事实。恢复须读取 `development-result.json` 和 `execution-budget.json`，保持已用计数；当前派发保守实际截止时间为 2026-10-19 21:33:00 +08:00。超过该截止点须由原规划明确恢复有限窗口，不能自行延长。

## 现场事实满足后，开发执行一次

先确认同候选未漂移、没有本角色尚未记录的下载，保留现场回复路径/操作者/实际时间。唯一命令如下，由开发执行；用户先不要在 GUI 中点击下载。

```powershell
& 'C:/Program Files/Python311/python.exe' -B 'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/recovery01/B01/timing-continuation01/remaining-attempts01/scripts/run_sram.py' --execute
```

cwd=`C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道`。入口自身先核对两个独立报告和全 manifest，原生 `bw.exe board/download_sram.tcl` 运行 120 秒实际 deadline，并在超时终止仅其拥有 PID 树。SRAM 模式 jtag、cable0、speed7、server127.0.0.1:5555；Tcl 必须读到 PH1P100。日志固定生成到本 run `board/sram-b01-<实际timestamp>/`。必须保存真实 PID、命令/cwd、器件原文、退出码、timeout、非空 download.log/result.json、`B01_SRAM_PASS` 和前后 SHA。

禁止自动启动 server、换 cable 扫描、自动重试、构建或 CLI 读回。入口失败时保存全部日志并停止；不得再次下载。当前预检未连接服务或设备，也未推定服务可用。

## 仅本次下载明确成功后交用户执行第 1 组

1. 打开唯一 [current.cwc](C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/recovery01/B01/timing-continuation01/remaining-attempts01/candidate/current.cwc)，SHA `b28e3d4ee476731b118da0b12c3bad8dcca1dadfbd9b7ae4dc418c4d225a74ce`；不要换线、改传感器或再下载。
2. T1：对 `auto_created_cwc1`（camera）与 `auto_created_cwc2`（DHI）分别 Instant Trigger，各保存完整实例的 32 位数值、实例名、采样时间。导出保存在本目录，或发可读清全部字段的原始截图。精确逐字探针见 `probe-reference.md`。
3. 至少 20 秒后 T2：对相同两个实例分别采样并保存完整原文，记录各自时间。跨 camera/DHI 不宣称原子同时。整组最多 300 秒；这是 1 组，包含 T1/T2 两时刻及各自两个域。
4. 回传原文件/原图和操作者、时间、单 A 接线/供电是否变化，以及实际源模式/配置/标定/已知图样依据（若持有现有记录则提供，不要求改配置）。两组针对性补样必须先有明确缺项；本候选最多总计 3 组，不自行重复触发。
5. 身份不符、DDR 校准异常、非零 fault/checker error 或软件失败时，立即保存原样并停下。不要重下、复位、断电或继续采样冲淡错误。

## 样本判定合同

两个不同 `cl_seq`，每个 `cl_words=648192`、`cl_len=2592768`，`cl_identity=0x434c0101`、`algo_identity=0x414c0101`，`cl_flags[31]=1`、`[3:0]=15`、`[15:8]=0`，`cl_fault=0`，`cl_fail_count=0`，通过计数推进。`cl_header_crc`/`cl_payload_crc` 保留真实数值；不套用合成图常数。完整保存全部 15 个 cl 字段（seq/session/base/len/words/flags/CRC/pass/fail/writer/recovery/fault/identity）及 camera 全 16 字段。

`source_geometry` 高 16 位是源行数，低 16 位是源 RAW 字节数。固定候选 ROI=(960,540,1920,1080)、SKIP_ROWS=37、PHASE=3；必须结合真实源模式/配置解释，不将源 geometry 直接当 ROI。物理 Bayer 相位无有效配置/标定/真实图样依据仍为 unknown，不能靠颜色观感/计数推定。

一次内部 abort 需 `source_injected=1`、writer_bad/拒发布路径和确切首个随后合法 good 的完整读回恢复因果（`cl_recovery_count>=1`）对应。只有最终 sticky 计数而缺必要因果时保留 partial；旧 pending 帧不算恢复。该内部注入不证明物理 CSI CRC 故障。当前无任何现场原文，以上门槛全部未测。

## 停止、后续冻结与回退

人工依赖立即返回 blocked，不空等；本文件仅为准备记录。完整 T02 现场证据齐备、停止活动、再次绑定未漂移 B01、冻结新现场证据 manifest 后，才可 `ready_for_test` 并交一个新综合测试者。G4 长稳/热态/性能仍按用户后放，不外推双路/PCIe/RK/实际图质。

现有回退 pair 仅保留路径，未执行：

- bit=`C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261018-1631_runA_fpga_side_readchannel/debug-fix3/prj/ph1p_pcie_integration_Runs/phy_1/cw/compiled.bit`，SHA `bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0`。
- CWC=`C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261018-1631_runA_fpga_side_readchannel/debug-fix3/prj/ph1p_pcie_integration_Runs/phy_1/cw/compiled.cwc`，SHA `8d2998b96ef1763c14a1302118235a687488297ce496692b1f6cd95d76981026`。

失败后先保存证据交原规划；不自动回退或循环电源，无 Flash/PCIe/RK/推送授权。
