# 局部检查与5.1适用项

工作目录为项目根。实际执行build_baseline.py：首次restore-check在长路径mkdir失败，退出1，归档/bundle未损；修正采用既存原归档+新restore-check-v2扩展路径，第二次退出0，baseline-run-02.log有3107项恢复SHA成功标记。git bundle verify退出0、日志非空。原002820 input_manifest 220项全部匹配，另外8项回退依赖也恢复核验。未动原工程。

inventory.ps1退出0，READ_ONLY_CLI_PROBE_OK，11项注册、版本6.2.3.210850/Tcl8.6.17，映射撤销；USB/串口查询只读。

build_package.py仅生成本run合同/固定输入/合成数据，不写RTL/driver。contract/check_contract.py的实际执行结果保存evidence/contract-check.log与contract-check-result.json；只验证合同公式与合成协议向量，不代表DUT测试。最终输入保护校验与候选哈希由freeze_candidate.py保存。

5.1：①冻结本包实际文档/脚本/上游输入/合成向量及SHA，构建约束/IP在固定peer tree；②旧bit4及+16/CRC/长度/坏帧负例可执行；③仅TD只读probe，本包无构建产物要求，明确exit+marker+非空日志；④G2不适用（无生产RTL改动）；⑤未生成含ChipWatcher新候选，CWC校验本包不适用，旧配对只备份不重验；⑥三个独立审阅由主后续派发，当前未完成；⑦唯一旧回退入口与未测边界见restore.md，本包无新bit；⑧本包无提交/发布授权动作，未同步私有GitHub。此处不虚填三测试PASS或板测。
