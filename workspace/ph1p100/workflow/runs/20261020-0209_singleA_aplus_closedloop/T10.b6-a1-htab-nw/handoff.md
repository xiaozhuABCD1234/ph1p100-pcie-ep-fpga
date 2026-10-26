# b6 收尾交接（2026-10-24，规划）

状态：**PASS / closed**。本包不再派开发或测试。上面/下文为执行前交接原文，保留用于追溯。

- 报告：`workflow/runs/20261020-0209_singleA_aplus_closedloop/test-reports/T10.b6-a1-htab-nw-r0-integrated.md`
- 冻结候选：core `6797db05…35bb`；bit `a2757d40…ffa2`；cwc `dc477c8f…dc57`；bid `2bf011c5…d730`
- 结果：P2 355,261 cycles / 81.067 MB/s；P1 三例逐字节；Routed 0/19,779、+0.119；1 bitgen + 1 CWC；0 下载
- 遗留 caveat：Syn +0.280；Routed/hold 薄余量；边界复用；CWC 未读回；G4 not_run
- 下一步不在本包：`T10.b7-cam-diag`（相机前端可观测性），见同 run 的 `T10.b7-cam-diag/dispatch.json`

---

# T10.b6-a1-htab-nw 交接（r0）

日期：2026-10-24。状态：**ready，尚未开发**。本文件只交接冻结输入、操作顺序和判据；详细设计见 `fpga-design-guide.md`，任务表见 `dev-plan.md`。

## 1. 一句话

r5 功能正确但每 match 多 1 拍，P2 comp 374,461 cycles / 76.91 MB/s，低于 77.76；b6 用“提前一拍的 htab p3v 影子读 + 必要时一级 bm_a 预取”保留 r5 的 flop-only bm_b 地址，去掉 S_EXT 等待，目标 **355,261 cycles / 81.067 MB/s**，输出逐字节不变。

## 2. 开工前检查（只读）

1. 确认 ModelSim 10.5b 可用（`D:\intelFPGA\18.1\modelsim_ase\win32aloem`）。
2. 确认 TD 安装 `D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe`，许可有效；磁盘足够放一个 `a1_board` 工程。
3. 确认本包目录不存在旧候选；如存在只追加/另建 `r1`，不覆盖、不批量删除。
4. 读 `T10.b5.../r0/result-r0.md` 的 §2/§4/§5，确认 r5 的 `bm_b_spec_q`、`ext_first`、TD 策略组和 WNS +0.100/0 事实。
5. 不下载、不 Flash、不碰 `D:\TD\work\csi2`；不改 `workflow/tasks.json`（规划维护）。

## 3. 建包与冻结起点

```powershell
$pkg = 'D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b6-a1-htab-nw'
New-Item -ItemType Directory -Force -Path "$pkg\r0\changed-src","$pkg\r0\sim","$pkg\r0\td" | Out-Null
Copy-Item -LiteralPath 'D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b5-a1-htab-pipe\r0\changed-src\a1_deflate_core.v' -Destination "$pkg\r0\changed-src\a1_deflate_core.v"
# SHA256 必须是 29b1e3e1a66abef78c228c4189322b0139a266d43bf02827dd1ebe498cdc9828
```

TD 模板只复制需要的部分（**不要**复制 `a1_board_Runs/`、`cw/`、旧 bit/cwc/bid/大报告）：

```powershell
$b5td = 'D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b5-a1-htab-pipe\r0\td'
Copy-Item -LiteralPath "$b5td\src" -Destination "$pkg\r0\td\src" -Recurse
foreach ($f in 'a1_eng_top.v','a1_small_top.sdc','p2_board.sdc','board_p2.adc','01_build.tcl','02_bitgen.tcl','03_cwc.tcl') {
  Copy-Item -LiteralPath (Join-Path $b5td $f) -Destination (Join-Path "$pkg\r0\td" $f)
}
```

然后只改 `r0/td/01_build.tcl` 中 core 源路径一行：由 b5 r0 `changed-src` 改到本包 `r0/changed-src`。其余 RTL/约束/IP 不动。把这条 diff 记入 `artifact-hashes.txt`。

## 4. RTL 实现要点（按设计指南 §4.1）

