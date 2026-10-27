# rollback.md — T11.runC-board-checklist 回退/恢复文档（更新版）

本文件只增补本包的回退口径，**不改写**基线 run `20261018-1631_runA_fpga_side_readchannel` 的任何既有回退文档；旧候选全部原位并列、未复制、未覆盖。

## 1. 候选并列（不混拼）

| 角色 | bit（SHA256） | CWC（SHA256） | 字数 | 位置 | 状态 |
|---|---|---|---|---|---|
| **本包新候选（P2）** | `5B67A8F5925327BA9D0442D9E4228FCFD254C80A2F86D921CEDA70ECAE111D52`（5,224,027 B） | `8DDA54D4EFA8E6BE728A6EBB34686F25DE90A36B039EDA6F831DFB9C346C664F`（143,444 B） | 16（word0..15） | run `20261019-0207_…\build\prj\ph1p_pcie_integration_Runs\phy_1\`（`ph1p_pcie_integration.bit`、`cw\compiled.cwc`；BID `A068E42E…F1DB`） | 冻结、未下载（本轮） |
| 本候选暂存副本 | 同上（SHA 复核 MATCH） | 同上（MATCH） | 16 | `D:\anlogic\runa_runC\20261019_192056\compiled.bit` / `compiled.cwc` | 新建、零覆盖；`preload.bwcmd` 未执行 |
| 板载基线（昨晚） | `bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0` | `8d2998b96ef1763c14a1302118235a687488297ce496692b1f6cd95d76981026`（81,063 B） | 9（word0..8） | 基线 run `debug-fix3\prj\…\phy_1\`（本包只读；SHA 已复算不变） | 若板上未动则仍是它 |
| 回退候选 | `e81d353b…2b9a`（5,224,023 B，见基线 run 冻结记录） | 对应旧 CWC | 9 | 基线 run `debug-build2\` / 基线 `board-readback\candidate-manifest.json`（`BC27553A…`）登记 | 原位保留，未复制 |
| 证据候选 | `2385cded…1873`（NOT_MATCHED 证据）、`AFFC4396…`（仅证据） | — | — | 基线 run 既有目录 | 不动、不用于回退 |

> 旧候选精确路径以 SHA 检索为准（不凭记忆猜路径）：
> ```
> Get-ChildItem "workflow\runs\20261018-1631_runA_fpga_side_readchannel" -Recurse -Filter *.bit |
>   ForEach-Object { (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower() + '  ' + $_.FullName }
> ```
> 命中 `e81d353b…` 者即回退 bit；其配对 CWC 必须取**同源同目录**旧 cwc（9 字），不得与新 16 字 cwc 混用。

## 2. 回退动作（按需选择）

1. **重下旧 bit（SRAM，推荐，≈30–40 s）**：板窗口空闲时（并行线互斥，先确认）
   ```
   connect_cable -host_name 127.0.0.1:5555 -open
   read_device_id                       # PH1P100
   download -bit <旧bit绝对ASCII路径> -mode jtag -spd 7 -cable 0
   read_device_id
   connect_cable -close
   ```
   成功判据同上（rc=0 + PRG-2014 + 100%）；记录 rc/时长/SHA/时间。失败**不重试**，交原规划。
2. **断电清 SRAM**：物理断电即失（无需命令）；重上电后须重新下载任一候选。
3. **丢弃本包产物**：只需丢弃 run `board-checklist\**` 与 `D:\anlogic\runa_runC\20261019_192056\`（默认**不删**；确需删除时按根 AGENTS 仅单文件路径操作或交用户）。
4. **上游回退**：本包零 RTL/约束/构建入口改动、零 commit、零 push；worktree 仍为 P1/P2/P3 冻结状态（HEAD `b0282d2a…` + 6 M + 4 ??），无需 git 操作。

## 3. 时间与风险

| 动作 | 预计耗时 | 风险 |
|---|---|---|
| 重下本候选（SRAM） | ≈28–40 s（基线实测 28.85 s） | 低；仅 SRAM，掉电即失 |
| 重下旧 bit（SRAM） | ≈30–40 s | 低；旧文件原位 |
| 断电 10 s（DDR 校准异常时） | ≈30 s + 重下 | 物理操作由用户执行 |
| 丢弃本包文档/暂存 | 秒级 | 无硬件影响 |

## 4. 禁止事项

- 禁止 Flash/efuse/SPI/svf 任何写操作；禁止把 16 字新 cwc 与旧 9 字候选混读；禁止覆盖板上并行线候选；禁止 GUI 自动化；禁止批量删除。
