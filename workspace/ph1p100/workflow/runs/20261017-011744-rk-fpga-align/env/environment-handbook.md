# T11.rk-align-base — FPGA 开发环境手册（从干净 shell 开始）

配套：`env/environment-inventory.json`（事实清单）、`tools/env/env_check.ps1`（自检）、`env/board-env-checklist.md`（板测）。本手册只写**可复制步骤与规则**；不修改任何全局配置。

> 修订（round2，2026-10-17）：§2 `MIPI_PHY_SIM_STUB` 断言加范围（本 run/raw G1 22/22；T07 backend 5/31）；§0/§3「唯一入口」加「CLI 脚本」范围。其余内容未变。

## 0. 30 秒上手

```powershell
# 项目根（含中文路径，命令原样可用；脚本内部自动处理）
cd C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道

# 环境自检（只读；默认日志写 run 的 env/logs/——复跑会追加日志；
#   给别人留痕时请加 -LogDir <你的目录>）
powershell -ExecutionPolicy Bypass -File tools/env/env_check.ps1

# 需要 TD 版本/命令注册证据时（临时 subst，自动撤销）
powershell -ExecutionPolicy Bypass -File tools/env/env_check.ps1 -TdProbe

# 仿真（示例：T11 写者 TB；-TbFiles 的相对路径基准是 fpga/csi2/pcie_integration/sim/，
#   所以写 tb/…，不要写 sim/tb/…）
powershell -ExecutionPolicy Bypass -File tools/pcie_integration/run_sim.ps1 `
  -Tb tb_cam_r10f_writer `
  -OutDir workflow/runs/20261017-011744-rk-fpga-align/test-reports/scratch/msim_writer_demo `
  -TbFiles tb/tb_cam_r10f_writer.v

# TD 构建（CLI 脚本唯一可跑入口：单会话 00_all；中文路径由脚本自动 subst）
powershell -ExecutionPolicy Bypass -File tools/pcie_integration/run_td.ps1 `
  -Stage 00_all -OutDir workflow/runs/20261017-011744-rk-fpga-align/test-reports/scratch/td_demo/prj
```

> **OutDir 安全规则（重要）**：上面两个示例的 `-OutDir` 是**临时 scratch 目录**（首次执行时不存在属正常，脚本会自动创建；可改成你自己包的证据目录）。**禁止**把 `-OutDir` 指向 `raw/`、`backend/`、`env/logs/` 或任何**既有证据/候选目录**：仿真会覆盖该目录的 `vlog.log`/`vsim.log`/`commands.log`/`work/`，TD 会以 `create_project -force` **重建**工程目录（会破坏冻结证据与候选身份）。

## 1. 工具与路径（只读事实）

| 用途 | 绝对路径 | 版本（实查） |
|---|---|---|
| TD CLI（综合/布局/位流） | `D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe` | TD Release_2026.2 / 6.2.3.210850（Tcl 8.6.17） |
| TD IP Tool | `D:\anlogic\TD_Release_2026.2\bin\IpTool.exe` | 同上安装 |
| BW（硬件只读入口，板测用） | `D:\anlogic\TD_Release_2026.2\bin\bw_commands_prompt.exe` | 同上安装 |
| ModelSim（仿真） | `D:\intelFPGA\18.1\modelsim_ase\win32aloem\{vsim,vlog}.exe` | vsim/vlog 10.5b ALTERA STARTER EDITION |
| Python | `C:\Program Files\Python311\python.exe` | 3.11.5 |
| GCC / tclsh | `D:\MSYS2\mingw64\bin\{gcc,tclsh}.exe` | gcc 13.2.0 / tcl 8.6.12 |
| Git | `D:\downlaod\Git\cmd\git.exe` | 2.54.0.windows.1 |
| TD license | `D:\anlogic\TD_Release_2026.2\license\Anlogic.lic` | SHA `DC19FEE6…`（缺它 → RUN-8008） |

PowerShell 5.1.26100.9711（Desktop）+ 系统 ACP/OEMCP **936**（zh-CN）。verilator 在本机**不可用**（不依赖它；仿真走 ModelSim）。

## 2. 仿真入口（ModelSim）

- 统一走 `tools/pcie_integration/run_sim.ps1`；它自动：
  1) 把 `sim/compile_checked.f` + `-TbFiles` 展开成绝对路径 `abs.f`；
  2) 若项目路径含中文 → 建**临时** subst 映射（只建自用、`finally` 撤销）；
  3) 依次跑 `vlib work` → `vlog +define+… -f abs.f` → `cmd /c vsim -c -l vsim.log -do run.do <Tb>`；
  4) 落盘 `commands.log`（含 cwd/退出码）、`vlog.log`、`vsim.log`、`run.do`。
