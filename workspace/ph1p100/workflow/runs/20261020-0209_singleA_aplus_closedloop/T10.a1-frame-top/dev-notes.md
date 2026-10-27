# T10.a1-frame-top — round1 dev notes

## 落地改动
1. `a1_frame_top.v`：`out_last` 增加 `!killed`；9 个 core stat 连接；smem 改为寄存读+2 级预取；
   `prep_r/pred_r` 在 sof 锁存；提交后 1 拍 `core_flush` 清理 P2 核残留 `enc_busy`。
2. `tb_a1_frame_top.v`：新增 mode 6（连续多帧）、mode 7（末字 pending abort）、mode 8（非法几何，
   复位前后各一次）、mode 9（pred-without-prep → 复位 → 合法恢复）；`out_ready` 增加“末字保持”模式。
3. `a1_p3_gen.py`：新增 f1080p_p0 / f1080p_p1d0 / f1080p_rand / mixed1920x16 / multi1080p /
   abort_last / 4 个非法几何/配置用例；W%4!=0 走确定性字节（无合法 RAW10 打包）。
4. `a1_p3_verify.py`：按 mode 校验流、末字 abort 语义、非法帧与连续多帧吞吐。
5. `run_p3.ps1`：支持 `+NFRAMES`；每命令超时。

## 关键取舍
- **不修改 P2 核**：核在最后一帧结束后 `enc_busy` 保持 1（P2 单流用例未暴露），帧 top 在提交后发 1 拍
  `abort` 脉冲清除核状态；核文件 hash 未变，P2 结论仍绑定。
- `smem` 不再组合读：2 级预取保持 4 样本/组，吞吐不变，同时消除 time-0 X 索引与越界。
- 非法几何/配置采用 **reset-only** 恢复：`I_DEAD` 不输出、不提交，复位后重新判定；mode 8/9 已验证。
- 吞吐结论按内容分层：整帧 1080p 101–104 MB/s；1920x16 小帧 88.9 MB/s；97.2 不作保证值。

## 已知限制
- 无 TD/G2/STA/CDC/资源；无板、无真实 RAW/相位。
- 真实样例导出与现场窗口仍 blocked/awaiting_hardware。
