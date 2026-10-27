# TD 与验证脚本

> **2026-10-15当前入口：** 原140836颜色G3失败，修复CWC后已读到白/红/蓝实测统计。当前使用[白平衡闭环](../../docs/RGB565白平衡闭环_2026-10-14.md)的002820候选：220项输入、GBRG相位3、R/B Q10=2400/2062、BL50；显示与下游帧裁决同延后一拍，原始统计保留原时序。G1及所选G2通过，bit/CWC与161份证据已归档，G3/G4待验。下方140836等段落为历史。

## 2026-10-16 TD CLI / IpTool 修缮批次入口（双版本 6.2.2 + 6.2.3）

结论一句话：**6.2.2 上 IpTool headless 生成未跑通（20/20 次受控尝试，边界已证实）；TD CLI 六命令 scratch 0→bit 全链跑通（含 bitgen）；6.2.3 新装的 Tcl IP flow 命令族可用、DDR1333 参数注入成功，但 generate 卡 `<comp>_adc.log` staging 前置——GUI bootstrap 为下一步（待用户）。** 完整报告 `docs/TD_CLI_IpTool修缮与验证_2026-10-16.md`；证据 `docs/evidence/ddr1333_iptool_cli_20261016.json`、`td_cli_commands_20261016.json`、`td2026_install_20261016.json`、`td2026_ipgen_20261016.json`；三维测试报告 `workflow/runs/20261016_185639_td_cli_iptool/test-reports/`。

### 本轮入口与 runner 用法