- **`-TbFiles` 相对路径的基准 = `fpga/csi2/pcie_integration/sim/`**：写 `tb/tb_cam_r10f_writer.v`（**不是** `sim/tb/…`——后者会被再拼一层 `sim/` 而打不开，vlog-7；绝对路径亦可）。注：`run_sim.ps1` 头部注释里的 `sim/tb/…` 写法与其实现不一致（该文件属 T07 冻结输入，本包不改；已登记给后续触碰它的包修正）。
- `MIPI_PHY_SIM_STUB`（旁路厂商 serdes 原语）：**本 run/raw G1 证据**的 TB 命令 22/22 均带 `-Defines MIPI_PHY_SIM_STUB`；**T07 backend G1 证据**中只有 `tb_csi_checked` 各轮带（5/31），其余 26 条（`tb_ddr_wr_arb`、`tb_ep_bar_win_rka1`、`tb_ddr_frame_pusher_rka1`、`tb_csi_integrity_diff` 等）未带——即该 define 不是项目级"所有 TB 必带"的要求。写者 TB `tb_cam_r10f_writer` 实测**加不加均可**（未加 define 亦 `ALL PASS`）；引用 stub 端口的 TB（如 `tb_csi_checked`）请按各自既有证据命令带该 define。
- **判据看产物**：`vlog.log` 末行 `Errors: 0` **且** `run.do`/`vsim.log` 齐备 **且** `vsim.log` 有 `ALL PASS`（TB 自检）。退出码单独不足以判断（`-File` 下失败也可能 exit 0，T07 F1 教训）。
- TB 模块名 ≠ 文件名：如文件 `tb_ddr_wr_arb_peer.v` 的模块名是 `tb_ddr_wr_arb`。

## 3. TD 构建入口（CLI 脚本唯一规则：单会话 00_all）

- 命令：`run_td.ps1 -Stage 00_all -OutDir <新建目录>/prj`（OutDir 安全规则见 §0 提示：不要指向既有证据/候选目录）。
- **为什么必须单会话**：TD 的 `create_project` 才把 `device_name/package_name` 放进会话变量；另开会话 `open_project` 再 `launch_runs` 会得到空 `settings.cfg`，子流程报 `can't read "device_name"`（PRJ-8642/PRJ-8806/USR-8122 实测）。`01_create/02_syn/03_phy` 仅作参考与单步复跑预算。
- 入口脚本 `tools/pcie_integration/td/00_all.tcl`：`create_project → add_files → top_module ph1p_pcie_ep_top → launch_runs syn_1 → launch_runs phy_1 → save_best_bits`；**不执行** `download_sram.tcl`、不下载、不写 Flash。
- **完成标记（三者同时满足才算过）**：
  1) `td_commands_prompt.exe` 退出码 0；
  2) 日志含 `PRJ-1406 Run phy_1 finished` + `PRJ-1424 … saved as best result`；
  3) 控制台完成标记 **`T07_ALL_DONE`**（共享入口脚本里的文本，T11 沿用）。
- 产物在 `<OutDir>/ph1p_pcie_integration_Runs/{syn_1,phy_1}/`：判定用 `phy_1/final_timing.rpt`、`*.area`、`*.chk.timing`、`pr.db/place.db`、`*.bit`（`best_result/` 同 SHA）。
- 收尾 `report_area/report_timing` 被 skip 是**已知现象**（未 import netlist），判据用 run 目录内 TD 自己生成的报告。
- G2 门槛（T07/T11 既定）：同一最终 DB `Routed`、**setup SWNS ≥ 0 且 STNS = 0**、hold ≥ 0、资源 ≤ 器件、bit 与同次 DB/报告同源；相机字节域（cam_a/cam_b 187.5 MHz）setup ≥ 0 是**回归门槛**（当前余量薄：T11 +0.115 ns）。

## 4. 中文路径与 subst 规则

- 项目路径含中文 → ModelSim/TD 打不开，必须用 subst 映射为 ASCII 盘符。
- 规则：**只建自用、用完立即撤销**；映射目标一律是**项目/run 内目录**（不得把映射指向 D 盘或其它位置）；记录映射与撤销动作到本次日志。
- `run_sim.ps1`/`run_td.ps1`/`env_check.ps1 -TdProbe` 都按此规则实现（`finally` 撤销）。当前机器上有一个**遗留映射 `R:`**（T07 functional r2 负对照目录，dev-plan 已登记）；不属于本包，勿动，由用户/后续处置。
- TD 会在 **cwd** 写 `td_<时间戳>.log` / `.logw` → 所以 TD 的 cwd 必须是被映射的 run 目录（不能是项目根或桌面）。