- 保留 r5 的 `bm_b_spec_q` 和
  `bm_raddr_b = s1_en ? bm_b_spec_q : (state==S_EXT) ? ext_faddr : raddr;`
- 新增提前一拍的 p3 影子读：主读 T-1 发地址、T 出数据；影子读 T-2 发同一窗口 hash、T-1 出数据装 `bm_b_spec_q`。
- 影子地址必须 flop-only；若需要，加 `bm_a_rd3 <= bm_a_rd2`，只用于影子 hash，不改现有 `bm_a` 地址/`w0..w2/x1_r` 链。
- 旁路两条：影子读当场同址写用 `s1_ins_data[49:37]`；`bm_b_spec_q` 装载时若主 `htab_byp` 有效，用 `htab_byp_data[49:37]` 覆盖。
- 恢复 r4：hit 拍 `cq_r <= x1_r`；`ext_raddr = p3_r+2`；`ext_faddr = hf_r+2`；`ext_mis_r` 在 hit 拍寄存 k=0；S_EXT 无 `ext_first` 等待。
- 先只改这一处；不要顺手改阈值/窗口/插入/旁路/帧/CRC。

## 5. P2 核级仿真（先做，决定是否进 TD）

输入/向量冻结：

| 文件 | SHA256 |
|---|---|
| `comp/in.hex` | `edbfdeaedb06824ced20ad76b260979e95e1322d6f6e3bab5e7a951a268f9849` |
| `comp/in.meta` | `e98c9a1c3e0fe621c9aa65aaadbcacbef13c2437a0bbbafcde17d2ff471f80fe` |
| `comp/in.xform` | `b836b51df0bc98045f3768cf497bb5a76f88fa301e0598c63514284e2fbfba7a` |
| `rand/in.hex` | `dcc80e7adeef41e4804390ba52dd1f6d2c12e1b99d851cccd50e246c082595bd` |

编译（把 b5 的 core 换成 b6 的；TB 不变）：

```powershell
$ms='D:\intelFPGA\18.1\modelsim_ase\win32aloem'
& "$ms\vlib.exe" "$pkg\r0\sim\work"
& "$ms\vlog.exe" -work "$pkg\r0\sim\work" `
  "$pkg\r0\changed-src\a1_deflate_core.v" `
  'D:\fpga\ph1p100\upstream\ph1p100-pcie-ep-fpga\sim\tb\codec\tb_a1_deflate_core.v'
```

仿真（comp/rand 各一次；`+BP=0 +GAP=0` 固定）：

```powershell
& "$ms\vsim.exe" -c -lib "$pkg\r0\sim\work" -l "$pkg\r0\sim\comp.log" tb_a1_deflate_core `
  "+IN=D:/fpga/ph1p100/work/parallel-sim-20261024-2204/codec-throughput/comp/in.hex" `
  "+META=D:/fpga/ph1p100/work/parallel-sim-20261024-2204/codec-throughput/comp/in.meta" `
  "+OUT=$pkg/r0/sim/comp.out.hex" "+STAT=$pkg/r0/sim/comp.stats.txt" `
  "+BP=0" "+GAP=0" "+TIMEOUT=2000000" -do "run -all; quit -f"
```

判据：
- comp `run_cycles == 355,261`；流 50,310 B，SHA `2601d57cd98d1fe69b2e46fe8423779a5d44bd14c00e1fe2d5faab6ff15a7c05`；zlib/strict 0 差异。
- rand 流 153,766 B，SHA `54f262f2a600a3e2f12129f2937a390737d1ec8018d8f0236979e604760496dd`；cycles ≤161,479。
- stats 需 `bp=0 gap=0 done=1 out_last=1 timeout_hit=0`；不得用 TB 退出码单独判定。

## 6. P1 三例（字节金标）

TB：`T10.b1-a1-uart-integ/r0/sim/tb_camera_a1_uart_top.v`；编译文件表看 b5 r0 `sim/logs/vlog_r0.log`，把 core 换成本包。三例的 generics/plusargs 看 b5 r0 `sim/logs/sim_{micro8x2,mid64x8,full_grad}.log` 第一行，原样复用（`+MODE=0`、`+OUT=...dec`、`+STAT=...stats`、`-gUART_DIV=1`、`-gW/-gH/-gCAM_W/-gCAM_H/-gROI_X/-gROI_Y`）。

