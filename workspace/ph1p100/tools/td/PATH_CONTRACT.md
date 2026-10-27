# TD / 仿真盘符与工程路径约定（2026-10-24）

## 工程位置

| 内容 | 路径 |
|---|---|
| 工程主仓库（源码/工具/技能/run） | `D:\fpga\ph1p100` |
| 文档区（OneDrive，经 junction 挂为仓库 `docs/`） | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\docs` |
| 参考设计（VID006 IMX415 等） | `D:\fpga\refs` |
| 旧 run / 旧整理归档 | `D:\fpga\archive` |
| TD 安装 | `D:\anlogic\TD_Release_2026.2` |
| TD 活动工程（不随仓库同步） | `D:\TD\work\csi2` |

仓库根现在是短 ASCII 路径 `D:\fpga\ph1p100`，不再为了绕开 260 字符限制而必须 `subst`；
但历史脚本和 `.al` 仍使用下列盘符，保留兼容。

## 固定盘符

| 盘符 | 指向 | 谁使用 |
|---|---|---|
| `T:` | 当前 TD run 目录（含 `a1_eng_top.v`、`a1_small_top.sdc`、`.al`） | TD GUI / `.al` |
| `Y:` | 工程根 | TD `.al` 里的 `Y:/upstream/...` |
| `P:` | 工程根 | `tools/codec/run_p2*.ps1`、`run_p3*.ps1` |
| `W:` | 当前仿真 run 目录 | 上述仿真脚本 |
| `X:` | **保留给 TD run 目录，禁止再映射到工程根** | — |

要点：

- `T:` 由 `tools/td/td_env.ps1` 创建，并校验 `a1_eng_top.v`、`a1_small_top.sdc` 与
  `upstream/ph1p100-pcie-ep-fpga/rtl/...` 是否存在；映射冲突时报错而不是静默覆盖。
- `Y:`/`P:`/`W:` 里的旧映射会在重启后消失，重开 TD/仿真前重新运行脚本即可。
- 新建 run 时，把 `T:` 指到该 run 的 `td` 目录，再打开该目录下的 `.al`。

## 当前 canonical 工程

```
D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-eng-freeze\r10\td\a1_eng_freeze_r10.al
```

该文件 `Path` 为 `T:/`。打开方式：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\td\open_td.ps1
# 只验证映射、不启动 GUI：
powershell -NoProfile -ExecutionPolicy Bypass -File tools\td\open_td.ps1 -NoLaunch
# 指定其他 run：
powershell -NoProfile -ExecutionPolicy Bypass -File tools\td\open_td.ps1 `
    -TdDir "workflow\runs\<run>\<task>\r0\td"
```

## 根目录历史文件

- `a1_eng_freeze_r9.al`：2026-10-21 的失败工程（`X:` 曾指向项目根），仅作历史保留。
- `a1_eng_freeze_r9_Runs/`：上述失败 run 的日志，仅作证据保留。
- `a1_bp_r2.al` / `a1_bp_r2_Runs/`：2026-10-22 的 B+R2 运行记录。

## 迁移说明（2026-10-24）

仓库整体从 OneDrive 中文长路径迁到 `D:\fpga\ph1p100`；`docs/` 物理留在 OneDrive，
以 junction 形式挂回仓库继续被 git 跟踪。迁移前的旧 run 证据里若出现
`C:/Users/czz/OneDrive/...` 绝对路径，属于历史记录，不改写。
