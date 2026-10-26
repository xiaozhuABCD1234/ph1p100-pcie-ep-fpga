# lessons-learned — T07.rk-align-backend（round0）

只记**可复用**的根因/触发/修正/验证入口，不记流水账。

## 1. 工具与环境

* **中文路径**：ModelSim 与 TD 都会在含中文的 cwd/文件路径上失败（sqlite 打不开 `work/_lib.qdb`、
  vlog 打不开文件）。可靠做法：临时 `subst` 一个 ASCII 盘符指向项目根，所有工具在映射路径下跑，
  结束只撤销自己建的映射（`run_sim.ps1` / `run_td.ps1` 已实现并记录到各自 `commands.log`）。
* **PowerShell 5.1 三个坑**（本包都踩过）：
  1. 原生命令（vlog/vsim/td）的 stderr 会被当成异常 → 调用前后把 `$ErrorActionPreference` 置 Continue 并看 `$LASTEXITCODE`；
  2. 数组 splat 给原生 exe 传参不会给含空格参数加引号 → vsim 的 `-do "run -all; quit -f"` 被拆成多个选项；
     稳妥做法是写 `run.do` 文件（本轮还遇到"刚写完的文件被 OneDrive 占位符读到旧版本"，加"写完立即读回校验"即可）；
  3. `>` 重定向写出来是 UTF-16 → `git diff > patch` 生成的补丁 `git apply` 会报 "No valid patches in input"；
     用 `cmd /c "git diff ... > file"` 或 `Out-File -Encoding ascii`。
* **不要用 `Set-Content` 改含中文的源文件**：PS 5.1 默认按 ANSI 写，会把 UTF-8 中文字节打坏（本轮
  `ph1p_pcie_ep_top.v` 被打坏过一次，只能从 peer 冻结副本重做）。用编辑器/结构化替换工具改。
* **peer 源码是 GBK**：本项目的 peer 驱动/FPGA 源里中文是 GBK，新建文件若写 UTF-8，
  混编不会影响 GCC/编译器，但编辑器会显示乱码；补充说明写进 patch README。

## 2. peer 源码的"TD 能过、ModelSim 不能过"

* 声明在使用之后（隐式网）是**peer 的既有写法**：`ep_bar_win.v` 的 `rd_addr32/rd_len_dw`、
  `pcie_ep_engine.v` 的 `tl_tx_state/TL_TX_*`、`ph1p_pcie_ep_top.v` 的 `tl_clk_user/pl_link_up/...`、
  `ui_cfg_imx415.v` 的 `reg_index`/`iic_busy`。修法只有一个：**把声明挪到第一次使用之前**（行为不变）。
  ⇒ 结论：peer 声称"TB 只写不跑"是真的；想跑必须先把这些声明顺序修掉。

## 3. 测试台本身的坑（会伪装成 DUT bug）

* **假 AXI 从机空档逻辑**：`if (gap) rvalid<=0` 后必须在同一次推进里 `beat<=beat+1`，
  否则恢复时**重复上一拍** → 数据整拍错位；数据函数若只有低字节变化会被"整拍错位"骗过，
  用「每个字节都随地址变化」的模式生成数据更灵敏。
* **按值传参的任务**：`task chk(input got, exp)` 在调用时就把值拷贝进来，
  想"等几拍再看信号"必须把等待放到调用点或把选择器传进去，否则永远读到旧值（后续检查假失败）。
* **Verilog task 的形参位宽**：`input [7:0] first_pix` 会把 `line*64` 截断（每行都发第 0 行），
  伪装成"数据重复"的 DUT bug；行号/像素号一律用 `integer` 或足够宽的向量。
* **FIFO 比较要用位选**：`mem[idx] >> (8*n)` 是 32bit 结果，和 8bit 的 got 比必然不等；
  用 `mem[idx][8*n +: 8]`。
