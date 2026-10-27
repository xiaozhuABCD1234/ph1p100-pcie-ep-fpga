# INT.P4 lessons（可复用根因/触发/修正/验证入口）

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


## r2（2026-10-27，round2 修复）

1. **"全或全无 ready" 扇出不能穿进另一模块的行缓冲读写调度**（r1 E1 的真正结构）
   - 触发：`y8_stream_ready = obuf_y8.full && gau.s_ready && he.s_ready` → `f_ready`（4 路灰度 s_ready
     相与）→ `bayer_raw10_demosaic4.pipe_en = !(m_valid && !m_ready)` → `algo_rowwin3.en/evt_en` →
     `ra0`（行缓冲读地址，fanout 320）→ 分布式 RAM 读 → `rb0_reg.d`。
   - 现象：5.333ns 下 330 个 setup 违例端点、WNS −1.549ns、TNS −271.427ns，最差 6.818ns（net 4.199）。
   - 修正：在**派生变体**里把 ready 变成寄存器输出（2 拍弹性级，count 寄存器驱动 ready），
     `pipe_en` 只依赖本地 count；再在 4 路灰度流与 3 个输出消费者之间加一级，切断 obuf→分支的内部
     ready 链。330→112 端点、WNS −1.549→−0.637（两次综合）。
   - 验证入口：`equiv_seedmode{0,1,2}.log` 的 `CHECK_REF_NEW PASS`（同激励、同 ready 形态下
     y8/gau/he 逐 token 一致）。
2. **综合临界路径的起点要落在 DUT 内，否则先修测试框架**
   - 现象：r2 run1 的最差路径起点是 harness 的 `gb_reg[1]`（捕获产生器状态寄存器组合驱动
     `s_valid/s_data`），穿过 DUT 准入与 P1 accept 才进入行缓冲。
   - 修正：harness 捕获产生器改成**寄存器输出 beat**（真实捕获源形态），同时把 `ddr_*ready/rvalid/
     rdata` 全部由行为 DDR 从模型驱动（r1 的 `HDL-5314` 未驱动告警因此消失，`u_arb/u_egress/u_store`
     重新出现在层次表）。
   - 教训：综合前先看 begin/end point 归属；harness 组合逻辑一旦入路，改 RTL 也可能白改。
3. **`Viol Endpoints` 只能取统计，不能数打印路径**
   - r1 的 `01_synth.tcl` 用 `regexp {Slack\s*:\s*(-[0-9.]+)}` 数报告里打印的路径行，得到 10，
     而 `flow.status` 的 `NUM_FEPS` 是 330；`Report Scheme: 10 end point(s) per path group` 只是
     打印条数。r2 起从 `flow.status` 取 `Setup ... NUM_FEPS`（再用报告头 `Viol Endpoints` 交叉核对），
     打印行数改名 `INT_SYN_PRINTED_PATHS` 单独输出。
4. **行缓冲改 ERAM 不是免费换法**：给 `algo_rowwin3` 的三块 bank 加 `(* ram_style="bram" *)` 后
   TD 并没有映射成 ERAM（ERAM 39、reg 5832 完全没变，netlist 与上一次逐项相同）。原因是读数据寄存器
   （`rb0/rb1/rb2`）带异步复位，无法被 ERAM 输出寄存器吸收；要换法必须改读调度（读地址提前一拍）
   或去掉复位，属跨包改动。**结论：为省 synth 额度先做一次"属性实验"是浪费**——属性类改动要用
   面积报告的 ERAM/reg 计数先验证是否真的生效，否则不要占额度。
5. **额度用尽就停**：round2 授权 3 次 synth（终身 6），实际 277→112→112，第 3 次是无效实验；
   G2 仍未过即按规则返回 FAIL/差距，不申请第 4 次、不改约束（5.333ns 与 0 违例门槛未动）。
6. **既有 HE 停顿敏感性（本轮新发现）**：同一份基线 `gray8_he_cdfmin_frame`，只改输出 ready 序列
   （`CONTROL_REF_REF2`，不同 LFSR 种子）就出现 48–99 处 HE 输出差异；说明其直方图读改写/旁路在
   不规则 `en` 下会漏计。等价性只能声明"同激励 + 同 ready 形态"；任意反压下的 HE 像素内容在基线
   里本来就不唯一。后续若要 P4 全尺寸/任意背压下 HE 一致，需要单独任务修这个模块（要写权限）。
7. **派生副本的最小化**：本轮最终只保留 2 个派生文件（demosaic 输出弹性级、并行顶层 stage B）
   + 1 个等价 TB；行缓冲/gaussian 的两个副本是无效实验，已移出候选目录并在 manifest 登记
   （不删、不编译）。派生件必须"逐字复制 + 明确 diff 清单"，否则等价 TB 也证明不了语义。

