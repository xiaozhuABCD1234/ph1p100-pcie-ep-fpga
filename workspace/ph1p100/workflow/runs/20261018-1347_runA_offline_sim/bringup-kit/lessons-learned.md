# lessons-learned.md — T11.runA-bringup-kit

1. 根因/触发：验收要求“用 B1 真实日志作正夹具”，但 B1=blocked 且 B2 未执行，不存在真实寄存器 dump。
   修正：把正例拆成两类——真实日志只验通道证据（channel 模式），寄存器规则用合成快照验证；报告与文档中分别标注来源，禁止用通道 PASS 代表寄存器 PASS。
   验证入口：`bringup-kit/dryrun.log` 的 `channel-b1-real` 与 `positive` 两个用例。

2. 根因/触发：`gen_crc32_flat.py` 名字像 CRC 工具，实际是 Verilog CRC 函数生成/自检器，不能对 `.dma` 文件复算。
   修正：文件级复算改用 `r10f_strict.py check`，并在 README 明确两者分工；`gen_crc32_flat.py --selfcheck-only` 只作 poly 自检。
   验证入口：dryrun.log CRC 段（两工具退出码与字段比对）。

3. 根因/触发：PowerShell 5.1 中 `& $py @args` 会把 args[0] 当脚本路径（本次 dry-run 首跑失败）。
   修正：显式写脚本路径 `& $py $script @args`；批量执行器按“每用例期望退出码”记录实际值，避免只看整体退出码。
   验证入口：`TOTAL_CASE_MISMATCH=0`。

4. 根因/触发：被复用的 `r10f_strict.py --json-out` 输出含 Windows 反斜杠路径，`ConvertFrom-Json` 报无法识别的转义序列。
   修正：改用 Python `json` 模块或逐字段文本比对；不改 protected 工具。
   验证入口：dryrun.log CRC 字段（sha256/size/ok/header_crc_calc/payload_crc_calc/marker）。

5. 根因/触发：bw 命令表里出现 `JTAG_REG_ACCESS` 等名字容易被当作可用读通道。
   修正：命令名 ≠ 有文档的读语义；无文档、无调试核时按“不可用”登记，不盲试、不触硬件；把“是否存在无需调试核的只读用户寄存器路径”作为给原规划/用户的证据问题。
   验证入口：`dev-result.md` §4；B1 `logs/03-bw-command-list.txt`。

6. 根因/触发：中文路径 + PS 默认编码易引入 BOM/GBK 噪声，影响脚本与 JSON 跨角色复跑。
   修正：工具包文件全 ASCII、写文件统一 `UTF8Encoding($false)`、dump 输入严格要求 UTF-8/ASCII（否则 exit 2）；重跑用固定 `--timestamp` 保证字节一致。
   验证入口：`DETERMINISM_OK=True`、`SCHEMA_KEYS_OK`。
