# T10.b8-crop-geom 交接（r0）

状态：**ready，尚未开工**。只交接冻结输入、操作顺序与判据；设计细节见 `fpga-design-guide.md`，门槛见 `dev-plan.md`。

## 1. 一句话

实测 IMX415 输出 **3864×2192**（966 beat/行、2192 行/帧），crop 却按 3840/960 写死，第一行就 `geom_err` 并把整帧 `active` 清零，所以 b7 的 `crop_groups/raw_pub/enc/exported` 全 0。本包把 crop 几何改成 3864/2192、ROI 972/556、输出 1920×1080，做真实几何逐字节仿真，重建 P2，**唯一 1 次** SRAM 下载 + 60 s COM8，目标四计数 >0。

## 2. 开工前只读检查

1. 读 `T10.b7-cam-diag\result-r0diag.md` §3/§6/§7、`lessons-r0diag.md` §1/§5；读 `r0\board\captures_retry\status_v2.json`。
2. 复核几何：用 `parse_status_v2.py` 解析 `com8_150s.bin`，取包 0–12 delta，确认 `65760/30=2192`、`63523629/65760=966.0`；写进 `r0\geometry-derivation.md`。
3. 确认 b7 TD `01_build.tcl` 第 17 行 `a1_raw_crop.v` 仍指向 `Y:/fpga/csi2/src/a1/`，第 20–22/25 行指向 b7 包；b8 必须全部改到 b8 包。
4. 确认 P1 TB 显式传 `CAM_W=3840/CAM_H=2160/ROI_X=960/ROI_Y=540`，因此默认参数改动不影响 P1 金标。
5. 不写 `workflow/tasks.json`；不动 `D:\TD\work\csi2`；不写 Flash；不做第二次下载；不批量删除。

## 3. 建包与冻结起点

```powershell
$pkg = 'D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b8-crop-geom'
New-Item -ItemType Directory -Force -Path "$pkg\r0\changed-src","$pkg\r0\sim","$pkg\r0\td","$pkg\r0\board" | Out-Null
$b7 = 'D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b7-cam-diag\r0'
Copy-Item -LiteralPath "$b7\td\src" -Destination "$pkg\r0\td\src" -Recurse
foreach ($f in 'a1_eng_top.v','a1_small_top.sdc','p2_board.sdc','board_p2.adc','01_build.tcl','02_bitgen.tcl','03_cwc.tcl') {
  Copy-Item -LiteralPath (Join-Path "$b7\td" $f) -Destination (Join-Path "$pkg\r0\td" $f)
}
foreach ($f in 'a1_uart_export.v','camera_a1_uart_top.v','cam_diag_mailbox.v','a1_deflate_core.v') {
  Copy-Item -LiteralPath (Join-Path "$b7\changed-src" $f) -Destination (Join-Path "$pkg\r0\changed-src" $f)
}
Copy-Item -LiteralPath 'D:\fpga\ph1p100\fpga\csi2\src\a1\a1_raw_crop.v' -Destination "$pkg\r0\changed-src\a1_raw_crop.v"
Copy-Item -LiteralPath "$b7\board\parse_status_v2.py" -Destination "$pkg\r0\board\parse_status_v2.py"
```

`r0\td\01_build.tcl` 只改路径表：第 17 行 crop → `Y:/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b8-crop-geom/r0/changed-src/a1_raw_crop.v`；第 20–22/25 行 → b8 包同名文件。其余 TCL 不动。

记录 `artifact-hashes.txt`：输入/复制文件 SHA256、TD/ModelSim 版本、盘符；注明**未复制** `a1_board_Runs/`、`cw/`、旧 bit/cwc/bid。

## 4. 实现顺序（不要并行改多处）

