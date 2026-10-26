# T10.b10-b9-fix r1 交接（给 fpga-dev）

## 一句话

r0 已把 B9-01/02/03 修好并通过 P1 三黄金，但 TD 预算用尽，最后两份网表建立在误删 `wire [39:0] crop_pix`（变成 1 bit）的源码上，**没有有效 bit/CWC、下载 0/2**。r1 不再改 RTL，只用当前已修复源码**重建 1 次**（综合 1 + 布线 1 + bitgen 1 + CWC 1），然后**先下载、后开 COM8** 采 180 s，拿 `raw_pub/enc_frames/exported` 增量与帧解码证据。

先读 `fpga-design-guide.md`（r0 增量口径不变）→ `dev-plan.md` §7（r1 冻结流程）→ `result-r0.md` / `lessons-r0.md`（r0 实际结果与坑）。

## 必须守住

- 只写 `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b10-b9-fix/**`。
- `T10.b9-rawstore/**`、`T10.b8-*`、`T10.b7-*`、`fpga/csi2/src/**`、`work/b9-opencode-audit-20261025/**`、`D:/TD/work/csi2` 全部**只读**；不删除任何旧目录/证据。
- **r1 不改 RTL/参数/SDC/引脚/端口**。源哈希以 `CANDIDATE-MANIFEST-b10-b9-fix-r0.json` 为准：
  - exporter `ff0ce16d…`、camera top `612d42a5…`、bridge `b9e83481…`、board top `98d6c446…`。
  - `camera_a1_uart_top.v` L156 必须是 `wire [39:0] crop_pix;`。
  - 该文件里的 `// T10.b10 R1:` 注释是 r0 已回退尝试的历史注释，**不是功能**；不要改注释（会破坏哈希绑定），在 r1 manifest/result 里说明即可。
- 44 B 帧头、流 CRC、zlib、UART 115200/协议、帧内不插包、crop 几何、MIPI/显示：全部不动。
- TD：**综合 1、布线 1、bitgen 1、CWC 1、1 个会话/60 min**；失败即停，不重跑、不扫参数。
- 板级：**下载 1 次（累计 ≤2）**、Flash 0；顺序必须是「COM8 关闭时先下载 → 释放 FTDI → 再开 COM8 采 180 s」。采集失败/0 B 即停，不二次下载。

## W2-r1：重建候选（顺序固定）

1. 同一 PowerShell 会话先 `. D:\fpga\ph1p100\tools\td\open_td.ps1`；cwd=`...\T10.b10-b9-fix\r0\td`；禁用 X:。
2. 预检：`Get-FileHash` 复核上面四个源；确认 `a1_board.bit`、`a1_board.cwc`、`cw\` 不存在；`a1_board_Runs`/`a1_board.al` 是 r0 s3 的。
3. 归档（复制/改名，**不删除**）：
   - 新建 `r0\td\r0-build-evidence\`，复制 s2/s3 的 `build_console_b10_s2.log`、`build_console_b10_s3.log`、`syn_gate_*.rpt`、`routed_*.rpt`、`phy_*.rpt`、`candidate_*.rpt`、`params_after.tcl`、`place_flow.status`、`route_flow.status`、`routed_netlist.v`。
   - `Move-Item a1_board_Runs a1_board_Runs_r0s3`；`Move-Item a1_board.al a1_board_r0.al`（单目录/单文件改名）。
4. 跑一次：`D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe 01_build.tcl *> build_console_b10_r1.log`
   - 通过标志：`P2_BUILD_DONE`、`NO_BIT_FILE`、`P2_SYN_SWNS>=0`、`P2_ROUTED_SWNS>=0.05`、`P2_ROUTED_STNS=0.000`、`P2_ROUTED_HWNS>=0`、`P2_ROUTED_HTNS=0.000`、`P2_ROUTED_VIOL_EP=0`。
   - 资源与 b9 差 ≤5%、ERAM 不增；无新增未解释 CDC/组合环。任一不满足：停，写 blocked，**不 bitgen、不下载**。
5. `td_commands_prompt.exe 02_bitgen.tcl *> bitgen_console_b10_r1.log` → 必须 `P2_BITGEN_STA_SETUP=.../0`、`P2_CANDIDATE_BIT_GENERATED_NO_DOWNLOAD`、`a1_board.bit` 存在。
6. `td_commands_prompt.exe 03_cwc.tcl *> cwc_console_b10_r1.log` → 必须 `P2_MATCHING_CWC_EXPORTED_NO_DOWNLOAD`、`a1_board.cwc` 存在、`cw/compiled.bit` 与 `a1_board.bit` 字节相同、`a1_board_inst.bid` 存在。层次化探针被拒按 `cwc_hier_not_available` 记录，不判 FAIL、不改端口。
7. `01_build.tcl` 只运行一次；`02/03` 各一次。CWC 脚本会拒绝已存在的 `a1_board.cwc` 或 `cw/compiled.*`——若预检发现它们存在，先查清来源，不能删了重来。

## 候选绑定（W2 收尾）

新建 `r0\mk_manifest_b10_r1.py`（从 `mk_manifest_b10.py` 派生），输出：
- `CANDIDATE-MANIFEST-b10-b9-fix-r1.json`（**保留 r0 manifest 不动**）
- `r0\artifact-hashes-r1.txt`

必须记录：`round:"r1"`、`previous_manifest` 的 SHA256、`sources`/`tests` 全量哈希、`artifacts.bit/cwc/bid` 的真实 SHA256、`board.download_count:1`、`evidence.board_capture:"r0/board/captures_r1/com8_180s.bin"`。
`changes` 必须改正 r0 的过时描述：camera top **只有** `CMP_BASE 262144` + 仿真布局断言（`crop_pix` 声明恢复）；`// T10.b10 R1:` 注释为历史、本候选**无** R1 功能修复。

