# T08 lessons — runD batch2（2026-10-19）

## 可复用根因/触发/修正

1. **位置连接不能写 `()`**：`sync_sof_mailbox ma(...,());` 中的 `()` 是表达式而不是“空端口”，vlog 报 `near ")"`。Verilog-2001 又禁止同一实例混用 ordered/named，所以正确修法是**全部改 named**，未用输出写 `.src_busy()`。只改连接，不改功能。
2. **TB 的“故障场景”必须切换 scoreboard 模式**：故意触发 FRAME_TIMEOUT 清理时，若不把 `mode` 从正常顺序检查切走，第一条清理写就会被判 `ordered role writes`。修正为仅该场景 `boot()` 后 `mode=1`，正常 boot 的顺序检查不受影响。
3. **TD 的 `.v` 按 Verilog-2001 解析**：载体里 `.*` 是 SystemVerilog，直接 `HDL-8007 near "*)"`。独立载体用显式 named 端口最稳；不要依赖 `.sv` 扩展名推断。
4. **TD bitgen 与 G2 解耦**：无 ADC 引脚约束时 `BIT-8123` 会中止，但 place/route 与 `pr.timing` 已生成。G2 只看 `Confidence: Routed`、route.qor、pr.timing、chk.timing、资源；不要为拿 bit 去伪造引脚或改门槛。需要让流程走完时可用 TD 文档的 `set_param bitgen unconstr_io on`，并在报告中明确“无 bit 声明”。
5. **ModelSim 中文路径**：用 `subst T:` 映射到 ASCII 盘符；负对照的 vsim 退出码可能被 `quit -code 0` 掩盖，判定应同时看 `vlog Errors:0` 与 `SYNC_FAIL ordered role writes` 文本，不能只看 exit code。
6. **首次失败证据要保留**：`positive-r0` 的 vsim 失败日志是 TB 修复依据；不要用“删掉重跑”制造干净历史。
7. **共享树/OneDrive 可能把测试文件改回旧版**：本 run 在负对照期间观察到 `tb_sync_offline.sv` 被外部恢复为未修复版（mtime 21:39:29，SHA 变回 `bc99c72…`）。处理：重放同一修复后以新 target 重新编译/运行（`positive-r2-final`）并核对 SHA/行内容，同时在 run 内保存 `tb_sync_offline_frozen.sv` 字节副本；冻结 manifest 绑定复验后的 SHA，不拿旧 PASS 拼新文件。

## 验证入口

- `sync-offline/g1/positive-r1/vlog.log`、`vsim.log`
- `sync-offline/g1/negative-r1/vsim.log`（tx=5 预期拒绝）
- `sync-offline/g2/td-work4/sync_offline_g2_Runs/phy_1/route.qor`、`sync_offline_g2_pr.timing`、`sync_offline_g2_chk.timing`、`sync_offline_g2_phy.area`
- `sync-offline/manifest.json`、`verification.txt`、`dev-result.md`

## 下次最小动作

独立测试者重编译/复跑同一 RTL+TB（同一 DB），核对 G2 报告；父 T08 的真实双路同步需另轮硬件条件，不能由本离线 PASS 外推。