## r1（2026-10-27，round1 修复）

1. **同一拍喂两个消费者时，每个消费者的 valid 必须由"对方 ready"门控**（r0 F1/F3 真正根因）。
   - 触发：`s_ready = a_ready && b_ready`，但 `a_valid`/`b_valid` 直接用源 valid（只有一侧被对方 ready 门控）。任一侧反压时，另一侧仍能接受源"没交出去"的同一拍；源保持该拍 → 该侧反复吃到同一拍。
   - 现象：A+ 入口重复吃 5 字节组 → 压缩流从第 55 字节起不符、raw_len 仍 3840（因为 A+ 按自身接受数计），A+ 提前收满 W*H/4 拍后 `in_ready` 永久为 0 → 采集在 beat 760/768 死锁；mode1 下算法侧同样多消费，加上未选中 gau/he 输出缓冲占满共享流 → Y8 监视流 0 拍。
   - 修正：`pk_valid = s_valid && mon_side_ready`、`algo_s_valid = s_valid && pk_ready && !raw_mode`、raw `m_valid = s_valid && pk_ready`、`s_ready = mon_side_ready && pk_ready`；未选中算法 `ready=1` 排空。
   - 验证入口：`integrated_mode4_extra.log`/`integrated_mode1_extra.log` 的 T2（监视反压+DDR 写停顿）必须 `pk beats==768`、`stream_len==3965`、`m_beats==768`；mode1 与 mode4 的 A1U1 样例三文件哈希相同（79e35f28/1357408f/76d88910）。

2. **"未完整帧不得成功提交"要在 store 之前拦，而不是事后改状态**。
   - 修正：EOF 拍锁存 `int_ok_r = (拍数==W*H/4) && (EOF 计数==1)`，`store.wr_last = core_out_last && int_ok_r`；A+ 仍 `core_commit` 但判定不成立时 `wr_abort` + `rel_status=1`，不 publish/不 arm/不 export。
   - 验证入口：T6（EOF 打在 700/768 拍）必须 `not published`、`not exported`、`arm_count==0`、`dropped==1`、`aborted==1`。该场景在 r0 RTL 上会 export，是拒绝旧行为的靶向用例。

3. **多场景 TB 必须每个场景独立复位 + 独立计数**。
   - r0 的失败一部分是 TB 记账（`arm_count` 不复位、用 DUT 绝对计数器判第二场景），会掩盖真实缺陷也误报。
   - 修正：`scn_begin` 清 TB 累计器；`rel_*` 用粘滞采样（一拍脉冲不要用轮询碰运气）；每场景判据只看本场景。

4. **综合前先把顶层 IO 降到器件内是合法且必要的**，但"测试框架本身"不能成为临界路径。
   - 做法：`integrated_delivery_synth_wrap.v` 原样实例化 DUT，把 DDR/捕获/描述符/PCIe/观测面换成片上模型 + 32bit 异或观测寄存器（2813→42 IO），不伪造引脚/ADC/时序。
   - 坑：框架里用 `% (W/4)`（480）算行尾，被综合成 18 级加法链（-8.360ns）并成为全局最差路径；改成显式列计数器后消失，真正最差路径才暴露（-1.549ns 在 P1 三算法共享流 ready 链）。**综合报告必须核对 begin/end point 是否落在 DUT 内**。

5. **TD 计数与日志**：`run_integrated_build.ps1` 的 console 日志用 `Tee-Object` 覆盖写，同一次派发内重跑会丢前一次的 `INT_SYN_*` 行；要保留多次结果需自己另存（或改成追加）。r1 因此只把最后一次 `syn_gate_*` 作为证据。

## r0（历史，已被 r1 取代）

6. store 的 drain 结束条件不能只靠 `drain_req` 的复位边沿：`dr_done` 与 `drain_req` 同拍会让 `DR_IDLE` 看到旧 `drain_req` 又重启一次。应在 `DR_CLOSE` 同拍清 `drain_req`。
7. TB 不能在 posedge 采组合 ready 再推进节拍：DUT 在同一沿更新次态后 ready 已掉，会漏握手。应在 negedge 后 `#1` 采 ready、下一 posedge 完成传输。
8. （**r0 误判，已撤销**）r0 曾把 mode1 Y8 停摆归因于 "`m_valid=1 && m_ready=0` → demosaic `pipe_en=0`"；r1 证明真正原因是未选中 gau/he 分支的共享 `ready` 反压 + 双消费者重复消费，按第 1 条修正后 mode1/2 监视流均 768 拍完整。
9. A1U1 样例必须由 RTL 产出再用独立脚本反算：`prep=0` 时 zlib 解压结果与 pk 原始字节逐字节相等，raw_crc 与 Python 重算一致，比"CRC 相同"强得多。
