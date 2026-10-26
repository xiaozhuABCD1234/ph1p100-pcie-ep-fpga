# T10.b7-cam-diag 交接（r0-diag）

状态：**ready，尚未开工**。本文件只交接冻结输入、操作顺序与判据；设计细节见 `fpga-design-guide.md`，任务表与门槛见 `dev-plan.md`。

## 1. 一句话

b5 r1-diag 的 8 个计数器 60 s 全 0（`cap_frames=0`），只能说明“卡在相机前端”。本包把相机核**已有**的 I2C/PHY/帧状态引出，加 1 个 clk_cam→clk_a1 邮箱和 1 个 sys→clk_a1 邮箱，扩展空闲状态包到 97 B v2，重建候选并做**唯一 1 次** SRAM 下载 + 60 s 采集，用计数器明确回答：MIPI 有没有数据 / I2C 有没有成功 / crop 有没有收到帧。

## 2. 开工前检查（只读）

1. ModelSim 10.5b 可用；TD `D:nlogic\TD_Release_2026.2` 许可有效；磁盘够放一个 `a1_board` 工程。
2. 包目录内无旧候选；如存在只追加 `r1`，**不覆盖、不批量删除**。
3. 读 `T10.b5-a1-htab-pipe/r1-diag/result-r1diag.md` §3/§7/§8，确认 v1 包格式、61/61、`cap_frames=0`、LED1 不可信。
4. 读 `T10.b6-a1-htab-nw/r0/result-r0.md` 与 test-report，确认 b6 core `6797db05…35bb`、bit `a2757d40…ffa2` 是 A1 基线。
5. 不写 `workflow/tasks.json`（规划维护）、不动 `D:\TD\work\csi2`、不写 Flash、不做第二次下载。

## 3. 建包与冻结起点

```powershell
$pkg = 'D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b7-cam-diag'
New-Item -ItemType Directory -Force -Path "$pkg\r0\changed-src","$pkg\r0\sim","$pkg\r0\td","$pkg\r0\board" | Out-Null
$b6 = 'D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b6-a1-htab-nw\r0\td'
Copy-Item -LiteralPath "$b6\src" -Destination "$pkg\r0\td\src" -Recurse
foreach ($f in 'a1_eng_top.v','a1_small_top.sdc','p2_board.sdc','board_p2.adc','01_build.tcl','02_bitgen.tcl','03_cwc.tcl') {
  Copy-Item -LiteralPath (Join-Path $b6 $f) -Destination (Join-Path "$pkg\r0\td" $f)
}
$d1 = 'D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b5-a1-htab-pipe\r1-diag\changed-src'
Copy-Item -LiteralPath "$d1\a1_uart_export.v"     -Destination "$pkg\r0\changed-src\a1_uart_export.v"
Copy-Item -LiteralPath "$d1\camera_a1_uart_top.v" -Destination "$pkg\r0\changed-src\camera_a1_uart_top.v"
```

在 `artifact-hashes.txt` 记录：上述每个输入文件的 SHA256、TD/ModelSim 版本、盘符；并记录**没有**复制 `a1_board_Runs/`、`cw/`、旧 bit/cwc/bid。

## 4. 实现顺序（严格按此，不要并行改多处）

1. `cam_diag_mailbox.v`（新）——先单独仿真：慢侧数据变化后，快侧最多 3 拍拿到；慢时钟停住时快侧保持最后值。
2. `f9p_camera_display_core.v`——只加 §3 的 output 与末尾 assign；`git diff` 必须只有端口行和 assign 行。
3. `camera_a1_uart_top.v`——clk_cam 计数（§4）、`u_dbg_cam_mail`、`cam_phystat`、`i_dbg_sys` 输入、480 bit 组装。
4. `p2_a1_board_top.v`——连相机诊断输出、`u_dbg_sys_mail`、`cam_sysstat` 打包、接 `u_a1.i_dbg_sys`。
5. `a1_uart_export.v`——v2 包（§7）；先跑包格式仿真，再跑 P1 三例。
6. `01_build.tcl`——文件表 + 3 处路径重定向；其它 tcl 不动。

