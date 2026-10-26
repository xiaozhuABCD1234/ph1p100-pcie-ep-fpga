# T10.b5-a1-htab-pipe r0 -- lessons

可复用根因/触发/修正/验证入口，只记能被下次直接用的。

## 1. ERAM clk2q → ERAM 地址：必须整拍打断，不能只挪 mux

- 触发：r4 routed `-0.274 / 23 端点`，同一组 `htab_p3v → bm_b.addrb`；
  TD 把 ERAM 输出寄存器记成 `<inst>_syn_*.clkb` 起点、把另一块 ERAM 的地址寄存器记成
  `<inst>.addrb[*]` 终点，所以 STA 报告里两端都是“ERAM 内部寄存器”，中间只有一个 fabric mux。
- 修正：在两者之间插一级 fabric flop（本包 `bm_b_spec_q`），**并且**把消费端（比较/判决）
  整体后移一拍对齐。只插 flop 不对齐消费端 = 功能立刻错。
- 验证入口：`routed_timing.rpt` 里搜索旧的 end-point 组应消失；syn 级看
  `syn_gate_timing.rpt` 最差路径是否换域。

## 2. “提前一拍发地址”在 A+ core 里是陷阱

- 想把 htab 读地址提前一拍，需要 position+3 的第三个 hash 字节，它只能来自 `bm_a_rd`
  （bm_a 的 ERAM clk2q）。那等于把这个违例搬到 htab 地址上，并要再加一级 bm_a 预取
  （改变 bm 预取语义）。**先检查 hash 的三个输入是不是都在 flop 上，再决定方案 1 是否可行。**

## 3. 命中扩展循环（S_EXT）加流水时，地址推进必须与“等待拍”同步

- 症状：micro8x2 19→18 B、mid64x8 106→104 B，`MDIST len` 多 1。
- 根因：等待拍只寄存比较、没推进 `ext_raddr/ext_faddr`，导致 k=1 的字节对被比较两次，
  循环多算一个“匹配字节”。
- 修正：等待拍同时 `ext_raddr/ext_faddr + 1`（保持“地址流比判决流早两拍”的原节奏）。
- 验证入口：`A1_TRACE_EXT` 探针（`sim/dbgsrc/dbg_*_core.v`）打印
  `EXT mis/rem/zero/len/ard/brd/cq/ea/ef/fw`，upstream 与本包逐行对比；
  命中拍起前 6 行就能看出是否重复比较。

## 4. 综合 +0.3 是“代理门”，真实门槛是 Routed

- 事实：本包 synth +0.222（新最差路径 `len_r → cand_bits`，属 match-length 计数链），
  r4 synth +0.256 也一样 < +0.3，但两者都进入布线；Routed 才是 fail-closed 放行依据。
- 教训：若综合最差路径不在获批锥内，**不要靠重跑综合凑数**（TD 确定性），
  记录偏离 + 交规划；**也不要**为了凑 +0.3 顺手改第二处 RTL。

## 5. 板卡不在位时，下载额度不要动

- 本次 `read_device_id` 返回 `PRG-8000 ERROR: transfer failed`，
  `GetPortNames()` 只剩 COM3/COM4、PnP 无 FTDI、hwserver 进程消失 → 板卡被拔/断电。
- 正确动作：只做**只读**探针（connect + read_device_id + close），确认后 blocked，
  1 次 SRAM 下载额度保持 0/1，bit/CWC 已冻结，下次不必重新综合/布线/bitgen。
- 反例（禁止）：拿“探测性下载”当探针；那会直接烧掉唯一额度。

## 6. 其它小坑

- `Set-Content -Encoding utf8` 给 Verilog/Tcl 加 BOM 会让 vlog 报
  `Syntax error, unexpected non-printable character 0xef`。RTL/Tcl 一律 ASCII 或 UTF8-no-BOM。
- `vlog -work lib` 要求 `lib` 是**已初始化**的库；手工建的空目录要先 `vlib lib`。
- ModelSim 10.5b 下 `$display` 在时钟沿显示的是**更新前**的值：判读 `mis` 时要记得它对应上一拍的比较。
- TD 工程目录复制时不要带 `*_Runs/`、`*.db`、`routed_netlist.v`；但 `syn_gate_*.rpt`
  等历史报告如果被带过来，要确认 `01_build.tcl` 会全部覆盖（本包会），否则会污染证据。
- `create_project -force` 会重写 `a1_board.al`：**唯一 File Path 重定向必须写在
  `01_build.tcl` 的 `add_files` 行**，而不是手改 `.al`。
