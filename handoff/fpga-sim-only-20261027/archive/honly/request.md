# 本轮用户原话与双线边界

## 当前用户原话

能否并行开两个线，一个在后面一致尝试做A+H，一个接着尝试 H-only 过 TD/STA

## 已完成基础（H-only 已过 prototype S_ss gate）

run `20261026-231711_fpga-a-plus-h-prototype` 已 finished，P1 `T10.ah-honly` r1 PASS：

- H-only N 4 帧 S_ss=**6,196,749.5**（G0 +0.859%）；L 4 帧 **5,834,940**（G0 +7.113%）；
- 4/4 帧 A1U1 header/CRC/长度/末字节与 baseline 逐字节相同；adapter 12/12；
- 候选：`a1_deflate_core.v` `8acd20b2…b17b`、`a1_frame_top.v` `4afc26e2…e30a`；
- manifest-r1 `f752ae09…`；报告 `test-reports/T10.ah-honly-r1-integrated.md`；
- A 未实现，`T10.ah-a-plus-h` = optional_not_run；
- 0 TD/板卡/网络；N 余量仅 +0.859%，TD/STA 未做，是当前最大风险。

## 两条并行线

### Line A：A+H 可选原型（离线仿真，不碰 TD）

- 在 H-only r1 候选的独立副本上加 **A**：2-position literal 扫描 + 双符号 packer（A+H 精确定义以 `20261026-143924.../T10.ss-g0-prod-coregap` 的 `coregap-model/verdict` 为准）。
- 目标：N/L 4 帧 S_ss ≤6.25M，且相对 H-only 提供更多 margin（A+H 模型 6,008,078 / +4.03%，但 45.034% 包络，不是保证）；A1U1/zlib 输出逐字节不变；adapter 定向测试；无 stall/timeout。
- 只做 ModelSim RTL/仿真；**0 TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK/网络**；不改 H-only r1 候选/报告；新开发/新 tester。
- 若 A 破坏逐字节等价、或 N/L 4 帧没有 ≤6.25M、或增益 <100k cycles，按 kill/partial 返回，不硬凑。
- 预算：N 探针 ≤1,200 s + N/L 4 帧各 ≤2,700 s + bench 2×300 s；总 ≤7,200 s；具体由规划冻结。

### Line B：H-only TD/STA（只做 TD/STA，不改 RTL）

- 用 H-only r1 的冻结候选中做 TD 综合/PnR/STA（187.5 MHz；必要时报告 209.6 MHz fallback），检查 WNS/hold/资源/CDC/关键路径（frame_top 双 CRC32 链、core replay 锥）。
- **不改 RTL**；不改 H-only r1 候选/报告；不 bitgen、不 CWC、不下载、不 Flash、不上板；只输出 TD/STA/资源报告与是否具备下一阶段资格。
- TD 是独占资源：先确认 `20261026-2138_fpga-integrated-delivery` 不在用 TD/板卡；若在用，Line B 等待，不抢、不并行开第二个 TD 会话。不得与 Line A 共享 TD/盘符/工作库。
- 新权威 FPGA 仓：`D:\fpga\repos\ph1p100-pcie-ep-fpga`（`main`），但 H-only diff 尚未迁移；Line B 应明确 repo binding：优先用冻结旧候选的隔离 TD 工程，或先做 diff 映射到新仓本地副本；**不得 commit/push/更新 main**，除非用户明确授权。
- 预算：1 次综合 + 1–2 次布线、≤180 min、TD 会话按串行租约；具体由规划冻结。

## 并行不互相影响的条件

1. Line A 只写自己的 run 任务目录 + `%TEMP%/opencode/ah-a/**`；Line B 只写自己的 run 任务目录 + TD 工程目录；两者不共享源、work 库、日志、TD 工程、盘符。
2. Line A 不用 TD；Line B 不改 RTL。二者只读 H-only r1 候选/manifest。
3. TD 独占：Line B 在 integrated delivery 不使用 TD 时才能开；若冲突，Line B 等待，Line A 可继续仿真。
4. 不碰 b18/b19/b20、`20261026-2138_fpga-integrated-delivery`、`20261026-144617_fpga-chain-detail-review`、旧 P1–P4、生产源、tasks.json、docs/work/.agents。
5. 每任务新开发/新 tester，不复用；主只传输。
6. 不批量删除；不新增外部/队友消息授权；不改全局配置。
7. Line A 的 A+H 不得写成已闭合/feasible；Line B 的 TD/STA 不得写成 bitgen/板级通过。N 余量 +0.859% 薄，任何“G0 已闭”必须等 TD/STA+后续授权。

## 关键输入路径

- H-only r1 报告：`workflow/runs/20261026-231711_fpga-a-plus-h-prototype/test-reports/T10.ah-honly-r1-integrated.md`
- H-only r1 manifest：`.../T10.ah-honly/r1/manifest-r1.json`（`f752ae09…`）
- H-only r0 候选/TB：`.../T10.ah-honly/r0/changed-src/{a1_deflate_core.v,a1_frame_top.v}`、`.../r0/sim/`
- A+H 定义：`workflow/runs/20261026-143924_fpga-1080p30-g0-production/T10.ss-g0-prod-coregap/r0/{out/coregap-model.json,out/coregap-verdict.json,manifest-r1.json}`
- P1 自然内容：`workflow/runs/20261026-143924_fpga-1080p30-g0-production/T10.ss-g0-prod-content/r0/content/raw40_{n,l}.hex`
- P4 总判定：`.../T10.ss-g0-prod-verdict/r0/g0-production-verdict.json`
- b11 基线/TB：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read/r0/...`
- 新权威仓（只读/不 push）：`D:\fpga\repos\ph1p100-pcie-ep-fpga`
- integrated delivery（只读，不碰）：`workflow/runs/20261026-2138_fpga-integrated-delivery/**`

## 输出目录

`D:/fpga/ph1p100/workflow/runs/20261027-055621_fpga-honly-td-and-ah`

## 期望

由规划角色按项目有界规则理解并拆分两条独立线；两条线各自新开发/新测试者，Line A 只离线仿真，Line B 只 TD/STA，TD 串行租约；先各派一个包，不要预 spawn 多个。主只原样转发，不解释技术需求。
