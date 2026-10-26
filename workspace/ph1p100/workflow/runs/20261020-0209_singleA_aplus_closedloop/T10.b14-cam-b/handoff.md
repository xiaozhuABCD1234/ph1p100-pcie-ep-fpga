# T10.b14-cam-b — handoff（规划冻结，2026-10-25）

状态：**ready**，尚未开发；`needs_user_input=true`（唯一问题：B 相机模块是否物理连接）。本文件交接冻结输入、操作顺序、门槛与恢复入口；设计细节见 `fpga-design-guide.md`，任务/预算见 `dev-plan.md`，机器可读派发见 `dispatch.json`。

## 1. 一句话

A 路 150 s 里 `pix_beats=0`、`line_rises=0`，但 MIPI 字节时钟和 CSI 包计数在涨；B 路的 I2C/MIPI/引脚本来就使能，只是从未接进 A+。本包把 B 的 tap 引出，用编译期 `CAM_SEL=1` 选中 B，走同一套 crop/raw/A+/export，用 v5 既有字段记录 B 的 pix/line/frame；若 B 也无像素，留证 blocked，不第二次下载。

## 2. 开工前检查（只读）

1. ModelSim 10.5b、TD `D:\anlogic\TD_Release_2026.2` 许可可用；磁盘够放一份 `a1_board` 工程。
2. 包目录内无旧候选；如存在只追加 `r1`，**不覆盖、不批量删除**。
3. 读 `T10.b13-ddr-retry/r1/result-r1.md` §4 与 `r1/board/captures/status_v5.txt`：确认 A 的 `pix_beats=0`、`line_rises=0`、`clk_tgl/pkt_tgl` 在涨、`cap/enc/exported=0`。
4. 读 `T10.b13-ddr-retry/r1/td/src/src/f9p_camera_display_core.v` L115–116、L128–129、L141–145、L182–205、L228–239：确认 B I2C/MIPI 已使能、B tap 存在、B frame/CRC 悬空。
5. 读 `T10.b13-ddr-retry/r1/td/board_p2.adc` L39–48、L64–67：确认 B 引脚已分配。
6. 不写 `workflow/tasks.json`（规划维护）、不改旧 run/manifest、不写 Flash。

## 3. 建包与冻结基线

```powershell
$pkg = 'D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b14-cam-b'
$b13 = 'D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b13-ddr-retry'
New-Item -ItemType Directory -Force -Path "$pkg\r0\changed-src","$pkg\r0\sim","$pkg\r0\td","$pkg\r0\board","$pkg\r0\diag" | Out-Null
Copy-Item -LiteralPath "$b13\r0\changed-src\*" -Destination "$pkg\r0\changed-src" -Force
Copy-Item -LiteralPath "$b13\r1\td\src\src\f9p_camera_display_core.v" -Destination "$pkg\r0\changed-src\f9p_camera_display_core.v" -Force
Copy-Item -LiteralPath "$b13\r1\td\src" -Destination "$pkg\r0\td\src" -Recurse
foreach ($f in '01_build.tcl','02_bitgen.tcl','03_cwc.tcl','a1_board.al','p2_board.sdc','board_p2.adc','a1_small_top.sdc') {
  if (Test-Path "$b13\r1\td\$f") { Copy-Item -LiteralPath "$b13\r1\td\$f" -Destination "$pkg\r0\td\$f" -Force }
}
foreach ($f in 'run_board_r1.ps1','capture_com8.py','parse_status_v5.py','dl_b13.tcl') {
  Copy-Item -LiteralPath "$b13\r1\board\$f" -Destination "$pkg\r0\board\$f" -Force
}
```

- 记 `r0/artifact-hashes.txt`：11 个源 + `p2_board.sdc` + Tcl/al/adc 的 SHA256、TD/ModelSim 版本、盘符；b13 核基线 SHA256 = `C9DE0D9C176E830DF35833EFF7E91B811D954FB5480BC13E1FB122EF23305089`。
- 不复制 `a1_board_Runs/`、`cw/`、旧 bit/CWC/BID/大报告。

## 4. 实现顺序（严格按此，不要并行改多处）

