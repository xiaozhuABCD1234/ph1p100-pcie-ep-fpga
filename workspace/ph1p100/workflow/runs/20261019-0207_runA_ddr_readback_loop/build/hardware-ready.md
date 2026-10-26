# hardware-ready — T11.runC-build 候选（READY_FOR_P4；未下载 / 未写 Flash）

任务 `T11.runC-build`（0207 runC P2）冻结候选：新 debug 位流 + 配对 CWC（含新字 word9..15 探针）。构建于 `upstream\ph1p100-pcie-ep-fpga-wt0207`（branch `opencode/runC-0207`，HEAD `b0282d2a…`，worktree-only），产物在 run `build\**`。

## 1. 门槛摘要

| Gate | Result |
|---|---|
| Build | PASS：exit 0（`commands.log`）、858.7 s、PRJ-1406(syn+phy)/PRJ-1424/T07_ALL_DONE/T11_DBG_ALL_DONE、Confidence=Routed |
| G2 STA | PASS：SWNS 0.104 / STNS 0.000 / HWNS 0.020 / HTNS 0.000 ns；0 违例（setup+hold NUM_FEPS=0）；与 r3 对比 SWNS 0.134→0.104（≥0） |
| Resources | PASS：LUT6 18722/71680 (26.12%)、slice reg 26555/143360 (18.52%)、ERAM 162/300 (54.00%)、IO 107/286、DSP 0/220、PCIE 1/1 |
| CWC | auto_created_cwc1：16 view nodes（word0..8 + word9..15）、512 trigger / 512 data、26 pieces、512/512 覆盖 |
| CWC validator | PASS：`--multipiece` rc=0（0 失败）；strict 仍拒多片（默认未改） |
| bit | `5B67A8F5925327BA9D0442D9E4228FCFD254C80A2F86D921CEDA70ECAE111D52`（5,224,027 B）= `cw/compiled.bit`（同源配对） |
| CWC | `8DDA54D4EFA8E6BE728A6EBB34686F25DE90A36B039EDA6F831DFB9C346C664F`（143,444 B） |
| BID | `A068E42E50B2D9D9CED1AE85F9CFA9E272BBCE99AE83192CA7FC930AF9ECF1DB`（151,492 B） |
| 离线边界 | 未下载、未触硬件、零 Flash/efuse/SPI/svf、未推送；候选并列不覆盖 |

## 2. 上板预期值表（供 P4“回来点两下”清单冻结；guide §6）

| word | 期望值/行为 |
|---|---|
| word0/1/2（身份/长度/CTRL） | 同基线命中（`50434946` / `31414B52` / `00010000`；CTRL 以 GUI 实读为准） |
| word3 | 推进 |
| word6 | good 增长（相机活）；bad/hdr/crc=0 |
| word9（CHECK_STATUS） | 稳态 `0x3E`；恰逢校验中可采样到 `0x01`（可解释，重采一次为准） |
| word10（CHECK_WORDS_READ） | `0x0009E400`（648,192；1080p 满帧） |
| word13（CHECK_RUNS） | ≥1，且增量≈word3 增量 |
| word11/12（HDR/PAYLOAD CRC32） | 原文记录；与 word14/15（smp1=head[20]/smp2=head[21]）存储 CRC 对照（如 GUI 保留） |
| 备注 | 新 CWC 为 16 字（word0..15）；GUI Watch 列表以 TD 实际生成的 16 节点为准；实例名 `auto_created_cwc1` |

## 3. 回退 / 恢复

- 丢弃 run `build/**` 产物即可（默认不删；需删时按根 AGENTS 单文件路径执行或交用户）；旧候选全部原位并列：板载 `bfafdf97…`、回退 `e81d353b……2b9a`、证据 `2385cded…1873`、`AFFC4396…`。
- SRAM 易失；重下旧 bit ≈30–40 s；板已断电分支先重下。P4 仅 SRAM、≤1 次下载、失败不阻塞、零 Flash。
- 参考：本 run `build\candidate-manifest.json`、`dev-result.md`；基线 `debug-spec\board-runbook.md`、`readback-criteria.md`（本 run 不覆盖）。