* **复位必须给脉冲**：把 `rst_ddr=1'b0` 常连，读指针/同步器初值是 X，`pop` 也变 X，
  整个 packer 冻结 —— 看起来像"写者不动"，其实是 TB 没复位。
* **脉冲用 posedge 采样器粘滞住**再比，别在同一个 negedge 直接比（单拍脉冲还没被采样）。

## 5. round1 复盘（三维 FAIL 后的修复经验）

* **同一 module 里"同一 reg 两处声明"是致命的**：TD 只在警告里说 `HDL-5333 second declaration ...
  ignored` 就继续综合（并产出了 bit！），而 ModelSim `vlog` 按 error 中止 → 交付的"G1 入口"
  在冻结输入上直接编译不过。**教训**：`vlog` 必须作为冻结前强制度量（0 错），不能只看 TD 能过；
  任何"改完 RTL 只跑一次 TD 就冻结"的流程都会漏掉这类错。
* **证据的时间绑定要机器化**：`run_sim.ps1` 不清输出目录，旧 `vsim.log` 会留在原地 →
  "目录里有 ALL PASS" 不等于"这次跑过"。修复轮的做法：新目录 `r1_*` + 逐 run 检查
  `vlog.log: Errors: 0` 且 `vsim.log` 时间戳晚于 RTL 末次修改。
* **跨源（A/B）契约必须"按身份"而不是"按值"**：pusher 只拿 A 路基址去比对 `ddr_base`，
  B 路就永远拿不到 release；两根 toggle 被两片 writer 共享，A 的事件还会清 B 的保护位。
  **教训**：多实例共享外设时，release/lock 事件要么带身份（per-instance 通道），
  要么把身份并入比较对象——**"值恰好相同"不能当身份**。
  定向验证要按"每发布帧恰好 1 次 release + 交叉场景计数不变"来断言，而不是只看帧推没推成。
* **易变日志不能进冻结清单**：`commands.log` 之类每次调用都会追加的文件一旦入清单，
  冻结后的任何一次运行都会让"基础哈希"失效（round0 实测 22 B 漂移，三维都登记了）。
  做法：清单生成器显式排除并把规则写进 manifest（`volatile_excluded`），
  同时**生成后逐条自检**（`manifest-selfcheck.json`）。
* **时序违例要分清"逻辑深"还是"布线远"**：本包最差路径 7.44 ns 里 52% 是 net delay、
  逻辑级 9——在 187.5 MHz 的字节域里，这属于"架构级"成本（每拍吃满 4 字节、CRC 逐拍递推、
  CSI 不可反压），不是加一两个 `set_max_delay` 能解决的；要动就得动数据通路结构，
  属于需要规划者决策的范围（本包按指令 blocked，不擅自放宽前提）。

## 6. 设计侧经验（round0）

* **TD 的 HDL-8007 一次就抓到了**：同一个 reg（`protect0/1`）同时出现在「同步块」和
  「AXI 状态机块」里，TD 报 `constantly driven from multiple places` 并让它变黑盒；
  ModelSim/iverilog **不报**。修法：把"置位"和"清零"收进同一个 always，跨块只传事件线
  （本包：release 事件由同步块产生，保护位只在 AXI 块里写）。
  * 这是 peer 注释里明确预警过的坑（`cam_ddr_writer.v` 的 HDL-8007 说明），仍然复现了一次。
* **TD 的工程分阶段会丢会话变量**：`create_project` 才设 device_name/package_name；
  另一个会话 `open_project` 再 `launch_runs`，run 的 settings.cfg 里这两项是空的，
  子流程报 `can't read "device_name"`。想分阶段就在每个新会话里显式 `set device_name/package_name`，
  或者干脆单会话跑完整流程（本包 `00_all.tcl`）。

* 「超时就把包丢掉」是**错的**：TL 口上 valid 拉起来之后必须持稳到被收走；超时只能
  「把已经开始的那一个包补完再排空」（本包把原来"未开始就放弃"的分支删掉，改成 bounded error 保持）。
