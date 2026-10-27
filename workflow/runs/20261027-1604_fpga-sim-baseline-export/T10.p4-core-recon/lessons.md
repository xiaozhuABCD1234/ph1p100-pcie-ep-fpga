# lessons · T10.p4-core-recon（round 0）

只记可复用根因/触发/规避与验证入口；本轮未定位到候选缺陷，禁止把下述内容当作候选判定。

## L1 先跑“冻结基线同 stimulus”再判候选

- 触发：本 TB 用单 stimulus 同时驱动 r2 冻结字节 `img_algo_parallel_top`（`7f1e0544…`）与候选 `img_algo_parallel_top_p4`。
- 现象：两者**同时**出现 `good=1 / abort=1`、`abt_ev=4`、缺 `eof`，且互相 `diff=5`。
- 复用结论：出现“基线也 abort”时先怀疑激励/TB 契约，不要写成候选 FAIL；同理也不得因为“基线也这样”就判候选通过。基线对照必须与候选同 stimulus、同 ready，且分别统计。

## L2 帧控制契约（`s_sof/s_eol/s_eof`）是这类 4px 流水最容易错的地方

- 该 DUT（`algo_rowwin3_p4`）的 abort 条件：`s_abort` / ACTIVE 中再来 `s_sof` / `s_eol != (in_w==m_words-1)` / 在 `(H-1,last)` 处 `!s_eof` / 非 `(H-1,last)` 处 `s_eof`。
- 本轮 `s_eol=(inner%16==15)`、`s_eof=(inner==767)`、`s_sof=(inner==0)`、2 帧 back-to-back，仍在第 1 帧早期出现 abort 且 y8 只出 14 个 token。**未定位**。
- 下一步优先用 r2 已跑通的 `tb_img_algo_equiv_p4.v`（`1350d75c…`，r2 `CHECK_REF_NEW PASS`）当驱动基线，而不是继续自造驱动；差异点按单变量隔离：`s_valid` 门控（`started`）、双 DUT 同步接受（`b_s_rdy && p_s_rdy`）、`he_ready` 常 1、帧数（本 TB 2 帧 vs r2 TB 2 good + 1 abort）、`cfg` 握手后首拍延迟。

## L3 ModelSim ASE 18.1 调用姿势（PowerShell）

- `Start-Process -ArgumentList @('-c','-quiet','-do','run -all; quit -f', ...)` 会被空格重组，vsim 把 `quit -f` 的 `-f` 当文件名 → `Failed to open -f file "tb_…"`。
  正确：拼成**一个**字符串 `'-c -quiet -do "run -all; quit -f" tb_x +BP=0'` 传给 `-ArgumentList`。
- `Start-Process -PassThru` 后 `WaitForExit(ms)` 已返回，但 `$p.ExitCode` 可能为空；判定改用日志内容（`TB_*_PASS` 行 + `** Error` 扫描），不要只看退出码。
- 超时控制用 `WaitForExit($ms)` + `$p.Kill()`（本次 300 s/次），满足“可安全终止”要求。

## L4 `$fopen` 路径

- `reg [1023:0] fname; $value$plusargs("TOKFILE=%s", fname); $fopen(fname,"w")` 在本机 vsim 下返回 0（打不开）。
  规避：TB 内 `$sformat(tokname, "tokens_bp%0d.txt", bp)` 写**相对名**（相对临时运行目录），由 `run_sim.ps1` 拷回 `sim/logs/`。字符串从 plusarg 取时只用于短名/枚举，不用于完整路径。

## L5 交付目录洁净

- 编译库/transcript/wlf 一律放 `%TEMP%\fpga_t10_p4core_<时间戳>`，交付目录只保留 `sim/logs/*.log|.txt`（文本）。入口脚本每次新建带时间戳的临时目录 → 天然“从干净 work/ 复跑”。

## L6 预算

- 本次派发默认 30 次工具调用；实际使用约 35 次（超出部分用于轨迹排障与冻结收尾）。后续同类任务应在**第一次仿真失败后立即**转用已验证 TB 骨架，不要在自造驱动上反复试参。

## L7 缺失源复核结论（可复用）

- `bayer_raw10_demosaic4_p4.v` / `img_algo_parallel_top_p4.v` 的 r2 精确字节（`4e108dd8…` / `1cb8262a…`）在三个允许搜索根内**不存在**：仅命中 `a5c40734…` / `e420685c…`（r3 绑定/漂移值，共 6 处）与 `D:\fpga\archive` 的 NOHIT。任何后续轮次不得再把这两个漂移副本称作 r2 字节。

## attempt2 增量（round0 attempt2 → ready_for_test）

### L8 驱动基线优先级高于自造 TB
- 把 r2 `tb_img_algo_equiv_p4.v` 原样移植（只加只读 dump 抽头）后，同一候选在 3 种 ready 模式全部 `CHECK_REF_NEW PASS`、`TB_IMG_ALGO_EQUIV_P4 PASS`；attempt1 的唯一差异是自造 TB 的 `s_sof/s_eol/s_eof` 契约。帧控制类回归应先复现已验证 TB，再谈 DUT 判定。

### L9 等价判据要三条腿
- 只有差分（base vs 候选）漏"两者同错"；只有参考模型漏"模型与规格同错"；再加 1-LSB 变异负对照才能证明比较器有灵敏度。三者应同轮执行并分别落证据文件。

### L10 ModelSim 观测抽头的正确姿势
- 在已有 `tsk_rec` 的同一 `if` 条件内加 `dump_tok`，可零风险产出与 scoreboard 完全同源的 token 序列（不改帧控制）。
- 抽头文件名用 `` 相对名 + `+TAG` 区分复跑；不要用 `("%s")` 传完整路径（attempt1 L4）。

### L11 复跑/跨模式对比设计
- 同一模式重复跑用于 E4（应逐 token 相同）；跨 ready 模式只比较"候选差异 ≤ base 差异"（r2 已明示 frozen 模块对 stall 模式敏感），不要写成跨模式逐字节相等。

### L12 只读核对节奏
- RTL 首检 + 尾检各一次（本次均 14/14，0 mismatch），并写入 manifest 的 `rtl_equivalence`；这是"候选未变"的最便宜证据。