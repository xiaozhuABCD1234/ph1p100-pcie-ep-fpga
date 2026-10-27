import io, os

RUN = r'D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery'

BLOCKS = {
 'INT.P4-build-entry.md': """
## r3 更新（2026-10-27，本轮权威数字；以下 r2 正文保留为历史）

- **候选源（仿真入口，24 个核心 + 6 TB）**：候选 8（`integrated_delivery_top.v`、`integrated_input_processing_top.v`、
  `raw10_sample_vector_to_packed.v`、`frame_good_publish_cancel.v`、`aplus_pcie_egress_adapter.v`、
  `dual_channel_capture_scheduler.v`、`bayer_raw10_demosaic4_p4.v`、`img_algo_parallel_top_p4.v`、
  `algo_rowwin3_p4.v`、`gray8_gaussian3x3_stream_p4.v` —— 其中后 4 个是派生时序变体）+ b20 4 + img 10 = **24**；
  TB 6（5 个候选 TB + 等价 TB）。img 源仍是 10 个（`img/**` 只读，未改）。
- **综合入口（`tools/integrated_delivery/td/01_synth.tcl`）**：25 个 Verilog 源（候选/工具 15 + img 10）+ harness 1 已含在 15 内 + tcl/sdc；
  文件集清单 `INT.P4/td/r3_run1-fileset.sha256`（27 项，SHA256 `FEDA255C…`）。
- **TD 证据目录**：`INT.P4/td/r3_run1/`（独立，不与 r2 混放）；`INT.P4/td/syn_r2_run2/` 仍是 r2 权威。
- **G2（本轮）**：`flow.status` Setup **NUM_FEPS 0 / 17220**、**WNS +72ps / TNS 0ps**，Hold 0 端点；
  IO 42/286、ERAM+CWC 39/300、reg 6004、slice* 10691/71680、DSP 14；`u_front/u_row`、`u_gau/u_row` 均为 `algo_rowwin3_p4`。
- **回归**：dev TB MODE=4/1 默认+EXTRA（27/65/26/65 ok，0 fail）；mode1/mode4 样例哈希 = `79E35F28…/1357408F…/76D88910…`；
  P1/P2/P3 TB 与 Python 全 PASS。**派生变体 token 等价仍有 57–2867 处数据差异（见 result-r3 §3），不作为已通过项。**
- route/bitgen/CWC/download/Flash = 0。命令见 `INT.P4-shortest-steps.md` 的 r3 段。
""",
 'INT.P4-shortest-steps.md': """
## r3 最短复现（2026-10-27；同一候选、独立证据目录）

```powershell
# 1) 仿真（-Tag r3 隔离编译库/日志/样例目录；不覆盖 r2 证据）
cd D:\\fpga\\ph1p100
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
""",
 'INT.P4-protocol.md': """
## r3 接口/语义增量（2026-10-27）

- **端口/参数/单位不变**：`algo_rowwin3_p4` 与 `algo_rowwin3` 端口逐一相同；`gray8_gaussian3x3_stream_p4`、
  `bayer_raw10_demosaic4_p4`、`img_algo_parallel_top_p4` 同理。A1U1 vs R10F、RAW vs Y8 的分离不变。
- **唯一语义增量**：两个 rowwin 实例的 `prod_valid/prod_*` 与 `win_*` 整体后移 **固定 +1 clk**（读地址/银行打拍 + 描述符/流侧同步延拍）；
  `s_ready = rst_n && cfg_ok && en && (state != ST_FLUSH)` 逐字不变，接收率与反压契约不变；sof/eol/eof/abort 标记、
  生产槽数、flush 顺序、中止/重启规则不变。停顿（en=0）时延迟组整体冻结，下一 en=1 拍消费一次，不丢不重。
- **帧调度**：写口 bank 轮转、读口 bank 选择、`asm40/asm32` clamp 规则、`pe/f_cycle` 产生时刻均未改。
- **既有差距**：`gray8_he_cdfmin_frame.v` 对停顿形态敏感（同一基础 RTL、仅换 ready 种子即 48–99 处差异）；
  因此“语义不变”只在同激励+同 ready 形态下声明，任意背压下的 HE 像素唯一性仍未定义（`img/**` 只读，未修）。
- 单 `clk`（5.333ns）、异步低有效 `rst_n`；无 CDC/异步 FIFO/时钟改动/时序例外。
""",
 'INT.P4-lessons.md': """
## r3 可复用经验（2026-10-27）

1. **深 LUT-RAM 读 mux 的正确切分点**：r2 的 `en → evt_en → ra0 → 320 深 DRAM → rb0.d` 只能在“地址打拍”处切；
   仅打拍地址即可把 5.906ns 拆成两段（r3 setup 0 违例、WNS +0.072ns，+172 reg）。
2. **打拍必须连带对齐，且“读寄存器”的使能要跟停顿一致**：`rb* <= bank[ra0_r]` 若无条件每拍读，停顿期间会把
   已持有的 token 窗口刷新掉（本轮 r2→r3 调试复现：停顿恢复时同描述符换数据）。用 `en` 使能（停顿冻结、
   gap 时与基础同址重读）才与基础逐拍一致。
3. **描述符务必用延迟版本驱动端口**：只延迟 win 数据而漏改 `assign prod_*` 会造成“描述符新、数据旧”的整链错位（本轮曾复现 5140 处差异）。
4. **等价 TB 的陷阱（写测试时注意）**：两个 DUT 若共享一个“两边都 ready 才前进”的源，`s_ready` 一旦不同步，
   两个 DUT 就会看到不同 beat；必须**每个 DUT 独立源/独立 beat 计数**，否则测的是激励而不是 RTL。
5. **TD 批处理会报 `PRJ-8806 Run syn_1 has exited unexpectedly`**（`wait_run` 在 run 结束后才调用），
   只要 `flow.status`/报告齐全且 4 条统计有值即属正常；不要据此重跑。
6. **证据目录卫生**：每个 synth run 独立子目录（`-Subdir`），文件集清单单独哈希；旧 run 的 root 级
   `run.log`/`01_synth.tcl` 必须注明或改名，否则会被误读成本轮证据。
7. **仍开放**：停顿/间隙交替下 +1 拍的窗口对齐仍有少量数据差异（57–2867 token 级），需按 §2 的使能规则继续收敛；
   HE 停顿敏感性是基础模块性质，未修。
""",
}

for name, block in BLOCKS.items():
    p = os.path.join(RUN, name)
    with io.open(p, encoding='utf-8') as f:
        txt = f.read()
    if 'r3 更新（2026-10-27' in txt or 'r3 最短复现（2026-10-27' in txt or 'r3 接口/语义增量（2026-10-27' in txt or 'r3 可复用经验（2026-10-27' in txt:
        print('SKIP already patched', name)
        continue
    lines = txt.split('\n')
    # insert after the first heading line (keep the title, put the r3 block right after it)
    out = lines[0] + '\n' + block + '\n' + '\n'.join(lines[1:])
    with io.open(p, 'w', encoding='utf-8', newline='\n') as f:
        f.write(out)
    print('PATCHED', name, 'bytes', len(out))
