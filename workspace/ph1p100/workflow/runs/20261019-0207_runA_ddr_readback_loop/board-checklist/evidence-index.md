# evidence-index.md — T11.runC-board-checklist 哈希链证据索引（0 不一致）

- task_id：`T11.runC-board-checklist`（0207 runC P4，round0）
- run：`20261019-0207_runA_ddr_readback_loop`
- 生成：2026-10-19T19:2x+08:00（本包开发，opencode 子会话）
- 复算入口：`board-checklist\recompute-hash-chain.ps1`；原始逐项日志：`board-checklist\hash-chain-recompute.txt`（每项一行 `MATCH|组|路径|SHA256|字节`）
- **结论：56 项逐项复算 = 0 不一致（mismatch=0）、0 缺失（missing=0）。**
- 复算口径：
  - run 内冻结件：`Get-FileHash -Algorithm SHA256`（在盘字节）+ 字节数，与各 manifest 登记值比对；
  - worktree 源文件：SHA256（在盘字节）+ **git blob**（`git hash-object` 默认与 `--no-filters` 双口径，至少一者等于冻结 blob；跨 checkout 以 clean-filter 口径 blob 为准，可消除 CRLF/LF 差异）；
  - P2 manifest 仅以冻结前缀 `0F67D299…6919` + 16,523 B 绑定（完整 SHA256 见原始日志对应 MATCH 行）。

## 1. 链结构（自上而下，逐节可复算）

| # | 链节 | 绑定值 | 复算结果 |
|---|---|---|---|
| 1 | RTL diff `checker-integrate\candidate.diff` | `5907B38F6241D3DCC163EEAEB78D67941C8AB0C2967B6D66EDF5C8C1C6E18CB2` / 59,091 B；8 个 `diff --git` 头、2 个新文件、NUL=0、UTF-8 无替换字符；`git apply --check --cached`（HEAD→index）rc=0、`--reverse`（worktree→HEAD）rc=0 | MATCH |
| 2 | 候选源文件（worktree `upstream\ph1p100-pcie-ep-fpga-wt0207`，branch `opencode/runC-0207`，HEAD `b0282d2a8dfdf11e6e63779510fe380dfffb5e83`） | P1 manifest r1 的 9/9（`ddr_readback_int.v`、`ddr_frame_readback_checker.v`、`ph1p_pcie_ep_top.v`、`pcie_ep_engine.v`、`ep_bar_win.v`、`tb_ddr_readback_int.v`、`tb_ep_bar_win_debug.v`、`compile_checked.f`、`00_all_debug.tcl`）：SHA256+git blob 全等 | 9/9 MATCH |
| 3 | P1 manifest（r1） | `68AB235E9C593E60EDD08EDE176C77D83082A9423E5920FAB78C195188D167BD` / 9,368 B（另 P1 工件 `geometry-audit.md`/`dev-result.md`/`regression-summary.txt` 全等） | MATCH |
| 4 | P2 manifest + 构建件 | manifest `0F67D299…6919` / 16,523 B；19 项工件全等（含 `commands.log`、`td_00_all_debug.log`、`final_timing.rpt`、`route_flow.status`、`chk.timing`、`run.log`、`phy.area`、CWC 校验输出、`hardware-ready.md`） | 19/19 MATCH |
| 5 | bit / CWC / BID | bit `5B67A8F5925327BA9D0442D9E4228FCFD254C80A2F86D921CEDA70ECAE111D52` / 5,224,027 B（`phy_1\ph1p_pcie_integration.bit` 与 `cw\compiled.bit` 逐字节相同=同源配对）；CWC `8DDA54D4EFA8E6BE728A6EBB34686F25DE90A36B039EDA6F831DFB9C346C664F` / 143,444 B；BID `A068E42E50B2D9D9CED1AE85F9CFA9E272BBCE99AE83192CA7FC930AF9ECF1DB` / 151,492 B | MATCH |
| 6 | P3 manifest + 工件 | manifest `01938EBB2EB6B56C18479877C64AD862F6DEA5A724B2727F692BF4F710C2AF72` / 17,323 B；19 项工件全等（msim 双 TB 的 vlog/vsim/commands/vsim_stdout/run.do/abs.f、rtl-hash-check、freeze-verify、campaign-summary、dev-result、dev-notes、lessons）；两新 TB `tb_ddr_readback_campaign.v`（`e1128cde…9160`/17,026 B/blob `0f1ab480…`）、`tb_ddr_readback_1080p.v`（`f63c1d8e…ce69`/10,159 B/blob `a75f5b4a…`）SHA+blob 全等 | 21/21 MATCH |
| 7 | test-reports（本轮四份） | `T11.runC-checker-integrate-r0-integrated.md` `e6ac12fd1c610a90b00288dea83f5644c5d3cc83d04507861556eaf014b6f754`（14,269 B）；`…-r1-integrated.md` `abbabdff9f8161c8bb32351b61a0bfcd0ff45be4a84267d51458b3b374ab9f33`（8,683 B）；`T11.runC-build-r0-integrated.md` `f633ee0dfcfbfe81a907422ad3724093d9350142c8b3844ff27920758661c32c`（10,200 B）；`T11.runC-sim-campaign-r0-integrated.md` `069938df42e655d2f9d5c35bccc8d8cf9993eced597ca0a48c6a238a1b5828b1`（11,526 B） | 记录锚定 |

## 2. 分组统计与保护审计

- 总数 56 = P1 5 + P2 19 + P3 19 + worktree 9 + P3 新 TB 2 + 旧候选保护 2；**0 不一致、0 缺失**。
- 保护审计（SHA256 复算不变）：板载基线 bit `bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0`、基线 CWC `8d2998b96ef1763c14a1302118235a687488297ce496692b1f6cd95d76981026`；P1/P2/P3 冻结件未动；旧候选并列未覆盖。
- worktree 指纹：HEAD=`b0282d2a…` 未变；6 M + 4 ??（与 P3 冻结一致；本包只写 run 目录与 D: 暂存，不写 worktree、不 commit、不 push）。
- 暂存（可选预加载物料，未下载）：`D:\anlogic\runa_runC\20261019_192056\` 为**新建**目录（首跑建空目录后由同一复算脚本复用；零覆盖、零删除），内含 `compiled.bit`（SHA `5B67A8F5…1D52` MATCH）、`compiled.cwc`（SHA `8DDA54D4…664F` MATCH）、`preload.bwcmd`（未执行）、`staging-record.txt`。
- 本轮**未执行**任何硬件动作：未 connect_cable、未 read_device_id、未 download、零 flash/efuse/SPI/svf；原因见 `board-checklist.md` §1（需在场用户确认板窗空闲；19:14 起并行线 0212 在本机运行 TD 构建）。

## 3. 边界（不构成板测结论）

本索引只证明“冻结件互相同链且未被改动”。G3（身份/新字上板实测）= **not_run**（待用户“回来点两下”）；G2 继承 P2 PASS（本包不复算）；G4 not_run。任何读数必须绑定本索引中的 bit/CWC SHA 才可计入后续判据（见 `board-checklist.md` §8）。
