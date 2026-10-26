# T03.rk-align-freeze 开发/三维测试输入

PROJECT_ROOT为本项目真实根；OUTPUT_DIR为本文件目录；batch_size=1，round0。角色技能按主派发的路径。输入先读request、user-feedback-01、input-index、fpga-design-guide、dev-plan。本文件是首包合同，不委托生产RTL实现。

## 开发产物与操作边界

1. `backup/baseline-manifest.json`、`backup/restore.md`、Git refs bundle、根目录源码/文档归档及dirty内容。记录HEAD/branch/remotes/worktree/dirty SHA并保留现有修改，不能stash/reset/clean。备份不把新backup目录递归包含自身；tracked+本轮前已有untracked按名单归档，排除凭据、环境文件、缓存/DB巨大产物，任何排除逐项写清。未跟踪上一run文件需保存，不能只备git HEAD。若打包量过大先记录文件清单/尺寸并分明确包，不删除。验证可向本run新restore-check目录解包，验证每项SHA，检查`git bundle verify`。不覆盖原文件。
2. 只读读取 D:/TD/work/csi2/prj/camera_rgb565_wb_20261015_002820 源码/约束/manifest以及实际bit/CWC，对关键回退依赖做备份/哈希、准确路径与现有验证局限。不复制所有历史数据库。Bayer工作树仅记录版本与dirty列表，不写它。
3. `references/peer-fpga-2a4b253/`与`peer-driver-a0215c5/`，从已核对Git提交 archive 生成精确快照，`references/provenance.json`逐文件SHA；不执行未审查外部脚本。记录许可缺失/厂商IP权利归属，不公开上传。用户origin/main、本地HEAD差异只记录、不同步。
4. `contract/compatibility.md`、`contract/registers.json`、`contract/rk-required-changes.md`、`contract/acceptance-vectors.json`：严格按指南，逐项源文件/行证据；必须区分host hdr_bytes=128、16B槽头和传输R10F头128。RK ARM_BITS=0x61，camera select bit8；原+16每4KiB有跨界TLP。DMA输入容量、单槽one-shot/ACK保护默认禁推、地址锁存、门铃边界合同明确。RK补丁可在本轮后续包实现，此包给明确修改位置/用户态联动。不得把仅建议称已上机。
5. `evidence/tool-inventory.json`、`evidence/hardware-access.md`：实查6.2.3二进制版本、现有CLI/IP工具成功入口，记录可用仿真器/编译器。只读查询接入FPGA相关USB/JTAG/UART设备与既有可用控制工具；不打印环境dump/凭据，不假定某COM号/某IP为RK，不重做旧IpTool失败试验，不下载硬件。本机已有CLI成功事实可引用当前日志但声明复用范围。
6. `artifacts/next-backend-input.md`：给下包实际模块/IP/约束清单、checked CSI需要真实接的端口/帧good-abort语义、构建路径/ASCII别名办法、peer测试台调用与已知风险（包内wait timeout、固定缓冲覆盖、无容量授权、source FIFO排空/旧会话）；架构遵指南，不把代码开发扩大进本包。
7. `candidate-manifest.json`（涵盖本包冻结产物/上游输入）、`dev-result.json`、lessons。停止写候选后ready_for_test；测试报告/日志不纳入冻结候选，防止并行测试自变manifest。初始备份manifest可标期间并发写入文件漂移，需单独稳定重取，不能默默忽略。

## 三维验收

- functional：独立复算2,592,000/2,592,128/2,592,768/640/20,256/633、host stride2,596,864；CTRL bit4负例、dma dst+16跨4K负例、CRC/尾填充分层、非法长度/坏帧/未知codec拒绝条件。此包只检查合同与向量的可执行一致性，不把尚不存在RTL当已通过。
- engineering：独立验证manifest/archives/bundle、抽取恢复后全量所列SHA、pinned上游版本、允许范围/dirty没有被覆盖、实际TD版本/工具入口证据。G2构建不适用：本包无生产RTL改动。
- system：交叉核对两仓接口与RK修改清单、实际源码行、版本/host偏移/ACK可兼容、回退与硬件条件准确；拒绝把peer自述及枚举设备当本轮板测。G3/G4/G5不适用此备份合同子包，正式双方G0确认依然待条件。

测试写本run/test-reports/T03.rk-align-freeze-r0-{dimension}.md，第一行唯一`### 判定：PASS`或`### 判定：FAIL`。三者读取同一candidate-manifest；输入漂移直接报告。测试者不得修生产/候选/备份文件，可在自己的证据子目录生成校验工具/恢复副本。返回仅传输合同字段。
