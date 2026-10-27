# T07.rk-align-backend：匹配PCIe后端、checked CSI和安全DMA候选

batch_size=1；round0；你是本包唯一新开发，不派生代理。读fpga-dev与fpga-design-guide技能、根AGENTS、request/user-feedback-01、原指南/计划、contract/registers.json、compatibility/rk-required-changes、artifacts/next-backend-input与backend-input-files.json。首包三维已PASS，身份见closeout-T03-r0；固定 references 与备份只读。

## 目的与本包边界

形成实际可构建的独立FPGA组合后端：采用peer精确版PCIe/IP/AXI DDR后端，接本方checked CSI完整性链，补one-shot/ACK容量授权、DMA对齐/范围与TX包完整性，交付可最终STA的bit及针对RK的匹配补丁。原PAXI/预览/002820工程不动。首个后端可以显式使用合成固定数据或旧Bayer8诊断源；正式RAW10成帧/CRC与1080p ROI在下一T11包实现，不把Bayer8叫RAW10、也不把合成帧叫真实相机帧。

本包G0局部/G1/G2必须；G3/G4/G5留给单独实际板验/集成包，不是免除后续硬件门槛。不能以没有RK连接当本包源代码和G2不推进的理由。

## 实际写入范围与工具

- 新源码与来源记录：PROJECT_ROOT/fpga/csi2/pcie_integration/（先确认不存在或记录本run归属）。将references/peer-fpga-2a4b253复制到该新目录，源blob/归档SHA及逐文件local diff记录完整，不能checkout/reset用户主线或另一工作树。
- 新runner/检查工具：PROJECT_ROOT/tools/pcie_integration/；新实现工程与数据库、日志、文档、RK隔离补丁树：OUTPUT_DIR/backend/。测试仅写OUTPUT_DIR/test-reports及各自独立证据目录。
- 备份/首包candidate-manifest、references/contract/artifacts/evidence及既有lessons只读；本包使用backend/candidate-manifest.json、backend/dev-result.json、backend/lessons-learned.md，不覆盖首包冻结文件。规划/传输控制文件不能由开发代写。
- TD绝对入口`D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe`，6.2.3；CLI IP Tool已可用，复用匹配生成IP优先。外部D盘只读。中文路径可新建未占用subst指向backend/candidate，真实写入须仍在项目根；记录映射与只撤销自建映射。
- 原规划已核实`Get-Command vsim,vlog`定位`D:/intelFPGA/18.1/modelsim_ase/win32aloem/{vsim,vlog}.exe`；现有run_csi_integrity/run_capture/run_ddr_frame均用该目录。先用该真实入口在backend/sim-smoke新建小TB并验证编译/执行/完成标记，失败记录原输出后交规划，不继续盲试Verilator，不自动安装/扩权。

## 必须实现

1. 匹配IP/约束/engine接入：从冻结peer源的create_project.tcl审查并导出自己的分阶段create/syn/phy/inspect/bit脚本，消除所有会写参考库/D盘的输出路径。所有引用IP和厂商加密源都含SHA；顶层PH1P100SBG484/-3与板引脚一致。不得执行原download_sram.tcl或reset/clean旧工程。允许新工程自身run复建但保留每轮失败证据，不批量删除。
2. checked CSI真实替换：在peer mipi_csi2_rx_ph1p中接本方csi_rx_packet_integrity + csi_rx_10bit_unpack_checked，保持PHY/word align/gearbox握手；输出keep→unpack、40bit四像素、FE/good/abort与error/WC/line诊断实际接顶层。旧Bayer8 writer仅诊断；新增good/abort应参与它的发布裁决，不能错误帧仍发布。正式几何尚未板证时可按明确参数验证合成，保留可诊断计数，不能声称本板参数已实测。
3. 安全控制：实现contract/registers.json所列0x100..11C RKA1扩展与窗口，不冲突旧0xD0..F4。默认cap/session/armed0，CTRL0x61本身绝不发送。ARM_ONE_SHOT整帧锁存有效完整descriptor、源选择、DMA地址/容量/门铃/session、最多完成1帧；busy/held/draining禁新ARM与活动配置替换。ACK必须匹配held_session+held_completion_seq，释放后仍需再次ARM。错误ACK无覆盖；RESET取消pending并隔离旧源响应。
4. 地址授权：dst128B对齐、db4B对齐、非零、64bit加法无溢出、容量>=frame_bytes、db不重叠传输区、源base4KiB对齐且actual DDR容量内。不得用AXI地址位宽当容量；从IP/板DDR配置确认并在参数和manifest冻结。frame_bytes要求>0、<=MAX且整4KiB；20,256包/633突发计数要覆盖。MPS选择仍固定128B，硬核协商能力未知时禁formal ARM而不是假定。32/64地址的3DW/4DW选择按PCIe规则与实际TL形式核验，不能把peer不确定注释当规范。
5. buffer/源所有权：源descriptor在发送期间不被writer覆盖；实现明确锁定/释放/CDC握手，或在可证明的one-shot捕获停止点保持immutable complete源。必须模拟多帧生产+TL长stall，禁止靠“通常1ms内推完”“两个缓冲够用”替代证明。可以先限定一个被锁住的diagnostic源，未获得锁定能力的真实camera源不得formal ARM；记录后续RAW接入入口。
6. 包完整性/取消：packet内wait持稳，已accepted SOP的TLP不能超时截断或让CPL插入；CANCEL发生在开放包时完成该包后不发成功doorbell并排空/隔离source，允许bounded error状态一直保持直到真实源/链恢复，不能伪报idle释放缓冲；ERROR/timeout不增加成功序号。帧完成数据后独立单DW门铃无RO。reset期间默认禁止新发；链路丢失与host unload的禁止busmaster边界交RK生命周期说明。
7. RK补丁：在backend/rk-driver-src新树从固定a0215c5生成精确diff patch，不写peer仓库、不安装RK。至少宏CTRL0x61/bit8、BAR窗口>=0x120、host hdr_bytes128保留16B ABI、single slot拒非法参数、安全session/容量配置、extension检测失败关闭、默认不自动ARM、受锁保护one-shot/ACK/CANCEL辅助、生命周期等与本包RTL一致。若需要下一RAW包才能完成R10F解析，清楚分离本包diagnostic命令与正式consumer；绝不默认用旧frame_grab将诊断字节当合法R10F发布。可提供安全PCIT/固定块consumer，正式解析后续补。必须patch apply --check（对精确clean snapshot的新副本），ioctl结构/号不变，Rust用户态可编译则编译，否则准确记录RK/kernel依赖，不能阻塞FPGA构建。

