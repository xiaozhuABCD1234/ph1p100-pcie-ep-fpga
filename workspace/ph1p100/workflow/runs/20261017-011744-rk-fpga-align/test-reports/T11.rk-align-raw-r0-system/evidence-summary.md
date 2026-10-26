# T11.rk-align-raw r0 — system 维度独立复核摘要（证据索引）

Date: 2026-10-17 (local). Tester: fpga-tester-system (new instance, round0). No production files modified.

## S1 manifest 独立复算（verify_manifest.py / verify_manifest.out.txt）
- `raw/candidate-manifest.json` SHA256 = `aab0cc08ef0134d5fcb18b25e0b70c43e9af1d577513ca2996dc46f22de76975`（与冻结值一致）
- 243/243 条目逐一复算 SHA256：0 mismatch / 0 missing（production_inputs/build_scripts/test_inputs 基=项目根；rk_patch_inputs/build_artifacts 基=run 目录）
- 与 T07 manifest 交叉比对“零变化”声明：SDC/ADC/checked 三文件/ddr_frame_pusher.v 全部 SAME
- production_inputs 差异：仅 `ph1p_pcie_ep_top.v` 修改；新增 `cam_r10f_writer.v`、`crc32_upd4.v`（与 change-report §1 一致）
- samples 与 contract artifacts 逐字节相同：1080p `646ebaed…`（2,592,768 B）、small `c855e03d…`（4,096 B）

## S2 默认入口 run_sim.ps1 原样复跑（entry-sim-p3/）
- 命令：`powershell -ExecutionPolicy Bypass -File tools/pcie_integration/run_sim.ps1 -Tb tb_t11_csi_enable_corner -OutDir …/entry-sim-p3 -TbFiles tb/tb_t11_csi_enable_corner.v -Defines MIPI_PHY_SIM_STUB`
- 产物：commands.log（vlog exit=0 / vsim exit=0 / subst S: removed）、vlog.log（Compiling module cam_r10f_writer）、vsim.log `ALL PASS`，`[summary] good=2 bad=2 crc=1 abort_pulses=3 good_pulses=2`（与开发 p3_enable 证据逐值相同）
- 注：`-TbFiles` 需相对 `sim/`（`tb/…`）；传 `sim/tb/…` 会双前缀失败——按 build-entry.md 写法使用即可

## S3 BOM 功能要求（字节级）
- `tools/pcie_integration/run_sim.ps1`：首 3 字节 `EF BB BF`（BOM_PRESENT）
- `tools/pcie_integration/run_td.ps1`：首 3 字节 `EF BB BF`（BOM_PRESENT）

## S4 RK 增量补丁独立 apply-check（rk-applycheck/）
- 隔离副本 `baseline/` = backend/rk-driver-src（T07 树）→ git init + commit（exit 0）
- `git apply --check` → exit 0；`git apply` → exit 0（系统级 core.autocrlf=true；见 rk-applycheck/apply-check-system-tester.txt）
- apply 后 3 文件与交付 `raw/rk-driver-src` 比对：CRLF 归一后 3/3 逐字节相同（frame_grab.rs 原始即相同）
- 负向设置对照：显式 `-c core.autocrlf=false` 会在 frame_grab.rs:43 失败（基线树 LF/CRLF 混合+补丁 LF）→ 证实 apply-check 依赖系统 git 配置，开发记录中的 CRLF 归一注记属实

## S5 严格解析工具与 fail-closed（本目录）
- samples 严格校验：small exit=0 / 1080p exit=0（`R10F_STRICT_OK`）；e2e RTL 输出 `raw/g1/msim/p2_e2e_v6/t11_e2e_e4_host.bin` 独立重跑 exit=0
- RTL 输出帧头逐字节抽验：magic R10F@0、ver 1.0@4/6、hdr_bytes 128@8、session@0x10、seq@0x14、width/height/stride@0x1C/0x1E/0x20、roi@0x24/0x26、valid_bits=10@0x2A、packing=0@0x2B、raw/payload@0x2C/0x30、flags@0x4C、三 CRC@0x50/0x54/0x58、reserved 全 0、尾 640B 全 0
- selftest：38 checks / 0 failures / `CONTRACT_VECTORS_OK`；Rust↔Python 字段一致 25/25（`R10F_TOOLS_CONSISTENT`）
- 变异负例（mutations/，全部 exit=1 拒绝）：truncated / bad_magic / nonzero_tail / payload_flip（payload_crc32 不等）/ header_flip（header_crc32 不等）/ bad_codec / wrong_session