- `prepare_ddr1333_ip.py`（修缮版 SHA `2D345898…`）：DDR1333 准备；`cli_entry_status` 写实（引用证据 JSON、可 `--entry-status` 覆盖）、argv 参数化（`--comp-name/--use-value/--extra-flag/--user-mode/--gen-mode`）、全部断言保留。**未以本版实跑**（写路径限制）；历史边界不因修缮改变。
- `run_ddr1333_ipgen.py`（新增 SHA `B44E065C…`）：受控实验 runner（`new-dir/run/gui-probe/verify/variant`）；全记录（argv/cwd/pid/exit/超时/产物 SHA/窗口证据）、超时真杀进程树、`assert_exp_dir` 锁定 `_validation\ddr1333_cli_*`、无删除（保留式清理）。
- `verify_cli_e2e.py`（新增 `D59D349F…`）/ `verify_cli_e2e.tcl`（新增 `440785F3…`）：六命令端到端 harness。用法：`python tools/td/verify_cli_e2e.py init --scratch-base D:/TD/work/csi2/_validation --tag <tag>` → 逐阶段 `stage …` → `collect --out <新证据路径>`（拒绝覆盖既有证据）。默认常量指 6.2.2（`D:/downlaod`）；换版本=字节副本仅改 `TD_EXE`/`PH1_DB` 两行（6.2.3 重定向副本 SHA `F916DDA1…`）。`verify_cli.tcl` 保持只读基线（`B3269486…`）。
- 实验目录约定（每个尝试全新、`mkdir(exist_ok=False)`、绝不写既有目录）：A=`_validation\ddr1333_cli_<YYYYMMDD_HHMMSS*>`；B=`_validation\td_cli_<ts>\`；D=`_validation\td2026_<ts>\`（本轮 D 用 `td2026_20261016_214505`）。

### 6.2.3 安装位置与新锚点（并行安装；`D:\downlaod` 6.2.2 全程未动）

- 安装根 `D:\anlogic\TD_Release_2026.2`：Release_2026.2 / **6.2.3.210850** / Tcl **8.6.17** / DB_VERSION **46207**（与 6.2.2 相同）。
- 锚点：`td_commands_prompt.exe` `2629E474…`、`td.exe` `FA2A5AC6…`（同尺寸、不同构建）、`IpTool.exe` `5B0654AA…`、`bw.exe` `89501B2D…`、`ph1_100p.db` `939EC294…`、MIS Depot `Component.xml 3E854A26…` / `Dependency.tcl 51C2311F…`；license=`D:\downlaod\license\Anlogic.lic` 复制（`DC19FEE6…`，NODELOCKED 至 2027-03-31；新装缺 license 时合成报 `RUN-8008`，外层表现为 `PRJ-5303`/`PRJ-8806`，勿误判管理器缺陷）。
- 6.2.3 Tcl IP flow 用法：`create_ip -vlnv <vendor:ip:name:ver> -component_name <n> -export_path <已存在目录>` → `load_project_ips`（跨会话重开工程后必须）→ `set_property CONFIG.<param> <value> [get_ips <n>]`（顺序反 Vivado）→ `generate_target [get_ips <n>]`；set 后**复读 `<ip>/.params_<n>.txt`** 比只看 exit 可靠；`help` 只打印整表。

### 边界注意（引用本轮结论前必读）

1. **DDR1333 headless 未跑通**：`generate_target` 卡 `<export>/.IpToolIpDataBackupDir_<comp>/<comp>_adc.log`（staging 先读后写；≥8 次同因）；该文件正常由 **GUI 的 ADC check/apply** 物化，CLI 无等价入口（`read_adc/read_ip_adc=USR-8321`）→ GUI bootstrap（A=GUI 应用一次后 CLI 重试；B=全 GUI）前**不得**把生成写成"跑通"、不得冻结候选。
2. IpTool（6.2.2）自动路径三要素：`-user/-gen` 是**目录**选项（文件形态弹"…/Design.xml"类错误）、`-use_value` 才进自动模式（否则开交互窗等待）、`-app_path` 才见错误对话框；`-tcl` 与生成参数互斥；**手工编辑实例而不同步 `.m_params` 会破坏 copy 取值**（回退默认 100/800）。
3. 退出码不可单证：显式 `exit 1` 传播；加载失败/未捕获错误（含 `-help` 当脚本名、中文路径）仍 **exit 0**；判定=`exit + 显式标记 + 非空产物 + 哈希`三件套；`td_*.log` 写 cwd；`./x.tcl` 正斜杠必需。
4. 管理器：`PRJ-8806` 类间歇（本批 1/4 复现）；**`wait_run` 报错 ≠ 产物失败**（结合 `run.log`/`flow.status`/DB 判读）；`save_best_bits` 两版本均"接受无产物"（不作验收项）。
5. 双版本共存：一律**绝对路径**调用（PATH 新 bin 追加在旧后，裸名仍先中 6.2.2；历史文档中的裸名示例勿照抄）；`.al` 默认关联已切到 2026.2（双击行为变化，旧版用绝对路径/右键）；新旧 scratch bit 差 4 B（**6.2.3 = 5,223,979 B 比 6.2.2 = 5,223,983 B 少 4 B**，头部字段），确定性核对看 bit/Global CRC、不看 `.al/.db` 逐字节。
6. 工具自身会在 6.2.2 安装目录写 `bin\.setup.ini`（21 B 窗口缓存，非破坏性，已逐次记录）；测试者补算未入证据字段的 h2h 对话框 PNG SHA `30D8F93B…78FF`。安装器副作用（PATH/.al 默认关联/快捷方式）与处置见报告 §4.3。

## 2026-10-17 DDR1333 集成与 1333/1600 对比批次入口（T01.tool-E1/E2/E3）

结论一句话：**DDR1333 IP 集成完成（只换 IP 等值派生，范围外 156 项逐字节=002820）；TD 6.2.3 同工具同脚本全链对比：1333 setup 0.230ns vs 1600ctl 0.128ns（+0.102ns），均 0 违例/TNS=0，均未达 0.300ns 探索线（如实）；决策登记 M1a 裁定维持 1333 主线、1600 回退；bit 仅候选未下载；TMST-7700（6.2.3 route DRC）未决。** 完整报告 `docs/DDR1333集成与1333vs1600对比_2026-10-17.md`；证据 `docs/evidence/ddr1333_integration_20261017.json`（E1）、`docs/evidence/ddr1333_build_sta_20261017.json`（E2；=别名 `ddr1333_integration_timing_20261017.json`，同内容）；三维测试报告见 run `workflow/runs/20261017_153201_T01_ddr1333_integration/test-reports/`。

### 本轮脚本用法与目录约定

- `prepare_rgb565_ddr1333.py`（新增，`A37CB9CD…`；本批双模式实跑）：从冻结 002820 等值派生——
  `& 'C:\Program Files\Python311\python.exe' -X utf8 -B <repo>/tools/td/prepare_rgb565_ddr1333.py [--control] [--timestamp YYYYMMDD_HHMMSS]`
  默认产出 `D:\TD\work\csi2\prj\camera_rgb565_ddr1333_<ts>`（只换 64 文件 IP 闭包+日志、wrapper 更名 1 移 1 加、范围外逐字节=002820）；`--control` 产出 `camera_rgb565_ddr1600ctl_<ts>`（002820 零改动复制+冻结脚本，供同工具控制构建）；`--timestamp` 用于两类候选配对命名。断言 A1–A9 全过才写盘、`mkdir(exist_ok=False)` 绝不覆盖、拒绝 `-O`；候选内另写 `input_manifest.json`（221 项）/`ddr1333_overlay.json`/`frozen_prepare_rgb565_ddr1333.py`。断言失败即停且**无部分产物**（断言先于 mkdir），现场保留。
- `run_rgb565_ddr1333.py`（新增，`4C42E368…`；6.2.3 专用；`run_rgb565_native.py` 保持 6.2.2 冻结不动）：
  `& 'C:\Program Files\Python311\python.exe' -X utf8 -B <repo>/tools/td/run_rgb565_ddr1333.py <候选绝对路径> build|route|bitgen [--timeout N]`
  工程须直接位于 `D:/TD/work/csi2/prj`、名以 `camera_rgb565_` 开头；执行前全量核对 `input_manifest.json`（221 项）；`native_<stage>.json/.txt` 不覆盖（失败现场保留）；命令=[6.2.3 CLI 绝对路径, `./<stage>.tcl`]、cwd=工程；成功判定=exit0+大写完成标记+非空产物+SHA（三件套）；超时真杀进程树；route 阶段另抽 SWNS/STNS/HWNS/HTNS/Period；bitgen 阶段 fail-closed（STA 非负/TNS=0/4 条 `set_path_skew`/abnormal=0），**永不下硬件**。0.300 gate 用 `tools/td/check_timing_margin.py <capture_timing.rpt> --min-setup-ns 0.3 --expected-endpoint-groups <人工复核显式值>` 单独评定（`execution_ok` 与 `timing_signoff` 分层，见报告 §3/§5）。
- **实验目录约定**：候选只新建于 `D:\TD\work\csi2\prj\camera_rgb565_{ddr1333,ddr1600ctl}_<ts>\`；测试/复核工作目录在 `D:\TD\work\csi2\_validation\*\`；证据 JSON 落 `docs/evidence/`；大 DB/bit 留 D 盘候选内（仓库只存 JSON 证据与报告）。
- 边界注意（引用前必读）：①本批**无板测/无下载/无 GUI**，bit（1333 `B7EF91CF…`、ctl `1447B243…`）仅为条件生成的候选，G3/G4 未测；②1333↔1600ctl 为唯一同工具同脚本公平对，6.2.2 历史行逐行标注、不混归因；③**TMST-7700**（6.2.3 route DRC 两候选各 1/4/4 条 SEVERE 约束提示；6.2.2=0；明细未生成）为未决项，不得宣称"无影响/已修复"；④0.300ns 为探索轮自定目标线（非器件保证），两候选均未达（`accepted=false`），0.300 优化列为优化窗口（决策登记 M5.5）。

## 当前白平衡候选流程

1. `prepare_rgb565_white_balance.py`验证固定基线和实际测量，输出独立英文路径、manifest、overlay及测试快照；不覆盖旧工程。旧`prepare_rgb565.py`遇到流水采样器会明确拒绝，避免把未延迟FE接到新像素上。
2. `run_white_balance.py <project>`提取实际core参数并仿真冻结算术/统计；`run_white_balance_pipeline.py <project>`逐拍验证+1周期、原始统计、帧裁决与guarded打包，含旧零级流水负控。生产尺寸补充为`run_white_balance_full_frame.py <project>`，独立记录完整960×540两帧及Python zlib CRC，不能冒充板测。
3. `run_rgb565_native.py <project> build|route|inspect|audit_hdmi|bitgen|export_debug`一次执行一个阶段。记录退出码、完成标记、产物哈希、所选DB与超时；route另核setup/hold/TNS/period，bitgen重新核最终STA与skew。所选CDC/复位和HDMI并行路径审查仍须先于bitgen完成。
4. `export_matching_display_debug.tcl`调用官方`setup_debugger`生成完整物理ERAM映射；`check_chipwatcher_readback.py <cwc> <bid>`核对可读回覆盖，不能只检查探针存在。
5. `archive_white_balance.py <project> --g1 <run> --pipeline <run> --matrix <run> --full-frame <run> --cdc-controls <run> --check-only`复核实际冻结输入、仿真、六阶段、同一DB、时序、CDC、HDMI和CWC/BID。全部通过后去掉`--check-only`，写入唯一证据目录；不上传bit/DB/完整网表，不删除旧文件。再按工作流第5.1节完成审阅、交接与Git检查点。

以上工具均不下载硬件。脚本校验使用普通Python，拒绝`-O`优化模式。早期`derive_rgb565_rtl.py`与`create_rgb565_tests.py`是历史一次性派生工具，不能用于覆盖当前已改进的正式源码/测试；当前复现以冻结快照及上述入口为准。

> **2026-10-14更新：** 用户明确确认同一215134位流后来恢复实时图，亮点仍在；按用户要求先做[RGB565整屏彩色](../../docs/RGB565完整彩色预览_方案与上板步骤_2026-10-14.md)，采集卡未到不阻塞。旧无图/灯态保留为历史，未得到新计数；不要求先完成旧四计数步骤。RGB565140836候选G1及所选G2通过、已生成bit，G3/G4未测。

## 历史：RGB565整屏彩色（2026-10-14首次交付）

`run_rgb565.py --test capture`、`--test pack`、`--test ddr`分别验证Bayer/统计、16位guarded打包、完整DDR显示链；`--test ddr --production`比较960×540载荷及1920×1080输出，帧CRC由Python zlib独立生成。`--baseline`是旧真实RGB332算法的兼容适配负对照；`--stats-early`只修改验证副本使统计提前发布；`--test ddr --address-fault`只对行为DDR注入别名，三者必须功能失败且工具错误为0。

`prepare_rgb565.py`固定215134的202项输入和bit哈希，复制新的独立英文工程，保留旧store/PLL/寄存器/约束/串行器，加入RGB56516位通路及Bayer原始统计，去除色条和灰度交替。当前140836已冻结的导出草稿含未调用的错误命令，因此实际CWC后处理使用单独的`export_matching_display_debug.tcl`及其哈希；不修改冻结RTL或输入清单。

`run_rgb565_native.py <project> build|route|inspect|audit_hdmi|bitgen|export_debug`按阶段保存原始日志和执行身份。它只执行所选阶段，**不会自动代替前置STA/CDC门禁**；bitgen前必须检查所有报告，失败时不能继续。不会连接硬件或自动下载。

完整RAW10后端的宽度修复和`run_raw10_frame_backend.py`独立保存，未验证草稿留在忽略的本地`fpga/csi2/_scratch/`，不列为可执行交付。


2026-10-13当前入口为[同负载RGB332参考色条](../../docs/RGB332偏色_同负载参考色条_2026-10-13.md)及[证据索引](../../docs/evidence/rgb332_reference_20261013.json)：215134冻结202输入，G1及所选G2通过、bit已生成，G3/G4未测。`run_rgb332_reference.py --test overlay|ddr`分别验证组合叠加和真实DDR集成；`--baseline`仅overlay，以复位/消隐黑、活动区直通stub预期功能拒绝，`--production`仅ddr，完整960×540载荷/1920×1080活动像素。`prepare_rgb332_reference.py`从冻结161550派生新工程，与runner共用`rgb332_reference_support.py`的精确接线转换。原消费者、采样、DDR协议、相机配置、PLL/SDC/ADC/串行器保持原输入；参考区绕过相机载荷，不能仅凭色条证明链路闭环。

215134综合管理器exit1/PRJ-8806，但worker完整gate结束标记、数据库和导出日志经检查后，由独立原生route恢复；没有将管理器记为成功。最终setup+0.005ns、hold+0.020ns、period+2.200ns、TNS0，4组skew、108个Q驱动与72个同步函数检查通过。route97.75%/重新导入96.39%的覆盖差异和原告警保留；82份原始归档见本轮索引，不代表全系统CDC、电气速率或长稳通过。

161550首版RGB332历史：`run_rgb332.py --test capture|display|chain|ddr_display`（选一项），capture/display支持`--baseline`旧灰度行为预期拒绝，chain/ddr_display支持`--production`，后者可用`--address-fault`拒绝字地址别名。`prepare_rgb332_probe.py`从固定222159派生，`refine_rgb332_once.tcl`仅做一次另存数据库优化。161550已收到偏色、灰度中性反馈，身份仅按上下文关联；构建身份及当时步骤保留于[首版报告](../../docs/RGB332真实彩色对照_操作与证据_2026-10-13.md)，不作为当前下载入口。

CDC执行顺序为两个`audit_display_cdc.py --fifo u_fifo|u_display_fifo` → `review_display_cdc_functions.py` → `review_display_cdc_origins.py`；错误粘滞链由`review_capture_error_cdc.py`另查。审计保留已观察单LUT映射及共享复位使用者时钟域检查；本轮仅增加精确`pixel_reset[1]`别名，仍要求两级复位及域来源。`test_display_cdc_reference.py <215134候选目录>`针对当前直接A×C/复位映射，实际有效网表通过，错误真值、错位、错误复位域三项变异被拒绝。`test_display_cdc_rgb332.py <161550候选目录>`仅针对旧独立LUT映射。二者均在独立目录操作、不改候选，不是任意网表通用测试，也不表示每种变异分别覆盖每个checker。首轮reference harness的CRLF匹配失败及修订记录保留，不能把它计为DUT故障；不能随意扩展白名单。

最新CSI帧完整性入口：`run_csi_integrity.py --test pack|packet|chain|preview`，pack/packet支持`--baseline`旧实现负对照，packet/chain/preview支持`--production`。preview串接真实`cam_preview_capture`，模型仅16源行、4输出行，production表示4800B行宽，并非完整4K帧。`run_ddr_display.py --guarded --production`验证960×540显示支路。`prepare_camera_csi_integrity.py`创建独立155843类工程；`review_capture_error_cdc.py`检查新错误粘滞同步链。详细门禁及边界见[最新记录](../../docs/CSI帧完整性_实现与验证_2026-10-12.md)。

审查返工入口：`run_csi_packet.py --legacy`确认旧包尾缺陷能被测试捕获，默认/`--production`验证包层，`--unpack`验证keep至RAW10像素。`prepare_camera_csi_checked.py`仅创建新D盘隔离工程，输出CSI覆盖与输入哈希；在ASCII目录运行TD，运行管理器报PRJ-8818时按本轮记录使用`route_csi_checked.tcl`从固定gate DB恢复，包含物理`insert_debugger`。`run_capture.py --test chain --bytes 518400 --address-fault`是生产尺寸字地址bit4别名拒绝测试，不能与`--red`混用且payload必须超过512B；常态保留原三类注错并明确排除store fence请求。各轮冻结源码及日志，详见[审查响应](../../docs/审查响应与返工_2026-10-12.md)。

本轮CSI候选审计继续使用`audit_display_cdc.py`和`review_display_cdc_functions.py`；新`review_display_cdc_origins.py <候选目录>`检查物理时钟分支、两级复位及请求应答源，输出`cdc_reset_clock_review.txt`。均为选定结构/数值函数检查，不能代替形式CDC、复位时序或MTBF证明。补充LUT映射的错误真值表/错位负对照已拒绝，日志归档于本轮索引。

相机真实帧DDR接入：`run_capture.py --test pack`、`--test chain`、`--test tap`分别检查异步打包、三帧DDR/CRC读回、与原预览RAM同拍的灰度旁接；`run_capture.py --test chain --bytes 518400`为生产图像尺寸，`--red`为无功能负对照。`prepare_camera_ddr_capture.py`固定已验证相机快照与DDR依赖，派生独立A路候选，不覆盖原相机工程；`--derive-only`只生成派生源码；`--phy-strategy TimingHigh`选择官方高力度物理时序优化，默认策略仍可复现前三轮。

在准备脚本输出的ASCII路径中运行`TD ./build.tcl`。将`inspect_camera_ddr_capture.tcl`复制到该目录后运行，导出网表和CDC对象；`audit_capture_cdc.py <候选目录>`核对六组54个Q驱动、36个同位同步级输入，并输出摘录。该脚本不独立证明LUT功能/CDC稳定性，仍要审查选中LUT函数、时钟及双向skew报告。`bitgen_camera_ddr_capture.tcl`也先复制到该目录后执行，重新检查STA、skew和异常端点，通过才生成bit；另需事先核对输入哈希/网表。所有脚本均不下载硬件、不删除旧目录。TD命令行本机不能正确处理中文脚本路径，须用上述D盘本地副本。

物理同步审计接受直接同位输入，或经数值真值表明确验证的单个本地复位AND；不遍历任意组合逻辑。最终版本有35条直接连接和1条复位AND→IMB连接，另审查两级复位来源；真值表及源位损坏负对照均拒绝。`postroute_camera_ddr_capture.tcl`仅用于已导出DB的一次独立ultra尝试，从工程根目录执行，原DB保留，另存`capture_postroute_pr.db`；本轮该尝试无改善，最终成功版本改为保留已有预览地址寄存级。inspect/bitgen可由wrapper显式设置`capture_project`、`capture_checkpoint`，默认仍使用工程根目录原DB。


DDR完整帧后端：`run_ddr_frame.py`运行边界回归，`--probe --words 16200`运行整帧逐字比较/损坏注入，`--red`为无功能负对照。`prepare_ddr_frame_probe.py`核对本板官方依赖快照并创建唯一独立D盘工程；在输出目录运行TD的`./build.tcl`，保留所有失败结果。`bitgen_ddr_frame_probe.tcl`只在该独立工程运行，重新检查最终STA，拒绝违例后再生成本地bit；没有任何硬件下载。见[DDR实施与验证](../../docs/DDR完整帧后端实施与上板验证_2026-10-11.md)。

RAW12 封存模块复现入口（不是当前主线）：

```powershell
python tools/td/run_raw12_unpack.py
& ./tools/td/build_raw12_unpack.ps1
```

首条需要本机 ModelSim 10.5b；第二条调用本机 TD 6.2.2，在 `D:/TD/work/csi2/_validation/raw12/` 创建独立运行目录，只综合解包模块。读取实际日志后再判断成功；不能将单模块综合当相机链路验收。`--red` 用无功能模块验证测试会失败。

`verify_cli.tcl` 为只读命令注册检查。

当前 RAW10 主线用 `run_raw10_sequence.py` 检查采集/显示、`run_hdmi_alignment.py` 检查包装边界，两者每次创建新证据目录；`--expect-fail` 只用于已知旧源码负对照。`run_camera_math.py --label <新label>` 检查数学（label须来自脚本白名单，不覆盖已有目录）。`build_raw10_sequence.tcl` 在D盘相机目录运行，使用时间戳run，只运行综合、route与报告，不bitgen或下载。

`run_camera_read.py` 是历史接口等价检查；DE已主动修正，不能再以旧等价性作为当前正确性标准。其他含 `camera` / `peer` 的导入、补丁、同步、文档更新、RAM实验脚本是此前迁移的固定步骤记录，保留追溯；含固定路径、源哈希或运行名，不能当作日常更新入口反复执行。当前主线不运行旧 `update_peer_docs.py` 或以其历史内容覆盖最新决定。

源码仍保存在仓库和授权D盘工程两处。新模块同步时先比较哈希，拒绝覆盖有独立修改的D盘文件；不自动reset工程或清理目录。完整模式与整机构建入口将在后续接入步骤补齐。

## RAW10 891 Mbps稳定档位回归

从仓库根目录用本机Python执行，生产RTL读取D盘活动工程：

```powershell
& 'C:\Program Files\Python311\python.exe' -X utf8 tools/td/run_raw10_stable.py config
& 'C:\Program Files\Python311\python.exe' -X utf8 tools/td/run_raw10_stable.py vtc
& 'C:\Program Files\Python311\python.exe' -X utf8 tools/td/run_raw10_stable.py startup
& 'C:\Program Files\Python311\python.exe' -X utf8 tools/td/run_raw10_stable.py lane_reset
```

config包含生产100kHz及错误注入，使用真实ui_i2c和引脚级传感器模型；lane_reset使用器件复位桩。负对照需`config --legacy-config --legacy-controller <归档ui_cfg_imx415.v绝对路径> --expect-fail`，仅在临时副本调整旧声明/测试参数。

2026-10-11主线已切到1080p60显示：`run_hdmi_native_stream.py --production`直接检查生产PH1P DDRX5分支；`lane_reset`检查像素域复位释放。旧`vtc`时钟测试保留30Hz档位历史，不作为当前60Hz验收证据。新时钟参数用`check_raw10_pll.py --clock-top fpga/csi2/prj/camera_peer/uisrc/01_rtl/raw10_display60_clocks.v --profile display60`审计。生成IP保持原样。

当前整机构建入口改用`build_raw10_display60.tcl`，复制到D盘相机工程后从该目录执行，创建唯一run并报告STA，不bitgen/下载。`bitgen_raw10_display60_20261011.tcl`只对应已归档`phy_display60_20261011_174231`，不能用于后续新run。详见[真实相机60Hz步骤与证据](../../docs/RAW10相机1080p60接回与DDR下一步_2026-10-11.md)。

将`build_raw10_stable.tcl`复制到D盘相机工程`_evidence`，切换到该工程后运行`td_commands_prompt.exe ./_evidence/build_raw10_stable.tcl`。脚本新建唯一run并停止于route/STA，不删除旧run、不生成bit、不下载；CLI返回0之后仍需读timing/ignored/abnormal和资源报告。正式结果见[稳定档位报告](../../docs/RAW10稳定档位实施与验证_2026-10-10.md)。

## DDR取数显示（2026-10-12）

从仓库根运行：

```powershell
& 'C:/Program Files/Python311/python.exe' -X utf8 tools/td/run_ddr_display.py --red
& 'C:/Program Files/Python311/python.exe' -X utf8 tools/td/run_ddr_display.py
& 'C:/Program Files/Python311/python.exe' -X utf8 tools/td/run_ddr_display.py --production
& 'C:/Program Files/Python311/python.exe' -X utf8 tools/td/run_ddr_display.py --production --address-fault
& 'C:/Program Files/Python311/python.exe' -X utf8 tools/td/prepare_camera_ddr_display.py
```

仿真冻结RTL/TB到ASCII结果路径并保存`inputs.json`。小尺寸覆盖重复/消隐换帧、活动期写新帧、断流黑帧恢复、footer/数据损坏、footer/DATA错误RLAST、reset/ready丢失及START活动期迟到。生产960×540仅检查正向缩放/CRC，消隐是紧凑测试配置；故障覆盖与生产VTC不可混称。

准备器复用固定依赖验证、在综合前选择`TimingHigh`，只将刚新建的capture目录重命名为display目录；旧候选不动。camera core派生接口和实际选择文件在生成目录`build.tcl`中。该策略名只是物理优化强度，CSI仍是当前软接收方案。

记下输出路径。在PowerShell将仓库位置保存在`$repoDir`，按以下顺序执行（`$candidateDir`填准备器真实输出，不能使用历史候选名复建覆盖）：

```powershell
$repoDir = (Get-Location).Path
$candidateDir = 'D:/TD/work/csi2/prj/camera_ddr_display_实际新时间戳'
Copy-Item -LiteralPath (Join-Path $repoDir 'tools/td/inspect_camera_ddr_display.tcl') -Destination (Join-Path $candidateDir 'inspect_display.tcl')
Copy-Item -LiteralPath (Join-Path $repoDir 'tools/td/bitgen_camera_ddr_display.tcl') -Destination (Join-Path $candidateDir 'bitgen_display.tcl')
Set-Location -LiteralPath $candidateDir
& 'D:/downlaod/bin/td_commands_prompt.exe' './build.tcl'
# 先读最终STA/skew/ignored/abnormal/资源及警告。
& 'D:/downlaod/bin/td_commands_prompt.exe' './inspect_display.tcl'
& 'C:/Program Files/Python311/python.exe' -X utf8 (Join-Path $repoDir 'tools/td/audit_display_cdc.py') $candidateDir --fifo u_fifo
& 'C:/Program Files/Python311/python.exe' -X utf8 (Join-Path $repoDir 'tools/td/audit_display_cdc.py') $candidateDir --fifo u_display_fifo
& 'C:/Program Files/Python311/python.exe' -X utf8 (Join-Path $repoDir 'tools/td/review_display_cdc_functions.py') $candidateDir
# 另外逐项核对input_manifest/vendor哈希、MCU ROM、复位别名/请求ACK实际时钟来源。
# 全部核验通过才执行下面的STA/skew门禁；不下载硬件。
& 'D:/downlaod/bin/td_commands_prompt.exe' './bitgen_display.tcl'
Set-Location -LiteralPath $repoDir
```

原生CLI脚本不能依赖中文路径下IP XML，所以Tcl放到准备目录且cwd必须相同。最终bit生成脚本重载具体DB并拒绝负setup/hold/period、非零TNS、缺失/违例四组skew及异常端点；输入/CDC审查仍是前置人工/原生核验，不由bitgen单独证明。

`audit_display_cdc.py`每FIFO核54 Q和36同位连接，只接受直接输入或精确单LUT复位AND；`review_display_cdc_functions.py`对72个实际同步FF解码数值真值表及数据选择，要求同位数据AND本地复位。后者不代替复位源、时钟、skew审查；未经识别的新映射应拒绝后读网表，不放宽成任意逻辑锥。错误源位与LUT真值表副本负对照均已实际拒绝。

结果：[实现与验证](../../docs/相机DDR显示闭环_实现与验证_2026-10-12.md)、[证据索引](../../docs/evidence/camera_ddr_display_20261012.json)、[上板操作](../../docs/相机DDR显示闭环_操作与预期_2026-10-12.md)。003550候选尚未上板，绿色闪点未宣称修复。

地址敏感图案纳入高位偏移量，避免原256字节周期斜坡掩盖512字节地址别名。`--production --address-fault`只在行为内存模型清字地址bit4并保留footer，必须出现FAIL；这是测试负对照，未修改生产RTL。旧图案实际漏检、新图案在x=1024/y=0实际检出，日志一并保留。

## HDMI同程序负载保留对照（2026-10-13）

`run_gray_pattern_probe.py --baseline`运行缺少模式选择的寄存直通负对照，必须在计数/切换检查失败；不接受编译失败。无参数版本检查诊断模块的寄存对齐、切换、复位和默认480帧计数。两者都创建独立ModelSim证据目录，不下载硬件。

`prepare_hdmi_loaded_probe.py`固定222159的bit与184项输入哈希，复制到新的英文目录，仅叠加HDMI前端自动切换与ROM路径迁移，输出冻结的188项输入清单。先在输出目录运行`build_probe.tcl`综合，再运行`route_probe.tcl`进行原生物理流程；不能以综合的预估时序作为最终门禁。后续沿用显示路径的网表导出、两个FIFO的CDC/真值表/复位时钟来源检查、错误CDC检查及STA/skew门禁bitgen；还需记录HDMI PAD并行输入路径。

该诊断保持1080p60，不修改PLL或输出标准。当前742.5MHz与芯片手册速率资格冲突仍未消除；图案干净也不能宣布稳定通过。具体操作和判据见[同程序对照说明](../../docs/HDMI同程序负载保留对照_操作与证据_2026-10-13.md)。