## 局部检查与冻结产物

保留并运行适用peer BAR/pusher/arb/writer TB，通过ModelSim可替换iverilog命令；测试要真正实例化修改RTL。补独立TL monitor/oracle：F0/FF/F8 DW-valid、头/端序/BE/128B/MPS/4KiB/32&64地址、门铃顺序，随机/连续wait，每包第0..4拍stall，包内timeout/CANCEL/CPL仲裁，短容量/非法源/0/越界/地址进位、旧+16/旧CTRL0x71拒绝、one-shot held/错误ACK/匹配ACK/慢消费、多帧生产覆盖、复位旧会话。正负测试不得只调用生产相同helper作为oracle。

checked CSI用真实modified wrapper和packet integrity/unpack DUT跑CRC/ECC/WC/短行/FE排尽/abort/恢复，保证坏帧无source complete。PCIT/TLP oracle按实际内容复用parallel/pcie，纳入manifest；fixture只证明源数据，不能代替sender DUT。

最终G2同一实现DB要求setup>=0、hold>=0、TNS0，实际时钟/引脚/约束覆盖、所有本次跨域/复位审阅、资源<=器件。指定真实绝对路径DB/report/bit/SHA。若CWC在候选中则完整ERAM/BID+配对bit检查；不含CWC可明确N/A，板测需有足够UART/BAR诊断。TD退出码+完成标记+非空产物三者齐全。计时/吞吐只是设计预算，未板测不当实测。

产出backend/change-report.md、source-provenance.json、build-entry.md、actual-commands.json、g1/g2证据、rk-change-list+patch/apply-check、hardware-ready.md（唯一bit及回退/已知限制）、完整candidate-manifest与dev-result、lessons。先停止所有候选写入/构建再ready_for_test；manifest含实际全部生产输入、IP/约束/参数/scripts与最终DB/报告/bit，测试证据目录不纳入候选。

## 三维验收与停止

functional：真实RTL TB/独立TLP scoreboard的上述安全/接口/反压/坏帧条件全部满足，完整1080p长度边界至少一例；G1必需。engineering：独立复核同manifest最终DB/STA/约束/CDC/资源与bit，G2必需，无工具/最终STA不能PASS。system：顶层真实接入、跨源ownership、RK patch兼容/失败关闭、硬件操作入口/回退与诊断边界，不宣称G3实收；纯后端包G3—5不适用已事前定。测试报告T07.rk-align-backend-r0-{dimension}.md唯一判定首行，均绑定backend/candidate-manifest.json。

若发现范围/合同疑问立即交原规划，不自行放宽。缺工具/完整IP/可实现必要条件直接blocked并留已完成产物，规划安排独立可继续包。禁止批量删除、外部工程写、Flash/发布/队友消息。开发不操作真实JTAG/下载；同G2候选后由system独占板测包执行已授权SRAM。