* 「完成即释放源缓冲」也是错的：held 帧在被 ACK 之前必须继续锁住源块，否则写者会覆盖主机尚未 ACK 的帧；
  释放点应当只有 ACK / CANCEL。
* 所有权保护用「发布即保护 + 每个发布恰好一个 release（claim 后 ACK/CANCEL，或未 claim 的 pass）」
  才能把读/写窗口做成互斥，且不需要假设"推得快"。TB 里用「长 stall + 期间连续出帧 + 计数器」
  才能证明（本包 PHASE6/PHASE8）。
* 安全门的 ARM 校验要在**同一拍**判定 claim/pass（同域比较），任何跨域"稍后再判"都会出现竞态窗口。

## 7. round2 过程与设计经验（G2 setup：checked 完整性链本域重构）

* **时序重构先建差分 oracle**：把被改模块的**改前版本**（只读原源 `fpga/csi2/src/csi/csi_rx_packet_integrity.v`
  的**重命名副本**，`sim/tb/csi_rx_packet_integrity_ref.v`）与改后版并联、同一激励喂两个 DUT，
  逐拍比对"必须不变"的输出（本包：payload/valid/keep、packet_done、in_line、vsync、in_frame、frame_end/good），
  对"允许有限拍滞后"的输出（abort/计数器）用"ref 抬起当拍或之后 2 拍"窗口 + 静默点全量比对。
  这条 oracle 立刻抓到两个**真实语义缺陷**（都不是综合工具问题）：
  1. 把 4 字节/拍的 CRC 递推写成"固定 4 字节"会把 keep=0 时的补零字节也喂进 CRC；正确语义是
     **按本拍实际有效字节数**（1..4）推进——用最小 WC 包立刻暴露；
  2. 为了把计数挪出同拍链而**新增一个状态**会让状态序列多 1 拍、IDLE/HEADER 相位漂移，
     背靠背包头会被 IDLE 吞掉。修法：**不动状态序列**，把工作塞进**既有**状态（END_PACKET）的第一拍。
  教训：等价性不能靠"看代码觉得一样"+ 生成器自检——生成器只证明**函数**对，证明不了**调用方式**对。
* **差分 TB 的激励时序也是被测契约的一部分**：包间至少要留出"END_PACKET→IDLE→HEADER"的重同步拍
  （本包 ≥2 拍，TB 用 3 拍）；否则帧超时/头错误计数满天飞，看起来像 DUT 坏了，实际是激励踩掉了模块的既有等待条件。
  测短包用小 `PACKET_IDLE_CYCLES`、测帧超时用小 `FRAME_TIMEOUT_CYCLES`，且两个 DUT 必须用**同一参数**。
* **187.5 MHz 下"逐拍递推"的可行手段**（无 multicycle、不动时钟、不改前提）：
  ① 宽比较 → 小范围译码（4 组 17bit 比较器 → `tail` 低 3 位列译码）；
  ② **线性**递推函数写成扁平 XOR 树（GF(2) 矩阵生成 `crc16_upd1..4`；脚本自带 2 万+ 随机/边界自检），
     不要指望综合器"自己展开"串行移位+条件异或的写法；
  ③ 把"比较+计数"从递推路径挪到包尾的**既有**状态，让计数器 enable 只依赖寄存位/浅组合。
* **最差路径报告要读 cell/net 与终点**：本轮（round1）最差路径的终点是"CRC 错误计数器 enable"而非 CRC 本身——
  这决定了修法是"把 enable 变浅"，不是"给 CRC 加流水"（该域不可反压，插不进气泡）。
* **PowerShell 5.1 没有 heredoc**：不要把多行 python 塞进命令行（`<<'PY'` 会被 PowerShell 当重定向符直接报错）；
  用 `write` 工具落一个脚本文件再执行，或改用 `edit` 工具批量替换（`replaceAll`）。
* 本轮 G2 判定与残余时序见 `g2/README.md` §3.5 / `dev-result.json`（判据不放宽）。