| case | 字节 | 金标 SHA256 | r4 cycles 上限 |
|---|---:|---|---:|
| micro8x2 | 63 | `fa513a2b5a7f268be9f29d62aea6c44aaab796d0f23256b0e1049f50acceedef` | 3,809 |
| mid64x8 | 150 | `ee61e6200d9abca66c5a74a0cbbd9dde982f1d4652647f8b0d67e5964f3e9789` | 5,172 |
| full_grad | 40,076 | `b992a8ad74063545cfebb67e59efc83b4136133a0c19479a18c05c343d48ada9` | 6,421,414 |

另复测奇数尾块 8×3、随机 stored 64×8 的 RAW/码流/CRC/尾垃圾/重复读；双路同步/负对照 RTL 未改，可在 `p1-regression.json` 中注明复用 b5 r0/探索结论及理由。

## 7. TD 工程（仅在 P2/P1 全过后）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\fpga\ph1p100\tools\td\td_env.ps1' -TdDir "$pkg\r0\td"
# 可选校验：open_td.ps1 -TdDir ... -NoLaunch
Push-Location "$pkg\r0\td"
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' ./01_build.tcl
Pop-Location
```

- `01_build.tcl` 内含 syn + route，冻结策略组同 b5 r0（`post_route_opt ultra`、`postrt_opt_loc 20`、`postrt_opt_extra_round 4`）；不加 seed sweep、不改 SDC、不加 false path/multicycle。
- 读 `syn_gate_timing.rpt`、`routed_timing.rpt`、`routed_qor.rpt`、`routed_area.rpt`、`routed_check_timing.rpt`；确认 `htab_p3v→bm_b.addrb` 端点组消失，记录新的最差路径。
- 门槛：Routed 0 违例、WNS ≥ +0.05、TNS=0、hold ≥0、period 0、组合环/无时钟 0、资源在器件内。若 WNS < +0.05 或有违例：只允许一次 RTL 修正 + 第 2 次 route；仍不过则停止，不 bitgen。
- 综合 ≤3、route ≤2、TD ≤3 sessions/150 min；第 1 次 syn/route 结果必须保留，失败也不覆盖。

## 8. bitgen / CWC（各 1 次，fail-closed）

```powershell
Push-Location "$pkg\r0\td"
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' ./02_bitgen.tcl
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' ./03_cwc.tcl
Pop-Location
```

- bitgen 前重核最终 STA（setup/hold/period/TNS/skew/abnormal）；任一为负或 TNS≠0 拒绝生成。
- 记录 `a1_board.bit`、`a1_board.cwc`、`a1_board_inst.bid` 的 SHA256 和字节数；`cw/compiled.bit` 必须与 `a1_board.bit` 逐字节相同，`cw/compiled.cwc` 与 cwc 相同。
- **不下载、不 Flash、不连板、不采集 COM8。** 板级/系统验证本轮 not_run。

## 9. 冻结与报告

- 停止修改后写 `CANDIDATE-MANIFEST-b6-a1-htab-nw-r0.json`：输入 SHA、唯一 core SHA、P2/P1 向量与结果、TD 报告、bit/CWC/BID、工具版本、预算消耗、caveat。
- `result-r0.md` 必须分开写：functional（P2/P1/边界）、engineering（syn/route/资源/关键路径）、system（仅接口不变+not_run 理由）、G0-G4 判定、实际命令/exit/超时。
- `lessons-r0.md` 写实际返工与踩坑；不得把未跑项写成 PASS。
- 交回主：`task_ids/status=ready_for_test/artifact_paths/manifest_path/test_input_paths/lessons_path/blocked/retest`。

## 10. 明确不做

- 不改 `a1_frame_top.v`、UART export、DDR/CRC/协议/帧；不改 SDC/时钟/复位。
- 不放宽 355,261/77.76/WNS +0.05 门槛；不用“功能对”替代吞吐 PASS。
- 不把相机 `cap_frames=0`、P3 下载、双路同步接入混进本包。
- 不删旧文件/目录；不批量删除；不覆盖 b5 r0/upstream。