## 5. 编码 / BOM 规则（本机功能性要求）

- **凡是含非 ASCII 的 `.ps1` 必须带 UTF-8 BOM（EF BB BF）**。原因：PS 5.1 + ACP=936 会把无 BOM 的 UTF-8 当 GBK 解码，中文注释可能吞掉行尾换行，导致后续语句被并进注释（T07 F1：`run_sim.ps1` 144→136 行、`$doPath` 未定义、vsim 前中止且 exit 0）。
- `.tcl`（TD 按字节解析）与 `.py`（Python 3 默认 UTF-8）**不受**该缺陷影响。
- 新增/修改 `.ps1` 后必须：① 确认 BOM；② 用 `tools/env/env_check.ps1` 复跑（它检查 3 个入口脚本 BOM 并做自身哨兵自检）；③ 记录 SHA。
- 编辑 `.ps1` 的推荐方式：保留 BOM 的编辑器；或用 PowerShell：`[System.IO.File]::WriteAllText($p, $text, (New-Object System.Text.UTF8Encoding($true)))`。
- 日志/JSON 产物用**无 BOM UTF-8**（便于 Python/脚本直接消费）。

## 6. 失败留痕规则

- 失败日志**保留不删**（TD 的失败日志、vsim 失败日志、负对照证据都留痕；本工作流明令禁止批量删除）。
- 每次运行记录：实际命令、cwd、退出码、完成标记、非空产物路径；失败时同时记"预期/实际/复现条件"。
- 判据分级用 `pass / fail / not_run / blocked / not_applicable`，不把"没跑"写成"通过"。
- 一次只改一个可解释变量；重复失败两轮后重审假设，不盲目调参。

## 7. 回退（不进不退都可用）

| 回退目标 | 入口 | 说明 |
|---|---|---|
| 旧主线（RGB565/HDMI 1080p60） | `D:\TD\work\csi2\prj\camera_rgb565_wb_20261015_002820` 既有 bit | 未被本线修改；SRAM 加载即回到旧功能 |
| T07 r3 候选 | `backend/candidate/prj/…/phy_1/ph1p_pcie_integration.bit`（SHA `0943CB36…8B0A`） | T07 三维 PASS 的候选 |
| T11 r0 候选 | `raw/candidate/prj/…/phy_1/ph1p_pcie_integration.bit`（SHA `14B32037…5686B`） | T11.rk-align-raw r0 三维 PASS 收束的候选（身份不变） |
| 源码级 | 整目录替换 `fpga/csi2/pcie_integration/` + `tools/pcie_integration/` | 不进不退；旧候选 bit 不覆盖、不重置 |

回退操作本身也要留痕（选择哪个 bit、SHA、时间）。

## 8. 明确禁止（本项目/本机）

- 不安装/升级任何工具；不改 PATH、环境变量、注册表、系统区域设置；不改全局 Codex 配置。
- 不写 D 盘：TD/ModelSim/IP 只读使用；工具产物经 subst 限定在项目/run 内（唯一例外是工具自身在 cwd 的临时文件，而 cwd 已被限定）。
- 不下载位流、不写 Flash、不改电源/跳线、不重启 RK、不发外部消息、不发布。
- 不批量删除文件/目录（含用循环/脚本包装的批量删除）；需要删除时一次一个明确路径，批量清理交用户手动。
- 不改冻结输入：`fpga/csi2/pcie_integration/`、`tools/pcie_integration/`、`raw/`、`backend/` 是 T07/T11 交付域——其任何修改只由对应任务的授权范围执行（T11.rk-align-raw r0 已收束；历史证据/候选目录永不复用为工作目录）；**同一冻结输入不得边改边测**。

## 9. 一次完整闭环的最小步骤（示例：改 RTL 后的回归）

1) 改 RTL（仅在自己的 write_scope；`rtl/checked/*` 改动要同步差分 oracle 参照）。
2) 仿真：对受影响 TB 逐个跑 `run_sim.ps1`（`-TbFiles` 相对路径基准见 §2；判据：`Errors: 0` + `ALL PASS` + 产物齐）。
3) 构建：`run_td.ps1 -Stage 00_all`（判据：exit 0 + PRJ-1406/1424 + `T07_ALL_DONE` + 非空产物）。
4) 读 `phy_1/final_timing.rpt`：setup/hold/TNS/违例端点/资源/bit SHA；与旧候选对照。
5) 冻结 manifest（含全部输入/产物 SHA）→ 交测试；**停止修改**。
6) 记录：change-report、commands、失败留痕、回退点、未测边界。