## 8. round3 经验（入口编码 / 工具链）

* **"文档命令 = 实跑命令"必须被验证，而不是被假定**：round3 functional FAIL 的根因不在 RTL/TB，而在
  开发侧 round0–round2 的实际调用是"`Get-Content -Raw` 读冻结脚本正文 → `Set-Content -Encoding UTF8`
  写 `%TEMP%` 副本 → `-File` 跑副本"（PS 5.1 的 `Set-Content -Encoding UTF8` 会**加 BOM**，副本因此可用），
  而文档里写的是 `-File <冻结脚本>` 原样形式。冻结字节本身在文档化命令下不可运行（PS 5.1/ACP=936
  按 ANSI 解码**无 BOM 的 UTF-8** 会吞换行：144→136 行，`$doPath` 被并进上一行中文注释）。
  教训：跑"交付入口"时**不要**用任何副本/包装/等价 launcher；若确实必须用，就在 `actual-commands.json`
  里如实记下，并把该 launcher/环境纳入冻结入口的一部分。
* **Windows PowerShell 5.1 + 中文注释 + LF + 无 BOM = 代码行消失**：.NET CP936 解码器把"行尾悬挂的
  首字节 + 0x0A"并吞为一个字符（Python 的 `cp936` 解码器**不**这样处理，用 Python 复现不出来——必须以
  `Get-Content` / `[Encoding]::GetEncoding(936)` 的 .NET 行为为准）。症状是注释后面的**代码行被静默吞掉**，
  且 `-File` 下进程 **exit 0**。修法（最小）：文件前置 UTF-8 BOM（内容其余逐字节不变）；
  判据是产物（`vlog.log`/`run.do`/`vsim.log`）而不是退出码。`.tcl`/`.py` 不受影响（Tcl 按字节解析；
  Python 3 源码默认 UTF-8），不必顺手改。
* **"exit 0" 不是通过**：修复前的中止、以及 vsim 自身失败，`-File` 都可能给出 exit 0。
  复核一律以"三件产物齐备 + 完成标记"判。
* **数字类结论要实读原始 run.log 并留行号**：曾用"grep `*.timing` 找 `TMST-7700` 字面量"推断为 0，
  实际该 DRC 计数在 `phy_1/run.log`（place 2 / post-route 5）。grep 到一个词不等于读懂报告。
* **负对照是自证的必需品**：入口负对照（修复前失败留痕 `g1/msim/r3_entry_before_fix/`）证明修复有效；
  oracle 负对照（隔离树注入 M1 → `FAIL: 507 mismatches`，`g1/msim/r3_neg_m1/`）证明差分 TB 能拒绝坏实现。
  正对照/负对照与正式证据放同一层目录，复核者才不必重新发明。
* **"文档里写了的证据文件"必须真在盘上**：原 round3 实例被上游额度打断后，三处元数据引用
  `r3_neg_m1/mutation.json` 与入口 AST 校验输出，但这两个文件实际上都**没有落盘**（会话在写它们之前中断）。
  接手的新实例逐项做"引用路径 × 磁盘存在性"核对才发现，并在 `r3v_neg_m1/` 完整重做。教训：引用≠落盘，
  收尾清单应含一次"所有被引用的证据路径存在性/完整性"的机械核对（round3 复核即按此执行）。
* **给编码缺陷做校验的脚本，别自己踩同一个坑**：原实例写的入口 AST 校验脚本（`r3_entry_before_fix/entry_ast_check.ps1`）
  自身是"UTF-8 无 BOM + LF + 中文注释"，被同一缺陷击中——`$PSScriptRoot` 赋值被并进注释变 `null`，运行即报
  Join-Path 空值、产不出任何结果（失败留痕 `g1/msim/r3v_entry_before_fix/old_ast_script_attempt.txt`）。
  任何将被 PS5.1 `-File` 执行的新 `.ps1`（含证据/校验脚本）从第一天起就应带 BOM 或写成纯 ASCII。

