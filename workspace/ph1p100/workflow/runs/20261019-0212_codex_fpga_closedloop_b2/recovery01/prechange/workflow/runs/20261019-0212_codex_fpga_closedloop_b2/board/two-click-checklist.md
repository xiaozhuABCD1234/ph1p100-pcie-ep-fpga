# 上板恢复准备（当前禁止下载本轮部分候选）

本批尚未通过联合测试台编译，也未运行生产 G2/CWC。新 bit、新 CWC 均不存在。本清单是待门槛满足后的操作模板；当前执行到这里必须停止。

1. 综合测试对本批唯一 manifest 的 G0/G1/G2 全部判定 PASS，填入真实新 bit/CWC/manifest；核对 CWC 完整 BID 物理映射覆盖与配对 bit 一致。由用户在场确认板窗口和候选身份后，仅 SRAM 下载。操作不写 Flash，不启动 PCIe/RK，不改线或电源；CLI 读回保持关闭。
2. GUI Instant Trigger 第一次保存全部 DDR 同域校验记录和 camera 源域记录原文；至少 20 秒后再次点击并保存。至少两个不同 seq 的完整帧须 words=648192、四 ok=1、err=0、32bit pass_count 推进。独立比较各域样本，不把跨域数据称原子。

内部一次 abort 的 source_injected=1、RAW bad_count 增加且该帧不发布、随后 good/不同seq恢复均须有真实证据。该注入只证明内部拒帧路径，不代表传感器电气 CRC 故障实测。几何、ROI、Bayer 相位仍待有效板证，未证不能判板闭环 PASS。

回退入口：基线 workflow/runs/20261018-1631_runA_fpga_side_readchannel/debug-fix3/candidate-manifest.json。基线 bit SHA256=bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0；CWC SHA256=8d2998b96ef1763c14a1302118235a687488297ce496692b1f6cd95d76981026。恢复前须按该 manifest 实际路径重核身份，当前未下载任何候选。

DeepSeek仅生成文字模板；Codex已纠正其将 SRAM 下载和 DDR 读回混称的建议，并保留原文在本目录。没有 worker 执行请求。
