# ISS-20261018-01 — 用户报告：非英文路径可能导致 ChipWatcher/TD 自动化失败

## 登记信息

- 登记时间：2026-10-18（上海）
- 登记人：主（机械登记，未做技术判定）
- 来源：用户原话（workflow/runs/20261018-1631_runA_fpga_side_readchannel/user-input-06.md）
- 状态：**已记录，待原规划/开发核实**（不作为已确认根因；不代表已复现或已排除）

## 用户原话

> 我说明下我现在应该知道你的问题了，你把路径放在了非英文路径的地方，请把目前这些放置到原来D盘TD的地方然后再尝试自己去调试chipwatcher我觉得就可以了不用我操作

## 用户诉求（原话归纳，供规划核对）

1. 认为工程/产物位于含中文的路径可能是问题原因；
2. 要求把当前所需文件放到 **D 盘 TD 原位置附近**（用户授权该外部路径写入）；
3. 由我方继续自动尝试 ChipWatcher（不需要用户手工点击）。

## 相关既有事实（仅列路径，供核实，非主结论）

- TD CLI 尝试记录：`workflow/runs/20261018-1631_runA_fpga_side_readchannel/board-readback/cwc-cli/`（round1/round2 stdout、run 记录；其中 download 报 `PRG-9505 USB device open error`、`PRG-9525`）。
- 同轮 Tcl 的 `config_chipwatcher`/`get_hw_cws`/`export_chipwatcher` 曾在非英文路径下成功（见 `cwc-cli/` 与 `%TEMP%\runa_p3\export_chipwatcher.txt`）。
- 现有 ASCII 副本：`%TEMP%\runa_p3\`（compiled_debug.cwc / debug.bit / cw_pair\）。
- 板卡状态：debug bit `2385CDED…1873` 以 SRAM 方式载入，板保持上电。

## 待办

- 原规划裁定 ASCII 路径（如 `D:\anlogic\...`）的外部写入范围与一次有界重试的预算/停止条件；
- 若重试仍失败，保留证据并回到 GUI 兜底；
- 本条问题在 dev-plan/handoff 中登记处置结论（确认/排除/仍待定）。
