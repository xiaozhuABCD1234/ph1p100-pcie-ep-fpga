# T08 round0 开发交付

真实生产RAW顶层派生覆盖层已完成局部检查，等待一个独立综合测试者重新编译验收。本文件不是综合测试PASS报告。唯一待测入口为manifest-r0.json。

最终build2输入：六个正例分别覆盖正常、最后字节NACK清理/恢复、缺B并中止A半帧后的恢复、写入中全局reset、显式停止/重启、I2C接受后未回应时reset。每个场景真实顶层运行完成，独立引脚/字节oracle mismatch=0，每路至少连续三帧正确发布。另一次真实30C1角色写值变异在相同编译输入下运行完成，被独立引脚顺序断言拒绝。精确数量/时间/命令/退出码见developer-result.json、local/final-suite-result.json及每case的sim-result.json/oracle-result.json/input-binding.json。

开发执行两次完整编译，Errors0。build1阶段的原始失败日志和checker纠正证据全部保留；ModelSim反斜杠路径启动失败未进入设计。build2新增pending-I2C reset用例后，按最终相同TB/RTL哈希重新运行全部必须场景，未沿用旧输入PASS。实际命令、工作目录和PID/超时记录在compile-result.json及sim-result.json；不从exit0单独判通过。

仅两份冻结生产文件有overlay差异：top接入和ui_cfg启用分支。新增两个可综合模块为独占真实I2C适配器及整帧门控；真实sync/CSI/unpack/writer/arbiter源码未改。source-to-overlay.json和diffs给出全部来源和逐行差异。static-audit.json、README.md记录默认关闭行为、50MHz/24ms=1200000拍、生产/小几何、地址单位、CRC和CDC/reset结构。protected-input-audit.json对规划108份冻结输入重新检查，漂移0。

模型边界：仅厂商PLL/PCIe/DDR和MIPI物理层为明确环境模型；真实I2C引脚事务、checked包层、解包、两路writer和仲裁器均未stub。DDR按AW/W/B接受握手存储并施加背压。传感器模型只ACK/NACK和解码引脚，不证明曝光/电气，数据源从既有包层仿真边界送入。告警完整保留在warning-audit.txt并在README.md逐类解释；无未说明的位宽或时钟告警。

G2本包not_run，G3/G4/G5按冻结规划不适用。生产迁入、完整STA/CDC/资源、真实曝光同步/硬件恢复/长稳/吞吐均未验证，父硬件T08不得置done。TD/板卡/Flash/共享盘符/其他会话进程/生产树写入/删除操作为0。回退为保留本目录和失败日志，生产候选原样。

综合测试者应在其允许写域建立独占工作库，按README运行CASE0—5及--mutate反例；使用相同manifest文件，前后SHA检查，再给出functional/engineering/system和G层判定。所有仿真命令已结束，最终冻结后开发不再修改或执行命令。
