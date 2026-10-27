# T10.a1-area-map r0 lessons

## 1. 「大数组被展开成寄存器」的判据与修法（可复用）
- 判据不是只看 `#reg` 总量，而是三组数对齐：TD `SYN-5114`（点名 `xxx_syn_<n>`）、gate `#seq/#reg` 与 RTL `#DFF` 的差额、以及数组容量 `depth×width`。本次三者一致指向 `cmem 4096×16 = 65536`。
- 真正阻碍 RAM 推断的不是“写来源多”本身，而是**写口位于带异步复位/abort 分支的主时序进程内**。TD 对这类进程里的数组直接放弃 RAM。
- 可用模板（同器件已验证）：把写口整理成**独立、无复位、单写**进程 `always @(posedge clk) if (we) mem[addr] <= data;`，读口单独一个寄存器读进程；写地址/数据/使能以组合信号在进程外合并，顺序按原“最后赋值优先”显式写出。`a1_frame_top.v` 的 `smem` 即此结构（4×ERAM20K）。
- 验证入口：`gate.area` 的 `#eram` 与实例数相符 + `SYN-5114` 消失 + `#reg` 回落到接近 RTL DFF。本次：reg 68085→2549、ERAM 4→8、slice 72904→15058。
- 不要只加 `ram_style`：本次未用属性也成功；属性无法解决复位进程内写的问题。

## 2. 综合 WNS 不能代表 G2（本 run 最重要的工程结论）
- r1 综合 +0.134 → 布线因容量未跑通，被当成“时序已闭合”。
- 本次容量解决后布通：综合 +0.104 → **布线 -1.115**（差 1.219 ns），1398 个违例端点。综合阶段的 net delay 是估算（本次最差路径 cell 35% / net 65%，布线后 net 明显更长）。
- 规则化：任何“时序通过”的结论必须标注阶段；只有 Routed 的 WNS/TNS/HWNS/HTNS 可作为 G2 依据。容量超限时不要用综合 WNS 作进展结论。

## 3. 分布式 RAM（DRAM LUT）是这块器件的时序陷阱
- `bm_a`/`bm_b`（2×16K×8）被映射成 8,432 个 DRAM LUT，组合读：地址寄存器 → 长线 → DRAM → 数据寄存器。布线后最差 6.15 ns（net 3.96 ns = 65%），与逻辑级数无关，纯粹是铺开阵列的长线。
- 21% 的 slice 占用并没有带来时序余量：**面积小 ≠ 时序好**。当存储落在 DRAM 上时，先看 `#dram lut`，再看 slice。
- 下一步唯一有证据的方向：bm 改同步读 ERAM + 预取（固定 1 拍延迟），而不是调 QoR 策略或 seed。

## 4. 地址 clamp 的等价改写（省一级串行进位链）
- `clamp_addr(pos+k, blk_n) = (pos+k < blk_n) ? pos+k : blk_n-1` 会串行“加法→比较→mux”。
- 用预计算 `limk = blk_n-k`（饱和到 0）和 `last = blk_n-1` 写成 `(pos < limk) ? pos+k : last`，加法与比较从 `pos` 并行出发。等价条件：`blk_n ≤ 4800`（无 13 位溢出）、`blk_n ≤ k` 时两式同为假。
- 效果：综合 WNS -0.283 → +0.104，面积几乎不变（+26 reg）。与 r1 的 `lim2` 是同一手法，可复用。

## 5. 流程/预算教训
- TD 默认 PhysicalDesign 流程末步会自动 `bitgen`；build-only 顶层有未约束 IO 时报 `BIT-8123`，`wait_run` 因此报 “run exited unexpectedly”，**看起来像布线失败，其实 place/route 都已完成**。判断布线成败要读 `route_flow.status`/`route.qor`/`*_pr.timing`，不要只看 `wait_run` 的返回。若不想触发 bitgen，应在 phy run 里关掉该 step。
- 默认 phy 流程**不含 `report_cdc`**；自己的 `open_run` + 报告段必须放在成功路径上，否则一旦 bitgen 报错就全丢。本次因此缺少 `cdc.rpt`。
- 综合在此设计上很快（1.3–5.5 min），布线约 15 min；预算应优先保证“综合检查点 + 一次布线 + 报告段”，而不是省综合次数。
- 改动前先证明工作区 == 冻结基线：把本次改动反向替换到临时副本再算 SHA256，是零成本且可复现的校验法（本次得回 `47db3057…e0a2`）。

## 6. 证据入口
- `r0/p4`：`../p4/result-r0.md`；manifest：`../CANDIDATE-MANIFEST-area-map.json`；diff：`r0/candidate.diff`
- 综合：`r0/td/syn_gate_{timing,area}_s1|s2.rpt`、`syn_run_s1|s2.log`
- 布线：`r0/td/a1_am_r0f_Runs/phy_1/{a1_am_r0f_pr.timing,a1_am_r0f_phy.area,a1_am_r0f_chk.timing,route.qor,route_flow.status,run.log}`
- 功能：`r0/p2/result.json`、`r0/p3/result.json`（与 r1 逐位相同）
