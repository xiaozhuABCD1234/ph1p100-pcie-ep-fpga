# T09.rk-align-algo — build / run entries（可复现命令）

项目根：`C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道`（含中文路径；
脚本内部用临时 subst 映射，ASCII 盘符，用完撤销）。

## 1. 独立软件 oracle 自检（与 parallel 参考交叉）

```powershell
& "C:\Program Files\Python311\python.exe" tools/algo/oracle_algo.py --selftest
# 期望：T09_ORACLE_SELFTEST ... 全部 PASS + T09_ORACLE PASS（当前 10/10 PASS）
```

## 2. 向量生成（oracle + 参考交叉后写文件）

```powershell
& "C:\Program Files\Python311\python.exe" tools/algo/gen_algo_vectors.py --out workflow/runs/20261017-011744-rk-fpga-align/algo/vectors
& "C:\Program Files\Python311\python.exe" tools/algo/gen_ref_vectors.py   --out workflow/runs/20261017-011744-rk-fpga-align/algo/vectors
```

## 3. G1（ModelSim 真实 RTL）

```powershell
# core：三算法逐样本 + 边界/首帧/坏帧/切换/停顿/并发 + LUT 回读
& "C:\Program Files\Python311\python.exe" tools/algo/run_g1.py --case core --mutation none
# 负对照（复制件变异，原文件 SHA 前后校验；期望特定 mismatch 且无仿真错误）
& "C:\Program Files\Python311\python.exe" tools/algo/run_g1.py --case core --mutation he_samebin
& "C:\Program Files\Python311\python.exe" tools/algo/run_g1.py --case core --mutation gray_round
& "C:\Program Files\Python311\python.exe" tools/algo/run_g1.py --case core --mutation gau_round
& "C:\Program Files\Python311\python.exe" tools/algo/run_g1.py --case core --mutation gray_clamp
# 吞吐（1080p30 常数帧，2 帧，含 HE 帧末）
& "C:\Program Files\Python311\python.exe" tools/algo/run_g1.py --case rate --mutation none
# 工作树引入候选的模块级验证
& "C:\Program Files\Python311\python.exe" tools/algo/run_g1.py --case gray        --mutation none
& "C:\Program Files\Python311\python.exe" tools/algo/run_g1.py --case gauss_frame --mutation none
```

每个用例在 `algo/g1/msim/<case>[-<mutation>]-<stamp>/` 下产生 `report.json`、`vlog.log`、
`vsim.log`、`commands.log`、向量副本与 SHA；runner 打印 JSON 摘要（verdict/coverage/lut_check）。

判据：clean 用例 = `ALGO_*_PASS` 标记 + 退出码 0 + 无 `** Error` + LUT 回读与
`algo_core.lut.hex` 一致；负对照 = 无仿真错误 + 无 PASS 标记 + 出现指定 mismatch
（TB 以 `$finish` 结束，退出码恒 0，故退出码不参与负对照判据）。

## 4. G2（TD 6.2.3，模块级小顶）

```powershell
powershell -ExecutionPolicy Bypass -File tools/algo/run_td_algo.ps1 -Name smalltop-r1b
# 单会话 00_all：create_project → syn_1 → phy_1 → save_best_bits；不下载、不写 Flash
# （round1 重建序列：r0d 基线 → r1a（HE 合并/LUTGEN 流水）→ r1b（直方图写流水+gray 流水））
```

- 顶层：`img_algo_top_g2`（内含 `img_algo_parallel_top` 真实并行组织 + pin 级包装）。
- 约束：`tools/algo/td/img_algo_top.sdc`（`create_clock algo_clk 5.333ns` = 187.5MHz 字节域
  目标；**主工程 SDC 未改**）、`img_algo_top.adc`（仅钉 clk/rst_n/2 输出）。
- 产物：`algo/g2/<name>/ph1p_algo_smalltop_Runs/{syn_1,phy_1}/`（`final_timing.rpt`、
  `*.area`、`*.bit`、`*.db`）；判定读 `phy_1/final_timing.rpt` 与 `*_phy.area`。
- 完成标记：`T09_ALGO_ALL_DONE` + `PRJ-1406 Run phy_1 finished` + `PRJ-1424 saved as best result`。

## 5. 冻结与自检

```powershell
& "C:\Program Files\Python311\python.exe" tools/algo/freeze_manifest.py
# 生成 algo/candidate-manifest.json 与 algo/manifest-selfcheck.json（重读重哈希，ok=true 才算冻结成功）
```

## 6. 吞吐实测（1920x1080 x2 连续流）

- 4 px/beat 连续服务；187.5MHz → 750 Mpx/s 处理能力。
- 实测：每帧 518400 拍，`cyc_f0=519370`、`settled_cyc=1040120` → 1.0032 拍/帧拍
  ≈ 0.997 拍/拍 ≈ 748 Mpx/s；`all3=1035832`（约 99.9% 拍三路并发）。
- 1080p30 单路 62.2 Mpx/s（≈8.3%）、双路 124.4 Mpx/s（≈16.6%）；1080p60 双路 ≈33%。
- 帧末 HE 计算 ~4.1k 拍；1080p30 帧间隔 ~33ms（<0.02%）。头/报文另计。
