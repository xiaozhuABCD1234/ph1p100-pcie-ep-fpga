# lessons.md — T11.runC-board-checklist（0207 runC P4）

1. **长脚本先落盘再执行**：内联多行 PowerShell 中出现 `[Text.Encoding]::GetEncoding('utf-8',$true,$true)` 重载错误（该重载不存在，需 `EncoderFallback/DecoderFallback` 对象或直接 `[Text.Encoding]::UTF8.GetString`），整段中止且未写日志。改为保存 `recompute-hash-chain.ps1` 后执行，既避免重发长命令，也留下可复跑证据入口（复算日志=证据本体）。触发条件：手持长内联脚本、含 .NET 重载调用；修正后一次通过。
2. **哈希链复算用“单脚本+逐项 MATCH 行”**：把 P1/P2/P3 manifest 的登记值内嵌为期望表（含字节数），逐项输出 `MATCH|组|路径|SHA256|字节`；worktree 文件同时校验 SHA256 与 `git hash-object`（默认/`--no-filters` 双口径），跨 checkout 以 blob 为准；diff 用 `git apply --check --cached`（HEAD→index）+ `--reverse`（worktree→HEAD）双向 rc=0 锚定“diff↔源文件↔HEAD”。验证入口：`board-checklist\recompute-hash-chain.ps1` → `total=56 mismatch=0 missing=0`。
3. **暂存“零覆盖”要含失败重跑**：首跑中止后 D: 留下空目录；复跑脚本先检测“唯一空子目录→复用”，避免产生第二个时间戳目录或覆盖；已有文件则 `STAGE_COLLISION_NO_COPY` 记录而不写。
4. **板窗互斥优先于“尽力预加载”**：下载前必须由在场用户确认窗口空闲；同机并行线有 TD 构建在跑（本机 0212 于 19:14 起 `run_build.py`）时，不发起 connect/download，暂存命令脚本+清单兜底即可（返回 awaiting_user_gui 是有效终态，不是失败）。
5. **5555 端口归属先查进程**：TD GUI 自带的 hwserver 通常已占 5555（本轮 `-r -s 5555 -f 12 -v -w 5556 -i 0`）；预加载直接 `connect_cable -host_name 127.0.0.1:5555` 复用，勿起第二个；自起会话用后释放。只读 `read_device_id` 只证明 PH1P100/线缆，不证明板上候选。
6. **期望值只从冻结文档逐字取**：清单/预加载不现场推导；预期值绑定 `build\hardware-ready.md`（SHA `1dbb8136…`）与 P1 `g0.words_map`，G3 判定权留给综合测试者+原规划，开发不宣布 PASS。
7. **控制台乱码≠文件损坏**：中文输出在 GBK 控制台显示为乱码；以 `Get-FileHash`/字节长度/`git blob` 判定文件本体，必要时以 UTF-8 读写 API 落盘。
8. **BW 命令脚本中的 Windows 路径必须用正斜杠**：本机 BW Release_2026.1_SP2（bw_commands_prompt build 6.2.2.200067）按类 Tcl 语义解析脚本行的 `\`（`\a`→BEL、`\r`→CR、`\n`→LF、`\2`→STX、`\c`→`c`），`download -bit D:\...\compiled.bit` 被解析成含控制字符的 `D:?nlogic?una_runC?61019_192056compiled.bit`，报 `PRG-8000 File path invalid`（0.0003 s、无写入）。改用 `D:/.../compiled.bit` 或 cwd+相对文件名；与编码/BOM 无关（脚本为纯 ASCII、UTF-8 no BOM、CRLF）。验证入口：`log\bw_*.log` 的“解析后命令”行与脚本 hex 字节对照。
9. **同一 5555 出现多个 hwserver 时，连接可能落在未持有 FTDI 的实例**：症状 `Error @ mpsse.cpp:90 : usb_open() failed` + `PRG-8000 ERROR: transfer failed`（≈6.8 s）。只保留控制台打印 `Open device vid=0x0403 pid=0x6042` 的实例（由用户关闭重复窗口）；不得自行结束他人进程。
