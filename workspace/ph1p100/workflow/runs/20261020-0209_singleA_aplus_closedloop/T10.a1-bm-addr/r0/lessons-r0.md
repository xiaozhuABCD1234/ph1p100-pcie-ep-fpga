# T10.a1-bm-addr r0 lessons（可复用根因/触发/修正/验证入口）

## 1. 触发：r2-waive 残留地址/CE 锥（routed −0.421 / 10 端点）
- `htab_p3v ERAM clk2q → bm_b.addrb[11..12]`：`bm_raddr_b = … ? hent[49:37] : …` 让 13 位 ERAM 读出数据经 **bypass mux + s1_en mux + hit mux 共 3 级 LUT** 才到 ERAM 地址端口（routed 报告：ERAM clk2q 1.846 ns + 3 级逻辑 + 2.09 ns 网络）。
- `pos_reg[1] → bm_a/bm_b.addrb`：`hdist2 = pos - hp_r` 的 13 位借位链之后，还要经状态 mux 与 hit2 mux；`pos → w0/w1.ceb` 则是 `hit2` 被 TD 折进“下一状态→装载使能”的共享逻辑。

## 2. 修正（本包实测可行、且 G1 逐位不变的三种手法）
1. **端口地址改成单级 mux**：把所有“同拍可用”的地址源（`hf1_r`/`ext_faddr`/`htab_byp_data[49:37]`/`raddr`）先合成一条**触发器路径**，ERAM 输出只经 **1 个 2:1 mux**（`bm_b_from_ram ? htab_q[49:37] : flop_addr`）。关键点：`htab_byp_data` 本身就是寄存器，直接切片 `[49:37]` 就等价于旧的 bypass 数据，不必再复制一份。
2. **提前一拍寄存“命中拍专用地址”**：`hf1_r <= hent[49:37] + 13'd1` 与 `hf_r` 同拍装载（同样 `if (s1_en)`），于是命中拍的 `ref+4` 地址是触发器，不再有 `hit2 → 加法器 → 地址`。
3. **把“可被后续状态覆盖”的移位改成无条件**：`S_SCAN` 的 `w0<=w1; w1<=w2; w2<=x1_r` 移到 case 顶部即功能等价（命中/块尾后都会进 `S_REPOS`/`S_PRE` 由 `bm_b_rd` 重装三个窗口字节），从而把 `hit2` 从 w0/w1/w2 的时钟使能锥移除。判定“可覆盖”的依据：`S_PRE@1/@2/@3` 与 `S_REPOS@1/@2/@3` 对 w0/w1/w2 全部重装。

## 3. 结果与边界
- 综合 1/1：WNS **+0.021 → +0.113**、TNS 0、slice 3,080→3,085、ERAM 26（core 22）、reg +13（`hf1_r`）。综合报告 10 端点内 **`ERAM (clk2q)` 出现 0 次**（r2 已是 0，本包确认地址/CE 锥不再进入关键集）。
- 但 **`report_timing -from …` 过滤在 TD 2026.2 无效**（r2-waive §3 已用逐字节相同报告实证），所以“所有 ERAM clk2q 端点 ≥ +0.9”仍只能覆盖“报告集合”，不能穷举；不要把它写成穷举通过。
- 全局 WNS 天花板是**锁定的 `a1_frame_top`**（本包 +0.113，起点 `byte_k_reg[2]`；r2 是 `grp_in_row_reg[3]` +0.021）：只要该文件不可改，任何“WNS ≥ +0.5”预布线闸门都不可达。派发时若给该闸门，等于预先规定 blocked——应在 dispatch 里显式豁免或把目标改为“ERAM clk2q 锥清出关键集 + 全局 WNS 不退步”。

## 4. 验证入口（下次直接复用）
- 仿真：`upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p2_bm_addr_r0.ps1`、`run_p3_bm_addr_r0.ps1`（`P:`=项目根、`W:`=run 目录；`$env:A1_P2_RUN="../T10.a1-bm-addr/r0/p2"`）。逐位判定最省事的做法：把新 `result.json` 与基线 `result.json` 逐 case 做**深度 JSON 比较**（`json.dumps(sort_keys=True)`），一次覆盖 len/sha/cycles/negative/strict/zlib/Bayer。
- 综合：`r0/td/00_syn_then_route.tcl`（无 BOM、cwd=`T:`、`td_commands_prompt.exe T:/00_syn_then_route.tcl`）。闸门打印 `SYN_SWNS/…` 与 `SYN_GATE_STOP|SYN_GATE_OK`；单次 46 s。
- G1 通过的判据必须含 **comp cycles 精确相等（355,261）**；本包 33 例全字段相等即同时满足 comp/1080p bytes/逐位。
