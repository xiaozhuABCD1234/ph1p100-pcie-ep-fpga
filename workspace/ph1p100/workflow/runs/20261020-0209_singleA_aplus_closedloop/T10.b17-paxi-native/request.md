# T10.b17-paxi-native — request（用户原话/本轮边界，2026-10-26）

已读审计文档：`D:\fpga\ph1p100\docs\OpenCode_b15根因审计与定位建议_2026-10-26.md`。核心：

- 地址单位未适配：store/bridge 发 0、1、2（256-bit 字下标），厂商原生参考对应 0、8、16（`{word_index,3'b000}`），链路无 ×8。
- 写 mask 不一致：bridge 全 1，厂商/原生 `ddr_frame_store` 用全 0（mask 0 写整字）；现有模型忽略 mask。
- 读写命令可同拍握手，原生参考单命令仲裁（`awready & arready` 共同判定）。
- 模型需检查低 3 位/越界/mask/并发；小图样 8–16 字写-停-读回先验证。
- 若仍缺 R，锁存失败 AR 地址、低 3 位、同拍握手、时间戳。

请冻结 `T10.b17-paxi-native`：

1. 在**唯一 PAXI 边界**做地址转换：`{word_index[23:0],3'b000}`（AW/AR 都做）；内部槽仍保持 256-bit 字单位；范围检查。
2. `paxi_wstrb` 按原生合同改 **0**（写整字）；模型必须实际执行 mask 语义。
3. 单命令接纳：AW/W 与 AR 互斥（受控诊断默认）；保留参数以便后续并发对照。
4. 更新仿真模型：检查低 3 位/越界/mask/并发；先做 8–16 个不同字写-停-读回逐字比对，再做整帧/两帧/丢 R；P1 三黄金。
5. v6 诊断：新增 `last_issued_ar_addr`、超时锁存 AR 地址+低3位、AW/W/AR 同拍握手标记、在途状态；状态包按需扩字段（记录长度/版本）。
6. 重建：Routed 0 违例、WNS≥+0.05（薄余量按 b13 口径）；1 bitgen + 1 CWC。
7. 板级：先下载后开 COM8、150 s；目标 timeout/retry/giveup 归零、enc/exported 增量>0、帧四 CRC+zlib；若仍缺 R，保留 v6 失败 AR 证据并停止。
8. 预算：开发 150 min/70 calls；TD 3 会话、综合 ≤3、布线 ≤2、bitgen 1、CWC 1、下载 1。
9. 更新 dev-plan/handoff/user-summary/final-summary，写 dispatch。

返回 task_ids、dispatch_path、status、needs_user_input、user_summary_path。有界：≤30 次调用、15 分钟。