1. `f9p_camera_display_core.v`：只加 §3.1 的 B 端口/assign + `CAM_B_IDELAY_TAP`；`git diff` 必须只有端口、assign、1 个 localparam、`u_csi_b` 6 个状态 wire 连接。
2. `p2_a1_board_top.v`：`localparam CAM_SEL=1'b1` + `generate` 选择；`cam_sysstat[20]=CAM_SEL`；接 B 端口；只改注释 “B pinned/disabled”。
3. `p2_board.sdc`：只加 `mipi_b_byte_clk` generated clock 与异步组 1 行改动；其他行逐字节不变。
4. 仿真 S1–S5（见 dev-plan §4），先跑 S1（B 几何全链）和 S2（P1 三黄金），再 S3/S4/S5。
5. `01_build.tcl`/`a1_board.al` 路径改指 b14 `r0/changed-src/`；先 `syn` 1 次看 WNS/资源，再按需 `route`；`02_bitgen.tcl` fail-closed；`03_cwc.tcl`。
6. 板级：先拿用户对 §7.0 的确认；未确认 → `board=blocked`、0 下载；确认且 FTDI 在位 → 先下载 1 次 SRAM，成功后再开 COM8 150 s。

## 5. 门槛（硬）

- S1：`pix_beats=2,117,472`、`line_rises=2,192`、`frame_rises=1`、`frame_falls=1`、`crop_roi_frames=1`、`crop_groups=518,400`、`raw_len=2,592,000`、`enc=1`、`exported=1`、四 CRC+zlib。
- S2：P1 三黄金压缩字节逐字节同 b13 基线。
- S3：v5 241 B/59/VER=5/XOR/单边沿/不插帧内；`#13 bit20=1`；`#3/#4/#5` 等于 B 计数。
- S4：B 时钟停振时状态包照发、不挂死、不半帧。
- 构建：Routed 0 违例、hold≥0、period 正、ERAM+CWC≤300；WNS 目标 ≥+0.05；0 违例且 +0.003..+0.05 接受为诊断候选并记 caveat；<+0.003 或任何违例即停。
- 板级：B 的 `clk_tgl/pkt_tgl/pix_beats/line_rises/frame_rises/cap_frames` 增量 >0；再 `enc/exported` 增量 >0、≥1 帧四 CRC+zlib；B 无像素即停并留证，不第二次下载。

## 6. 不要做

- 不要“顺手”改 I2C 寄存器表、MIPI 配置、IDELAY tap、crop 几何/ROI、帧头/CRC、DDR IP/PAXI、A+ core、exporter。
- 不要用运行时寄存器/LUT mux 切时钟；不要用 A 时钟采 B 数据。
- 不要把 B 无像素写成 PASS；不要为出图放宽 checker 或 SDC。
- 不要写 Flash、不要第二次下载、不要批量删除。
- 不要动 `T10.b13-ddr-retry/**`、`fpga/csi2/src/**`、`D:/TD/work/csi2/**`。

## 7. 预算与恢复

- 开发 120 min / 60 calls；TD 3 会话、综合≤3、布线≤2、bitgen 1、CWC 1、下载 1、Flash 0；测试者 45/30。
- 恢复入口：
  > 恢复 `20261020-0209_singleA_aplus_closedloop` 的 **`T10.b14-cam-b` r0**（ready；needs_user_input=B 相机是否连接）。
  > 先读 `T10.b14-cam-b/{dev-plan.md,fpga-design-guide.md,handoff.md,dispatch.json}`、
  > `T10.b13-ddr-retry/r1/td/src/src/f9p_camera_display_core.v`、`T10.b13-ddr-retry/r0/changed-src/**`、
  > `T10.b13-ddr-retry/r1/td/**`、`T10.b13-ddr-retry/r1/board/captures/status_v5.txt`。
  > 目标：核只加 B tap/B 诊断 assign；`CAM_SEL=1` + `generate` 选 B；SDC 加 `mipi_b_byte_clk`；v5 保持 241 B/59 并记录 B 计数；
  > P1 三黄金逐字节；Routed 0 违例；板级先确认 B 已连接，再 1 次 SRAM 下载 + COM8 150 s。
- 状态回传：`result-r0.md` 明确 `status`（pass/blocked）、`board`、`needs_user_input` 是否已解决、所有哈希与计数；`lessons-r0.md` 只记可复用根因/触发/验证入口。

## 8. 已知残余风险

1. B 与 A 共用 tap 46，B 眼图未扫；若 B 有包无像素，tap 是首要嫌疑（另立包）。
2. MIPI 差分经 FEP1B C 排、子卡 A 排侧串 100R，A/B 都可能衰减（硬件条件，记录不修）。
3. B 模块连接未确认；未确认时板级 blocked。
4. B 时钟停振时 clk_cam 域复位无法被采样（与 A 现状同构）；仿真需显式初始化。
