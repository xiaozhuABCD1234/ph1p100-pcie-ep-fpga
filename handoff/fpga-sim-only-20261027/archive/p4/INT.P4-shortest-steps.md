# INT.P4 最短操作步骤（r2）

## r3 最短复现（2026-10-27；同一候选、独立证据目录）

```powershell
# 1) 仿真（-Tag r3 隔离编译库/日志/样例目录；不覆盖 r2 证据）
cd D:\fpga\ph1p100
powershell -NoProfile -File tools/integrated_delivery/run_integrated_sim.ps1 -Tag r3 -Mode 4 -Sample 0 -Extra -Full
powershell -NoProfile -File tools/integrated_delivery/run_integrated_sim.ps1 -Tag r3 -Mode 1 -Sample 1 `
  -SampleDir D:/fpga/ph1p100/workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4/r3/sim/ev1
# 期望：dev TB 65 ok/0 fail（EXTRA）、27/26 ok（默认）；P1/P2/P3 + python 全 PASS；
#       样例哈希 79E35F28…/1357408F…/76D88910…；
#       注意：tb_img_algo_equiv_p4 的 CHECK_REF_NEW 仍有数据差异（57–2867），不是 PASS，见 result-r3 §3。

# 2) 综合（独立子目录 + 25min 超时，只停自身 PID）
powershell -NoProfile -File tools/integrated_delivery/run_integrated_build.ps1 -Stage 01_synth -TimeoutMin 25 -Subdir r3_run1
# 期望：INT_SYN_VIOL_ENDPOINTS=0 / SWNS=0.072 / STNS=0.000 / IO=42 / ERAM_CWC=39 / REG=6004

# 3) 证据校验
Get-FileHash workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4/td/r3_run1/syn_flow.status
```

- route：`02_route.tcl` **未执行**（G2 已过，但 harness 无引脚/IO 约束，布线 STA 非板级证据；额度保留）。
- 本轮唯一 RTL 变化：`algo_rowwin3_p4.v`（+1 拍固定延迟）+ 两个上层实例替换；`img/**`、b20、upstream 未动。


1. 复跑集成仿真（约 1 分钟，cwd 任意）：
   `powershell -NoProfile -ExecutionPolicy Bypass -File tools/integrated_delivery/run_integrated_sim.ps1`
   期望末行 `TB_INTEGRATED_DELIVERY_TOP PASS`，样例三文件写入 `tools/integrated_delivery/evidence/`。
2. 复跑多场景表（反压 / abort / A 禁用+B 优先 / 错误 ACK / 截断帧）：
   `... run_integrated_sim.ps1 -Mode 4 -Sample 0 -Extra` → `TB_INTEGRATED_DELIVERY_TOP PASS`（T1–T6 全 ok，65 ok / 0 fail）。
   Y8 通路同一套场景：`... -Mode 1 -Sample 0 -Extra` → PASS（65 ok / 0 fail）。
3. 校验样例：
   `python tools/integrated_delivery/verify_integrated_sample.py tools/integrated_delivery/evidence/integrated_sample.a1u1 tools/integrated_delivery/evidence/integrated_sample.raw tools/integrated_delivery/evidence/integrated_sample.json`
   期望 `VERIFY_INTEGRATED_SAMPLE PASS`；独立判据 `test-reports/INT.P4/oracle_sample.py --sample ... --raw ... --json ...`
   期望 `ORACLE PASS`。mode1 与 mode4 的样例哈希必须仍是 `79e35f28…`/`1357408f…`/`76d88910…`。
4. 复跑派生变体等价 + P1/P2/P3 回归：
   `... run_integrated_sim.ps1 -Full -Mode 4 -Sample 0 -Extra`
   期望 `equiv_seedmode{0,1,2}.log` 三次 `CHECK_REF_NEW PASS`、`TB_IMG_ALGO_EQUIV_P4 PASS`，
   `TB_RAW10_PACK PASS`、`TB_APLUS_PCIE_EGRESS_ADAPTER PASS`、`TB_DUAL_CHANNEL_CAPTURE_SCHEDULER PASS`、
   `RAW10_PACK PASS`、`INT.P1_VERIFY PASS`、`DUAL_CHANNEL_SCHEDULE PASS`、`A1U1_DECODE OK`、
   `VERIFY_INTEGRATED_SAMPLE PASS`。
5. 综合（只读 run 证据，不需重跑即可判读；round2 synth 额度 3/3 已用尽）：
   `INT.P4/td/syn_flow.status` 与 `INT.P4/td/td_01_synth_console.log` 的 `INT_SYN_*` 行 →
   `INT_SYN_VIOL_ENDPOINTS=112`（`FLOWSTATUS=112`、`TOTAL=16770`）、`SWNS=-0.637`、`STNS=-69.776`、
   `HWNS/HTNS=0.000`、`IO=42`、`ERAM=39`、`CWC=0`、`REG=5832`、`SLICE=10761`、`DSP=14`。
   结论：综合可完成、IO/资源在器件内、无未驱动 DUT 输入告警、`u_arb/u_egress/u_store` 层次可见，
   但 187.5MHz setup 仍不收敛（112 违例端点）→ 按门槛不布线（route=not_run）、不写 bit。
   r1 的真实端点是 330（不是 r1 文档里写的 10）；三次 r2 综合依次为 277 / 112 / 112。
6. 下一条最短动作（要过 G2）：剩余违例全部在 `fpga/csi2/src/img/algo_rowwin3.v` 的行缓冲读路径
   （`u_obuf_gau/count → pipe_en → evt_en → ra0(fanout 256) → DRAM 读 → relut/f7mux → rb0_reg.d`，
   5.906ns）；`u_front` 与 `u_gau` 各一份。已排除的边界内手段：顶层 ready/skid 打拍（已做，330→112）、
   harness 寄存器化捕获（已做）、P1 输入弹性级（已做）、行缓冲改 ERAM（TD 不识别该 `ram_style` 形态，
   netlist 未变）。要真正收敛必须改该模块的读调度/存储形态（本轮 `img/**` 只读）、或经授权降低 P1 时钟、
   或（不允许）放宽 STA 约束。任何改动都必须重跑本文件 1/2/4 与测试者的独立 TB。
7. RK 侧只需样例：`tools/integrated_delivery/evidence/integrated_sample.a1u1`（44B 头 + zlib）按
   `a1u1_decode.py` 的头定义解析；真实 PCIe 传输仍需 RK 联调（未做）。
