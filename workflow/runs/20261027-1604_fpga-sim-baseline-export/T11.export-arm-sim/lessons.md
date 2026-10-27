# lessons — T11.export-arm-sim（round 0，blocked）

只记可复用的根因/触发/入口，不重复报告细节。

## 环境/入口（可省整轮返工）

1. **ModelSim `-f sources.f` 用 `/`，不要 `\`**。`\` 被当转义，报 `Failed to open design unit file "..rtlp4algo_obuf.v"`。
2. **`vsim` 的 `-do` 必须传 `.do` 文件**。`Start-Process -ArgumentList @("-do","run -all; quit -f",...)` 会把 `quit -f` 拆成独立 argv，导致 `-f work.tb_xxx` 被当作 filelist。
3. 层次化只读观测需要 `-voptargs=+acc`，否则 `u_dut.a.b` 可能被优化掉或读到 `x`。
4. **TB 计数器（`integer`）没有初值就是 `x`**：`tlp_f/db_f/cmp_bytes` 未初始化导致"等待门铃"条件恒假，测试直接跳到比较并输出 `compared=x`。任何 `integer` 状态量都要 `initial` 清零。
5. 递归扫描仓库时 `Get-ChildItem -Recurse` 会被历史目录里含特殊字符的路径打断（`DirectoryNotFound`），优先在已知子树内操作。

## 契约（读参考 RTL，不要自造）

6. `ddr_frame_pusher` 的 **ARM 语义**：`arm_pulse` 时 `last_seq <= src_seq`（只认 ARM 之后新发布的帧），且 `arm_reject` 要求 `frame_bytes != 0`。因此主机必须"描述符可见后先 ARM 一次（该帧被 ARM 消费、不导出）"，之后每帧 ACK 后再 re-arm（此时 `frame_bytes` 仍是上一帧值）。真实上板也是这个顺序；首帧必然被 ARM 消费。
7. **ACK 的 seq 是 pusher 的 push 计数（doorbell 载荷 `db_val`），不是 `capture_seq`**。用 capture_seq 回 ACK 会被判错 ACK，槽不释放。
8. 描述符释放用 `(rel_valid && rel_camera_id)` 判 A/B 时，**身份定义必须与 `a_desc_camera_id=0 / b_desc_camera_id=1` 一致**；极性写反的表现是"第一帧之后再也不发布"（`b_desc_active` 卡 1），且 `st_release_count` 仍在涨，容易误判为"已释放"。
9. `desc_active` 是**电平且释放后会立刻重新置位**（standing offer）。判断"已释放"要用 `st_release_count` 这类单调计数，不要用 `desc_active==0` 的电平。

## 方法

10. 先加"只在关键事件打印一行"的只读 monitor（`PUB_EVT`/`DESC_VALID`/`PUSH_G`），比事后读大日志快；每行带 `$time`，可直接对上 cycle。
11. 判"卡住"要区分"没启动"和"启动了没推进"：`g_st` 状态变化日志一行就能区分（本轮 D3 就是靠 `g_st 1→2` 判定 claim 已成立）。

## 增量（r0b / dev iteration 1）

12. **三分法探针模板**：同一行同时打印 `ar_hs / ddrR_hs / puR_hs`（AR 握手、DDR 回拍、pusher 消费拍）+ `owner/busy/p_st`，一次运行即可排除"没授权 / 没回数 / 没消费"三支。本轮 `1 / 128 / 128` 直接定位到消费之后。
13. **`utx_sel` 是授权输入，不是状态输出**：`ddr_frame_pusher` 的 `utx_ack = utx_sel && !tl_tx_wait && beat_present && beat_ready`。外壳若把它当输出接回，网络悬空 `z`，表现是"读完整帧后永久停在 `S_HEAD`、无 MWr、无 doorbell、无超时"。
14. **A+ user-TL 拍格式**（rx 侧易踩）：第 1 拍 = `{hdr_dw0..3, 128'd0}`，载荷从第 2 拍起；门铃是单拍 TLP；`utx_valid` 只在 `beat_ready` 时为非零 → TB 采样必须同时限定 `utx_valid != 0`，否则会把未接受拍计入导致假 TLP。
15. **释放计数会"骗人"**：`integrated_delivery_top` 的 `GS_WAIT_REL` 看门狗（0xFFFF core cycles）也会 drain+release，`st_release_count` 照样 +1。判断"ACK 被接受"必须另取 `aplus_pcie_egress_adapter.state` 回到 `S_IDLE`，不能只看释放计数（本轮因此误判 ACK 生效）。
16. **准入死锁的首查项**：`admit_ok` 的 8 个项里 `egress_busy` 最容易长期为 1（adapter 停 `S_HELD`/`S_ARM`）。descriptor 不再出现时先打这一行，比逐层翻日志快。

## 增量（r0c / dev iteration 2）

17. **A+ user-TL 头在拍的高半部**：`utx_data = {hdr_dw0..3, 128'd0}`，即 256-bit 拍的 MSB 侧才是 `hdr_dw0`（`dw_all[7]`），低半部为 0；载荷拍低 DW 优先（`dw_all[8]` 起）。按 `dw_all[0..3]` 解析会得到"length 0 / addr 0"这类**全量假失败**（本轮 65 条），务必先用 `RAW_SOP` 打一拍原始 MSB→LSB 再写解析。
18. **ACK 的 seq 是 capture_seq，不是 doorbell 载荷**：`brd_pcie_track` 用 `o_pcie_held_seq <= i_arm_seq`（ARM 时的 capture_seq），doorbell 载荷是 pusher 的 push 计数，两者会差 1。
19. **区分"脉冲到了没生效"与"根本没到"**：在目的域对 `x_ack` 计数（`xack_cnt`）+ 同时抓 `start/free/valid` 和适配器状态。本轮由此把问题从"跨域丢失"收窄到"适配器 `S_HELD` 未接受"，避免继续改 TB 试参。
20. **释放来源必须单独可观测**：`st_release_count` 增加**不能**证明 ACK 生效——`GS_WAIT_REL` 看门狗也会 drain+release。判据必须同时看 `slot_release` 脉冲与 `wd_cnt`（≈0xFFFF 即为 WDG）。

## 增量（r0d / dev iteration 3）

21. **CDC 拼接体的读侧切片要按写侧位序数**：`in_bus = {cancel, ack_seq, ack_session}` → LSB 半字是 `ack_session`。读侧写成 `o_ack_seq <= out_bus[31:0]` 就得到互换的 seq/session；症状是"身份值全对却不匹配"。凡是 `{a,b,c}` 打包再按 `[31:0]/[63:32]` 拆的地方都要逐位核对（`brd_desc_xing` 有逐位注释可对照）。
22. **看门狗延时可当"是否走了正常路径"的指纹**：同一次释放，ACK 路径 ≈754 tl cycles，WDG 路径 ≈27810 tl cycles（0xFFFF core）。用数量级差异判定 `rel_src`，比加探针省一轮。
23. **每帧 TLP 的目的地址重新起算**：pusher 每帧都从 `dst_lo` 开始发 `base+128B×i`，TB 若用累计 TLP 计数算期望地址，第 2 帧起会全线"地址不符"。用 `n = tlp_f - base_tlp`（帧内索引）。
24. **断言也要有负对照**：`POS_RESULT` 曾出现 `PASS frames=1 of 2`。把判定写成 `pos_verdict(ok,fail,req)` 后，在同一 run 里再算一次 `req+1`，可证明"少一帧必 FAIL"，不必额外跑场景。
25. **两台 neg_top 合并成一次 vsim**：给 harness 加 `NEGID` 参数并在结果行打印 `id=`，另一个 `$finish` 前加 `#2000` 延时，两个实例都能打印完再结束——省一次场景额度。

## 增量（r0e / round1 实际修复）

26. **禁止"同源自比较"**：TB 若拿 `u_mem.mem`（pusher 读取的同一份内存）当期望，任何"没写进去/写错地址/写零"都会被 `mismatch=0` 掩盖。正确基准要在**写侧**取（store 的 `core_out_data/core_out_keep`，按 `wr_begin` 分帧），这样才第一次看到真实的 `mismatch=3505/3965`。
27. **三探针定位地址类缺陷**（一次运行即可定性）：`AWDBG`（AW 握手时的 `awaddr` + `wdata[7:0]`）、`ARDBG`（AR 握手地址/长度）、`MEMDBG`（`mem[期望索引]` 的原始 32B）。本轮由 `mem[8192]` 非零 + `mem[2048]` 全零直接判定"写对了、读偏了"，无需再猜握手/数据通路。
28. **`mem[i]` 的索引是字节地址 >>5**：先算清"写地址单位 → mem 索引"和"读地址单位 → mem 索引"两条链，再判断是否同址；本候选写/排空路径为 `slot_word×128`（0x40000），pusher 读为 `slot_word×32`（0x10000），差 ×4 正好落在设计指南已记录的"DDR ×4 重映射"未闭合项上。
29. **"两帧流相同"要当独立断言**：即使载荷正确，也要显式比较两帧写侧流（`STREAM_DIFF>0`）与长度（`STREAM_EXP == exact_bytes`）；合成激励若产生周期图案，压缩流可能真的相同，需检查激励而不是想当然。
30. **测试者的独立解析器是本项目最有效的判据**：自写 `parse_tlp.py` 从 256-bit 原始 beat 重建 TLP，绕开了开发脚本输出，才暴露"载荷全 0"。后续自测应默认准备一个"不读开发脚本"的旁路。

## 增量（r0f / round2）

31. **槽字节基址 = `slot_base_word × 128`**：本候选写/排空路径把 word 索引按 ×128 落成字节地址（word 2048 → 0x40000），pusher 侧必须同标度；×32 会让 pusher 读到全 0 区（`mem[2048]` 空、`mem[8192]` 有数据）。`PUSH_BASE0/1` 必须同步，否则 `claim_base_ok/par_valid` 会失配。
32. **"读数非零"后要立刻查字节序**：地址对齐只解决"读到哪"，字节序解决"读出来是什么"。用 `payload[0]` 与写侧 `exp[0]` 对比；若 `payload[0] == exp[31]`（=该 beat 的最后一个字节），就是 32B beat 整体反序，`mismatch ≈ 29/32` 而不是接近 100%。
33. **分帧键不要用 `wr_begin`/`core_commit`**：`wr_begin` 同帧可多次脉冲、`core_commit` 与帧不一一对应，都会把某帧落到空窗口（`exp_len=0` → 误报"两帧流相同"）。可靠键是 `pub_pulse`（每完成帧一次）；即便如此也要检查 `cap_end[]` 是否取到值（本轮仍出现 X）。
34. **blocked 也要把"哪一侧是规范"问清楚**：本轮的 beat 字节序涉及 b20 store 与参考 pusher 两处冻结件，开发无权选定；带 (a)/(b)/(c) 三个候选修复点的裁定请求比"再试一轮"有效。

## 增量（r0g / round3 最后额度）

35. **先把冻结 oracle 跑起来，再谈改谁**：把 T03 的 `tb_byte_replay.v` + `stream.mem` + 冻结 `rtl-slot-read.bin` 复制进工作根，用**同一** store 跑一遍即可得逐字节结论（本轮 `BYTE_DIFF=0`、首 8 字节 `78 9c 62 48 4a 4a 5a 01`）。20 分钟省掉整轮猜测，并直接排除"store 端序有问题"。
36. **T03 的 DDR 模型是"字索引"的**（`mem[awaddr]`，store 的 `ddr_awaddr` 直接当字索引），而 T11 TB 的模型是"字节索引"（`mem[addr>>5]`）+ 桥 ×32。两套约定混用会让同一个 `slot_base_word` 在不同 testbench 里落在不同地址——跨 run 复用 DDR 模型前先确认索引单位。
37. **"读到了数据"与"读对了数据"是两步**：地址对齐后先看 `payload[0]`；若它等于写侧 `exp[31]`，就是 32B beat 整体逆序（`mismatch≈29/32`），此时再改地址/容量都无意义，必须先把端序规范问清楚。
38. **规范与实测冲突时不要静默二选一**：本轮 §3.6 写 ×32、实测写路径 ×128，且按 ×32 会回到全 0 读。正确做法是保留能自洽的一组、把冲突与两条反证一起上报，而不是照规范改出一个已知失败。