## S6 顶层真实接入（静态 + TD 证据）
- `ph1p_pcie_ep_top.v`（manifest SHA `817d1949…`）：两片 `cam_r10f_writer`（A/B，clk_ddr/cam_clk/rel_tgl0..3/session/wr_len 各一套）；`w_push_ddr_len` 由 CTRL[8] 选 A/B；`w_push_frame_bytes`=writer len（DDR 源）
- writer：`wr_len = DMA_BYTES32`；`DMA_BYTES=((PAY+HDR+4095)/4096)*4096`；W/H/X0/Y0/SKIP=1920/1080/960/540/37（占位，synthetic）；`FLAGS_VAL=(X0|Y0)!=0?2:0`
- DDR 基址 A `0x00100000/0x00900000`、B `0x01100000/0x01900000`，4KiB 对齐、双块间隔 8 MB ≥ dma_bytes；`DDR_CAP_BYTES=0x1000_0000`
- TD 单会话证据：`td_00_all.log` 有 `PRJ-1406`×2 + `PRJ-1424` + `T07_ALL_DONE`；phy/syn run.log 与 area/final_timing 均含 `cam_r10f_writer`（真实综合/实现）；无 download/Flash 行
- 位流身份：`…/best_result/ph1p_pcie_integration.bit` SHA256 `14b32037eb0b4aff4f9ea1f61b75160c11ff9381e23f11563f97ecaf5bf5686b`（= manifest = dev-result）；CWC 无产物（不适用）
- final_timing.rpt 抽验：Routed；SWNS 0.115 / STNS 0.000 / HWNS 0.020 / HTNS 0.000；0 Viol Endpoints / 18,724；clk2 0.115（1911 端点 0 违例）/ clk3 0.150（1816 端点 0 违例）

## S7 寄存器面/槽布局/ACK 接口
- ep_bar_win（T07 同 SHA）：0xA0..0xAC / 0xE0..0xEC writer 握手；0xC0..0xCC push 诊断；0x100..0x11C RKA1 扩展（magic 0x31414B52/version 0x00010000）；0x120..0x12C CSI 诊断
- contract/registers.json host_abi：slot header 16B / hdr_bytes offset 128 / 112B pad / R10F 128B / mailbox 64B / push_dbell offset 32；arm mask 0x61（B 0x161）
- 驱动（raw/rk-driver-src）：`ANLOGIC_FRAME_HDR_BYTES=128`、`ANLOGIC_FRAME_DMA_BYTES=2592768`、frameinfo.hdr_bytes、cap_bytes 语义；frame_grab R10F 严格解析失败 `EX_INCONSISTENT=5` 拒发布；r10f_check 退出码 0/1/2/5
- pusher（T07 同 SHA）：dst 64bit（dst_lo/hi）锁存、dst+len 无 64bit 回绕、dst 128B 对齐、db 4B 对齐且不与传输区重叠、cap≥frame_bytes、frame_bytes 4KiB 整倍且 ≤ MAX_FRAME_BYTES(3840×2160)、DDR 源 base 4KiB+范围≤DDR 容量

## S8 卫生与硬件边界
- manifest `volatile_excluded`：build_artifacts 35 条 0 命中易变日志模式
- 回退候选在位：T07 r3 bit `0943cb36…8b0a`（backend/candidate best_result）存在
- 本 run raw/ 无任何 download/jtag/flash/svf 产物；td/00_all.tcl 无 download_sram 调用 → “本包不操作硬件”与证据一致（G3/G4 按规划留 T07.rk-align-board）
