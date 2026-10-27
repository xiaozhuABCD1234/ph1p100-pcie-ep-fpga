# T10.a1-adler-smem r0 — **BLOCKED at the synth gate**（WNS +0.233 < +0.3；未布线、未派测试者）

- task_id `T10.a1-adler-smem` | round **r0**（用户“继续A”，最后 87 ps 微修）| 2026-10-22 | run `20261020-0209_singleA_aplus_closedloop`
- 基准：`T10.a1-bm-addr` r0 候选 `35ea7364…0942`（G1 33/33 逐位、comp 355,261、1080p 81,707 B）；frame `18d51b1b…1cbe`、SDC `227dd39e…6311`
- 判定 **BLOCKED**：G1 全绿；综合 1/1 得 WNS **+0.233 / TNS 0.000** < 闸门 **+0.3** → `SYN_GATE_STOP no_route`；route 0/1、无 routed STA、无 check_timing/report_clock_utilization、bitgen not_run、`.bit/.cwc` = 0、无下载
- 按 dispatch 停止规则：**失败即收尾**，T10 记 3/4 PASS + 1 ⚠；保留 r2 `0b084317` 与 bm-addr `35ea7364` 全部证据，不自动扩轮
- **更新**：本候选其后经规划一次性豁免执行了 route-only，结果见 `../r0-route/result-r0-route.md`（Routed −0.541 / 299 端点 → FAIL）。本文件 §1–§6 为综合阶段记录。

## 1. 改了什么（严格限于 adler / smem 写地址）

| # | 文件 | 改动 | 目标锥 |
|---|---|---|---|
| 1 | `a1_frame_top.v` | 新增 16 位 `wbase` = `(wr_bank ? NSAMP : 0) + row_in_blk * W`，每行/每块更新一次（帧起始清 0，块结束换 bank），每字节写地址改为 `prep ? wbase + (x_t[0]?HALFW:0) + (x_t>>1) : wbase + x_t` | `byte_k → smem_waddr_r`（综合 7 级、+0.113） |
| 2 | `a1_deflate_core.v` | 新增 1 位 `adler_hold` 替代 `in_ready` 里的 `!adler_blk_q && (adler_red_st==0)`；`in_blk_end` 置位，`in_sop`/abort/reset/`adler_red_st` 回 0 清零 | `adler_red_st → in_ready → smem.addrb`（routed −0.087） |

- **无周期变化**：写地址与 adler gate 都是同拍值的前移/寄存，未改协议、端口、帧裁决、CRC/长度/abort/Bayer、smem 读地址 `rd_addr`、bm/htab 存储、`thresh_lit8/9`、SDC。
- 改动前把两个基线文件备份到 `r0/base/`；候选副本冻结在 `r0/td/`；`r0/patch.diff` 为精确 diff。

## 2. G1（全绿，33/33 逐位同 r2）

| 项 | 结果 |
|---|---|
| P2 | **13/13 PASS**、0 mismatch、0 X、`vlog 0/0`；comp `len 50,310 / cycles **355,261**（精确相等）/ sha 2601d57c…`；rand 161,479 |
| P3 | **20/20 PASS**、0 mismatch、0 X、`vlog 0/0` + `vlog -lint 0`；`f1080p_p1d1` **81,707 B / b769cc66…08ff / cycles 4,677,945** |
| 逐位对比 | 与 r2 `0b084317` 的 `result.json` 去除时间/路径/manifest 字段后**深度比较：P2 13/13 + P3 20/20 全字段相同（0 差异）** |
| 命令 | `r0/p2/logs/exitcodes.txt` 21/21 exit=0；`r0/p3/logs/exitcodes.txt` 25/25 exit=0 |

## 3. 综合 1/1（闸门未过 → 未布线）

TD Release_2026.2，`T:/`=`r0/td`、`Y:`=项目根（`td_env.ps1 -Force`），1 会话，syn_1 **40.3 s**：

| 项 | bm-addr r0 `35ea7364` | **本候选** | 闸门 | 结论 |
|---|---|---|---|---|
| 全局 WNS / TNS | +0.113 / 0.000 | **+0.233 / 0.000** | WNS ≥ +0.3 | **FAIL** |
| slice | 3,085 | **3,076** | ≤ 71,680 | pass |
| ERAM（core） | 26（22） | **26（22）** | 26 与实例相符 | pass |
| reg / DRAM LUT | 1,646 / 32 | 1,656 / 32 | — | +10 = `wbase`/`adler_hold` |
| 原最差路径 | `byte_k_reg[2] → smem_waddr_r_reg[14/15].d` +0.113（7 级） | **已移出报告集**（smem_waddr_r 全文 0 次） | — | 目标锥已清 |
| 新最差路径 | — | `u_core/hp_r_reg[0] → bm_b.addrb[4]` +0.233（7 级：2 ADDER+4 LUT+ERAM） | 包范围外 | **卡住闸门** |

- 结论：本包唯一允许改的两个锥（frame_top 写地址、adler gate）都已从关键集消失，综合 WNS 从 +0.113 提到 +0.233；但下一名是**冻结的 core bm 读地址锥**（`hp_r → bm_b.addrb`，属 bm 存储/地址逻辑，dispatch 明确不得改），+0.233 < +0.3，闸门不可达。

## 4. 完整性/回退

- 报告均工具直接 `-file`/`file copy` 到 `r0/td/`：`syn_gate_timing_a1.rpt`、`syn_gate_area_a1.rpt`、`syn_console.log`、`syn_1/run.log`；SHA 见 manifest。
- bitgen not_run：phy 未启动，无 `.bit/.cwc`、无下载、无 Flash、无 QoR/seed/时钟/exception 变更、无 frame/SDC 越界编辑。
- 工作树已恢复为 G1 全绿基线 `35ea7364`（core）/`18d51b1b`（frame）；候选与基线均在 `r0/base/`、`r0/td/`、`r0/patch.diff` 留档。
- 未改 `workflow/tasks.json`；未派测试者（按 dispatch 失败即收尾）。

## 5. 给规划的最小下一步（不在本包执行）

1. T10 收口：**3/4 PASS + 1 ⚠**（功能/吞吐逐位全绿；G2 时序未闭）。
2. 若要继续，剩余违例全部落在**冻结的 core bm 读地址/CE 锥**（综合 `hp_r→bm_b.addrb` +0.233；routed `pos/sdata_ptr/dtot_r/blk_final1/hp_r` 各 −0.057…−0.084），已超出“adler/smem 写地址”授权；需用户明确新授权（core 地址锥或更大器件/QoR）。
3. 不应以“+0.3 闸门”再派同类包：本包证明该闸门在现行冻结范围内不可达。

## 6. 恢复入口

`T10.a1-adler-smem/r0/`（本文件、`CANDIDATE-MANIFEST-adler-smem-r0.json`、`patch.diff`、`base/`、`p2/`、`p3/`、`td/`、`lessons-r0.md`、`cdc-static.md`）。

## 7. r0-route（后续 revision，2026-10-22）

规划豁免 +0.3 后已执行 **route-only 1/1**（对象本文件候选 core `611ad704` / frame `cc330814`）：Routed **SWNS −0.541 / STNS −52.866、299 违约端点**、hold PASS、资源在器件内、单时钟静态 CDC 已取证 → **FAIL 收尾**，无测试者、无 r1。详见 `../r0-route/result-r0-route.md` 与 `../r0-route/CANDIDATE-MANIFEST-adler-smem-r0-route.json`。**本节之后的结论以 r0-route 为准。**
