# recovery-plan-02.md — T02 recovery02 交叉命名有界修正（最后一次补证）

原规划者冻结；2026-10-20。触发：`test-reports/T02.codex-singleA-board-r0-recovery02-integrated.md` 判 **FAIL（blocked，INPUT_CONFLICT + EVIDENCE_INSUFFICIENT）**：6 张原图数值与转录一致，但 T2 的 cwc2/cwc3 文件内容互换；manifest-samples-02 的 `user_statement` 编码损坏、sample-record 仍写“未落盘/未提供”。本文件只覆盖这一次有界修正，不再开新的补证轮。

## 1. 裁定：A（一次有界修正）

- 需要用户做的只有：把 T2 两张 PNG 按内容互换文件名（不重拍、不重下载、不改接线/电源）。
- 开发：只做重命名后的 6 文件 SHA/存在性/映射登记，新建 `manifest-samples-03.json` 与 `sample-record-v3.md/json`；修正 `user_statement` 可读文本与陈旧字段（写在 v3，不改旧冻结文件）。
- 测试者：原 T02 tester 出 `recovery03`，逐张读 6 图确认 6/6；**命名修正不自动升 PASS**。G3 仍按现有证据判：原图+转录一致、操作者/接线/供电仍仅用户口述、ROI X/Y/SKIP/PHASE 无直接证据 → **至多 partial**。
- **停止规则**：recovery03 若仍 partial，立即按 B 收尾（G3=partial/blocked，写清边界/恢复入口），不再要求用户补图、不再开 recovery04。不得把 partial 写成 PASS。

## 2. 两张 T2 文件的精确互换（用户操作）

当前：

| 现文件名 | 实际内容 | 时间 | 现 SHA256 |
|---|---|---|---|
| `T2_cwc2_dhi_20261019_235228.png` | cwc3 TL（`dbg_mark_word0..8`） | 23:53:10 | `680bfc0581b8be46b24a65706a4edcb36d7b2dc7088a4de4b1dc3ebff9bf2b69` |
| `T2_cwc3_tl_20261019_235310.png` | cwc2 DHI（`cl_*`） | 23:52:28 | `424e2f09d8960e59e6e099fc5fd13ef9393bc92857c5bc404b5bbd640451cf12` |

三步互换（不要删文件）：

1. 把 `T2_cwc2_dhi_20261019_235228.png` 改名为 `T2_cwc3_tl_20261019_235310_TEMP.png`。
2. 把 `T2_cwc3_tl_20261019_235310.png` 改名为 `T2_cwc2_dhi_20261019_235228.png`。
3. 把 `T2_cwc3_tl_20261019_235310_TEMP.png` 改名为 `T2_cwc3_tl_20261019_235310.png`。

完成后：`T2_cwc2_dhi_...235228.png` = cwc2 DHI（23:52:28）；`T2_cwc3_tl_...235310.png` = cwc3 TL（23:53:10）。T1 四张、T2 cwc1 不动。

用户回一句：`已按三步互换，T2 两个文件名现在与内容一致。`

## 3. 开发重冻（用户回传后；≤8 calls/10 min）

1. 复核 T2 两文件存在、无 TEMP 残留、SHA 与内容映射：`T2_cwc2_dhi...235228.png` 应为 `424e2f09…cf12`（cwc2 DHI）；`T2_cwc3_tl...235310.png` 应为 `680bfc05…2b69`（cwc3 TL）。若 SHA 不匹配，停，记录实际值，不猜。
2. 新建 `board/t02/samples/sample-record-v3.md`、`sample-record-v3.json`：`screenshot_files_on_disk=true`、`evidence_type=original_png_on_disk`、6/6 文件名/实例/时间；`operator="用户本人（未具名）"`、`wiring="未变（用户口述）"`、`power="未断（用户口述）"`；明确标注“口述、无独立观察/CSV”。
3. 新建 `board/t02/recovery01/manifest-samples-03.json`：绑定 6 张原图（新文件名+新 SHA）、旧 manifest-samples-01/02、user-input-08/09、user-action-rename、probe map、B01 manifest/bit/CWC/BID；`user_statement` 用 UTF-8 可读文本；`status=ready_for_test`、`g3=not_run`；不覆盖旧文件。
4. 不改候选/不重下载/不重拍/不改门槛；不把 recovery02 的旧 manifest 当作 clean 输入。返回 `ready_for_test`。
5. 缺文件/仍有 TEMP/ SHA 不符 → `blocked` 列缺项，不派 tester。

## 4. Tester recovery03 边界（≤15 calls/20 min）

- 输入：6 张原图 + `manifest-samples-03` + `sample-record-v3`；同候选/同 B01 699/同下载证据。
- 必须逐张读 6 图，确认文件名/实例/时间 6/6；确认 T1/T2 间隔 104/57/71 s；确认身份/长度/words/flags/fault/pass/seq 等仍成立。
- **命名修正只消除 INPUT_CONFLICT，不等于功能/系统 PASS**：操作者/接线/供电仍仅口述、无 CSV/事件条带、ROI X/Y/SKIP/PHASE 无直接证据 → G3 至多 **partial**。
- 报告：`test-reports/T02.codex-singleA-board-r0-recovery03-integrated.md`；不得改旧报告/manifest。
- 若仍 partial：按 B 收尾，不再开补证轮；由原规划写 final-summary/handoff，G3=partial/blocked，T02/父任务不 done。

## 5. 计数与边界

- recovery01/02/03 均为证据轮，**不计实现修复轮**；actual repair rounds 仍 0；T08 PASS r0 不受影响。
- 不重下载（本轮 download 0）、不写 Flash、不推送、不接 PCIe/RK、不 GUI 自动化、不批量删除、不杀他人进程。
- 不覆盖：旧 manifest-samples-01/02、旧 sample-record、recovery01/02 报告、B01 699/bit/CWC/BID、0207 run、T08。
