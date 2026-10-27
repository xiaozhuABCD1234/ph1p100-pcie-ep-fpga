# lessons-learned.md — T11.runB-board-readback（P3）

1. **可复跑的 SRAM 下载组合（第三次验证）**：预启 `D:\downlaod\bin\hwserver.exe -r -s 5555 -f 12 -v -w 5556 -i 0`，再用 `cmd /c "bw_commands_prompt.exe <相对脚本> < NUL"`（脚本目录为 cwd，位流路径经环境变量传入）。本次 rc=0、28.85 s、PRG-2014、100%，与 B1 口径一致。`< NUL` 可避免交互式等待。
2. **下载前用 `read_device_id` 做 fail-closed 门**：脚本内先读 ID，非 `PH1P100` 直接退出，避免误下载到错误器件。
3. **位流 ASCII 暂存需双向复核**：源与 `%TEMP%\runa_p3\` 副本均算 SHA；本次两者相等（5,224,027 B）。
4. **ChipWatcher 无 CLI**：TD 2026.2 `bin` 无 cwc/watcher/rdbk 可执行，`scripts` 抽样 300 个 tcl 无 `rdbk_cwc/chipwatcher` → 读回必须 GUI；应在下载成功后**立即**把 GUI 清单交现场用户，不要等待或盲试 `bw` 未知命令（JTAG_REG_ACCESS 语义未证）。
5. **hwserver 生命周期要事先规划**：本角色结束 hwserver 的 `Stop-Process` 被宿主权限拒绝；应在启动前写入“由用户/后续轮结束”的约定，或改用非终止方式（不占 5555 的方式本次未验证）。TD GUI 若报线缆占用，先结束遗留 hwserver（本次 PID 30988）。
6. **“下载 PASS”≠“板级读回 PASS”**：G3 必须绑定真实读数；无首样本时只能记 not_evaluated + blocked，不得用“下载成功/进度 100%”推断身份字。

## round1（TD Tcl CLI 尝试，2026-10-18 22:35–22:41）

7. **td_commands_prompt.exe 执行脚本时必须写 UTF-8 无 BOM**：PowerShell 5.1 `Set-Content -Encoding UTF8` 带 BOM，TD 报 `invalid command name "\ufeffset"` 且立即退出（exit=0、0.29 s，静默失败）。修正=`[System.IO.File]::WriteAllText(path, $s, (New-Object System.Text.UTF8Encoding($false)))`。诊断要点：脚本 0.3 s 内“成功”退出＝脚本未被解析。
8. **TD Tcl 的 ChipWatcher 命令确实存在**（`config_chipwatcher`/`get_hw_cws`/`get_cw_probes`/`run_hw_cw`/`wait_on_hw_cw`/`write_hw_cw_data`/`check_cw_trigger`/`report_cwc_status`/`export_chipwatcher`/`connect_cable`/`list_cable`），且 `config_chipwatcher <compiled.cwc>` 可完整导入（KIT-1004：9 view/288 trigger/288 data；`export_chipwatcher` 导出的 XML 与 `.cwc` **字节同 SHA**）。
9. **状态是会话级的**：`config_chipwatcher` 的导入在该 `td_commands_prompt.exe` 会话内有效；新会话不继承 → 每条读回链（config→run→wait→write）必须写在同一脚本里。
10. **卡点特征**：`get_hw_cws *` 能找到实例，但 `run_hw_cw/wait_on_hw_cw/check_cw_trigger/write_hw_cw_data` 一律 `KIT-8000 No watcher instance matched`（实例名/trigger 名/`*`/`[get_hw_cws]`、`connect_cable` 前后、有无 `-cable` 全一样）→ 与该实例是否已在**硬件侧注册**有关（线索：`report_cwc_status` 的 Bit File 列为空）。排查顺序建议：先做 .bit/.cwc 同目录同名配对，再考虑由 TD 下载配对位流。
11. **`get_cw_probes *` 返回 9 个空 `{}`**：该命令在当前（未接硬件的）会话里不提供探针名列表；探针名可从 `export_chipwatcher` XML 或 `config_chipwatcher` KIT-1004 行获取（`dbg_bank_word0..8` → 网名 `u_top/u_pcie_ep_engine/u_ep_bar_win/g_dbg_mark$dbg_mark_wordN[31:0]`）。
12. **`-help` 对这批命令无输出**：不要依赖 help；用 `info commands *cw*` 枚举 + 实跑最小链验证。
13. **证据冻结优先**：预算用尽时至少把 stdout/脚本留在 run 目录（本轮 round1 的 8 份 stdout 是唯一原始记录）；manifest/attempt-record 若当轮写不完，必须在下一轮第一件事补齐。

## ASCII round（2026-10-18 23:23–23:25）

14. **PRG-9505 不是路径问题，是没有可用 hwserver**：中文 cwd 与 `D:\anlogic\runa_p3\ascii_*` 下表现完全相同（都 PRG-9505）；启动 TD 2026.2 自带 `D:\anlogic\TD_Release_2026.2\bin\hwserver.exe -r -s 5555 -f 12 -v -w 5556 -i 0` 后，`connect_cable -host_name 127.0.0.1:5555 -open` + `read_device_id` 立即返回 PH1P100。**以后任何 TD Tcl 硬件操作前，先起 TD 自带 hwserver 并显式 connect_cable。**
15. **`connect_cable` 裸调用无效**（`PRG-8000 host name is empty`）；必须 `-host_name 127.0.0.1:5555 -open`。
16. **`report_cwc_status` 在硬件连接 + hwserver 下会打印 `compile chipwatcher successfully!`**；但 `run_hw_cw` 仍 KIT-8000 —— 说明“编译成功”≠“hw watcher 句柄可用”。KIT-8000 的根因不是路径、配对或 USB，而是 `run_hw_cw` 期望的 watcher 对象在纯 CLI 会话中不存在（疑似仅 GUI Watch 流程创建）。
17. **探针名要从 `get_cw_probes * -nocase -verbose` 的 KIT-1001 stdout 抄**（返回值仍是 9 个空 `{}`）：`u_top/u_pcie_ep_engine/u_ep_bar_win/g_dbg_mark$dbg_mark_wordN[31:0]`。放进 Tcl 列表时必须用大括号包裹，避免 `$`/`[]` 被替换。
18. **`config_chipwatcher` / `report_cwc_status` 不接受 `-verbose`**（USR-8011），但 `get_hw_cws` 接受。
19. **进程残留风险**：TD hwserver（PID 73028）在本轮结束时仍在跑，占 5555；给用户的 GUI 清单必须写“先结束 hwserver.exe”。轮末 shell 权限被拒会阻止清理，需在主/规划层安排。
20. **ASCII 工作目录做法**：`D:\anlogic\runa_p3\ascii_<ts>\` 复制 `compiled.cwc`+`compiled.bit`（同名配对）+ 脚本 + CSV 输出，cwd 设为该目录、`td_commands_prompt.exe ./script.tcl`；不触碰 TD 安装、不删除。

## final round（2026-10-18 23:34）

21. **TD Tcl `download` 可用且是 SRAM**：前置条件是 TD 自带 hwserver 在跑 + `connect_cable -host_name 127.0.0.1:5555 -open`；实测 `download -bit <ascii>\compiled.bit -mode jtag -cable 0` → `PRG-2014 Chip validation success: PH1P100`、rc=0、25,871 ms（`Error @ mpsse.cpp:90 usb_open() failed` 为伴随行，不判败）。`doc/config/config.json` 的 `PROGRAM_SRAM` macro=`jtag` 是确认 SRAM-only 的可靠依据。
22. **同会话 download 也不能注册 hw watcher**：download 成功 + `compile chipwatcher successfully!` 后 `run_hw_cw` 仍 `KIT-8000 No watcher instance matched` → 结论：**CLI 路径永久关闭**；该 hw watcher 句柄只能由 GUI Watch 流程创建（或至少不是 CLI 现有命令能创建的）。
23. **停止口径**：命中“download 成功但 run 仍 KIT-8000”即最终停，不再换名/换参数/换模式；保留 stdout/CSV/日志并交 GUI 兜底。
24. **每轮收尾必做**：停掉自建 hwserver 释放 5555（本轮 PID 35108 已停），否则用户开 TD GUI 可能报占用。

## GUI 实读全零（2026-10-18 23:43，root cause）

25. **标记探针必须放在“无链路也活着”的域**：本轮 9 个 `MARK_DEBUG` 快照寄存器在 `tl_clk_user` 域、`rst=tl_rst_user`；`tl_rst_user` 由 `ph1p_pcie_rst_sync`（LTSSM==L0 才释放）产生 → **无 PCIe 主机时寄存器被钉在复位值 0**，ChipWatcher 采到的就是恒定全零（连 `MAGIC` 常量字也为 0）。
26. **判别要点**：常量字读 0 = 寄存器从未离开复位（或时钟停），而不是“数据恰好为 0”；这比“计数不增长”强得多，可直接判为域/复位问题。
27. **触发成功 ≠ 数据有效**：`Triggered: 1` 只说明调试时钟在跑；采样时钟可独立于被观察域的复位。
28. **GUI 重试/改触发位置对“复位钉死”无效**——命中该模式应停止用户操作，转设计修复（重建位流：把与链路无关的身份/状态字改到自由运行域，或使用不依赖 link-up 的复位）。
29. **诊断写进证据**：`board-readback/zero-read-diagnosis.md` 给出 RTL 行号级证据链（L464–499 / L397–399 / rst_sync L52–74 / top L472–477），供规划与测试者复核，不靠推测。

## 新候选首读（2026-10-19，P1-fix3）

30. **复位域修复有效**：新 bit `bfafdf97…` 首读即命中身份三字（`50434946`/`31414B52`/`00010000`）与 CTRL `0x21`——与旧候选 `2385cded…` 全零形成直接对照，`issue-02`（探针域被链路复位钉死）判定被实测确认。
31. **word6 good 字段非单调**（242→11，bad/hdr/crc=0）：该字段更像“帧内/滚动好行数”而非累积计数，与判据文字“good 增长”语义不完全对齐；本轮**按冻结判据如实记为未达并归因**，若规划确证应新增判据说明或要求连续快照，不改本轮判据。
32. **读数时间戳要当场记录**：本轮两组读数用户未标注触发时间（仅疑用截图 Updated 时间），建议后续清单直接把“时间=HH:MM:SS”写进回报模板首行。
33. **复用用户已开的 TD hwserver 即可完成 SRAM 下载**（`connect_cable -host_name 127.0.0.1:5555 -open` → `download -mode jtag`，PRG-2014/rc=0/28.4 s），无需另起服务、无需抢线；下载后无需告诉用户“先关进程”。

## r0 FAIL 修复轮（2026-10-19）

34. **Tier-2 有一项未达时 G3 必记 `partial`**（dev-plan §3.5 L174/L180）：不能用“仅 FPGA 侧/范围限定”把它写成 pass——范围语只能写在 G3 的覆盖说明里，不能替换状态字。
35. **manifest 必须按时间序分层**：旧候选/旧尝试段落要么删除要么移入显式 `history[]` 并标 `superseded:true`+日期，绝不能与当前结论并列在同一顶层（同名顶层 `readback`/`next_steps` 字段会把下游引到相反结论）。
36. **空日志也有哈希**：`00-hwserver-out.txt` 这类空文件的 SHA256=`E3B0C442…B855`（空串哈希），不要留 `sha256:null`；被占用/未采集的项要显式说明。
37. **截图转述不能当时间戳证据**：二进制/截断转录与 32-bit MSB-first 渲染对不上时，不得推断样本归属；按 §3.5 A.3 走“一次有界重采”，并让用户直接写时间到回报里。
38. **TD CLI 崩溃会落 minidump**（`cwc-cli/minidump-20261018-224953.dmp`）：发现后要纳入 manifest 工件清单，别漏项。
