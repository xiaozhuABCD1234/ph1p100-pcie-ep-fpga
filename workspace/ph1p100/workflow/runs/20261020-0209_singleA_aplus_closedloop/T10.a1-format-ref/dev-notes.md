# dev-notes — `T10.a1-format-ref`

## 1. 写域与允许清单

**唯一写域（均为新建）**

- `upstream/ph1p100-pcie-ep-fpga/tools/codec/`（dispatch.json 的 `upstream_new_only` 三个新目录之一）：
  - `a1_ref.py`
  - `a1_inflate_strict.py`
  - `a1_sample_check.py`
  - `a1_vectors.py`
  - `a1_p1_verify.py`
  - `a1_freeze_manifest.py`
- run 输出：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-format-ref/**`
- lessons：`workflow/runs/20261020-0209_singleA_aplus_closedloop/lessons/T10.a1-format-ref-lessons.md`

**未修改/未覆盖**

- 未改 `ph1p_pcie_ep_top.v`、`cam_r10f_writer.v`、`csi_rx_10bit_unpack.v`、`r10f_strict.py`、`run_sim.ps1`。
- 未改生产 `.al`、`build.tcl`、SDC、`sim/compile_checked.f`、约束、既有 RTL/TB、`docs/protocol/**`。
- 未创建 `rtl/ep_side/codec/**`、`sim/tb/codec/**`（P2/P3 才需要；本轮不预占）。
- 未写 `workflow/tasks.json`；未改旧 run/manifest/bit/CWC/BID。
- 未批量删除；本地无 git 操作。

## 2. 工具与环境（实测）

| 工具 | 版本/路径 | 本轮用途 |
|---|---|---|
| Python | 3.11.5，`C:\Program Files\Python311\python.exe` | 参考模型、向量、验证、manifest |
| zlib | 1.2.13（`zlib.ZLIB_VERSION`） | 第三方标准解码对照 |
| binascii.crc32 | 标准库 | IEEE CRC32 |
| 未用 | ModelSim/TD/Verilator/板卡 | P1 不需要；未启动 |

- 运行时间：向量生成与验证合计 < 1 分钟（wall clock 最终验证 1.73 s；生成约数秒）。
- 工具调用：在 30 次预算内。

## 3. 实现选择与理由

1. **块粒度严格按 2 行对**：1080/2=540。guide §2 的 270/1,350/2,593,356 与同文件块定义和 §3 `540` 矛盾，按 §3 与块定义冻结，并在 `format-v1.md` §4.1 记为勘误。
2. **变换域打包**：guide 只规定“平面样本拼接、总样本数不变”，未规定字节打包。冻结为“平面序列连续 4 样本组、5B/4px”，保证 `xform_len==raw_len`、组不跨块、W%4==0 即可用；避免每平面补 bit 造成长度变化。
3. **预测重置**：每块每平面 `s[-1]=0`。这样块可独立编码/解码，与“每块清 LZ77 历史”一致；跨块预测需要额外状态，guide 未要求。
4. **奇数 H 尾块**：块从 y=0 起每 2 行切，H 奇数时尾行必为 even y，只含 R/G1；不补 G2/B。
5. **header CRC 范围**：guide 写 `0x00..0x1B` 且“字段置 0”。字段在 `0x1C`，不在范围内；冻结为对 28 B `[0x00,0x1C)` 计算，字段自身不参与。此为措辞歧义，已记录，不改 32 B 布局。
6. **参考编码器不追求与 RTL 逐字节相同**：P2 只要求 DUT 流可被 zlib + 严格解析器双解；本模型的 greedy 单候选是格式样例，不是 RTL 必须复刻的匹配器。
7. **严格解析器独立性**：`a1_inflate_strict.py` 不 import `a1_ref`、不调用 zlib；常量表独立复制；Adler 自实现。`a1_sample_check.py` 复用严格解析器做记录层校验，zlib 由验证器单独调用。

## 4. 调试/重试记录（诚实留痕）

最终日志 `p1/logs/run-verify.log` 是第 3 次运行（retry2）。前两次失败与修复：

1. **retry0**：`_fixed_tables()` 返回两个 tuple 被错误解包，`_LIT_MAX` 变成 tuple → 全部正例 `TypeError: '<' not supported ... tuple and int`。修复：显式解包 `lit_tab, lit_max, dist_tab, dist_max`。
2. **retry1**：固定 Huffman 解码把 LSB-first peek 值直接当 MSB-first 码，距离/长度全错（`E_DISTANCE_WINDOW` 等）。修复：增加 `_rev_bits()` 将 peek 的 LSB-first 位反转成 canonical MSB-first 码（带缓存）。
3. **retry2**：9 正例 + 17 负例全通过，`ROUNDTRIP_PASS mismatch=0`。

说明：日志文件在每次重跑时被覆盖，失败文本未单独归档；本文件保留失败现象、根因与修复，最终证据以 retry2 日志与 `verify-report.json` 为准。失败均发生在工具代码，未修改格式门槛或期望值。

## 5. 已知限制/歧义（未自行降门槛）

- 32 B 测试头无 `stream_crc32`、无 W/H：P1 不扩头；P4 导出契约需外带。
- guide §2 最坏膨胀数值勘误（见上）；P4 容量检查必须用 2,594,706 B。
- 物理 Bayer/ROI 仍 unknown；2192 vs 2160+37 的 5 行差异仍 conflict；本任务不猜。
- 合成纹理的 ratio 25.52 仅是生成器性质，不是真实图集压缩率。
- P1 未产生 RTL/时序/吞吐证据；`ready_for_test` 仅指 P1 软件层可独立复核。

## 6. 复现命令

工作目录：`C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\upstream\ph1p100-pcie-ep-fpga\tools\codec`

```powershell
& 'C:\Program Files\Python311\python.exe' a1_vectors.py --out '<task>\p1\vectors'
& 'C:\Program Files\Python311\python.exe' a1_p1_verify.py --vectors '<task>\p1\vectors' --report '<task>\p1\verify-report.json'
& 'C:\Program Files\Python311\python.exe' a1_inflate_strict.py '<task>\p1\vectors\pos\p_1920x1080_texture_prep1_pred1.z1' --expected-len 2592000
& 'C:\Program Files\Python311\python.exe' a1_sample_check.py '<task>\p1\vectors\pos\p_1920x1080_texture_prep1_pred1.rec' --width 1920 --height 1080
```

`<task>` = `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-format-ref`。