每步完成后更新 `artifact-hashes.txt`；任一步失败先回到上一步，不要带着半成品进 TD。

## 5. 仿真判据（不过不进 TD）

| 项 | 判据 |
|---|---|
| 包格式 | 97 B、`A5 5A 61 02`、23 字段等于常量、`bad_xor=0`、≥6 包 |
| MIPI 死分支 | `cam_clk_tgl_inc=0`、其它 cam=0、包仍按节拍发、无 A1 阻塞 |
| P1 三例 | micro8x2 `fa513a2b…`(3,809 cyc)、mid64x8 `ee61e620…`(5,172)、full_grad `b992a8ad…`(6,421,414) 逐字节；stats `err/raw_drop/cmp_drop/geom/dup_words=0` |
| core | `a1_deflate_core.v` SHA = `6797db05…35bb` |

短路径要求：`tb_camera_a1_uart_top.v` 的 `out_path/stat_path` 只有 128 字符，工作目录用 `C:\Users\czz\AppData\Local\Temp\opencode\b7` 这类短路径。

## 6. TD 与候选

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\fpga\ph1p100\tools\td\td_env.ps1' -TdDir "$pkg\r0\td"
Push-Location "$pkg\r0\td"
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' ./01_build.tcl
Pop-Location
```

- 综合 ≤2、布线 ≤1；策略组与 b6 r0 相同；不改 SDC/false path/multicycle/seed/时钟/频率。
- 门槛：Routed 0 违例、WNS ≥ +0.05、TNS 0、hold ≥ 0、period 0、组合环 0、无时钟网 0、资源在器件内。不过 → 停止，不 bitgen。
- 保留第 1 次 syn/route 报告（失败也不覆盖）；把最差路径写进 result。

## 7. bitgen / CWC

```powershell
Push-Location "$pkg\r0\td"
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' ./02_bitgen.tcl
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' ./03_cwc.tcl
Pop-Location
```

记录 `a1_board.bit`、`a1_board.cwc`、`a1_board_inst.bid` 的 SHA256/字节数；`cw/compiled.bit|cwc` 必须与父文件逐字节相同。

## 8. 板级（唯一 1 次 SRAM 下载）

1. 先 `ping_cable.tcl`，必须打印 `PH1P100`。
2. `download_sram_camdiag.tcl`：SRAM only、不写 Flash；日志必须含 `PRG-2014` 与显式 `DL_OK mode=jtag(sram)`。若出现 USB 首次打开失败但随后校验成功，按 PRG-2014 判定已下载，并在 result 中原文记录。
3. COM8 115200 8N1 采 **60 s**，保存 `captures/com8_60s.bin`，同时保存 `.stats`（字节数/包数/掉字节）。
4. `python board/parse_status_v2.py --in captures/com8_60s.bin --out captures/status_v2_60s.txt`，要求 ≥55 包、`bad_xor=0`。
5. 把三问结论与支持字段写进 `result-r0diag.md`；若结论是“MIPI 无数据”，照实写，**不要**为了好看再下载一次。

## 9. 冻结与报告

- 停止修改后写 `CANDIDATE-MANIFEST-b7-cam-diag-r0diag.json`：所有输入/产物 SHA、唯一 bit/CWC/BID、TD 报告、v2 包格式、23 字段定义、预算消耗、caveat。
- `result-r0diag.md` 分 functional / engineering / system / G0–G4；必须含三问答案表、命令与 exit、60 s 包数与 XOR、not_run 声明。
- `lessons-r0diag.md` 写实际返工与踩坑；不得把未跑项写成 PASS。
- 交回主：`task_ids/status=ready_for_test/artifact_paths/manifest_path/test_input_paths/lessons_path/blocked/retest`。