## W3-r1：1 轮板级（顺序不能反）

1. 板卡上电、相机连接、COM8 空闲、无 hwserver/python 占用；记录时间/端口/115200 8N1。
2. 下载前复核 bit/CWC/BID 的 SHA256 与 r1 manifest 一致；不一致即停。
3. **先下载（COM8 关闭）**：cwd=`r0\td`，`td_commands_prompt.exe download_sram_b10.tcl`。日志须含 `B10_DL_OK mode=jtag(sram)`；把 bit SHA256、BID SHA256、`B10_DL_DEVICE` 追加到 `r0\board\log-r1\download_sram_r1.log`。**只下载 1 次**。
4. 结束 hwserver/TD 的 FTDI 占用，等 ≥2 s；**后开 COM8**：
   `python r0\board\capture_com8.py --port COM8 --baud 115200 --secs 180 --outdir r0\board\captures_r1`
   要求 `com8_180s.bin` 存在且 >0 B。
5. 解析：`python r0\board\parse_status_v3.py --in r0\board\captures_r1\com8_180s.bin --json r0\board\captures_r1\status_v3.json --min-packets 2`
   - ≥2 个合法 v3 包（177 B/ver=3/len=177/XOR 全对）；
   - 记录首/末 `raw_pub`、`enc_frames`、`exported`，增量=末−首，三者均 >0 才满足主门；
   - 同时记录 `crop_geom_err/crop_short/errors`。
6. 解码（仅当 `exported` 增量 >0）：
   `python r0\board\decode_frame.py --in ...\com8_180s.bin --outdir ...\decoded`
   要求 ≥1 帧：`A5 5A`、ver/len 合法、`stream_len` 与实际一致、stream CRC 通过、zlib 解出 1920×1080 / 2,592,000 B。
7. 判定：全满足 = G3-r1 PASS；有包但三增量不全 >0 或帧未解出 = ⚠（写清卡点，保留证据，不二次下载）；0 B/无包 = 停。
8. 写 `result-r1.md`：实际下载次数（1，累计 1/2）、TD 使用（1 会话/综合 1/布线 1/bitgen 1/CWC 1）、G2/G3 表、哈希、计数与增量、解码结论；`lessons-r1.md`（如有）；回填 manifest 的 `download_count`/证据路径。父 T10 **不置 done**。

## 可选 W1-r1-opt（只在 W3 证据落盘后、时间允许）

- 复用 `r0/sim/tb_p1_chain.v` 的相机驱动，复制到 `r0/sim/r1-extra/`；不改原 TB。
- ① R1 丢 LAST：LAST 拍对 CDC FIFO 背压 → 坏帧不发布、`raw_drop/abort` +1、slot 回收、下一好帧正常发布；
- ② 3 连续真实压缩帧：逐帧 44 B 头/长度/stream CRC/zlib，状态包仅帧间。
- 结果写 `r0/sim/r1-extra/findings-r1-extra.md`。**不改 RTL、不重综合、不重下载**；暴露的真实缺陷记为残余风险/下一任务输入，不改 r1 结论。

## 常见坑（r0 已踩）

- `crop_pix` 1-bit 缺陷：r0 P1 只报 `exported=0`，不报语法错；综合前必须确认 40 bit。
- TD 的 `download_sram_b10.tcl` 若 cwd 不对，只打印 banner 不下载；必须 cwd=`r0\td` 且日志出现 `B10_DL_OK`。
- 下载时 COM8 被监听会让 hwserver `usb_open` 失败；先下载、后监听。
- `03_cwc.tcl` 遇到已有 `a1_board.cwc`/`cw/compiled.*` 会直接报错退出；预检时确认不存在。
- 不要把 `a1_board_Runs` 当垃圾删；改名保留，r0 的 s3 报告是测试者复核输入。
- 不写 Flash、不改线/电源/相机、不换板、不跑第三次下载。

## 交付

`CANDIDATE-MANIFEST-b10-b9-fix-r1.json`、`r0/artifact-hashes-r1.txt`、`r0/td/{build_console_b10_r1.log,bitgen_console_b10_r1.log,cwc_console_b10_r1.log,a1_board.bit,a1_board.cwc,a1_board_inst.bid}`、`r0/board/captures_r1/**`、`r0/board/log-r1/**`、`result-r1.md`、`lessons-r1.md`（如有）、`r0/sim/r1-extra/**`（可选）。测试者报告由独立 fpga-tester 写 `test-reports/T10.b10-b9-fix-r1-integrated.md`。
