# dev-result — `T10.a1-format-ref`

- task_id：`T10.a1-format-ref`
- run：`20261020-0209_singleA_aplus_closedloop`
- 状态：**ready_for_test**（P1 开发完成并自验通过；等待独立综合测试者）
- 日期：2026-10-20
- 写入性质：**纯新增文件**；未修改/覆盖任何既有生产文件；未上板、未下载、未写 Flash、未接 PCIe/RK、未推送。

## 1. 交付内容

| 交付 | 路径（绝对/相对 task 目录） |
|---|---|
| 输入 profile（四态审计） | `p1/input-profile.json` |
| A+ v1 格式冻结 | `p1/format-v1.md` |
| 参考编码模型 + Bayer 正/逆变换 | `PROJECT_ROOT/upstream/ph1p100-pcie-ep-fpga/tools/codec/a1_ref.py` |
| 独立严格 zlib/DEFLATE 解析器 | `.../tools/codec/a1_inflate_strict.py` |
| 32 B 记录校验器 | `.../tools/codec/a1_sample_check.py` |
| 向量生成器 | `.../tools/codec/a1_vectors.py` |
| 三方验证器 | `.../tools/codec/a1_p1_verify.py` |
| 冻结清单生成器 | `.../tools/codec/a1_freeze_manifest.py` |
| 向量（9 正 / 17 负） | `p1/vectors/` + `p1/vectors/vectors.json` |
| 验证报告 | `p1/verify-report.json` |
| 原始日志 | `p1/logs/run-vectors.log`、`p1/logs/run-verify.log` |
| 结果说明 | `p1/result.md` |
| 冻结 manifest | `CANDIDATE-MANIFEST.json`（最后生成） |

## 2. 自验结论

- `python a1_vectors.py --out <task>/p1/vectors` → exit 0，生成 9 正例 + 17 负例。
- `python a1_p1_verify.py --vectors <task>/p1/vectors --report <task>/p1/verify-report.json` → exit 0。
- 最终行：`ROUNDTRIP_PASS mismatch=0 positives=9 negatives=17 three_way=9`。
- 1080p 纹理：540 块 fixed、stream 101,566 B（合成纹理，ratio 25.52，不可外推真实）。
- 1080p 随机：540 块 stored、stream **2,594,706 B**，恰等于冻结最坏上界（+0.1044%）。
- 17/17 负例按稳定 reason code 拒绝；流级负例同时被 zlib 拒绝（尾随字节为 `unused_data`）。

## 3. 格式冻结决定（需测试者重点核对）

1. 块 = 1 个 2 行对；1080p **540 块**；最坏 stored **2,594,706 B**。guide §2 的 `270 块 / 2,593,356 B` 已作为算术勘误记录，未采用。
2. 变换域打包：平面 `R,G1,G2,B` 样本首尾拼接后按 5B/4px 连续打包；4 样本组可跨平面、不跨块。
3. 预测器每块每平面重置；奇数 H 尾块只含 R/G1 单行。
4. 测试头 header CRC 覆盖 `[0x00,0x1C)` 28 B，字段自身不参与。
5. 32 B 测试头无 `stream_crc32`、无 W/H；P4 导出契约需在记录外携带。P1 未擅自扩头。

## 4. 明确未做（不得由本结果推断）

- 无 RTL、无 ModelSim/Verilator、无 G1 RTL 证据。
- 无 G2/STA/资源/吞吐；无 77.76 MB/s 或 97.2 MB/s 结论。
- 无真实 RAW、真实 ROI/相位、真实压缩率、非 PCIe 导出。
- 无板上/PCIe/RK/Flash/下载；需求二/三未完成。
- 合成 A/B 比率不构成真实 Bayer 收益结论。

## 5. 给测试者的入口

- 复跑（工作目录 `upstream/ph1p100-pcie-ep-fpga/tools/codec`）：
  - `python a1_vectors.py --out <task>/p1/vectors`
  - `python a1_p1_verify.py --vectors <task>/p1/vectors --report <task>/p1/verify-report.json`
- 单流检查：`python a1_inflate_strict.py <stream> --expected-len <n>`
- 单记录检查：`python a1_sample_check.py <record> --width 1920 --height 1080`
- 冻结清单：`CANDIDATE-MANIFEST.json`（逐文件 SHA256 + 输入版本 + 自校验 `MANIFEST_OK`）。
