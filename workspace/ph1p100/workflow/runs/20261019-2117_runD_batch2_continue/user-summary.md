# 用户短总结 — 20261019-2117_runD_batch2_continue（最终）

## 结论

- **T08 双相机同步离线原型：PASS r0**（G0/G1/G2；独立重编译/复跑、G2 Routed、三时钟、WNS/TNS≥0）。
- **T02 单 A 板级闭环：功能/工程 PASS，系统/G3 只能 partial**。6 张原图 6/6 与转录一致；身份、长度、words、flags、fault、pass/seq、几何、CRC、word0–8 均符合；内部 abort/recovery 与 RTL 语义相符；B01 699 项/候选 0 漂移；下载成功（PRG-2014、100%、29.4 s）。
- 但操作者未具名、接线/供电仅为口述、无 CSV/原始导出/独立观察；ROI 的 X/Y/SKIP 与物理 Bayer 相位没有直接探针。因此 **G3=partial，不判 PASS**。这不是数值错误、也不是候选漂移。

## 你不用再做什么

不再需要补 CSV/截图/操作者，也不会再派测试者；本 run 结束。按规划 **B** 收尾，接受上述 partial 边界。

## 板子与回退

- 板上仍是 T02 候选 `b68c6e18…f9bf`（SRAM，**断电即丢**；断电后要用时需重下）。
- 0207 候选已被 T02 覆盖；0207 若还要采，需另轮重下。
- 旧回退：bit `bfafdf97…` / CWC `8d2998b9…`（基线 run `debug-fix3`）；只作入口，不自动执行，不写 Flash。

## 路径

- T02 最终报告：`workflow\runs\20261019-2117_runD_batch2_continue\test-reports\T02.codex-singleA-board-r0-recovery03-integrated.md`
- 本 run 收尾：`final-summary.md`、`handoff.md`
- 上板/回退清单：`board\t02\board-checklist-final.md`

## 边界

仅 SRAM、不写 Flash、不推送、不接 PCIe/RK、不批量删除。T02/T06/T11 父任务未 done；G4 长稳/优化后放；T08 离线 PASS 不外推真实双路曝光同步。
