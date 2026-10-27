# T11.rk-align-raw：正式 packed RAW10→R10F 非压缩成帧、所有权与严格解析

batch_size=1；round0；你是本包唯一新开发，不派生代理。读 fpga-dev 与 fpga-design-guide 技能、根AGENTS、request/user-feedback-01/-02、fpga-design-guide.md、contract/registers.json+acceptance-vectors.json+compatibility.md、artifacts/next-backend-input.md，以及 backend 冻结证据（candidate-manifest.json、change-report.md、hardware-ready.md、rk-change-list.md、g2/README.md、g1/README.md、patches/rka1-driver.patch——全部只读）。backend/ 与首包冻结内容不可改写；本包新输出写 `OUTPUT_DIR/raw/`。

## 目的与本包边界

在 backend r3 候选（manifest 68F9F4D0…4275、bit 0943CB36…8B0A）基础上，把“诊断/合成源”升级为正式非压缩帧通路：checked CSI 4px → packed RAW10 → R10F v1（128B 头 + 三层 CRC + 640B 尾零）→ AXI DDR 完整帧（所有权 writing→complete→held_for_tx→released）→ peer one-shot 发送 + 门铃。RK 侧只做增量：严格解析校验工具与按需补丁更新；不安装、不写队友仓库。

几何：以源包实际 WC/行数推导；4K30 模式，仅按实际有效行取偶数 ROI 形成 1920×1080（默认居中 x=960、有效图 y=540；physical dummy/embedded 行跳过另计）；ROI Bayer 相位按有效源相位与 x/y 奇偶推导。板证前只输出明确标注 synthetic/diagnostic 的候选；不得把 960×540 预览放大当 1080p，不得把合成帧称真实帧。

## 实际写入范围与工具

- 继续使用 `fpga/csi2/pcie_integration/`（新增 RAW10 packer / R10F 成帧 / source ownership / 顶层接入）与 `tools/pcie_integration/`（runner、生成器、严格解析校验器）。
- 新候选/证据/数据库/位流/清单/文档：`OUTPUT_DIR/raw/`（独立于 backend/；不得覆盖 backend/candidate、backend 文档或首包冻结内容）。
- 测试只写 `OUTPUT_DIR/test-reports/T11.rk-align-raw-r0-*.md` 与各自证据目录；backend/ 只读。
- 工具：TD6.2.3 CLI `D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe`；ModelSim `D:/intelFPGA/18.1/modelsim_ase/win32aloem`；复用 `tools/pcie_integration/run_sim.ps1`、`run_td.ps1`（两个 .ps1 的 UTF-8 BOM 是功能性要求，编辑必须保留）。外部 D 盘只读。
- 禁止：放宽 SDC、加 set_multicycle/set_max_delay、改 187.5 MHz 或相机速率前提、改 `fpga/csi2/src/csi` 原源、改 wrapper 对外接口/顶层连线（确需→停止交规划）；批量删除、外部工程写、Flash/发布/队友消息。任何 RTL/约束改动都要重跑 G2（相机字节域 setup≥0 为回归门槛；r3 余量仅 +0.107 ns）。

## 必须实现

1. packed RAW10 打包：4px(40bit)→5 字节（P0[9:2],P1[9:2],P2[9:2],P3[9:2]，低 2bit 按 P0→P3），与 `parallel/frame/frame_contract.py` 一致；10bit 不静默变 8bit；行尾/tail 逐拍正确并与 SOF/EOL/EOF 对齐；CSI 不可反压（FIFO 满拒整帧并计数，不发布残片）。
2. 帧控制与所有权：writing→complete→held_for_tx→released 状态机；good/abort（CRC/ECC/WC/行长/短帧/timeout）参与发布裁决，坏帧禁止成为发送源；源 descriptor（session/seq/base/字数/CRC）跨域原子锁存；capture_seq 缺口记录；reset 隔离旧会话。
3. R10F v1 成帧：128B 头（magic/version/format0/codec0/valid_bits10/packing0/几何/stride/raw=payload/长度/flags/session/seq）；header_crc32 清 0 其 0x58 字段后覆盖 128B；raw/payload_crc32 覆盖 packed 有效载荷；640B 全 0 尾；dma_bytes=2,592,768 整 4KiB；transport 尾/槽 padding 不计入内容 CRC。
4. 发送接入：复用 backend 的 one-shot/容量授权/地址规则（dst128B 对齐、db4B、64bit 无溢出、cap>=dma_bytes、source base4KiB）；frame_bytes=dma_bytes；完整 1080p=20,256 笔 128B MWr+1 门铃、DDR 读 633×4KiB；数据后门铃、无 RO；held 不覆盖。
5. 严格解析工具与 RK 增量：`tools/pcie_integration/` 提供离线严格 R10F 校验/样例生成（拒 unknown codec、长度不符、尾非零、CRC 错、session 不匹配；可生成小几何与 1080p 样例）；如帧语义/ABI 需扩展，仅在 `raw/rk-driver-src/` 新树从 backend 的 rk-driver-src 基线生成增量 patch（`git apply --check` 过；不写 peer 仓库、不安装）；无增量则明确记录“沿用 rka1-driver.patch”。
6. 真实几何证据路径：WC/行数参数化；板上真实值未得前所有声明加 synthetic/diagnostic 标签；列出板测需读计数器/寄存器（沿用 hardware-ready.md §4）。

## 局部检查与冻结产物

- G1（ModelSim 真实 RTL）：小几何端到端（生成→打包→成帧→DDR→pusher→host 模型→逐样本+CRC 复核）；完整 1080p 长度边界（20,256 MWr+633 突发+尾零）；坏帧拒绝（EOF abort/短行/坏 CRC/坏 ECC 不发布）；RAW 尾/边界；capacity 高位/溢出拒绝；慢消费 held；reset 旧会话隔离；沿用独立 TL/TLP 记分板；至少一项可重放负对照。
- 增补 T07 遗留用例：`I_enable` 包尾后 1 拍撤销的覆盖缺口（functional r2 §6.1，仅诊断计数级）。
- G2：同一最终 DB 的 TD 重建（setup≥0/STNS0/hold≥0/资源≤器件/Routed/报告与 bit 同源 SHA；TD 重建记账≤2 次；余量如实登记）。
- 产出：`raw/change-report.md`、`raw/source-provenance.json`、`raw/build-entry.md`、`raw/actual-commands.json`、`raw/g1/`、`raw/g2/`、`raw/hardware-ready.md`（板测指导更新）、`raw/rk-change-list.md`（增量或明确沿用）、`raw/candidate-manifest.json`+自检、`raw/dev-result.json`、`raw/lessons-learned.md`。停止修改后 ready_for_test。

## 三维验收与停止

functional：上述 TB 全过（真实 RTL；G1 必需）。engineering：独立复核同 manifest 最终 DB/STA/约束/CDC/资源与 bit（G2 必需）。system：顶层真实接入、所有权、RK 补丁/解析工具 apply-check、64/32 地址、槽布局/ACK、板测入口可操作；不宣称 G3 实收（G3/G4 留给板测包，G5 未完成）。报告 `T11.rk-align-raw-r0-{functional,engineering,system}.md` 首行唯一判定，绑定 `raw/candidate-manifest.json`。缺工具/资料直接 blocked 交原规划，不空转、不放宽。