1. `a1_raw_crop.v`：先只改参数默认值（3864/2192/972/556/1920/1080）和 `initial` 断言；保持端口/时序/计数器。跑全尺寸仿真；若行尾最后一组晚于下一条行头 1 拍，再加 1 拍行关闭校验（只改内部，不改输出）。
2. `camera_a1_uart_top.v`：只改 4 个默认参数；`git diff` 除这 4 行外必须为空（相对 b7 副本）。
3. 仿真：全尺寸 → 真实流水小向量 → 负例 → P1 三例 → v2 回归。全过才进 TD。
4. `01_build.tcl` 路径表；TD 综合/布线/bitgen/CWC。
5. 板级 1 次下载 + 60 s；解析/解码；写 result。

## 5. 仿真判据（不过不进 TD）

| 项 | 判据 |
|---|---|
| 全尺寸 | 2 帧各 518,400 valid；480/ROI 行；sof/last 各 1；`roi_frames=2`；`groups=1,036,800`；`geom=0/short=0/abort=0`；输出与独立参考 SHA256 相同 |
| 真实流水 | 每行 16 beat；8×8 组逐字节；`geom=0/short=0/roi_frames=1` |
| 负例 | 965/967 → `geom_err+1`、无 last；短帧 → `short+1`、无 last |
| P1 | 三例逐字节；`err/raw_drop/cmp_drop/geom/dup=0` |
| core/v2 | core SHA 不变；v2 97 B/6 包/XOR 0/23 字段常量 |

短路径：ModelSim 输出路径 ≤128 字符，工作目录用 `C:\Users\czz\AppData\Local\Temp\opencode\b8`。

## 6. TD / 候选

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\fpga\ph1p100\tools\td\td_env.ps1' -TdDir "$pkg\r0\td"
Push-Location "$pkg\r0\td"
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' ./01_build.tcl
Pop-Location
```

- 综合 ≤2、布线 **1**；策略组/SDC/器件/引脚/频率同 b7；不改 seed。
- 门槛：Routed 0 违例、WNS ≥ +0.05、TNS 0、hold ≥ 0、period 0、环 0、无时钟 0、资源在器件内。不过 → 停，不 bitgen。
- 保留每次 syn/route 报告；最差路径写 result。

## 7. bitgen / CWC

```powershell
Push-Location "$pkg\r0\td"
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' ./02_bitgen.tcl
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' ./03_cwc.tcl
Pop-Location
```

记录 `a1_board.bit`、`a1_board.cwc`、`a1_board_inst.bid` SHA/字节；`cw/compiled.bit|cwc` 与父文件逐字节相同。fail-closed 阈值同 b7。

## 8. 板级（唯一 1 次 SRAM 下载）

1. `ping_cable.tcl` → `PH1P100`。
2. 新建 `board/download_sram_b8.tcl`（从 b7 复制，只改 bit 路径到 b8 `r0\td\a1_board.bit`）；SRAM only，日志必须 `PRG-2014` + `DL_OK mode=jtag(sram)`；0 Flash。
3. 下载完成后立即开 COM8 115200 8N1 60 s（可提前 2 s 开监听）；保存 `captures/com8_60s.bin/.stats`，记录 wall_start/end。
4. `python board/parse_status_v2.py --in captures/com8_60s.bin --out captures/status_v2_60s.txt`；`bad_xor=0`；检查四目标与 `crop_geom_err/crop_short` delta、`crop_groups=518,400×cap_frames`。
5. 若 `exported>0`：写/复用 `board/decode_frame.py`，扫描 `41 31 55 31`，解析 44 B 头，校验 header/stream CRC，zlib 解压；有反变换则 raw_crc + PGM/PNG。
6. 相机停流：记录停流时刻/计数；不得二次下载；不得把停流当 crop 错。

## 9. 冻结/报告

- 停止修改后写 `CANDIDATE-MANIFEST-b8-crop-geom-r0.json`：输入/产物 SHA、唯一 bit/CWC/BID、TD 报告、几何、预算消耗、caveat。
- `result-r0.md` 分 functional/engineering/system/G0–G4；含几何推导、仿真逐字节、P1、TD 门槛、板级四目标、解码/CRC、not_run。
- `lessons-r0.md` 写实际返工/踩坑；不得把未跑项写 PASS。
- 交回主：`task_ids/status=ready_for_test/artifact_paths/manifest_path/test_input_paths/lessons_path/blocked/retest`。
