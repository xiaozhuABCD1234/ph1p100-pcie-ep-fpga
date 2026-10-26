# lessons-learned.md — T11.rk-align-raw（只记可复用根因/触发/修正/验证入口）

## L1. 测试台的「阻塞赋值 + 自增」把读从机地址每次多跳 32B（T11 e2e 首轮 FAIL 的根因）

* **现象**：`tb_t11_r10f_e2e` 的 E1 失败且 host 内容错位 —— 帧头 0..31 正确、
  32..47 为 0、48..51 却是 DDR 0x2050 的 CRC 字节；TLP 计数/ARM/held 判定全乱。
* **根因**：TB 的假 AXI 读从机里
  `rd_beat = rd_beat + 1; rd_data <= ddr_beat(base + rd_beat*32 + 32);`
  —— `rd_beat` 是**阻塞**赋值，下一行的表达式用的是**自增后**的值，等价于
  「一次跳两拍」（+64B）。数据流因此从第 2 拍起整体错位（DDR 本身无错）。
* **修正**：先算 `rd_data/rd_last`（用旧值）再自增；并在注释里写明顺序要求。
* **验证入口**：`raw/g1/msim/p2_e2e_v6`（修后 ALL PASS）；
  错位期的证据留在 `raw/g1/msim/p2_e2e_v2..v5`（含 RDDBG/POPDBG/WRDBG 抓帧记录）。
* **复用建议**：任何「计数器 + 阻塞赋值 + 非阻塞装载」混用的读从机/激励发生器，
  先写 3 条打印（地址序列、FIFO 写指针、pop 数据首字节）再怀疑 DUT。

## L2. ARM 的前置条件与「只 claim ARM 之后新发布帧」是同一条语义（e2e 相位顺序）

* **现象**：e2e 首版「先 ARM → 出帧 → 发送」被拒（err=5/6、0 TLP）。
* **根因**：T07 冻结语义里，ARM 校验要求 **DDR 源已有发布过的完整帧**（防呆），
  而 claim 只认「ARM 之后新发布」的帧 —— 所以正确序是
  **先出帧（热身，允许被 pass 释放）→ ARM → 下一帧发布 → claim 发送**。
  首次 ARM 在任何发布之前被拒是设计行为，不是缺陷。
* **修正**：e2e 增加 E0 热身相位（同时验证「未 ARM 0 TLP + E_NOT_ARM + 该块 release」）
  并逐相位复位监视计数（`tlp_idx/db_cnt/db_exp`）。
* **验证入口**：`raw/g1/msim/p2_e2e_v6` 的 E0/E1；T07 原 TB 的 PHASE3 是同一语义。

## L3. release 是 **toggle**：测试台只数上升沿会漏掉第 2 次释放

* **现象**：E2/E3 的「ACK 后该块被释放」检查失败，但 DUT 行为正确。
* **根因**：`rel_tgl*` 每来一次事件翻转一次（0→1→0→1）。TB 的边沿计数器只数 0→1，
  同一块的第 2 次释放（1→0）被漏计。
* **修正**：把计数器改成**双边沿**（`rel !== prev` 即计数）。
* **验证入口**：`raw/g1/msim/p2_e2e_v6` E1..E4 的 RELDBG 显示与期望一致；
  写者的 protect 释放是 3FF + 边沿检测（两边沿都生效），与 TB 口径无关。

## L4. `flags` 语义：ROI 帧要置 CROPPED(bit1)，与合同 1080p 样例一致

* **根因/触发**：T03 冻结合同的 1080p 样例 `r10f-1080p-synthetic.dma` 里
  `flags=2`（roi=(960,540)），而写者 RTL 原先恒写 0（小几何样例 flags=0 恰好一致，
  所以只跑小几何不会暴露）。
* **修正**：写者加 `FLAGS_VAL = (X0!=0 || Y0!=0) ? 2 : 0`；写者 TB 的 1080p 头表/CRC
  同步更新（EXP_HDRCRC3 0x8523C000 → **0x56BA381A**）。
* **验证入口**：`raw/g1/msim/p1_writer_v4`（P10 头字节 + CRC 复算；v3 为标签修正前同输入运行）、
  `tools/pcie_integration/r10f_strict.py`（flags 只放行 0/2，拒 1/4/8）。

## L5. T07 交下来的 RK 侧 R10F 解析是**草案布局**（magic "R0FR"、字段错位），必须增量修

* **根因**：T07 只在离线生成脚本上校验了合同（后端范围不含 RK 端解析语义核对），
  `rka1.rs::r10f` 的字段表是早期草案；冻结合同/写者 RTL 用的是另一套偏移。
  由于 T07 的 RK 侧 never compiled/run，这个错位没被任何测试暴露。
* **修正**：T11 增量补丁按合同逐字段修正 + 新增 `r10f_check` CLI + `frame_grab` 发布前
  严格解析；用 `tools/pcie_integration/r10f_tools_consistency.py` 做 Rust↔Python 静态
  交叉核对（25/25 一致），补丁对 T07 干净基线 `git apply --check` 通过。
* **验证入口**：`raw/patches/apply-check-stat.txt`、`raw/g1/r10f_tool_consistency.json`、
  `raw/rk-change-list.md` §0 对照表。
* **复用建议**：跨语言/跨机器的解析器，至少保留一份「同一合同的两个独立实现 + 静态
  字段表交叉核对」，不把「能编译/能 apply」当成语义正确。

## L6. 1080p 长度边界要分清「谁在证明哪一段」

* 写者侧：81,024 拍（2,592,768B/32B）+ 1 笔 CRC 重写、633+1 个 4KiB 突发、尾 640B 全 0、
  3 组 CRC/头字段 —— `tb_cam_r10f_writer` P10 全量核对（含抽拍）。
* 推帧侧：20,256 笔 128B MWr + 1 笔单 DW 门铃 + 633 个 4KiB DDR 读突发 ——
  `tb_ddr_frame_pusher_rka1` 的 BIG 相位（T11 回归复跑）。
* 两条证据分别绑定各自输入；不要在报告里用一条冒充另一条（本包报告按此口径列出）。
